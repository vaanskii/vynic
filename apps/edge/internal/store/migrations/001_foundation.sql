CREATE TABLE installation (
 singleton INTEGER PRIMARY KEY CHECK (singleton=1),
 id TEXT NOT NULL UNIQUE,
 public_key TEXT NOT NULL,
 private_key BLOB NOT NULL,
 venue_id TEXT,
 certificate BLOB NOT NULL,
 tls_key BLOB NOT NULL,
 binding_grant TEXT,
 created_at INTEGER NOT NULL
);
CREATE TABLE pairing_ticket (
 verifier TEXT PRIMARY KEY,
 expires_at INTEGER NOT NULL,
 request_id TEXT UNIQUE,
 terminal_id TEXT UNIQUE,
 request_digest TEXT
);
CREATE TABLE terminal (
 id TEXT PRIMARY KEY,
 display_name TEXT NOT NULL,
 verifier TEXT NOT NULL,
 created_at INTEGER NOT NULL,
 revoked_at INTEGER
);
CREATE TABLE session (
 id TEXT PRIMARY KEY,
 terminal_id TEXT NOT NULL REFERENCES terminal(id),
 client_version TEXT NOT NULL,
 created_at INTEGER NOT NULL,
 last_seen_at INTEGER NOT NULL,
 last_boot_id TEXT NOT NULL
);
CREATE INDEX session_terminal ON session(terminal_id);
