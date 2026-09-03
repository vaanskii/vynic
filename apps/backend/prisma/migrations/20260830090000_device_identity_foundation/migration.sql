-- Step 3A: additive identity for one concrete Vynic POS installation.
-- No tenancy or operational-row ownership is introduced by this migration.

-- CreateEnum
CREATE TYPE "pos"."DeviceStatus" AS ENUM ('ACTIVE', 'DISABLED', 'REVOKED');

-- CreateTable
CREATE TABLE "pos"."Device" (
    "id" TEXT NOT NULL,
    "installationId" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "credentialHash" TEXT NOT NULL,
    "status" "pos"."DeviceStatus" NOT NULL DEFAULT 'ACTIVE',
    "lastSeenAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Device_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Device_installationId_key" ON "pos"."Device"("installationId");

-- CreateIndex
CREATE INDEX "Device_status_idx" ON "pos"."Device"("status");
