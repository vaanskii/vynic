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
import { ManagerTenant } from '../auth/manager-auth-context';
import type { TenantContext } from '../tenancy/tenant-context';
import { FeatureGuard } from '../entitlements/feature.guard';
import { FeatureKeys } from '../entitlements/feature-keys';
import { RequiresFeature } from '../entitlements/requires-feature.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { StaffRole } from '../staff/staff-role';
import { MobileUsersService } from './services/mobile-users.service';
import { MobileReportsService } from './services/mobile-reports.service';
import { MobileDevicesService } from './services/mobile-devices.service';
import { MobileMenuService } from './services/mobile-menu.service';
import { MobileMutationSupport } from './services/mobile-mutation-support.service';
import { MobileReservationsService } from './services/mobile-reservations.service';
import { MobileDashboardService } from './services/mobile-dashboard.service';
import { MobileOrdersService } from './services/mobile-orders.service';

// ─── Controller ───────────────────────────────────────────────────────────────

@Controller('mobile')
@UseGuards(JwtAuthGuard, RolesGuard, FeatureGuard)
@Roles(StaffRole.MANAGER)
@RequiresFeature(FeatureKeys.MANAGER_APP)
export class MobileController {
  constructor(
    private readonly users: MobileUsersService,
    private readonly reports: MobileReportsService,
    private readonly devices: MobileDevicesService,
    private readonly menu: MobileMenuService,
    private readonly mutationSupport: MobileMutationSupport,
    private readonly reservations: MobileReservationsService,
    private readonly dashboard: MobileDashboardService,
    private readonly orders: MobileOrdersService,
  ) {}

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
  @Get('reservations')
  async getReservations(
    @ManagerTenant() tenant: TenantContext,
    @Query('date') date?: string,
  ) {
    return this.reservations.getReservations(tenant, date);
  }

  // POST /mobile/reservations
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

  // DELETE /mobile/takeaway-orders/:id — fully remove a takeaway order from DB and POS
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
