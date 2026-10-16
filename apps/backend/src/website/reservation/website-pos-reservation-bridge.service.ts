import {
  ConflictException,
  Injectable,
  Logger,
  type OnModuleInit,
  type OnModuleDestroy,
} from '@nestjs/common';
import { PrismaService } from '../../shared/prisma/prisma.service';
import { PosCommandDispatcher } from '../../pos/pos-command-dispatcher.service';
import { PosReservationMirrorService } from '../../pos/pos-reservation-mirror.service';
import { Prisma } from '@prisma/client';
import { lockOperationalVenue } from '../../edge/operational-authority';
import type {
  WebsiteReservationWithTables,
  WebsiteTableRow,
} from './website-delivery-intent';
import { EdgeCommandTypes } from '../../shared/contracts/edge-command';
import { MonitoringGateway } from '../../realtime/monitoring.gateway';
import { suppressPosEchoForReservation } from '../../pos/sync-echo-guard';
import { MenuService } from '../menu/menu.service';
import {
  canEncodeTableCode,
  dayBounds,
  decodeTableCode,
  encodeTableCode,
  isRealPosTableBooking,
  isReservationBlocking,
  reservationDateKey,
  unavailableCodesFromPosReservations,
} from './reservation-table-codes';
import type { TenantContext } from '../../tenancy/tenant-context';

