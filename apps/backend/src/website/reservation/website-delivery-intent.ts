import { Prisma } from '@prisma/client';
import { allocatePosReservationId } from '../../pos/pos-reservation-id';

export type WebsiteTableRow = {
  id: number;
  websiteTableNumber: string;
  posTableNumber: string;
  posFloor: string;
  capacity: number;
};
export type WebsiteReservationWithTables = {
  id: string;
  venueId: string;
  date: Date;
  serviceDate?: string;
  timeSlot: string;
  status: string;
  customerName: string | null;
  customerPhone: string | null;
  customerEmail: string | null;
  notes: string | null;
  menuItems: string | null;
  numberOfGuests: number | null;
  posReservationId: string | null;
  tables: Array<{ table: WebsiteTableRow }>;
};

/** Called only under Venue -> booking locks, in the payment outcome transaction. */
export async function captureWebsiteDeliveryIntent(
  tx: Prisma.TransactionClient,
  reservation: WebsiteReservationWithTables,
  firstConfirmation: boolean,
) {
  const intents = await tx.websiteReservationDeliveryIntent.findMany({
    where: { venueId: reservation.venueId, reservationId: reservation.id },
  });
  const create = intents.find((row) => row.kind === 'CREATE');
  if (
    firstConfirmation &&
    reservation.status === 'CONFIRMED' &&
    !reservation.posReservationId &&
    !create
  ) {
    let posId: string;
    let allocations = 0;
    // Venue lock serializes allocations. Retain every intent's identity, even
    // before admission and after failure, so another booking cannot reuse it.
    do {
      if (++allocations > 1000)
        throw new Error('Website POS identity allocation exhausted');
      posId = allocatePosReservationId();
    } while (
      (await tx.websiteReservation.count({
        where: { venueId: reservation.venueId, posReservationId: posId },
      })) ||
      (await tx.websiteReservationDeliveryIntent.count({
        where: {
          venueId: reservation.venueId,
          proposedPosReservationId: posId,
        },
      }))
    );
    const dayHold = await tx.websiteReservationDayHold.findFirst({
      where: { venueId: reservation.venueId, reservationId: reservation.id },
      select: { serviceDate: true },
    });
    await tx.websiteReservationDeliveryIntent.create({
      data: {
        venueId: reservation.venueId,
        reservationId: reservation.id,
        kind: 'CREATE',
        proposedPosReservationId: posId,
        snapshot: JSON.parse(
          JSON.stringify({
            ...reservation,
            ...(dayHold ? { serviceDate: dayHold.serviceDate } : {}),
          }),
        ) as Prisma.InputJsonObject,
      },
    });
  }
  const cancelId = (
    reservation.posReservationId ?? create?.proposedPosReservationId
  )?.trim();
  if (
    reservation.status === 'FAILED' &&
    cancelId &&
    !intents.some((row) => row.kind === 'CANCEL')
  ) {
    await tx.websiteReservationDeliveryIntent.create({
      data: {
        venueId: reservation.venueId,
        reservationId: reservation.id,
        kind: 'CANCEL',
        proposedPosReservationId: cancelId,
        snapshot: {},
      },
    });
  }
}
