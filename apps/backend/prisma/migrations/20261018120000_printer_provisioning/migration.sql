-- Additive printer-purpose authority. Existing POS and Foundation identities are unchanged.
CREATE UNIQUE INDEX "Device_id_venueId_key" ON pos."Device"("id", "venueId");
CREATE TABLE pos."PrinterInstallation" (
  "id" TEXT PRIMARY KEY,
  "venueId" TEXT NOT NULL REFERENCES pos."Venue"("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
  "deviceId" TEXT NOT NULL,
  "publicKey" TEXT NOT NULL UNIQUE,
  "certificateSha256" TEXT NOT NULL UNIQUE,
  "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PrinterInstallation_deviceId_venueId_fkey" FOREIGN KEY ("deviceId", "venueId") REFERENCES pos."Device"("id", "venueId") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX "PrinterInstallation_venueId_idx" ON pos."PrinterInstallation"("venueId");
CREATE INDEX "PrinterInstallation_deviceId_idx" ON pos."PrinterInstallation"("deviceId");
-- An explicit revoke is required before a fresh Go installation replaces a Device's service.
CREATE UNIQUE INDEX "PrinterInstallation_active_device" ON pos."PrinterInstallation"("deviceId") WHERE "revokedAt" IS NULL;
CREATE TABLE pos."PrinterVenueAuthority" (
  "venueId" TEXT PRIMARY KEY REFERENCES pos."Venue"("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
  "clusterId" TEXT NOT NULL UNIQUE,
  "revision" INTEGER NOT NULL DEFAULT 0 CHECK ("revision" >= 0),
  "generation" INTEGER NOT NULL DEFAULT 0 CHECK ("generation" >= 0),
  "configuration" JSONB NOT NULL,
  "fixedBindings" JSONB NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL
);
