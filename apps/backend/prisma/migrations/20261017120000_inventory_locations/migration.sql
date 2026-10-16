BEGIN;

CREATE TABLE pos."StockLocation" (
  id TEXT PRIMARY KEY,
  "venueId" TEXT NOT NULL,
  name TEXT NOT NULL,
  "isDefault" BOOLEAN NOT NULL DEFAULT false,
  "creationRequestId" TEXT,
  "creationFingerprint" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "StockLocation_venueId_fkey" FOREIGN KEY ("venueId")
    REFERENCES pos."Venue"(id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "StockLocation_name_check" CHECK (length(btrim(name)) BETWEEN 1 AND 200)
);
CREATE UNIQUE INDEX "StockLocation_venueId_id_key"
  ON pos."StockLocation"("venueId", id);
CREATE UNIQUE INDEX "StockLocation_venueId_creationRequestId_key"
  ON pos."StockLocation"("venueId", "creationRequestId");
CREATE UNIQUE INDEX "StockLocation_one_default_per_venue"
  ON pos."StockLocation"("venueId") WHERE "isDefault";
CREATE INDEX "StockLocation_venueId_name_id_idx"
  ON pos."StockLocation"("venueId", name, id);

-- Stable default identity; no old quantity, value, sequence or timestamp changes.
INSERT INTO pos."StockLocation" (id, "venueId", name, "isDefault", "updatedAt")
SELECT md5('vynic:stock-location:' || id)::uuid::text, id,
  'ძირითადი მარაგი', true, CURRENT_TIMESTAMP FROM pos."Venue";

CREATE FUNCTION pos.create_default_stock_location() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO pos."StockLocation" (id, "venueId", name, "isDefault", "updatedAt")
  VALUES (md5('vynic:stock-location:' || NEW.id)::uuid::text, NEW.id,
    'ძირითადი მარაგი', true, CURRENT_TIMESTAMP);
  RETURN NEW;
END $$;
CREATE TRIGGER venue_default_stock_location AFTER INSERT ON pos."Venue"
  FOR EACH ROW EXECUTE FUNCTION pos.create_default_stock_location();

ALTER TABLE pos."Receiving" ADD COLUMN "locationId" TEXT;
ALTER TABLE pos."StockMovement" ADD COLUMN "locationId" TEXT;
UPDATE pos."Receiving" r SET "locationId"=l.id
  FROM pos."StockLocation" l WHERE l."venueId"=r."venueId" AND l."isDefault";
UPDATE pos."StockMovement" m SET "locationId"=l.id
  FROM pos."StockLocation" l WHERE l."venueId"=m."venueId" AND l."isDefault";

-- Nullable columns keep legacy Prisma insert shapes valid. CHECK constraints
-- and BEFORE INSERT triggers make NULL impossible in committed ledger rows.
ALTER TABLE pos."Receiving"
  ADD CONSTRAINT "Receiving_location_required" CHECK ("locationId" IS NOT NULL),
  ADD CONSTRAINT "Receiving_venueId_locationId_fkey"
    FOREIGN KEY ("venueId", "locationId") REFERENCES pos."StockLocation"("venueId", id)
    ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE pos."StockMovement"
  ADD CONSTRAINT "StockMovement_location_required" CHECK ("locationId" IS NOT NULL),
  ADD CONSTRAINT "StockMovement_venueId_locationId_fkey"
    FOREIGN KEY ("venueId", "locationId") REFERENCES pos."StockLocation"("venueId", id)
    ON DELETE RESTRICT ON UPDATE CASCADE;
CREATE INDEX "StockMovement_venueId_locationId_stockItemId_idx"
  ON pos."StockMovement"("venueId", "locationId", "stockItemId");

CREATE FUNCTION pos.assign_receiving_location() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='UPDATE' AND OLD.status <> 'DRAFT' AND
    NEW."locationId" IS DISTINCT FROM OLD."locationId" THEN
    RAISE EXCEPTION 'Posted receiving location is immutable';
  END IF;
  IF NEW."locationId" IS NULL THEN
    SELECT id INTO STRICT NEW."locationId" FROM pos."StockLocation"
      WHERE "venueId"=NEW."venueId" AND "isDefault";
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER receiving_location_before_write
  BEFORE INSERT OR UPDATE OF "locationId" ON pos."Receiving"
  FOR EACH ROW EXECUTE FUNCTION pos.assign_receiving_location();

CREATE FUNCTION pos.assign_stock_movement_location() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE expected TEXT;
BEGIN
  IF TG_OP='UPDATE' THEN
    IF NEW."locationId" IS DISTINCT FROM OLD."locationId" THEN
      RAISE EXCEPTION 'Stock movement location is immutable';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW."reversalOfMovementId" IS NOT NULL THEN
    SELECT "locationId" INTO STRICT expected FROM pos."StockMovement"
      WHERE id=NEW."reversalOfMovementId" AND "venueId"=NEW."venueId"
        AND "stockItemId"=NEW."stockItemId";
  ELSIF NEW."receivingId" IS NOT NULL THEN
    SELECT "locationId" INTO STRICT expected FROM pos."Receiving"
      WHERE id=NEW."receivingId" AND "venueId"=NEW."venueId";
  ELSE
    -- Keep old/offline version-1 consumption deterministic. Its missing field
    -- cannot mean a newer configured issue location at Cloud acceptance time.
    IF NEW."locationId" IS NULL THEN
      SELECT id INTO STRICT expected FROM pos."StockLocation"
        WHERE "venueId"=NEW."venueId" AND "isDefault";
    END IF;
  END IF;
  IF expected IS NOT NULL THEN
    IF NEW."locationId" IS NOT NULL AND NEW."locationId" <> expected THEN
      RAISE EXCEPTION 'Stock movement location differs from source document';
    END IF;
    NEW."locationId" := expected;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER stock_location_before_write
  BEFORE INSERT OR UPDATE OF "locationId" ON pos."StockMovement"
  FOR EACH ROW EXECUTE FUNCTION pos.assign_stock_movement_location();

-- D015's stock_value_before_write and value_stock_movement are unchanged.
COMMIT;
