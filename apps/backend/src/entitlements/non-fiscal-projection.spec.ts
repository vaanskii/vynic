import { withoutNonFiscal } from './non-fiscal-projection';
import { firstValueFrom, of } from 'rxjs';
import { CommercialProjectionInterceptor } from './commercial-projection.interceptor';

describe('Nonfiscal customer projection', () => {
  it.each([{ features: [] }, { features: ['NON_FISCAL_CLOSE'] }])(
    'uses authoritative request Venue entitlements: %j',
    async ({ features }) => {
      const effectiveFeatures = jest.fn().mockResolvedValue(features);
      const interceptor = new CommercialProjectionInterceptor({
        effectiveFeatures,
      } as never);
      const payload = {
        internalCount: 1,
        revenue: '1000.00',
        events: [
          {
            type: 'CLOSE',
            note: 'Order closed (non-fiscal)',
            details: {
              isFiscal: false,
              paymentMethod: 'non-fiscal',
              grossAmount: 900,
            },
          },
        ],
      };
      const stream = await interceptor.intercept(
        {
          switchToHttp: () => ({
            getRequest: () => ({
              user: {
                venueId: 'server-owned-venue',
                organizationId: 'server-owned-organization',
              },
              query: { venueId: 'untrusted-venue' },
            }),
          }),
        } as never,
        { handle: () => of(payload) },
      );
      const projected = await firstValueFrom(stream);
      expect(effectiveFeatures).toHaveBeenCalledWith('server-owned-venue');
      expect(projected.revenue).toBe('1000.00');
      expect(projected.internalCount).toBe(features.length ? 1 : undefined);
      expect(JSON.stringify(projected).includes('non-fiscal')).toBe(
        features.length > 0,
      );
    },
  );
  it('hides internal sales and feature figures while retaining deposits, voids and audit evidence', () => {
    const original = {
      revenue: '1000.00',
      advanceApplied: '100.00',
      cashCollected: '900.00',
      internalCount: 1,
      internalValue: '900.00',
      nonFiscalClosedRevenue: 900,
      paymentBreakdown: { cash: 900, advance: 100, 'non-fiscal': 900 },
      sales: [
        { posSaleId: 'paid', isFiscal: true, gross: '1000.00' },
        { posSaleId: 'internal', isFiscal: false, gross: '900.00' },
        {
          orderId: 1,
          recordType: 'advance_receipt',
          isFiscal: false,
          total: 100,
        },
        { posSaleId: 'cancelled', isFiscal: false, isCancelled: true },
      ],
      events: [
        {
          type: 'INTERNAL_CLOSE',
          note: 'Order closed (non-fiscal)',
          details: {
            isFiscal: false,
            paymentMethod: 'non-fiscal',
            grossAmount: 900,
            collectedNow: 0,
          },
        },
      ],
    };
    const copy = JSON.stringify(original);
    const projected = withoutNonFiscal(original);
    expect(projected.revenue).toBe('1000.00');
    expect(
      projected.sales.map((s: any) => s.posSaleId ?? s.recordType),
    ).toEqual(['paid', 'advance_receipt', 'cancelled']);
    expect(projected.paymentBreakdown).toEqual({ cash: 900, advance: 100 });
    expect(projected.events).toEqual([
      {
        type: 'CLOSE',
        note: 'Order closed',
        details: { grossAmount: 900, collectedNow: 0 },
      },
    ]);
    expect(JSON.stringify(projected).toLowerCase()).not.toMatch(
      /non.?fiscal|internal/,
    );
    expect(JSON.stringify(original)).toBe(copy);
  });
});
