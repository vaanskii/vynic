-- AlterTable
ALTER TABLE "pos"."PayrollAccrual" ADD COLUMN     "dayEntryId" TEXT,
ADD COLUMN     "worked" BOOLEAN;

-- CreateIndex
CREATE UNIQUE INDEX "PayrollAccrual_venueId_payrollPeriodId_id_key" ON "pos"."PayrollAccrual"("venueId", "payrollPeriodId", "id");

-- AddForeignKey
ALTER TABLE "pos"."PayrollAccrual" ADD CONSTRAINT "PayrollAccrual_venueId_payrollPeriodId_dayEntryId_fkey" FOREIGN KEY ("venueId", "payrollPeriodId", "dayEntryId") REFERENCES "pos"."PayrollAccrual"("venueId", "payrollPeriodId", "id") ON DELETE RESTRICT ON UPDATE NO ACTION;

