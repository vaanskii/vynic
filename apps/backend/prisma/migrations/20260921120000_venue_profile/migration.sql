ALTER TABLE "pos"."Venue"
  ADD COLUMN "branchName" TEXT,
  ADD COLUMN "address" TEXT,
  ADD COLUMN "phone" TEXT,
  ADD COLUMN "legalId" TEXT,
  ADD COLUMN "profileUpdatedAt" TIMESTAMP(3);
