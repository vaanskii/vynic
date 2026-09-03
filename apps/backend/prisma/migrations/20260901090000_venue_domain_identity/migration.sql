-- Public website tenant identity: a hostname resolves authoritatively to one Venue.
--
-- Additive only. No existing table is touched, so this migration cannot fail on
-- production data. Registering a real production hostname is a deployment step,
-- not part of the schema: the row seeded below uses the reserved `.localhost`
-- TLD (RFC 6761) so nothing here can accidentally claim a live domain.

-- CreateEnum
CREATE TYPE "pos"."VenueDomainStatus" AS ENUM ('ACTIVE', 'DISABLED');

-- CreateTable
CREATE TABLE "pos"."VenueDomain" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "hostname" TEXT NOT NULL,
    "status" "pos"."VenueDomainStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VenueDomain_pkey" PRIMARY KEY ("id")
);

-- A hostname may name at most one Venue, ever. Reuse requires releasing it
-- first, which is deliberate: silently re-pointing a live domain at another
-- restaurant is exactly the failure this constraint exists to prevent.
CREATE UNIQUE INDEX "VenueDomain_hostname_key" ON "pos"."VenueDomain"("hostname");

-- CreateIndex
CREATE INDEX "VenueDomain_venueId_idx" ON "pos"."VenueDomain"("venueId");

-- Ownership cannot be silently orphaned: a Venue with domains cannot be deleted.
ALTER TABLE "pos"."VenueDomain" ADD CONSTRAINT "VenueDomain_venueId_fkey"
  FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Grandfather the bootstrap Venue with a development hostname so the existing
-- custom site resolves a real Venue locally. The production hostname is
-- registered at deployment time; the repository holds no evidence of it and
-- this migration deliberately does not guess one.
INSERT INTO "pos"."VenueDomain" ("id", "venueId", "hostname", "status", "createdAt", "updatedAt")
SELECT
  '00000000-0000-4000-8000-000000000030',
  '00000000-0000-4000-8000-000000000002',
  'vankisi.localhost',
  'ACTIVE',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
WHERE EXISTS (
  SELECT 1 FROM "pos"."Venue" WHERE "id" = '00000000-0000-4000-8000-000000000002'
)
ON CONFLICT ("hostname") DO NOTHING;
