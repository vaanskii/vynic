"""Validate the additive SQLite migration only; this does not execute Go APIs."""
import base64
import json
import pathlib
import sqlite3
import uuid


ROOT = pathlib.Path(__file__).parent / "source/apps/edge/internal/store/migrations"
MIGRATIONS = sorted(ROOT.glob("*.sql"))
CHECKS = []


def database(version=3):
    conn = sqlite3.connect(":memory:", isolation_level=None)
    conn.execute("PRAGMA foreign_keys=ON")
    for migration in MIGRATIONS[:version]:
        conn.executescript(migration.read_text())
    return conn


def fixture(conn, sequence=0, authority=True):
    # These intentionally synthetic SQL records do not exercise grant admission.
    conn.execute("INSERT INTO installation(singleton,id,public_key,private_key,venue_id,certificate,tls_key,binding_grant,created_at) VALUES(1,?,?,?,?,?,?,?,?)", ("fixture-installation", "fixture-public", b"private", "fixture-venue", b"cert", b"tls", "foundation", 1))
    conn.execute("INSERT INTO terminal VALUES(?,?,?,?,NULL)", ("fixture-terminal", "SQL fixture", "verifier", 1))
    if authority:
        conn.execute("INSERT INTO op_authority VALUES(1,?,?,?,?,?,?,?,?,?,?,?)", ("vynic-edge-operational-proof", "ISOLATED_PROOF", "fixture-installation", "fixture-venue", "fixture-public", 41, b"g" * 32, b"SQL-ONLY-FIXTURE", b"s" * 32, b"b" * 32, sequence))


def counts(conn):
    return tuple(conn.execute("SELECT count(*) FROM " + table).fetchone()[0] for table in ("op_entity", "op_event", "op_effect", "op_request"))


def success(conn, identity="entity", request="request", effect="effect"):
    conn.execute("BEGIN")
    conn.execute("INSERT INTO op_entity VALUES('ORDER',?,1,0,?)", (identity, b'{"complete":true}'))
    conn.execute("INSERT INTO op_event VALUES(1,41,?,'fixture-terminal',?)", (request, b"event"))
    conn.execute("INSERT INTO op_effect VALUES(?,'PRINT',?,1,0,?)", (effect, request, b"frozen print"))
    conn.execute("UPDATE op_authority SET sequence=1")
    conn.execute("INSERT INTO op_request VALUES(?,'fixture-terminal',41,?,'COMMITTED',1,?)", (request, b"h" * 32, b"exact result"))
    conn.execute("COMMIT")


fresh = database()
assert fresh.execute("SELECT count(*) FROM op_authority").fetchone()[0] == 0
assert fresh.execute("PRAGMA foreign_key_check").fetchall() == []
CHECKS.append("fresh 001/002/003 migration: no default authority; foreign keys valid")

for table in ("op_entity", "op_event", "op_effect", "op_request", "op_authority"):
    conn = database()
    fixture(conn)
    action = "UPDATE" if table == "op_authority" else "INSERT"
    conn.execute("CREATE TRIGGER failure BEFORE " + action + " ON " + table + " BEGIN SELECT RAISE(ABORT,'injected failure'); END")
    try:
        success(conn)
        raise AssertionError("false success at " + table)
    except sqlite3.IntegrityError:
        conn.execute("ROLLBACK")
    assert counts(conn) == (0, 0, 0, 0)
    assert conn.execute("SELECT sequence FROM op_authority").fetchone()[0] == 0
    conn.close()
    CHECKS.append("atomic rollback after injected " + table + " failure")

conn = database()
fixture(conn)
success(conn)
assert counts(conn) == (1, 1, 1, 1)
assert conn.execute("PRAGMA foreign_key_check").fetchall() == []
conn.execute("INSERT INTO op_request VALUES('conflict','fixture-terminal',41,?,'CONFLICT',NULL,?)", (b"c" * 32, b"exact conflict"))
assert counts(conn) == (1, 1, 1, 2)
CHECKS.append("success cyclic deferred references commit; exact conflict needs no event/effect")

for statement in (
    "UPDATE op_request SET digest=zeroblob(32)",
    "DELETE FROM op_request",
    "UPDATE op_event SET event=x'00'",
    "DELETE FROM op_event",
    "UPDATE op_effect SET payload=x'00'",
    "DELETE FROM op_effect",
    "UPDATE op_authority SET authority_epoch=42,sequence=2",
    "DELETE FROM op_authority",
    "DELETE FROM op_entity",
    "UPDATE op_entity SET revision=3",
):
    try:
        conn.execute(statement)
        raise AssertionError("immutable record changed: " + statement)
    except sqlite3.IntegrityError:
        pass
