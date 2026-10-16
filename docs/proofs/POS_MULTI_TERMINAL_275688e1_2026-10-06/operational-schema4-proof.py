#!/usr/bin/env python3
"""Execute source migrations in standalone SQLite; never claims Go/API/wire proof."""

import argparse
import datetime
import hashlib
import json
import shutil
import sqlite3
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

DEFAULT_SOURCE = Path('/tmp/vynic-readiness-20261006-a2nbcprb/source')
DEFAULT_RECEIPT = Path(__file__).with_name('operational-schema4-receipt.json')
APPLICATION_ID = 1448693321
OLD_KINDS = ['ORDER', 'TABLE', 'RESERVATION', 'PACKAGE', 'SALE', 'DAY']
NEW_KINDS = ['OPERATIONAL_CONTROL', 'AUDIT_REPORT', 'CLOSURE', 'ADVANCE', 'EXPENSE', 'STAFF', 'OPERATIONAL_POLICY']
TABLES = ['installation', 'pairing_ticket', 'terminal', 'session', 'coordination',
          'projection', 'committed_event', 'request_result', 'op_authority',
          'op_entity', 'op_request', 'op_event', 'op_effect']
SOURCE_FILES = [
    'apps/edge/internal/store/operational.go',
    'apps/edge/internal/store/operational_test.go',
    'apps/edge/internal/store/store.go',
    'apps/edge/internal/store/migrations/001_foundation.sql',
    'apps/edge/internal/store/migrations/002_orders_tables.sql',
    'apps/edge/internal/store/migrations/003_operational_coordination.sql',
    'apps/edge/internal/store/migrations/004_operational_entity_kinds.sql',
    'packages/contracts/proto/vynic/edge/v1/operational_proof.proto',
]
SOURCE = DEFAULT_SOURCE


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def migration_files():
    return sorted((SOURCE / 'apps/edge/internal/store/migrations').glob('*.sql'))


def statements(script):
    pending = ''
    for line in script.splitlines(keepends=True):
        pending += line
        if sqlite3.complete_statement(pending):
            yield pending
            pending = ''
    if any(line.strip() and not line.lstrip().startswith('--') for line in pending.splitlines()):
        raise ValueError('incomplete source SQL')


def shape(db):
    return db.execute("SELECT type,name,tbl_name,COALESCE(sql,'') FROM sqlite_master "
                      "WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name").fetchall()


def all_objects(db):
    return db.execute('SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name').fetchall()


def exact_rows(db):
    result = {}
    for table in TABLES:
        columns = [row[1] for row in db.execute('PRAGMA table_info(' + table + ')')]
        types = ','.join('typeof("' + column + '")' for column in columns)
        result[table] = db.execute('SELECT *,' + types + ' FROM ' + table + ' ORDER BY 1,2').fetchall()
    return result


def triggers(db):
    return db.execute("SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name").fetchall()


def migrate(db, target, *, verify=True, inject_after_drop=False):
    """Exercise actual SQL in one transaction and maintain source checksums.

    The Python ledger/version/shape driver models relevant Store.prepare steps;
    it does not execute that Go method or prove Go driver equivalence.
    """
    files = migration_files()
    version = db.execute('PRAGMA user_version').fetchone()[0]
    db.execute('BEGIN')
    try:
        if version == 0:
            db.execute('CREATE TABLE schema_migration(version INTEGER PRIMARY KEY, checksum TEXT NOT NULL)')
        if db.execute('SELECT count(*) FROM schema_migration').fetchone()[0] != version:
            raise ValueError('inconsistent migration ledger')
        for number, file in enumerate(files[:target], 1):
            if not file.name.startswith(f'{number:03d}_'):
                raise ValueError('noncontiguous migrations')
            checksum = digest(file)
            if number <= version:
                if db.execute('SELECT checksum FROM schema_migration WHERE version=?', (number,)).fetchone() != (checksum,):
                    raise ValueError('migration checksum mismatch')
                continue
            for statement in statements(file.read_text()):
                db.execute(statement)
                if inject_after_drop and statement.strip() == 'DROP TABLE op_entity;':
                    db.execute('SELECT injected_sqlite_migration_failure()')
            db.execute('INSERT INTO schema_migration VALUES(?,?)', (number, checksum))
        if verify:
            expected = sqlite3.connect(':memory:', isolation_level=None)
            try:
                migrate(expected, target, verify=False)
                if shape(db) != shape(expected):
                    raise ValueError('local schema differs from source migrations')
            finally:
                expected.close()
        db.execute('PRAGMA application_id=' + str(APPLICATION_ID))
        db.execute('PRAGMA user_version=' + str(target))
        if db.execute('PRAGMA foreign_key_check').fetchall():
            raise ValueError('foreign-key violation')
        db.execute('COMMIT')
    except BaseException:
        db.execute('ROLLBACK')
        raise


