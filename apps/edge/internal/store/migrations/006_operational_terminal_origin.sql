-- Fixture-only immutable issuer registration. A PRINT envelope never enrolls
-- an origin. The local signed-grant method is deliberately absent from RPC and
-- normal startup. Schema 6 is not readable by older binaries; no downgrade is
-- offered even when the isolated proof has not been activated.
CREATE TABLE op_terminal_origin (
 terminal_id TEXT PRIMARY KEY REFERENCES terminal(id),
 purpose TEXT NOT NULL CHECK(purpose='vynic-edge-operational-proof-origin'),
 mode TEXT NOT NULL CHECK(mode='ISOLATED_PROOF'),
 grant_id TEXT NOT NULL UNIQUE,
 venue_id TEXT NOT NULL,
 installation_id TEXT NOT NULL REFERENCES installation(id),
 authority_epoch INTEGER NOT NULL CHECK(typeof(authority_epoch)='integer' AND authority_epoch>0),
 origin_installation_id TEXT NOT NULL,
 client_ca_hash BLOB NOT NULL CHECK(length(client_ca_hash)=32),
 authority_grant_hash BLOB NOT NULL CHECK(length(authority_grant_hash)=32),
 signer_hash BLOB NOT NULL CHECK(length(signer_hash)=32),
 grant_hash BLOB NOT NULL UNIQUE CHECK(length(grant_hash)=32),
 grant BLOB NOT NULL CHECK(length(grant)>0 AND length(grant)<=8192)
);
CREATE TRIGGER op_terminal_origin_update BEFORE UPDATE ON op_terminal_origin
BEGIN SELECT RAISE(ABORT,'proof terminal origin cannot change'); END;
CREATE TRIGGER op_terminal_origin_delete BEFORE DELETE ON op_terminal_origin
BEGIN SELECT RAISE(ABORT,'proof terminal origin must be retained'); END;
