/** Read projection only. Never applied to sync ingestion or stored evidence. */
const internalMethods = new Set([
  'non-fiscal',
  'nonfiscal',
  'non_fiscal',
  'internal',
]);
const hiddenFields = new Set([
  'nonFiscalClosedRevenue',
  'internalCount',
  'internalValue',
  'grossOperationalValue',
  'isFiscal',
  'originalIsFiscal',
]);
const internalEvents = new Set([
  'INTERNAL_CLOSE',
  'NON_FISCAL_CLOSE',
  'NONFISCAL_CLOSE',
]);
const nonFiscalMethod = (value: unknown) =>
  typeof value === 'string' && internalMethods.has(value.trim().toLowerCase());

function internalSale(value: any): boolean {
  if (!value || typeof value !== 'object' || value.isCancelled === true)
    return false;
  if (
    String(value.recordType ?? '').toLowerCase() === 'advance_receipt' ||
    value.paymentMethod === 'advance' ||
    ['ADVANCE', 'ADVANCE_RECEIPT', 'CANCELLED', 'CANCELLATION'].includes(
      value.classification,
    )
  )
    return false;
  return (
    value.classification === 'INTERNAL' ||
    ((value.posSaleId != null ||
      value.closedAt != null ||
      value.orderId != null) &&
      (value.isFiscal === false || nonFiscalMethod(value.paymentMethod)))
  );
}

export function withoutNonFiscal(value: unknown): any {
  if (Array.isArray(value))
    return value.filter((row) => !internalSale(row)).map(withoutNonFiscal);
  if (
    value &&
    typeof value === 'object' &&
    Object.getPrototypeOf(value) === Object.prototype
  ) {
    const row = value as Record<string, unknown>;
    const details = row.details as Record<string, unknown> | null;
    const internalEvent =
      internalEvents.has(String(row.type ?? '').toUpperCase()) ||
      (row.type === 'CLOSE' &&
        (details?.isFiscal === false ||
          nonFiscalMethod(details?.paymentMethod)));
    return Object.fromEntries(
      Object.entries(row)
        .filter(
          ([key, child]) =>
            !hiddenFields.has(key) &&
            !nonFiscalMethod(key) &&
            !(key === 'paymentMethod' && nonFiscalMethod(child)),
        )
        .map(([key, child]) => [
          key,
          internalEvent && key === 'type'
            ? 'CLOSE'
            : internalEvent && (key === 'note' || key === 'description')
              ? 'Order closed'
              : withoutNonFiscal(child),
        ]),
    );
  }
  return value;
}
