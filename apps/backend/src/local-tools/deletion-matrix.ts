import { Prisma } from '@prisma/client';

/** Explicit child-first order; never infer ownership from an arbitrary request. */
export const venueModels = [
  'StockMovement',
  'SaleConsumptionComponent',
  'SaleConsumptionLine',
  'SaleConsumption',
  'MenuConsumptionComponent',
  'MenuConsumptionRecipe',
  'SupplierPayment',
  'ReceivingLine',
  'Receiving',
  'SupplierProduct',
  'StockItemPurchaseUnit',
  'StockItem',
  'Supplier',
  'PayrollAccrual',
  'PayrollPayment',
  'PayrollPeriod',
  'StaffCompensation',
  'Staff',
  'ObligationPayment',
  'ObligationReserveEntry',
  'ObligationCycle',
  'FinancialObligation',
  'WebsiteReservationTable',
  'WebsiteReservation',
  'WebsiteTable',
  'PaymentIntegration',
  'OrderItem',
  'Order',
  'Table',
  'SaleLine',
  'SalePayment',
  'CloudSale',
  'SaleLedgerDay',
  'MenuItemWebsitePresentation',
  'MenuCatalogMutation',
  'MenuCatalogTombstone',
  'MenuItemVariant',
  'MenuItem',
  'MenuSubcategory',
  'MenuCategory',
  'AuditEvent',
  'AuditReport',
  'AuditEventLog',
  'QuickOrderDraftItem',
  'QuickOrderDraft',
  'ManagerNotificationDelivery',
  'ManagerNotification',
  'Expense',
  'PosReservation',
  'DailySnapshot',
  'Setting',
  'PushDevice',
  'PosCallbackOutbox',
  'EdgeCommand',
  'DeviceEnrollment',
  'Device',
  'EdgeFoundationInstallation',
  'SubscriptionBillingEvent',
  'SubscriptionBillingOperation',
  'VenueSubscription',
  'VenuePlanAssignment',
  'VenueFeatureOverride',
  'WebsiteHostnameRequest',
  'CustomWebsiteBinding',
  'VenueWebsiteCapability',
  'VenueWebsiteConfig',
  'VenuePublicProfile',
  'VenueDomain',
  'WebsiteMediaAsset',
] as const;
export const preservedModels = [
  'PlatformUser',
  'PlatformAuditEvent',
  'Plan',
  'Feature',
  'PlanFeature',
  'OnboardingPolicy',
] as const;
export const specialModels = [
  'Venue',
  'Organization',
  'OrganizationMembership',
  'OwnerInvitation',
  'CustomerAccount',
  'CustomerAuditEvent',
  'OnboardingRequest',
  'WebsiteUser',
] as const;
const parentPaths: Record<string, string> = {
  ReceivingLine: 'receiving',
  WebsiteReservationTable: 'reservation',
  OrderItem: 'order',
  SaleLine: 'sale',
  SalePayment: 'sale',
  MenuItemVariant: 'menuItem',
  MenuSubcategory: 'category',
  AuditEvent: 'report',
  QuickOrderDraftItem: 'draft',
  ManagerNotificationDelivery: 'notification',
  SubscriptionBillingEvent: 'operation',
};
export function venueFilter(model: string, ids: string[]) {
  const filter = { venueId: { in: ids } };
  return parentPaths[model] ? { [parentPaths[model]]: filter } : filter;
}
/** A schema addition requires an explicit ownership decision before any delete. */
export function assertMatrixComplete() {
  const classified = new Set<string>([
    ...venueModels,
    ...preservedModels,
    ...specialModels,
  ]);
  const actual = Prisma.dmmf.datamodel.models.map((m) => m.name);
  if (
    actual.length !== classified.size ||
    actual.some((name) => !classified.has(name))
  )
    throw new Error(
      'Deletion matrix differs from Prisma models; audit the schema first',
    );
}
// Limited to the audited model names above, never a client-selected delegate.
export function delegate(tx: Prisma.TransactionClient, model: string) {
  return (
    tx as unknown as Record<
      string,
      {
        count(args?: { where: object }): Promise<number>;
        deleteMany(args: { where: object }): Promise<{ count: number }>;
      }
    >
  )[model[0].toLowerCase() + model.slice(1)];
}
