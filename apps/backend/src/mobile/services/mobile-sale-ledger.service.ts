import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { TenantContext } from '../../tenancy/tenant-context';
import { PrismaService } from '../../prisma.service';
import { isBusinessDate } from '../util/mobile-date.util';

const REVENUE_WHERE = {
  isFiscal: true,
  isCancelled: false,
  restoredToOrder: false,
} as const;

type Provenance = 'LEDGER_COMPLETE' | 'LEGACY_FALLBACK' | 'PARTIAL';

type ProductRow = {
  menuItemId: string | null;
  variantId: string | null;
  name: string;
  variantName: string | null;
  quantity: bigint;
  revenue: Prisma.Decimal;
};

export type StaffAttribution = 'creator' | 'closer';

/** POS records names, not server Staff IDs. Never resolve a historical name
 * through today's mutable staff directory or turn a closer into a waiter. */
function recordedActor(value: unknown) {
  const name = typeof value === 'string' ? value.trim() : '';
  const known = !!name && !['unknown', 'system'].includes(name.toLowerCase());
  return {
    staffId: known ? name : null,
    staffName: known ? name : 'Unknown / system',
    identityBasis: known ? 'RECORDED_POS_USERNAME' : 'UNKNOWN',
    identityStable: false,
    attributionReliable: false,
  };
}

function money(value: unknown): string {
  return new Prisma.Decimal((value as any) ?? 0).toFixed(2);
}

function add(a: string, b: unknown): string {
  return new Prisma.Decimal(a).plus((b as any) ?? 0).toFixed(2);
}

function parseDate(value: string | undefined, fallback: string): string {
  const result = value ?? fallback;
  if (!isBusinessDate(result)) {
    throw new BadRequestException('Dates must use YYYY-MM-DD');
  }
  return result;
}

function pageLimit(
  value: string | number | undefined,
  fallback: number,
): number {
  const limit = Number(value ?? fallback);
  if (!Number.isSafeInteger(limit))
    throw new BadRequestException('Limit must be an integer');
  return Math.min(100, Math.max(1, limit));
}

function enumerateDates(from: string, to: string): string[] {
  const start = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  if (start > end) throw new BadRequestException('from must not be after to');
  const dates: string[] = [];
  for (
    let date = start;
    date <= end;
    date = new Date(date.valueOf() + 86400000)
  ) {
    dates.push(date.toISOString().slice(0, 10));
    if (dates.length > 366)
      throw new BadRequestException('Date range is limited to 366 days');
  }
  return dates;
}

function warningFor(provenance: Provenance): string | null {
  if (provenance === 'PARTIAL') {
    return 'Detailed sale history is incomplete for part of this period. Totals shown are ledger-only and may be partial.';
  }
  if (provenance === 'LEGACY_FALLBACK') {
    return 'Detailed sale history is unavailable for part of this period. Summary values include legacy daily records.';
  }
  return null;
}

@Injectable()
export class MobileSaleLedgerService {
  constructor(private readonly prisma: PrismaService) {}

  private async currentDate(tenant: TenantContext): Promise<string> {
    const setting = await (this.prisma as any).setting.findUnique({
      where: {
        venueId_key: { venueId: tenant.venueId, key: 'currentBusinessDate' },
      },
    });
    return setting?.value ?? new Date().toISOString().slice(0, 10);
  }

  private async range(
    tenant: TenantContext,
    fromValue?: string,
    toValue?: string,
  ): Promise<{ from: string; to: string; dates: string[] }> {
    const current = await this.currentDate(tenant);
    const from = parseDate(fromValue, current);
    const to = parseDate(toValue, from);
    return { from, to, dates: enumerateDates(from, to) };
  }

