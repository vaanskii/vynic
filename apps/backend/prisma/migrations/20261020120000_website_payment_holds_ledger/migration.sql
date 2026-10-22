-- AlterTable
ALTER TABLE "website"."reservations" ADD COLUMN     "holdExpiresAt" TIMESTAMP(3),
ADD COLUMN     "holdState" TEXT,
ADD COLUMN     "nextPaymentCheckAt" TIMESTAMP(3),
ADD COLUMN     "paymentCurrency" TEXT,
ADD COLUMN     "paymentExpectedMinor" TEXT,
ADD COLUMN     "paymentGrossMinor" TEXT,
ADD COLUMN     "paymentRefundedMinor" TEXT,
ADD COLUMN     "paymentReviewReason" TEXT,
ADD COLUMN     "paymentState" TEXT NOT NULL DEFAULT 'UNTRACKED',
ADD COLUMN     "paymentTimelyProofAt" TIMESTAMP(3),
ADD COLUMN     "paymentWindowStartedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "pos"."WebsiteReservationDayHold" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "reservationId" TEXT NOT NULL,
    "serviceDate" TEXT NOT NULL,
    "tableCode" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'HELD',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "WebsiteReservationDayHold_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."WebsitePaymentObservation" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "reservationId" TEXT NOT NULL,
    "paymentId" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "fingerprint" TEXT NOT NULL,
    "facts" JSONB NOT NULL,
    "decision" TEXT NOT NULL,
    "reason" TEXT,
    "observedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WebsitePaymentObservation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "WebsiteReservationDayHold_venueId_serviceDate_status_idx" ON "pos"."WebsiteReservationDayHold"("venueId", "serviceDate", "status");

-- CreateIndex
CREATE UNIQUE INDEX "WebsiteReservationDayHold_reservationId_tableCode_key" ON "pos"."WebsiteReservationDayHold"("reservationId", "tableCode");

-- CreateIndex
CREATE INDEX "WebsitePaymentObservation_venueId_reservationId_createdAt_idx" ON "pos"."WebsitePaymentObservation"("venueId", "reservationId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "WebsitePaymentObservation_venueId_reservationId_fingerprint_key" ON "pos"."WebsitePaymentObservation"("venueId", "reservationId", "fingerprint");

-- AddForeignKey
ALTER TABLE "pos"."WebsiteReservationDayHold" ADD CONSTRAINT "WebsiteReservationDayHold_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."WebsiteReservationDayHold" ADD CONSTRAINT "WebsiteReservationDayHold_reservationId_venueId_fkey" FOREIGN KEY ("reservationId", "venueId") REFERENCES "website"."reservations"("id", "venueId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."WebsitePaymentObservation" ADD CONSTRAINT "WebsitePaymentObservation_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."WebsitePaymentObservation" ADD CONSTRAINT "WebsitePaymentObservation_reservationId_venueId_fkey" FOREIGN KEY ("reservationId", "venueId") REFERENCES "website"."reservations"("id", "venueId") ON DELETE RESTRICT ON UPDATE CASCADE;


-- Legacy money and holds are not reconstructed from old Float values/history.
ALTER TABLE website.reservations ALTER COLUMN "paymentState" SET DEFAULT 'PENDING';
CREATE UNIQUE INDEX website_one_active_table_day ON pos."WebsiteReservationDayHold" ("venueId", "serviceDate", "tableCode") WHERE status IN ('HELD','CONFIRMED');
ALTER TABLE pos."WebsiteReservationDayHold" ADD CONSTRAINT website_day_hold_shape CHECK (status IN ('HELD','CONFIRMED','RELEASED') AND "serviceDate" ~ '^\d{4}-\d{2}-\d{2}$' AND "tableCode">0);
ALTER TABLE website.reservations ADD CONSTRAINT website_payment_snapshot_shape CHECK (
  "paymentState" IN ('UNTRACKED','PENDING','PAID','PARTIALLY_REFUNDED','REFUNDED','DECLINED','REVIEW')
  AND ("holdState" IS NULL OR "holdState" IN ('HELD','CONFIRMED','RELEASED','EXPIRED'))
  AND (("paymentExpectedMinor" IS NULL AND "paymentCurrency" IS NULL) OR ("paymentExpectedMinor" IS NOT NULL AND "paymentCurrency" IS NOT NULL AND "paymentExpectedMinor" ~ '^[1-9][0-9]{0,15}$' AND "paymentCurrency"='GEL'))
);
CREATE FUNCTION pos.website_payment_observation_immutable() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Website payment observations are immutable' USING ERRCODE='23514'; END $$;
CREATE TRIGGER website_payment_observation_immutable BEFORE UPDATE ON pos."WebsitePaymentObservation" FOR EACH ROW EXECUTE FUNCTION pos.website_payment_observation_immutable();
CREATE FUNCTION pos.website_day_hold_identity_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.id, NEW."venueId", NEW."reservationId", NEW."serviceDate", NEW."tableCode", NEW."createdAt") IS DISTINCT FROM (OLD.id, OLD."venueId", OLD."reservationId", OLD."serviceDate", OLD."tableCode", OLD."createdAt") THEN
    RAISE EXCEPTION 'Website hold identity is immutable' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER website_day_hold_identity_immutable BEFORE UPDATE ON pos."WebsiteReservationDayHold" FOR EACH ROW EXECUTE FUNCTION pos.website_day_hold_identity_immutable();
CREATE FUNCTION website.payment_snapshot_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (OLD."paymentExpectedMinor" IS NOT NULL AND (NEW."paymentExpectedMinor", NEW."paymentCurrency", NEW."venueId", NEW.date, NEW."timeSlot", NEW."totalAmount", NEW."menuItems", NEW."paymentIntegrationId") IS DISTINCT FROM (OLD."paymentExpectedMinor", OLD."paymentCurrency", OLD."venueId", OLD.date, OLD."timeSlot", OLD."totalAmount", OLD."menuItems", OLD."paymentIntegrationId"))
    OR (OLD."paymentWindowStartedAt" IS NOT NULL AND (NEW."paymentWindowStartedAt",NEW."holdExpiresAt") IS DISTINCT FROM (OLD."paymentWindowStartedAt",OLD."holdExpiresAt"))
    OR (OLD."paymentId" IS NOT NULL AND NEW."paymentId" IS DISTINCT FROM OLD."paymentId") THEN
    RAISE EXCEPTION 'Website payment snapshot/identity is immutable' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER website_payment_snapshot_immutable BEFORE UPDATE ON website.reservations FOR EACH ROW EXECUTE FUNCTION website.payment_snapshot_immutable();

CREATE UNIQUE INDEX website_new_booking_payment_identity ON website.reservations ("venueId", "paymentId") WHERE "paymentExpectedMinor" IS NOT NULL;
