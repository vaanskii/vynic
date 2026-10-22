import { BadRequestException } from '@nestjs/common';

export interface HistoryQuery {
  from?: string;
  to?: string;
  unmapped?: string;
  cursor?: string;
  limit?: string;
}
interface HistoryCursor {
  version: 1;
  scope: string;
  from: string | null;
  to: string | null;
  unmapped: boolean;
  createdBefore: string;
  at: string;
  id: string;
}
function day(value: string | undefined) {
  if (value == null) return null;
  const date = new Date(value + 'T00:00:00.000Z');
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 10) !== value
  )
    throw new BadRequestException('Invalid history date');
  return value;
}
function isInstant(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    Number.isFinite(Date.parse(value)) &&
    new Date(value).toISOString() === value
  );
}

/** A creation window, not a snapshot of mutable reversal/payment state. Every
 * query still resolves Venue independently of this untrusted cursor. */
export function historyPage(scope: string, query: HistoryQuery) {
  const from = day(query.from),
    to = day(query.to);
  if (from && to && from > to)
    throw new BadRequestException('Invalid history range');
  if (query.unmapped != null && !['true', 'false'].includes(query.unmapped))
    throw new BadRequestException('Invalid unmapped filter');
  const unmapped = query.unmapped === 'true';
  const limit = query.limit == null ? 50 : Number(query.limit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100)
    throw new BadRequestException('History limit must be 1–100');
  let cursor: HistoryCursor | null = null;
  if (query.cursor != null) {
    try {
      if (query.cursor.length > 4096 || !/^[A-Za-z0-9_-]+$/.test(query.cursor))
        throw Error();
      const raw: unknown = JSON.parse(
        Buffer.from(query.cursor, 'base64url').toString('utf8'),
      );
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw Error();
      const c = raw as HistoryCursor;
      if (
        c.version !== 1 ||
        c.scope !== scope ||
        c.from !== from ||
        c.to !== to ||
        c.unmapped !== unmapped ||
        !isInstant(c.createdBefore) ||
        !isInstant(c.at) ||
        typeof c.id !== 'string' ||
        !c.id ||
        c.id.length > 500
      )
        throw Error();
      cursor = c;
    } catch {
      throw new BadRequestException(
        'Invalid history cursor or changed filters',
      );
    }
  }
  const createdBefore = cursor?.createdBefore ?? new Date().toISOString();
  return {
    limit,
    from,
    to,
    unmapped,
    cursor,
    createdBefore: new Date(createdBefore),
    envelope<T extends { id: string }>(rows: T[], at: (row: T) => Date) {
      const hasMore = rows.length > limit;
      const items = rows.slice(0, limit);
      const last = items.at(-1);
      return {
        items,
        nextCursor:
          hasMore && last
            ? Buffer.from(
                JSON.stringify({
                  version: 1,
                  scope,
                  from,
                  to,
                  unmapped,
                  createdBefore,
                  at: at(last).toISOString(),
                  id: last.id,
                } satisfies HistoryCursor),
              ).toString('base64url')
            : null,
        window: {
          recordsCreatedBefore: createdBefore,
          state: 'CURRENT_AT_EACH_REQUEST',
        },
      };
    },
  };
}