  private async provenance(
    tenant: TenantContext,
    dates: string[],
  ): Promise<{
    provenance: Provenance;
    warning: string | null;
    legacyDates: string[];
    reconciliation: Array<{ businessDate: string; result: string }>;
  }> {
    const days = await (this.prisma as any).saleLedgerDay.findMany({
      where: { venueId: tenant.venueId, businessDate: { in: dates } },
    });
    const byDate = new Map<string, any>(
      days.map((day: any) => [day.businessDate, day]),
    );
    const legacyDates = dates.filter(
      (date) => byDate.get(date)?.completeness !== 'COMPLETE',
    );
    const [legacySettings, ledgerDates] = legacyDates.length
      ? await Promise.all([
          (this.prisma as any).setting.findMany({
            where: {
              venueId: tenant.venueId,
              key: {
                in: legacyDates.map((date) => `salesSummary:${date}`),
              },
            },
            select: { key: true },
          }),
          (this.prisma as any).cloudSale.findMany({
            where: {
              venueId: tenant.venueId,
              businessDate: { in: legacyDates },
            },
            distinct: ['businessDate'],
            select: { businessDate: true },
          }),
        ])
      : [[], []];
    const legacyAvailable = new Set(
      legacySettings.map((row: any) => row.key.replace('salesSummary:', '')),
    );
    const partial =
      dates.some((date) => byDate.get(date)?.completeness === 'PARTIAL') ||
      ledgerDates.length > 0;
    const unavailable = legacyDates.some((date) => !legacyAvailable.has(date));
    const provenance: Provenance =
      partial || unavailable
        ? 'PARTIAL'
        : legacyDates.length > 0
          ? 'LEGACY_FALLBACK'
          : 'LEDGER_COMPLETE';
    return {
      provenance,
      warning: warningFor(provenance),
      legacyDates,
      reconciliation: days.map((day: any) => ({
        businessDate: day.businessDate,
        result: day.reconciliation,
      })),
    };
  }

  private async detailProvenance(tenant: TenantContext, dates: string[]) {
    const source = await this.provenance(tenant, dates);
    return {
      ...source,
      provenance:
        source.provenance === 'LEDGER_COMPLETE'
          ? ('LEDGER_COMPLETE' as const)
          : ('PARTIAL' as const),
      warning:
        source.provenance === 'LEDGER_COMPLETE'
          ? null
          : 'Detailed Sale records are incomplete for this period. Aggregate-only history cannot supply product quantities or staff attribution.',
    };
  }

  private async ledgerSummary(tenant: TenantContext, from: string, to: string) {
    const dateWhere = { gte: from, lte: to };
    const [revenue, operational, internal, voided, restored, payments] =
      await Promise.all([
        (this.prisma as any).cloudSale.aggregate({
          where: {
            venueId: tenant.venueId,
            businessDate: dateWhere,
            ...REVENUE_WHERE,
          },
          _sum: { gross: true, advanceApplied: true },
          _count: { _all: true },
        }),
        (this.prisma as any).cloudSale.aggregate({
          where: {
            venueId: tenant.venueId,
            businessDate: dateWhere,
            isCancelled: false,
            restoredToOrder: false,
          },
          _sum: { gross: true },
        }),
        (this.prisma as any).cloudSale.aggregate({
          where: {
            venueId: tenant.venueId,
            businessDate: dateWhere,
            isFiscal: false,
            isCancelled: false,
            restoredToOrder: false,
          },
          _sum: { gross: true },
          _count: { _all: true },
        }),
        (this.prisma as any).cloudSale.aggregate({
          where: {
            venueId: tenant.venueId,
            businessDate: dateWhere,
            isCancelled: true,
          },
          _sum: { gross: true },
          _count: { _all: true },
        }),
        (this.prisma as any).cloudSale.aggregate({
          where: {
            venueId: tenant.venueId,
            businessDate: dateWhere,
            restoredToOrder: true,
          },
          _sum: { gross: true },
          _count: { _all: true },
        }),
        (this.prisma as any).salePayment.groupBy({
          by: ['method'],
          where: {
            sale: {
              venueId: tenant.venueId,
              businessDate: dateWhere,
              ...REVENUE_WHERE,
            },
          },
          _sum: { amount: true },
        }),
      ]);
    const breakdown: Record<string, string> = {};
    for (const part of payments)
      breakdown[part.method] = money(part._sum.amount);
    const revenueValue = money(revenue._sum.gross);
    const saleCount = Number(revenue._count._all ?? 0);
    return {
      revenue: revenueValue,
      revenueSaleCount: saleCount,
      averageRevenueSale: saleCount
        ? new Prisma.Decimal(revenueValue).dividedBy(saleCount).toFixed(2)
        : '0.00',
      grossOperationalValue: money(operational._sum.gross),
      cashCollected: breakdown.cash ?? '0.00',
      tbcCollected: breakdown['card-tbc'] ?? '0.00',
      bogCollected: breakdown['card-bog'] ?? '0.00',
      legacyCardCollected: breakdown.card ?? '0.00',
      advanceApplied: money(revenue._sum.advanceApplied),
      paymentBreakdown: breakdown,
      internalCount: Number(internal._count._all ?? 0),
      internalValue: money(internal._sum.gross),
      voidedCount: Number(voided._count._all ?? 0),
      voidedValue: money(voided._sum.gross),
      restoredCount: Number(restored._count._all ?? 0),
      restoredValue: money(restored._sum.gross),
    };
  }

