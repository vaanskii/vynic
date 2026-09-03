import { normalizeChangeSummary } from './notification-summary.util';
import type { WsEventType } from '../ws-events';

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

function todayIsoDate(): string {
  return new Date().toISOString().slice(0, 10);
}

function formatTableNumbers(raw: unknown): string {
  if (!Array.isArray(raw)) return '';
  return raw
    .map((e) => asString(e).trim())
    .filter((s) => s.length > 0 && s !== '0')
    .join(', ');
}

function isWalkInCustomerName(name: string): boolean {
  const n = name.trim().toLowerCase();
  return n === 'walk-in' || n.includes('walk-in') || n === 'walk in';
}

/** Shared copy for reservation / table WS payloads (FCM + DB). */
export function buildReservationsDataUpdatedCopy(p: Record<string, unknown>): {
  title: string;
  body: string;
} {
  const action = asString(p.action).trim().toLowerCase();
  const customerName = asString(p.customerName).trim();
  const resDateRaw = asString(p.reservationDate).trim();
  const resDate =
    resDateRaw.length >= 10 ? resDateRaw.slice(0, 10) : resDateRaw;
  const resTime = asString(p.reservationTime).trim();
  const tables = formatTableNumbers(p.tableNumbers);
  const today = todayIsoDate();

  const detailParts: string[] = [];
  if (customerName.length > 0) detailParts.push(customerName);
  if (tables.length > 0) detailParts.push(`მაგიდა ${tables}`);
  if (resTime.length > 0) detailParts.push(`დრო: ${resTime}`);
  if (resDate.length > 0 && resDate !== today) {
    detailParts.push(`თარიღი: ${resDate}`);
  }
  const detail = detailParts.join(' • ');

  if (action === 'deleted' || action === 'cancelled') {
    return {
      title: 'რეზერვაცია',
      body:
        detail.length > 0
          ? `რეზერვაცია გაუქმდა — ${detail}`
          : 'რეზერვაცია გაუქმდა',
    };
  }

  if (isWalkInCustomerName(customerName)) {
    return {
      title: 'მაგიდა',
      body: detail.length > 0 ? `ახალი walk-in — ${detail}` : 'ახალი walk-in',
    };
  }

  if (action === 'created') {
    const isFuture = resDate.length > 0 && resDate > today;
    const headline = isFuture ? 'მომავალი რეზერვაცია' : 'ახალი რეზერვაცია';
    return {
      title: 'რეზერვაციები',
      body: detail.length > 0 ? `${headline} — ${detail}` : headline,
    };
  }

  if (action === 'updated' || action.length > 0) {
    return {
      title: 'რეზერვაციები',
      body:
        detail.length > 0
          ? `რეზერვაცია განახლდა — ${detail}`
          : 'რეზერვაცია განახლდა',
    };
  }

  return {
    title: 'რეზერვაციები',
    body: detail.length > 0 ? `რეზერვაცია — ${detail}` : 'რეზერვაცია განახლდა',
  };
}

function buildOrderCreatedCopy(p: Record<string, unknown>): {
  title: string;
  body: string;
} {
  const id = asOrderId(p.posOrderId);
  const walkIn = p.walkIn === true;
  const tableLabel = asString(p.tableLabel).trim();
  const tableNumbers = formatTableNumbers(p.tableNumbers);
  const tableSeg =
    tableLabel.length > 0
      ? tableLabel
      : tableNumbers.length > 0
        ? tableNumbers
        : '';
  const tablePart = tableSeg.length > 0 ? ` — მაგიდა $tableSeg` : '';
  const idPart = id !== null ? ' #$id' : '';

  if (walkIn) {
    return {
      title: 'მაგიდა',
      body: `ახალი walk-in${idPart}${tablePart}`,
    };
  }
  return {
    title: 'შეკვეთა',
    body:
      id !== null
        ? `შეიქმნა ახალი შეკვეთა #${id}${tablePart}`
        : `შეიქმნა ახალი შეკვეთა${tablePart}`,
  };
}

function buildOrderCancelledCopy(p: Record<string, unknown>): {
  title: string;
  body: string;
} {
  const id = asOrderId(p.posOrderId);
  const tableLabel = asString(p.tableLabel).trim();
  if (tableLabel.length > 0) {
    return {
      title: 'მაგიდა',
      body: `მაგიდა $tableLabel გაუქმდა`,
    };
  }
  return {
    title: 'შეკვეთა',
    body: id !== null ? `შეკვეთა #$id გაუქმდა` : 'შეკვეთა გაუქმდა',
  };
}

function buildTablesBulkTouchCopy(p: Record<string, unknown>): {
  title: string;
  body: string;
} | null {
  const touchesRaw = p.touches;
  const touches = Array.isArray(touchesRaw)
    ? touchesRaw.filter(
        (t): t is Record<string, unknown> =>
          Boolean(t) && typeof t === 'object' && !Array.isArray(t),
      )
    : [];

  const freed = [...touches]
    .reverse()
    .find((t) => asString(t.changeType).toLowerCase() === 'freed');
  if (freed) {
    const tableNumber = asString(freed.tableNumber).trim();
    if (tableNumber.length > 0) {
      return {
        title: 'მაგიდა',
        body: `მაგიდა $tableNumber გაუქმდა`,
      };
    }
  }

  // Reserved tables are covered by order_created; avoid duplicate POS toasts.
  return null;
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
        body: id !== null ? `დაემატა შეკვეთა #${id}` : 'დაემატა შეკვეთა',
      };
    }
    case 'takeaway_deleted': {
      const id = asOrderId(p?.posOrderId);
      return {
        title: 'გატანა',
        body: id !== null ? `შეკვეთა წაიშალა #${id}` : 'შეკვეთა წაიშალა',
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
        body:
          summary.length > 0
            ? `${bodyCore} — ${summary}`
            : `${bodyCore} განახლდა`,
      };
    }
    case 'tables_bulk_touch':
      return p ? buildTablesBulkTouchCopy(p) : null;
    case 'order_updated': {
      const src = asString(p?.source);
      const isPos = src === 'pos_sync';
      const singleId = asOrderId(p?.posOrderId);
      const idsRaw = p?.posOrderIds;
      const ids = Array.isArray(idsRaw)
        ? idsRaw
            .map((e) => asOrderId(e))
            .filter((id): id is number => id !== null)
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
    case 'order_cancelled':
      return p ? buildOrderCancelledCopy(p) : null;
    case 'order_created':
      return p ? buildOrderCreatedCopy(p) : null;
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
          return p ? buildReservationsDataUpdatedCopy(p) : null;
        case 'tables': {
          const tableNumber = asString(p?.tableNumber).trim();
          const floor = asString(p?.floor).trim();
          const action = asString(p?.action).trim().toLowerCase();
          if (action === 'freed' || action === 'cancelled') {
            const label = tableNumber.length > 0 ? tableNumber : 'მაგიდა';
            return {
              title: 'მაგიდა',
              body: `მაგიდა $label გაუქმდა`,
            };
          }
          if (tableNumber.length > 0) {
            return {
              title: 'მაგიდები',
              body: `მაგიდა $tableNumber განახლდა`,
            };
          }
          return {
            title: 'მაგიდები',
            body: 'მაგიდის სტატუსი განახლდა',
          };
        }
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
