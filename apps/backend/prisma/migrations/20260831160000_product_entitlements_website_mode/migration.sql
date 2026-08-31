-- Step 5A: commercial product entitlements and website mode.
--
-- Additive only. No operational root, Device credential, canonical Table
-- identity, or reservation record is touched. Nothing created here gates
-- POS -> Cloud synchronization; see docs/PRODUCT_ENTITLEMENTS.md.


-- CreateEnum
CREATE TYPE "pos"."PlanStatus" AS ENUM ('ACTIVE', 'RETIRED');

-- CreateEnum
CREATE TYPE "pos"."FeatureOverrideEffect" AS ENUM ('ENABLED', 'DISABLED');

-- CreateEnum
CREATE TYPE "pos"."WebsiteMode" AS ENUM ('NONE', 'SAAS', 'CUSTOM');

-- CreateTable
CREATE TABLE "pos"."Feature" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Feature_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."Plan" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "status" "pos"."PlanStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Plan_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."PlanFeature" (
    "planId" TEXT NOT NULL,
    "featureId" TEXT NOT NULL,

    CONSTRAINT "PlanFeature_pkey" PRIMARY KEY ("planId","featureId")
);

-- CreateTable
CREATE TABLE "pos"."VenuePlanAssignment" (
    "venueId" TEXT NOT NULL,
    "planId" TEXT NOT NULL,
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VenuePlanAssignment_pkey" PRIMARY KEY ("venueId")
);

-- CreateTable
CREATE TABLE "pos"."VenueFeatureOverride" (
    "venueId" TEXT NOT NULL,
    "featureId" TEXT NOT NULL,
    "effect" "pos"."FeatureOverrideEffect" NOT NULL,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VenueFeatureOverride_pkey" PRIMARY KEY ("venueId","featureId")
);

-- CreateTable
CREATE TABLE "pos"."VenueWebsiteConfig" (
    "venueId" TEXT NOT NULL,
    "mode" "pos"."WebsiteMode" NOT NULL DEFAULT 'NONE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VenueWebsiteConfig_pkey" PRIMARY KEY ("venueId")
);

-- CreateIndex
CREATE UNIQUE INDEX "Feature_key_key" ON "pos"."Feature"("key");

-- CreateIndex
CREATE UNIQUE INDEX "Plan_key_key" ON "pos"."Plan"("key");

-- CreateIndex
CREATE INDEX "PlanFeature_featureId_idx" ON "pos"."PlanFeature"("featureId");

-- CreateIndex
CREATE INDEX "VenuePlanAssignment_planId_idx" ON "pos"."VenuePlanAssignment"("planId");

-- CreateIndex
CREATE INDEX "VenueFeatureOverride_featureId_idx" ON "pos"."VenueFeatureOverride"("featureId");

-- AddForeignKey
ALTER TABLE "pos"."PlanFeature" ADD CONSTRAINT "PlanFeature_planId_fkey" FOREIGN KEY ("planId") REFERENCES "pos"."Plan"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."PlanFeature" ADD CONSTRAINT "PlanFeature_featureId_fkey" FOREIGN KEY ("featureId") REFERENCES "pos"."Feature"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."VenuePlanAssignment" ADD CONSTRAINT "VenuePlanAssignment_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."VenuePlanAssignment" ADD CONSTRAINT "VenuePlanAssignment_planId_fkey" FOREIGN KEY ("planId") REFERENCES "pos"."Plan"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."VenueFeatureOverride" ADD CONSTRAINT "VenueFeatureOverride_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."VenueFeatureOverride" ADD CONSTRAINT "VenueFeatureOverride_featureId_fkey" FOREIGN KEY ("featureId") REFERENCES "pos"."Feature"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."VenueWebsiteConfig" ADD CONSTRAINT "VenueWebsiteConfig_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- ─── Seed the capabilities the product sells today ──────────────────────────
-- Features are rows so a later capability is an insert, not a migration.

INSERT INTO "pos"."Feature" ("id", "key", "name", "updatedAt") VALUES
    ('00000000-0000-4000-8000-000000000010', 'POS',         'Point of sale',    CURRENT_TIMESTAMP),
    ('00000000-0000-4000-8000-000000000011', 'WEBSITE',     'Restaurant website', CURRENT_TIMESTAMP),
    ('00000000-0000-4000-8000-000000000012', 'MANAGER_APP', 'Manager app',      CURRENT_TIMESTAMP);

-- ─── Seed the packages the business requires today ──────────────────────────
-- Names describe feature composition. They are not marketing names and carry
-- no pricing. The relational shape means a fifth package is data, not schema.

INSERT INTO "pos"."Plan" ("id", "key", "name", "status", "updatedAt") VALUES
    ('00000000-0000-4000-8000-000000000020', 'POS',                 'POS',                          'ACTIVE', CURRENT_TIMESTAMP),
    ('00000000-0000-4000-8000-000000000021', 'POS_WEBSITE',         'POS + Website',                'ACTIVE', CURRENT_TIMESTAMP),
    ('00000000-0000-4000-8000-000000000022', 'POS_MANAGER',         'POS + Manager App',            'ACTIVE', CURRENT_TIMESTAMP),
    ('00000000-0000-4000-8000-000000000023', 'POS_WEBSITE_MANAGER', 'POS + Website + Manager App',  'ACTIVE', CURRENT_TIMESTAMP);

INSERT INTO "pos"."PlanFeature" ("planId", "featureId")
SELECT p."id", f."id"
FROM "pos"."Plan" p
JOIN "pos"."Feature" f ON TRUE
WHERE (p."key" = 'POS'                 AND f."key" = 'POS')
   OR (p."key" = 'POS_WEBSITE'         AND f."key" IN ('POS', 'WEBSITE'))
   OR (p."key" = 'POS_MANAGER'         AND f."key" IN ('POS', 'MANAGER_APP'))
   OR (p."key" = 'POS_WEBSITE_MANAGER' AND f."key" IN ('POS', 'WEBSITE', 'MANAGER_APP'));

-- ─── Grandfather the existing installation ──────────────────────────────────
-- The Step 4A bootstrap Venue is the live Vankisi restaurant. It runs POS, a
-- custom website (apps/venue-web/), and Manager today, so it is assigned the
-- package that disables none of them. Its website is a restaurant-specific
-- build, which is configuration of the WEBSITE feature, not a feature of its
-- own. Guarded on existence so the migration is safe on a fresh database.

INSERT INTO "pos"."VenuePlanAssignment" ("venueId", "planId", "updatedAt")
SELECT
    '00000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000023',
    CURRENT_TIMESTAMP
WHERE EXISTS (
    SELECT 1 FROM "pos"."Venue"
    WHERE "id" = '00000000-0000-4000-8000-000000000002'
);

INSERT INTO "pos"."VenueWebsiteConfig" ("venueId", "mode", "updatedAt")
SELECT
    '00000000-0000-4000-8000-000000000002',
    'CUSTOM',
    CURRENT_TIMESTAMP
WHERE EXISTS (
    SELECT 1 FROM "pos"."Venue"
    WHERE "id" = '00000000-0000-4000-8000-000000000002'
);
