import {
  applyWebsitePaymentObservation,
  expireWebsiteHolds,
} from './website-booking-state';
import {
  WEBSITE_PAYMENT_WINDOW_MS,
  type WebsitePaymentEvidence,
} from '../payment/bog-payment-facts';
import { lockOperationalVenue } from '../../edge/operational-authority';
import { captureWebsiteDeliveryIntent } from './website-delivery-intent';
import {
  BadRequestException,
  Injectable,
  Inject,
  forwardRef,
  Logger,
} from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../shared/prisma/prisma.service';
import { BogService } from '../payment/payment.service';
import { bookingIntent, claimedBookingTotal } from './booking-request';
import {
  WebsitePosReservationBridgeService,
  normalizeMapReservationStatus,
  serializeWebsiteTableForMap,
} from './website-pos-reservation-bridge.service';
import {
  dayBounds,
  encodeTableCode,
  isReservationBlocking,
} from './reservation-table-codes';
import type { TenantContext } from '../../tenancy/tenant-context';

@Injectable()
export class ReservationService {
  private readonly logger = new Logger(ReservationService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(forwardRef(() => BogService))
    private readonly bogService: BogService,
    private readonly posBridge: WebsitePosReservationBridgeService,
  ) {}

  async getAllTables(tenant: TenantContext) {
    const tables = await this.prisma.websiteTable.findMany({
      where: { venueId: tenant.venueId, isActive: true },
      orderBy: { websiteTableNumber: 'asc' },
    });
    return tables.map((table) => ({
      ...table,
      tableNumber: table.websiteTableNumber,
    }));
  }

  /** Per-day availability — merges website bookings + live POS reservations. */
  async getTableAvailability(tenant: TenantContext, date: string) {
    const tables = await this.getAllTables(tenant);
    const { dateKey, start, end } = dayBounds(date);
    const unavailable = await this.posBridge.getUnavailableTableCodesForDate(
      tenant,
      dateKey,
    );

    const websiteReservations = await this.prisma.websiteReservation.findMany({
      where: {
        venueId: tenant.venueId,
        date: { gte: start, lte: end },
        status: { in: ['CONFIRMED', 'PENDING'] },
      },
      include: { tables: { include: { table: true } } },
    });

    return tables.map((table) => {
      const tableCode = encodeTableCode(table.posFloor, table.posTableNumber);
      const tableReservations = websiteReservations.filter((reservation) =>
        reservation.tables.some((rt) => rt.tableId === table.id),
      );
      const blockingSlots = tableReservations
        .filter((r) => isReservationBlocking(r.status))
        .map((r) => r.timeSlot);

      return {
        id: table.id,
        tableNumber: table.websiteTableNumber,
        posTableNumber: table.posTableNumber,
        posFloor: table.posFloor,
        posTableCode: tableCode,
        capacity: table.capacity,
        isAvailable: !unavailable.has(tableCode),
        bookedTimeSlots: blockingSlots,
        date: dateKey,
      };
    });
  }

  async isTableAvailable(
    tenant: TenantContext,
    tableNumber: string,
    date: string,
    _timeSlot?: string,
  ): Promise<boolean> {
    const table = await this.prisma.websiteTable.findUnique({
      where: {
        venueId_websiteTableNumber: {
          venueId: tenant.venueId,
          websiteTableNumber: tableNumber,
        },
      },
    });
    if (!table) return false;

    const { dateKey } = dayBounds(date);
    const unavailable = await this.posBridge.getUnavailableTableCodesForDate(
      tenant,
      dateKey,
    );
    const tableCode = encodeTableCode(table.posFloor, table.posTableNumber);
    return !unavailable.has(tableCode);
  }

