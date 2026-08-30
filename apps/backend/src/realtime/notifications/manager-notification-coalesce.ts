import { mergeChangeSummaries } from './notification-summary.util';
import type { BroadcastOptions, WsEventType } from '../ws-events';

const SERVICE_FEE_COALESCE_MS = 2500;

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

function normalizeTouches(
  payload: Record<string, unknown>,
): Record<string, unknown>[] {
  const touchesRaw = payload.touches;
  if (!Array.isArray(touchesRaw)) return [];
  return touchesRaw.filter(
    (t): t is Record<string, unknown> =>
      Boolean(t) && typeof t === 'object' && !Array.isArray(t),
  );
}

/**
 * When every touch is a service-fee toggle, batch push/FCM until the user stops
 * flipping the switch (avoids notification spam from rapid on/off).
 */
export function getServiceFeeCoalesceKey(
  type: WsEventType,
  payload: unknown,
): string | null {
  if (type !== 'orders_bulk_touch') return null;
  const p = asRecord(payload);
  if (!p) return null;
  const touches = normalizeTouches(p);
  if (touches.length === 0) return null;
  const allServiceFee = touches.every(
    (t) => asString(t.changeKind).trim().toLowerCase() === 'service_fee',
  );
  if (!allServiceFee) return null;
  const ids = touches
    .map((t) => asOrderId(t.posOrderId))
    .filter((id): id is number => id !== null)
    .sort((a, b) => a - b);
  if (ids.length === 0) return null;
  const src = asString(p.source).trim() || 'unknown';
  return `service_fee:${src}:${ids.join(',')}`;
}

export function mergeOrdersBulkTouchPayload(
  existing: unknown,
  incoming: unknown,
): Record<string, unknown> {
  const prev = asRecord(existing) ?? {};
  const next = asRecord(incoming) ?? {};
  const byId = new Map<number, Record<string, unknown>>();

  for (const touch of [...normalizeTouches(prev), ...normalizeTouches(next)]) {
    const id = asOrderId(touch.posOrderId);
    if (id === null) continue;
    const prev = byId.get(id);
    const mergedSummary = mergeChangeSummaries(
      prev?.changeSummary,
      touch.changeSummary,
    );
    byId.set(id, {
      ...prev,
      ...touch,
      ...(mergedSummary ? { changeSummary: mergedSummary } : {}),
    });
  }

  const touches = [...byId.values()].sort(
    (a, b) => (asOrderId(a.posOrderId) ?? 0) - (asOrderId(b.posOrderId) ?? 0),
  );

  return {
    ...prev,
    ...next,
    touches,
    posOrderIds: touches
      .map((t) => asOrderId(t.posOrderId))
      .filter((id): id is number => id !== null),
    source:
      asString(next.source).trim() ||
      asString(prev.source).trim() ||
      'pos_sync',
  };
}

export type CoalescedDeliverFn = (
  type: WsEventType,
  payload: unknown,
  options?: BroadcastOptions,
) => Promise<void>;

export class ServiceFeeNotificationCoalescer {
  private readonly pending = new Map<
    string,
    {
      timer: ReturnType<typeof setTimeout>;
      type: WsEventType;
      payload: Record<string, unknown>;
      options?: BroadcastOptions;
    }
  >();

  constructor(
    private readonly quietMs: number,
    private readonly onFlush: CoalescedDeliverFn,
  ) {}

  schedule(
    key: string,
    type: WsEventType,
    payload: unknown,
    options?: BroadcastOptions,
  ): void {
    const incoming = asRecord(payload) ?? {};
    const existing = this.pending.get(key);
    if (existing) {
      clearTimeout(existing.timer);
      existing.payload = mergeOrdersBulkTouchPayload(
        existing.payload,
        incoming,
      );
      existing.options = options ?? existing.options;
      existing.timer = setTimeout(() => {
        void this.flush(key);
      }, this.quietMs);
      return;
    }

    this.pending.set(key, {
      type,
      payload: { ...incoming },
      options,
      timer: setTimeout(() => {
        void this.flush(key);
      }, this.quietMs),
    });
  }

  private async flush(key: string): Promise<void> {
    const entry = this.pending.get(key);
    if (!entry) return;
    this.pending.delete(key);
    clearTimeout(entry.timer);
    await this.onFlush(entry.type, entry.payload, entry.options);
  }
}

export const defaultServiceFeeCoalesceMs = SERVICE_FEE_COALESCE_MS;
