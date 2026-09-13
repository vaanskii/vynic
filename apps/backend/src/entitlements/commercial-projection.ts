/** Remove derived profitability only; purchasing/payment evidence and stock quantities remain. */
const derivedCostFields = new Set([
  'currentCost',
  'costsByItem',
  'weightedUnitCost',
  'lastPurchaseUnitCost',
  'costStatus',
  'inventoryValue',
  'costPerBaseUnit',
  'inventoryValueDelta',
  'issueUnitCost',
  'issueValue',
  'valuationStatus',
]);
export function withoutProfitability(value: unknown): any {
  if (Array.isArray(value)) return value.map(withoutProfitability);
  if (
    value &&
    typeof value === 'object' &&
    Object.getPrototypeOf(value) === Object.prototype
  ) {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !derivedCostFields.has(key))
        .map(([key, child]) => [key, withoutProfitability(child)]),
    );
  }
  return value;
}
