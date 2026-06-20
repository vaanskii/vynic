-- AlterTable
ALTER TABLE "website"."reservations" ADD COLUMN "posReservationId" TEXT,
ADD COLUMN "numberOfGuests" INTEGER;

-- CreateIndex
CREATE UNIQUE INDEX "reservations_posReservationId_key" ON "website"."reservations"("posReservationId");
