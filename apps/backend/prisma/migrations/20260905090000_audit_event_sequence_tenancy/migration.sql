-- Audit storage foundation: POS-owned event order, Venue-scoped event queries,
-- and a queryable Order kind on the report.
--
-- Additive only. No audit event, report, ordinal or detail is altered here:
-- `AuditEvent.venueId` is filled from the parent report, which is where that
-- Venue already came from, and `AuditReport.orderKind` is left null for every
-- existing row so ingestion can derive it from a report's own creation event
-- the next time that report legitimately changes. Nothing is guessed.

-- ── AuditEvent: denormalized tenant ─────────────────────────────────────────
ALTER TABLE "pos"."AuditEvent" ADD COLUMN "venueId" TEXT;

-- Copies the owning Venue down from the report. Deterministic and lossless:
-- every event already belongs to exactly one report, and that report already
-- carries the Venue the authenticated principal resolved.
UPDATE "pos"."AuditEvent" AS e
SET "venueId" = r."venueId"
FROM "pos"."AuditReport" AS r
WHERE e."reportId" = r."id"
  AND e."venueId" IS NULL;

-- ── AuditReport: queryable Order kind ───────────────────────────────────────
ALTER TABLE "pos"."AuditReport" ADD COLUMN "orderKind" TEXT;

-- ── Indexes ─────────────────────────────────────────────────────────────────
-- The timeline read. A composite on (reportId, seq) also answers every lookup
-- the single-column index answered, so that one goes.
DROP INDEX "pos"."AuditEvent_reportId_idx";
CREATE INDEX "AuditEvent_reportId_seq_idx" ON "pos"."AuditEvent"("reportId", "seq");

-- Cross-order event queries inside one Venue.
CREATE INDEX "AuditEvent_venueId_type_eventTime_idx" ON "pos"."AuditEvent"("venueId", "type", "eventTime");

-- `posOrderId` only identifies an Order within a Venue; index it that way.
DROP INDEX "pos"."AuditReport_posOrderId_idx";
CREATE INDEX "AuditReport_venueId_posOrderId_idx" ON "pos"."AuditReport"("venueId", "posOrderId");
