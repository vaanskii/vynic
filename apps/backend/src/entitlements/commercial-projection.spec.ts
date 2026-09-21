import { withoutProfitability } from './commercial-projection';
import { commercialAccessAllowed } from './subscription-policy';
describe('Commercial projection', () => {
  it('retains raw quantities and purchasing evidence while removing derived valuation', () => {
    expect(
      withoutProfitability({
        currentStock: '15.000',
        currentCost: { total: '50' },
        lines: [
          {
            unitPurchaseCost: '5',
            costPerBaseUnit: '4.5',
            inventoryValueDelta: '9',
            quantityDeltaBase: '2',
          },
        ],
        recipe: {
          currentCost: { total: '5' },
          components: [{ baseQuantityPerUnit: '0.5' }],
        },
      }),
    ).toEqual({
      currentStock: '15.000',
      lines: [{ unitPurchaseCost: '5', quantityDeltaBase: '2' }],
      recipe: { components: [{ baseQuantityPerUnit: '0.5' }] },
    });
  });
  it.each(['TRIAL', 'ACTIVE', 'PAST_DUE', null])(
    'allows explicit grace and rollout compatibility: %s',
    (status) => expect(commercialAccessAllowed(status)).toBe(true),
  );
  it.each(['SUSPENDED', 'CANCELLED', 'unknown'])(
    'denies inactive/unknown state: %s',
    (status) => expect(commercialAccessAllowed(status)).toBe(false),
  );
});
