-- Platform administrator identity and its audit trail.
--
-- Purely additive: two enums, two tables, their indexes and one foreign key.
-- No existing table, column or index is touched, so this migration cannot fail
-- on production data and changes nothing that runs today. No administrator is
-- seeded — a known default password would be a worse hole than the missing
-- boundary this closes. The first one is created by `npm run platform-admin:create`.

-- CreateEnum
CREATE TYPE "pos"."PlatformUserStatus" AS ENUM ('ACTIVE', 'DISABLED');

-- CreateEnum
CREATE TYPE "pos"."PlatformRole" AS ENUM ('SUPER_ADMIN');

-- CreateTable
CREATE TABLE "pos"."PlatformUser" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "role" "pos"."PlatformRole" NOT NULL DEFAULT 'SUPER_ADMIN',
    "status" "pos"."PlatformUserStatus" NOT NULL DEFAULT 'ACTIVE',
    "lastLoginAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PlatformUser_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."PlatformAuditEvent" (
    "id" TEXT NOT NULL,
    "platformUserId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" TEXT NOT NULL,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PlatformAuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PlatformUser_email_key" ON "pos"."PlatformUser"("email");

-- CreateIndex
CREATE INDEX "PlatformAuditEvent_platformUserId_createdAt_idx" ON "pos"."PlatformAuditEvent"("platformUserId", "createdAt");

-- CreateIndex
CREATE INDEX "PlatformAuditEvent_targetType_targetId_createdAt_idx" ON "pos"."PlatformAuditEvent"("targetType", "targetId", "createdAt");

-- CreateIndex
CREATE INDEX "PlatformAuditEvent_createdAt_idx" ON "pos"."PlatformAuditEvent"("createdAt");

-- AddForeignKey
ALTER TABLE "pos"."PlatformAuditEvent" ADD CONSTRAINT "PlatformAuditEvent_platformUserId_fkey" FOREIGN KEY ("platformUserId") REFERENCES "pos"."PlatformUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

