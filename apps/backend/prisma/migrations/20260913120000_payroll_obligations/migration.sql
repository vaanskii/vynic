-- CreateEnum
CREATE TYPE "pos"."CompensationType" AS ENUM ('MONTHLY_FIXED', 'DAILY_FIXED', 'MANUAL');

-- CreateEnum
CREATE TYPE "pos"."FinancialObligationType" AS ENUM ('RENT', 'BANK_LOAN', 'LEASE', 'UTILITY', 'OTHER');

-- CreateTable
CREATE TABLE "pos"."StaffCompensation" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "staffId" TEXT NOT NULL,
    "compensationType" "pos"."CompensationType" NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    "effectiveFrom" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actorId" TEXT NOT NULL,
    "actorName" TEXT NOT NULL,

    CONSTRAINT "StaffCompensation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."PayrollPeriod" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "staffId" TEXT NOT NULL,
    "staffName" TEXT NOT NULL,
    "periodMonth" TEXT NOT NULL,
    "compensationType" "pos"."CompensationType" NOT NULL,
    "rate" DECIMAL(18,2) NOT NULL,
    "targetAmount" DECIMAL(18,2) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PayrollPeriod_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."PayrollAccrual" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "payrollPeriodId" TEXT NOT NULL,
    "payableDate" TEXT,
    "amount" DECIMAL(18,2) NOT NULL,
    "notes" TEXT,
    "actorId" TEXT NOT NULL,
    "actorName" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PayrollAccrual_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."PayrollPayment" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "payrollPeriodId" TEXT NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    "businessDate" TEXT NOT NULL,
    "paymentDate" TEXT NOT NULL,
    "notes" TEXT,
    "actorId" TEXT NOT NULL,
    "actorName" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PayrollPayment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."FinancialObligation" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "type" "pos"."FinancialObligationType" NOT NULL,
    "monthlyAmount" DECIMAL(18,2) NOT NULL,
    "materializedThrough" TEXT,
    "dueDay" INTEGER NOT NULL,
    "startsOn" TEXT NOT NULL,
    "endsOn" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FinancialObligation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."ObligationCycle" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "obligationId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "type" "pos"."FinancialObligationType" NOT NULL,
    "periodMonth" TEXT NOT NULL,
    "targetAmount" DECIMAL(18,2) NOT NULL,
    "dueDate" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ObligationCycle_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."ObligationReserveEntry" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "obligationCycleId" TEXT NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    "businessDate" TEXT NOT NULL,
    "notes" TEXT,
    "actorId" TEXT NOT NULL,
    "actorName" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ObligationReserveEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."ObligationPayment" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "obligationCycleId" TEXT NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    "reserveConsumed" DECIMAL(18,2) NOT NULL,
    "businessDate" TEXT NOT NULL,
    "paymentDate" TEXT NOT NULL,
    "notes" TEXT,
    "actorId" TEXT NOT NULL,
    "actorName" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ObligationPayment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "StaffCompensation_venueId_staffId_effectiveFrom_key" ON "pos"."StaffCompensation"("venueId", "staffId", "effectiveFrom");

-- CreateIndex
CREATE UNIQUE INDEX "PayrollPeriod_venueId_staffId_periodMonth_key" ON "pos"."PayrollPeriod"("venueId", "staffId", "periodMonth");

-- CreateIndex
CREATE UNIQUE INDEX "PayrollPeriod_venueId_id_key" ON "pos"."PayrollPeriod"("venueId", "id");

-- CreateIndex
CREATE INDEX "PayrollAccrual_venueId_payrollPeriodId_idx" ON "pos"."PayrollAccrual"("venueId", "payrollPeriodId");

-- CreateIndex
CREATE UNIQUE INDEX "PayrollAccrual_payrollPeriodId_payableDate_key" ON "pos"."PayrollAccrual"("payrollPeriodId", "payableDate");

-- CreateIndex
CREATE INDEX "PayrollPayment_venueId_businessDate_idx" ON "pos"."PayrollPayment"("venueId", "businessDate");

-- CreateIndex
CREATE INDEX "FinancialObligation_venueId_isActive_idx" ON "pos"."FinancialObligation"("venueId", "isActive");

-- CreateIndex
CREATE UNIQUE INDEX "FinancialObligation_venueId_id_key" ON "pos"."FinancialObligation"("venueId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "ObligationCycle_venueId_obligationId_periodMonth_key" ON "pos"."ObligationCycle"("venueId", "obligationId", "periodMonth");

-- CreateIndex
CREATE UNIQUE INDEX "ObligationCycle_venueId_id_key" ON "pos"."ObligationCycle"("venueId", "id");

-- CreateIndex
CREATE INDEX "ObligationReserveEntry_venueId_businessDate_idx" ON "pos"."ObligationReserveEntry"("venueId", "businessDate");

-- CreateIndex
CREATE INDEX "ObligationPayment_venueId_businessDate_idx" ON "pos"."ObligationPayment"("venueId", "businessDate");

-- CreateIndex
CREATE UNIQUE INDEX "Staff_venueId_id_key" ON "pos"."Staff"("venueId", "id");

-- AddForeignKey
ALTER TABLE "pos"."StaffCompensation" ADD CONSTRAINT "StaffCompensation_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."StaffCompensation" ADD CONSTRAINT "StaffCompensation_venueId_staffId_fkey" FOREIGN KEY ("venueId", "staffId") REFERENCES "pos"."Staff"("venueId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."PayrollPeriod" ADD CONSTRAINT "PayrollPeriod_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."PayrollPeriod" ADD CONSTRAINT "PayrollPeriod_venueId_staffId_fkey" FOREIGN KEY ("venueId", "staffId") REFERENCES "pos"."Staff"("venueId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."PayrollAccrual" ADD CONSTRAINT "PayrollAccrual_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."PayrollAccrual" ADD CONSTRAINT "PayrollAccrual_venueId_payrollPeriodId_fkey" FOREIGN KEY ("venueId", "payrollPeriodId") REFERENCES "pos"."PayrollPeriod"("venueId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."PayrollPayment" ADD CONSTRAINT "PayrollPayment_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."PayrollPayment" ADD CONSTRAINT "PayrollPayment_venueId_payrollPeriodId_fkey" FOREIGN KEY ("venueId", "payrollPeriodId") REFERENCES "pos"."PayrollPeriod"("venueId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."FinancialObligation" ADD CONSTRAINT "FinancialObligation_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."ObligationCycle" ADD CONSTRAINT "ObligationCycle_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."ObligationCycle" ADD CONSTRAINT "ObligationCycle_venueId_obligationId_fkey" FOREIGN KEY ("venueId", "obligationId") REFERENCES "pos"."FinancialObligation"("venueId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."ObligationReserveEntry" ADD CONSTRAINT "ObligationReserveEntry_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."ObligationReserveEntry" ADD CONSTRAINT "ObligationReserveEntry_venueId_obligationCycleId_fkey" FOREIGN KEY ("venueId", "obligationCycleId") REFERENCES "pos"."ObligationCycle"("venueId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."ObligationPayment" ADD CONSTRAINT "ObligationPayment_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."ObligationPayment" ADD CONSTRAINT "ObligationPayment_venueId_obligationCycleId_fkey" FOREIGN KEY ("venueId", "obligationCycleId") REFERENCES "pos"."ObligationCycle"("venueId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

