import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../auth/pos-auth-context';

/** One reservation, in the shape the LAN read used to return. */
export interface MirroredPosReservation {
  id: string;
  customerName: string;
  customerPhone: string;
  tableNumbers: number[];
  tableRefs: string[];
  reservationDate: string;
  reservationTime: string;
  numberOfGuests: number;
  notes?: string;
  status: string;
  createdBy?: string;
  isTakeAway: boolean;
  linkedOrderId: number | null;
}

export interface MirrorFreshness {
  /** When the newest reservation row for this Venue was last written. */
  syncedAt: Date | null;
  /** Whether that is recent enough to answer an availability question with. */
  fresh: boolean;
}

/**
 * How stale the mirror may be before a caller should stop trusting it.
 *
 * The POS pushes a full snapshot on every local change and on a periodic
 * failsafe, so a healthy restaurant refreshes this far more often than this. A
 * gap this long means the terminal has been unreachable through several sync
 * attempts, which is the case where a booking taken at the till is not in here.
 */
const FRESHNESS_WINDOW_MS = 10 * 60_000;

/**
 * Reads a Venue's reservations from the Cloud mirror.
 *
 * ## What this replaced, and why
 *
 * Every one of these reads used to be `GET /mobile-reservations` on the POS's
 * own HTTP server, dialled from a backend request. Three things were wrong with
 * that. A hosted Vynic has no route to `192.168.1.50`, so it could not be done
 * at all once Cloud moved off the LAN. A public website's availability page hung
 * on one restaurant PC answering. And a work queue does not fix it — a queue
 * delivers instructions, it does not answer questions — so the answer had to be
 * a mirror rather than a new command type.
 *
 * ## What a caller must know
 *
 * This is a mirror, not the source. The POS owns reservations and pushes them;
 * Cloud reads its copy. So the copy lags, and the direction of the lag matters:
 * a reservation cancelled at the till while the restaurant was offline still
 * blocks its table here, which is the safe error, while a reservation *taken* at
 * the till is missing, which is not. [freshness] is how a caller finds out which
 * situation it is in, and availability callers are expected to use it rather
 * than quietly treating a stale mirror as an empty restaurant.
 */
@Injectable()
export class PosReservationMirrorService {
  constructor(private readonly prisma: PrismaService) {}

  /** Every reservation Cloud holds for this Venue. */
  async listAll(
    tenant: Pick<TenantContext, 'venueId'>,
  ): Promise<MirroredPosReservation[]> {
    const rows = await this.prisma.posReservation.findMany({
      where: { venueId: tenant.venueId },
      orderBy: [{ reservationDate: 'asc' }, { reservationTime: 'asc' }],
    });
    return rows.map(toWireShape);
  }

  /** The reservations for one calendar day, by the POS's own date field. */
  async listForDate(
    tenant: Pick<TenantContext, 'venueId'>,
    dateKey: string,
  ): Promise<MirroredPosReservation[]> {
    const start = new Date(`${dateKey}T00:00:00.000Z`);
    if (Number.isNaN(start.getTime())) return [];
    const end = new Date(start.getTime() + 24 * 60 * 60_000 - 1);

    const rows = await this.prisma.posReservation.findMany({
      where: {
        venueId: tenant.venueId,
        reservationDate: { gte: start, lte: end },
      },
      orderBy: { reservationTime: 'asc' },
    });
    return rows.map(toWireShape);
  }

  /**
   * How current this Venue's mirror is.
   *
   * A Venue with no reservations at all has no row to date, and that is
   * reported as unknown rather than stale: an empty restaurant is a legitimate
   * state and must not read as a broken one.
   */
  async freshness(
    tenant: Pick<TenantContext, 'venueId'>,
  ): Promise<MirrorFreshness> {
    const newest = await this.prisma.posReservation.findFirst({
      where: { venueId: tenant.venueId },
      orderBy: { syncedAt: 'desc' },
      select: { syncedAt: true },
    });
    if (!newest) return { syncedAt: null, fresh: true };
    return {
      syncedAt: newest.syncedAt,
      fresh: Date.now() - newest.syncedAt.getTime() <= FRESHNESS_WINDOW_MS,
    };
  }
}

function toWireShape(row: {
  posReservationId: string;
  customerName: string;
  customerPhone: string;
  tableNumbers: number[];
  tableRefs: string[];
  reservationDate: Date;
  reservationTime: string;
  numberOfGuests: number;
  notes: string | null;
  status: string;
  createdBy: string | null;
  isTakeAway: boolean;
  linkedOrderId: number | null;
}): MirroredPosReservation {
  return {
    id: row.posReservationId,
    customerName: row.customerName,
    customerPhone: row.customerPhone,
    tableNumbers: row.tableNumbers,
    tableRefs: row.tableRefs,
    // The POS sends a full ISO timestamp and the availability rules compare the
    // date half, so the wire shape keeps the timestamp exactly as it arrived.
    reservationDate: row.reservationDate.toISOString(),
    reservationTime: row.reservationTime,
    numberOfGuests: row.numberOfGuests,
    notes: row.notes ?? undefined,
    status: row.status,
    createdBy: row.createdBy ?? undefined,
    isTakeAway: row.isTakeAway,
    linkedOrderId: row.linkedOrderId,
  };
}
