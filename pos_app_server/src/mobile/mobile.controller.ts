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
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(StaffRole.MANAGER)
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
  async getRestaurantSettings() {
    return this.devices.getRestaurantSettings();
  }

  /** Missed manager notifications while the app was backgrounded (persisted on server). */
  @Get('notifications')
  async getNotifications(
    @Req() req: { user: { username: string } },
    @Query('since') since?: string,
  ) {
    return this.devices.getNotifications(req.user.username, since);
  }

  @Post('push/register')
  async registerPushDevice(
    @Req() req: { user: { username: string } },
    @Body() payload: { fcmToken?: string; platform?: string },
  ) {
    return this.devices.registerPushDevice(req.user.username, payload);
  }

  @Post('push/unregister')
  async unregisterPushDevice(
    @Req() req: { user: { username: string } },
    @Body() payload: { fcmToken?: string },
  ) {
    return this.devices.unregisterPushDevice(req.user.username, payload);
  }

  // GET /mobile/dashboard
  @Get('dashboard')
  async getDashboard() {
    return this.dashboard.getDashboard();
  }

  // GET /mobile/tables
  @Get('tables')
  async getTables() {
    return this.dashboard.getTables();
  }

  // POST /mobile/tables/:tableNumber/free?floor=first
  // Forcefully marks a table as free (emergency ghost-table fix for managers).
  @Post('tables/:tableNumber/free')
  async freeTable(
    @Param('tableNumber') tableNumber: string,
    @Query('floor') floor: string = 'first',
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.dashboard.freeTable(tableNumber, floor, monitoringSocketId);
  }

  // GET /mobile/staff-performance
  @Get('staff-performance')
  async getStaffPerformance() {
    return this.dashboard.getStaffPerformance();
  }

  // GET /mobile/financials
  @Get('financials')
  async getFinancials() {
    return this.dashboard.getFinancials();
  }

  // POST /mobile/expenses
  @Post('expenses')
  async createExpense(
    @Body()
    payload: {
      description?: string;
      amount?: number;
      category?: string;
      paymentType?: string;
    },
  ) {
    return this.dashboard.createExpense(payload);
  }

  // DELETE /mobile/expenses/:id
  @Delete('expenses/:id')
  async deleteExpense(@Param('id') id: string) {
    return this.dashboard.deleteExpense(id);
  }

  // GET /mobile/orders?page=1&pageSize=20&status=open
  @Get('orders')
  async getOrders(
    @Query('page', new DefaultValuePipe(1), ParseIntPipe) page: number,
    @Query('pageSize', new DefaultValuePipe(20), ParseIntPipe) pageSize: number,
    @Query('status') status?: string,
  ) {
    return this.orders.getOrders(page, pageSize, status);
  }

  // GET /mobile/reservations?date=YYYY-MM-DD
  @Get('reservations')
  async getReservations(@Query('date') date?: string) {
    return this.reservations.getReservations(date);
  }

  // POST /mobile/reservations
  @Post('reservations')
  async createReservation(
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
    return this.reservations.createReservation(monitoringSocketId, payload);
  }

  // POST /mobile/reservations/:id/status
  @Post('reservations/:id/status')
  async updateReservationStatus(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() payload: { status?: string },
  ) {
    return this.reservations.updateReservationStatus(
      id,
      monitoringSocketId,
      payload,
    );
  }

  // DELETE /mobile/reservations/:id
  @Delete('reservations/:id')
  async deleteReservation(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.reservations.deleteReservation(id, monitoringSocketId);
  }

  // GET /mobile/order/:id
  @Get('order/:id')
  async getOrder(@Param('id') id: string) {
    return this.orders.getOrder(id);
  }

  // POST /mobile/order/:id
  @Post('order/:id')
  async updateOrder(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() body: any,
  ) {
    return this.orders.updateOrder(id, monitoringSocketId, body);
  }

  // POST /mobile/order/:id/cancel
  @Post('order/:id/cancel')
  async cancelOrder(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.orders.cancelOrder(id, monitoringSocketId);
  }

  // POST /mobile/takeaway-orders — create a new takeaway order from the mobile app
  @Post('takeaway-orders')
  async createTakeawayOrder(
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() body: {
    customerName: string;
    pickupTime: string;
    waiterName: string;
    items: { itemName: string; unitPrice: number; quantity: number }[];
    },
  ) {
    return this.orders.createTakeawayOrder(monitoringSocketId, body);
  }

  // POST /mobile/walk-in-orders — create a dine-in (walk-in) order on table(s)
  @Post('walk-in-orders')
  async createWalkInOrder(
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() body: {
      tableNumbers: (string | number)[];
      floor: string;
      waiterName: string;
      guestCount?: number;
      items: { itemName: string; unitPrice: number; quantity: number }[];
    },
  ) {
    return this.orders.createWalkInOrder(monitoringSocketId, body);
  }

  // DELETE /mobile/takeaway-orders/:id — fully remove a takeaway order from DB and POS
  @Delete('takeaway-orders/:id')
  async deleteTakeawayOrder(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.orders.deleteTakeawayOrder(id, monitoringSocketId);
  }

  // GET /mobile/takeaway-orders
  // Returns ALL takeaway orders for the current business day, matching Windows POS exactly.
  @Get('takeaway-orders')
  async getTakeawayOrders() {
    return this.orders.getTakeawayOrders();
  }

  // GET /mobile/menu
  @Get('menu')
  async getMenu() {
    return this.menu.getMenu();
  }

  // GET /mobile/users
  @Get('users')
  async getUsers() {
    return this.users.getUsers();
  }

  @Post('users')
  async createUser(
    @Body() payload: { username?: string; pinCode?: string; role?: string },
  ) {
    return this.users.createUser(payload);
  }

  @Post('users/:username/pin')
  async updateUserPin(
    @Param('username') usernameParam: string,
    @Body() payload: { pinCode?: string },
  ) {
    return this.users.updateUserPin(usernameParam, payload);
  }

  @Patch('users/:username')
  async renameUser(
    @Param('username') usernameParam: string,
    @Body() payload: { username?: string },
  ) {
    return this.users.renameUser(usernameParam, payload);
  }

  @Delete('users/:username')
  async deleteUser(@Param('username') usernameParam: string) {
    return this.users.deleteUser(usernameParam);
  }

  // GET /mobile/audit?year=2026&month=4&status=OPEN
  // Returns full AuditReports with events, grouped by day, for a given month.
  // If year/month are omitted, returns the most recent 90 days.
  @Get('audit')
  async getAuditLog(
    @Query('year') yearStr?: string,
    @Query('month') monthStr?: string,
    @Query('status') status?: string,
    @Query('all') allStr?: string,
  ) {
    return this.reports.getAuditLog(yearStr, monthStr, status, allStr);
  }

  // GET /mobile/sales-report?period=today|week|month
  @Get('sales-report')
  async getSalesReport(
    @Query('period') period: string = 'today',
    @Query('month') month?: string,
  ) {
    return this.reports.getSalesReport(period, month);
  }

  // GET /mobile/sales-daily?month=YYYY-MM
  @Get('sales-daily')
  async getSalesDaily(@Query('month') month?: string) {
    return this.reports.getSalesDaily(month);
  }

  // GET /mobile/top-items?limit=10
  @Get('top-items')
  async getTopItems(
    @Query('limit', new DefaultValuePipe(10), ParseIntPipe) limit: number,
  ) {
    return this.reports.getTopItems(limit);
  }

  // GET /mobile/counted-menus
  @Get('counted-menus')
  async getCountedMenus() {
    return this.menu.getCountedMenus();
  }

  // POST /mobile/counted-menu/save
  @Post('counted-menu/save')
  async saveCountedMenu(
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() data: any,
  ) {
    return this.menu.saveCountedMenu(
      data,
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
  }

  // POST /mobile/counted-menu/:id/delete
  @Post('counted-menu/:id/delete')
  async deleteCountedMenu(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    return this.menu.deleteCountedMenu(
      id,
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
  }
}