  async getSummary(
    tenant: TenantContext,
    query: { from?: string; to?: string },
  ) {
    const range = await this.range(tenant, query.from, query.to);
    const source = await this.provenance(tenant, range.dates);
    const summary = await this.ledgerSummary(tenant, range.from, range.to);
    if (source.provenance === 'LEGACY_FALLBACK') {
      const rows = await (this.prisma as any).setting.findMany({
        where: {
          venueId: tenant.venueId,
          key: { in: source.legacyDates.map((date) => `salesSummary:${date}`) },
        },
      });
      for (const row of rows) {
        try {
          const legacy = JSON.parse(row.value);
          summary.revenue = add(summary.revenue, legacy.totalRevenue);
          summary.revenueSaleCount += Number(legacy.orderCount ?? 0);
          summary.cashCollected = add(
            summary.cashCollected,
            legacy.cashRevenue,
          );
          summary.advanceApplied = add(
            summary.advanceApplied,
            legacy.paymentBreakdown?.advance,
          );
          const legacyBreakdown = legacy.paymentBreakdown ?? {};
          const hasCardParts = Object.keys(legacyBreakdown).some((method) =>
            method.startsWith('card'),
          );
          if (!hasCardParts) {
            summary.legacyCardCollected = add(
              summary.legacyCardCollected,
              legacy.cardRevenue,
            );
          }
          for (const [method, amount] of Object.entries(legacyBreakdown)) {
            summary.paymentBreakdown[method] = add(
              summary.paymentBreakdown[method] ?? '0.00',
              amount,
            );
            if (method === 'card-tbc') {
              summary.tbcCollected = add(summary.tbcCollected, amount);
            } else if (method === 'card-bog') {
              summary.bogCollected = add(summary.bogCollected, amount);
            } else if (method === 'card') {
              summary.legacyCardCollected = add(
                summary.legacyCardCollected,
                amount,
              );
            }
          }
        } catch {
          // A malformed legacy summary is unavailable, never silently zeroed
          // into a claim of complete ledger history.
          source.provenance = 'PARTIAL';
          source.warning = warningFor('PARTIAL');
        }
      }
      summary.averageRevenueSale = summary.revenueSaleCount
        ? new Prisma.Decimal(summary.revenue)
            .dividedBy(summary.revenueSaleCount)
            .toFixed(2)
        : '0.00';
    }
    return { ...range, ...summary, ...source };
  }

