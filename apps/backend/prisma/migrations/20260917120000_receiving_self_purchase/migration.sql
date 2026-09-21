-- Market purchases preserve a source snapshot without inventing a supplier.
ALTER TABLE "pos"."Receiving" ALTER COLUMN "supplierId" DROP NOT NULL;
ALTER TABLE "pos"."Receiving" ADD COLUMN "sourceType" TEXT NOT NULL DEFAULT 'SUPPLIER';
ALTER TABLE "pos"."Receiving" ADD CONSTRAINT "Receiving_source_check"
CHECK (("sourceType" = 'SUPPLIER' AND "supplierId" IS NOT NULL)
    OR ("sourceType" = 'SELF_PURCHASE' AND "supplierId" IS NULL));
