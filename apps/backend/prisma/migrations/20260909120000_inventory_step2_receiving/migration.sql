-- CreateEnum
CREATE TYPE "pos"."ReceivingStatus" AS ENUM ('DRAFT', 'POSTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "pos"."StockMovementType" AS ENUM ('RECEIVING', 'RECEIVING_REVERSAL');

-- CreateTable
CREATE TABLE "pos"."StockItemPurchaseUnit" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "unit" TEXT NOT NULL,
    "baseUnitMultiplier" DECIMAL(18,6) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StockItemPurchaseUnit_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."Receiving" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "supplierId" TEXT NOT NULL,
    "supplierNameSnapshot" TEXT NOT NULL,
    "waybillNumber" TEXT,
    "invoiceNumber" TEXT,
    "documentDate" TEXT NOT NULL,
    "receivedAt" TIMESTAMP(3) NOT NULL,
    "status" "pos"."ReceivingStatus" NOT NULL DEFAULT 'DRAFT',
    "notes" TEXT,
    "documentTotal" DECIMAL(18,2) NOT NULL DEFAULT 0,
    "createdById" TEXT NOT NULL,
    "createdByName" TEXT NOT NULL,
    "postedById" TEXT,
    "postedByName" TEXT,
    "postedAt" TIMESTAMP(3),
    "cancelledById" TEXT,
    "cancelledByName" TEXT,
    "cancelledAt" TIMESTAMP(3),
    "cancellationReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Receiving_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."ReceivingLine" (
    "id" TEXT NOT NULL,
    "receivingId" TEXT NOT NULL,
    "lineSequence" INTEGER NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "stockItemNameSnapshot" TEXT NOT NULL,
    "enteredQuantity" DECIMAL(18,3) NOT NULL,
    "enteredUnit" TEXT NOT NULL,
    "baseQuantity" DECIMAL(18,3) NOT NULL,
    "baseUnit" TEXT NOT NULL,
    "unitPurchaseCost" DECIMAL(18,4) NOT NULL,
    "lineTotal" DECIMAL(18,2) NOT NULL,
    "effectiveBaseUnitCost" DECIMAL(18,6) NOT NULL,
    "notes" TEXT,

    CONSTRAINT "ReceivingLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."StockMovement" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "movementType" "pos"."StockMovementType" NOT NULL,
    "quantityDeltaBase" DECIMAL(18,3) NOT NULL,
    "baseUnit" TEXT NOT NULL,
    "receivingId" TEXT,
    "receivingLineId" TEXT,
    "reversalOfMovementId" TEXT,
    "businessDate" TEXT NOT NULL,
    "effectiveAt" TIMESTAMP(3) NOT NULL,
    "actorId" TEXT NOT NULL,
    "actorName" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "details" JSONB,

    CONSTRAINT "StockMovement_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "StockItemPurchaseUnit_venueId_stockItemId_idx" ON "pos"."StockItemPurchaseUnit"("venueId", "stockItemId");

-- CreateIndex
CREATE UNIQUE INDEX "StockItemPurchaseUnit_stockItemId_unit_key" ON "pos"."StockItemPurchaseUnit"("stockItemId", "unit");

-- CreateIndex
CREATE INDEX "Receiving_venueId_documentDate_createdAt_id_idx" ON "pos"."Receiving"("venueId", "documentDate", "createdAt", "id");

-- CreateIndex
CREATE INDEX "Receiving_venueId_status_documentDate_idx" ON "pos"."Receiving"("venueId", "status", "documentDate");

-- CreateIndex
CREATE INDEX "Receiving_venueId_supplierId_documentDate_idx" ON "pos"."Receiving"("venueId", "supplierId", "documentDate");

-- CreateIndex
CREATE INDEX "Receiving_venueId_waybillNumber_idx" ON "pos"."Receiving"("venueId", "waybillNumber");

-- CreateIndex
CREATE INDEX "ReceivingLine_stockItemId_idx" ON "pos"."ReceivingLine"("stockItemId");

-- CreateIndex
CREATE UNIQUE INDEX "ReceivingLine_receivingId_lineSequence_key" ON "pos"."ReceivingLine"("receivingId", "lineSequence");

-- CreateIndex
CREATE UNIQUE INDEX "StockMovement_reversalOfMovementId_key" ON "pos"."StockMovement"("reversalOfMovementId");

-- CreateIndex
CREATE INDEX "StockMovement_venueId_stockItemId_createdAt_id_idx" ON "pos"."StockMovement"("venueId", "stockItemId", "createdAt", "id");

-- CreateIndex
CREATE INDEX "StockMovement_venueId_receivingId_idx" ON "pos"."StockMovement"("venueId", "receivingId");

-- CreateIndex
CREATE INDEX "StockMovement_venueId_movementType_businessDate_idx" ON "pos"."StockMovement"("venueId", "movementType", "businessDate");

-- CreateIndex
CREATE UNIQUE INDEX "StockMovement_receivingLineId_movementType_key" ON "pos"."StockMovement"("receivingLineId", "movementType");

-- AddForeignKey
ALTER TABLE "pos"."StockItemPurchaseUnit" ADD CONSTRAINT "StockItemPurchaseUnit_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."StockItemPurchaseUnit" ADD CONSTRAINT "StockItemPurchaseUnit_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "pos"."StockItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."Receiving" ADD CONSTRAINT "Receiving_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."Receiving" ADD CONSTRAINT "Receiving_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "pos"."Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."ReceivingLine" ADD CONSTRAINT "ReceivingLine_receivingId_fkey" FOREIGN KEY ("receivingId") REFERENCES "pos"."Receiving"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."ReceivingLine" ADD CONSTRAINT "ReceivingLine_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "pos"."StockItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."StockMovement" ADD CONSTRAINT "StockMovement_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."StockMovement" ADD CONSTRAINT "StockMovement_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "pos"."StockItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."StockMovement" ADD CONSTRAINT "StockMovement_receivingId_fkey" FOREIGN KEY ("receivingId") REFERENCES "pos"."Receiving"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."StockMovement" ADD CONSTRAINT "StockMovement_receivingLineId_fkey" FOREIGN KEY ("receivingLineId") REFERENCES "pos"."ReceivingLine"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

