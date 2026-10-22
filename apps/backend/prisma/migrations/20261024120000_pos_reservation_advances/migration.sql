ALTER TABLE "pos"."PosReservation"
  ADD COLUMN "advanceAmount" DECIMAL(18,2) NOT NULL DEFAULT 0,
  ADD COLUMN "advanceCollectedOn" TEXT,
  ADD COLUMN "advanceReceiptId" TEXT,
  ADD CONSTRAINT "PosReservation_advance_nonnegative"
    CHECK ("advanceAmount" >= 0);
