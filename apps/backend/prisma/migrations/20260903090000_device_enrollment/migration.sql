-- POS self-enrollment: one invitation table, nothing else touched.
--
-- Purely additive. One new table, its indexes and three foreign keys. No
-- existing table, column, index or constraint is modified, so this cannot fail
-- on production data and changes nothing that runs today. Devices provisioned
-- through the existing file drop keep working exactly as they do; they simply
-- have no row here.
--
-- One enrollment redeems into at most one Device, enforced by the conditional
-- claim on "redeemedAt" rather than by a unique index on "deviceId": a repaired
-- terminal re-enrolls onto the Device it already had, so the same "deviceId"
-- legitimately appears against more than one spent enrollment over time.

-- CreateTable
CREATE TABLE "pos"."DeviceEnrollment" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "codeSelector" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "lastAttemptAt" TIMESTAMP(3),
    "redeemedAt" TIMESTAMP(3),
    "redeemedInstallationId" TEXT,
    "deviceId" TEXT,
    "cancelledAt" TIMESTAMP(3),
    "createdByPlatformUserId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DeviceEnrollment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "DeviceEnrollment_codeSelector_key" ON "pos"."DeviceEnrollment"("codeSelector");

-- CreateIndex
CREATE INDEX "DeviceEnrollment_deviceId_idx" ON "pos"."DeviceEnrollment"("deviceId");

-- CreateIndex
CREATE INDEX "DeviceEnrollment_venueId_createdAt_idx" ON "pos"."DeviceEnrollment"("venueId", "createdAt");

-- CreateIndex
CREATE INDEX "DeviceEnrollment_expiresAt_idx" ON "pos"."DeviceEnrollment"("expiresAt");

-- AddForeignKey
ALTER TABLE "pos"."DeviceEnrollment" ADD CONSTRAINT "DeviceEnrollment_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."DeviceEnrollment" ADD CONSTRAINT "DeviceEnrollment_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "pos"."Device"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."DeviceEnrollment" ADD CONSTRAINT "DeviceEnrollment_createdByPlatformUserId_fkey" FOREIGN KEY ("createdByPlatformUserId") REFERENCES "pos"."PlatformUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
