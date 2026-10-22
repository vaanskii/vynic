-- ISOLATED_PROOF only. No authority is created by migration or foundation binding.
CREATE TABLE op_authority (
 singleton INTEGER PRIMARY KEY CHECK(singleton=1),
 purpose TEXT NOT NULL CHECK(purpose='vynic-edge-operational-proof'),
 mode TEXT NOT NULL CHECK(mode='ISOLATED_PROOF'),
 installation_id TEXT NOT NULL REFERENCES installation(id),
 venue_id TEXT NOT NULL,
 public_key TEXT NOT NULL,
 authority_epoch INTEGER NOT NULL CHECK(typeof(authority_epoch)='integer' AND authority_epoch>0),
 grant_hash BLOB NOT NULL CHECK(length(grant_hash)=32),
 grant BLOB NOT NULL CHECK(length(grant)>0 AND length(grant)<=8192),
 signer_hash BLOB NOT NULL CHECK(length(signer_hash)=32),
 binding_hash BLOB NOT NULL CHECK(length(binding_hash)=32),
 sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>=0)
);
CREATE TABLE op_entity (
 kind TEXT NOT NULL CHECK(kind IN ('ORDER','TABLE','RESERVATION','PACKAGE','SALE','DAY')),
 id TEXT NOT NULL,
 revision INTEGER NOT NULL CHECK(typeof(revision)='integer' AND revision>0),
 tombstone INTEGER NOT NULL CHECK(tombstone IN (0,1)),
 document BLOB NOT NULL CHECK(length(document)<=1048576 AND ((tombstone=1 AND length(document)=0) OR (tombstone=0 AND length(document)>0))),
 PRIMARY KEY(kind,id)
);
CREATE TABLE op_request (
 request_id TEXT PRIMARY KEY,
 terminal_id TEXT NOT NULL REFERENCES terminal(id),
 authority_epoch INTEGER NOT NULL CHECK(typeof(authority_epoch)='integer' AND authority_epoch>0),
 digest BLOB NOT NULL CHECK(length(digest)=32),
 outcome TEXT NOT NULL CHECK(outcome IN ('COMMITTED','CONFLICT')),
 event_sequence INTEGER REFERENCES op_event(sequence) DEFERRABLE INITIALLY DEFERRED,
 result BLOB NOT NULL CHECK(length(result)>0 AND length(result)<=50331648),
 CHECK((outcome='COMMITTED' AND event_sequence IS NOT NULL) OR (outcome='CONFLICT' AND event_sequence IS NULL))
);
CREATE TABLE op_event (
 sequence INTEGER PRIMARY KEY CHECK(typeof(sequence)='integer' AND sequence>0),
 authority_epoch INTEGER NOT NULL CHECK(typeof(authority_epoch)='integer' AND authority_epoch>0),
 request_id TEXT NOT NULL UNIQUE REFERENCES op_request(request_id) DEFERRABLE INITIALLY DEFERRED,
 terminal_id TEXT NOT NULL REFERENCES terminal(id),
 event BLOB NOT NULL CHECK(length(event)>0 AND length(event)<=18874368)
);
CREATE TABLE op_effect (
 id TEXT PRIMARY KEY,
 kind TEXT NOT NULL CHECK(kind IN ('AUDIT','PRINT')),
 request_id TEXT NOT NULL REFERENCES op_request(request_id) DEFERRABLE INITIALLY DEFERRED,
 event_sequence INTEGER NOT NULL REFERENCES op_event(sequence) DEFERRABLE INITIALLY DEFERRED,
 ordinal INTEGER NOT NULL CHECK(typeof(ordinal)='integer' AND ordinal>=0),
 payload BLOB NOT NULL CHECK(length(payload)>0 AND length(payload)<=12582912),
 UNIQUE(event_sequence,ordinal)
);
CREATE INDEX op_request_terminal ON op_request(terminal_id);

-- Durable request/effect/event records are immutable. The proof has no dispatch,
-- deletion, retention, authority rotation or tombstone resurrection operation.
CREATE TRIGGER op_authority_update BEFORE UPDATE ON op_authority
WHEN NEW.singleton IS NOT OLD.singleton OR NEW.purpose IS NOT OLD.purpose
 OR NEW.mode IS NOT OLD.mode OR NEW.installation_id IS NOT OLD.installation_id
 OR NEW.venue_id IS NOT OLD.venue_id OR NEW.public_key IS NOT OLD.public_key
 OR NEW.authority_epoch IS NOT OLD.authority_epoch OR NEW.grant_hash IS NOT OLD.grant_hash
 OR NEW.grant IS NOT OLD.grant OR NEW.signer_hash IS NOT OLD.signer_hash
 OR NEW.binding_hash IS NOT OLD.binding_hash OR NEW.sequence!=OLD.sequence+1
BEGIN SELECT RAISE(ABORT,'immutable proof authority or invalid sequence'); END;
CREATE TRIGGER op_authority_delete BEFORE DELETE ON op_authority
BEGIN SELECT RAISE(ABORT,'proof authority cannot be removed'); END;
CREATE TRIGGER op_entity_update BEFORE UPDATE ON op_entity
WHEN OLD.tombstone=1 OR NEW.kind IS NOT OLD.kind OR NEW.id IS NOT OLD.id OR NEW.revision!=OLD.revision+1
BEGIN SELECT RAISE(ABORT,'invalid entity revision or retained tombstone'); END;
CREATE TRIGGER op_entity_delete BEFORE DELETE ON op_entity
BEGIN SELECT RAISE(ABORT,'entity identity must be retained'); END;
CREATE TRIGGER op_request_update BEFORE UPDATE ON op_request
BEGIN SELECT RAISE(ABORT,'immutable request result'); END;
CREATE TRIGGER op_request_delete BEFORE DELETE ON op_request
BEGIN SELECT RAISE(ABORT,'immutable request result'); END;
CREATE TRIGGER op_event_update BEFORE UPDATE ON op_event
BEGIN SELECT RAISE(ABORT,'immutable event'); END;
CREATE TRIGGER op_event_delete BEFORE DELETE ON op_event
BEGIN SELECT RAISE(ABORT,'immutable event'); END;
CREATE TRIGGER op_effect_update BEFORE UPDATE ON op_effect
BEGIN SELECT RAISE(ABORT,'immutable frozen effect'); END;
CREATE TRIGGER op_effect_delete BEFORE DELETE ON op_effect
BEGIN SELECT RAISE(ABORT,'immutable frozen effect'); END;
