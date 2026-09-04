import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { normalizeAuditEventType } from '../../pos/audit/audit-event-type';
import {
  nextDay,
  parseBusinessDateStart,
  todayStart,
} from '../util/mobile-date.util';
import { settingIdentity } from '../../tenancy/tenant-identity';
import type { TenantContext } from '../../tenancy/tenant-context';

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
    tenant: TenantContext,
    yearStr?: string,
    monthStr?: string,
    status?: string,
    allStr?: string,
  ) {
    const where: any = { venueId: tenant.venueId };
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

  async getSalesReport(
    tenant: TenantContext,
    period: string = 'today',
    month?: string,
  ) {
    const now = new Date();
    let from: Date;
    let through: Date | null = null;
    let currentBusinessDate: string | null = null;

    if (period === 'all') {
      from = new Date(0);
    } else if (period === 'week') {
      from = new Date(now);
      from.setDate(from.getDate() - 7);
      from.setHours(0, 0, 0, 0);
    } else if (period === 'month') {
      const monthMatch = month?.match(/^(\d{4})-(\d{2})$/);
      if (monthMatch) {
        const y = Number(monthMatch[1]);
        const m = Number(monthMatch[2]);
        from = new Date(y, m - 1, 1);
        through = new Date(y, m, 1);
      } else {
        from = new Date(now.getFullYear(), now.getMonth(), 1);
        through = new Date(now.getFullYear(), now.getMonth() + 1, 1);
      }
    } else {
      // today = current business date
      const businessDateSetting = await (this.prisma as any).setting.findUnique(
        {
          where: settingIdentity(tenant, 'currentBusinessDate'),
        },
      );
      const resolvedBusinessDate =
        businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
      currentBusinessDate = resolvedBusinessDate;
      from = parseBusinessDateStart(resolvedBusinessDate);
    }

    const expenses = await this.prisma.expense.findMany({
      where:
        period === 'today' && currentBusinessDate
          ? {
              venueId: tenant.venueId,
              createdAt: {
                gte: parseBusinessDateStart(currentBusinessDate),
                lt: nextDay(parseBusinessDateStart(currentBusinessDate)),
              },
            }
          : {
              venueId: tenant.venueId,
              createdAt:
                through == null ? { gte: from } : { gte: from, lt: through },
            },
      select: { amount: true, category: true },
    });

    const r = (n: number) => Math.round(n * 100) / 100;
    const totalExpenses = expenses.reduce(
      (sum, e) => sum + Number(e.amount),
      0,
    );
    const expenseBreakdownMap = new Map<string, number>();
    for (const e of expenses) {
      const key = (e.category ?? '').trim() || 'სხვა';
      expenseBreakdownMap.set(
        key,
        (expenseBreakdownMap.get(key) ?? 0) + Number(e.amount),
      );
    }

    // Revenue is unavailable until a POS Sale-derived summary exists. A raw
    // Order cannot prove fiscality, completed closure, reversal state, or gross.
    let effectiveTotalRevenue = 0;
    let effectiveOrderCount = 0;
    let effectiveCashRevenue = 0;
    let effectiveCardRevenue = 0;
    let effectivePaymentBreakdown: Record<string, number> = {};
    let effectiveTopItems: Array<{
      name: string;
      qty: number;
      revenue: number;
    }> | null = null;

    // For today, prefer Windows-POS sales summary (local closed-sales records)
    // when available, so mobile payment-method analytics match Windows exactly.
    if (period === 'today' && currentBusinessDate) {
      const summarySetting = await (this.prisma as any).setting.findUnique({
        where: settingIdentity(tenant, `salesSummary:${currentBusinessDate}`),
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
          effectiveTotalRevenue = Number(summary.totalRevenue ?? 0);
          effectiveOrderCount = Number(summary.orderCount ?? 0);
          effectiveCashRevenue = Number(summary.cashRevenue ?? 0);
          effectiveCardRevenue = Number(summary.cardRevenue ?? 0);
          effectivePaymentBreakdown = summary.paymentBreakdown ?? {};
        } catch (error) {
          console.warn(
            `[MobileReports] Invalid Sale-derived summary for ${currentBusinessDate}; revenue unavailable.`,
            error,
          );
        }
      }
    }

    if (period === 'all') {
      const allTimeSetting = await (this.prisma as any).setting.findUnique({
        where: settingIdentity(tenant, 'salesSummary:all_time'),
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
          effectiveTotalRevenue = Number(summary.totalRevenue ?? 0);
          effectiveOrderCount = Number(summary.orderCount ?? 0);
          effectiveCashRevenue = Number(summary.cashRevenue ?? 0);
          effectiveCardRevenue = Number(summary.cardRevenue ?? 0);
          effectiveTopItems = Array.isArray(summary.topItems)
            ? summary.topItems
            : null;
          effectivePaymentBreakdown = summary.paymentBreakdown ?? {};
        } catch (error) {
          console.warn(
            '[MobileReports] Invalid all-time Sale-derived summary; revenue unavailable.',
            error,
          );
        }
      }
    }

    if (period === 'month' || period === 'week') {
      const historyIndexSetting = await (this.prisma as any).setting.findUnique(
        {
          where: settingIdentity(tenant, 'salesSummary:history_index'),
          select: { value: true },
        },
      );
      let indexedDates: Set<string> | null = null;
      if (historyIndexSetting?.value) {
        try {
          const parsed = JSON.parse(historyIndexSetting.value) as unknown;
          if (Array.isArray(parsed)) {
            indexedDates = new Set(
              parsed
                .map(String)
                .filter((date) => /^\d{4}-\d{2}-\d{2}$/.test(date)),
            );
          }
        } catch (error) {
          console.warn(
            '[MobileReports] Invalid sales-history index; using valid summary rows only.',
            error,
          );
        }
      }
      const summaryRows = await (this.prisma as any).setting.findMany({
        where: {
          venueId: tenant.venueId,
          key: { startsWith: 'salesSummary:' },
        },
        select: { key: true, value: true },
      });
      const localDateKey = (date: Date) =>
        [
          date.getFullYear().toString().padStart(4, '0'),
          (date.getMonth() + 1).toString().padStart(2, '0'),
          date.getDate().toString().padStart(2, '0'),
        ].join('-');
      const fromDateKey = localDateKey(from);
      const throughDateKey = localDateKey(now);
      const monthPrefix =
        period === 'month'
          ? `${month && /^\d{4}-\d{2}$/.test(month) ? month : fromDateKey.slice(0, 7)}-`
          : null;
      const periodRows = summaryRows
        .filter((setting: any) => {
          const date = String(setting.key).replace('salesSummary:', '');
          if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
          if (indexedDates != null && !indexedDates.has(date)) return false;
          if (monthPrefix != null) return date.startsWith(monthPrefix);
          return date >= fromDateKey && date <= throughDateKey;
        })
        .map((s: any) => {
          try {
            return JSON.parse(s.value);
          } catch (error) {
            console.warn(
              `[MobileReports] Invalid Sale-derived history summary ${s.key}; row unavailable.`,
              error,
            );
            return null;
          }
        })
        .filter((x: any) => x != null);
      if (periodRows.length > 0) {
        let totalRevenue = 0;
        let orderCount = 0;
        const pb: Record<string, number> = {};
        const itemMap = new Map<string, { qty: number; revenue: number }>();
        for (const row of periodRows) {
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

    const topItems =
      effectiveTopItems != null && effectiveTopItems.length > 0
        ? effectiveTopItems
            .map((it) => ({
              name: it.name,
              qty: Number(it.qty ?? 0),
              revenue: r(Number(it.revenue ?? 0)),
            }))
            .slice(0, 10)
        : [];

    // Build category mapping so mobile report can expand sold items by categories.
    const menuItems = await (this.prisma as any).menuItem.findMany({
      where: { venueId: tenant.venueId },
      select: {
        nameKa: true,
        nameEn: true,
        category: { select: { nameKa: true } },
        subcategory: { select: { nameKa: true } },
      },
    });
    const nameToCategory = new Map<string, string>();
    for (const it of menuItems) {
      const catName = it.subcategory?.nameKa ?? it.category?.nameKa ?? 'სხვა';
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
        : [];

    const topItemsWithCategory = itemsForCategoryGrouping.map((it) => {
      const key = (it.name ?? '').trim().toLowerCase();
      return {
        ...it,
        category: nameToCategory.get(key) ?? 'სხვა',
      };
    });
    const topItemsByCategoryMap = new Map<
      string,
      {
        totalRevenue: number;
        totalQty: number;
        items: Array<{ name: string; qty: number; revenue: number }>;
      }
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
        Object.entries(effectivePaymentBreakdown).map(([key, value]) => [
          key,
          r(value),
        ]),
      ),
      orderCount: effectiveOrderCount,
      avgOrderValue:
        effectiveOrderCount > 0
          ? r(effectiveTotalRevenue / effectiveOrderCount)
          : 0,
      totalExpenses: r(totalExpenses),
      profit: r(effectiveTotalRevenue - totalExpenses),
      expenseBreakdown: Array.from(expenseBreakdownMap.entries()).map(
        ([category, amount]) => ({
          category,
          amount: r(amount),
        }),
      ),
      topItems,
      topItemsByCategory,
      // The current Cloud Order mirror cannot prove Sale revenue semantics per
      // waiter. Return unavailable rather than manufacturing a revenue rank.
      byWaiter: [],
    };
  }

  async getSalesDaily(tenant: TenantContext, month?: string) {
    const expenses = await this.prisma.expense.findMany({
      where: { venueId: tenant.venueId },
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
      const date = dateKey(e.createdAt);
      expensesByDate.set(
        date,
        (expensesByDate.get(date) ?? 0) + Number(e.amount ?? 0),
      );
    }
    const historyIndexSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'salesSummary:history_index'),
      select: { value: true },
    });
    const summaries = await (this.prisma as any).setting.findMany({
      where: {
        venueId: tenant.venueId,
        key: { startsWith: 'salesSummary:' },
      },
      select: { key: true, value: true },
    });
    const summaryByDate = new Map<string, any>();
    for (const s of summaries) {
      if (s.key === 'salesSummary:all_time') continue;
      const date = s.key.replace('salesSummary:', '');
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
      try {
        summaryByDate.set(date, JSON.parse(s.value));
      } catch (error) {
        console.warn(
          `[MobileReports] Invalid Sale-derived history summary ${s.key}; row unavailable.`,
          error,
        );
      }
    }

    let allDates: Set<string> | null = null;
    if (historyIndexSetting?.value) {
      try {
        const indexedDates = JSON.parse(historyIndexSetting.value) as unknown;
        if (Array.isArray(indexedDates)) {
          allDates = new Set(
            indexedDates
              .map(String)
              .filter((date) => /^\d{4}-\d{2}-\d{2}$/.test(date)),
          );
        }
      } catch (error) {
        console.warn(
          '[MobileReports] Invalid sales-history index; using valid summary rows only.',
          error,
        );
      }
    }
    allDates ??= new Set<string>(Array.from(summaryByDate.keys()));
    let rows = Array.from(allDates).map((date) => {
      const summary = summaryByDate.get(date);
      const totalRevenue = Number(summary?.totalRevenue ?? 0);
      const totalExpenses = Number(
        summary?.totalExpenses ?? expensesByDate.get(date) ?? 0,
      );
      return {
        date,
        totalRevenue,
        closedOrders: Number(summary?.orderCount ?? 0),
        cancelledOrders: Number(summary?.cancelledOrders ?? 0),
        totalOrders: Number(summary?.totalOrders ?? 0),
        paymentBreakdown: summary?.paymentBreakdown ?? {},
        closedTables: Array.isArray(summary?.closedTables)
          ? summary.closedTables
          : [],
        totalExpenses: Math.round(totalExpenses * 100) / 100,
        profit: Math.round((totalRevenue - totalExpenses) * 100) / 100,
      };
    });
    if (month && /^\d{4}-\d{2}$/.test(month)) {
      rows = rows.filter((r) => r.date.startsWith(month));
    }
    rows.sort((a, b) => b.date.localeCompare(a.date));
    return rows;
  }

  async getTopItems(tenant: TenantContext, limit: number) {
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
    });
    const businessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
    const summarySetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, `salesSummary:${businessDate}`),
    });
    if (!summarySetting?.value) return [];

    try {
      const summary = JSON.parse(summarySetting.value) as {
        topItems?: Array<{ name: string; qty: number; revenue: number }>;
      };
      if (!Array.isArray(summary.topItems)) return [];
      return summary.topItems
        .map((item) => ({
          name: String(item.name ?? ''),
          qty: Number(item.qty ?? 0),
          revenue: Math.round(Number(item.revenue ?? 0) * 100) / 100,
        }))
        .sort((a, b) => b.revenue - a.revenue)
        .slice(0, Math.min(limit, 50));
    } catch (error) {
      console.warn(
        `[MobileReports] Invalid Sale-derived top-items summary for ${businessDate}; revenue unavailable.`,
        error,
      );
      return [];
    }
  }
}
