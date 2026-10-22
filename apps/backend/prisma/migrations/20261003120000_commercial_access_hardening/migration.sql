ALTER TYPE "pos"."SubscriptionStatus" ADD VALUE 'NO_PLAN';
ALTER TABLE "pos"."VenueSubscription" ALTER COLUMN "status" DROP DEFAULT;
ALTER TABLE "pos"."Venue" ADD COLUMN "legacyCommercialAccess" BOOLEAN NOT NULL DEFAULT false;
-- Only rows that already relied on missing-subscription compatibility retain it.
UPDATE "pos"."Venue" v SET "legacyCommercialAccess" = true
WHERE NOT EXISTS (SELECT 1 FROM "pos"."VenueSubscription" s WHERE s."venueId" = v."id");
-- Existing authority/configuration is preserved; new writes must opt in.
ALTER TABLE "pos"."Venue" ALTER COLUMN "cloudMenuEditingEnabled" SET DEFAULT false;
ALTER TABLE "pos"."PlatformAuditEvent" ALTER COLUMN "platformUserId" DROP NOT NULL;
ALTER TABLE "pos"."Plan"
  ADD COLUMN "description" TEXT,
  ADD COLUMN "priceMinor" INTEGER NOT NULL DEFAULT 0 CHECK ("priceMinor" >= 0),
  ADD COLUMN "currency" TEXT NOT NULL DEFAULT 'GEL',
  ADD COLUMN "billingPeriod" TEXT NOT NULL DEFAULT 'MONTH',
  ADD COLUMN "mediaQuotaBytes" INTEGER NOT NULL DEFAULT 52428800 CHECK ("mediaQuotaBytes" >= 0),
  ADD COLUMN "mediaQuotaFiles" INTEGER NOT NULL DEFAULT 50 CHECK ("mediaQuotaFiles" >= 0);
-- Unknown historical agreed prices stay NULL, never invented from today's list price.
ALTER TABLE "pos"."VenuePlanAssignment"
  ADD COLUMN "agreedPriceMinor" INTEGER,
  ADD COLUMN "agreedCurrency" TEXT,
  ADD COLUMN "agreedBillingPeriod" TEXT;
ALTER TABLE "pos"."VenueDomain" ADD COLUMN "releaseAfter" TIMESTAMP(3);
CREATE TABLE "pos"."OnboardingRequest" (
  "id" TEXT PRIMARY KEY,
  "applicantName" TEXT NOT NULL, "businessName" TEXT NOT NULL,
  "email" TEXT NOT NULL, "phone" TEXT NOT NULL,
  "requestedPlanId" TEXT, "note" TEXT,
  "status" TEXT NOT NULL DEFAULT 'PENDING' CHECK ("status" IN ('PENDING','APPROVED','REJECTED')),
  "reviewedBy" TEXT, "reviewedAt" TIMESTAMP(3), "reviewNote" TEXT, "approvedVenueId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL
);
CREATE INDEX "OnboardingRequest_status_createdAt_idx" ON "pos"."OnboardingRequest" ("status", "createdAt");
CREATE INDEX "OnboardingRequest_email_createdAt_idx" ON "pos"."OnboardingRequest" ("email", "createdAt");
CREATE TABLE "pos"."WebsiteMediaAsset" (
  "id" TEXT PRIMARY KEY, "venueId" TEXT NOT NULL REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "storageKey" TEXT NOT NULL UNIQUE, "purpose" TEXT NOT NULL,
  "byteSize" INTEGER NOT NULL CHECK ("byteSize" >= 0),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "unusedSince" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "WebsiteMediaAsset_venueId_idx" ON "pos"."WebsiteMediaAsset" ("venueId");
CREATE INDEX "WebsiteMediaAsset_unusedSince_idx" ON "pos"."WebsiteMediaAsset" ("unusedSince");
-- Defense in depth: even SQL writes cannot make this operator-only policy a package grant.
CREATE FUNCTION "pos"."reject_non_fiscal_plan_grant"() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM "pos"."Feature" WHERE "id"=NEW."featureId" AND "key"='NON_FISCAL_CLOSE') THEN
    RAISE EXCEPTION 'NON_FISCAL_CLOSE requires an explicit Venue override';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER "non_fiscal_plan_grant" BEFORE INSERT OR UPDATE ON "pos"."PlanFeature"
FOR EACH ROW EXECUTE FUNCTION "pos"."reject_non_fiscal_plan_grant"();