  async listSales(
    tenant: TenantContext,
    query: {
      from?: string;
      to?: string;
      cursor?: string;
      limit?: string | number;
      paymentMethod?: string;
      staffId?: string;
      fiscal?: string;
      state?: string;
      menuItemId?: string;
      variantId?: string;
    },
  ) {
    const range = await this.range(tenant, query.from, query.to);
    const take = pageLimit(query.limit, 30);
    let cursor: { closedAt: Date; id: string } | null = null;
    if (query.cursor) {
      try {
        const [closedAt, id] = Buffer.from(query.cursor, 'base64url')
          .toString('utf8')
          .split('|');
        cursor = { closedAt: new Date(closedAt), id };
        if (!id || Number.isNaN(cursor.closedAt.valueOf())) throw new Error();
      } catch {
        throw new BadRequestException('Invalid Sale cursor');
      }
    }
    const state = query.state?.toLowerCase();
    const where: any = {
      venueId: tenant.venueId,
      businessDate: { gte: range.from, lte: range.to },
      ...(query.paymentMethod
        ? { payments: { some: { method: query.paymentMethod } } }
        : {}),
      ...(query.staffId ? { closedById: query.staffId } : {}),
      ...(query.fiscal === 'true' ? { isFiscal: true } : {}),
      ...(query.fiscal === 'false' ? { isFiscal: false } : {}),
      ...(state === 'voided' ? { isCancelled: true } : {}),
      ...(state === 'restored' ? { restoredToOrder: true } : {}),
      ...(state === 'active'
        ? { isCancelled: false, restoredToOrder: false }
        : {}),
      ...(query.menuItemId || query.variantId
        ? {
            lines: {
              some: {
                ...(query.menuItemId ? { menuItemId: query.menuItemId } : {}),
                ...(query.variantId ? { variantId: query.variantId } : {}),
              },
            },
          }
        : {}),
      ...(cursor
        ? {
            OR: [
              { closedAt: { lt: cursor.closedAt } },
              { closedAt: cursor.closedAt, id: { lt: cursor.id } },
            ],
          }
        : {}),
    };
    const rows = await (this.prisma as any).cloudSale.findMany({
      where,
      orderBy: [{ closedAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
      select: {
        id: true,
        posSaleId: true,
        posOrderId: true,
        closureId: true,
        businessDate: true,
        closedAt: true,
        gross: true,
        collectedNow: true,
        paymentMethod: true,
        isFiscal: true,
        isCancelled: true,
        restoredToOrder: true,
        closedById: true,
        createdBy: true,
        tableNumbers: true,
        floor: true,
        payments: { orderBy: { method: 'asc' } },
      },
    });
    const hasMore = rows.length > take;
    const page = rows.slice(0, take);
    const last = page.at(-1);
    const source = await this.detailProvenance(tenant, range.dates);
    return {
      ...range,
      ...source,
      sales: page.map((sale: any) => this.serializeSale(sale)),
      nextCursor:
        hasMore && last
          ? Buffer.from(`${last.closedAt.toISOString()}|${last.id}`).toString(
              'base64url',
            )
          : null,
    };
  }

  async getSale(tenant: TenantContext, id: string) {
    const sale = await (this.prisma as any).cloudSale.findFirst({
      where: { id, venueId: tenant.venueId },
      include: {
        lines: { orderBy: { lineSeq: 'asc' } },
        payments: { orderBy: { method: 'asc' } },
      },
    });
    if (!sale) throw new NotFoundException('Sale not found');
    const audit = await (this.prisma as any).auditReport.findFirst({
      where: {
        venueId: tenant.venueId,
        posOrderId: sale.posOrderId,
        ...(sale.closureId
          ? {
              events: {
                some: {
                  type: 'CLOSE',
                  details: {
                    path: ['closureId'],
                    equals: sale.closureId,
                  },
                },
              },
            }
          : {}),
      },
      select: { id: true, reportId: true },
      orderBy: { updatedAt: 'desc' },
    });
    return {
      ...this.serializeSale(sale),
      auditLink: audit
        ? {
            reportId: audit.reportId,
            cloudReportId: audit.id,
            posOrderId: sale.posOrderId,
            closureId: sale.closureId,
          }
        : null,
    };
  }

  async getProducts(
    tenant: TenantContext,
    query: { from?: string; to?: string; limit?: string | number },
  ) {
    const range = await this.range(tenant, query.from, query.to);
    const limit = pageLimit(query.limit, 20);
    const selection = Prisma.sql`
      SELECT
        line."menuItemId",
        line."variantId",
        (array_agg(line."itemName" ORDER BY sale."closedAt" DESC, sale."id" DESC))[1] AS "name",
        (array_agg(line."variantName" ORDER BY sale."closedAt" DESC, sale."id" DESC))[1] AS "variantName",
        SUM(line."quantity")::bigint AS "quantity",
        SUM(line."lineTotal") AS "revenue"
    `;
    const grouped = Prisma.sql`
      FROM "pos"."SaleLine" line
      JOIN "pos"."CloudSale" sale ON sale."id" = line."saleId"
      WHERE sale."venueId" = ${tenant.venueId}
        AND sale."businessDate" >= ${range.from}
        AND sale."businessDate" <= ${range.to}
        AND sale."isFiscal" = true
        AND sale."isCancelled" = false
        AND sale."restoredToOrder" = false
      GROUP BY
        line."menuItemId",
        line."variantId",
        CASE WHEN line."menuItemId" IS NULL THEN line."itemName" ELSE '' END,
        CASE WHEN line."menuItemId" IS NULL THEN COALESCE(line."variantName", '') ELSE '' END
    `;
    const byRevenueRows = await this.prisma.$queryRaw<ProductRow[]>(
      Prisma.sql`${selection} ${grouped} ORDER BY SUM(line."lineTotal") DESC LIMIT ${limit}`,
    );
    const byQuantityRows = await this.prisma.$queryRaw<ProductRow[]>(
      Prisma.sql`${selection} ${grouped} ORDER BY SUM(line."quantity") DESC, SUM(line."lineTotal") DESC LIMIT ${limit}`,
    );
    const serializeProduct = (row: ProductRow) => ({
      menuItemId: row.menuItemId,
      variantId: row.variantId,
      name: row.name,
      variantName: row.variantName,
      quantity: Number(row.quantity),
      revenue: money(row.revenue),
      manual: row.menuItemId == null,
    });
    const source = await this.detailProvenance(tenant, range.dates);
    return {
      ...range,
      ...source,
      byQuantity: byQuantityRows.map(serializeProduct),
      byRevenue: byRevenueRows.map(serializeProduct),
    };
  }

  async getStaff(
    tenant: TenantContext,
    query: { from?: string; to?: string; attribution?: string },
  ) {
    const attribution = query.attribution ?? 'closer';
    if (attribution !== 'creator' && attribution !== 'closer')
      throw new BadRequestException('Attribution must be creator or closer');
    const range = await this.range(tenant, query.from, query.to);
    return this.staffForRange(tenant, range, attribution);
  }

  /** All-time detail is complete only when declared days and the retained
   * POS summary agree. A summary alone never supplies employee attribution. */
  async getRecordedStaffHistory(tenant: TenantContext) {
    const [saleDates, days, summary] = await Promise.all([
      this.prisma.cloudSale.findMany({
        where: { venueId: tenant.venueId },
        distinct: ['businessDate'],
        select: { businessDate: true },
      }),
      this.prisma.saleLedgerDay.findMany({
        where: { venueId: tenant.venueId },
        select: { businessDate: true },
      }),
      this.prisma.setting.findUnique({
        where: {
          venueId_key: {
            venueId: tenant.venueId,
            key: 'salesSummary:all_time',
          },
        },
      }),
    ]);
    const dates = [
      ...new Set([...saleDates, ...days].map((row) => row.businessDate)),
    ].sort();
    const current = await this.currentDate(tenant);
    const range = {
      from: dates.at(0) ?? current,
      to: dates.at(-1) ?? current,
      dates,
    };
    const result = await this.staffForRange(tenant, range, 'creator');
    let matches = false;
    if (
      summary &&
      dates.length > 0 &&
      result.provenance === 'LEDGER_COMPLETE'
    ) {
      try {
        const raw: unknown = JSON.parse(summary.value);
        if (
          raw !== null &&
          typeof raw === 'object' &&
          'totalRevenue' in raw &&
          typeof raw.totalRevenue === 'number' &&
          Number.isFinite(raw.totalRevenue) &&
          'orderCount' in raw &&
          typeof raw.orderCount === 'number' &&
          Number.isSafeInteger(raw.orderCount)
        ) {
          const revenue = result.staff.reduce(
            (sum, row) => sum.plus(row.revenue),
            new Prisma.Decimal(0),
          );
          const count = result.staff.reduce(
            (sum, row) => sum + row.saleCount,
            0,
          );
          matches =
            revenue.equals(raw.totalRevenue) && count === raw.orderCount;
        }
      } catch {
        // Malformed aggregate evidence cannot establish all-time completeness.
        matches = false;
      }
    }
    return {
      ...result,
      provenance: matches ? ('LEDGER_COMPLETE' as const) : ('PARTIAL' as const),
      warning: matches
        ? null
        : 'All-time staff results cover retained detailed Sales only; complete day coverage and agreement with the POS retained-history summary are not established.',
    };
  }

  private async staffForRange(
    tenant: TenantContext,
    range: { from: string; to: string; dates: string[] },
    attribution: StaffAttribution,
  ) {
    // The column is chosen from two constants, never interpolated client SQL.
    const actor =
      attribution === 'creator'
        ? Prisma.sql`sale."createdBy"`
        : Prisma.sql`sale."closedById"`;
    const rows = await this.prisma.$queryRaw<
      Array<{
        actor: string | null;
        revenue: Prisma.Decimal;
        saleCount: bigint;
      }>
    >(Prisma.sql`
      SELECT ${actor} AS "actor", SUM(sale."gross") AS "revenue",
        COUNT(*)::bigint AS "saleCount"
      FROM "pos"."CloudSale" sale
      WHERE sale."venueId" = ${tenant.venueId}
        AND sale."businessDate" >= ${range.from}
        AND sale."businessDate" <= ${range.to}
        AND sale."isFiscal" = true
        AND sale."isCancelled" = false
        AND sale."restoredToOrder" = false
      GROUP BY ${actor}
      ORDER BY SUM(sale."gross") DESC, ${actor} ASC NULLS LAST
    `);
    const source = await this.detailProvenance(tenant, range.dates);
    return {
      ...range,
      ...source,
      attribution,
      attributionBasis: 'RECORDED_POS_USERNAME' as const,
      attributionWarning:
        'Names are frozen POS records. Renamed or reused usernames cannot prove a stable employee identity.',
      staff: rows.map((row) => {
        const saleCount = Number(row.saleCount);
        const revenue = money(row.revenue);
        return {
          ...recordedActor(row.actor),
          revenue,
          saleCount,
          averageSale: saleCount
            ? new Prisma.Decimal(revenue).dividedBy(saleCount).toFixed(2)
            : '0.00',
        };
      }),
    };
  }

  async getStaffPerformance(
    tenant: TenantContext,
    query: { from?: string; to?: string } = {},
  ) {
    const result = await this.getStaff(tenant, {
      ...query,
      attribution: 'creator',
    });
    return result.staff.map((row, index) => ({
      rank: index + 1,
      waiterName: row.staffName,
      totalSales: Number(row.revenue),
      orderCount: row.saleCount,
      avgOrderValue: Number(row.averageSale),
      staffId: row.staffId,
      identityBasis: row.identityBasis,
      identityStable: row.identityStable,
    }));
  }

  private serializeSale(sale: any) {
    return {
      ...sale,
      attribution: {
        creator: recordedActor((sale as { createdBy?: unknown }).createdBy),
        closer: recordedActor(sale.closedById),
      },
      gross: money(sale.gross),
      subtotal: sale.subtotal == null ? undefined : money(sale.subtotal),
      serviceFee: sale.serviceFee == null ? undefined : money(sale.serviceFee),
      discount: sale.discount == null ? undefined : money(sale.discount),
      manualAdjustment:
        sale.manualAdjustment == null
          ? undefined
          : money(sale.manualAdjustment),
      advanceApplied:
        sale.advanceApplied == null ? undefined : money(sale.advanceApplied),
      amountDueNow:
        sale.amountDueNow == null ? undefined : money(sale.amountDueNow),
      collectedNow: money(sale.collectedNow),
      payments: sale.payments?.map((part: any) => ({
        method: part.method,
        amount: money(part.amount),
      })),
      lines: sale.lines?.map((line: any) => ({
        ...line,
        unitPrice: money(line.unitPrice),
        lineTotal: money(line.lineTotal),
      })),
    };
  }
}
