ALTER TABLE pos."Receiving" ADD COLUMN "dueDate" TEXT,
  ADD COLUMN "paymentHistoryKnown" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE pos."Receiving" ALTER COLUMN "paymentHistoryKnown" SET DEFAULT true;
CREATE UNIQUE INDEX "Receiving_venueId_id_key" ON pos."Receiving"("venueId", id);
CREATE TABLE pos."SupplierPayment" (
 id TEXT PRIMARY KEY, "venueId" TEXT NOT NULL, "receivingId" TEXT NOT NULL,
 "requestId" TEXT NOT NULL, amount DECIMAL(18,2) NOT NULL CHECK (amount <> 0),
 "paymentDate" TEXT NOT NULL, "businessDate" TEXT NOT NULL, method TEXT NOT NULL,
 "actorId" TEXT NOT NULL, "actorName" TEXT NOT NULL, notes TEXT, reference TEXT,
 "reversalOfId" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "SupplierPayment_receiving_fkey" FOREIGN KEY ("venueId", "receivingId") REFERENCES pos."Receiving"("venueId", id) ON DELETE RESTRICT ON UPDATE CASCADE,
 CONSTRAINT "SupplierPayment_reversal_fkey" FOREIGN KEY ("reversalOfId") REFERENCES pos."SupplierPayment"(id),
 CHECK ((amount > 0 AND "reversalOfId" IS NULL) OR (amount < 0 AND "reversalOfId" IS NOT NULL))
);
CREATE UNIQUE INDEX "SupplierPayment_venueId_requestId_key" ON pos."SupplierPayment"("venueId", "requestId");
CREATE UNIQUE INDEX "SupplierPayment_reversalOfId_key" ON pos."SupplierPayment"("reversalOfId");
CREATE INDEX "SupplierPayment_venueId_businessDate_idx" ON pos."SupplierPayment"("venueId", "businessDate");
ALTER TABLE pos."StockMovement" ADD COLUMN "costPerBaseUnit" DECIMAL(30,12),
 ADD COLUMN "inventoryValueDelta" DECIMAL(30,12),
 ADD COLUMN "valuationStatus" TEXT NOT NULL DEFAULT 'UNVALUED',
 ADD COLUMN "valuationSequence" BIGSERIAL;
CREATE UNIQUE INDEX "StockMovement_valuationSequence_key" ON pos."StockMovement"("valuationSequence");

-- One value writer covers receipts, POS consumption and exact reversals.
-- Cloud acceptance order is authoritative; effective/business dates are labels.
CREATE FUNCTION pos.value_stock_movement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE q NUMERIC; v NUMERIC; last_cost NUMERIC; original pos."StockMovement"%ROWTYPE;
BEGIN
 PERFORM id FROM pos."StockItem" WHERE id=NEW."stockItemId" AND "venueId"=NEW."venueId" FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Stock item tenant mismatch'; END IF;
 IF TG_OP='INSERT' THEN NEW."valuationSequence" := nextval(pg_get_serial_sequence('pos."StockMovement"','valuationSequence')); END IF;
 IF NEW."reversalOfMovementId" IS NOT NULL THEN
   SELECT * INTO STRICT original FROM pos."StockMovement" WHERE id=NEW."reversalOfMovementId" AND "venueId"=NEW."venueId" AND "stockItemId"=NEW."stockItemId";
   IF NEW."quantityDeltaBase" <> -original."quantityDeltaBase" THEN RAISE EXCEPTION 'Reversal quantity mismatch'; END IF;
   NEW."costPerBaseUnit" := original."costPerBaseUnit";
   NEW."inventoryValueDelta" := -original."inventoryValueDelta";
   NEW."valuationStatus" := original."valuationStatus";
 ELSIF NEW."movementType"='RECEIVING' THEN
   SELECT "lineTotal" INTO STRICT v FROM pos."ReceivingLine" l JOIN pos."Receiving" r ON r.id=l."receivingId"
    WHERE l.id=NEW."receivingLineId" AND l."stockItemId"=NEW."stockItemId" AND r."venueId"=NEW."venueId";
   NEW."inventoryValueDelta" := v;
   NEW."costPerBaseUnit" := v / NEW."quantityDeltaBase";
   NEW."valuationStatus" := 'VALUED';
 ELSE
   SELECT COALESCE(SUM("quantityDeltaBase"),0), COALESCE(SUM("inventoryValueDelta"),0) INTO q,v
    FROM pos."StockMovement" WHERE "stockItemId"=NEW."stockItemId" AND "venueId"=NEW."venueId" AND id<>NEW.id AND "valuationStatus"<>'UNVALUED';
   SELECT "costPerBaseUnit" INTO last_cost FROM pos."StockMovement"
    WHERE "stockItemId"=NEW."stockItemId" AND "venueId"=NEW."venueId" AND id<>NEW.id AND "costPerBaseUnit" IS NOT NULL
    ORDER BY "valuationSequence" DESC LIMIT 1;
   NEW."costPerBaseUnit" := CASE WHEN q>0 AND v>=0 THEN v/q ELSE last_cost END;
   NEW."inventoryValueDelta" := CASE WHEN -NEW."quantityDeltaBase"=q THEN -v ELSE NEW."quantityDeltaBase"*NEW."costPerBaseUnit" END;
   NEW."valuationStatus" := CASE WHEN NEW."costPerBaseUnit" IS NULL OR q+NEW."quantityDeltaBase"<0 THEN 'PROVISIONAL' ELSE 'VALUED' END;
 END IF;
 RETURN NEW;
END $$;
-- Historical values are reconstructed once from deterministic recorded order,
-- never represented as original close-time cost snapshots.
CREATE TRIGGER stock_value_before_write BEFORE INSERT OR UPDATE OF "valuationStatus" ON pos."StockMovement"
 FOR EACH ROW EXECUTE FUNCTION pos.value_stock_movement();
DO $$ DECLARE m RECORD; seq BIGINT:=0; BEGIN
 FOR m IN SELECT id FROM pos."StockMovement" ORDER BY "createdAt", CASE "movementType" WHEN 'RECEIVING' THEN 0 WHEN 'CONSUMPTION' THEN 1 ELSE 2 END, id LOOP
  seq:=seq+1;
  UPDATE pos."StockMovement" SET "valuationSequence"= -seq WHERE id=m.id;
 END LOOP;
 UPDATE pos."StockMovement" SET "valuationSequence"= -"valuationSequence";
 FOR m IN SELECT id FROM pos."StockMovement" ORDER BY "valuationSequence" LOOP
  UPDATE pos."StockMovement" SET "valuationStatus"='RECONSTRUCTED' WHERE id=m.id;
 END LOOP;
END $$;
DROP TRIGGER stock_value_before_write ON pos."StockMovement";
UPDATE pos."StockMovement" SET "valuationStatus"='RECONSTRUCTED' WHERE "valuationStatus"='VALUED';
CREATE TRIGGER stock_value_before_write BEFORE INSERT ON pos."StockMovement" FOR EACH ROW EXECUTE FUNCTION pos.value_stock_movement();
