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
    data: {
      selectedTables: string[];
      selectedDate: string;
      selectedTime: string;
      menuItems?: Array<{ id: string; quantity: number; price: number }>;
      totalAmount?: number;
      customerName?: string;
      customerEmail?: string;
      customerPhone?: string;
      userId?: string;
      notes?: string;
      language?: string;
      numberOfGuests?: number;
    },
  ) {
    // Scoped by Venue, so a table belonging to another restaurant simply is not
    // found — a booking can never reach across the tenant boundary.
    const tables = await this.prisma.websiteTable.findMany({
      where: {
        venueId: tenant.venueId,
        websiteTableNumber: { in: data.selectedTables },
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

    const available = await this.posBridge.areWebsiteTablesAvailable(
      tenant,
      tables,
      data.selectedDate,
    );
    if (!available) {
      throw new BadRequestException(
        'One or more selected tables are already booked on this date',
      );
    }

    const numberOfGuests =
      data.numberOfGuests ??
      tables.reduce((sum, table) => sum + table.capacity, 0);

    const reservation = await this.prisma.websiteReservation.create({
      data: {
        venueId: tenant.venueId,
        date: new Date(dayBounds(data.selectedDate).start),
        timeSlot: data.selectedTime,
        customerName: data.customerName,
        customerEmail: data.customerEmail,
        customerPhone: data.customerPhone,
        userId: data.userId,
        notes: data.notes,
        status: 'PENDING',
        totalAmount: data.totalAmount || 0,
        numberOfGuests,
        menuItems: data.menuItems ? JSON.stringify(data.menuItems) : null,
        tables: {
          create: tables.map((table) => ({ tableId: table.id })),
        },
      },
      include: {
        tables: { include: { table: true } },
        user: true,
      },
    });

    const bogOrder = await this.bogService.createOrder(
      reservation.id,
      reservation.totalAmount || 0,
      data.language || 'en',
    );

    if (bogOrder?.id) {
      await this.prisma.websiteReservation.update({
        where: { id: reservation.id },
        data: { paymentId: bogOrder.id },
      });
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
        menuItems: data.menuItems || [],
        totalAmount: reservation.totalAmount,
        status: reservation.status,
        notes: reservation.notes,
        numberOfGuests,
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

    return results;
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
  ) {
    const confirmedStatuses = [
      'completed',
      'partial_completed',
      'auth_requested',
    ];
    const failedStatuses = ['rejected', 'refunded', 'refunded_partially'];
    const normalized = paymentStatus.toLowerCase();
    const status = confirmedStatuses.includes(normalized)
      ? 'CONFIRMED'
      : failedStatuses.includes(normalized)
        ? 'FAILED'
        : 'PENDING';

    const existing = await this.prisma.websiteReservation.findUnique({
      where: { id: reservationId },
      include: {
        tables: { include: { table: true } },
        venue: { select: { organizationId: true } },
      },
    });
    if (!existing) {
      throw new BadRequestException(`Reservation ${reservationId} not found`);
    }

    const tenant: TenantContext = {
      venueId: existing.venueId,
      organizationId: existing.venue.organizationId,
    };

    const updated = await this.prisma.websiteReservation.update({
      where: { id: reservationId },
      data: {
        paymentStatus,
        notes: paymentDescription,
        paymentId,
        status,
      },
      include: { tables: { include: { table: true } } },
    });

    if (status === 'CONFIRMED' && !existing.posReservationId) {
      try {
        await this.posBridge.pushConfirmedReservationToPos(tenant, updated);
      } catch (error) {
        this.logger.error(
          `POS push failed for website reservation ${reservationId}: ${(error as Error).message}`,
        );
        throw error;
      }
    }

    if (status === 'FAILED' && existing.posReservationId) {
      await this.posBridge.cancelPosReservation(existing.posReservationId);
    }

    return updated;
  }

  async getPaymentIdByReservationId(
    reservationId: string,
  ): Promise<string | null> {
    const reservation = await this.prisma.websiteReservation.findUnique({
      where: { id: reservationId },
      select: { paymentId: true },
    });
    return reservation?.paymentId || null;
  }

  @Cron(CronExpression.EVERY_MINUTE)
  async cleanupExpiredPendingReservations() {
    const cutOff = new Date(Date.now() - 10 * 60 * 1000);
    const expired = await this.prisma.websiteReservation.findMany({
      where: { status: 'PENDING', createdAt: { lt: cutOff } },
    });

    if (expired.length === 0) return;

    await this.prisma.websiteReservation.updateMany({
      where: { status: 'PENDING', createdAt: { lt: cutOff } },
      data: {
        status: 'FAILED',
        notes: 'Automatically expired due to timeout',
      },
    });
  }
}
