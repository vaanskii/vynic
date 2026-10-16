-- CreateTable
CREATE TABLE "pos"."WebsiteReservationDeliveryIntent" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "reservationId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "proposedPosReservationId" TEXT NOT NULL,
    "snapshot" JSONB NOT NULL,
    "commandPayload" JSONB,
    "queueTransport" TEXT,
    "queueId" TEXT,
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "nextAttemptAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastErrorCode" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "WebsiteReservationDeliveryIntent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "WebsiteReservationDeliveryIntent_status_nextAttemptAt_idx" ON "pos"."WebsiteReservationDeliveryIntent"("status", "nextAttemptAt");

-- CreateIndex
CREATE INDEX "WebsiteReservationDeliveryIntent_venueId_proposedPosReserva_idx" ON "pos"."WebsiteReservationDeliveryIntent"("venueId", "proposedPosReservationId");

-- CreateIndex
CREATE UNIQUE INDEX "WebsiteReservationDeliveryIntent_venueId_reservationId_kind_key" ON "pos"."WebsiteReservationDeliveryIntent"("venueId", "reservationId", "kind");

-- CreateIndex
CREATE UNIQUE INDEX "reservations_id_venueId_key" ON "website"."reservations"("id", "venueId");

-- AddForeignKey
ALTER TABLE "pos"."WebsiteReservationDeliveryIntent" ADD CONSTRAINT "WebsiteReservationDeliveryIntent_venueId_fkey" FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."WebsiteReservationDeliveryIntent" ADD CONSTRAINT "WebsiteReservationDeliveryIntent_reservationId_venueId_fkey" FOREIGN KEY ("reservationId", "venueId") REFERENCES "website"."reservations"("id", "venueId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- No historical rows are backfilled. Their delivery outcome requires inspection.
CREATE UNIQUE INDEX website_delivery_create_pos_identity ON pos."WebsiteReservationDeliveryIntent" ("venueId", "proposedPosReservationId") WHERE kind='CREATE';
ALTER TABLE pos."WebsiteReservationDeliveryIntent" ADD CONSTRAINT website_delivery_shape CHECK (
  kind IN ('CREATE','CANCEL') AND status IN ('PENDING','QUEUED','ATTENTION') AND "attemptCount">=0
  AND ((status='QUEUED' AND "queueTransport" IS NOT NULL AND "queueTransport" IN ('edge','legacy') AND "queueId" IS NOT NULL AND "commandPayload" IS NOT NULL)
    OR (status<>'QUEUED' AND "queueTransport" IS NULL AND "queueId" IS NULL AND "commandPayload" IS NULL))
);
CREATE FUNCTION pos.website_delivery_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.id, NEW."venueId", NEW."reservationId", NEW.kind, NEW."proposedPosReservationId", NEW.snapshot, NEW."createdAt")
    IS DISTINCT FROM (OLD.id, OLD."venueId", OLD."reservationId", OLD.kind, OLD."proposedPosReservationId", OLD.snapshot, OLD."createdAt")
    OR (OLD.status IN ('QUEUED','ATTENTION') AND NEW IS DISTINCT FROM OLD) THEN
    RAISE EXCEPTION 'Website delivery intent is immutable' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER website_delivery_immutable BEFORE UPDATE ON pos."WebsiteReservationDeliveryIntent" FOR EACH ROW EXECUTE FUNCTION pos.website_delivery_immutable();
-- Protect only receipts owned by this outbox. Generic command retry behavior
-- remains available for unrelated commands, but cannot revive paid booking work.
CREATE FUNCTION pos.website_delivery_receipt_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME='EdgeCommand' THEN
    IF EXISTS (SELECT 1 FROM pos."WebsiteReservationDeliveryIntent" i WHERE i."queueTransport"='edge' AND i."queueId"=OLD.id AND i."venueId"=OLD."venueId") THEN
      IF (NEW."venueId",NEW."deviceId",NEW.type,NEW."contractVersion",NEW.payload,NEW."idempotencyKey") IS DISTINCT FROM (OLD."venueId",OLD."deviceId",OLD.type,OLD."contractVersion",OLD.payload,OLD."idempotencyKey")
        OR (OLD.status IN ('SUCCEEDED','FAILED') AND NEW.status IS DISTINCT FROM OLD.status) THEN
        RAISE EXCEPTION 'Website delivery receipt cannot be rewritten or revived' USING ERRCODE='23514';
      END IF;
    END IF;
  ELSE
    IF EXISTS (SELECT 1 FROM pos."WebsiteReservationDeliveryIntent" i WHERE i."queueTransport"='legacy' AND i."queueId"=OLD.id AND i."venueId"=OLD."venueId") THEN
      IF (NEW."venueId",NEW.endpoint,NEW.payload,NEW."dedupeKey") IS DISTINCT FROM (OLD."venueId",OLD.endpoint,OLD.payload,OLD."dedupeKey")
        OR (OLD.status IN ('delivered','failed') AND NEW.status IS DISTINCT FROM OLD.status) THEN
        RAISE EXCEPTION 'Website delivery receipt cannot be rewritten or revived' USING ERRCODE='23514';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER website_delivery_receipt_immutable BEFORE UPDATE ON pos."EdgeCommand" FOR EACH ROW EXECUTE FUNCTION pos.website_delivery_receipt_immutable();
CREATE TRIGGER website_delivery_receipt_immutable BEFORE UPDATE ON pos."PosCallbackOutbox" FOR EACH ROW EXECUTE FUNCTION pos.website_delivery_receipt_immutable();