def populate(db):
    """Synthetic opaque SQL rows, without signing/admission or business claims."""
    installation, venue, terminal, session = (str(uuid.uuid4()) for _ in range(4))
    request1, request2, conflict = (str(uuid.uuid4()) for _ in range(3))
    db.execute('BEGIN')
    db.execute('INSERT INTO installation VALUES(?,?,?,?,?,?,?,?,?)',
               (1, installation, 'synthetic-public-key', b'\x00\xffprivate', venue,
                b'\x00certificate', b'\xfftls-key', 'synthetic-foundation-binding', 123))
    db.execute('INSERT INTO terminal VALUES(?,?,?,?,?)', (terminal, 'Fixture', 'synthetic-verifier', 123, None))
    db.execute('INSERT INTO session VALUES(?,?,?,?,?,?)', (session, terminal, 'fixture', 123, 124, 'fixture-boot'))
    db.execute('INSERT INTO pairing_ticket VALUES(?,?,?,?,?)', ('ticket', 200, str(uuid.uuid4()), str(uuid.uuid4()), 'digest'))
    db.execute('UPDATE coordination SET sequence=4')
    db.execute('INSERT INTO projection VALUES(?,?,?,?,?)', (1, str(uuid.uuid4()), 7, 0, b' {"shadow":"old"}\n'))
    db.execute('INSERT INTO projection VALUES(?,?,?,?,?)', (2, str(uuid.uuid4()), 9, 1, b''))
    db.execute('INSERT INTO committed_event VALUES(?,?)', (4, b'\x00\xfffrozen-shadow-event'))
    db.execute('INSERT INTO request_result VALUES(?,?,?,?)', (str(uuid.uuid4()), terminal, b'\x00digest', b'\xffshadow-result'))
    db.execute('INSERT INTO op_authority VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
               (1, 'vynic-edge-operational-proof', 'ISOLATED_PROOF', installation,
                venue, 'synthetic-public-key', 41, bytes(range(32)), b'fixture-grant',
                b'\x01' * 32, b'\x02' * 32, 2))
    db.execute('INSERT INTO op_request VALUES(?,?,?,?,?,?,?)',
               (request1, terminal, 41, b'\x03' * 32, 'COMMITTED', 1, b'\x00\xffexact-result-one'))
    db.execute('INSERT INTO op_request VALUES(?,?,?,?,?,?,?)',
               (request2, terminal, 41, b'\x04' * 32, 'COMMITTED', 2, b'\xfeexact-result-two'))
    db.execute('INSERT INTO op_request VALUES(?,?,?,?,?,?,?)',
               (conflict, terminal, 41, b'\x05' * 32, 'CONFLICT', None, b' {"conflict":"exact"}\n'))
    db.execute('INSERT INTO op_event VALUES(?,?,?,?,?)', (1, 41, request1, terminal, b'\x00\xffexact-event-one'))
    db.execute('INSERT INTO op_event VALUES(?,?,?,?,?)', (2, 41, request2, terminal, b'\xfeexact-event-two'))
    db.execute('INSERT INTO op_effect VALUES(?,?,?,?,?,?)',
               (str(uuid.uuid4()), 'AUDIT', request1, 1, 0, b' {"audit":"frozen"}\n'))
    db.execute('INSERT INTO op_effect VALUES(?,?,?,?,?,?)',
               (str(uuid.uuid4()), 'PRINT', request1, 1, 1, bytes(range(256))))
    for number, kind in enumerate(OLD_KINDS):
        document = (' {\n "opaque": "ქართული", "oldKind": "' + kind + '" }\n').encode()
        db.execute('INSERT INTO op_entity VALUES(?,?,?,?,?)', (kind, str(uuid.uuid4()), number + 7, 0, document))
        revision = 9223372036854775807 if number == 5 else number + 19
        db.execute('INSERT INTO op_entity VALUES(?,?,?,?,?)', (kind, str(uuid.uuid4()), revision, 1, b''))
    db.execute('COMMIT')


