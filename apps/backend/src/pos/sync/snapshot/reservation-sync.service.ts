import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
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
    failOnError = false,
  ): Promise<{ complete: boolean }> {
    if (!Array.isArray(reservations)) return { complete: false };
    let complete = true;

    const seen = new Set<string>();
    for (const raw of reservations) {
      const posReservationId = String(raw?.id ?? '').trim();
      if (!posReservationId) {
        complete = false;
        continue;
      }

      const reservationDate = parseDate(raw.reservationDate);
      if (!reservationDate) {
        complete = false;
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
        const write = async (
          db: Pick<Prisma.TransactionClient, 'posReservation'>,
        ) => {
          const advance = await this.advanceFields(
            db,
            tenant.venueId,
            posReservationId,
            raw,
          );
          await db.posReservation.upsert({
            where: {
              venueId_posReservationId: {
                venueId: tenant.venueId,
                posReservationId,
              },
            },
            update: { ...fields, ...advance },
            create: {
              venueId: tenant.venueId,
              posReservationId,
              ...fields,
              ...advance,
            },
          });
        };
        if (raw.advanceAmount !== undefined) {
          const lockedWrite = async (tx: Prisma.TransactionClient) => {
            await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${tenant.venueId} FOR UPDATE`;
            await write(tx);
          };
          // Snapshot ingest supplies its already-open transaction client.
          if (typeof this.prisma.$transaction === 'function') {
            await this.prisma.$transaction(lockedWrite);
          } else await lockedWrite(this.prisma);
        } else await write(this.prisma);
        seen.add(posReservationId);
      } catch (error) {
        // Refusing new money metadata must not delete a retained booking.
        seen.add(posReservationId);
        complete = false;
        if (failOnError) throw error;
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
    return { complete };
  }

  private async advanceFields(
    db: Pick<Prisma.TransactionClient, 'posReservation'>,
    venueId: string,
    posReservationId: string,
    raw: ReservationSync,
  ) {
    // Absence from an older POS says nothing about an already recorded receipt.
    if (raw.advanceAmount === undefined) return {};
    const amount = raw.advanceAmount;
    if (
      typeof amount !== 'number' ||
      !Number.isFinite(amount) ||
      amount < 0 ||
      amount > 999999999.99 ||
      Math.abs(amount * 100 - Math.round(amount * 100)) > 0.0001
    ) {
      throw new BadRequestException(
        'Reservation advance must be a non-negative cent amount',
      );
    }
    const date = raw.advanceCollectedOn ?? null;
    const receiptId = raw.advanceReceiptId ?? null;
    if (
      amount > 0 &&
      (typeof date !== 'string' ||
        !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
        typeof receiptId !== 'string' ||
        !receiptId.trim() ||
        receiptId.length > 200)
    ) {
      throw new BadRequestException(
        'Reservation advance receipt identity/date are required',
      );
    }
    if (amount === 0 && (date !== null || receiptId !== null)) {
      throw new BadRequestException(
        'A zero reservation advance cannot carry a receipt',
      );
    }
    if (date !== null) {
      const collectionDate = new Date(`${date}T00:00:00Z`);
      if (
        !Number.isFinite(collectionDate.getTime()) ||
        collectionDate.toISOString().slice(0, 10) !== date
      ) {
        throw new BadRequestException(
          'Reservation advance collection date is invalid',
        );
      }
    }
    const decimal = new Prisma.Decimal(amount.toFixed(2));
    const old = await db.posReservation.findUnique({
      where: { venueId_posReservationId: { venueId, posReservationId } },
      select: {
        advanceAmount: true,
        advanceCollectedOn: true,
        advanceReceiptId: true,
      },
    });
    if (
      old?.advanceAmount.gt(0) &&
      (!old.advanceAmount.equals(decimal) ||
        old.advanceCollectedOn !== date ||
        old.advanceReceiptId !== receiptId)
    ) {
      throw new BadRequestException(
        'A recorded reservation advance cannot be rewritten by a snapshot',
      );
    }
    return {
      advanceAmount: decimal,
      advanceCollectedOn: date,
      advanceReceiptId: receiptId,
    };
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