  async createReservation(
    tenant: TenantContext,
    input: unknown,
    authenticatedUserId?: string,
  ) {
    const data = bookingIntent(input);
    // Scoped by Venue, so a table belonging to another restaurant simply is not
    // found — a booking can never reach across the tenant boundary.
    const tables = await this.prisma.websiteTable.findMany({
      where: {
        venueId: tenant.venueId,
        websiteTableNumber: { in: data.selectedTables },
        isActive: true,
      },
    });

    if (tables.length !== data.selectedTables.length) {
      throw new BadRequestException('One or more tables not found');
    }

    const floors = new Set(tables.map((table) => table.posFloor));
    if (floors.size > 1) {
      throw new BadRequestException(
        'Please select tables from the same floor only',
      );
    }

    const numberOfGuests =
      data.numberOfGuests ??
      tables.reduce((sum, table) => sum + table.capacity, 0);

    const priced = await this.bogService.validateAndCalculateOrder(
      tenant,
      data,
    );
    const paymentIntegrationId = await this.bogService.preparePayment(tenant);
    const tableCodes = tables.map((table) =>
      encodeTableCode(table.posFloor, table.posTableNumber),
    );
    if (new Set(tableCodes).size !== tables.length)
      throw new BadRequestException(
        'The same physical table was selected more than once',
      );
    const reservation = await this.prisma.$transaction(
      async (tx) => {
        await lockOperationalVenue(tx, tenant.venueId);
        await expireWebsiteHolds(tx, tenant.venueId, new Date());
        const conflict = await tx.websiteReservationDayHold.findFirst({
          where: {
            venueId: tenant.venueId,
            serviceDate: data.selectedDate,
            tableCode: { in: tableCodes },
            status: { in: ['HELD', 'CONFIRMED'] },
          },
        });
        const available =
          !conflict &&
          (await this.posBridge.areWebsiteTablesAvailable(
            tenant,
            tables,
            data.selectedDate,
            undefined,
            tx,
          ));
        if (!available)
          throw new BadRequestException(
            'One or more selected tables are already booked on this date',
          );
        const windowStartedAt = new Date();
        const created = await tx.websiteReservation.create({
          data: {
            paymentIntegrationId,
            venueId: tenant.venueId,
            date: new Date(dayBounds(data.selectedDate).start),
            timeSlot: data.selectedTime,
            customerName: data.customerName,
            customerEmail: data.customerEmail,
            customerPhone: data.customerPhone,
            userId: authenticatedUserId,
            notes: data.notes,
            status: 'PENDING',
            paymentState: 'PENDING',
            paymentExpectedMinor: String(priced.payment.amountMinor),
            paymentCurrency: priced.payment.currency,
            holdState: 'HELD',
            paymentWindowStartedAt: windowStartedAt,
            holdExpiresAt: new Date(
              windowStartedAt.getTime() + WEBSITE_PAYMENT_WINDOW_MS,
            ),
            nextPaymentCheckAt: new Date(Date.now() + 60_000),
            totalAmount: priced.totalAmount,
            numberOfGuests,
            menuItems: JSON.stringify(priced.menuItems),
            dayHolds: {
              create: tableCodes.map((tableCode) => ({
                serviceDate: data.selectedDate,
                tableCode,
              })),
            },
            tables: {
              create: tables.map((table) => ({ tableId: table.id })),
            },
          },
          include: {
            tables: { include: { table: true } },
            user: true,
          },
        });

        return created;
      },
      { maxWait: 10_000, timeout: 30_000 },
    );

    let bogOrder: Awaited<ReturnType<BogService['createOrder']>>;
    try {
      bogOrder = await this.bogService.createOrder(
        tenant,
        paymentIntegrationId,
        reservation.id,
        priced.payment,
        data.language || 'en',
      );
      await this.prisma.$transaction(async (tx) => {
        await lockOperationalVenue(tx, tenant.venueId);
        const current = await tx.websiteReservation.findUniqueOrThrow({
          where: { id: reservation.id, venueId: tenant.venueId },
        });
        if (current.paymentId && current.paymentId !== bogOrder.id)
          throw new BadRequestException('Payment reference mismatch');
        await tx.websiteReservation.update({
          where: { id: reservation.id },
          data: { paymentId: bogOrder.id },
        });
      });
    } catch (error) {
      await this.prisma.$transaction(async (tx) => {
        await lockOperationalVenue(tx, tenant.venueId);
        if (error instanceof BadRequestException) {
          // Release only a still-unbound hold. A callback may already have
          // pinned a bank identity before the create reply arrives.
          const failed = await tx.websiteReservation.updateMany({
            where: { id: reservation.id, paymentId: null, holdState: 'HELD' },
            data: {
              paymentState: 'DECLINED',
              status: 'FAILED',
              holdState: 'RELEASED',
              nextPaymentCheckAt: null,
            },
          });
          if (failed.count)
            await tx.websiteReservationDayHold.updateMany({
              where: {
                reservationId: reservation.id,
                venueId: tenant.venueId,
                status: 'HELD',
              },
              data: { status: 'RELEASED' },
            });
        } else {
          // A lost provider reply does not prove that no order exists.
          await tx.websiteReservation.updateMany({
            where: { id: reservation.id, paymentId: null },
            data: {
              paymentState: 'REVIEW',
              paymentReviewReason: 'order_creation_outcome_unknown',
            },
          });
        }
      });
      throw error;
    }

    return {
      success: true,
      message: 'Reservation created, waiting for payment',
      reservation: {
        id: reservation.id,
        date: reservation.date,
        timeSlot: reservation.timeSlot,
        customerInfo: {
          name: reservation.customerName,
          email: reservation.customerEmail,
          phone: reservation.customerPhone,
        },
        tables: reservation.tables.map((rt) => ({
          id: rt.table.id,
          tableNumber: rt.table.websiteTableNumber,
          posTableNumber: rt.table.posTableNumber,
          posFloor: rt.table.posFloor,
          capacity: rt.table.capacity,
        })),
        menuItems: priced.menuItems,
        totalAmount: reservation.totalAmount,
        status: reservation.status,
        notes: reservation.notes,
        numberOfGuests,
      },
      validation: {
        serverCalculatedTotal: priced.totalAmount,
        subtotal: priced.subtotal,
        serviceFee: priced.serviceFee,
        validatedItems: priced.menuItems,
        priceManipulationDetected:
          claimedBookingTotal(input) !== priced.totalAmount,
      },
      paymentUrl: bogOrder?._links?.redirect?.href,
    };
  }

