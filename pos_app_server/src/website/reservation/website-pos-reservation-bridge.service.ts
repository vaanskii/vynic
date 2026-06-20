import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../shared/prisma/prisma.service';
import { PosCallbackClient } from '../../pos-callback.client';
import { MonitoringGateway } from '../../monitoring.gateway';
import { suppressPosEchoForReservation } from '../../sync-echo-guard';
import { MenuService } from '../menu/menu.service';
import {
  dayBounds,
  decodeTableCode,
  encodeTableCode,
  isRealPosTableBooking,
  isReservationBlocking,
  reservationDateKey,
  unavailableCodesFromPosReservations,
} from './reservation-table-codes';

type WebsiteTableRow = {
  id: number;
  websiteTableNumber: string;
  posTableNumber: string;
  posFloor: string;
  capacity: number;
};

type WebsiteReservationWithTables = {
  id: string;
  date: Date;
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

@Injectable()
export class WebsitePosReservationBridgeService {
  private readonly logger = new Logger(WebsitePosReservationBridgeService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    private readonly menuService: MenuService,
    private readonly posCallback: PosCallbackClient,
  ) {}

  encodeWebsiteTables(tables: WebsiteTableRow[]): number[] {
    return tables
      .map((table) =>
        encodeTableCode(table.posFloor, table.posTableNumber),
      )
      .sort((a, b) => a - b);
  }

  /** Day-level blocking — same rules as mobile manager table picker. */
  async getUnavailableTableCodesForDate(
    date: string,
    excludeWebsiteReservationId?: string,
  ): Promise<Set<number>> {
    const { dateKey, start, end } = dayBounds(date);
    const unavailable = new Set<number>();

    const websiteReservations = await this.prisma.websiteReservation.findMany({
      where: {
        date: { gte: start, lte: end },
        status: { in: ['CONFIRMED', 'PENDING'] },
        ...(excludeWebsiteReservationId
          ? { id: { not: excludeWebsiteReservationId } }
          : {}),
      },
      include: { tables: { include: { table: true } } },
    });

    for (const reservation of websiteReservations) {
      if (!isReservationBlocking(reservation.status)) continue;
      for (const row of reservation.tables) {
        unavailable.add(
          encodeTableCode(row.table.posFloor, row.table.posTableNumber),
        );
      }
    }

    try {
      const posRows = await this.posCallback.fetchPosReservations();
      const posUnavailable = unavailableCodesFromPosReservations(
        posRows as Array<Record<string, unknown>>,
        dateKey,
      );
      for (const code of posUnavailable) {
        unavailable.add(code);
      }
    } catch (error) {
      this.logger.warn(
        `POS reservations unavailable for ${dateKey}: ${(error as Error).message}`,
      );
    }

    return unavailable;
  }

  async fetchPosBookingsForDate(
    dateKey: string,
    linkedPosIds: Set<string>,
  ): Promise<Array<Record<string, unknown>>> {
    try {
      const posRows = await this.posCallback.fetchPosReservations();
      return (posRows as Array<Record<string, unknown>>).filter((row) => {
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
      });
    } catch (error) {
      this.logger.warn(
        `POS reservations fetch failed for ${dateKey}: ${(error as Error).message}`,
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
      byCode.set(
        encodeTableCode(table.posFloor, table.posTableNumber),
        table,
      );
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
    tables: WebsiteTableRow[],
    date: string,
    excludeWebsiteReservationId?: string,
  ): Promise<boolean> {
    if (tables.length === 0) return false;
    const unavailable = await this.getUnavailableTableCodesForDate(
      date,
      excludeWebsiteReservationId,
    );
    const codes = this.encodeWebsiteTables(tables);
    return codes.every((code) => !unavailable.has(code));
  }

  async pushConfirmedReservationToPos(
    reservation: WebsiteReservationWithTables,
  ): Promise<string | null> {
    if (reservation.posReservationId) {
      return reservation.posReservationId;
    }

    const websiteTables = reservation.tables.map((row) => row.table);
    const serviceDate = reservationDateKey(reservation.date);

    const available = await this.areWebsiteTablesAvailable(
      websiteTables,
      serviceDate,
      reservation.id,
    );
    if (!available) {
      throw new Error(
        `Tables no longer available on ${serviceDate} — POS sync skipped`,
      );
    }

    const tableNumbers = this.encodeWebsiteTables(websiteTables);
    const numberOfGuests =
      reservation.numberOfGuests ??
      websiteTables.reduce((sum, table) => sum + table.capacity, 0) ??
      2;

    const preOrderItems = await this.buildPreOrderItems(reservation.menuItems);
    const notes = this.buildPosNotes(reservation);

    const posReservation = await this.posCallback.createPosReservation({
      customerName: reservation.customerName ?? 'Website Guest',
      customerPhone: reservation.customerPhone ?? '-',
      tableNumbers,
      reservationDate: serviceDate,
      reservationTime: reservation.timeSlot,
      numberOfGuests,
      notes,
      createdBy: 'website',
      status: 'confirmed',
      isTakeAway: false,
      preOrderItems,
    });

    const posReservationId = String(posReservation?.id ?? '').trim();
    if (!posReservationId) {
      throw new Error('POS did not return a reservation id');
    }

    await this.prisma.websiteReservation.update({
      where: { id: reservation.id },
      data: { posReservationId },
    });

    suppressPosEchoForReservation(posReservationId);

    this.gateway.broadcastUpdate('data_updated', {
      type: 'reservations',
      action: 'created',
      source: 'website',
      websiteReservationId: reservation.id,
      reservationId: posReservationId,
      customerName: reservation.customerName,
      tableNumbers,
      reservationTime: reservation.timeSlot,
      reservationDate: serviceDate,
    });

    this.logger.log(
      `Website reservation ${reservation.id} → POS ${posReservationId} (${serviceDate} ${reservation.timeSlot})`,
    );

    return posReservationId;
  }

  async cancelPosReservation(posReservationId: string): Promise<void> {
    const id = posReservationId.trim();
    if (!id) return;
    try {
      await this.posCallback.updatePosReservationStatus(id, 'cancelled');
      this.gateway.broadcastUpdate('data_updated', {
        type: 'reservations',
        action: 'cancelled',
        source: 'website',
        reservationId: id,
      });
    } catch (error) {
      this.logger.warn(
        `Failed to cancel POS reservation ${id}: ${(error as Error).message}`,
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
    menuItemsJson: string | null,
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
      if (!name && id) {
        const menuItem = await this.menuService.getMenuItemById(id);
        name =
          menuItem?.nameEn ??
          menuItem?.translations?.find((t) => t.language === 'en')?.name ??
          id;
      }
      if (!name) continue;
      items.push({
        itemKey: `${name}_${price.toFixed(2)}`,
        itemName: name,
        unitPrice: price,
        quantity,
        total: price * quantity,
        comment: null,
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
