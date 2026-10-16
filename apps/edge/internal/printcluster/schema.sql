-- Schema 2 is deliberately unreadable by the former full-projection reader.
CREATE TABLE IF NOT EXISTS printcluster_projection (
 id INTEGER PRIMARY KEY CHECK(id=1),
 schema_version INTEGER NOT NULL CHECK(schema_version=2),
 cluster_id TEXT NOT NULL CHECK(length(cluster_id)=36),
 pin_sha256 TEXT NOT NULL CHECK(length(pin_sha256)=64),
 applied_index INTEGER NOT NULL CHECK(applied_index>=0),
 state_json BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS printcluster_rows (
 kind TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL,
 sha256 TEXT NOT NULL CHECK(length(sha256)=64),
 PRIMARY KEY(kind,key)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS printcluster_payloads (
 digest TEXT PRIMARY KEY CHECK(length(digest)=64),
 length INTEGER NOT NULL CHECK(length>0),
 bytes BLOB NOT NULL CHECK(length(bytes)=length)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS printcluster_payload_refs (
 kind TEXT NOT NULL, key TEXT NOT NULL, digest TEXT NOT NULL,
 PRIMARY KEY(kind,key),
 FOREIGN KEY(kind,key) REFERENCES printcluster_rows(kind,key) ON DELETE CASCADE,
 FOREIGN KEY(digest) REFERENCES printcluster_payloads(digest)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS printcluster_payload_ref_digest ON printcluster_payload_refs(digest);
