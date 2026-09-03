-- Step 4A: additive business ownership for the existing installation.
-- Operational records remain unscoped until Step 4B.

-- CreateEnum
CREATE TYPE "pos"."VenueStatus" AS ENUM ('ACTIVE', 'DISABLED');

-- CreateTable
CREATE TABLE "pos"."Organization" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Organization_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."Venue" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "status" "pos"."VenueStatus" NOT NULL DEFAULT 'ACTIVE',
    "timezone" TEXT NOT NULL,
    "currency" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Venue_pkey" PRIMARY KEY ("id")
);

-- Bootstrap the one restaurant installation that predates tenancy.
INSERT INTO "pos"."Organization" ("id", "name", "updatedAt")
VALUES (
    '00000000-0000-4000-8000-000000000001',
    'Restaurant Vankisi',
    CURRENT_TIMESTAMP
);

INSERT INTO "pos"."Venue" (
    "id",
    "organizationId",
    "name",
    "status",
    "timezone",
    "currency",
    "updatedAt"
)
VALUES (
    '00000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000001',
    'Restaurant Vankisi',
    'ACTIVE',
    'Asia/Tbilisi',
    'GEL',
    CURRENT_TIMESTAMP
);

-- Attach every pre-Step-4A Device before making ownership required.
ALTER TABLE "pos"."Device" ADD COLUMN "venueId" TEXT;

UPDATE "pos"."Device"
SET "venueId" = '00000000-0000-4000-8000-000000000002'
WHERE "venueId" IS NULL;

ALTER TABLE "pos"."Device" ALTER COLUMN "venueId" SET NOT NULL;

-- CreateIndex
CREATE INDEX "Venue_organizationId_idx" ON "pos"."Venue"("organizationId");

-- CreateIndex
CREATE INDEX "Device_venueId_idx" ON "pos"."Device"("venueId");

-- AddForeignKey
ALTER TABLE "pos"."Venue" ADD CONSTRAINT "Venue_organizationId_fkey"
FOREIGN KEY ("organizationId") REFERENCES "pos"."Organization"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."Device" ADD CONSTRAINT "Device_venueId_fkey"
FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;
