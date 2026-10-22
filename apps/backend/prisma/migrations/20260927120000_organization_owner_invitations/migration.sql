CREATE TYPE "pos"."OrganizationRole" AS ENUM ('OWNER');
CREATE TYPE "pos"."OnboardingWebsiteMode" AS ENUM ('NONE', 'SAAS');
ALTER TABLE "pos"."CustomerAccount" ALTER COLUMN "organizationId" DROP NOT NULL;
ALTER TABLE "pos"."OnboardingPolicy" ADD COLUMN "defaultWebsiteMode" "pos"."OnboardingWebsiteMode" NOT NULL DEFAULT 'NONE';
CREATE TABLE "pos"."OrganizationMembership" (
  "customerAccountId" TEXT NOT NULL REFERENCES "pos"."CustomerAccount"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "organizationId" TEXT NOT NULL REFERENCES "pos"."Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "role" "pos"."OrganizationRole" NOT NULL DEFAULT 'OWNER',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY ("customerAccountId", "organizationId")
);
CREATE INDEX "OrganizationMembership_organizationId_idx" ON "pos"."OrganizationMembership"("organizationId");
INSERT INTO "pos"."OrganizationMembership" ("customerAccountId", "organizationId", "createdAt")
SELECT "id", "organizationId", "createdAt" FROM "pos"."CustomerAccount" WHERE "organizationId" IS NOT NULL
ON CONFLICT DO NOTHING;
CREATE TABLE "pos"."OwnerInvitation" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "organizationId" TEXT NOT NULL REFERENCES "pos"."Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "email" TEXT NOT NULL,
  "role" "pos"."OrganizationRole" NOT NULL DEFAULT 'OWNER',
  "tokenHash" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "acceptedAt" TIMESTAMP(3),
  "acceptedById" TEXT REFERENCES "pos"."CustomerAccount"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "revokedAt" TIMESTAMP(3),
  "createdBy" TEXT NOT NULL,
  "revokedBy" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX "OwnerInvitation_tokenHash_key" ON "pos"."OwnerInvitation"("tokenHash");
CREATE INDEX "OwnerInvitation_organizationId_email_idx" ON "pos"."OwnerInvitation"("organizationId", "email");
