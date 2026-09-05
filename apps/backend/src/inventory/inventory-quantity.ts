import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  convertInventoryQuantity,
  inventoryUnit,
  inventoryUnitDimension,
  type InventoryUnit,
} from './inventory-unit';

/**
 * Exact arithmetic for the procurement ledger.
 *
 * Quantities and money never pass through binary floating point here. Every
 * value arrives as text, becomes a `Prisma.Decimal`, and is rounded once, at a
 * declared scale, at the moment it becomes durable. Accumulating `0.1 + 0.2` in
 * a `number` and storing the answer is exactly what this module exists to stop.
 */

/** Inventory quantities. Matches `Decimal(18, 3)` in the schema. */
export const QUANTITY_SCALE = 3;
/** GEL. Matches `Decimal(18, 2)`. */
export const MONEY_SCALE = 2;
/** Purchase cost of one entered unit. Matches `Decimal(18, 4)`. */
export const UNIT_COST_SCALE = 4;
/** Cost of one base unit, preserved for later weighted-average costing. */
export const BASE_UNIT_COST_SCALE = 6;
/** Packaging ratios. Matches `Decimal(18, 6)`. */
export const MULTIPLIER_SCALE = 6;

const ROUND_HALF_UP = Prisma.Decimal.ROUND_HALF_UP;

function parseDecimal(raw: unknown, field: string): Prisma.Decimal {
  if (raw === null || raw === undefined || raw === '') {
    throw new BadRequestException(`${field} is required`);
  }
  const text = String(raw).trim();
  if (!/^-?\d+(?:\.\d+)?$/.test(text)) {
    throw new BadRequestException(`${field} must be a decimal number`);
  }
  const value = new Prisma.Decimal(text);
  if (!value.isFinite()) {
    throw new BadRequestException(`${field} must be finite`);
  }
  return value;
}

/** A quantity that must be strictly greater than zero. */
export function positiveQuantity(raw: unknown, field: string): Prisma.Decimal {
  const value = parseDecimal(raw, field);
  if (value.lessThanOrEqualTo(0)) {
    throw new BadRequestException(`${field} must be greater than zero`);
  }
  return value.toDecimalPlaces(QUANTITY_SCALE, ROUND_HALF_UP);
}

/** A cost that may legitimately be zero (a free sample, a bonus case). */
export function nonNegativeCost(raw: unknown, field: string): Prisma.Decimal {
  const value = parseDecimal(raw, field);
  if (value.isNegative()) {
    throw new BadRequestException(`${field} must not be negative`);
  }
  return value.toDecimalPlaces(UNIT_COST_SCALE, ROUND_HALF_UP);
}

export function positiveMultiplier(
  raw: unknown,
  field: string,
): Prisma.Decimal {
  const value = parseDecimal(raw, field);
  if (value.lessThanOrEqualTo(0)) {
    throw new BadRequestException(`${field} must be greater than zero`);
  }
  return value.toDecimalPlaces(MULTIPLIER_SCALE, ROUND_HALF_UP);
}

export function money(value: Prisma.Decimal): Prisma.Decimal {
  return value.toDecimalPlaces(MONEY_SCALE, ROUND_HALF_UP);
}

export function quantity(value: Prisma.Decimal): Prisma.Decimal {
  return value.toDecimalPlaces(QUANTITY_SCALE, ROUND_HALF_UP);
}

export function moneyText(value: unknown): string {
  return new Prisma.Decimal((value ?? 0) as never).toFixed(MONEY_SCALE);
}

export function quantityText(value: unknown): string {
  return new Prisma.Decimal((value ?? 0) as never).toFixed(QUANTITY_SCALE);
}

export function unitCostText(value: unknown): string {
  return new Prisma.Decimal((value ?? 0) as never).toFixed(UNIT_COST_SCALE);
}

export function baseUnitCostText(value: unknown): string {
  return new Prisma.Decimal((value ?? 0) as never).toFixed(
    BASE_UNIT_COST_SCALE,
  );
}

export function multiplierText(value: unknown): string {
  const decimal = new Prisma.Decimal((value ?? 0) as never);
  // Ratios read as "24", not "24.000000", unless they genuinely have decimals.
  return decimal.toDecimalPlaces(MULTIPLIER_SCALE).toString();
}

export interface PurchaseUnitRatio {
  unit: string;
  baseUnitMultiplier: Prisma.Decimal | string | number;
}

export interface ResolvedQuantity {
  baseQuantity: Prisma.Decimal;
  /** How many base units one entered unit contained. */
  multiplier: Prisma.Decimal;
  /** How the ratio was found, for error messages and for tests. */
  via: 'IDENTITY' | 'PURCHASE_UNIT' | 'GLOBAL_UNIT';
}

/**
 * How many base units a receiving line actually delivered.
 *
 * Resolution order is deliberate. The base unit itself is free. An
 * item-specific packaging row wins next, because "1 box = 24 bottle" is a fact
 * about this product that no global table can know. Only then does the global
 * mass/volume table apply. Anything else is refused rather than guessed —
 * `kg -> L` and an unconfigured `box -> kg` are both real data-entry mistakes,
 * and silently inventing a ratio would corrupt the ledger permanently.
 */
