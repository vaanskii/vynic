CREATE TYPE "pos"."SubscriptionStatus" AS ENUM ('TRIAL','ACTIVE','PAST_DUE','SUSPENDED','CANCELLED');
ALTER TYPE "pos"."PlatformRole" ADD VALUE 'SUPPORT_READONLY';
ALTER TABLE "pos"."Staff" ADD COLUMN "platformManaged" BOOLEAN NOT NULL DEFAULT false, ADD COLUMN "displayName" TEXT;
CREATE TABLE "pos"."VenueSubscription" (
 "venueId" TEXT PRIMARY KEY REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 "status" "pos"."SubscriptionStatus" NOT NULL DEFAULT 'TRIAL',
 "startedAt" TIMESTAMP(3), "trialEndsAt" TIMESTAMP(3), "currentPeriodEndsAt" TIMESTAMP(3),
 "suspendedAt" TIMESTAMP(3), "cancelledAt" TIMESTAMP(3), "note" TEXT, "updatedBy" TEXT,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL
);
INSERT INTO "pos"."VenueSubscription" ("venueId","status","startedAt","updatedAt")
SELECT "id",'ACTIVE',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP FROM "pos"."Venue";
INSERT INTO "pos"."Feature" ("id","key","name","updatedAt") VALUES
('feature-inventory','INVENTORY','Inventory',CURRENT_TIMESTAMP),
('feature-payroll','PAYROLL','Payroll',CURRENT_TIMESTAMP),
('feature-financial-planning','FINANCIAL_PLANNING','Financial planning',CURRENT_TIMESTAMP),
('feature-profitability','PROFITABILITY','Profitability',CURRENT_TIMESTAMP),
('feature-manager-reservations','MANAGER_RESERVATIONS','Manager reservations',CURRENT_TIMESTAMP),
('feature-advanced-audit','ADVANCED_AUDIT','Advanced audit',CURRENT_TIMESTAMP)
ON CONFLICT ("key") DO NOTHING;
-- Existing Manager plans retain the modules that were bundled at rollout.
INSERT INTO "pos"."PlanFeature" ("planId","featureId")
SELECT pf."planId", f."id" FROM "pos"."PlanFeature" pf
JOIN "pos"."Feature" base ON base."id"=pf."featureId" AND base."key"='MANAGER_APP'
CROSS JOIN "pos"."Feature" f
WHERE f."key" IN ('INVENTORY','PAYROLL','FINANCIAL_PLANNING','PROFITABILITY','MANAGER_RESERVATIONS','ADVANCED_AUDIT')
ON CONFLICT DO NOTHING;
-- Explicit Manager grants also preserve their formerly bundled capabilities.
INSERT INTO "pos"."VenueFeatureOverride" ("venueId","featureId","effect","note","updatedAt")
SELECT o."venueId",f."id",'ENABLED','Phase 2 compatibility grant',CURRENT_TIMESTAMP
FROM "pos"."VenueFeatureOverride" o JOIN "pos"."Feature" base ON base."id"=o."featureId"
CROSS JOIN "pos"."Feature" f WHERE base."key"='MANAGER_APP' AND o."effect"='ENABLED'
AND f."key" IN ('INVENTORY','PAYROLL','FINANCIAL_PLANNING','PROFITABILITY','MANAGER_RESERVATIONS','ADVANCED_AUDIT')
ON CONFLICT DO NOTHING;
