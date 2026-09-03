-- The Cloud mirror of POS reservations (Step 6C).
--
-- Reservation reads used to be a synchronous HTTP call from a backend request
-- into a restaurant's LAN: the manager reservation list, the public website's
-- table availability, and paid-booking creation all waited on one PC being
-- awake and reachable. A hosted Vynic cannot make that call at all.
--
-- This table is where those reads go instead. The POS stays authoritative and
-- pushes its reservations in the snapshot it already sends; Cloud reads its own
-- copy. Purely additive: nothing reads it until a POS build starts filling it,
-- and an empty mirror answers the same way an unreachable POS used to.
CREATE TABLE "pos"."PosReservation" (
    "id" TEXT NOT NULL,
    "venueId" TEXT NOT NULL,
    "posReservationId" TEXT NOT NULL,
    "customerName" TEXT NOT NULL,
    "customerPhone" TEXT NOT NULL DEFAULT '',
    "tableNumbers" INTEGER[],
    "tableRefs" TEXT[],
    "reservationDate" TIMESTAMP(3) NOT NULL,
    "reservationTime" TEXT NOT NULL,
    "numberOfGuests" INTEGER NOT NULL DEFAULT 0,
    "notes" TEXT,
    "status" TEXT NOT NULL,
    "createdBy" TEXT,
    "isTakeAway" BOOLEAN NOT NULL DEFAULT false,
    "linkedOrderId" INTEGER,
    "posCreatedAt" TIMESTAMP(3),
    "syncedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PosReservation_pkey" PRIMARY KEY ("id")
);

-- Reservation identity is the POS's, scoped to the Venue that owns the POS.
-- Two restaurants may hold the same reservation id and they stay two rows.
CREATE UNIQUE INDEX "PosReservation_venueId_posReservationId_key"
    ON "pos"."PosReservation"("venueId", "posReservationId");

-- Availability is always asked per venue and per day.
CREATE INDEX "PosReservation_venueId_reservationDate_idx"
    ON "pos"."PosReservation"("venueId", "reservationDate");

ALTER TABLE "pos"."PosReservation"
    ADD CONSTRAINT "PosReservation_venueId_fkey"
    FOREIGN KEY ("venueId") REFERENCES "pos"."Venue"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
