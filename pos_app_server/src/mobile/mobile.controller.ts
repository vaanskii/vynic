import {
  BadRequestException,
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
import { PrismaService } from '../prisma.service';
import { Order } from '@prisma/client';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { StaffRole } from '../staff/staff-role';
import { MonitoringGateway } from '../realtime/monitoring.gateway';
import { PosCallbackClient } from '../pos/pos-callback.client';
import { MobileUsersService } from './services/mobile-users.service';
import { MobileReportsService } from './services/mobile-reports.service';
import { MobileDevicesService } from './services/mobile-devices.service';
import { MobileMenuService } from './services/mobile-menu.service';
import { MobileMutationSupport } from './services/mobile-mutation-support.service';
import { MobileReservationsService } from './services/mobile-reservations.service';
import { MobileDashboardService } from './services/mobile-dashboard.service';
import {
  businessDateWhere,
  readRestaurantServiceFeeSettings,
  todayStart,
} from './util/mobile-date.util';
import { buildAuditEventsForOrderDiff } from '../pos/audit/audit-order-diff';
import { normalizeAuditEventType } from '../pos/audit/audit-event-type';
import { PosOutboxService } from '../pos/pos-outbox.service';

// ─── Lightweight response types ───────────────────────────────────────────────

interface PaginatedOrders {
  data: {
    id: string;
    posOrderId: number;
    status: string;
    totalAmount: number;
    waiterName: string;
    guestCount: number;
    createdAt: string;
    itemCount: number;
  }[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

// ─── Controller ───────────────────────────────────────────────────────────────

@Controller('mobile')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(StaffRole.MANAGER)
export class MobileController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    private readonly posOutbox: PosOutboxService,
    private readonly posCallback: PosCallbackClient,
    private readonly users: MobileUsersService,
    private readonly reports: MobileReportsService,
    private readonly devices: MobileDevicesService,
    private readonly menu: MobileMenuService,
    private readonly mutationSupport: MobileMutationSupport,
    private readonly reservations: MobileReservationsService,
    private readonly dashboard: MobileDashboardService,
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
  ): Promise<PaginatedOrders> {
    const take = Math.min(pageSize, 100);
    const skip = (page - 1) * take;
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
    });
    const currentBusinessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
    const where: any = businessDateWhere(currentBusinessDate);
    if (status) where.status = status;

    const [data, total] = await Promise.all([
      this.prisma.order.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
        select: {
          id: true,
          posOrderId: true,
          status: true,
          totalAmount: true,
          waiterName: true,
          guestCount: true,
          createdAt: true,
          _count: { select: { items: true } },
        },
      }),
      this.prisma.order.count({ where }),
    ]);

    return {
      data: data.map((o: any) => ({
        id: o.id,
        posOrderId: o.posOrderId,
        status: o.status,
        totalAmount: Math.round(Number(o.totalAmount) * 100) / 100,
        waiterName: o.waiterName,
        guestCount: o.guestCount,
        createdAt: (o.createdAt as Date).toISOString(),
        itemCount: o._count.items,
      })),
      total,
      page,
      pageSize: take,
      hasMore: skip + take < total,
    };
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
    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const order = await this.prisma.order.findUnique({
      where: { posOrderId: Number(id) },
      include: { items: true },
    });
    if (!order) return { error: 'Order not found' };

    const linkedTables = await (this.prisma as any).table.findMany({
      where: { activeOrderId: Number(id) },
      orderBy: [{ floor: 'asc' }, { tableNumber: 'asc' }],
    });
    const tableNumbers = linkedTables.map((t: { tableNumber: string }) =>
      String(t.tableNumber).trim(),
    ).filter((n: string) => n.length > 0);
    const linkedFloor =
      linkedTables.length > 0
        ? String(linkedTables[0].floor ?? '').trim()
        : '';

    const itemsSubtotal = order.items.reduce(
      (sum, it) => sum + Number(it.price) * it.quantity,
      0,
    );
    const discount = Number(order.discountAmount ?? 0);
    const includeServiceFee =
      feeSettings.serviceFeeAvailable && order.includeServiceFee === true;
    const feeRate = includeServiceFee
      ? Number(order.serviceFeePercent ?? feeSettings.serviceFeePercent) / 100
      : 0;
    const serviceFee = includeServiceFee
      ? Math.round(itemsSubtotal * feeRate * 100) / 100
      : 0;
    const totalAmount =
      Math.round((itemsSubtotal + serviceFee - discount) * 100) / 100;

    return {
      ...order,
      posOrderId: order.posOrderId,
      tableNumbers,
      floor: linkedFloor || order.floor || 'first',
      totalAmount,
      includeServiceFee,
      discountAmount: discount,
      serviceFeePercent: Number(order.serviceFeePercent),
    };
  }

  // POST /mobile/order/:id
  @Post('order/:id')
  async updateOrder(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId: string | undefined,
    @Body() body: any,
  ) {
    const order = await this.prisma.order.findUnique({
      where: { posOrderId: Number(id) },
    });
    if (!order) return { success: false };

    const previousItems = await this.prisma.orderItem.findMany({
      where: { orderId: order.id },
    });

    await (this.prisma as any).orderItem.deleteMany({ where: { orderId: order.id } });
    for (const item of body.items ?? []) {
      await (this.prisma as any).orderItem.create({
        data: {
          orderId: order.id,
          name: item.itemName ?? item.name ?? '',
          quantity: item.quantity ?? 1,
          price: item.unitPrice ?? item.price ?? 0,
        },
      });
    }

    // Mobile can toggle service fee; fall back to stored value if not sent
    const feeSettings = await readRestaurantServiceFeeSettings(this.prisma);
    const requestedInclude =
      typeof body.includeServiceFee === 'boolean'
        ? body.includeServiceFee
        : order.includeServiceFee;
    const includeServiceFee =
      feeSettings.serviceFeeAvailable && requestedInclude === true;

    // Recalculate total server-side
    const itemsSubtotal = (body.items ?? []).reduce(
      (sum: number, it: any) =>
        sum + (it.unitPrice ?? it.price ?? 0) * (it.quantity ?? 1),
      0,
    );
    const feeRate = includeServiceFee
      ? Number(order.serviceFeePercent ?? feeSettings.serviceFeePercent) / 100
      : 0;
    const serviceFee = includeServiceFee ? itemsSubtotal * feeRate : 0;
    const discount = Number(order.discountAmount ?? 0);
    const newTotal =
      Math.round((itemsSubtotal + serviceFee - discount) * 100) / 100;

    const prevIncludeServiceFee = order.includeServiceFee === true;
    const prevTotal = Number(order.totalAmount ?? 0);

    await this.prisma.order.update({
      where: { id: order.id },
      data: {
        totalAmount: newTotal > 0 ? newTotal : 0,
        includeServiceFee,
      },
    });

    const tableNumbers = Array.isArray(body.tableNumbers)
      ? body.tableNumbers.map((t: unknown) => String(t))
      : [];
    const floor =
      typeof body.floor === 'string' && body.floor.trim().length > 0
        ? body.floor
        : order.floor ?? 'first';
    if (tableNumbers.length > 0 && newTotal >= 0) {
      for (const rawNum of tableNumbers) {
        const tableNumber = String(rawNum)
          .replace(/^table\s*/i, '')
          .trim();
        if (!tableNumber) continue;
        await (this.prisma as any).table.updateMany({
          where: { tableNumber, floor },
          data: { currentBill: newTotal > 0 ? newTotal : 0 },
        });
      }
    }

    const performer = String(
      body.updatedBy ?? body.waiterName ?? 'მობილური მენეჯერი',
    ).trim();
    const performerName = performer.length > 0 ? performer : 'მობილური მენეჯერი';
    const posOrderId = Number(id);
    this.mutationSupport.registerMobileMutationEchoGuard(posOrderId);

    const auditEvents = buildAuditEventsForOrderDiff({
      previousItems: previousItems.map((it) => ({
        name: it.name,
        quantity: it.quantity,
        price: it.price,
      })),
      updatedItems: body.items ?? [],
      performerId: performerName,
      performerName,
    });
    if (auditEvents.length > 0) {
      await this.appendAuditEventsForPosOrder({
        posOrderId,
        tableNumbers: Array.isArray(body.tableNumbers)
          ? body.tableNumbers.map((t: unknown) => String(t))
          : [],
        floor: typeof body.floor === 'string' ? body.floor : order.floor,
        openedByName: order.waiterName || performerName,
        events: auditEvents,
      });
      this.gateway.broadcastUpdate(
        'audit_updated',
        { count: auditEvents.length, source: 'mobile', posOrderId },
        this.mutationSupport.wsExcludeOpts(monitoringSocketId),
      );
    }

    this.gateway.broadcastUpdate(
      'order_updated',
      { posOrderId, source: 'mobile_manager' },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );

    const feeChanged = prevIncludeServiceFee !== includeServiceFee;
    const totalChanged = Math.abs(prevTotal - newTotal) > 0.009;
    if (feeChanged || totalChanged) {
      const tableLabel = tableNumbers
        .map((t) =>
          String(t)
            .replace(/^table\s*/i, '')
            .trim(),
        )
        .filter((t) => t.length > 0)
        .join(', ');
      const changeSummary = feeChanged
        ? includeServiceFee
          ? 'სერვისის საფასური ჩართულია'
          : 'სერვისის საფასური გამორთულია'
        : 'თანხა განახლდა';
      this.gateway.broadcastUpdate(
        'orders_bulk_touch',
        {
          touches: [
            {
              posOrderId,
              tableLabel,
              floor,
              changeSummary,
              changeKind: feeChanged ? 'service_fee' : 'total',
              occurredAt: new Date().toISOString(),
            },
          ],
          posOrderIds: [posOrderId],
          source: 'mobile_manager',
        },
        this.mutationSupport.wsExcludeOpts(monitoringSocketId),
      );
      this.gateway.broadcastUpdate(
        'table_updated',
        { source: 'mobile_manager' },
        this.mutationSupport.wsExcludeOpts(monitoringSocketId),
      );
    }

    // Push change back to the Windows POS (durable outbox — retried until delivered)
    void this.posOutbox.enqueue({
      endpoint: '/mobile-order-update',
      posOrderId,
      payload: {
        posOrderId,
        updatedBy: performerName,
        items: (body.items ?? []).map((it: any) => ({
          name: it.itemName ?? it.name ?? '',
          quantity: it.quantity ?? 1,
          unitPrice: it.unitPrice ?? it.price ?? 0,
          price: it.unitPrice ?? it.price ?? 0,
          total: (it.unitPrice ?? it.price ?? 0) * (it.quantity ?? 1),
          itemKey: it.itemKey ?? it.itemName ?? it.name ?? '',
          itemName: it.itemName ?? it.name ?? '',
        })),
        totalAmount: newTotal > 0 ? newTotal : 0,
        includeServiceFee,
      },
    });

    return { success: true };
  }

  /** Append audit line events for a POS order (mobile manager edits). */
  private async appendAuditEventsForPosOrder(params: {
    posOrderId: number;
    tableNumbers: string[];
    floor: string;
    openedByName: string;
    events: import('../pos/audit/audit-order-diff').AuditEventInput[];
  }) {
    const { posOrderId, tableNumbers, floor, openedByName, events } = params;
    if (events.length === 0) return;

    const reportId = `audit_report_order_${posOrderId}`;
    const now = new Date();
    const prisma = this.prisma as any;

    let dbReport = await prisma.auditReport.findUnique({ where: { reportId } });
    if (!dbReport) {
      dbReport = await prisma.auditReport.create({
        data: {
          reportId,
          posOrderId,
          tableNumbers,
          floor: floor || 'first',
          openedById: openedByName,
          openedByName,
          openedAt: now,
          status: 'OPEN',
          locked: false,
        },
      });
    }

    const existing = await prisma.auditEvent.findMany({
      where: { reportId: dbReport.id },
      orderBy: { seq: 'asc' },
    });
    const startSeq = existing.length;

    await prisma.auditEvent.createMany({
      data: events.map((ev, seq) => ({
        reportId: dbReport.id,
        type: normalizeAuditEventType(ev.type, ev.previousQty, ev.newQty),
        itemName: ev.itemName,
        previousQty: ev.previousQty,
        newQty: ev.newQty,
        waiterId: ev.waiterId,
        waiterName: ev.waiterName,
        eventTime: now,
        note: ev.note ?? null,
        seq: startSeq + seq,
      })),
    });

    await prisma.auditReport.update({
      where: { id: dbReport.id },
      data: { updatedAt: now },
    });
  }

  // POST /mobile/order/:id/cancel
  @Post('order/:id/cancel')
  async cancelOrder(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    const posOrderId = Number(id);
    const order = await this.prisma.order.findUnique({
      where: { posOrderId },
    });
    if (!order) return { success: false, error: 'order_not_found' };

    this.mutationSupport.registerMobileMutationEchoGuard(posOrderId);

    // Capture which tables this order held before we release them, so the
    // cancellation notification can say which table was freed.
    const heldTables = await (this.prisma as any).table.findMany({
      where: { activeOrderId: posOrderId },
      select: { tableNumber: true },
    });
    const tableLabel = heldTables
      .map((t: any) => String(t.tableNumber).trim())
      .filter((t: string) => t.length > 0)
      .join(', ');

    await this.prisma.order.update({
      where: { id: order.id },
      data: { status: 'cancelled' },
    });

    // Free the table that was holding this order so it no longer shows as occupied
    await (this.prisma as any).table.updateMany({
      where: { activeOrderId: posOrderId },
      data: { isReserved: false, activeOrderId: null, currentBill: 0 },
    });

    this.gateway.broadcastUpdate(
      'order_cancelled',
      {
        posOrderId,
        floor: order.floor,
        ...(tableLabel.length > 0 ? { tableLabel } : {}),
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );

    // Tell the Windows POS to mark this order as cancelled in Hive (NOT delete — cancel shows on both sides)
    void this.posOutbox.enqueue({
      endpoint: '/mobile-order-status',
      posOrderId,
      payload: { posOrderId, status: 'cancelled' },
    });

    return { success: true };
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
    // Resolve current business date
    const bdSetting = await (this.prisma as any).setting.findUnique({ where: { key: 'currentBusinessDate' } });
    const businessDate: string = bdSetting?.value ?? new Date().toISOString().slice(0, 10);

    const totalAmount = body.items.reduce((s, it) => s + it.unitPrice * it.quantity, 0);

    // Allocate a posOrderId and create the order, retrying on the (rare) race
    // where two mobile requests grabbed the same id.
    let order: any;
    for (let attempt = 0; ; attempt++) {
      const candidateId = await this.allocateMobileOrderId();
      this.mutationSupport.registerMobileMutationEchoGuard(candidateId);
      try {
        order = await this.prisma.order.create({
          data: {
            posOrderId: candidateId,
            status: 'pending',
            totalAmount: Math.round(totalAmount * 100) / 100,
            guestCount: 1,
            waiterName: body.waiterName,
            floor: 'takeaway',
            businessDate,
            customerName: body.customerName,
            customerPhone: '-',
            pickupTime: body.pickupTime,
            items: {
              create: body.items.map(it => ({
                name: it.itemName,
                quantity: it.quantity,
                price: it.unitPrice,
              })),
            },
          },
          include: { items: true },
        });
        break;
      } catch (e) {
        if (this.isPosOrderIdConflict(e) && attempt < 5) continue;
        throw e;
      }
    }
    const nextId = order.posOrderId;

    this.gateway.broadcastUpdate(
      'takeaway_created',
      {
        posOrderId: nextId,
        customerName: body.customerName,
        pickupTime: body.pickupTime,
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );

    // Push to Windows POS in real-time so it appears immediately (durable outbox)
    void this.posOutbox.enqueue({
      endpoint: '/mobile-order-create',
      posOrderId: nextId,
      payload: {
        posOrderId: nextId,
        customerName: body.customerName,
        pickupTime: body.pickupTime,
        waiterName: body.waiterName,
        businessDate,
        items: body.items,
        totalAmount: order.totalAmount,
      },
    });

    return {
      posOrderId: order.posOrderId,
      status: order.status,
      totalAmount: order.totalAmount,
      customerName: order.customerName,
      pickupTime: order.pickupTime,
      waiterName: order.waiterName,
      businessDate: order.businessDate,
      items: order.items.map((it: any) => ({
        itemName: it.name,
        unitPrice: it.price,
        quantity: it.quantity,
      })),
    };
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
    const floor = (body.floor ?? 'first').toString().trim() || 'first';
    const tableNumbers = Array.isArray(body.tableNumbers)
      ? body.tableNumbers
          .map((t) => String(t).replace(/^table\s*/i, '').trim())
          .filter((t) => t.length > 0)
      : [];
    if (tableNumbers.length === 0) {
      throw new BadRequestException('Select at least one table');
    }
    if (!Array.isArray(body.items) || body.items.length === 0) {
      throw new BadRequestException('Add at least one item');
    }

    const bdSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
    });
    const businessDate: string =
      bdSetting?.value ?? new Date().toISOString().slice(0, 10);

    const totalAmount =
      Math.round(
        body.items.reduce((s, it) => s + it.unitPrice * it.quantity, 0) * 100,
      ) / 100;
    const guestCount = Number(body.guestCount ?? 0);

    // Allocate a posOrderId and create the order, retrying on the (rare) race
    // where two mobile requests grabbed the same id.
    let order: any;
    for (let attempt = 0; ; attempt++) {
      const candidateId = await this.allocateMobileOrderId();
      // Suppress echo for the order and every reserved table.
      this.mutationSupport.registerMobileMutationEchoGuard(candidateId);
      for (const tableNumber of tableNumbers) {
        this.mutationSupport.registerMobileMutationEchoGuard(candidateId, { tableNumber, floor });
      }
      try {
        order = await this.prisma.order.create({
          data: {
            posOrderId: candidateId,
            status: 'pending',
            totalAmount,
            guestCount: guestCount > 0 ? guestCount : 1,
            waiterName: body.waiterName,
            floor,
            businessDate,
            customerName: 'Walk-in',
            customerPhone: '-',
            items: {
              create: body.items.map((it) => ({
                name: it.itemName,
                quantity: it.quantity,
                price: it.unitPrice,
              })),
            },
          },
          include: { items: true },
        });
        break;
      } catch (e) {
        if (this.isPosOrderIdConflict(e) && attempt < 5) continue;
        throw e;
      }
    }
    const nextId = order.posOrderId;

    // Reserve the tables in the server DB so mobile live-status reflects it.
    for (const tableNumber of tableNumbers) {
      await (this.prisma as any).table.upsert({
        where: { tableIdentifier: { tableNumber, floor } },
        update: { isReserved: true, activeOrderId: nextId, currentBill: totalAmount },
        create: {
          tableNumber,
          floor,
          isReserved: true,
          activeOrderId: nextId,
          currentBill: totalAmount,
        },
      });
    }

    this.gateway.broadcastUpdate(
      'order_created',
      {
        posOrderId: nextId,
        floor,
        tableNumbers,
        tableLabel: tableNumbers.join(', '),
        walkIn: true,
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );
    this.gateway.broadcastUpdate(
      'table_updated',
      { source: 'mobile' },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );

    // Deliver to the Windows POS (durable outbox) so it appears on a table.
    void this.posOutbox.enqueue({
      endpoint: '/mobile-walk-in-order-create',
      posOrderId: nextId,
      payload: {
        posOrderId: nextId,
        tableNumbers,
        floor,
        waiterName: body.waiterName,
        guestCount,
        businessDate,
        items: body.items,
        totalAmount,
      },
    });

    return {
      posOrderId: order.posOrderId,
      status: order.status,
      totalAmount: order.totalAmount,
      floor: order.floor,
      tableNumbers,
      waiterName: order.waiterName,
      businessDate: order.businessDate,
      items: order.items.map((it: any) => ({
        itemName: it.name,
        unitPrice: it.price,
        quantity: it.quantity,
      })),
    };
  }

  // DELETE /mobile/takeaway-orders/:id — fully remove a takeaway order from DB and POS
  @Delete('takeaway-orders/:id')
  async deleteTakeawayOrder(
    @Param('id') id: string,
    @Headers('x-monitoring-socket-id') monitoringSocketId?: string,
  ) {
    const posOrderId = Number(id);
    const order = await this.prisma.order.findUnique({
      where: { posOrderId },
    });
    if (!order) return { success: false, error: 'order_not_found' };

    this.mutationSupport.registerMobileMutationEchoGuard(posOrderId);

    await this.prisma.order.delete({ where: { id: order.id } });

    this.gateway.broadcastUpdate(
      'takeaway_deleted',
      { posOrderId },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );

    // Tell POS to fully delete this order from Hive (durable outbox)
    void this.posOutbox.enqueue({
      endpoint: '/mobile-order-cancel',
      posOrderId,
      payload: { posOrderId },
    });

    return { success: true };
  }

  // GET /mobile/takeaway-orders
  // Returns ALL takeaway orders for the current business day, matching Windows POS exactly.
  @Get('takeaway-orders')
  async getTakeawayOrders() {
    // Use the currentBusinessDate setting — same source Windows POS uses to filter.
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'currentBusinessDate' },
    });
    const currentBD: string = businessDateSetting?.value ?? '';

    const orders = await this.prisma.order.findMany({
      where: {
        floor: 'takeaway',
        // Primary: match by stored businessDate (set during sync).
        // Fallback: if businessDate not yet populated (old orders), match by createdAt calendar day.
        ...(currentBD
          ? {
              OR: [
                { businessDate: currentBD },
                { businessDate: '', createdAt: { gte: (() => { const [y,m,d] = currentBD.split('-').map(Number); return new Date(y,m-1,d,0,0,0,0); })(), lt: (() => { const [y,m,d] = currentBD.split('-').map(Number); const s = new Date(y,m-1,d,0,0,0,0); s.setDate(s.getDate()+1); return s; })() } },
              ],
            }
          : {}),
      },
      orderBy: { createdAt: 'asc' },
      include: { items: true },
    });

    return orders.map((o: any) => ({
      posOrderId: o.posOrderId,
      status: o.status,
      totalAmount: Math.round(Number(o.totalAmount) * 100) / 100,
      waiterName: o.waiterName,
      guestCount: o.guestCount,
      customerPhone: o.customerPhone ?? '',
      customerName: o.customerName ?? '',
      pickupTime: o.pickupTime ?? '',
      createdAt: (o.createdAt as Date).toISOString(),
      items: (o.items ?? []).map((it: any) => ({
        itemKey: it.name,
        itemName: it.name,
        unitPrice: Math.round(Number(it.price) * 100) / 100,
        quantity: it.quantity,
        total: Math.round(Number(it.price) * it.quantity * 100) / 100,
      })),
    }));
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

  /// Allocate a collision-safe posOrderId for a mobile-originated order.
  /// Uses the greater of the persisted counter and the current max posOrderId
  /// already in the DB (never below 90001), then advances the counter. This
  /// survives counter drift and orders synced up from the POS that already sit
  /// in the mobile id range.
  private async allocateMobileOrderId(): Promise<number> {
    const counterKey = 'mobileOrderIdCounter';
    const [counterSetting, maxAgg] = await Promise.all([
      (this.prisma as any).setting.findUnique({ where: { key: counterKey } }),
      this.prisma.order.aggregate({ _max: { posOrderId: true } }),
    ]);
    const counterValue = counterSetting ? Number(counterSetting.value) : 0;
    const maxExisting = Number((maxAgg as any)?._max?.posOrderId ?? 0);
    const nextId = Math.max(counterValue + 1, maxExisting + 1, 90001);
    await (this.prisma as any).setting.upsert({
      where: { key: counterKey },
      update: { value: String(nextId) },
      create: { key: counterKey, value: String(nextId) },
    });
    return nextId;
  }

  /// True when a Prisma error is a unique-constraint violation on posOrderId,
  /// i.e. two requests raced for the same mobile id.
  private isPosOrderIdConflict(error: unknown): boolean {
    const e = error as { code?: string; meta?: { target?: unknown } };
    if (e?.code !== 'P2002') return false;
    const target = e?.meta?.target;
    if (Array.isArray(target)) return target.includes('posOrderId');
    return String(target ?? '').includes('posOrderId');
  }
}

