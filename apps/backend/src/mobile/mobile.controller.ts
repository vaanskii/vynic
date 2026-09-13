import { UseInterceptors } from '@nestjs/common';
import { CommercialProjectionInterceptor } from '../entitlements/commercial-projection.interceptor';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { SaleConsumptionService } from '../inventory/sale-consumption.service';
import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Headers,
  Param,
  Body,
  Query,
  UseGuards,
  ParseIntPipe,
  DefaultValuePipe,
  Req,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  ManagerAuth,
  ManagerTenant,
  type ManagerAuthContext,
} from '../auth/manager-auth-context';
import type { TenantContext } from '../tenancy/tenant-context';
import { FeatureGuard } from '../entitlements/feature.guard';
import { FeatureKeys } from '../entitlements/feature-keys';
import { RequiresFeature } from '../entitlements/requires-feature.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { StaffRole } from '../staff/staff-role';
import { MobileUsersService } from './services/mobile-users.service';
import { MobileAuditLogService } from './services/mobile-audit-log.service';
import type { AuditLogQuery } from './services/mobile-audit-log.service';
import { MobileReportsService } from './services/mobile-reports.service';
import { MobileDevicesService } from './services/mobile-devices.service';
import { MobileMenuService } from './services/mobile-menu.service';
import { MobileMutationSupport } from './services/mobile-mutation-support.service';
import { MobileReservationsService } from './services/mobile-reservations.service';
import { MobileDashboardService } from './services/mobile-dashboard.service';
import { MobileOrdersService } from './services/mobile-orders.service';
import { MobileSaleLedgerService } from './services/mobile-sale-ledger.service';
import {
  InventoryService,
  type StockItemInput,
  type SupplierInput,
} from '../inventory/inventory.service';
import {
  ReceivingService,
  type ReceivingInput,
} from '../inventory/receiving.service';
import { RecipeService, type RecipeInput } from '../inventory/recipe.service';

// ─── Controller ───────────────────────────────────────────────────────────────

@UseInterceptors(CommercialProjectionInterceptor)
@Controller('mobile')
@UseGuards(JwtAuthGuard, RolesGuard, FeatureGuard)
@Roles(StaffRole.MANAGER)
@RequiresFeature(FeatureKeys.MANAGER_APP)
export class MobileController {
  constructor(
    private readonly entitlements: VenueEntitlementsService,
    private readonly users: MobileUsersService,
    private readonly reports: MobileReportsService,
    private readonly auditLog: MobileAuditLogService,
    private readonly devices: MobileDevicesService,
    private readonly menu: MobileMenuService,
    private readonly mutationSupport: MobileMutationSupport,
    private readonly reservations: MobileReservationsService,
    private readonly dashboard: MobileDashboardService,
    private readonly orders: MobileOrdersService,
    private readonly saleLedger: MobileSaleLedgerService,
    private readonly inventory: InventoryService,
    private readonly consumption: SaleConsumptionService,
    private readonly receiving: ReceivingService,
    private readonly recipes: RecipeService,
  ) {}

