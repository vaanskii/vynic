-- Booking tenant ownership: website tables and reservations become Venue-owned.
--
-- Staged so it is safe on a populated database:
--   1. add the column nullable
--   2. backfill every existing row to the bootstrap Venue
--   3. tighten to NOT NULL
--   4. replace the global unique indexes with Venue-aware ones
--   5. add the foreign keys
--
-- No booking row is deleted and no column is dropped; the customer-facing
-- identifiers (websiteTableNumber, posFloor, posTableNumber) are untouched.

-- ── 1. Nullable columns ─────────────────────────────────────────────────────
ALTER TABLE "website"."tables" ADD COLUMN "venueId" TEXT;
ALTER TABLE "website"."reservations" ADD COLUMN "venueId" TEXT;

-- ── 2. Backfill to the bootstrap Venue ──────────────────────────────────────
-- Every pre-existing website table and booking belongs to the single existing
-- restaurant, which Step 4A recorded as the bootstrap Venue.
UPDATE "website"."tables"
   SET "venueId" = '00000000-0000-4000-8000-000000000002'
 WHERE "venueId" IS NULL;

UPDATE "website"."reservations"
   SET "venueId" = '00000000-0000-4000-8000-000000000002'
 WHERE "venueId" IS NULL;

-- ── 3. Require ownership ────────────────────────────────────────────────────
ALTER TABLE "website"."tables" ALTER COLUMN "venueId" SET NOT NULL;
ALTER TABLE "website"."reservations" ALTER COLUMN "venueId" SET NOT NULL;

-- ── 4. Venue-aware uniqueness ───────────────────────────────────────────────
-- `websiteTableNumber` is a per-restaurant customer-facing label: two Venues
-- may both publish `table1`, so it is unique only within a Venue.
DROP INDEX "website"."tables_websiteTableNumber_key";
CREATE UNIQUE INDEX "tables_venueId_websiteTableNumber_key"
  ON "website"."tables"("venueId", "websiteTableNumber");
CREATE INDEX "tables_venueId_idx" ON "website"."tables"("venueId");

-- `posReservationId` is issued by a Venue's own POS, so the same numeric id can
-- legitimately exist in two restaurants.
DROP INDEX "website"."reservations_posReservationId_key";
CREATE UNIQUE INDEX "reservations_venueId_posReservationId_key"
  ON "website"."reservations"("venueId", "posReservationId");
CREATE INDEX "reservations_venueId_date_idx" ON "website"."reservations"("venueId", "date");

-- ── 5. Foreign keys ─────────────────────────────────────────────────────────
ALTER TABLE "website"."tables" ADD CONSTRAINT "tables_venueId_fkey"
  FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "website"."reservations" ADD CONSTRAINT "reservations_venueId_fkey"
  FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
