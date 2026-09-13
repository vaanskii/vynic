jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { HybridNotificationService } from './notifications/hybrid-notification.service';
import { PresenceService } from './presence.service';
import {
  suppressPosEchoForOrder,
  isPosEchoSuppressed,
  suppressPosAuditBroadcast,
  isPosAuditBroadcastSuppressed,
} from '../pos/sync-echo-guard';

const a = { venueId: 'a', organizationId: 'org' },
  b = { venueId: 'b', organizationId: 'org' };

describe('Venue realtime boundaries', () => {
  afterEach(() => jest.useRealTimers());

  it('cannot suppress another Venue order or audit stream', () => {
    suppressPosEchoForOrder(a, 1);
    suppressPosAuditBroadcast(a);
    expect(isPosEchoSuppressed(a, 1)).toBe(true);
    expect(isPosEchoSuppressed(b, 1)).toBe(false);
    expect(isPosAuditBroadcastSuppressed(a)).toBe(true);
    expect(isPosAuditBroadcastSuppressed(b)).toBe(false);
  });

  it('coalesces repeated order IDs independently for each Venue', async () => {
    jest.useFakeTimers();
    const rows: any[] = [];
    const prisma = {
      venueSubscription: { findUnique: jest.fn(async () => null) },
      venue: {
        findUnique: jest.fn(async () => ({
          planAssignment: {
            plan: { features: [{ feature: { key: 'MANAGER_APP' } }] },
          },
          featureOverrides: [],
        })),
      },
      managerNotification: {
        create: jest.fn(async ({ data }) => {
          rows.push(data);
        }),
      },
      staff: { findMany: jest.fn(async () => []) },
    };
    const emitEnvelope = jest.fn(async () => undefined);
    const hybrid = new HybridNotificationService(
      prisma as never,
      new PresenceService(),
      { emitEnvelope } as never,
    );
    const payload = (summary: string) => ({
      source: 'pos_sync',
      touches: [
        { posOrderId: 1, changeKind: 'service_fee', changeSummary: summary },
      ],
    });
    await hybrid.deliver('orders_bulk_touch', payload('Venue A'), a);
    await hybrid.deliver('orders_bulk_touch', payload('Venue B'), b);
    await jest.advanceTimersByTimeAsync(2600);
    expect(rows).toHaveLength(2);
    expect(
      rows.find((r) => r.venueId === 'a').envelope.payload.touches[0]
        .changeSummary,
    ).toBe('Venue A');
    expect(
      rows.find((r) => r.venueId === 'b').envelope.payload.touches[0]
        .changeSummary,
    ).toBe('Venue B');
  });

  it('fails closed with no resolved notification tenant', async () => {
    const hybrid = new HybridNotificationService(
      {} as never,
      new PresenceService(),
      {} as never,
    );
    await expect(hybrid.deliver('day_closed', {}, {} as never)).rejects.toThrow(
      'resolved Venue',
    );
  });
});
