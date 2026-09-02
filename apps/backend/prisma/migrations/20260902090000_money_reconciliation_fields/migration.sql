-- Fields the Cloud needs to reconcile what the POS reports.
--
-- Purely additive. Three new columns, all with defaults or nullable, plus two
-- indexes and one unique constraint on a nullable column. No existing row is
-- rewritten and no existing column changes type or nullability, so this
-- migration cannot fail on production data.
--
-- "Order.manualAdjustmentAmount" mirrors the POS's signed override of a bill
-- total. Until now the Cloud received the adjusted "totalAmount" with nothing
-- explaining the difference from the order's own item lines. Existing rows
-- default to 0, which is what they were implicitly assumed to be.
--
-- "Expense.posExpenseId" gives the POS's own record id a home so ingestion can
-- upsert instead of insert. The unique constraint is venue-scoped and, because
-- PostgreSQL treats NULLs as distinct, does not collide across the existing
-- rows that have no POS id.

-- AlterTable
ALTER TABLE "pos"."Order" ADD COLUMN "manualAdjustmentAmount" DOUBLE PRECISION NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "pos"."Expense" ADD COLUMN "posExpenseId" TEXT;
ALTER TABLE "pos"."Expense" ADD COLUMN "businessDate" TEXT NOT NULL DEFAULT '';

-- CreateIndex
CREATE UNIQUE INDEX "Expense_venueId_posExpenseId_key" ON "pos"."Expense"("venueId", "posExpenseId");

-- CreateIndex
CREATE INDEX "Expense_venueId_businessDate_idx" ON "pos"."Expense"("venueId", "businessDate");
