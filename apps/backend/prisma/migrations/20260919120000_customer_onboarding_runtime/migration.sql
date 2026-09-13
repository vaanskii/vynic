-- AlterTable
ALTER TABLE "pos"."Device" ADD COLUMN     "firstSyncAt" TIMESTAMP(3),
ADD COLUMN     "runtimeConfig" JSONB;

-- AlterTable
ALTER TABLE "pos"."DeviceEnrollment" ADD COLUMN     "createdByCustomerAccountId" TEXT,
ALTER COLUMN "createdByPlatformUserId" DROP NOT NULL;

-- CreateTable
CREATE TABLE "pos"."CustomerAccount" (
    "id" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "emailVerifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CustomerAccount_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."CustomerAuditEvent" (
    "id" TEXT NOT NULL,
    "customerAccountId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" TEXT NOT NULL,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CustomerAuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."OnboardingPolicy" (
    "id" TEXT NOT NULL DEFAULT 'default',
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "trialPlanId" TEXT,
    "trialDays" INTEGER NOT NULL DEFAULT 14,
    "releaseLinks" JSONB,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OnboardingPolicy_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "CustomerAccount_email_key" ON "pos"."CustomerAccount"("email");

-- CreateIndex
CREATE INDEX "CustomerAccount_organizationId_idx" ON "pos"."CustomerAccount"("organizationId");

-- CreateIndex
CREATE INDEX "CustomerAuditEvent_customerAccountId_createdAt_idx" ON "pos"."CustomerAuditEvent"("customerAccountId", "createdAt");

-- CreateIndex
CREATE INDEX "CustomerAuditEvent_targetId_createdAt_idx" ON "pos"."CustomerAuditEvent"("targetId", "createdAt");

-- AddForeignKey
ALTER TABLE "pos"."DeviceEnrollment" ADD CONSTRAINT "DeviceEnrollment_createdByCustomerAccountId_fkey" FOREIGN KEY ("createdByCustomerAccountId") REFERENCES "pos"."CustomerAccount"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."CustomerAccount" ADD CONSTRAINT "CustomerAccount_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "pos"."Organization"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."CustomerAuditEvent" ADD CONSTRAINT "CustomerAuditEvent_customerAccountId_fkey" FOREIGN KEY ("customerAccountId") REFERENCES "pos"."CustomerAccount"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


-- Existing enrollments retain their Platform actor; new customer codes have one owner.
ALTER TABLE "pos"."DeviceEnrollment" ADD CONSTRAINT "DeviceEnrollment_one_actor" CHECK (("createdByPlatformUserId" IS NOT NULL)::int + ("createdByCustomerAccountId" IS NOT NULL)::int = 1);