class Schema4Proof(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='vynic-schema4-sql-')
        self.path = Path(self.directory.name) / 'edge.db'
        self.db = sqlite3.connect(self.path, isolation_level=None)
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=FULL')

    def tearDown(self):
        self.db.close()
        self.directory.cleanup()

    def populated_v3(self):
        migrate(self.db, 3)
        populate(self.db)

    def test_01_fresh_migrations_1_to_4_without_authority(self):
        migrate(self.db, 4)
        self.assertEqual(self.db.execute('PRAGMA user_version').fetchone(), (4,))
        self.assertEqual(self.db.execute('SELECT count(*) FROM schema_migration').fetchone(), (4,))
        self.assertEqual(self.db.execute('SELECT count(*) FROM op_authority').fetchone(), (0,))
        self.assertEqual(self.db.execute('SELECT count(*) FROM op_entity').fetchone(), (0,))
        self.assertEqual(self.db.execute('SELECT name FROM sqlite_temp_master').fetchall(), [])

    def test_02_populated_v3_preserves_exact_rows_types_and_guards(self):
        self.populated_v3()
        rows, guards = exact_rows(self.db), triggers(self.db)
        ledger = self.db.execute('SELECT * FROM schema_migration ORDER BY version').fetchall()
        migrate(self.db, 4)
        self.assertEqual(exact_rows(self.db), rows)
        self.assertEqual(triggers(self.db), guards)
        self.assertEqual(len(guards), 10)
        self.assertEqual(self.db.execute('SELECT * FROM schema_migration WHERE version<=3 ORDER BY version').fetchall(), ledger)
        self.assertEqual(self.db.execute('PRAGMA integrity_check').fetchall(), [('ok',)])
        self.assertEqual(self.db.execute('PRAGMA foreign_key_check').fetchall(), [])
        self.assertEqual(self.db.execute('SELECT name FROM sqlite_temp_master').fetchall(), [])
        self.db.close()
        self.db = sqlite3.connect(self.path, isolation_level=None)
        self.db.execute('PRAGMA foreign_keys=ON')
        self.assertEqual(exact_rows(self.db), rows)
        self.assertEqual(self.db.execute('PRAGMA user_version').fetchone(), (4,))
        migrate(self.db, 4)
        self.assertEqual(exact_rows(self.db), rows)

    def test_03_new_kinds_sql_roundtrip_revision_and_retained_tombstones(self):
        migrate(self.db, 4)
        identity = str(uuid.uuid4())
        document = ' {\n "opaque": "ქართული", "field": 1 }\n'.encode()
        for kind in NEW_KINDS:
            with self.subTest(kind=kind):
                self.db.execute('INSERT INTO op_entity VALUES(?,?,?,?,?)', (kind, identity, 1, 0, document))
                self.assertEqual(self.db.execute('SELECT revision,tombstone,document FROM op_entity WHERE kind=? AND id=?', (kind, identity)).fetchone(), (1, 0, document))
                self.db.execute('UPDATE op_entity SET revision=2,document=? WHERE kind=? AND id=?', (b'{"opaque":2}', kind, identity))
                self.assertEqual(self.db.execute('SELECT revision,document FROM op_entity WHERE kind=? AND id=?', (kind, identity)).fetchone(), (2, b'{"opaque":2}'))
                self.db.execute("UPDATE op_entity SET revision=3,tombstone=1,document=x'' WHERE kind=? AND id=?", (kind, identity))
                with self.assertRaises(sqlite3.IntegrityError):
                    self.db.execute("UPDATE op_entity SET revision=4,tombstone=0,document=x'7b7d' WHERE kind=? AND id=?", (kind, identity))
                with self.assertRaises(sqlite3.IntegrityError):
                    self.db.execute('DELETE FROM op_entity WHERE kind=? AND id=?', (kind, identity))
        self.assertEqual(self.db.execute('SELECT kind,revision,tombstone,document FROM op_entity ORDER BY kind').fetchall(), [(kind, 3, 1, b'') for kind in sorted(NEW_KINDS)])

    def test_04_all_immutability_guards_still_abort_without_partial_writes(self):
        self.populated_v3()
        migrate(self.db, 4)
        before = exact_rows(self.db)
        for query in [
            'UPDATE op_authority SET sequence=sequence',
            "UPDATE op_authority SET venue_id='changed',sequence=sequence+1",
            'DELETE FROM op_authority', 'UPDATE op_entity SET revision=revision',
            "UPDATE op_entity SET kind='EXPENSE',revision=revision+1 WHERE kind='ORDER' AND tombstone=0",
            "UPDATE op_entity SET id='changed',revision=revision+1 WHERE kind='ORDER' AND tombstone=0",
            "UPDATE op_entity SET tombstone=0,document=x'7b7d',revision=revision+1 WHERE kind='ORDER' AND tombstone=1",
            'DELETE FROM op_entity', 'UPDATE op_request SET result=result',
            'DELETE FROM op_request', 'UPDATE op_event SET event=event', 'DELETE FROM op_event',
            'UPDATE op_effect SET payload=payload', 'DELETE FROM op_effect',
        ]:
            with self.subTest(query=query):
                with self.assertRaises(sqlite3.IntegrityError):
                    self.db.execute(query)
                self.assertEqual(exact_rows(self.db), before)
        self.db.execute('UPDATE op_authority SET sequence=sequence+1')
        self.db.execute("UPDATE op_entity SET revision=revision+1 WHERE kind='ORDER' AND tombstone=0")

    def test_05_v3_schema_drift_refused_atomically(self):
        self.populated_v3()
        mutations = {
            'missing-update': 'DROP TRIGGER op_entity_update',
            'missing-delete': 'DROP TRIGGER op_entity_delete',
            'altered-update': 'DROP TRIGGER op_entity_update; CREATE TRIGGER op_entity_update BEFORE UPDATE ON op_entity BEGIN SELECT 1; END;',
            'altered-delete': 'DROP TRIGGER op_entity_delete; CREATE TRIGGER op_entity_delete BEFORE DELETE ON op_entity BEGIN SELECT 1; END;',
            'extra-trigger': 'CREATE TRIGGER unexpected_entity_trigger BEFORE UPDATE ON op_entity BEGIN SELECT 1; END;',
            'extra-index': 'CREATE INDEX unexpected_entity_index ON op_entity(revision)',
            'added-column': 'ALTER TABLE op_entity ADD COLUMN unexpected TEXT',
            'altered-check': None,
            'missing-primary-key': None,
        }
        for name, mutation in mutations.items():
            with self.subTest(drift=name):
                file = Path(self.directory.name) / (name + '.db')
                db = sqlite3.connect(file, isolation_level=None)
                try:
                    self.db.backup(db)
                    db.execute('PRAGMA foreign_keys=ON')
                    if mutation:
                        db.executescript(mutation)
                    else:
                        table = db.execute("SELECT sql FROM sqlite_master WHERE name='op_entity'").fetchone()[0]
                        guards = triggers(db)
                        if name == 'altered-check':
                            table = table.replace("'SALE','DAY'", "'SALE','DAY','UNSUPPORTED'")
                        else:
                            table = table.replace(',\n PRIMARY KEY(kind,id)', '')
                        db.execute('BEGIN')
                        db.execute(table.replace('CREATE TABLE op_entity (', 'CREATE TABLE op_entity_drift ('))
                        db.execute('INSERT INTO op_entity_drift SELECT * FROM op_entity')
                        db.execute('DROP TRIGGER op_entity_update')
                        db.execute('DROP TRIGGER op_entity_delete')
                        db.execute('DROP TABLE op_entity')
                        db.execute('ALTER TABLE op_entity_drift RENAME TO op_entity')
                        for trigger, ddl in guards:
                            if trigger in ('op_entity_update', 'op_entity_delete'):
                                db.execute(ddl)
                        db.execute('COMMIT')
                    rows, objects = exact_rows(db), all_objects(db)
                    with self.assertRaisesRegex(sqlite3.IntegrityError, 'unmodified_operational_entity_v3'):
                        migrate(db, 4)
                    self.assertEqual(exact_rows(db), rows)
                    self.assertEqual(all_objects(db), objects)
                    self.assertEqual(db.execute('PRAGMA user_version').fetchone(), (3,))
                    self.assertEqual(db.execute('SELECT count(*) FROM schema_migration').fetchone(), (3,))
                    self.assertEqual(db.execute('SELECT name FROM sqlite_temp_master').fetchall(), [])
                finally:
                    db.close()

    def test_06_mid_rebuild_sql_failure_rolls_back_exact_v3(self):
        self.populated_v3()
        rows, objects = exact_rows(self.db), all_objects(self.db)
        with self.assertRaisesRegex(sqlite3.OperationalError, 'injected_sqlite_migration_failure'):
            migrate(self.db, 4, inject_after_drop=True)
        self.assertEqual(exact_rows(self.db), rows)
        self.assertEqual(all_objects(self.db), objects)
        self.assertEqual(self.db.execute('PRAGMA user_version').fetchone(), (3,))
        self.assertEqual(self.db.execute('SELECT count(*) FROM schema_migration').fetchone(), (3,))
        self.assertEqual(self.db.execute('SELECT name FROM sqlite_temp_master').fetchall(), [])

    def test_07_v4_retains_kind_and_storage_constraints(self):
        migrate(self.db, 4)
        cases = [
            ('FUTURE_KIND', 1, 0, b'{}'), ('operational_control', 1, 0, b'{}'),
            ('EXPENSE', 0, 0, b'{}'), ('EXPENSE', -1, 0, b'{}'),
            ('EXPENSE', 1.5, 0, b'{}'), ('EXPENSE', float(2 ** 63), 0, b'{}'),
            ('EXPENSE', 1, 2, b'{}'), ('EXPENSE', 1, 0, b''),
            ('EXPENSE', 1, 1, b'{}'), ('EXPENSE', 1, 0, b'a' * 1048577),
        ]
        for number, (kind, revision, tombstone, document) in enumerate(cases):
            with self.subTest(case=number):
                with self.assertRaises(sqlite3.IntegrityError):
                    self.db.execute('INSERT INTO op_entity VALUES(?,?,?,?,?)', (kind, str(uuid.uuid4()), revision, tombstone, document))
        self.assertEqual(self.db.execute('SELECT count(*) FROM op_entity').fetchone(), (0,))

    def test_08_original_v3_migration_unmodified(self):
        file = SOURCE / 'apps/edge/internal/store/migrations/003_operational_coordination.sql'
        self.assertEqual(digest(file), '47e6dcf89410b3c3eb28d9e54f50541556e722ee6d515d63242204322e3537ac')


