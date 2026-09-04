-- Venue-wide audit rows gain an entity identity.
--
-- Additive and nullable. Historical rows are deliberately left with NULL in
-- both columns: nothing durable on an old row says what it was about beyond
-- its action name, and the reader derives that at query time by translating an
-- entity filter into the set of actions that mean it. Rewriting history to
-- make a filter simpler is not a trade this system makes.
ALTER TABLE "pos"."AuditEventLog" ADD COLUMN "entityType" TEXT;
ALTER TABLE "pos"."AuditEventLog" ADD COLUMN "entityId" TEXT;

-- The reader's two shapes: "what happened to this thing" and "every action of
-- this kind here, recently". Both Venue-scoped and time-ordered, because every
-- query the reader issues is.
CREATE INDEX "AuditEventLog_venueId_entityType_entityId_createdAt_idx"
  ON "pos"."AuditEventLog"("venueId", "entityType", "entityId", "createdAt");
CREATE INDEX "AuditEventLog_venueId_action_createdAt_idx"
  ON "pos"."AuditEventLog"("venueId", "action", "createdAt");