  async getReservationsForDate(tenant: TenantContext, date: string) {
    const { start, end } = dayBounds(date);

    const rows = await this.prisma.websiteReservation.findMany({
      where: { venueId: tenant.venueId, date: { gte: start, lte: end } },
      include: {
        tables: { include: { table: true } },
        user: true,
      },
      orderBy: [{ timeSlot: 'asc' }, { id: 'asc' }],
    });

    return rows.map((row) => this.serializeWebsiteReservationForMap(row));
  }

  /**
   * Legacy shape for the public 3D map — merges website DB + live POS bookings.
   * Frontend expects: [{ id, status, timeSlot, tables: [{ table: { tableNumber } }] }]
   */
  async getPublicMapReservations(tenant: TenantContext, date: string) {
    const { dateKey, start, end } = dayBounds(date);
    const websiteTables = await this.prisma.websiteTable.findMany({
      where: { venueId: tenant.venueId, isActive: true },
    });

    const websiteRows = await this.prisma.websiteReservation.findMany({
      where: {
        venueId: tenant.venueId,
        date: { gte: start, lte: end },
        status: { in: ['CONFIRMED', 'PENDING'] },
      },
      include: { tables: { include: { table: true } } },
      orderBy: [{ timeSlot: 'asc' }, { id: 'asc' }],
    });

    const linkedPosIds = new Set(
      websiteRows
        .map((row) => row.posReservationId?.trim())
        .filter((id): id is string => Boolean(id)),
    );

    const results = websiteRows
      .filter((row) => isReservationBlocking(row.status))
      .map((row) => this.serializeWebsiteReservationForMap(row));

    const posRows = await this.posBridge.fetchPosBookingsForDate(
      tenant,
      dateKey,
      linkedPosIds,
    );

    for (const pos of posRows) {
      const tableCodes = ((pos.tableNumbers as unknown[]) ?? [])
        .map((raw) =>
          typeof raw === 'number' ? raw : Number.parseInt(String(raw), 10),
        )
        .filter((code) => Number.isFinite(code) && code > 0);

      const mappedTables = this.posBridge.mapPosTableCodesToWebsiteTables(
        tableCodes,
        websiteTables,
      );
      if (mappedTables.length === 0) continue;

      const reservationDate = String(pos.reservationDate ?? dateKey);
      results.push({
        id: String(pos.id ?? ''),
        date: reservationDate,
        timeSlot: String(pos.reservationTime ?? ''),
        status: normalizeMapReservationStatus(
          String(pos.status ?? 'confirmed'),
        ),
        customerName: String(pos.customerName ?? ''),
        customerPhone: String(pos.customerPhone ?? ''),
        numberOfGuests: Number(pos.numberOfGuests ?? 0) || null,
        posReservationId: null,
        source: 'pos',
        tables: mappedTables.map((table) => ({
          table: serializeWebsiteTableForMap(table),
        })),
      });
    }

    // Anonymous visitors need occupancy, not other guests' names or phones.
    return results.map((row) => ({
      ...row,
      customerName: null,
      customerPhone: null,
    }));
  }

