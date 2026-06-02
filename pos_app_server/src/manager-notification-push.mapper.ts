import { normalizeChangeSummary } from './notification-summary.util';
import type { WsEventType } from './ws-events';

function asRecord(p: unknown): Record<string, unknown> | null {
  if (p && typeof p === 'object' && !Array.isArray(p)) {
    return p as Record<string, unknown>;
  }
  return null;
}

function asString(value: unknown): string {
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  return '';
}

function asOrderId(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function isDecreaseSummary(summary: string): boolean {
  const match = summary.match(/(\d+)\s*→\s*(\d+)/);
  if (!match) return false;
  const prev = Number(match[1]);
  const next = Number(match[2]);
  return Number.isFinite(prev) && Number.isFinite(next) && next < prev;
}

/**
 * Human-readable copy for FCM / DB when mirroring manager notification panel rules.
 * Returns null when this WS event should not create a stored manager notification.
 */
export function buildManagerPushCopy(
  type: WsEventType,
  payload: unknown,
): { title: string; body: string } | null {
  const p = asRecord(payload);

  switch (type) {
    case 'takeaway_created': {
      const id = asOrderId(p?.posOrderId);
      return {
        title: 'გატანა',
        body:
          id !== null
            ? `დაემატა შეკვეთა #${id}`
            : 'დაემატა შეკვეთა',
      };
    }
    case 'takeaway_deleted': {
      const id = asOrderId(p?.posOrderId);
      return {
        title: 'გატანა',
        body:
          id !== null
            ? `შეკვეთა წაიშალა #${id}`
            : 'შეკვეთა წაიშალა',
      };
    }
    case 'orders_bulk_touch': {
      const touchesRaw = p?.touches;
      const touches = Array.isArray(touchesRaw)
        ? touchesRaw.filter(
            (t): t is Record<string, unknown> =>
              Boolean(t) && typeof t === 'object' && !Array.isArray(t),
          )
        : [];
      const meaningful = touches.find((t) => {
        const kind = asString(t.changeKind).trim().toLowerCase();
        if (kind === 'service_fee') return true;
        const summary = asString(t.changeSummary).trim();
        if (!summary) return false;
        return isDecreaseSummary(summary);
      });
      if (!meaningful) return null;
      const orderId = asOrderId(meaningful.posOrderId);
      const summary = normalizeChangeSummary(meaningful.changeSummary);
      const kind = asString(meaningful.changeKind).trim().toLowerCase();
      const tableLabel = asString(meaningful.tableLabel).trim();
      if (kind === 'service_fee') {
        const state =
          summary.length > 0 ? summary : 'სერვისის საფასური განახლდა';
        const tableSeg =
          tableLabel.length > 0 && tableLabel !== '-'
            ? `მაგიდა ${tableLabel}`
            : orderId !== null
              ? `შეკვეთა #${orderId}`
              : 'შეკვეთა';
        return {
          title: 'მაგიდები',
          body: `${tableSeg} — ${state}`,
        };
      }
      const bodyCore = orderId !== null ? `შეკვეთა #${orderId}` : 'შეკვეთა';
      return {
        title: 'სალარო',
        body: summary.length > 0
          ? `${bodyCore} — ${summary}`
          : `${bodyCore} განახლდა`,
      };
    }
    case 'tables_bulk_touch':
      // POS often emits this together with orders_bulk_touch; keep mobile panel/push single-source.
      return null;
    case 'order_updated': {
      const src = asString(p?.source);
      const isPos = src === 'pos_sync';
      const singleId = asOrderId(p?.posOrderId);
      const idsRaw = p?.posOrderIds;
      const ids = Array.isArray(idsRaw)
        ? idsRaw.map((e) => asOrderId(e)).filter((id): id is number => id !== null)
        : [];
      if (ids.length > 1) {
        return {
          title: isPos ? 'სალარო' : 'შეკვეთები',
          body: `განახლდა ${ids.length} შეკვეთა`,
        };
      }
      const id = singleId ?? ids[0] ?? null;
      if (id === null) {
        return {
          title: isPos ? 'სალარო' : 'მენეჯერი',
          body: 'შეკვეთა განახლდა',
        };
      }
      return {
        title: isPos ? 'სალარო' : 'მენეჯერი',
        body: isPos
          ? `შეკვეთა #${id} განახლდა (სალარო)`
          : `შეკვეთა #${id} განახლდა (მენეჯერი)`,
      };
    }
    case 'order_cancelled': {
      const id = asOrderId(p?.posOrderId);
      return {
        title: 'შეკვეთა',
        body: id !== null ? `გაუქმდა #${id}` : 'გაუქმდა შეკვეთა',
      };
    }
    case 'order_created': {
      const id = asOrderId(p?.posOrderId);
      return {
        title: 'შეკვეთა',
        body: id !== null ? `შეიქმნა ახალი შეკვეთა #${id}` : 'შეიქმნა ახალი შეკვეთა',
      };
    }
    case 'table_updated':
      return null;
    case 'day_closed':
      return {
        title: 'დღის დახურვა',
        body: 'ბიზნეს დღის სტატუსი შეიცვალა',
      };
    case 'data_updated': {
      const inner = asString(p?.type);
      switch (inner) {
        case 'reservations':
          return {
            title: 'რეზერვაციები',
            body: 'მონაცემები განახლდა',
          };
        case 'tables':
          return {
            title: 'მაგიდები',
            body: 'მონაცემები განახლდა',
          };
        case 'menu':
          return {
            title: 'მენიუ',
            body: 'მენიუ განახლდა',
          };
        case 'all':
        default:
          return null;
      }
    }
    default:
      return null;
  }
}
