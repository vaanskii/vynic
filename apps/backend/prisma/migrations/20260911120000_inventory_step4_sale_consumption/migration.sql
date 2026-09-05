-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "pos"."StockMovementType" ADD VALUE 'CONSUMPTION';
ALTER TYPE "pos"."StockMovementType" ADD VALUE 'CONSUMPTION_REVERSAL';

-- AlterTable
ALTER TABLE "pos"."StockMovement" ADD COLUMN     "consumptionComponentId" TEXT,
ALTER COLUMN "quantityDeltaBase" SET DATA TYPE DECIMAL(21,6);

-- CreateTable
CREATE TABLE "pos"."SaleConsumption" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "posSaleId" TEXT NOT NULL,
    "closureId" TEXT NOT NULL,
    "orderId" INTEGER NOT NULL,
    "businessDate" TEXT NOT NULL,
    "closedAt" TIMESTAMP(3) NOT NULL,
    "catalogGeneratedAt" TEXT,
    "policy" TEXT NOT NULL,
    "snapshot" JSONB NOT NULL,
    "reversedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SaleConsumption_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."SaleConsumptionLine" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "consumptionId" TEXT NOT NULL,
    "lineSeq" INTEGER NOT NULL,
    "menuItemId" TEXT,
    "variantId" TEXT,
    "itemName" TEXT NOT NULL,
    "variantName" TEXT,
    "soldQuantity" INTEGER NOT NULL,
    "status" TEXT NOT NULL,
    "reason" TEXT,
    "recipeId" TEXT,
    "recipeRevision" INTEGER,

    CONSTRAINT "SaleConsumptionLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."SaleConsumptionComponent" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "lineId" TEXT NOT NULL,
    "stockItemId" TEXT NOT NULL,
    "stockItemNameSnapshot" TEXT NOT NULL,
    "baseQuantityPerUnit" DECIMAL(18,6) NOT NULL,
    "totalBaseQuantity" DECIMAL(21,6) NOT NULL,
    "baseUnit" TEXT NOT NULL,

    CONSTRAINT "SaleConsumptionComponent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "SaleConsumption_venueId_businessDate_id_idx" ON "pos"."SaleConsumption"("venueId", "businessDate", "id");

-- CreateIndex
CREATE UNIQUE INDEX "SaleConsumption_venueId_posSaleId_key" ON "pos"."SaleConsumption"("venueId", "posSaleId");

-- CreateIndex
CREATE UNIQUE INDEX "SaleConsumption_venueId_closureId_key" ON "pos"."SaleConsumption"("venueId", "closureId");

-- CreateIndex
CREATE INDEX "SaleConsumptionLine_venueId_status_idx" ON "pos"."SaleConsumptionLine"("venueId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "SaleConsumptionLine_consumptionId_lineSeq_key" ON "pos"."SaleConsumptionLine"("consumptionId", "lineSeq");

-- CreateIndex
CREATE INDEX "SaleConsumptionComponent_venueId_stockItemId_idx" ON "pos"."SaleConsumptionComponent"("venueId", "stockItemId");

-- CreateIndex
CREATE UNIQUE INDEX "SaleConsumptionComponent_lineId_stockItemId_key" ON "pos"."SaleConsumptionComponent"("lineId", "stockItemId");

-- CreateIndex
CREATE UNIQUE INDEX "StockMovement_consumptionComponentId_movementType_key" ON "pos"."StockMovement"("consumptionComponentId", "movementType");

-- AddForeignKey
ALTER TABLE "pos"."StockMovement" ADD CONSTRAINT "StockMovement_consumptionComponentId_fkey" FOREIGN KEY ("consumptionComponentId") REFERENCES "pos"."SaleConsumptionComponent"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."SaleConsumption" ADD CONSTRAINT "SaleConsumption_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."SaleConsumptionLine" ADD CONSTRAINT "SaleConsumptionLine_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."SaleConsumptionLine" ADD CONSTRAINT "SaleConsumptionLine_consumptionId_fkey" FOREIGN KEY ("consumptionId") REFERENCES "pos"."SaleConsumption"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."SaleConsumptionComponent" ADD CONSTRAINT "SaleConsumptionComponent_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."SaleConsumptionComponent" ADD CONSTRAINT "SaleConsumptionComponent_lineId_fkey" FOREIGN KEY ("lineId") REFERENCES "pos"."SaleConsumptionLine"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."SaleConsumptionComponent" ADD CONSTRAINT "SaleConsumptionComponent_stockItemId_fkey" FOREIGN KEY ("stockItemId") REFERENCES "pos"."StockItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

