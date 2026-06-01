import type { WsEventType } from './ws-events';

function asRecord(p: unknown): Record<string, unknown> | null {
  if (p && typeof p === 'object' && !Array.isArray(p)) {
    return p as Record<string, unknown>;
  }
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
      const id = p?.posOrderId;
      return {
        title: 'გატანა',
        body:
          id !== undefined && id !== null
            ? `დაემატა შეკვეთა #${id}`
            : 'დაემატა შეკვეთა',
      };
    }
    case 'takeaway_deleted': {
      const id = p?.posOrderId;
      return {
        title: 'გატანა',
        body:
          id !== undefined && id !== null
            ? `შეკვეთა წაიშალა #${id}`
            : 'შეკვეთა წაიშალა',
      };
    }
    case 'orders_bulk_touch':
      return {
        title: 'სალარო',
        body: 'შეკვეთა განახლდა (მენიუ / რაოდენობა)',
      };
    case 'tables_bulk_touch':
      return {
        title: 'მაგიდები',
        body: 'მაგიდის სტატუსი შეიცვალა',
      };
    case 'order_updated': {
      const src = String(p?.source ?? '');
      const isPos = src === 'pos_sync';
      const singleId = p?.posOrderId ?? (Array.isArray(p?.posOrderIds) ? null : null);
      const ids = Array.isArray(p?.posOrderIds)
        ? (p!.posOrderIds as unknown[])
            .map((e) => (typeof e === 'number' ? e : Number.parseInt(String(e), 10)))
            .filter((n) => Number.isFinite(n))
        : [];
      if (ids.length > 1) {
        return {
          title: isPos ? 'სალარო' : 'შეკვეთები',
          body: `განახლდა ${ids.length} შეკვეთა`,
        };
      }
      const id = singleId ?? ids[0];
      if (id === undefined || id === null || Number.isNaN(Number(id))) {
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
      const id = p?.posOrderId;
      return {
        title: 'შეკვეთა',
        body:
          id !== undefined && id !== null ? `გაუქმდა #${id}` : 'გაუქმდა შეკვეთა',
      };
    }
    case 'order_created': {
      const id = p?.posOrderId;
      return {
        title: 'შეკვეთა',
        body:
          id !== undefined && id !== null
            ? `შეიქმნა ახალი შეკვეთა #${id}`
            : 'შეიქმნა ახალი შეკვეთა',
      };
    }
    case 'table_updated':
      return {
        title: 'მაგიდები',
        body: 'მაგიდების სტატუსი განახლდა',
      };
    case 'day_closed':
      return {
        title: 'დღის დახურვა',
        body: 'ბიზნეს დღის სტატუსი შეიცვალა',
      };
    case 'data_updated': {
      const inner = String(p?.type ?? '');
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
