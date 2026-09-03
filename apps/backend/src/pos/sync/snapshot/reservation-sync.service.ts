import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../../prisma.service';
import type { TenantContext } from '../../../auth/pos-auth-context';
import type { ReservationSync } from '../sync-payload';

/**
 * Keeps Cloud's copy of a Venue's POS reservations current.
 *
 * The POS owns operational reservations and always has. What changed in Step 6C
 * is where Cloud *reads* them: it used to dial the restaurant over the LAN and
 * ask, which coupled a manager screen and a public website's availability page
 * to one PC being awake — and which a hosted Vynic could not do at all, because
 * the only addresses that path accepts are the ones it can never reach.
 *
 * So the reservations ride the snapshot the POS already pushes, and Cloud reads
 * its own table. That makes the mirror eventually consistent rather than live,
 * and the consumers are written knowing it: a booking taken at the terminal
 * while the restaurant is offline is not in here yet.
 *
 * ## Reconciliation
 *
 * A snapshot that carries reservations carries all of them, so anything absent
 * from it is gone and is deleted. A snapshot that omits the field entirely says
 * nothing about reservations and changes nothing — that is a POS build older
 * than this feature, and emptying a restaurant's mirror because its terminal
 * has not been upgraded would be the worst possible reading of silence.
 */
@Injectable()
export class ReservationSyncService {
  private readonly logger = new Logger(ReservationSyncService.name);

  constructor(private readonly prisma: PrismaService) {}

  async sync(
    tenant: Pick<TenantContext, 'venueId'>,
    reservations: ReservationSync[] | undefined,
  ): Promise<void> {
    if (!Array.isArray(reservations)) return;

    const seen = new Set<string>();
    for (const raw of reservations) {
      const posReservationId = String(raw?.id ?? '').trim();
      if (!posReservationId) continue;

      const reservationDate = parseDate(raw.reservationDate);
      if (!reservationDate) {
        this.logger.warn(
          `Reservation ${posReservationId} has no usable date; skipped.`,
        );
        continue;
      }

      const fields = {
        customerName: String(raw.customerName ?? ''),
        customerPhone: String(raw.customerPhone ?? ''),
        tableNumbers: toIntArray(raw.tableNumbers),
        tableRefs: toStringArray(raw.tableRefs),
        reservationDate,
        reservationTime: String(raw.reservationTime ?? ''),
        numberOfGuests: Number.isFinite(Number(raw.numberOfGuests))
          ? Number(raw.numberOfGuests)
          : 0,
        notes: raw.notes == null ? null : String(raw.notes),
        status: String(raw.status ?? 'pending'),
        createdBy: raw.createdBy == null ? null : String(raw.createdBy),
        isTakeAway: raw.isTakeAway === true,
        linkedOrderId:
          typeof raw.linkedOrderId === 'number' ? raw.linkedOrderId : null,
        posCreatedAt: parseDate(raw.createdAt),
      };

      try {
        await this.prisma.posReservation.upsert({
          where: {
            venueId_posReservationId: {
              venueId: tenant.venueId,
              posReservationId,
            },
          },
          update: fields,
          create: {
            venueId: tenant.venueId,
            posReservationId,
            ...fields,
          },
        });
        seen.add(posReservationId);
      } catch (error) {
        // One malformed reservation must not cost the rest of the snapshot.
        this.logger.warn(
          `Reservation ${posReservationId} failed: ${(error as Error).message}`,
        );
      }
    }

    // Reconcile. The snapshot is the complete set, so anything the POS no
    // longer holds is no longer a booking.
    const removed = await this.prisma.posReservation.deleteMany({
      where: {
        venueId: tenant.venueId,
        posReservationId: { notIn: [...seen] },
      },
    });
    if (removed.count > 0) {
      this.logger.log(
        `Venue ${tenant.venueId}: removed ${removed.count} reservation(s) the POS no longer holds`,
      );
    }
  }
}

function parseDate(raw: unknown): Date | null {
  if (typeof raw !== 'string' || raw.trim().length === 0) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function toIntArray(raw: unknown): number[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((entry) => Number(entry))
    .filter((entry) => Number.isFinite(entry))
    .map((entry) => Math.trunc(entry));
}

function toStringArray(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((entry) => String(entry).trim())
    .filter((entry) => entry.length > 0);
}
