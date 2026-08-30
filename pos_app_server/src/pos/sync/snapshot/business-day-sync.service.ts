import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../prisma.service';
import { ExpenseSync, SyncPayload } from '../sync-payload';

export interface BusinessDayRollover {
  date: string;
  prevDate: unknown;
}

/**
 * The money and calendar records the POS reports for its business day.
 *
 * A business day is not a calendar day — the POS decides when one ends, and
 * says so by sending a new `businessDate`. When that value changes the manager
 * closed the day, so every table is released: otherwise a ghost reservation
 * from yesterday survives, and the cold-boot guard in TableSyncService would
 * refuse the all-free snapshot that would have cleared it.
 *
 * Everything else here is write-through of values the POS computed. The server
 * does not recalculate them, because the POS's X-report is what the restaurant
 * treats as authoritative — the one exception is `openTablesPayable`, summed
 * from the occupied tables in the snapshot.
 */
@Injectable()
export class BusinessDaySyncService {
  constructor(private readonly prisma: PrismaService) {}

  async recordExpenses(expenses: ExpenseSync[]): Promise<void> {
    for (const expense of expenses) {
      await (this.prisma.expense.create as any)({
        data: {
          description: expense.description,
          amount: expense.amount,
          category: expense.category,
          paymentType: expense.paymentType ?? 'cash',
          createdAt: expense.createdAt
            ? new Date(expense.createdAt)
            : new Date(),
        },
      });
    }
  }

