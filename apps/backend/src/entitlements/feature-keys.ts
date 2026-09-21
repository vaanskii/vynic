/** Stable commercial capabilities. Resolution remains database-driven. */
export const FeatureKeys = {
  POS: 'POS',
  NON_FISCAL_CLOSE: 'NON_FISCAL_CLOSE',
  WEBSITE: 'WEBSITE',
  MANAGER_APP: 'MANAGER_APP',
  INVENTORY: 'INVENTORY',
  PAYROLL: 'PAYROLL',
  FINANCIAL_PLANNING: 'FINANCIAL_PLANNING',
  PROFITABILITY: 'PROFITABILITY',
  MANAGER_RESERVATIONS: 'MANAGER_RESERVATIONS',
  ADVANCED_AUDIT: 'ADVANCED_AUDIT',
} as const;
export type KnownFeatureKey = (typeof FeatureKeys)[keyof typeof FeatureKeys];
