import { Injectable } from '@nestjs/common';
import { PrismaService } from './prisma.service';
import { normalizeAuditEventType } from './pos/audit/audit-event-type';
import {
  businessDateWhere,
  nextDay,
  normalizePaymentType,
  parseBusinessDateStart,
  todayStart,
} from './mobile-date.util';

/**
 * Read-only reporting for the mobile manager app: audit log, sales report,
 * daily sales history, and top items (`/mobile/audit`, `/mobile/sales-report`,
 * `/mobile/sales-daily`, `/mobile/top-items`).
 *
 * Extracted verbatim from MobileController; behavior unchanged. The controller
 * keeps the route decorators (and the top-items query pipes) and delegates here.
 */
@Injectable()
export class MobileReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async getAuditLog(
    yearStr?: string,
    monthStr?: string,
    status?: string,
    allStr?: string,
  ) {
    const where: any = {};
    const includeAllHistory = allStr === '1' || allStr === 'true';

    if (yearStr && monthStr) {
      const y = parseInt(yearStr, 10);
      const m = parseInt(monthStr, 10);
      const from = new Date(y, m - 1, 1);
      const to = new Date(y, m, 1);
      // Match Windows: show reports with activity in this month (not only openedAt).
      where.OR = [
        { openedAt: { gte: from, lt: to } },
        { updatedAt: { gte: from, lt: to } },
        { events: { some: { eventTime: { gte: from, lt: to } } } },
      ];
    } else if (!includeAllHistory) {
      // default: last 90 days
      const from = new Date();
      from.setDate(from.getDate() - 90);
      where.openedAt = { gte: from };
    }

    if (status) {
      where.status = status.toUpperCase();
    }

    const reports = await (this.prisma as any).auditReport.findMany({
      where,
      orderBy: { updatedAt: 'desc' },
      include: {
        events: { orderBy: { seq: 'asc' } },
      },
    });

    return reports.map((r: any) => ({
      reportId: r.reportId,
      orderId: r.posOrderId,
      tableNumbers: r.tableNumbers ?? [],
      floor: r.floor,
      openedById: r.openedById,
      openedByName: r.openedByName,
      openedAt: (r.openedAt as Date).toISOString(),
      status: r.status, // OPEN | CLOSED | CANCELLED
      closedAt: r.closedAt ? (r.closedAt as Date).toISOString() : null,
      closedById: r.closedById ?? null,
      closedByName: r.closedByName ?? null,
      locked: r.locked,
      updatedAt: (r.updatedAt as Date).toISOString(),
      events: (r.events ?? []).map((ev: any) => ({
        type: normalizeAuditEventType(ev.type, ev.previousQty, ev.newQty),
        itemName: ev.itemName,
        previousQty: ev.previousQty,
        newQty: ev.newQty,
        waiterId: ev.waiterId,
        waiterName: ev.waiterName,
        timestamp: (ev.eventTime as Date).toISOString(),
        note: ev.note ?? null,
      })),
    }));
  }

  async getSalesReport(period: string = 'today', month?: string) {
    const now = new Date();
    let from: Date;
    let where: any;
    let currentBusinessDate: string | null = null;

    if (period === 'all') {
      from = new Date(0);
      where = { status: { not: 'cancelled' } };
    } else if (period === 'week') {
      from = new Date(now);
      from.setDate(from.getDate() - 7);
      from.setHours(0, 0, 0, 0);
      where = { createdAt: { gte: from }, status: { not: 'cancelled' } };
    } else if (period === 'month') {
      const monthMatch = month?.match(/^(\d{4})-(\d{2})$/);
      if (monthMatch) {
        const y = Number(monthMatch[1]);
        const m = Number(monthMatch[2]);
        from = new Date(y, m - 1, 1);
        const to = new Date(y, m, 1);
        where = {
          createdAt: { gte: from, lt: to },
          status: { not: 'cancelled' },
        };
      } else {
        from = new Date(now.getFullYear(), now.getMonth(), 1);
        where = { createdAt: { gte: from }, status: { not: 'cancelled' } };
      }
    } else {
      // today = current business date
      const businessDateSetting = await (this.prisma as any).setting.findUnique({
        where: { key: 'currentBusinessDate' },
      });
      const resolvedBusinessDate =
        businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
      currentBusinessDate = resolvedBusinessDate;
      from = parseBusinessDateStart(resolvedBusinessDate);
      where = { ...businessDateWhere(resolvedBusinessDate), status: { not: 'cancelled' } };
    }

    const [orders, byWaiter, expenses] = await Promise.all([
      this.prisma.order.findMany({
        where,
        include: { items: true },
      }),
      this.prisma.order.groupBy({
        by: ['waiterName'],
        where,
        _sum: { totalAmount: true },
        _count: { id: true },
      }),
      this.prisma.expense.findMany({
        where:
          period === 'today' && currentBusinessDate
            ? {
                createdAt: {
                  gte: parseBusinessDateStart(currentBusinessDate),
                  lt: nextDay(parseBusinessDateStart(currentBusinessDate)),
                },
              }
            : { createdAt: { gte: from } },
        select: { amount: true, category: true },
      }),
    ]);

    const r = (n: number) => Math.round(n * 100) / 100;
    const totalRev = orders.reduce((s, o) => s + Number(o.totalAmount), 0);
    const paymentBreakdown: Record<string, number> = {};
    for (const o of orders) {
      const key = normalizePaymentType((o as any).paymentType);
      paymentBreakdown[key] = (paymentBreakdown[key] ?? 0) + Number(o.totalAmount);
    }
    const cashRev = paymentBreakdown['cash'] ?? 0;
    const cardRev = Object.entries(paymentBreakdown).reduce(
      (sum, [key, amount]) => (key.startsWith('card') ? sum + amount : sum),
      0,
    );
    const totalExpenses = expenses.reduce((sum, e) => sum + Number(e.amount), 0);
    const expenseBreakdownMap = new Map<string, number>();
    for (const e of expenses) {
      const key = (e.category ?? '').trim() || 'სხვა';
      expenseBreakdownMap.set(key, (expenseBreakdownMap.get(key) ?? 0) + Number(e.amount));
    }

    let effectiveTotalRevenue = totalRev;
    let effectiveOrderCount = orders.length;
    let effectiveCashRevenue = cashRev;
    let effectiveCardRevenue = cardRev;
    let effectivePaymentBreakdown: Record<string, number> = { ...paymentBreakdown };
    let effectiveTopItems: Array<{ name: string; qty: number; revenue: number }> | null =
      null;

    // For today, prefer Windows-POS sales summary (local closed-sales records)
    // when available, so mobile payment-method analytics match Windows exactly.
    if (period === 'today' && currentBusinessDate) {
      const summarySetting = await (this.prisma as any).setting.findUnique({
        where: { key: `salesSummary:${currentBusinessDate}` },
      });
      if (summarySetting?.value) {
        try {
          const summary = JSON.parse(summarySetting.value) as {
            totalRevenue?: number;
            orderCount?: number;
            cashRevenue?: number;
            cardRevenue?: number;
            paymentBreakdown?: Record<string, number>;
          };
          effectiveTotalRevenue = Number(summary.totalRevenue ?? effectiveTotalRevenue);
          effectiveOrderCount = Number(summary.orderCount ?? effectiveOrderCount);
          effectiveCashRevenue = Number(summary.cashRevenue ?? effectiveCashRevenue);
          effectiveCardRevenue = Number(summary.cardRevenue ?? effectiveCardRevenue);
          effectivePaymentBreakdown = {
            ...effectivePaymentBreakdown,
            ...(summary.paymentBreakdown ?? {}),
          };
        } catch {
          // Ignore malformed summary and keep DB-derived fallback values.
        }
      }
    }

    if (period === 'all') {
      const allTimeSetting = await (this.prisma as any).setting.findUnique({
        where: { key: 'salesSummary:all_time' },
      });
      if (allTimeSetting?.value) {
        try {
          const summary = JSON.parse(allTimeSetting.value) as {
            totalRevenue?: number;
            orderCount?: number;
            cashRevenue?: number;
            cardRevenue?: number;
            paymentBreakdown?: Record<string, number>;
            topItems?: Array<{ name: string; qty: number; revenue: number }>;
          };
          effectiveTotalRevenue = Number(summary.totalRevenue ?? effectiveTotalRevenue);
          effectiveOrderCount = Number(summary.orderCount ?? effectiveOrderCount);
          effectiveCashRevenue = Number(summary.cashRevenue ?? effectiveCashRevenue);
          effectiveCardRevenue = Number(summary.cardRevenue ?? effectiveCardRevenue);
          effectiveTopItems = Array.isArray(summary.topItems)
            ? summary.topItems
            : null;
          effectivePaymentBreakdown = {
            ...effectivePaymentBreakdown,
            ...(summary.paymentBreakdown ?? {}),
          };
        } catch {
          // Ignore malformed summary and keep DB-derived fallback values.
        }
      }
    }

    if (period === 'month' && month && /^\d{4}-\d{2}$/.test(month)) {
      const summaryRows = await (this.prisma as any).setting.findMany({
        where: { key: { startsWith: 'salesSummary:' } },
        select: { key: true, value: true },
      });
      const monthRows = summaryRows
        .filter((s: any) => s.key.startsWith(`salesSummary:${month}-`))
        .map((s: any) => {
          try {
            return JSON.parse(s.value);
          } catch {
            return null;
          }
        })
        .filter((x: any) => x != null);
      if (monthRows.length > 0) {
        let totalRevenue = 0;
        let orderCount = 0;
        const pb: Record<string, number> = {};
        const itemMap = new Map<string, { qty: number; revenue: number }>();
        for (const row of monthRows) {
          totalRevenue += Number(row.totalRevenue ?? 0);
          orderCount += Number(row.orderCount ?? 0);
          const pbd = (row.paymentBreakdown ?? {}) as Record<string, number>;
          Object.entries(pbd).forEach(([k, v]) => {
            pb[k] = (pb[k] ?? 0) + Number(v);
          });
          const tis = Array.isArray(row.topItems) ? row.topItems : [];
          for (const it of tis) {
            const name = String(it.name ?? '').trim();
            if (!name) continue;
            const cur = itemMap.get(name) ?? { qty: 0, revenue: 0 };
            cur.qty += Number(it.qty ?? 0);
            cur.revenue += Number(it.revenue ?? 0);
            itemMap.set(name, cur);
          }
        }
        effectiveTotalRevenue = totalRevenue;
        effectiveOrderCount = orderCount;
        effectiveCashRevenue = Number(pb['cash'] ?? 0);
        effectiveCardRevenue = Object.entries(pb).reduce(
          (sum, [k, v]) => (k.startsWith('card') ? sum + Number(v) : sum),
          0,
        );
        effectivePaymentBreakdown = pb;
        effectiveTopItems = Array.from(itemMap.entries())
          .sort((a, b) => b[1].revenue - a[1].revenue)
          .map(([name, s]) => ({
            name,
            qty: Math.round(s.qty),
            revenue: r(s.revenue),
          }));
      }
    }

    // Per-item aggregation
    const itemMap = new Map<string, { qty: number; revenue: number }>();
    for (const o of orders) {
      for (const it of (o as any).items ?? []) {
        const cur = itemMap.get(it.name) ?? { qty: 0, revenue: 0 };
        itemMap.set(it.name, {
          qty: cur.qty + it.quantity,
          revenue: cur.revenue + it.quantity * Number(it.price),
        });
      }
    }

    const allItemsSorted = Array.from(itemMap.entries())
      .sort((a, b) => b[1].revenue - a[1].revenue)
      .map(([name, s]) => ({ name, qty: s.qty, revenue: r(s.revenue) }));

    const topItems =
      effectiveTopItems != null && effectiveTopItems.length > 0
        ? effectiveTopItems
            .map((it) => ({
              name: it.name,
              qty: Number(it.qty ?? 0),
              revenue: r(Number(it.revenue ?? 0)),
            }))
            .slice(0, 10)
        : allItemsSorted.slice(0, 10);

    // Build category mapping so mobile report can expand sold items by categories.
    const menuItems = await (this.prisma as any).menuItem.findMany({
      select: {
        nameKa: true,
        nameEn: true,
        category: { select: { nameKa: true } },
        subcategory: { select: { nameKa: true } },
      },
    });
    const nameToCategory = new Map<string, string>();
    for (const it of menuItems) {
      const catName =
        it.subcategory?.nameKa ??
        it.category?.nameKa ??
        'სხვა';
      const ka = (it.nameKa ?? '').trim().toLowerCase();
      const en = (it.nameEn ?? '').trim().toLowerCase();
      if (ka) nameToCategory.set(ka, catName);
      if (en) nameToCategory.set(en, catName);
    }
    const itemsForCategoryGrouping =
      effectiveTopItems != null && effectiveTopItems.length > 0
        ? effectiveTopItems.map((it) => ({
            name: it.name,
            qty: Number(it.qty ?? 0),
            revenue: r(Number(it.revenue ?? 0)),
          }))
        : allItemsSorted;

    const topItemsWithCategory = itemsForCategoryGrouping.map((it) => {
      const key = (it.name ?? '').trim().toLowerCase();
      return {
        ...it,
        category: nameToCategory.get(key) ?? 'სხვა',
      };
    });
    const topItemsByCategoryMap = new Map<
      string,
      { totalRevenue: number; totalQty: number; items: Array<{ name: string; qty: number; revenue: number }> }
    >();
    for (const item of topItemsWithCategory) {
      const category = item.category;
      const cur = topItemsByCategoryMap.get(category) ?? {
        totalRevenue: 0,
        totalQty: 0,
        items: [],
      };
      cur.totalRevenue += item.revenue;
      cur.totalQty += item.qty;
      cur.items.push({ name: item.name, qty: item.qty, revenue: item.revenue });
      topItemsByCategoryMap.set(category, cur);
    }
    const topItemsByCategory = Array.from(topItemsByCategoryMap.entries())
      .map(([category, data]) => ({
        category,
        totalRevenue: r(data.totalRevenue),
        totalQty: data.totalQty,
        items: data.items.sort((a, b) => b.revenue - a.revenue),
      }))
      .sort((a, b) => b.totalRevenue - a.totalRevenue);

    return {
      period,
      from: from.toISOString(),
      to: now.toISOString(),
      totalRevenue: r(effectiveTotalRevenue),
      cashRevenue: r(effectiveCashRevenue),
      cardRevenue: r(effectiveCardRevenue),
      paymentBreakdown: Object.fromEntries(
        Object.entries(effectivePaymentBreakdown).map(([key, value]) => [key, r(value)]),
      ),
      orderCount: effectiveOrderCount,
      avgOrderValue:
        effectiveOrderCount > 0 ? r(effectiveTotalRevenue / effectiveOrderCount) : 0,
      totalExpenses: r(totalExpenses),
      profit: r(effectiveTotalRevenue - totalExpenses),
      expenseBreakdown: Array.from(expenseBreakdownMap.entries()).map(([category, amount]) => ({
        category,
        amount: r(amount),
      })),
      topItems,
      topItemsByCategory,
      byWaiter: byWaiter.map((w) => ({
        waiterName: w.waiterName,
        totalSales: r(Number(w._sum.totalAmount ?? 0)),
        orderCount: w._count.id,
      })),
    };
  }

  async getSalesDaily(month?: string) {
    const expenses = await this.prisma.expense.findMany({
      select: { amount: true, createdAt: true },
    });
    const expensesByDate = new Map<string, number>();
    const dateKey = (d: Date) => {
      const y = d.getFullYear().toString().padStart(4, '0');
      const m = (d.getMonth() + 1).toString().padStart(2, '0');
      const day = d.getDate().toString().padStart(2, '0');
      return `${y}-${m}-${day}`;
    };
    for (const e of expenses) {
      // Use local date parts instead of UTC ISO split to avoid off-by-one-day
      // shifts for business dates in positive timezones (e.g. +04).
      const date = dateKey(e.createdAt as Date);
      expensesByDate.set(date, (expensesByDate.get(date) ?? 0) + Number(e.amount ?? 0));
    }
    const historyIndexSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'salesSummary:history_index' },
      select: { value: true },
    });
    const summaries = await (this.prisma as any).setting.findMany({
      where: { key: { startsWith: 'salesSummary:' } },
      select: { key: true, value: true },
    });
    const summaryByDate = new Map<string, any>();
    for (const s of summaries) {
      if (s.key === 'salesSummary:all_time') continue;
      const date = s.key.replace('salesSummary:', '');
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
      try {
        summaryByDate.set(date, JSON.parse(s.value));
      } catch {
        // ignore malformed
      }
    }

    const orders = await this.prisma.order.findMany({
      select: {
        businessDate: true,
        status: true,
        totalAmount: true,
        paymentType: true,
        createdAt: true,
      },
    });
    const byDate = new Map<
      string,
      {
        totalOrders: number;
        cancelledOrders: number;
        nonCancelledTotal: number;
        paymentBreakdown: Record<string, number>;
      }
    >();
    const dateFromOrder = (o: any) =>
      (o.businessDate && o.businessDate.trim().length > 0
        ? o.businessDate
        : (o.createdAt as Date).toISOString().split('T')[0]) as string;
    for (const o of orders) {
      const date = dateFromOrder(o);
      const cur = byDate.get(date) ?? {
        totalOrders: 0,
        cancelledOrders: 0,
        nonCancelledTotal: 0,
        paymentBreakdown: {},
      };
      cur.totalOrders += 1;
      const isCancelled = (o.status ?? '').toLowerCase() === 'cancelled';
      if (isCancelled) {
        cur.cancelledOrders += 1;
      } else {
        const amount = Number(o.totalAmount ?? 0);
        cur.nonCancelledTotal += amount;
        const method = normalizePaymentType((o as any).paymentType);
        cur.paymentBreakdown[method] = (cur.paymentBreakdown[method] ?? 0) + amount;
      }
      byDate.set(date, cur);
    }

    const allDates = new Set<string>([
      ...Array.from(summaryByDate.keys()),
      ...Array.from(byDate.keys()),
    ]);
    if (historyIndexSetting?.value) {
      try {
        const indexedDates = JSON.parse(historyIndexSetting.value) as string[];
        for (const d of indexedDates) allDates.add(d);
      } catch {
        // ignore malformed index
      }
    }
    let rows = Array.from(allDates).map((date) => {
      const summary = summaryByDate.get(date) as any;
      const fallback = byDate.get(date) ?? {
        totalOrders: 0,
        cancelledOrders: 0,
        nonCancelledTotal: 0,
        paymentBreakdown: {},
      };
      return {
        date,
        totalRevenue: Number(summary?.totalRevenue ?? fallback.nonCancelledTotal ?? 0),
        closedOrders: Number(summary?.orderCount ?? (fallback.totalOrders - fallback.cancelledOrders)),
        cancelledOrders: fallback.cancelledOrders,
        totalOrders: fallback.totalOrders,
        paymentBreakdown: summary?.paymentBreakdown ?? fallback.paymentBreakdown,
        closedTables: Array.isArray(summary?.closedTables) ? summary.closedTables : [],
        totalExpenses:
          Math.round(
            Number(summary?.totalExpenses ?? expensesByDate.get(date) ?? 0) * 100,
          ) / 100,
        profit:
          Math.round(
            (Number(summary?.totalRevenue ?? fallback.nonCancelledTotal ?? 0) -
              Number(summary?.totalExpenses ?? expensesByDate.get(date) ?? 0)) *
              100,
          ) / 100,
      };
    });
    if (month && /^\d{4}-\d{2}$/.test(month)) {
      rows = rows.filter((r) => r.date.startsWith(month));
    }
    rows.sort((a, b) => b.date.localeCompare(a.date));
    return rows;
  }

  async getTopItems(limit: number) {
    const today = todayStart();
    const items = await (this.prisma as any).orderItem.findMany({
      where: { order: { createdAt: { gte: today } } },
      select: { name: true, quantity: true, price: true },
    });

    const map = new Map<string, { qty: number; revenue: number }>();
    for (const item of items) {
      const cur = map.get(item.name) ?? { qty: 0, revenue: 0 };
      map.set(item.name, {
        qty: cur.qty + item.quantity,
        revenue: cur.revenue + item.quantity * Number(item.price),
      });
    }

    return Array.from(map.entries())
      .sort((a, b) => b[1].revenue - a[1].revenue)
      .slice(0, Math.min(limit, 50))
      .map(([name, stats]) => ({
        name,
        qty: stats.qty,
        revenue: Math.round(stats.revenue * 100) / 100,
      }));
  }
}
