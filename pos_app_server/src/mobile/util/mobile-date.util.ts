// Shared date / business-date / payment helpers for the mobile manager API.
//
// Extracted verbatim from MobileController so controller-split services
// (reports, dashboard, orders, …) can share them without importing the
// controller (which would create a circular dependency). Behavior unchanged.

export function todayStart(): Date {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

export function yesterdayStart(): Date {
  const d = todayStart();
  d.setDate(d.getDate() - 1);
  return d;
}

export function parseBusinessDateStart(businessDate: string): Date {
  const [y, m, d] = businessDate.split('-').map(Number);
  return new Date(y, m - 1, d, 0, 0, 0, 0);
}

export function nextDay(start: Date): Date {
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return end;
}

export function previousDay(start: Date): Date {
  const prev = new Date(start);
  prev.setDate(prev.getDate() - 1);
  return prev;
}

export function normalizePaymentType(raw: string | null | undefined): string {
  const key = (raw ?? 'cash').trim().toLowerCase();
  if (key === '') return 'cash';
  if (key.startsWith('card-')) return key;
  if (key === 'card_tbc') return 'card-tbc';
  if (key === 'card_bog') return 'card-bog';
  return key;
}

export function businessDateWhere(
  businessDate: string,
): { OR: Array<Record<string, unknown>> } {
  const start = parseBusinessDateStart(businessDate);
  const end = nextDay(start);
  return {
    OR: [
      { businessDate },
      { businessDate: '', createdAt: { gte: start, lt: end } },
    ],
  };
}

export function pctChange(today: number, yesterday: number): number {
  if (yesterday === 0) return today > 0 ? 100 : 0;
  return Math.round(((today - yesterday) / yesterday) * 1000) / 10;
}

export async function readRestaurantServiceFeeSettings(prisma: any) {
  const [percentRow, enabledRow] = await Promise.all([
    (prisma as any).setting.findUnique({
      where: { key: 'restaurant:serviceFeePercent' },
    }),
    (prisma as any).setting.findUnique({
      where: { key: 'restaurant:serviceFeeEnabled' },
    }),
  ]);
  const serviceFeePercent = percentRow ? Number(percentRow.value) : 10;
  const serviceFeeEnabled = enabledRow?.value === 'true';
  return {
    serviceFeePercent,
    serviceFeeEnabled,
    serviceFeeAvailable: serviceFeeEnabled && serviceFeePercent > 0,
  };
}