@Injectable()
export class WebsitePosReservationBridgeService
  implements OnModuleInit, OnModuleDestroy
{
  private timer?: ReturnType<typeof setInterval>;
  private running = false;

  onModuleInit() {
    this.timer = setInterval(() => {
      void this.processDue();
    }, 15_000);
    this.timer.unref();
    void this.processDue();
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }
  private readonly logger = new Logger(WebsitePosReservationBridgeService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    private readonly menuService: MenuService,
    private readonly posReservations: PosReservationMirrorService,
    private readonly posCommands: PosCommandDispatcher,
  ) {}

  encodeWebsiteTables(tables: WebsiteTableRow[]): number[] {
    return tables
      .map((table) => encodeTableCode(table.posFloor, table.posTableNumber))
      .sort((a, b) => a - b);
  }

  /** Day-level blocking — same rules as mobile manager table picker. */
  async getUnavailableTableCodesForDate(
    tenant: TenantContext,
    date: string,
    excludeWebsiteReservationId?: string,
    db: Prisma.TransactionClient = this.prisma,
  ): Promise<Set<number>> {
    const { dateKey, start, end } = dayBounds(date);
    const unavailable = new Set<number>();

    const websiteReservations = await db.websiteReservation.findMany({
      where: {
        venueId: tenant.venueId,
        date: { gte: start, lte: end },
        status: { in: ['CONFIRMED', 'PENDING'] },
        ...(excludeWebsiteReservationId
          ? { id: { not: excludeWebsiteReservationId } }
          : {}),
      },
      include: { tables: { include: { table: true } } },
    });

    const holds = await db.websiteReservationDayHold.findMany({
      where: {
        venueId: tenant.venueId,
        serviceDate: dateKey,
        status: { in: ['HELD', 'CONFIRMED'] },
        ...(excludeWebsiteReservationId
          ? { reservationId: { not: excludeWebsiteReservationId } }
          : {}),
      },
      select: { tableCode: true },
    });
    for (const hold of holds) unavailable.add(hold.tableCode);
    for (const reservation of websiteReservations) {
      if (!isReservationBlocking(reservation.status)) continue;
      for (const row of reservation.tables) {
        unavailable.add(
          encodeTableCode(row.table.posFloor, row.table.posTableNumber),
        );
      }
    }

    // Tables the POS itself has booked. This used to be an HTTP request from
    // here into the restaurant's LAN — a public availability page waiting on one
    // PC — and is now a read of the Cloud mirror the POS pushes into.
    //
    // The mirror lags, and the direction of the lag is the whole risk: a
    // booking taken at the till since the last snapshot is not in here, so this
    // set can be too small. Staleness is therefore reported rather than
    // swallowed, so the caller knows it is answering from an old picture.
    const posRows = await this.posReservations.listForDate(tenant, dateKey, db);
    const posUnavailable = unavailableCodesFromPosReservations(
      posRows as unknown as Array<Record<string, unknown>>,
      dateKey,
    );
    for (const code of posUnavailable) {
      unavailable.add(code);
    }

    const freshness = await this.posReservations.freshness(tenant, db);
    if (!freshness.fresh) {
      this.logger.warn(
        `Venue ${tenant.venueId}: reservation mirror last updated ` +
          `${freshness.syncedAt?.toISOString() ?? 'never'} — availability for ` +
          `${dateKey} is answered from a stale picture of the POS.`,
      );
    }

    return unavailable;
  }

  async fetchPosBookingsForDate(
    tenant: TenantContext,
    dateKey: string,
    linkedPosIds: Set<string>,
  ): Promise<Array<Record<string, unknown>>> {
    try {
      const posRows = await this.posReservations.listForDate(tenant, dateKey);
      return (posRows as unknown as Array<Record<string, unknown>>).filter(
        (row) => {
          const id = String(row.id ?? '').trim();
          if (!id || linkedPosIds.has(id)) return false;

          const reservationDate = String(row.reservationDate ?? '');
          const normalizedDate =
            reservationDate.length >= 10
              ? reservationDate.slice(0, 10)
              : reservationDate;
          if (normalizedDate !== dateKey) return false;

          if (!isReservationBlocking(String(row.status ?? ''))) return false;
          return isRealPosTableBooking(row);
        },
      );
    } catch (error) {
      this.logger.warn(
        `POS reservation mirror read failed for ${dateKey}: ${(error as Error).message}`,
      );
      return [];
    }
  }

  mapPosTableCodesToWebsiteTables(
    tableCodes: number[],
    websiteTables: WebsiteTableRow[],
  ): WebsiteTableRow[] {
    const byCode = new Map<number, WebsiteTableRow>();
    for (const table of websiteTables) {
      byCode.set(encodeTableCode(table.posFloor, table.posTableNumber), table);
    }

    const mapped: WebsiteTableRow[] = [];
    for (const raw of tableCodes) {
      const code =
        typeof raw === 'number' ? raw : Number.parseInt(String(raw), 10);
      if (!Number.isFinite(code)) continue;
      const table = byCode.get(code);
      if (table) mapped.push(table);
    }
    return mapped;
  }

  async areWebsiteTablesAvailable(
    tenant: TenantContext,
    tables: WebsiteTableRow[],
    date: string,
    excludeWebsiteReservationId?: string,
    db: Prisma.TransactionClient = this.prisma,
  ): Promise<boolean> {
    if (tables.length === 0) return false;
    const unavailable = await this.getUnavailableTableCodesForDate(
      tenant,
      date,
      excludeWebsiteReservationId,
      db,
    );
    const codes = this.encodeWebsiteTables(tables);
    return codes.every((code) => !unavailable.has(code));
  }

  async pushConfirmedReservationToPos(
    tenant: TenantContext,
    reservation: WebsiteReservationWithTables,
  ): Promise<string | null> {
    await this.processDue(tenant.venueId, reservation.id);
    const linked = await this.prisma.websiteReservation.findUnique({
      where: { id: reservation.id, venueId: tenant.venueId },
      select: { posReservationId: true },
    });
    return linked?.posReservationId ?? null;
  }

  async cancelPosReservation(
    tenant: TenantContext,
    posReservationId: string,
  ): Promise<void> {
    // Cancellation intent was already captured with the payment outcome.
    const booking =
      await this.prisma.websiteReservationDeliveryIntent.findFirst({
        where: {
          venueId: tenant.venueId,
          proposedPosReservationId: posReservationId,
          kind: 'CANCEL',
        },
        select: { reservationId: true },
      });
    if (booking) await this.processDue(tenant.venueId, booking.reservationId);
  }

  /** Durable restart/replica recovery. No historical booking replay. */
  async processDue(venueId?: string, reservationId?: string) {
    if (this.running) return;
    this.running = true;
    try {
      const rows = await this.prisma.websiteReservationDeliveryIntent.findMany({
        where: {
          status: 'PENDING',
          nextAttemptAt: { lte: new Date() },
          ...(venueId ? { venueId } : {}),
          ...(reservationId ? { reservationId } : {}),
        },
        orderBy: [
          { nextAttemptAt: 'asc' },
          { kind: 'desc' },
          { createdAt: 'asc' },
          { id: 'asc' },
        ],
        take: 50,
      });
      for (const row of rows) {
        try {
          await this.admitIntent(row.id, row.venueId, row.reservationId);
        } catch (error) {
          const attention = error instanceof ConflictException;
          await this.prisma.websiteReservationDeliveryIntent.updateMany({
            where: { id: row.id, status: 'PENDING' },
            data: {
              status: attention ? 'ATTENTION' : 'PENDING',
              attemptCount: { increment: 1 },
              nextAttemptAt: new Date(
                Date.now() +
                  Math.min(
                    300_000,
                    15_000 * 2 ** Math.min(row.attemptCount, 4),
                  ),
              ),
              lastErrorCode: attention
                ? 'identity_conflict'
                : 'queue_recording_failed',
            },
          });
          this.logger.error(
            `Website delivery ${row.id}: ${attention ? 'operator reconciliation required' : 'recording failed; durable retry pending'}`,
          );
        }
      }
    } catch {
      this.logger.error(
        'Website delivery worker failed; durable intents retained',
      );
    } finally {
      this.running = false;
    }
  }

  private async admitIntent(
    id: string,
    venueId: string,
    reservationId: string,
  ) {
    const admitted = await this.prisma.$transaction(
      async (tx) => {
        const venue = await lockOperationalVenue(tx, venueId);
        await tx.$queryRaw`SELECT id FROM website.reservations WHERE id=${reservationId} AND "venueId"=${venueId} FOR UPDATE`;
        const intent =
          await tx.websiteReservationDeliveryIntent.findUniqueOrThrow({
            where: { id },
          });
        if (intent.status !== 'PENDING') return null;
        const booking = await tx.websiteReservation.findUniqueOrThrow({
          where: { id: reservationId, venueId },
        });
        const tenant = { venueId, organizationId: venue.organizationId };
        const attention = (code: string) =>
          tx.websiteReservationDeliveryIntent.update({
            where: { id },
            data: { status: 'ATTENTION', lastErrorCode: code },
          });
        let payload: Record<string, unknown>;
        if (intent.kind === 'CREATE') {
          if (
            booking.posReservationId &&
            booking.posReservationId !== intent.proposedPosReservationId
          ) {
            await attention('pos_identity_conflict');
            return null;
          }
          const snapshot =
            intent.snapshot as unknown as WebsiteReservationWithTables;
          if (
            snapshot.id !== reservationId ||
            snapshot.venueId !== venueId ||
            !Array.isArray(snapshot.tables) ||
            !Number.isFinite(new Date(snapshot.date).getTime())
          ) {
            await attention('invalid_snapshot');
            return null;
          }
          const tables = snapshot.tables.map((row) => row.table);
          const serviceDate =
            snapshot.serviceDate ?? reservationDateKey(new Date(snapshot.date));
          if (
            tables.some(
              (table) =>
                !canEncodeTableCode(table.posFloor, table.posTableNumber),
            )
          ) {
            await attention('unsupported_table_identity');
            return null;
          }
          if (
            !(await this.areWebsiteTablesAvailable(
              tenant,
              tables,
              serviceDate,
              reservationId,
              tx,
            ))
          ) {
            await attention('tables_unavailable');
            return null;
          }
          payload = {
            reservationId: intent.proposedPosReservationId,
            customerName: snapshot.customerName ?? 'Website Guest',
            customerPhone: snapshot.customerPhone ?? '-',
            tableNumbers: this.encodeWebsiteTables(tables),
            reservationDate: serviceDate,
            reservationTime: snapshot.timeSlot,
            numberOfGuests:
              snapshot.numberOfGuests ??
              tables.reduce((sum, table) => sum + table.capacity, 0) ??
              2,
            notes: this.buildPosNotes(snapshot),
            createdBy: 'website',
            status: 'confirmed',
            isTakeAway: false,
            preOrderItems: await this.buildPreOrderItems(
              tenant,
              snapshot.menuItems,
              tx,
            ),
            source: 'website',
          };
        } else {
          const create = await tx.websiteReservationDeliveryIntent.findUnique({
            where: {
              venueId_reservationId_kind: {
                venueId,
                reservationId,
                kind: 'CREATE',
              },
            },
          });
          if (create) {
            if (create.status === 'ATTENTION') {
              await attention('create_unresolved');
              return null;
            }
            // Never let cancellation overtake a create that is still leased or
            // retrying. A lost ACK remains the same create identity in Edge.
            let completed = false;
            let failed = false;
            if (create.status === 'QUEUED' && create.queueId) {
              if (create.queueTransport === 'edge') {
                const receipt = await tx.edgeCommand.findFirst({
                  where: { id: create.queueId, venueId },
                  select: { status: true },
                });
                completed = receipt?.status === 'SUCCEEDED';
                failed = !receipt || receipt.status === 'FAILED';
              } else {
                const receipt = await tx.posCallbackOutbox.findFirst({
                  where: { id: create.queueId, venueId },
                  select: { status: true },
                });
                completed = receipt?.status === 'delivered';
                failed = !receipt || receipt.status === 'failed';
              }
            }
            if (failed) {
              await attention('create_outcome_unresolved');
              return null;
            }
            if (!completed) {
              await tx.websiteReservationDeliveryIntent.update({
                where: { id },
                data: {
                  nextAttemptAt: new Date(Date.now() + 15_000),
                  lastErrorCode: 'awaiting_create_ack',
                },
              });
              return null;
            }
          }
          if (
            booking.posReservationId?.trim() !== intent.proposedPosReservationId
          ) {
            await attention('pos_identity_conflict');
            return null;
          }
          payload = {
            reservationId: intent.proposedPosReservationId,
            status: 'cancelled',
            updatedBy: 'website',
            source: 'website',
            reason: 'Cancelled on the website',
          };
        }
        const command = {
          type:
            intent.kind === 'CREATE'
              ? EdgeCommandTypes.RESERVATION_CREATE
              : EdgeCommandTypes.RESERVATION_STATUS_UPDATE,
          payload,
          idempotencyKey:
            intent.kind === 'CREATE'
              ? `RESERVATION_CREATE:website:${reservationId}`
              : `RESERVATION_STATUS_UPDATE:website-cancel:${intent.proposedPosReservationId}`,
        };
        const receipt = await this.posCommands.recordWebsiteDelivery(
          tx,
          venueId,
          command,
        );
        if (!receipt) {
          await tx.websiteReservationDeliveryIntent.update({
            where: { id },
            data: {
              nextAttemptAt: new Date(Date.now() + 15_000),
              lastErrorCode: 'awaiting_pos_enrollment',
            },
          });
          return null;
        }
        if (intent.kind === 'CREATE')
          await tx.websiteReservation.update({
            where: { id: reservationId },
            data: { posReservationId: intent.proposedPosReservationId },
          });
        await tx.websiteReservationDeliveryIntent.update({
          where: { id },
          data: {
            status: 'QUEUED',
            commandPayload: payload as Prisma.InputJsonObject,
            queueTransport: receipt.transport,
            queueId: receipt.queueId,
            attemptCount: { increment: 1 },
            lastErrorCode: null,
          },
        });
        return {
          tenant,
          kind: intent.kind,
          posId: intent.proposedPosReservationId,
          transport: receipt.transport,
        };
      },
      { maxWait: 10_000, timeout: 30_000 },
    );
    if (!admitted) return;
    // Notifications are a wake-up, never the durable handoff. Do not turn their
    // failure into a retry of committed POS work.
    try {
      suppressPosEchoForReservation(admitted.tenant, admitted.posId);
      this.gateway.broadcastUpdate(admitted.tenant, 'data_updated', {
        type: 'reservations',
        action: admitted.kind === 'CREATE' ? 'created' : 'cancelled',
        source: 'website',
        websiteReservationId: reservationId,
        reservationId: admitted.posId,
      });
      if (admitted.transport === 'legacy')
        await this.posCommands.kickWebsiteLegacy(venueId);
    } catch {
      this.logger.warn(
        `Website delivery ${id}: queued; notification wake-up failed`,
      );
    }
  }

  private buildPosNotes(reservation: WebsiteReservationWithTables): string {
    const parts = ['Website booking'];
    if (reservation.customerEmail) {
      parts.push(reservation.customerEmail);
    }
    if (reservation.notes?.trim()) {
      parts.push(reservation.notes.trim());
    }
    parts.push(`web:${reservation.id}`);
    return parts.join(' • ');
  }

  private async buildPreOrderItems(
    tenant: TenantContext,
    menuItemsJson: string | null,
    db: Prisma.TransactionClient = this.prisma,
  ): Promise<Array<Record<string, unknown>>> {
    if (!menuItemsJson) return [];
    let parsed: unknown;
    try {
      parsed = JSON.parse(menuItemsJson);
    } catch {
      return [];
    }
    if (!Array.isArray(parsed)) return [];

    const items: Array<Record<string, unknown>> = [];
    for (const raw of parsed) {
      if (!raw || typeof raw !== 'object') continue;
      const entry = raw as Record<string, unknown>;
      const id = String(entry.id ?? '').trim();
      const quantity = Math.max(1, Math.floor(Number(entry.quantity) || 1));
      const price = Number(entry.price) || 0;
      let name = String(entry.name ?? '').trim();
      let menuItemId: string | null = null;
      if (!name && id) {
        const menuItem = await this.menuService.getMenuItemById(tenant, id, db);
        name =
          menuItem?.nameEn ??
          menuItem?.translations?.find((t) => t.language === 'en')?.name ??
          id;
      }
      if (id) {
        menuItemId = await this.menuService.getPosItemIdByCloudId(
          tenant,
          id,
          db,
        );
      }
      if (!name) continue;
      items.push({
        itemKey: `${name}_${price.toFixed(2)}`,
        itemName: name,
        unitPrice: price,
        quantity,
        total: price * quantity,
        comment: null,
        ...(menuItemId ? { menuItemId } : {}),
      });
    }
    return items;
  }
}

export function serializeWebsiteTableForMap(table: WebsiteTableRow) {
  return {
    id: table.id,
    tableNumber: table.websiteTableNumber,
    capacity: table.capacity,
    posFloor: table.posFloor,
    posTableNumber: table.posTableNumber,
  };
}

export function normalizeMapReservationStatus(status: string): string {
  const upper = status.trim().toUpperCase();
  if (upper === 'CONFIRMED' || upper === 'PENDING') return upper;
  if (isReservationBlocking(status)) return 'CONFIRMED';
  return upper;
}
