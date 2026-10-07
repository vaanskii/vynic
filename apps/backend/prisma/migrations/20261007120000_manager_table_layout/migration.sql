-- Additive POS-owned presentation metadata. NULL is an unclassified legacy row.
ALTER TABLE "pos"."Table"
  ADD COLUMN "tableKind" TEXT,
  ADD COLUMN "tableLabel" TEXT,
  ADD COLUMN "floorLabel" TEXT,
  ADD COLUMN "tableSortOrder" INTEGER,
  ADD COLUMN "floorSortOrder" INTEGER;

ALTER TABLE "pos"."Table" ADD CONSTRAINT "Table_tableKind_check"
  CHECK ("tableKind" IS NULL OR "tableKind" IN ('PHYSICAL', 'VIRTUAL'));
