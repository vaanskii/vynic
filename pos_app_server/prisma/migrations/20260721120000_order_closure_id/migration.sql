-- Task 1 (docs/VYNIC_ROADMAP.md): additive idempotency key for the future
-- atomic table-close flow. Nullable + unique; no data backfill required.
-- Rollback: DROP INDEX "pos"."Order_closureId_key";
--           ALTER TABLE "pos"."Order" DROP COLUMN "closureId";

-- AlterTable
ALTER TABLE "pos"."Order" ADD COLUMN     "closureId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Order_closureId_key" ON "pos"."Order"("closureId");
