CREATE TABLE "pos"."EdgeFoundationInstallation" (
  "id" TEXT NOT NULL,
  "venueId" TEXT NOT NULL,
  "publicKey" TEXT NOT NULL,
  "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "EdgeFoundationInstallation_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "EdgeFoundationInstallation_publicKey_key" ON "pos"."EdgeFoundationInstallation"("publicKey");
CREATE INDEX "EdgeFoundationInstallation_venueId_idx" ON "pos"."EdgeFoundationInstallation"("venueId");
ALTER TABLE "pos"."EdgeFoundationInstallation" ADD CONSTRAINT "EdgeFoundationInstallation_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
