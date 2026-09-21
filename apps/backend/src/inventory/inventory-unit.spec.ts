import { BadRequestException } from '@nestjs/common';
import {
  convertInventoryQuantity,
  inventoryUnit,
  inventoryUnitDimension,
} from './inventory-unit';

describe('Inventory units', () => {
  it('converts kg/g and L/ml canonically', () => {
    expect(convertInventoryQuantity(1, 'kg', 'g')).toBe(1000);
    expect(convertInventoryQuantity(2500, 'g', 'kg')).toBe(2.5);
    expect(convertInventoryQuantity(1, 'L', 'ml')).toBe(1000);
    expect(convertInventoryQuantity(750, 'ml', 'L')).toBe(0.75);
  });

  it('protects incompatible dimensions', () => {
    expect(() => convertInventoryQuantity(1, 'kg', 'L')).toThrow(
      BadRequestException,
    );
  });

  it('does not invent global count-unit ratios', () => {
    expect(inventoryUnitDimension('piece')).toBe('COUNT');
    expect(() => convertInventoryQuantity(1, 'box', 'piece')).toThrow(
      'No global conversion',
    );
  });

  it('accepts only canonical unit spellings', () => {
    expect(inventoryUnit('L')).toBe('L');
    expect(() => inventoryUnit('liter')).toThrow(BadRequestException);
  });
});
