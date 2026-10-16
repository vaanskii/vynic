-- Additive: existing Staff, sessions, Venue codes and setup grants are unchanged.
CREATE TABLE "pos"."ManagerVenueLink" (
  "id" TEXT NOT NULL,
  "venueId" TEXT NOT NULL,
  "codeSelector" TEXT NOT NULL,
  "codeHash" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "attemptCount" INTEGER NOT NULL DEFAULT 0,
  "consumedAt" TIMESTAMP(3),
  "consumedInstallationId" TEXT,
  "cancelledAt" TIMESTAMP(3),
  "issuedByPlatformUserId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ManagerVenueLink_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ManagerVenueLink_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT "ManagerVenueLink_issuedByPlatformUserId_fkey" FOREIGN KEY ("issuedByPlatformUserId") REFERENCES "pos"."PlatformUser"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE UNIQUE INDEX "ManagerVenueLink_codeSelector_key" ON "pos"."ManagerVenueLink"("codeSelector");
CREATE INDEX "ManagerVenueLink_venueId_createdAt_idx" ON "pos"."ManagerVenueLink"("venueId", "createdAt");
