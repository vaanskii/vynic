-- Preserve structured closure identity and money facts on synced audit events.
ALTER TABLE "pos"."AuditEvent" ADD COLUMN "details" JSONB;
