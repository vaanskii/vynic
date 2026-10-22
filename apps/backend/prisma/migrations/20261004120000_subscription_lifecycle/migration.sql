-- Additive: historical prices and billing dates remain unknown, never fabricated.
ALTER TABLE pos."VenueSubscription"
 ADD COLUMN "currentPeriodStart" TIMESTAMP(3),
 ADD COLUMN "billingAnchorAt" TIMESTAMP(3),
 ADD COLUMN "billingManaged" BOOLEAN NOT NULL DEFAULT false,
 ADD COLUMN "version" INTEGER NOT NULL DEFAULT 0,
 ADD COLUMN "pendingPlanId" TEXT,
 ADD COLUMN "pendingPriceMinor" INTEGER,
 ADD COLUMN "pendingCurrency" TEXT,
 ADD COLUMN "pendingBillingPeriod" TEXT,
 ADD COLUMN "pendingChangeAt" TIMESTAMP(3),
 ADD COLUMN "cancelAtPeriodEnd" BOOLEAN NOT NULL DEFAULT false,
 ADD COLUMN "suspendedFrom" pos."SubscriptionStatus",
 ADD COLUMN "paymentState" TEXT NOT NULL DEFAULT 'NONE',
 ADD COLUMN "trialEndedAt" TIMESTAMP(3),
 ADD CONSTRAINT "VenueSubscription_pendingPlanId_fkey" FOREIGN KEY ("pendingPlanId") REFERENCES pos."Plan"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
CREATE TABLE pos."SubscriptionBillingOperation" (
 "id" TEXT PRIMARY KEY, "venueId" TEXT NOT NULL, "kind" TEXT NOT NULL,
 "state" TEXT NOT NULL DEFAULT 'PENDING', "subscriptionVersion" INTEGER NOT NULL,
 "planId" TEXT NOT NULL, "planName" TEXT NOT NULL, "priceMinor" INTEGER NOT NULL,
 "currency" TEXT NOT NULL, "billingPeriod" TEXT NOT NULL, "amountMinor" INTEGER NOT NULL,
 "quotedAt" TIMESTAMP(3) NOT NULL, "expiresAt" TIMESTAMP(3) NOT NULL,
 "periodStart" TIMESTAMP(3), "periodEnd" TIMESTAMP(3), "source" TEXT NOT NULL, "reason" TEXT,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "SubscriptionBillingOperation_venueId_createdAt_idx" ON pos."SubscriptionBillingOperation"("venueId", "createdAt");
CREATE TABLE pos."SubscriptionBillingEvent" (
 "id" TEXT PRIMARY KEY, "provider" TEXT NOT NULL, "eventId" TEXT NOT NULL,
 "operationId" TEXT NOT NULL, "type" TEXT NOT NULL, "amountMinor" INTEGER NOT NULL,
 "currency" TEXT NOT NULL, "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "SubscriptionBillingEvent_operationId_fkey" FOREIGN KEY ("operationId") REFERENCES pos."SubscriptionBillingOperation"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "SubscriptionBillingEvent_provider_eventId_key" ON pos."SubscriptionBillingEvent"("provider", "eventId");
