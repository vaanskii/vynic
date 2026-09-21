-- CreateEnum
CREATE TYPE "pos"."SaleLedgerCompleteness" AS ENUM ('COMPLETE', 'PARTIAL', 'LEGACY_SUMMARY_ONLY');

-- CreateEnum
CREATE TYPE "pos"."SaleLedgerReconciliation" AS ENUM ('MATCHED', 'MISMATCH', 'INCOMPLETE', 'LEGACY_ONLY');

-- CreateTable
CREATE TABLE "pos"."CloudSale" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "posSaleId" TEXT NOT NULL,
    "posOrderId" INTEGER NOT NULL,
    "closureId" TEXT,
    "businessDate" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL,
    "closedAt" TIMESTAMP(3) NOT NULL,
    "gross" DECIMAL(18,2) NOT NULL,
    "subtotal" DECIMAL(18,2) NOT NULL,
    "serviceFee" DECIMAL(18,2) NOT NULL,
    "discount" DECIMAL(18,2) NOT NULL,
    "manualAdjustment" DECIMAL(18,2) NOT NULL,
    "advanceApplied" DECIMAL(18,2) NOT NULL,
    "amountDueNow" DECIMAL(18,2) NOT NULL,
    "collectedNow" DECIMAL(18,2) NOT NULL,
    "paymentMethod" TEXT NOT NULL,
    "customPaymentLabel" TEXT,
    "isFiscal" BOOLEAN NOT NULL,
    "isCancelled" BOOLEAN NOT NULL DEFAULT false,
    "cancelledAt" TIMESTAMP(3),
    "cancelledBy" TEXT,
    "cancellationReason" TEXT,
    "restoredToOrder" BOOLEAN NOT NULL DEFAULT false,
    "restoredAt" TIMESTAMP(3),
    "restoredBy" TEXT,
    "createdBy" TEXT NOT NULL,
    "closedById" TEXT,
    "tableNumbers" TEXT[],
    "floor" TEXT NOT NULL,
    "sourceRevision" INTEGER NOT NULL,
    "sourceUpdatedAt" TIMESTAMP(3) NOT NULL,
    "syncedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CloudSale_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "pos"."SaleLine" (
    "id" TEXT NOT NULL,
    "saleId" TEXT NOT NULL,
    "lineSeq" INTEGER NOT NULL,
    "menuItemId" TEXT,
    "variantId" TEXT,
    "itemName" TEXT NOT NULL,
    "variantName" TEXT,
    "quantity" INTEGER NOT NULL,
    "unitPrice" DECIMAL(18,2) NOT NULL,
    "lineTotal" DECIMAL(18,2) NOT NULL,
    "comment" TEXT,
    CONSTRAINT "SaleLine_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "pos"."SalePayment" (
    "id" TEXT NOT NULL,
    "saleId" TEXT NOT NULL,
    "method" TEXT NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    CONSTRAINT "SalePayment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "pos"."SaleLedgerDay" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "businessDate" TEXT NOT NULL,
    "completeness" "pos"."SaleLedgerCompleteness" NOT NULL,
    "reconciliation" "pos"."SaleLedgerReconciliation" NOT NULL,
    "expectedSaleCount" INTEGER,
    "expectedRevenue" DECIMAL(18,2),
    "ledgerSaleCount" INTEGER NOT NULL,
    "ledgerRevenue" DECIMAL(18,2) NOT NULL,
    "legacyRevenue" DECIMAL(18,2),
    "declaredCompleteAt" TIMESTAMP(3),
    "lastSyncedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "SaleLedgerDay_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CloudSale_venueId_posSaleId_key" ON "pos"."CloudSale"("venueId", "posSaleId");
CREATE UNIQUE INDEX "CloudSale_venueId_closureId_key" ON "pos"."CloudSale"("venueId", "closureId");
CREATE INDEX "CloudSale_venueId_businessDate_closedAt_id_idx" ON "pos"."CloudSale"("venueId", "businessDate", "closedAt", "id");
CREATE INDEX "CloudSale_venueId_businessDate_paymentMethod_idx" ON "pos"."CloudSale"("venueId", "businessDate", "paymentMethod");
CREATE INDEX "CloudSale_venueId_closedById_businessDate_idx" ON "pos"."CloudSale"("venueId", "closedById", "businessDate");
CREATE UNIQUE INDEX "SaleLine_saleId_lineSeq_key" ON "pos"."SaleLine"("saleId", "lineSeq");
CREATE INDEX "SaleLine_menuItemId_idx" ON "pos"."SaleLine"("menuItemId");
CREATE INDEX "SaleLine_variantId_idx" ON "pos"."SaleLine"("variantId");
CREATE UNIQUE INDEX "SalePayment_saleId_method_key" ON "pos"."SalePayment"("saleId", "method");
CREATE INDEX "SalePayment_method_idx" ON "pos"."SalePayment"("method");
CREATE UNIQUE INDEX "SaleLedgerDay_venueId_businessDate_key" ON "pos"."SaleLedgerDay"("venueId", "businessDate");
CREATE INDEX "SaleLedgerDay_venueId_completeness_businessDate_idx" ON "pos"."SaleLedgerDay"("venueId", "completeness", "businessDate");

ALTER TABLE "pos"."CloudSale" ADD CONSTRAINT "CloudSale_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."SaleLine" ADD CONSTRAINT "SaleLine_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "pos"."CloudSale"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "pos"."SalePayment" ADD CONSTRAINT "SalePayment_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "pos"."CloudSale"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "pos"."SaleLedgerDay" ADD CONSTRAINT "SaleLedgerDay_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
