-- Additive: old enrollment codes and Manager invitations retain their behavior.
ALTER TABLE "pos"."DeviceEnrollment"
  ADD COLUMN "initialManagerSetup" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "pos"."ManagerActivation"
  ADD COLUMN "setupEnrollmentId" TEXT,
  ADD COLUMN "setupDeviceId" TEXT;
CREATE UNIQUE INDEX "DeviceEnrollment_id_venueId_key"
  ON "pos"."DeviceEnrollment"("id", "venueId");
CREATE UNIQUE INDEX "ManagerActivation_setupEnrollmentId_key"
  ON "pos"."ManagerActivation"("setupEnrollmentId");
ALTER TABLE "pos"."ManagerActivation"
  ADD CONSTRAINT "ManagerActivation_setupEnrollmentId_venueId_fkey"
  FOREIGN KEY ("setupEnrollmentId", "venueId")
  REFERENCES "pos"."DeviceEnrollment"("id", "venueId")
  ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE "pos"."ManagerActivation"
  ADD CONSTRAINT "ManagerActivation_setupDeviceId_venueId_fkey"
  FOREIGN KEY ("setupDeviceId", "venueId")
  REFERENCES "pos"."Device"("id", "venueId")
  ON DELETE RESTRICT ON UPDATE RESTRICT;
