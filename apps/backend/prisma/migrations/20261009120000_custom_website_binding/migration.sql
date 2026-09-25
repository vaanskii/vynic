-- CUSTOM website binding: which custom frontend serves a CUSTOM Venue and the
-- operator-tracked setup status. Tenant authority is unchanged
-- (Host -> VenueDomain -> Venue); this table records deployment identity only.

-- CreateEnum
CREATE TYPE "pos"."CustomWebsiteStatus" AS ENUM ('SETUP_PENDING', 'READY', 'ACTIVE', 'ERROR');

-- CreateTable
CREATE TABLE "pos"."CustomWebsiteBinding" (
    "venueId" TEXT NOT NULL,
    "siteKey" TEXT,
    "status" "pos"."CustomWebsiteStatus" NOT NULL DEFAULT 'SETUP_PENDING',
    "statusNote" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CustomWebsiteBinding_pkey" PRIMARY KEY ("venueId")
);

-- CreateIndex
CREATE INDEX "CustomWebsiteBinding_siteKey_idx" ON "pos"."CustomWebsiteBinding"("siteKey");

-- AddForeignKey
ALTER TABLE "pos"."CustomWebsiteBinding" ADD CONSTRAINT "CustomWebsiteBinding_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Existing CUSTOM Venues keep serving. One that already has an ACTIVE domain is
-- live today (Vankisi), so it is recorded ACTIVE; any other CUSTOM Venue is
-- still being set up. The frontend identity is left for the operator to record.
INSERT INTO "pos"."CustomWebsiteBinding" ("venueId", "status", "updatedAt")
SELECT c."venueId",
       CASE WHEN EXISTS (
         SELECT 1 FROM "pos"."VenueDomain" d
         WHERE d."venueId" = c."venueId" AND d."status" = 'ACTIVE'
       ) THEN 'ACTIVE'::"pos"."CustomWebsiteStatus"
         ELSE 'SETUP_PENDING'::"pos"."CustomWebsiteStatus" END,
       CURRENT_TIMESTAMP
FROM "pos"."VenueWebsiteConfig" c
WHERE c."mode" = 'CUSTOM';

-- Website SUPER_ADMIN is bound to one Venue.
ALTER TABLE "website"."users" ADD COLUMN "adminVenueId" TEXT;

ALTER TABLE "website"."users" ADD CONSTRAINT "users_adminVenueId_fkey" FOREIGN KEY ("adminVenueId") REFERENCES "pos"."Venue"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- The only administrator that exists is the one the bootstrap seeder creates
-- for the bootstrap Venue, which was also the only Venue whose booking list it
-- could ever read before public tenancy existed. Preserve exactly that.
UPDATE "website"."users" u
SET "adminVenueId" = '00000000-0000-4000-8000-000000000002'
WHERE u."role" = 'SUPER_ADMIN'
  AND EXISTS (SELECT 1 FROM "pos"."Venue" v WHERE v."id" = '00000000-0000-4000-8000-000000000002');