  @Get('entitlements')
  entitlementsSnapshot(@ManagerTenant() tenant: TenantContext) {
    return this.entitlements.snapshot(tenant.venueId);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/consumptions')
  consumptions(
    @ManagerTenant() tenant: TenantContext,
    @Query() query: { from?: string; to?: string; unmapped?: string },
  ) {
    return this.consumption.list(tenant, query);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/consumptions/:id')
  consumptionDetail(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.consumption.detail(tenant, id);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/overview')
  getInventoryOverview(@ManagerTenant() tenant: TenantContext) {
    return this.inventory.overview(tenant);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/units')
  getInventoryUnits() {
    return this.inventory.getUnits();
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/stock-items')
  getStockItems(
    @ManagerTenant() tenant: TenantContext,
    @Query('q') search?: string,
  ) {
    return this.inventory.listStockItems(tenant, search, true);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/stock-items')
  createStockItem(
    @ManagerAuth() actor: ManagerAuthContext,
    @Body() payload: StockItemInput,
  ) {
    return this.inventory.createStockItem(actor, payload);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Patch('inventory/stock-items/:id')
  updateStockItem(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Body() payload: StockItemInput,
  ) {
    return this.inventory.updateStockItem(actor, id, payload);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/stock-items/:id')
  getStockItem(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.inventory.getStockItem(tenant, id);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/suppliers')
  getSuppliers(
    @ManagerTenant() tenant: TenantContext,
    @Query('q') search?: string,
  ) {
    return this.inventory.listSuppliers(tenant, search);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/suppliers/:id')
  async inventorySupplierDetail(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.inventory.supplierDetail(tenant, id);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/suppliers/:id/items')
  addSuppliedItem(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Body() input: unknown,
  ) {
    return this.inventory.addSuppliedItem(actor, id, input);
  }
  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/suppliers/:id/products/:stockItemId')
  async linkSupplierProduct(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Param('stockItemId') stockItemId: string,
  ) {
    return this.inventory.setSupplierProduct(actor, id, stockItemId, true);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Delete('inventory/suppliers/:id/products/:stockItemId')
  async unlinkSupplierProduct(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Param('stockItemId') stockItemId: string,
  ) {
    return this.inventory.setSupplierProduct(actor, id, stockItemId, false);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/suppliers')
  createSupplier(
    @ManagerAuth() actor: ManagerAuthContext,
    @Body() payload: SupplierInput,
  ) {
    return this.inventory.createSupplier(actor, payload);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Patch('inventory/suppliers/:id')
  updateSupplier(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Body() payload: SupplierInput,
  ) {
    return this.inventory.updateSupplier(actor, id, payload);
  }

  // ── Receiving / waybills ──────────────────────────────────────────────

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/receivings/:id/payments/:paymentId/reverse')
  reverseSupplierPayment(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Param('paymentId') paymentId: string,
    @Body() input: unknown,
  ) {
    return this.receiving.reversePayment(actor, id, paymentId, input);
  }
  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/receivings/:id/verify-settlement')
  verifySupplierSettlement(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Body() input: unknown,
  ) {
    return this.receiving.verifyPayments(actor, id, input);
  }
  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/payables')
  supplierPayables(
    @ManagerTenant() tenant: TenantContext,
    @Query('supplierId') supplierId?: string,
  ) {
    return this.receiving.payments(tenant, supplierId);
  }
  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/receivings/:id/payments')
  supplierPayment(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Body() input: unknown,
  ) {
    return this.receiving.recordPayment(actor, id, input);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/receivings')
  listReceivings(
    @ManagerTenant() tenant: TenantContext,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('supplierId') supplierId?: string,
    @Query('status') status?: string,
    @Query('q') search?: string,
    @Query('take') take?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.receiving.list(tenant, {
      from,
      to,
      supplierId,
      status,
      search,
      take: take ? Number(take) : undefined,
      cursor,
    });
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/receivings/:id')
  getReceiving(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.receiving.detail(tenant, id);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/receivings')
  createReceiving(
    @ManagerAuth() actor: ManagerAuthContext,
    @Body() payload: ReceivingInput,
  ) {
    return this.receiving.createDraft(actor, payload);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Patch('inventory/receivings/:id')
  updateReceiving(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Body() payload: ReceivingInput,
  ) {
    return this.receiving.updateDraft(actor, id, payload);
  }

  /** Drafts only. A posted document is cancelled, never deleted. */
  @RequiresFeature(FeatureKeys.INVENTORY)
  @Delete('inventory/receivings/:id')
  deleteReceiving(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
  ) {
    return this.receiving.deleteDraft(actor, id);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/receivings/:id/post')
  postReceiving(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
  ) {
    return this.receiving.post(actor, id);
  }

  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/receivings/:id/cancel')
  cancelReceiving(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
    @Body() payload: { reason?: unknown } = {},
  ) {
    return this.receiving.cancel(actor, id, payload?.reason);
  }

  // ── Recipes / technological cards ─────────────────────────────────────

  /** Menu-oriented: every Menu Item, marked configured or not. */
  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/recipes')
  listRecipeMenuItems(
    @ManagerTenant() tenant: TenantContext,
    @Query('q') search?: string,
    @Query('status') status?: string,
  ) {
    return this.recipes.listMenuItems(tenant, { search, status });
  }

  /** The definition for one Menu Item, or null when none is configured. */
  @RequiresFeature(FeatureKeys.INVENTORY)
  @Get('inventory/recipes/menu-item/:menuItemId')
  getRecipe(
    @ManagerTenant() tenant: TenantContext,
    @Param('menuItemId') menuItemId: string,
    @Query('variantId') variantId?: string,
  ) {
    return this.recipes.detail(tenant, menuItemId, variantId);
  }

  /** Creates or replaces the one definition for this Menu Item + variant. */
  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/recipes')
  saveRecipe(
    @ManagerAuth() actor: ManagerAuthContext,
    @Body() payload: RecipeInput,
  ) {
    return this.recipes.save(actor, payload);
  }

  /** Stops applying a definition without deleting what it said. */
  @RequiresFeature(FeatureKeys.INVENTORY)
  @Post('inventory/recipes/:id/disable')
  disableRecipe(
    @ManagerAuth() actor: ManagerAuthContext,
    @Param('id') id: string,
  ) {
    return this.recipes.disable(actor, id);
  }

  // GET /mobile/restaurant-settings
  @Get('restaurant-settings')
  async getRestaurantSettings(@ManagerTenant() tenant: TenantContext) {
    return this.devices.getRestaurantSettings(tenant);
  }

  /** Missed manager notifications while the app was backgrounded (persisted on server). */
  @Get('notifications')
  async getNotifications(
    @ManagerTenant() tenant: TenantContext,
    @Req() req: { user: { username: string } },
    @Query('since') since?: string,
  ) {
    return this.devices.getNotifications(tenant, req.user.username, since);
  }

  @Post('push/register')
  async registerPushDevice(
    @ManagerTenant() tenant: TenantContext,
    @Req() req: { user: { username: string } },
    @Body() payload: { fcmToken?: string; platform?: string },
  ) {
    return this.devices.registerPushDevice(tenant, req.user.username, payload);
  }

  @Post('push/unregister')
  async unregisterPushDevice(
    @ManagerTenant() tenant: TenantContext,
    @Req() req: { user: { username: string } },
    @Body() payload: { fcmToken?: string },
  ) {
    return this.devices.unregisterPushDevice(
      tenant,
      req.user.username,
      payload,
    );
  }

  // GET /mobile/dashboard
  @Get('dashboard')
  async getDashboard(@ManagerTenant() tenant: TenantContext) {
    return this.dashboard.getDashboard(tenant);
  }

  // GET /mobile/tables
  @Get('tables')
  async getTables(@ManagerTenant() tenant: TenantContext) {
    return this.dashboard.getTables(tenant);
  }

  // POST /mobile/tables/:tableNumber/free?floor=first
  // Forcefully marks a table as free (emergency ghost-table fix for managers).
  @Post('tables/:tableNumber/free')
  async freeTable(
    @ManagerTenant() tenant: TenantContext,
    @Param('tableNumber') tableNumber: string,
    @Query('floor') floor: string = 'first',
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.dashboard.freeTable(
      tenant,
      tableNumber,
      floor,
      monitoringSocketId,
    );
  }

  // GET /mobile/staff-performance
  @Get('staff-performance')
  async getStaffPerformance(@ManagerTenant() tenant: TenantContext) {
    return this.dashboard.getStaffPerformance(tenant);
  }

  // GET /mobile/financials
  @Get('financials')
  async getFinancials(@ManagerTenant() tenant: TenantContext) {
    return this.dashboard.getFinancials(tenant);
  }

  /** Exact, provenance-bearing Cloud Sale ledger summary. */
  @Get('financial-summary')
  async getFinancialSummary(
    @ManagerTenant() tenant: TenantContext,
    @Query() query: { from?: string; to?: string },
  ) {
    return this.saleLedger.getSummary(tenant, query);
  }

  /** Keyset-paginated frozen Sale history. */
  @Get('sales')
  async getSales(
    @ManagerTenant() tenant: TenantContext,
    @Query()
    query: {
      from?: string;
      to?: string;
      cursor?: string;
      limit?: string;
      paymentMethod?: string;
      staffId?: string;
      fiscal?: string;
      state?: string;
      menuItemId?: string;
      variantId?: string;
    },
  ) {
    return this.saleLedger.listSales(tenant, query);
  }

  @Get('sales/:id')
  async getSale(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.saleLedger.getSale(tenant, id);
  }

  @Get('product-analytics')
  async getProductAnalytics(
    @ManagerTenant() tenant: TenantContext,
    @Query() query: { from?: string; to?: string; limit?: string },
  ) {
    return this.saleLedger.getProducts(tenant, query);
  }

  @Get('sale-staff-analytics')
  async getSaleStaffAnalytics(
    @ManagerTenant() tenant: TenantContext,
    @Query() query: { from?: string; to?: string },
  ) {
    return this.saleLedger.getStaff(tenant, query);
  }

  // POST /mobile/expenses
  @Post('expenses')
  async createExpense(
    @ManagerTenant() tenant: TenantContext,
    @Body()
    payload: {
      description?: string;
      amount?: number;
      category?: string;
      paymentType?: string;
    },
  ) {
    return this.dashboard.createExpense(tenant, payload);
  }

  // DELETE /mobile/expenses/:id
  @Delete('expenses/:id')
  async deleteExpense(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.dashboard.deleteExpense(tenant, id);
  }

  // GET /mobile/orders?page=1&pageSize=20&status=open
  @Get('orders')
  async getOrders(
    @ManagerTenant() tenant: TenantContext,
    @Query('page', new DefaultValuePipe(1), ParseIntPipe) page: number,
    @Query('pageSize', new DefaultValuePipe(20), ParseIntPipe) pageSize: number,
    @Query('status') status?: string,
  ) {
    return this.orders.getOrders(tenant, page, pageSize, status);
  }

  // GET /mobile/reservations?date=YYYY-MM-DD
  @RequiresFeature(FeatureKeys.MANAGER_RESERVATIONS)
  @Get('reservations')
  async getReservations(
    @ManagerTenant() tenant: TenantContext,
    @Query('date') date?: string,
  ) {
    return this.reservations.getReservations(tenant, date);
  }

  // POST /mobile/reservations
  @RequiresFeature(FeatureKeys.MANAGER_RESERVATIONS)
  @Post('reservations')
  async createReservation(
    @ManagerTenant() tenant: TenantContext,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body()
    payload: {
      customerName?: string;
      customerPhone?: string;
      tableNumbers?: number[];
      reservationDate?: string;
      reservationTime?: string;
      numberOfGuests?: number;
      notes?: string;
      createdBy?: string;
      status?: string;
      preOrderItems?: Array<Record<string, unknown>>;
    },
  ) {
    return this.reservations.createReservation(
      tenant,
      monitoringSocketId,
      payload,
    );
  }

  // POST /mobile/reservations/:id/status
  @RequiresFeature(FeatureKeys.MANAGER_RESERVATIONS)
  @Post('reservations/:id/status')
  async updateReservationStatus(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() payload: { status?: string },
  ) {
    return this.reservations.updateReservationStatus(
      tenant,
      id,
      monitoringSocketId,
      payload,
    );
  }

  // DELETE /mobile/reservations/:id
  @RequiresFeature(FeatureKeys.MANAGER_RESERVATIONS)
  @Delete('reservations/:id')
  async deleteReservation(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.reservations.deleteReservation(tenant, id, monitoringSocketId);
  }

  // POST /mobile/reservations/:id/print-check
  // Manager-triggered: relays a print request to the Windows POS, which is the
  // only print host. No realtime broadcast — printing is not a data mutation.
  @RequiresFeature(FeatureKeys.MANAGER_RESERVATIONS)
  @Post('reservations/:id/print-check')
  async printReservationCheck(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.reservations.printReservationCheck(tenant, id);
  }

  // GET /mobile/order/:id
  @Get('order/:id')
  async getOrder(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.orders.getOrder(tenant, id);
  }

  // POST /mobile/order/:id
  @Post('order/:id')
  async updateOrder(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() body: any,
  ) {
    return this.orders.updateOrder(tenant, id, monitoringSocketId, body);
  }

  // POST /mobile/order/:id/cancel
  @Post('order/:id/cancel')
  async cancelOrder(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.orders.cancelOrder(tenant, id, monitoringSocketId);
  }

  // POST /mobile/order/:id/print-check
  // Manager-triggered: relays a table/order pre-bill print to the Windows POS,
  // the only print host. No realtime broadcast — printing is not a data mutation.
  @Post('order/:id/print-check')
  async printOrderCheck(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.orders.printOrderCheck(tenant, id);
  }

  // POST /mobile/takeaway-orders — create a new takeaway order from the mobile app
  @Post('takeaway-orders')
  async createTakeawayOrder(
    @ManagerTenant() tenant: TenantContext,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body()
    body: {
      customerName: string;
      pickupTime: string;
      waiterName: string;
      items: { itemName: string; unitPrice: number; quantity: number }[];
    },
  ) {
    return this.orders.createTakeawayOrder(tenant, monitoringSocketId, body);
  }

  // POST /mobile/walk-in-orders — create a dine-in (walk-in) order on table(s)
  @Post('walk-in-orders')
  async createWalkInOrder(
    @ManagerTenant() tenant: TenantContext,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body()
    body: {
      tableNumbers: (string | number)[];
      floor: string;
      waiterName: string;
      guestCount?: number;
      items: { itemName: string; unitPrice: number; quantity: number }[];
    },
  ) {
    return this.orders.createWalkInOrder(tenant, monitoringSocketId, body);
  }

  // DELETE /mobile/takeaway-orders/:id — cancel a takeaway order on Cloud and POS (kept as history)
  @Delete('takeaway-orders/:id')
  async deleteTakeawayOrder(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.orders.deleteTakeawayOrder(tenant, id, monitoringSocketId);
  }

  // GET /mobile/takeaway-orders
  // Returns ALL takeaway orders for the current business day, matching Windows POS exactly.
  @Get('takeaway-orders')
  async getTakeawayOrders(@ManagerTenant() tenant: TenantContext) {
    return this.orders.getTakeawayOrders(tenant);
  }

  // GET /mobile/menu
  @Get('menu')
  async getMenu(@ManagerTenant() tenant: TenantContext) {
    return this.menu.getMenu(tenant);
  }

  // GET /mobile/users
  @Get('users')
  async getUsers(@ManagerTenant() tenant: TenantContext) {
    return this.users.getUsers(tenant);
  }

  @Post('users')
  async createUser(
    @ManagerTenant() tenant: TenantContext,
    @Body() payload: { username?: string; pinCode?: string; role?: string },
  ) {
    return this.users.createUser(tenant, payload);
  }

  @Post('users/:username/pin')
  async updateUserPin(
    @ManagerTenant() tenant: TenantContext,
    @Param('username') usernameParam: string,
    @Body() payload: { pinCode?: string },
  ) {
    return this.users.updateUserPin(tenant, usernameParam, payload);
  }

  @Post('users/:username/role')
  async updateUserRole(
    @ManagerTenant() tenant: TenantContext,
    @Param('username') usernameParam: string,
    @Body() payload: { role?: string },
  ) {
    return this.users.updateUserRole(tenant, usernameParam, payload);
  }

  @Patch('users/:username')
  async renameUser(
    @ManagerTenant() tenant: TenantContext,
    @Param('username') usernameParam: string,
    @Body() payload: { username?: string },
  ) {
    return this.users.renameUser(tenant, usernameParam, payload);
  }

  @Delete('users/:username')
  async deleteUser(
    @ManagerTenant() tenant: TenantContext,
    @Param('username') usernameParam: string,
  ) {
    return this.users.deleteUser(tenant, usernameParam);
  }

  // GET /mobile/audit?year=2026&month=4&status=OPEN
  // Returns full AuditReports with events, grouped by day, for a given month.
  // If year/month are omitted, returns the most recent 90 days.
  @Get('audit')
  async getAuditLog(
    @ManagerTenant() tenant: TenantContext,
    @Query('year') yearStr?: string,
    @Query('month') monthStr?: string,
    @Query('status') status?: string,
    @Query('all') allStr?: string,
  ) {
    return this.reports.getAuditLog(tenant, yearStr, monthStr, status, allStr);
  }

  /**
   * GET /mobile/audit-log
   *
   * The venue-wide audit feed: staff, menu, packages, expenses, close day,
   * backups, settings and the business date — everything that is not the
   * lifecycle of one Order, which `/mobile/audit` already serves as its own
   * ordered report.
   *
   * Newest first, keyset-paginated through `cursor`. Every filter is applied
   * inside the authenticated Staff's Venue; there is no way to ask for
   * another's.
   */
  @RequiresFeature(FeatureKeys.ADVANCED_AUDIT)
  @Get('audit-log')
  async getGlobalAuditLog(
    @ManagerTenant() tenant: TenantContext,
    @Query() query: AuditLogQuery,
  ) {
    return this.auditLog.getAuditLog(tenant, query);
  }

  /** The actions and entity types this Venue has actually recorded. */
  @RequiresFeature(FeatureKeys.ADVANCED_AUDIT)
  @Get('audit-log/facets')
  async getGlobalAuditLogFacets(@ManagerTenant() tenant: TenantContext) {
    return this.auditLog.getAuditLogFacets(tenant);
  }

  // GET /mobile/sales-report?period=today|week|month
  @Get('sales-report')
  async getSalesReport(
    @ManagerTenant() tenant: TenantContext,
    @Query('period') period: string = 'today',
    @Query('month') month?: string,
  ) {
    return this.reports.getSalesReport(tenant, period, month);
  }

  // GET /mobile/sales-daily?month=YYYY-MM
  @Get('sales-daily')
  async getSalesDaily(
    @ManagerTenant() tenant: TenantContext,
    @Query('month') month?: string,
  ) {
    return this.reports.getSalesDaily(tenant, month);
  }

  // GET /mobile/top-items?limit=10
  @Get('top-items')
  async getTopItems(
    @ManagerTenant() tenant: TenantContext,
    @Query('limit', new DefaultValuePipe(10), ParseIntPipe) limit: number,
  ) {
    return this.reports.getTopItems(tenant, limit);
  }

  // GET /mobile/counted-menus
  @Get('counted-menus')
  async getCountedMenus(@ManagerTenant() tenant: TenantContext) {
    return this.menu.getCountedMenus(tenant);
  }

  // POST /mobile/counted-menu/save
  @Post('counted-menu/save')
  async saveCountedMenu(
    @ManagerTenant() tenant: TenantContext,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() data: any,
  ) {
    return this.menu.saveCountedMenu(
      tenant,
      data,
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
  }

  // POST /mobile/counted-menu/:id/delete
  @Post('counted-menu/:id/delete')
  async deleteCountedMenu(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.menu.deleteCountedMenu(
      tenant,
      id,
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
  }

  // POST /mobile/counted-menu/:id/print
  // Manager-triggered: relays a counted-menu receipt print to the Windows POS,
  // the only print host. No realtime broadcast — printing is not a data mutation.
  @Post('counted-menu/:id/print')
  async printCountedMenu(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
  ) {
    return this.menu.printCountedMenu(tenant, id);
  }

  // POST /mobile/counted-menu/:id/update — edit an existing counted menu in place
  @Post('counted-menu/:id/update')
  async updateCountedMenu(
    @ManagerTenant() tenant: TenantContext,
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() data: any,
  ) {
    return this.menu.updateCountedMenu(
      tenant,
      id,
      data,
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
  }
}
