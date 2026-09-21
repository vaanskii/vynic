ALTER TABLE pos."StockItem" ADD COLUMN "creationRequestId" TEXT;
CREATE UNIQUE INDEX "StockItem_venueId_creationRequestId_key" ON pos."StockItem"("venueId","creationRequestId");
ALTER TABLE pos."Receiving" ADD COLUMN "creationRequestId" TEXT, ADD COLUMN "creationFingerprint" TEXT;
CREATE UNIQUE INDEX "Receiving_venueId_creationRequestId_key" ON pos."Receiving"("venueId","creationRequestId");
