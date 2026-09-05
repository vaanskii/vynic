import { Prisma } from '@prisma/client';
import {
  lineMoney,
  nonNegativeCost,
  positiveMultiplier,
  positiveQuantity,
  resolveBaseQuantity,
  perUnitQuantity,
  recipeUnitsFor,
  resolveRecipeQuantity,
  sumMoney,
} from './inventory-quantity';

const decimal = (text: string) => new Prisma.Decimal(text);

describe('Receiving quantities', () => {
  it('converts global mass and volume without a configured ratio', () => {
    expect(
      resolveBaseQuantity({
        enteredQuantity: decimal('5000'),
        enteredUnit: 'g',
        baseUnit: 'kg',
      }),
    ).toMatchObject({ via: 'GLOBAL_UNIT' });
    expect(
      resolveBaseQuantity({
        enteredQuantity: decimal('5000'),
        enteredUnit: 'g',
        baseUnit: 'kg',
      }).baseQuantity.toFixed(3),
    ).toBe('5.000');
    expect(
      resolveBaseQuantity({
        enteredQuantity: decimal('1500'),
        enteredUnit: 'ml',
        baseUnit: 'L',
      }).baseQuantity.toFixed(3),
    ).toBe('1.500');
  });

  it('refuses to invent a ratio across dimensions', () => {
    expect(() =>
      resolveBaseQuantity({
        enteredQuantity: decimal('1'),
        enteredUnit: 'kg',
        baseUnit: 'L',
      }),
    ).toThrow('Cannot convert kg to L');
    expect(() =>
      resolveBaseQuantity({
        enteredQuantity: decimal('1'),
        enteredUnit: 'piece',
        baseUnit: 'kg',
      }),
    ).toThrow('Cannot convert piece to kg');
  });

  it('refuses an unconfigured count package rather than guessing', () => {
    expect(() =>
      resolveBaseQuantity({
        enteredQuantity: decimal('10'),
        enteredUnit: 'box',
        baseUnit: 'bottle',
      }),
    ).toThrow();
  });

  it('uses the item-specific package when one is configured', () => {
    const resolved = resolveBaseQuantity({
      enteredQuantity: decimal('10'),
      enteredUnit: 'box',
      baseUnit: 'bottle',
      purchaseUnits: [{ unit: 'box', baseUnitMultiplier: '24' }],
    });
    expect(resolved.via).toBe('PURCHASE_UNIT');
    expect(resolved.baseQuantity.toFixed(3)).toBe('240.000');
  });

  it('keeps one item’s box out of another item’s box', () => {
    const lemonade = resolveBaseQuantity({
      enteredQuantity: decimal('10'),
      enteredUnit: 'box',
      baseUnit: 'bottle',
      purchaseUnits: [{ unit: 'box', baseUnitMultiplier: '24' }],
    });
    const wine = resolveBaseQuantity({
      enteredQuantity: decimal('10'),
      enteredUnit: 'box',
      baseUnit: 'bottle',
      purchaseUnits: [{ unit: 'box', baseUnitMultiplier: '6' }],
    });
    expect(lemonade.baseQuantity.toFixed(3)).toBe('240.000');
    expect(wine.baseQuantity.toFixed(3)).toBe('60.000');
  });

  it('prefers the item ratio over the global one', () => {
    // A venue that buys 1 kg sacks it counts as 900 g of usable flour is
    // telling the truth about its own product; the global table is not.
    const resolved = resolveBaseQuantity({
      enteredQuantity: decimal('2'),
      enteredUnit: 'kg',
      baseUnit: 'g',
      purchaseUnits: [{ unit: 'kg', baseUnitMultiplier: '900' }],
    });
    expect(resolved.via).toBe('PURCHASE_UNIT');
    expect(resolved.baseQuantity.toFixed(3)).toBe('1800.000');
  });

  it('accepts fractional quantities at three decimals', () => {
    expect(positiveQuantity('12.750', 'q').toFixed(3)).toBe('12.750');
    expect(positiveQuantity('3.5', 'q').toFixed(3)).toBe('3.500');
    expect(() => positiveQuantity('0', 'q')).toThrow(
      'q must be greater than zero',
    );
    expect(() => positiveQuantity('-1', 'q')).toThrow();
    expect(() => positiveQuantity('abc', 'q')).toThrow();
  });

  it('allows a zero cost but never a negative one', () => {
    expect(nonNegativeCost('0', 'c').toFixed(4)).toBe('0.0000');
    expect(() => nonNegativeCost('-0.01', 'c')).toThrow();
  });

  it('rejects a non-positive packaging multiplier', () => {
    expect(positiveMultiplier('24', 'm').toString()).toBe('24');
    expect(() => positiveMultiplier('0', 'm')).toThrow();
    expect(() => positiveMultiplier('-6', 'm')).toThrow();
  });
});

