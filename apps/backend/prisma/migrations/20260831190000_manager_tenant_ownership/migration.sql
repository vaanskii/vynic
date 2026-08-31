-- Step 4B2A: Venue ownership for the Manager-owned models Step 4B1 deferred.
--
-- These three carry Manager product data addressed by staff username or by a
-- client-generated draft id. Both are only unique inside a Venue, so without
-- ownership a second Venue's manager would read the first's counted menus and
-- notifications. Deferred in 4B1 because Manager tenant authentication did not
-- exist yet; it does now.
--
-- Staged additive migration: nullable column -> backfill -> NOT NULL ->
-- constraints. No row is deleted and no operational root is touched.

-- ─── 1. Add ownership as nullable ───────────────────────────────────────────

ALTER TABLE "pos"."QuickOrderDraft" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."ManagerNotification" ADD COLUMN "venueId" TEXT;
ALTER TABLE "pos"."PushDevice" ADD COLUMN "venueId" TEXT;

-- ─── 2. Backfill to the Step 4A bootstrap Venue ─────────────────────────────
-- Every existing row predates multi-tenancy and belongs to the one live
-- installation, exactly as the 4A and 4B1 backfills established.

UPDATE "pos"."QuickOrderDraft"
SET "venueId" = '00000000-0000-4000-8000-000000000002'
WHERE "venueId" IS NULL;

UPDATE "pos"."ManagerNotification"
SET "venueId" = '00000000-0000-4000-8000-000000000002'
WHERE "venueId" IS NULL;

UPDATE "pos"."PushDevice"
SET "venueId" = '00000000-0000-4000-8000-000000000002'
WHERE "venueId" IS NULL;

-- ─── 3. Require ownership ───────────────────────────────────────────────────

ALTER TABLE "pos"."QuickOrderDraft" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."ManagerNotification" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "pos"."PushDevice" ALTER COLUMN "venueId" SET NOT NULL;

-- ─── 4. Scope identity and indexes to the Venue ─────────────────────────────
-- draftId is a client-generated UUID, so its uniqueness becomes Venue-local in
-- the same way Order.posOrderId and Staff.username did in Step 4B1.
-- PushDevice.fcmToken stays globally unique: a device token genuinely is.

DROP INDEX "pos"."QuickOrderDraft_draftId_key";
CREATE UNIQUE INDEX "QuickOrderDraft_venueId_draftId_key"
    ON "pos"."QuickOrderDraft"("venueId", "draftId");
CREATE INDEX "QuickOrderDraft_venueId_idx" ON "pos"."QuickOrderDraft"("venueId");

CREATE INDEX "ManagerNotification_venueId_createdAt_idx"
    ON "pos"."ManagerNotification"("venueId", "createdAt");

DROP INDEX "pos"."PushDevice_staffUsername_idx";
CREATE INDEX "PushDevice_venueId_staffUsername_idx"
    ON "pos"."PushDevice"("venueId", "staffUsername");

-- ─── 5. Enforce ownership ───────────────────────────────────────────────────

ALTER TABLE "pos"."QuickOrderDraft" ADD CONSTRAINT "QuickOrderDraft_venueId_fkey"
FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "pos"."ManagerNotification" ADD CONSTRAINT "ManagerNotification_venueId_fkey"
FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "pos"."PushDevice" ADD CONSTRAINT "PushDevice_venueId_fkey"
FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;
