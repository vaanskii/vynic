-- Stable, POS-owned identity for a menu item.
--
-- Additive and nullable: every existing row keeps its Cloud `id` (which the
-- website already publishes in pre-order payloads) and adopts `posMenuItemId`
-- on the first snapshot from a POS that sends one. No backfill — the POS is
-- the only thing that knows which product is which.
ALTER TABLE "pos"."MenuItem" ADD COLUMN "posMenuItemId" TEXT;

-- One Cloud row per POS item, per Venue. Postgres allows many NULLs here, so
-- rows that have not been adopted yet do not collide with each other.
CREATE UNIQUE INDEX "MenuItem_venueId_posMenuItemId_key"
  ON "pos"."MenuItem"("venueId", "posMenuItemId");