  /** Returns the rollover when the day advanced, having cleared the floor. */
  async trackBusinessDate(
    businessDate?: string,
  ): Promise<BusinessDayRollover | null> {
    if (!businessDate) return null;

    // ── Business date tracking ──────────────────────────────────────────────
    // The POS sends its current business date (YYYY-MM-DD). Store it so the
    // mobile dashboard queries the correct date range instead of calendar-day.
    const newDate = businessDate; // e.g. "2026-04-30"
    const existing = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
    });
    const prevDate = existing?.value ?? null;

    await (this.prisma as any).setting.upsert({
      where: { key: 'currentBusinessDate' },
      update: { value: newDate },
      create: { key: 'currentBusinessDate', value: newDate },
    });

    const openedAtKey = `businessDayOpenedAt:${newDate}`;
    const openedAtExisting = await (this.prisma as any).setting.findUnique({
      where: { key: openedAtKey },
    });
    const dayAdvanced = prevDate !== null && prevDate !== newDate;
    if (dayAdvanced || !openedAtExisting?.value) {
      const openedAt = new Date().toISOString();
      await (this.prisma as any).setting.upsert({
        where: { key: openedAtKey },
        update: { value: openedAt },
        create: { key: openedAtKey, value: openedAt },
      });
    }

    // If the date actually advanced, the manager closed the day → notify mobile
    if (dayAdvanced) {
      console.log(
        `[Sync] Business date advanced: ${prevDate} → ${newDate}. Clearing all table reservations.`,
      );
      // Reset every table to free so ghost tables from the previous business
      // day cannot persist. The cold-boot guard in TableSyncService would
      // otherwise block the next "all tables free" push from the POS.
      await (this.prisma as any).table.updateMany({
        data: { isReserved: false, activeOrderId: null, currentBill: 0 },
      });
      return { date: newDate, prevDate };
    }

    return null;
  }

  async persistReportingSnapshot(
    data: SyncPayload,
    realtimeOnly: boolean,
  ): Promise<void> {
    const { tables, salesSummary, salesAllTimeSummary, salesHistoryByDate } =
      data;

    // Persist POS day sales summary (payment methods + totals) so mobile reads
    // exactly what Windows saved locally after table close.
    if (salesSummary?.date) {
      const summaryValue = JSON.stringify({
        date: salesSummary.date,
        totalRevenue: salesSummary.totalRevenue ?? 0,
        orderCount: salesSummary.orderCount ?? 0,
        cashRevenue: salesSummary.cashRevenue ?? 0,
        cardRevenue: salesSummary.cardRevenue ?? 0,
        paymentBreakdown: salesSummary.paymentBreakdown ?? {},
        totalExpenses: salesSummary.totalExpenses ?? 0,
        profit: salesSummary.profit ?? 0,
        syncedAt: new Date().toISOString(),
      });
      await (this.prisma as any).setting.upsert({
        where: { key: `salesSummary:${salesSummary.date}` },
        update: { value: summaryValue },
        create: {
          key: `salesSummary:${salesSummary.date}`,
          value: summaryValue,
        },
      });
    }

    if (salesAllTimeSummary && !realtimeOnly) {
      const allTimeValue = JSON.stringify({
        totalRevenue: salesAllTimeSummary.totalRevenue ?? 0,
        orderCount: salesAllTimeSummary.orderCount ?? 0,
        cashRevenue: salesAllTimeSummary.cashRevenue ?? 0,
        cardRevenue: salesAllTimeSummary.cardRevenue ?? 0,
        paymentBreakdown: salesAllTimeSummary.paymentBreakdown ?? {},
        topItems: salesAllTimeSummary.topItems ?? [],
        syncedAt: new Date().toISOString(),
      });
      await (this.prisma as any).setting.upsert({
        where: { key: 'salesSummary:all_time' },
        update: { value: allTimeValue },
        create: { key: 'salesSummary:all_time', value: allTimeValue },
      });
    }

    if (
      salesHistoryByDate &&
      typeof salesHistoryByDate === 'object' &&
      !realtimeOnly
    ) {
      for (const [date, summary] of Object.entries(salesHistoryByDate)) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
        const summaryValue = JSON.stringify({
          date,
          totalRevenue: summary.totalRevenue ?? 0,
          orderCount: summary.orderCount ?? 0,
          totalOrders: summary.totalOrders ?? 0,
          cancelledOrders: summary.cancelledOrders ?? 0,
          cashRevenue: summary.cashRevenue ?? 0,
          cardRevenue: summary.cardRevenue ?? 0,
          paymentBreakdown: summary.paymentBreakdown ?? {},
          totalExpenses: summary.totalExpenses ?? 0,
          profit: summary.profit ?? 0,
          topItems: summary.topItems ?? [],
          closedTables: summary.closedTables ?? [],
        });
        await (this.prisma as any).setting.upsert({
          where: { key: `salesSummary:${date}` },
          update: { value: summaryValue },
          create: { key: `salesSummary:${date}`, value: summaryValue },
        });
      }
      await (this.prisma as any).setting.upsert({
        where: { key: 'salesSummary:history_index' },
        update: {
          value: JSON.stringify(Object.keys(salesHistoryByDate).sort()),
        },
        create: {
          key: 'salesSummary:history_index',
          value: JSON.stringify(Object.keys(salesHistoryByDate).sort()),
        },
      });
    }

    if (data.settings) {
      const percent = Number(data.settings.serviceFeePercent ?? 10);
      const enabled = data.settings.serviceFeeEnabled === true;
      await (this.prisma as any).setting.upsert({
        where: { key: 'restaurant:serviceFeePercent' },
        update: { value: String(percent) },
        create: { key: 'restaurant:serviceFeePercent', value: String(percent) },
      });
      await (this.prisma as any).setting.upsert({
        where: { key: 'restaurant:serviceFeeEnabled' },
        update: { value: enabled ? 'true' : 'false' },
        create: {
          key: 'restaurant:serviceFeeEnabled',
          value: enabled ? 'true' : 'false',
        },
      });
    }

    if (data.dailySalesTotal !== undefined && data.businessDate) {
      await (this.prisma as any).setting.upsert({
        where: { key: `dailySalesTotal:${data.businessDate}` },
        update: { value: String(data.dailySalesTotal ?? 0) },
        create: {
          key: `dailySalesTotal:${data.businessDate}`,
          value: String(data.dailySalesTotal ?? 0),
        },
      });
    }

    if (data.businessDate) {
      const fromOccupiedTables = (tables ?? [])
        .filter(
          (t) =>
            t.isReserved ||
            (t.activeOrderId !== undefined && t.activeOrderId !== null),
        )
        .reduce((sum, t) => sum + Number(t.currentBill ?? 0), 0);

      const openTablesPayableToStore = fromOccupiedTables;

      await (this.prisma as any).setting.upsert({
        where: { key: `openTablesPayable:${data.businessDate}` },
        update: { value: String(openTablesPayableToStore) },
        create: {
          key: `openTablesPayable:${data.businessDate}`,
          value: String(openTablesPayableToStore),
        },
      });
      console.log(
        '[Sync][MoneyDebug][STORE] key=openTablesPayable:%s value=%s',
        data.businessDate,
        openTablesPayableToStore,
      );
    }

    if (data.dailySalesTotal !== undefined && data.businessDate) {
      console.log(
        '[Sync][MoneyDebug][STORE] key=dailySalesTotal:%s value=%s',
        data.businessDate,
        data.dailySalesTotal ?? 0,
      );
    }
  }
}
