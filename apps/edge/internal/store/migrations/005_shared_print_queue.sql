-- ISOLATED qualification only: a durable gateway queue for frozen PRINT
-- envelopes. This schema does not activate a physical sender, authenticate a
-- relay, replicate a gateway or fence an old raw-TCP writer. No lease expiry
-- grants ownership and an UNCERTAIN head never automatically replays.
CREATE TABLE pq_registry (
 physical_id TEXT PRIMARY KEY,
 venue_id TEXT NOT NULL,
 installation_id TEXT NOT NULL,
 epoch INTEGER NOT NULL CHECK(typeof(epoch)='integer' AND epoch>0),
 device_id TEXT NOT NULL,
 worker_host_id TEXT NOT NULL,
 binding_revision INTEGER NOT NULL CHECK(typeof(binding_revision)='integer' AND binding_revision>0),
 config_revision INTEGER NOT NULL CHECK(typeof(config_revision)='integer' AND config_revision>0),
 registry_revision INTEGER NOT NULL CHECK(typeof(registry_revision)='integer' AND registry_revision>0),
 destination BLOB NOT NULL CHECK(length(destination)>0 AND length(destination)<=16384),
 endpoint_key TEXT NOT NULL UNIQUE,
 next_sequence INTEGER NOT NULL DEFAULT 1 CHECK(typeof(next_sequence)='integer' AND next_sequence>0)
);
CREATE TABLE pq_alias (
 alias_id TEXT PRIMARY KEY,
 physical_id TEXT NOT NULL REFERENCES pq_registry(physical_id)
);
CREATE TABLE pq_job (
 job_id TEXT PRIMARY KEY,
 effect_id TEXT NOT NULL UNIQUE,
 request_id TEXT NOT NULL,
 terminal_id TEXT NOT NULL,
 origin_installation_id TEXT NOT NULL,
 physical_id TEXT NOT NULL REFERENCES pq_registry(physical_id),
 alias_id TEXT NOT NULL REFERENCES pq_alias(alias_id),
 sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>0),
 digest TEXT NOT NULL CHECK(length(digest)=64),
 envelope BLOB NOT NULL CHECK(length(envelope)>0 AND length(envelope)<=12582912),
 attempt_id TEXT NOT NULL UNIQUE,
 primary_state TEXT NOT NULL CHECK(primary_state IN ('queued','started','submitted','notSent','uncertain')),
 primary_result BLOB CHECK(primary_result IS NULL OR length(primary_result)<=8192),
 phase TEXT NOT NULL CHECK(phase IN ('queued','primary','beep','complete','hold')),
 UNIQUE(physical_id,sequence),
 CHECK((primary_state='queued' AND phase='queued' AND primary_result IS NULL)
  OR (primary_state='started' AND phase='primary' AND primary_result IS NULL)
  OR (primary_state='submitted' AND phase IN ('beep','complete') AND primary_result IS NOT NULL)
  OR (primary_state='notSent' AND phase='complete' AND primary_result IS NOT NULL)
  OR (primary_state='uncertain' AND phase='hold' AND primary_result IS NOT NULL))
);
CREATE TABLE pq_receipt (
 job_id TEXT PRIMARY KEY REFERENCES pq_job(job_id),
 receipt BLOB NOT NULL CHECK(length(receipt)>0 AND length(receipt)<=4096)
);
CREATE TABLE pq_claim (
 physical_id TEXT PRIMARY KEY REFERENCES pq_registry(physical_id),
 job_id TEXT NOT NULL UNIQUE REFERENCES pq_job(job_id),
 worker_id TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('running','hold'))
);
CREATE TABLE pq_attempt (
 attempt_id TEXT PRIMARY KEY,
 job_id TEXT NOT NULL UNIQUE REFERENCES pq_job(job_id),
 state TEXT NOT NULL CHECK(state IN ('started','submitted','notSent','uncertain')),
 result BLOB CHECK(result IS NULL OR length(result)<=8192),
 CHECK((state='started' AND result IS NULL) OR (state!='started' AND result IS NOT NULL))
);
CREATE TABLE pq_beep (
 job_id TEXT PRIMARY KEY REFERENCES pq_job(job_id),
 attempt_id TEXT NOT NULL UNIQUE,
 state TEXT NOT NULL CHECK(state IN ('pending','skipped','reserved','submitted','notSent','uncertain')),
 result BLOB CHECK(result IS NULL OR length(result)<=8192),
 CHECK((state IN ('pending','reserved') AND result IS NULL) OR (state NOT IN ('pending','reserved') AND result IS NOT NULL))
);

