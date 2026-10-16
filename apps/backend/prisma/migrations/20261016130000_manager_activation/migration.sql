-- Initial activation has no shared PIN and does not change existing Staff.
CREATE TABLE "pos"."ManagerActivation" (
  "id" TEXT NOT NULL,
  "venueId" TEXT NOT NULL,
  "secretHash" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "consumedAt" TIMESTAMP(3),
  "requestId" TEXT,
  "staffId" TEXT,
  "issuerId" TEXT NOT NULL,
  "issuerType" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ManagerActivation_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "ManagerActivation_venueId_key" ON "pos"."ManagerActivation"("venueId");
ALTER TABLE "pos"."ManagerActivation" ADD CONSTRAINT "ManagerActivation_venueId_fkey"
  FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
