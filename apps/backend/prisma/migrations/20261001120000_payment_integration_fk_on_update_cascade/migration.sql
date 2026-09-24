-- DropForeignKey
ALTER TABLE "pos"."PaymentIntegration" DROP CONSTRAINT "PaymentIntegration_venueId_fkey";

-- DropForeignKey
ALTER TABLE "website"."reservations" DROP CONSTRAINT "reservations_paymentIntegrationId_venueId_fkey";

-- AddForeignKey
ALTER TABLE "website"."reservations" ADD CONSTRAINT "reservations_paymentIntegrationId_venueId_fkey" FOREIGN KEY ("paymentIntegrationId", "venueId") REFERENCES "pos"."PaymentIntegration"("id", "venueId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."PaymentIntegration" ADD CONSTRAINT "PaymentIntegration_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