def main():
    global SOURCE
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=DEFAULT_SOURCE)
    parser.add_argument('--receipt', type=Path, default=DEFAULT_RECEIPT)
    arguments = parser.parse_args()
    SOURCE = arguments.source.resolve()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Schema4Proof)
    result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite)
    receipt = {
        'atUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'sourceRoot': str(SOURCE),
        'scope': 'Standalone Python SQLite executes actual migrations; ledger/shape/version driver is a Python model, not Go execution.',
        'python': sys.version.split()[0], 'sqlite': sqlite3.sqlite_version,
        'success': result.wasSuccessful(), 'testsRun': result.testsRun,
        'failures': len(result.failures), 'errors': len(result.errors),
        'newKindSqlVariants': NEW_KINDS, 'schemaDriftVariants': 9,
        'go': 'UNCOMPILED; SDK absent; no acquisition, gofmt, Go tests or Go binary execution.',
        'wire': 'UNVERIFIED; canonical proto only; generated output untouched; no protoc/build/wire test.',
        'olderEdgeRollback': 'BLOCKED. SchemaVersion is 4; existing greater-version refusal retained. Old Edge binary rejection is theoretical, not executed.',
        'activation': 'None. No production registration/capability/startup change or authority created by SQL.',
        'sourceFiles': [{'path': name, 'sha256': digest(SOURCE / name), 'bytes': (SOURCE / name).stat().st_size} for name in SOURCE_FILES],
        'scriptSha256': digest(Path(__file__)),
        'goOnPath': shutil.which('go'),
    }
    arguments.receipt.parent.mkdir(parents=True, exist_ok=True)
    arguments.receipt.write_text(json.dumps(receipt, indent=2) + '\n')
    print('Receipt: ' + str(arguments.receipt))
    print('Go: ' + receipt['go'])
    print('Older Edge rollback: ' + receipt['olderEdgeRollback'])
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    raise SystemExit(main())
