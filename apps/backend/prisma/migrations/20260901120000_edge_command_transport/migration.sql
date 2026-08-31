-- Cloud → Edge work queue.
--
-- Purely additive: one new enum, one new table, its indexes and its foreign
-- keys. No existing table, column or index is touched, so this migration cannot
-- fail on production data and changes no current behaviour. Nothing enqueues
-- into it yet — the legacy POS callback outbox keeps delivering today's work
-- until Step 6B migrates command types across.

-- CreateEnum
CREATE TYPE "pos"."EdgeCommandStatus" AS ENUM ('PENDING', 'CLAIMED', 'SUCCEEDED', 'FAILED');

-- CreateTable
CREATE TABLE "pos"."EdgeCommand" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "deviceId" TEXT,
    "type" TEXT NOT NULL,
    "contractVersion" INTEGER NOT NULL DEFAULT 1,
    "payload" JSONB NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "status" "pos"."EdgeCommandStatus" NOT NULL DEFAULT 'PENDING',
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "maxAttempts" INTEGER NOT NULL DEFAULT 10,
    "availableAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimedAt" TIMESTAMP(3),
    "claimedByDeviceId" TEXT,
    "claimExpiresAt" TIMESTAMP(3),
    "acknowledgedAt" TIMESTAMP(3),
    "resultCode" TEXT,
    "resultDetail" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "EdgeCommand_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "EdgeCommand_venueId_status_availableAt_idx" ON "pos"."EdgeCommand"("venueId", "status", "availableAt");

-- CreateIndex
CREATE INDEX "EdgeCommand_deviceId_status_availableAt_idx" ON "pos"."EdgeCommand"("deviceId", "status", "availableAt");

-- CreateIndex
CREATE INDEX "EdgeCommand_status_claimExpiresAt_idx" ON "pos"."EdgeCommand"("status", "claimExpiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "EdgeCommand_venueId_idempotencyKey_key" ON "pos"."EdgeCommand"("venueId", "idempotencyKey");

-- AddForeignKey
ALTER TABLE "pos"."EdgeCommand" ADD CONSTRAINT "EdgeCommand_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."EdgeCommand" ADD CONSTRAINT "EdgeCommand_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "pos"."Device"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."EdgeCommand" ADD CONSTRAINT "EdgeCommand_claimedByDeviceId_fkey" FOREIGN KEY ("claimedByDeviceId") REFERENCES "pos"."Device"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

