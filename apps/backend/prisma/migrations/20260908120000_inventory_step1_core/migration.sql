CREATE TABLE "pos"."StockItem" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "sku" TEXT,
    "baseUnit" TEXT NOT NULL,
    "minimumStock" DECIMAL(18,3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "StockItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "pos"."Supplier" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "taxId" TEXT,
    "phone" TEXT,
    "email" TEXT,
    "address" TEXT,
    "notes" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Supplier_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StockItem_venueId_sku_key" ON "pos"."StockItem"("venueId", "sku");
CREATE INDEX "StockItem_venueId_isActive_name_idx" ON "pos"."StockItem"("venueId", "isActive", "name");
CREATE INDEX "Supplier_venueId_isActive_name_idx" ON "pos"."Supplier"("venueId", "isActive", "name");

ALTER TABLE "pos"."StockItem" ADD CONSTRAINT "StockItem_venueId_fkey"
  FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "pos"."Supplier" ADD CONSTRAINT "Supplier_venueId_fkey"
  FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