CREATE TRIGGER pq_registry_update BEFORE UPDATE ON pq_registry
WHEN NEW.physical_id IS NOT OLD.physical_id OR NEW.venue_id IS NOT OLD.venue_id
 OR NEW.installation_id IS NOT OLD.installation_id OR NEW.epoch IS NOT OLD.epoch
 OR NEW.device_id IS NOT OLD.device_id OR NEW.worker_host_id IS NOT OLD.worker_host_id
 OR NOT ((NEW.next_sequence=OLD.next_sequence+1 AND NEW.binding_revision=OLD.binding_revision
  AND NEW.config_revision=OLD.config_revision AND NEW.registry_revision=OLD.registry_revision
  AND NEW.destination IS OLD.destination AND NEW.endpoint_key IS OLD.endpoint_key)
  OR (NEW.next_sequence=OLD.next_sequence AND NEW.registry_revision=OLD.registry_revision+1
   AND NEW.binding_revision>=OLD.binding_revision AND NEW.config_revision>=OLD.config_revision
   AND NOT EXISTS(SELECT 1 FROM pq_job WHERE physical_id=OLD.physical_id AND phase!='complete')))
BEGIN SELECT RAISE(ABORT,'invalid registry mutation or unresolved printer'); END;
CREATE TRIGGER pq_registry_delete BEFORE DELETE ON pq_registry
BEGIN SELECT RAISE(ABORT,'physical identity must be retained'); END;
CREATE TRIGGER pq_alias_update BEFORE UPDATE ON pq_alias
BEGIN SELECT RAISE(ABORT,'alias identity must be retained'); END;
CREATE TRIGGER pq_alias_delete BEFORE DELETE ON pq_alias
BEGIN SELECT RAISE(ABORT,'alias identity must be retained'); END;
CREATE TRIGGER pq_job_update BEFORE UPDATE ON pq_job
WHEN NEW.job_id IS NOT OLD.job_id OR NEW.effect_id IS NOT OLD.effect_id
 OR NEW.request_id IS NOT OLD.request_id OR NEW.terminal_id IS NOT OLD.terminal_id
 OR NEW.origin_installation_id IS NOT OLD.origin_installation_id
 OR NEW.physical_id IS NOT OLD.physical_id OR NEW.alias_id IS NOT OLD.alias_id
 OR NEW.sequence IS NOT OLD.sequence OR NEW.digest IS NOT OLD.digest
 OR NEW.envelope IS NOT OLD.envelope OR NEW.attempt_id IS NOT OLD.attempt_id
 OR NOT ((OLD.primary_state='queued' AND NEW.primary_state='started')
  OR (OLD.primary_state='started' AND NEW.primary_state IN ('submitted','notSent','uncertain'))
  OR (OLD.primary_state='submitted' AND OLD.phase='beep' AND NEW.primary_state='submitted'
   AND NEW.phase='complete' AND NEW.primary_result IS OLD.primary_result))
BEGIN SELECT RAISE(ABORT,'invalid immutable job transition'); END;
CREATE TRIGGER pq_job_delete BEFORE DELETE ON pq_job
BEGIN SELECT RAISE(ABORT,'job identity must be retained'); END;
CREATE TRIGGER pq_receipt_update BEFORE UPDATE ON pq_receipt
BEGIN SELECT RAISE(ABORT,'admission receipt is immutable'); END;
CREATE TRIGGER pq_receipt_delete BEFORE DELETE ON pq_receipt
BEGIN SELECT RAISE(ABORT,'admission receipt must be retained'); END;
CREATE TRIGGER pq_claim_update BEFORE UPDATE ON pq_claim
WHEN NEW.physical_id IS NOT OLD.physical_id OR NEW.job_id IS NOT OLD.job_id
 OR NEW.worker_id IS NOT OLD.worker_id OR NOT (OLD.state='running' AND NEW.state='hold')
BEGIN SELECT RAISE(ABORT,'invalid busy owner transition'); END;
CREATE TRIGGER pq_claim_delete BEFORE DELETE ON pq_claim
WHEN EXISTS(SELECT 1 FROM pq_job WHERE job_id=OLD.job_id AND phase!='complete')
 OR EXISTS(SELECT 1 FROM pq_beep WHERE job_id=OLD.job_id AND state IN ('pending','reserved'))
BEGIN SELECT RAISE(ABORT,'busy or uncertain owner must be retained'); END;
CREATE TRIGGER pq_attempt_update BEFORE UPDATE ON pq_attempt
WHEN NEW.attempt_id IS NOT OLD.attempt_id OR NEW.job_id IS NOT OLD.job_id
 OR NOT (OLD.state='started' AND NEW.state IN ('submitted','notSent','uncertain'))
BEGIN SELECT RAISE(ABORT,'attempt cannot replay'); END;
CREATE TRIGGER pq_attempt_delete BEFORE DELETE ON pq_attempt
BEGIN SELECT RAISE(ABORT,'attempt evidence must be retained'); END;
CREATE TRIGGER pq_beep_update BEFORE UPDATE ON pq_beep
WHEN NEW.job_id IS NOT OLD.job_id OR NEW.attempt_id IS NOT OLD.attempt_id
 OR NOT ((OLD.state='pending' AND NEW.state IN ('reserved','skipped'))
  OR (OLD.state='reserved' AND NEW.state IN ('submitted','notSent','uncertain')))
BEGIN SELECT RAISE(ABORT,'beep reservation is spent'); END;
CREATE TRIGGER pq_beep_delete BEFORE DELETE ON pq_beep
BEGIN SELECT RAISE(ABORT,'beep evidence must be retained'); END;
