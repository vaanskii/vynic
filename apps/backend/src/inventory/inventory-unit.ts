import { BadRequestException } from '@nestjs/common';

export const INVENTORY_UNITS = [
  'kg',
  'g',
  'L',
  'ml',
  'piece',
  'bottle',
  'pack',
  'box',
  'keg',
] as const;

export type InventoryUnit = (typeof INVENTORY_UNITS)[number];
export type InventoryUnitDimension = 'MASS' | 'VOLUME' | 'COUNT';

const UNIT_DIMENSIONS: Record<InventoryUnit, InventoryUnitDimension> = {
  kg: 'MASS',
  g: 'MASS',
  L: 'VOLUME',
  ml: 'VOLUME',
  piece: 'COUNT',
  bottle: 'COUNT',
  pack: 'COUNT',
  box: 'COUNT',
  keg: 'COUNT',
};

const TO_CANONICAL: Partial<Record<InventoryUnit, number>> = {
  kg: 1000,
  g: 1,
  L: 1000,
  ml: 1,
};

export function inventoryUnit(raw: unknown): InventoryUnit {
  const value = typeof raw === 'string' ? raw.trim() : '';
  if ((INVENTORY_UNITS as readonly string[]).includes(value)) {
    return value as InventoryUnit;
  }
  throw new BadRequestException(
    `baseUnit must be one of: ${INVENTORY_UNITS.join(', ')}`,
  );
}

export function inventoryUnitDimension(
  unit: InventoryUnit,
): InventoryUnitDimension {
  return UNIT_DIMENSIONS[unit];
}

/**
 * Converts only globally canonical mass/volume pairs.
 *
 * Count labels deliberately have no global ratio: one box may contain 6
 * pieces for one item and 24 for another. Packaging belongs to a later step.
 */
export function convertInventoryQuantity(
  value: number,
  from: InventoryUnit,
  to: InventoryUnit,
): number {
  if (!Number.isFinite(value)) {
    throw new BadRequestException('quantity must be finite');
  }
  if (from === to) return value;
  if (UNIT_DIMENSIONS[from] !== UNIT_DIMENSIONS[to]) {
    throw new BadRequestException(`Cannot convert ${from} to ${to}`);
  }
  const fromFactor = TO_CANONICAL[from];
  const toFactor = TO_CANONICAL[to];
  if (fromFactor == null || toFactor == null) {
    throw new BadRequestException(
      `No global conversion exists between ${from} and ${to}`,
    );
  }
  return (value * fromFactor) / toFactor;
}

export const INVENTORY_UNIT_DEFINITIONS = INVENTORY_UNITS.map((code) => ({
  code,
  dimension: UNIT_DIMENSIONS[code],
}));