  private serializeWebsiteReservationForMap(reservation: {
    id: string;
    date: Date | string;
    timeSlot: string;
    status: string;
    customerName: string | null;
    customerPhone: string | null;
    numberOfGuests: number | null;
    posReservationId?: string | null;
    tables: Array<{ table: Parameters<typeof serializeWebsiteTableForMap>[0] }>;
  }) {
    return {
      id: reservation.id,
      date: reservation.date,
      timeSlot: reservation.timeSlot,
      status: normalizeMapReservationStatus(reservation.status),
      customerName: reservation.customerName,
      customerPhone: reservation.customerPhone,
      numberOfGuests: reservation.numberOfGuests,
      posReservationId: reservation.posReservationId ?? null,
      source: 'website',
      tables: reservation.tables.map((row) => ({
        table: serializeWebsiteTableForMap(row.table),
      })),
    };
  }

  /**
   * Applies a payment outcome to a booking.
   *
   * Reached from BOG status checks and from the bank's callback, neither of
   * which carries the website host. The tenant is therefore taken from the
   * server-owned reservation row itself — the provider names a reservation, and
   * the reservation names its Venue.
   */
  async updateReservationPaymentStatus(
    reservationId: string,
    paymentStatus: string,
    paymentDescription: string,
    paymentId: string,
    evidence?: WebsitePaymentEvidence,
  ) {
    void paymentStatus; // Financial status comes from verified provider facts.
    void paymentDescription;
    // Payment identity supplies the tenant; no host/client tenant is trusted.
    const identity = await this.prisma.websiteReservation.findUnique({
      where: { id: reservationId },
      select: { venueId: true },
    });
    if (!identity)
      throw new BadRequestException(`Reservation ${reservationId} not found`);
    const { updated, tenant, cancelId } = await this.prisma.$transaction(
      async (tx) => {
        const venue = await lockOperationalVenue(tx, identity.venueId);
        await tx.$queryRaw`SELECT id FROM website.reservations WHERE id=${reservationId} AND "venueId"=${venue.id} FOR UPDATE`;
        const existing = await tx.websiteReservation.findUniqueOrThrow({
          where: { id: reservationId, venueId: venue.id },
          include: { tables: { include: { table: true } } },
        });
        if (
          !paymentId ||
          !existing.paymentIntegrationId ||
          (existing.paymentId && existing.paymentId !== paymentId)
        ) {
          throw new BadRequestException('Payment reference mismatch');
        }
        await expireWebsiteHolds(tx, venue.id, new Date());
        const current = await tx.websiteReservation.findUniqueOrThrow({
          where: { id: reservationId, venueId: venue.id },
          include: { tables: { include: { table: true } } },
        });
        const updated = await applyWebsitePaymentObservation(
          tx,
          current,
          paymentId,
          evidence ?? {
            source: 'RECONCILE',
            observedAt: new Date(),
            receipt: null,
          },
        );
        // Money outcome and durable handoff cannot commit independently. Historical
        // POS links are deliberately not replayed: their outcome is unknown.
        await captureWebsiteDeliveryIntent(
          tx,
          updated,
          existing.status !== 'CONFIRMED' && updated.status === 'CONFIRMED',
        );
        const cancel = await tx.websiteReservationDeliveryIntent.findUnique({
          where: {
            venueId_reservationId_kind: {
              venueId: venue.id,
              reservationId,
              kind: 'CANCEL',
            },
          },
        });
        return {
          updated,
          tenant: { venueId: venue.id, organizationId: venue.organizationId },
          cancelId: cancel?.proposedPosReservationId ?? null,
        };
      },
    );
    // Best-effort wake-up only. A crash here is recovered by the intent worker.
    try {
      if (updated.status === 'CONFIRMED' && !updated.posReservationId)
        await this.posBridge.pushConfirmedReservationToPos(tenant, updated);
      if (updated.status === 'FAILED' && cancelId)
        await this.posBridge.cancelPosReservation(tenant, cancelId);
    } catch {
      this.logger.error(
        `Website reservation ${reservationId}: durable POS handoff pending; worker will reconcile`,
      );
    }
    return updated;
  }