describe('Receiving money', () => {
  it('multiplies quantity by unit cost exactly', () => {
    const { lineTotal } = lineMoney({
      enteredQuantity: decimal('50'),
      unitPurchaseCost: decimal('15.00'),
      baseQuantity: decimal('50'),
    });
    expect(lineTotal.toFixed(2)).toBe('750.00');
  });

  it('settles 0.1 + 0.2 without binary drift', () => {
    // 0.1 + 0.2 !== 0.3 in a double. The ledger has to say 0.30.
    const first = lineMoney({
      enteredQuantity: decimal('1'),
      unitPurchaseCost: decimal('0.10'),
      baseQuantity: decimal('1'),
    });
    const second = lineMoney({
      enteredQuantity: decimal('1'),
      unitPurchaseCost: decimal('0.20'),
      baseQuantity: decimal('1'),
    });
    expect(sumMoney([first.lineTotal, second.lineTotal]).toFixed(2)).toBe(
      '0.30',
    );
    expect(0.1 + 0.2).not.toBe(0.3);
  });

  it('accumulates a long document without drifting', () => {
    const totals = Array.from({ length: 10 }, () =>
      lineMoney({
        enteredQuantity: decimal('3'),
        unitPurchaseCost: decimal('0.10'),
        baseQuantity: decimal('3'),
      }).lineTotal,
    );
    expect(sumMoney(totals).toFixed(2)).toBe('3.00');
  });

  it('rounds a half-cent line half up, once', () => {
    const { lineTotal } = lineMoney({
      enteredQuantity: decimal('3'),
      unitPurchaseCost: decimal('0.005'),
      baseQuantity: decimal('3'),
    });
    expect(lineTotal.toFixed(2)).toBe('0.02');
  });

  it('preserves the effective base-unit cost through packaging', () => {
    // 10 boxes of 24 bottles at 28.80 GEL a box is 1.20 GEL a bottle.
    const { lineTotal, effectiveBaseUnitCost } = lineMoney({
      enteredQuantity: decimal('10'),
      unitPurchaseCost: decimal('28.80'),
      baseQuantity: decimal('240'),
    });
    expect(lineTotal.toFixed(2)).toBe('288.00');
    expect(effectiveBaseUnitCost.toFixed(6)).toBe('1.200000');
  });
  // ── Recipe consumption (Step 3) ───────────────────────────────────────

  it('normalizes a recipe entry into the item base unit', () => {
    expect(
      resolveRecipeQuantity({
        quantity: decimal('35'),
        unit: 'g',
        baseUnit: 'kg',
      }).baseQuantity.toFixed(3),
    ).toBe('0.035');
    expect(
      resolveRecipeQuantity({
        quantity: decimal('500'),
        unit: 'ml',
        baseUnit: 'L',
      }).baseQuantity.toFixed(3),
    ).toBe('0.500');
    expect(
      resolveRecipeQuantity({
        quantity: decimal('1'),
        unit: 'bottle',
        baseUnit: 'bottle',
      }).baseQuantity.toFixed(3),
    ).toBe('1.000');
  });

  it('refuses an incompatible dimension in a recipe', () => {
    expect(() =>
      resolveRecipeQuantity({
        quantity: decimal('1'),
        unit: 'kg',
        baseUnit: 'L',
      }),
    ).toThrow(/Cannot convert/);
  });

  it('refuses purchase packaging as a consumption unit', () => {
    // Receiving happily converts "1 box = 24 bottle". Consumption must not:
    // a box is how the venue buys lemonade, never how it serves it.
    expect(() =>
      resolveRecipeQuantity({
        quantity: decimal('1'),
        unit: 'box',
        baseUnit: 'bottle',
      }),
    ).toThrow(/not a consumption unit/);
  });

  it('offers only natural consumption units for a dimension', () => {
    expect(recipeUnitsFor('kg')).toEqual(['g', 'kg']);
    expect(recipeUnitsFor('L')).toEqual(['ml', 'L']);
    expect(recipeUnitsFor('bottle')).toEqual(['bottle']);
    expect(recipeUnitsFor('piece')).toEqual(['piece']);
  });

  it('divides a batch definition into per-sale-unit consumption', () => {
    // 100 khinkali from 3.5 kg of beef is 0.035 kg each.
    expect(
      perUnitQuantity(decimal('3.5'), decimal('100')).toFixed(6),
    ).toBe('0.035000');
    // A per-unit recipe is the same arithmetic with a yield of one.
    expect(perUnitQuantity(decimal('0.15'), decimal('1')).toFixed(6)).toBe(
      '0.150000',
    );
    expect(() => perUnitQuantity(decimal('1'), decimal('0'))).toThrow(
      /greater than zero/,
    );
  });
});
