import {
  Injectable,
  type CallHandler,
  type ExecutionContext,
  type NestInterceptor,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { mergeMap } from 'rxjs';
import { PrismaService } from '../../prisma.service';
import type {
  PosAuthContext,
  TenantContext,
} from '../../auth/pos-auth-context';
import type { SyncPayload } from '../../pos/sync/sync-payload';

export const FRESHNESS_HEADER = 'X-Vynic-Data-Freshness';
const prefix = 'manager:data-freshness:';
export type ManagerDataBlock =
  | 'dashboard'
  | 'tables'
  | 'financials'
  | 'staff_performance'
  | 'menu'
  | 'top_items'
  | 'counted_menus'
  | 'sales_report'
  | 'report_all'
  | 'report_history'
  | 'sales_daily'
  | 'reservations'
  | 'takeaway';
export interface ManagerSourceStamp {
  source: 'POS' | 'CLOUD' | 'UNKNOWN';
  sourceUpdatedAt: string | null;
  receivedAt: string | null;
  completeness: 'KNOWN' | 'PARTIAL' | 'UNKNOWN' | 'UNAVAILABLE';
  generation?: string;
}
interface StoredStamp extends ManagerSourceStamp {
  deviceId: string | null;
}
function instant(value: unknown): string | null {
  if (typeof value !== 'string' || !/(Z|[+-]\d\d:\d\d)$/.test(value))
    return null;
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date.toISOString();
}

/** Only called inside the authenticated snapshot transaction, after its writes. */
export async function recordManagerSource(
  db: PrismaService,
  auth: PosAuthContext,
  data: SyncPayload,
  tablesApplied: boolean,
  reservationsComplete: boolean,
  ledgerApplied = false,
): Promise<void> {
  const receivedAt = new Date().toISOString();
  const sourceTime = instant(data.syncedAt);
  const sourceUpdatedAt =
    sourceTime && Date.parse(sourceTime) <= Date.parse(receivedAt) + 60000
      ? sourceTime
      : null;
  const stamp: StoredStamp = {
    source: 'POS',
    sourceUpdatedAt,
    receivedAt,
    completeness: sourceUpdatedAt ? 'KNOWN' : 'UNKNOWN',
    deviceId: auth.deviceId,
    generation: randomUUID(),
  };
  const validSummary =
    data.salesSummary &&
    /^\d{4}-\d{2}-\d{2}$/.test(data.salesSummary.date) &&
    data.salesSummary.date === data.businessDate;
  const blocks: ManagerDataBlock[] = [];
  if (tablesApplied && data.tables !== undefined) blocks.push('tables');
  if (data.orders !== undefined) blocks.push('takeaway');
  if (!data.realtimeOnly) {
    // Full reporting values are not refreshed by a partial realtime upload.
    if (
      validSummary &&
      data.orders !== undefined &&
      data.tables !== undefined &&
      data.salesHistoryByDate !== undefined &&
      tablesApplied
    )
      blocks.push('dashboard');
    if (validSummary) blocks.push('financials', 'sales_report');
    if (data.salesAllTimeSummary) blocks.push('report_all');
    if (data.salesHistoryByDate !== undefined) blocks.push('sales_daily');
    if (data.salesHistoryByDate !== undefined) blocks.push('report_history');
    if (data.reservations !== undefined) blocks.push('reservations');
    if (data.menu !== undefined) blocks.push('menu');
  }
  for (const block of blocks) {
    const key = prefix + block;
    const value = JSON.stringify(
      (block === 'reservations' && !reservationsComplete) ||
        (block === 'tables' && data.tableLayout === undefined) ||
        block === 'sales_report' ||
        block === 'report_history' ||
        (block === 'report_all' &&
          !Array.isArray(data.salesAllTimeSummary?.topItems))
        ? { ...stamp, completeness: 'PARTIAL' }
        : stamp,
    );
    await db.setting.upsert({
      where: { venueId_key: { venueId: auth.venueId, key } },
      create: { venueId: auth.venueId, key, value },
      update: { value },
    });
  }
  if (ledgerApplied && !data.realtimeOnly) {
    const dates = new Set([
      ...(data.saleLedgerDays ?? []).map((day) => day.businessDate),
      ...(data.saleLedger ?? []).map((sale) => sale.businessDate),
    ]);
    for (const date of dates) {
      const key = prefix + 'ledger:' + date;
      const day = await db.saleLedgerDay.findUnique({
        where: {
          venueId_businessDate: { venueId: auth.venueId, businessDate: date },
        },
      });
      const value = JSON.stringify({
        ...stamp,
        completeness:
          day?.completeness === 'COMPLETE' &&
          data.saleLedgerDays?.some(
            (d) => d.businessDate === date && d.uploadComplete,
          )
            ? stamp.completeness
            : 'PARTIAL',
      });
      await db.setting.upsert({
        where: { venueId_key: { venueId: auth.venueId, key } },
        create: { venueId: auth.venueId, key, value },
        update: { value },
      });
    }
  }
}

function readStamp(
  raw: string | undefined,
  primary: string | null,
): ManagerSourceStamp {
  const unknown: ManagerSourceStamp = {
    source: 'UNKNOWN',
    sourceUpdatedAt: null,
    receivedAt: null,
    completeness: 'UNKNOWN',
  };
  if (!raw) return unknown;
  let value: StoredStamp;
  try {
    value = JSON.parse(raw) as StoredStamp;
  } catch {
    return unknown;
  }
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return unknown;
  if (value.source !== 'POS' || value.deviceId !== primary) return unknown;
  const receivedAt = instant(value.receivedAt);
  if (!receivedAt) return unknown;
  const sourceUpdatedAt = instant(value.sourceUpdatedAt);
  return {
    source: 'POS',
    sourceUpdatedAt,
    receivedAt,
    generation: value.generation,
    completeness:
      value.completeness === 'PARTIAL'
        ? 'PARTIAL'
        : sourceUpdatedAt && value.deviceId !== null
          ? 'KNOWN'
          : 'UNKNOWN',
  };
}

export async function managerSource(
  db: PrismaService,
  tenant: TenantContext,
  block: ManagerDataBlock | `ledger:${string}`,
): Promise<ManagerSourceStamp> {
  const unknown: ManagerSourceStamp = {
    source: 'UNKNOWN',
    sourceUpdatedAt: null,
    receivedAt: null,
    completeness:
      block === 'staff_performance' || block === 'top_items'
        ? 'UNAVAILABLE'
        : 'UNKNOWN',
  };
  // Staff attribution is deliberately unavailable in the existing read model.
  if (block === 'staff_performance' || block === 'top_items') return unknown;
  if (block === 'counted_menus')
    return { ...unknown, source: 'CLOUD', completeness: 'KNOWN' };
  const [row, venue] = await Promise.all([
    db.setting.findUnique({
      where: { venueId_key: { venueId: tenant.venueId, key: prefix + block } },
    }),
    db.venue.findUnique({
      where: { id: tenant.venueId },
      select: { activeOperationalDeviceId: true, menuAuthority: true },
    }),
  ]);
  if (block === 'menu' && venue?.menuAuthority === 'CLOUD')
    return { ...unknown, source: 'CLOUD', completeness: 'KNOWN' };
  if (!row || !venue) return unknown;
  const result = readStamp(row.value, venue.activeOperationalDeviceId);
  if (block === 'dashboard' || block === 'financials') {
    const current = await db.setting.findUnique({
      where: {
        venueId_key: { venueId: tenant.venueId, key: 'currentBusinessDate' },
      },
    });
    if (current) {
      const day = await db.saleLedgerDay.findUnique({
        where: {
          venueId_businessDate: {
            venueId: tenant.venueId,
            businessDate: current.value,
          },
        },
      });
      if (day)
        return combineSources([
          result,
          await managerSource(db, tenant, `ledger:${current.value}`),
        ]);
    }
  }
  return result;
}

function combineSources(values: ManagerSourceStamp[]): ManagerSourceStamp {
  const unknown: ManagerSourceStamp = {
    source: 'UNKNOWN',
    sourceUpdatedAt: null,
    receivedAt: null,
    completeness: 'UNKNOWN',
  };
  if (
    !values.length ||
    values.some(
      (value) =>
        value.source !== 'POS' || !value.sourceUpdatedAt || !value.receivedAt,
    )
  )
    return unknown;
  return {
    source: 'POS',
    sourceUpdatedAt: values.map((value) => value.sourceUpdatedAt!).sort()[0],
    receivedAt: values.map((value) => value.receivedAt!).sort()[0],
    completeness: values.every((value) => value.completeness === 'KNOWN')
      ? 'KNOWN'
      : 'PARTIAL',
    generation: values.map((value) => value.generation ?? '').join(':'),
  };
}

async function ledgerSource(
  db: PrismaService,
  tenant: TenantContext,
  query: { from?: string; to?: string },
): Promise<ManagerSourceStamp> {
  const current = await db.setting.findUnique({
    where: {
      venueId_key: { venueId: tenant.venueId, key: 'currentBusinessDate' },
    },
  });
  const from = query.from ?? current?.value,
    to = query.to ?? from;
  if (
    !from ||
    !to ||
    !/^\d{4}-\d{2}-\d{2}$/.test(from) ||
    !/^\d{4}-\d{2}-\d{2}$/.test(to)
  )
    return combineSources([]);
  const start = new Date(from + 'T00:00:00Z'),
    end = new Date(to + 'T00:00:00Z');
  if (
    Number.isNaN(start.valueOf()) ||
    Number.isNaN(end.valueOf()) ||
    start > end ||
    end.valueOf() - start.valueOf() > 365 * 86400000
  )
    return combineSources([]);
  const keys: string[] = [];
  for (
    let date = start;
    date <= end;
    date = new Date(date.valueOf() + 86400000)
  )
    keys.push(prefix + 'ledger:' + date.toISOString().slice(0, 10));
  const [rows, venue] = await Promise.all([
    db.setting.findMany({
      where: { venueId: tenant.venueId, key: { in: keys } },
      select: { key: true, value: true },
    }),
    db.venue.findUnique({
      where: { id: tenant.venueId },
      select: { activeOperationalDeviceId: true },
    }),
  ]);
  if (!venue) return combineSources([]);
  const byKey = new Map(rows.map((row) => [row.key, row.value]));
  return combineSources(
    keys.map((key) =>
      readStamp(byKey.get(key), venue.activeOperationalDeviceId),
    ),
  );
}

const reads: Record<string, ManagerDataBlock> = {
  getFinancialSummary: 'financials',
  getSales: 'financials',
  getProductAnalytics: 'financials',
  getSaleStaffAnalytics: 'financials',
  getDashboard: 'dashboard',
  getTables: 'tables',
  getFinancials: 'financials',
  getStaffPerformance: 'staff_performance',
  getMenu: 'menu',
  getCountedMenus: 'counted_menus',
  getTopItems: 'top_items',
  getSalesReport: 'sales_report',
  getSalesDaily: 'sales_daily',
  getReservations: 'reservations',
  getTakeawayOrders: 'takeaway',
};
@Injectable()
export class ManagerDataFreshnessInterceptor implements NestInterceptor {
  constructor(private readonly db: PrismaService) {}
  async intercept(context: ExecutionContext, next: CallHandler) {
    let block = reads[context.getHandler().name];
    if (block) {
      const request = context.switchToHttp().getRequest<{
        user: TenantContext;
        query?: { period?: string; from?: string; to?: string };
      }>();
      if (block === 'sales_report' && request.query?.period === 'all')
        block = 'report_all';
      if (
        block === 'sales_report' &&
        ['week', 'month'].includes(request.query?.period ?? '')
      )
        block = 'report_history';
      const ledgerRead = [
        'getFinancialSummary',
        'getSales',
        'getProductAnalytics',
        'getSaleStaffAnalytics',
      ].includes(context.getHandler().name);
      const sourceBlock = block;
      const read = () =>
        ledgerRead
          ? ledgerSource(this.db, request.user, request.query ?? {})
          : managerSource(this.db, request.user, sourceBlock);
      const stamp = await read();
      return next.handle().pipe(
        mergeMap(async (value: unknown) => {
          const after = ledgerRead
            ? await ledgerSource(this.db, request.user, request.query ?? {})
            : await managerSource(this.db, request.user, sourceBlock);
          // Ingest commits mirrors and generation together. A mixed read cannot
          // claim a complete source from either side of a concurrent transaction.
          const coherent = JSON.stringify(after) === JSON.stringify(stamp);
          context
            .switchToHttp()
            .getResponse<{ setHeader(name: string, value: string): void }>()
            .setHeader(
              FRESHNESS_HEADER,
              JSON.stringify(
                coherent
                  ? stamp
                  : {
                      source: 'UNKNOWN',
                      sourceUpdatedAt: null,
                      receivedAt: null,
                      completeness: 'UNKNOWN',
                    },
              ),
            );
          return value;
        }),
      );
    }
    return next.handle();
  }
}