  async getPaymentIdByReservationId(
    reservationId: string,
    venueId: string,
  ): Promise<string | null> {
    const reservation = await this.prisma.websiteReservation.findUnique({
      where: { id: reservationId, venueId },
      select: { paymentId: true },
    });
    return reservation?.paymentId || null;
  }

  @Cron(CronExpression.EVERY_MINUTE)
  async cleanupExpiredPendingReservations() {
    const venues = await this.prisma.websiteReservation.findMany({
      where: { holdState: 'HELD', holdExpiresAt: { lte: new Date() } },
      distinct: ['venueId'],
      select: { venueId: true },
      take: 100,
    });
    for (const row of venues)
      await this.prisma.$transaction(async (tx) => {
        await lockOperationalVenue(tx, row.venueId);
        await expireWebsiteHolds(tx, row.venueId, new Date());
      });
    // Preserve the prior legacy pending timeout without inventing old holds or prices.
    await this.prisma.websiteReservation.updateMany({
      where: {
        status: 'PENDING',
        holdState: null,
        createdAt: { lt: new Date(Date.now() - WEBSITE_PAYMENT_WINDOW_MS) },
      },
      data: {
        status: 'FAILED',
        paymentState: 'REVIEW',
        paymentReviewReason: 'historical_payment_snapshot_missing',
      },
    });
  }

  @Cron(CronExpression.EVERY_MINUTE)
  async reconcileOutstandingPayments() {
    const rows = await this.prisma.websiteReservation.findMany({
      where: {
        OR: [
          { paymentId: { not: null } },
          { paymentObservations: { some: { source: 'CALLBACK' } } },
        ],
        nextPaymentCheckAt: { lte: new Date() },
      },
      orderBy: [{ nextPaymentCheckAt: 'asc' }, { id: 'asc' }],
      take: 30,
      select: {
        id: true,
        paymentId: true,
        paymentObservations: {
          where: { source: 'CALLBACK' },
          orderBy: { createdAt: 'desc' },
          take: 1,
          select: { paymentId: true },
        },
      },
    });
    for (const row of rows) {
      const paymentId = row.paymentId ?? row.paymentObservations[0]?.paymentId;
      if (!paymentId) continue;
      try {
        const receipt = await this.bogService.getPaymentDetailsForReservation(
          row.id,
          paymentId,
        );
        await this.updateReservationPaymentStatus(row.id, '', '', paymentId, {
          source: 'RECONCILE',
          observedAt: new Date(),
          receipt,
        });
      } catch {
        await this.prisma.websiteReservation.updateMany({
          where: { id: row.id, nextPaymentCheckAt: { lte: new Date() } },
          data: {
            paymentReviewReason: 'provider_receipt_unavailable',
            nextPaymentCheckAt: new Date(Date.now() + 5 * 60_000),
          },
        });
        this.logger.warn(
          `Website payment ${row.id}: receipt reconciliation unavailable; operator review retained`,
        );
      }
    }
  }
}