CHECKS.append("request/event/effect/grant identity immutable; revision jumps/entity deletion refused")
conn.execute("UPDATE op_entity SET revision=2,tombstone=1,document=x''")
try:
    conn.execute("UPDATE op_entity SET revision=3,tombstone=0,document=x'7b7d'")
    raise AssertionError("tombstone resurrected")
except sqlite3.IntegrityError:
    pass
CHECKS.append("tombstone identity persists and refuses resurrection")

orphan = database()
fixture(orphan)
orphan.execute("BEGIN")
orphan.execute("INSERT INTO op_event VALUES(1,41,'absent-request','fixture-terminal',x'00')")
try:
    orphan.execute("COMMIT")
    raise AssertionError("event without durable request committed")
except sqlite3.IntegrityError:
    orphan.execute("ROLLBACK")
assert counts(orphan) == (0, 0, 0, 0)
CHECKS.append("deferred commit cannot persist event without its request result")

numeric = database()
fixture(numeric, sequence=9223372036854775807)
numeric.execute("INSERT INTO op_entity VALUES('ORDER','maximum',9223372036854775807,0,x'7b7d')")
for statement in (
    "UPDATE op_authority SET sequence=sequence+1",
    "UPDATE op_entity SET revision=revision+1",
    "INSERT INTO op_entity VALUES('ORDER','negative',-1,0,x'7b7d')",
    "INSERT INTO op_entity VALUES('ORDER','real',9223372036854775808,0,x'7b7d')",
    "INSERT INTO op_entity VALUES('ORDER','deadpayload',1,1,x'7b7d')",
):
    try:
        numeric.execute(statement)
        raise AssertionError("numeric/payload boundary escaped: " + statement)
    except sqlite3.IntegrityError:
        pass
CHECKS.append("int64 sequence/revision overflow, negative revision and tombstone payload refused")

legacy = database(2)
fixture(legacy, authority=False)
legacy.execute("INSERT INTO projection VALUES(1,'shadow-order',1,0,x'7b7d')")
legacy.execute("INSERT INTO committed_event VALUES(1,x'00')")
legacy.execute("INSERT INTO request_result VALUES('shadow-request','fixture-terminal',x'00',x'00')")
legacy.execute("UPDATE coordination SET sequence=1")
old_tables = ("installation", "terminal", "coordination", "projection", "committed_event", "request_result")
before = {table: legacy.execute("SELECT * FROM " + table).fetchall() for table in old_tables}
legacy.executescript(MIGRATIONS[2].read_text())
assert before == {table: legacy.execute("SELECT * FROM " + table).fetchall() for table in old_tables}
assert legacy.execute("SELECT count(*) FROM op_authority").fetchone()[0] == 0
assert legacy.execute("PRAGMA foreign_key_check").fetchall() == []
CHECKS.append("populated v2 additive upgrade preserves all existing foundation/Phase2A rows")

raster = bytes([0xA5]) * (8 << 20)
frozen_print = json.dumps({"target": "fixture-printer-only", "raster": base64.b64encode(raster).decode()}, separators=(",", ":")).encode()
encoded_request = json.dumps({"requestId": str(uuid.uuid4()), "authorityEpoch": 41, "reads": None, "writes": [{"kind": "ORDER", "id": str(uuid.uuid4()), "expectedRevision": 0, "tombstone": False, "document": "e30="}], "effects": [{"id": str(uuid.uuid4()), "kind": "PRINT", "payload": base64.b64encode(frozen_print).decode()}], "applicationData": None}, separators=(",", ":")).encode()
assert len(frozen_print) <= 12 << 20
assert len(encoded_request) <= 16 << 20
CHECKS.append("8MiB raster fits nested frozen PrintJob/effect/request encoding bounds")

print("SQL-only validation passed:", len(CHECKS), "checks; SQLite", sqlite3.sqlite_version)
for check in CHECKS:
    print("PASS", check)
print("raster_bytes", len(raster), "frozen_print_bytes", len(frozen_print), "encoded_request_bytes", len(encoded_request))
print("Go API, concurrency, signed-grant, restart and crash tests remain unexecuted without Go tooling.")