export function resolveBaseQuantity(input: {
  enteredQuantity: Prisma.Decimal;
  enteredUnit: string;
  baseUnit: string;
  purchaseUnits?: readonly PurchaseUnitRatio[];
}): ResolvedQuantity {
  const entered = inventoryUnit(input.enteredUnit);
  const base = inventoryUnit(input.baseUnit);

  if (entered === base) {
    return {
      baseQuantity: quantity(input.enteredQuantity),
      multiplier: new Prisma.Decimal(1),
      via: 'IDENTITY',
    };
  }

  const configured = (input.purchaseUnits ?? []).find(
    (row) => row.unit === entered,
  );
  if (configured) {
    const multiplier = new Prisma.Decimal(
      configured.baseUnitMultiplier as never,
    );
    if (multiplier.lessThanOrEqualTo(0)) {
      throw new BadRequestException(
        `purchase unit ${entered} has a non-positive multiplier`,
      );
    }
    return {
      baseQuantity: quantity(input.enteredQuantity.times(multiplier)),
      multiplier,
      via: 'PURCHASE_UNIT',
    };
  }

  if (inventoryUnitDimension(entered) !== inventoryUnitDimension(base)) {
    throw new BadRequestException(`Cannot convert ${entered} to ${base}`);
  }

  const converted = convertInventoryQuantity(1, entered, base);
  const multiplier = new Prisma.Decimal(converted);
  return {
    baseQuantity: quantity(input.enteredQuantity.times(multiplier)),
    multiplier,
    via: 'GLOBAL_UNIT',
  };
}

/** Consumption quantities per sold unit. Matches `Decimal(18, 6)`. */
export const PER_UNIT_SCALE = 6;

export function perUnitQuantityText(value: unknown): string {
  return new Prisma.Decimal((value ?? 0) as never).toFixed(PER_UNIT_SCALE);
}

/**
 * The natural consumption units for an item held in `baseUnit`.
 *
 * A kitchen weighs beef in grams and pours beer in millilitres, so mass and
 * volume offer both scales. A counted item offers only itself: "1 box of
 * khinkali" is not a consumption fact, and `box` is procurement packaging.
 */
export function recipeUnitsFor(baseUnit: string): InventoryUnit[] {
  const base = inventoryUnit(baseUnit);
  switch (inventoryUnitDimension(base)) {
    case 'MASS':
      return ['g', 'kg'];
    case 'VOLUME':
      return ['ml', 'L'];
    case 'COUNT':
      return [base];
  }
}

/**
 * How many base units one sold portion consumes.
 *
 * Deliberately narrower than {@link resolveBaseQuantity}: only the base unit
 * itself and the global mass/volume table convert here. Item packaging is
 * excluded on purpose — "1 box" is how a venue buys lemonade, never how it
 * serves it, and letting a purchase ratio through would quietly turn a
 * data-entry slip into a 24x consumption error.
 */
export function resolveRecipeQuantity(input: {
  quantity: Prisma.Decimal;
  unit: string;
  baseUnit: string;
}): { baseQuantity: Prisma.Decimal } {
  const entered = inventoryUnit(input.unit);
  const base = inventoryUnit(input.baseUnit);

  if (entered === base) {
    return { baseQuantity: quantity(input.quantity) };
  }
  if (inventoryUnitDimension(entered) !== inventoryUnitDimension(base)) {
    throw new BadRequestException(`Cannot convert ${entered} to ${base}`);
  }
  if (inventoryUnitDimension(base) === 'COUNT') {
    throw new BadRequestException(
      `${entered} is purchase packaging, not a consumption unit; enter this recipe in ${base}`,
    );
  }
  const multiplier = new Prisma.Decimal(
    convertInventoryQuantity(1, entered, base),
  );
  return { baseQuantity: quantity(input.quantity.times(multiplier)) };
}

/**
 * Consumption for one sold unit, from a definition written for a batch.
 *
 * A kitchen enters "100 khinkali need 3.5 kg beef"; every later step wants
 * "0.035 kg". Dividing once, here, at a declared scale, is what keeps those
 * two facts from disagreeing.
 */
export function perUnitQuantity(
  baseQuantity: Prisma.Decimal,
  yieldQuantity: Prisma.Decimal,
): Prisma.Decimal {
  if (yieldQuantity.lessThanOrEqualTo(0)) {
    throw new BadRequestException('yieldQuantity must be greater than zero');
  }
  return baseQuantity
    .dividedBy(yieldQuantity)
    .toDecimalPlaces(PER_UNIT_SCALE, ROUND_HALF_UP);
}

export interface LineMoney {
  lineTotal: Prisma.Decimal;
  effectiveBaseUnitCost: Prisma.Decimal;
}

/**
 * `lineTotal = enteredQuantity x unitPurchaseCost`, rounded once to exact GEL.
 *
 * `effectiveBaseUnitCost` divides that settled total by the base quantity, so
 * "288.00 GEL for 240 bottles" preserves "1.20 GEL/bottle" without any later
 * step having to re-derive it from the packaging.
 */
export function lineMoney(input: {
  enteredQuantity: Prisma.Decimal;
  unitPurchaseCost: Prisma.Decimal;
  baseQuantity: Prisma.Decimal;
}): LineMoney {
  const lineTotal = money(input.enteredQuantity.times(input.unitPurchaseCost));
  const effectiveBaseUnitCost = input.baseQuantity.isZero()
    ? new Prisma.Decimal(0)
    : lineTotal
        .dividedBy(input.baseQuantity)
        .toDecimalPlaces(BASE_UNIT_COST_SCALE, ROUND_HALF_UP);
  return { lineTotal, effectiveBaseUnitCost };
}

export function sumMoney(values: readonly Prisma.Decimal[]): Prisma.Decimal {
  return money(
    values.reduce(
      (total, value) => total.plus(value),
      new Prisma.Decimal(0),
    ),
  );
}

export type { InventoryUnit };
