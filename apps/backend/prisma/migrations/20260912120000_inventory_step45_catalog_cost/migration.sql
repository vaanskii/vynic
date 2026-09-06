CREATE TYPE "pos"."StockItemClassification" AS ENUM ('FOOD', 'BEVERAGE');
ALTER TABLE "pos"."StockItem" ADD COLUMN "classification" "pos"."StockItemClassification" NOT NULL DEFAULT 'FOOD';
CREATE UNIQUE INDEX "StockItem_venueId_id_key" ON "pos"."StockItem"("venueId", "id");
CREATE UNIQUE INDEX "Supplier_venueId_id_key" ON "pos"."Supplier"("venueId", "id");
CREATE TABLE "pos"."SupplierProduct" (
 "venueId" TEXT NOT NULL, "supplierId" TEXT NOT NULL, "stockItemId" TEXT NOT NULL,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "SupplierProduct_pkey" PRIMARY KEY ("venueId", "supplierId", "stockItemId"),
 CONSTRAINT "SupplierProduct_venueId_supplierId_fkey" FOREIGN KEY ("venueId", "supplierId") REFERENCES "pos"."Supplier"("venueId", "id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "SupplierProduct_venueId_stockItemId_fkey" FOREIGN KEY ("venueId", "stockItemId") REFERENCES "pos"."StockItem"("venueId", "id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "SupplierProduct_venueId_stockItemId_idx" ON "pos"."SupplierProduct"("venueId", "stockItemId");
ALTER TABLE "pos"."Receiving" ADD COLUMN "businessDate" TEXT;
-- Legacy documents used documentDate for their RECEIVING movement's businessDate.
UPDATE "pos"."Receiving" SET "businessDate" = "documentDate";
ALTER TABLE "pos"."Receiving" ALTER COLUMN "businessDate" SET NOT NULL;
CREATE INDEX "Receiving_venueId_businessDate_createdAt_id_idx" ON "pos"."Receiving"("venueId", "businessDate", "createdAt", "id");
