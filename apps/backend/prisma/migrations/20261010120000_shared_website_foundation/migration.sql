-- Shared website foundation: Venue-owned public information and per-Venue
-- capability policy, used alike by SAAS and CUSTOM frontends.
-- CreateEnum
CREATE TYPE "pos"."WebsiteCapabilityKey" AS ENUM ('MENU', 'HOURS', 'GALLERY', 'RESERVATIONS', 'CUSTOMER_ACCOUNTS', 'ONLINE_PAYMENTS');

-- CreateTable
CREATE TABLE "pos"."VenuePublicProfile" (
    "venueId" TEXT NOT NULL,
    "workingHours" JSONB NOT NULL DEFAULT '[]',
    "contactEmail" TEXT,
    "mapUrl" TEXT,
    "socials" JSONB NOT NULL DEFAULT '[]',
    "gallery" JSONB NOT NULL DEFAULT '[]',
    "revision" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VenuePublicProfile_pkey" PRIMARY KEY ("venueId")
);

-- CreateTable
CREATE TABLE "pos"."VenueWebsiteCapability" (
    "venueId" TEXT NOT NULL,
    "capability" "pos"."WebsiteCapabilityKey" NOT NULL,
    "enabled" BOOLEAN NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VenueWebsiteCapability_pkey" PRIMARY KEY ("venueId","capability")
);

-- AddForeignKey
ALTER TABLE "pos"."VenuePublicProfile" ADD CONSTRAINT "VenuePublicProfile_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."VenueWebsiteCapability" ADD CONSTRAINT "VenueWebsiteCapability_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Hours, contact, socials and gallery move out of the SAAS page document.
-- The latest saved draft is the owner's most recent intent, so it wins over
-- the published snapshot; a Venue with only a published document keeps that.
-- These values are live from here on (like the Venue profile), so an edit
-- that was saved but not yet published becomes public with this migration.
INSERT INTO "pos"."VenuePublicProfile"
  ("venueId", "workingHours", "contactEmail", "mapUrl", "socials", "gallery", "updatedAt")
SELECT
  c."venueId",
  COALESCE(src->'workingHours', '[]'::jsonb),
  NULLIF(src->>'contactEmail', ''),
  NULLIF(src->>'mapUrl', ''),
  COALESCE(src->'socials', '[]'::jsonb),
  COALESCE(src->'gallery', '[]'::jsonb),
  CURRENT_TIMESTAMP
FROM (
  SELECT "venueId", COALESCE("draft", "published") AS src
  FROM "pos"."VenueWebsiteConfig"
) c
WHERE jsonb_typeof(c.src) = 'object';

-- The page documents no longer carry the moved fields; the SAAS payload
-- projects them from VenuePublicProfile instead.
UPDATE "pos"."VenueWebsiteConfig"
SET "draft" = "draft" - 'workingHours' - 'contactEmail' - 'mapUrl' - 'socials' - 'gallery'
WHERE jsonb_typeof("draft") = 'object';
UPDATE "pos"."VenueWebsiteConfig"
SET "published" = "published" - 'workingHours' - 'contactEmail' - 'mapUrl' - 'socials' - 'gallery'
WHERE jsonb_typeof("published") = 'object';
