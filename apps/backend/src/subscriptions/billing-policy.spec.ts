import {
  classifyPlanChange,
  nextRenewal,
  prorateUpgrade,
} from './billing-policy';
const d = (s: string) => new Date(s + 'T00:00:00Z');
describe('billing calendar, classification and minor-unit proration', () => {
  it('charges half the positive difference without resetting renewal', () => {
    expect(
      prorateUpgrade(
        5000,
        15000,
        d('2026-09-25'),
        d('2026-10-25'),
        d('2026-10-10'),
      ),
    ).toBe(5000);
    expect(
      prorateUpgrade(
        15000,
        5000,
        d('2026-09-25'),
        d('2026-10-25'),
        d('2026-10-10'),
      ),
    ).toBe(0);
    expect(
      prorateUpgrade(0, 1, d('2026-09-25'), d('2026-10-25'), d('2026-10-10')),
    ).toBe(1);
    expect(
      prorateUpgrade(0, 1, d('2026-09-25'), d('2026-10-25'), d('2026-10-11')),
    ).toBe(0);
  });
  it('clamps month ends without drifting the anchor', () => {
    expect(nextRenewal(d('2028-01-31'), 'MONTH', d('2028-01-31'))).toEqual(
      d('2028-02-29'),
    );
    expect(nextRenewal(d('2028-01-31'), 'MONTH', d('2028-02-29'))).toEqual(
      d('2028-03-31'),
    );
    expect(nextRenewal(d('2028-02-29'), 'YEAR', d('2029-02-28'))).toEqual(
      d('2030-02-28'),
    );
    expect(nextRenewal(d('2026-09-25'), 'MONTH', d('2026-09-25'))).toEqual(
      d('2026-10-25'),
    );
  });
  it('rejects invalid prices, dates and out-of-period calculation', () => {
    for (const price of [-1, 0.5, NaN])
      expect(() =>
        prorateUpgrade(
          price,
          20,
          d('2026-09-25'),
          d('2026-10-25'),
          d('2026-10-10'),
        ),
      ).toThrow();
    expect(() =>
      prorateUpgrade(10, 20, d('2026-09-25'), d('2026-10-25'), d('2026-10-25')),
    ).toThrow();
    expect(() =>
      nextRenewal(d('2026-09-25'), 'WEEK', d('2026-09-25')),
    ).toThrow();
  });
  it('uses capability inclusion and sends unsafe mixed changes to review', () => {
    const current = {
      priceMinor: 5000,
      currency: 'GEL',
      billingPeriod: 'MONTH',
      features: ['WEBSITE'],
    };
    expect(
      classifyPlanChange(current, {
        ...current,
        priceMinor: 1000,
        features: ['WEBSITE', 'POS'],
      }),
    ).toBe('UPGRADE');
    expect(classifyPlanChange(current, { ...current, features: ['POS'] })).toBe(
      'REVIEW',
    );
    expect(
      classifyPlanChange(current, { ...current, billingPeriod: 'YEAR' }),
    ).toBe('RENEWAL_CHANGE');
    expect(
      classifyPlanChange(current, {
        ...current,
        billingPeriod: 'YEAR',
        features: ['WEBSITE', 'POS'],
      }),
    ).toBe('REVIEW');
    expect(
      classifyPlanChange({ ...current, features: ['WEBSITE', 'POS'] }, current),
    ).toBe('DOWNGRADE');
  });
});
