import { requestOrderEdit } from './manager-order-edit';
import { readEditProjection } from '../../shared/contracts/order-edit-projection';
import type { ManagerAuthContext } from '../../auth/manager-auth-context';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { MonitoringGateway } from '../../realtime/monitoring.gateway';
import { PosCommandDispatcher } from '../../pos/pos-command-dispatcher.service';
import { EdgeCommandTypes } from '../../shared/contracts/edge-command';
import {
  buildAuditEventsForOrderDiff,
  AuditEventInput,
} from '../../pos/audit/audit-order-diff';
import { normalizeAuditEventType } from '../../pos/audit/audit-event-type';
import { MobileMutationSupport } from './mobile-mutation-support.service';
import {
  businessDateWhere,
  readRestaurantServiceFeeSettings,
  todayStart,
} from '../util/mobile-date.util';
import { orderIdentity, settingIdentity } from '../../tenancy/tenant-identity';
import type { TenantContext } from '../../tenancy/tenant-context';

export interface PaginatedOrders {
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

type MobileOrderLine = {
  itemName: string;
  unitPrice: number;
  quantity: number;
  menuItemId?: string | null;
  variantId?: string | null;
};

/**
 * Order endpoints for the mobile manager app: dine-in order list/detail/edit/
 * cancel plus takeaway and walk-in order creation
 * (`/mobile/orders`, `/mobile/order/:id*`, `/mobile/takeaway-orders*`,
 * `/mobile/walk-in-orders`).
 *
 * Extracted verbatim from MobileController; behavior unchanged. The controller
 * keeps the route decorators (and query pipes) and passes params through.
 */
@Injectable()
export class MobileOrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    private readonly posCommands: PosCommandDispatcher,
    private readonly mutationSupport: MobileMutationSupport,
  ) {}

  async getOrders(
    tenant: TenantContext,
    page: number,
    pageSize: number,
    status?: string,
  ): Promise<PaginatedOrders> {
    const take = Math.min(pageSize, 100);
    const skip = (page - 1) * take;
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
    });
    const currentBusinessDate =
      businessDateSetting?.value ?? todayStart().toISOString().split('T')[0];
    const where: any = {
      venueId: tenant.venueId,
      ...businessDateWhere(currentBusinessDate),
    };
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

  async getOrder(tenant: TenantContext, id: string) {
    const feeSettings = await readRestaurantServiceFeeSettings(
      this.prisma,
      tenant,
    );
    const order = await this.prisma.order.findUnique({
      where: orderIdentity(tenant, Number(id)),
      include: { items: true },
    });
    if (!order) return { error: 'Order not found' };

    const linkedTables = await (this.prisma as any).table.findMany({
      where: {
        venueId: tenant.venueId,
        activeOrderId: Number(id),
      },
      orderBy: [{ floor: 'asc' }, { tableNumber: 'asc' }],
    });
    const tableNumbers = linkedTables
      .map((t: { tableNumber: string }) => String(t.tableNumber).trim())
      .filter((n: string) => n.length > 0);
    const linkedFloor =
      linkedTables.length > 0 ? String(linkedTables[0].floor ?? '').trim() : '';

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

    if (order.managerEditProjection) {
      const { projection, order: exact } = readEditProjection(order.managerEditProjection, order.posOrderId);
      return { ...exact, posOrderId: order.posOrderId, editProjection: projection };
    }
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

  async updateOrder(actor: ManagerAuthContext, id: string, _socket: string | undefined, body: any) {
    return requestOrderEdit(this.prisma, actor, id, body);
  }

  async cancelOrder(
    tenant: TenantContext,
    id: string,
    monitoringSocketId?: string,
  ) {
    const posOrderId = Number(id);
    const order = await this.prisma.order.findUnique({
      where: orderIdentity(tenant, posOrderId),
    });
    if (!order) return { success: false, error: 'order_not_found' };

    this.mutationSupport.registerMobileMutationEchoGuard(tenant, posOrderId);

    // Capture which tables this order held before we release them, so the
    // cancellation notification can say which table was freed.
    const heldTables = await (this.prisma as any).table.findMany({
      where: {
        venueId: tenant.venueId,
        activeOrderId: posOrderId,
      },
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
      where: {
        venueId: tenant.venueId,
        activeOrderId: posOrderId,
      },
      data: { isReserved: false, activeOrderId: null, currentBill: 0 },
    });

    this.gateway.broadcastUpdate(
      tenant,
      'order_cancelled',
      {
        posOrderId,
        floor: order.floor,
        ...(tableLabel.length > 0 ? { tableLabel } : {}),
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );

    // Cancel on the POS shows on both sides, so this is a status change rather
    // than a delete.
    const posDelivery = await this.posCommands.dispatch(tenant, {
      type: EdgeCommandTypes.ORDER_STATUS_UPDATE,
      payload: { posOrderId, status: 'cancelled' },
    });

    return { success: true, posDelivery };
  }

  /**
   * Relay an order/table check (customer pre-bill) print request to the Windows
   * POS — the only print host — via the direct POS callback path. No realtime
   * broadcast: printing is not a data mutation. POS-side failures (unreachable
   * POS, order missing in Hive) surface as clean HTTP errors instead of a 500.
   */
  async printOrderCheck(tenant: TenantContext, id: string) {
    const posOrderId = Number(id);
    if (!Number.isFinite(posOrderId)) {
      throw new BadRequestException('order id must be a number');
    }
    const posDelivery = await this.posCommands.dispatchAndAwait(tenant, {
      type: EdgeCommandTypes.ORDER_CHECK_PRINT,
      payload: { posOrderId },
    });

    if (posDelivery.status === 'FAILED') {
      if (posDelivery.code === 'order_not_found') {
        throw new NotFoundException('Order not found on POS');
      }
      throw new ServiceUnavailableException(
        `The POS could not print this check (${posDelivery.code ?? 'unknown'})`,
      );
    }
    if (posDelivery.status === 'UNAVAILABLE') {
      throw new ServiceUnavailableException(
        'Could not reach the POS to print this check — is it running?',
      );
    }
    // SUCCEEDED means the POS printed it. QUEUED / CLAIMED mean the request is
    // recorded and the terminal has not reported back inside the wait, which is
    // what an offline or busy POS looks like. The caller is told which.
    return { success: true, posDelivery };
  }

  async createTakeawayOrder(
    tenant: TenantContext,
    monitoringSocketId: string | undefined,
    body: {
      customerName: string;
      pickupTime: string;
      waiterName: string;
      items: MobileOrderLine[];
    },
  ) {
    // Resolve current business date
    const bdSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
    });
    const businessDate: string =
      bdSetting?.value ?? new Date().toISOString().slice(0, 10);

    const totalAmount = body.items.reduce(
      (s, it) => s + it.unitPrice * it.quantity,
      0,
    );

    // Allocate a posOrderId and create the order, retrying on the (rare) race
    // where two mobile requests grabbed the same id.
    let order: any;
    for (let attempt = 0; ; attempt++) {
      const candidateId = await this.allocateMobileOrderId(tenant);
      this.mutationSupport.registerMobileMutationEchoGuard(tenant, candidateId);
      try {
        order = await this.prisma.order.create({
          data: {
            venueId: tenant.venueId,
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
              create: body.items.map((it) => ({
                name: it.itemName,
                quantity: it.quantity,
                price: it.unitPrice,
                menuItemId: it.menuItemId ?? null,
                variantId: it.variantId ?? null,
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
      tenant,
      'takeaway_created',
      {
        posOrderId: nextId,
        customerName: body.customerName,
        pickupTime: body.pickupTime,
      },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );

    // `posOrderId` is allocated here, which is what makes the command safe to
    // deliver twice: the POS upserts on it rather than creating a second order.
    const posDelivery = await this.posCommands.dispatch(tenant, {
      type: EdgeCommandTypes.TAKEAWAY_ORDER_UPSERT,
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
      posDelivery,
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
        menuItemId: it.menuItemId,
        variantId: it.variantId,
      })),
    };
  }

  async createWalkInOrder(
    tenant: TenantContext,
    monitoringSocketId: string | undefined,
    body: {
      tableNumbers: (string | number)[];
      floor: string;
      waiterName: string;
      guestCount?: number;
      items: MobileOrderLine[];
    },
  ) {
    const floor = (body.floor ?? 'first').toString().trim() || 'first';
    const tableNumbers = Array.isArray(body.tableNumbers)
      ? body.tableNumbers
          .map((t) =>
            String(t)
              .replace(/^table\s*/i, '')
              .trim(),
          )
          .filter((t) => t.length > 0)
      : [];
    if (tableNumbers.length === 0) {
      throw new BadRequestException('Select at least one table');
    }
    if (!Array.isArray(body.items) || body.items.length === 0) {
      throw new BadRequestException('Add at least one item');
    }

    const bdSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
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
      const candidateId = await this.allocateMobileOrderId(tenant);
      // Suppress echo for the order and every reserved table.
      this.mutationSupport.registerMobileMutationEchoGuard(tenant, candidateId);
      for (const tableNumber of tableNumbers) {
        this.mutationSupport.registerMobileMutationEchoGuard(
          tenant,
          candidateId,
          {
            tableNumber,
            floor,
          },
        );
      }
      try {
        order = await this.prisma.order.create({
          data: {
            venueId: tenant.venueId,
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
                menuItemId: it.menuItemId ?? null,
                variantId: it.variantId ?? null,
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
        where: {
          tableIdentifier: {
            venueId: tenant.venueId,
            tableNumber,
            floor,
          },
        },
        update: {
          isReserved: true,
          activeOrderId: nextId,
          currentBill: totalAmount,
        },
        create: {
          venueId: tenant.venueId,
          tableNumber,
          floor,
          isReserved: true,
          activeOrderId: nextId,
          currentBill: totalAmount,
        },
      });
    }

    this.gateway.broadcastUpdate(
      tenant,
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
      tenant,
      'table_updated',
      { source: 'mobile' },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );

    // Same identity story as takeaway: Cloud allocates `posOrderId` so the POS
    // can upsert on it instead of creating a second walk-in.
    const posDelivery = await this.posCommands.dispatch(tenant, {
      type: EdgeCommandTypes.DINE_IN_ORDER_UPSERT,
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
      posDelivery,
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
        menuItemId: it.menuItemId,
        variantId: it.variantId,
      })),
    };
  }

  async deleteTakeawayOrder(
    tenant: TenantContext,
    id: string,
    monitoringSocketId?: string,
  ) {
    const posOrderId = Number(id);
    const order = await this.prisma.order.findUnique({
      where: orderIdentity(tenant, posOrderId),
    });
    if (!order) return { success: false, error: 'order_not_found' };

    this.mutationSupport.registerMobileMutationEchoGuard(tenant, posOrderId);

    // The Cloud row is the mirror of a POS Order that is about to be
    // cancelled, not erased: the POS keeps the Order and its audit report and
    // the next snapshot would re-mirror it as cancelled anyway. Deleting the
    // row here only made it vanish until then.
    if (order.status !== 'cancelled') {
      await this.prisma.order.update({
        where: { id: order.id },
        data: { status: 'cancelled' },
      });
    }

    this.gateway.broadcastUpdate(
      tenant,
      'takeaway_deleted',
      { posOrderId },
      this.mutationSupport.wsExcludeOpts(monitoringSocketId),
    );

    // ORDER_CANCEL is a cancellation on the POS: typed CANCEL_TABLE event,
    // locked report, non-fiscal cancelled Sale, Order kept.
    const posDelivery = await this.posCommands.dispatch(tenant, {
      type: EdgeCommandTypes.ORDER_CANCEL,
      payload: { posOrderId },
    });

    return { success: true, posDelivery };
  }

  async getTakeawayOrders(tenant: TenantContext) {
    // Use the currentBusinessDate setting — same source Windows POS uses to filter.
    const businessDateSetting = await (this.prisma as any).setting.findUnique({
      where: settingIdentity(tenant, 'currentBusinessDate'),
    });
    const currentBD: string = businessDateSetting?.value ?? '';

    const orders = await this.prisma.order.findMany({
      where: {
        venueId: tenant.venueId,
        floor: 'takeaway',
        // Primary: match by stored businessDate (set during sync).
        // Fallback: if businessDate not yet populated (old orders), match by createdAt calendar day.
        ...(currentBD
          ? {
              OR: [
                { businessDate: currentBD },
                {
                  businessDate: '',
                  createdAt: {
                    gte: (() => {
                      const [y, m, d] = currentBD.split('-').map(Number);
                      return new Date(y, m - 1, d, 0, 0, 0, 0);
                    })(),
                    lt: (() => {
                      const [y, m, d] = currentBD.split('-').map(Number);
                      const s = new Date(y, m - 1, d, 0, 0, 0, 0);
                      s.setDate(s.getDate() + 1);
                      return s;
                    })(),
                  },
                },
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
        menuItemId: it.menuItemId,
        variantId: it.variantId,
      })),
    }));
  }

  /// Allocate a collision-safe posOrderId for a mobile-originated order.
  /// Uses the greater of the persisted counter and the current max posOrderId
  /// already in the DB (never below 90001), then advances the counter. This
  /// survives counter drift and orders synced up from the POS that already sit
  /// in the mobile id range.
  private async allocateMobileOrderId(tenant: TenantContext): Promise<number> {
    const counterKey = 'mobileOrderIdCounter';
    const [counterSetting, maxAgg] = await Promise.all([
      (this.prisma as any).setting.findUnique({
        where: settingIdentity(tenant, counterKey),
      }),
      this.prisma.order.aggregate({
        where: { venueId: tenant.venueId },
        _max: { posOrderId: true },
      }),
    ]);
    const counterValue = counterSetting ? Number(counterSetting.value) : 0;
    const maxExisting = Number((maxAgg as any)?._max?.posOrderId ?? 0);
    const nextId = Math.max(counterValue + 1, maxExisting + 1, 90001);
    await (this.prisma as any).setting.upsert({
      where: settingIdentity(tenant, counterKey),
      update: { value: String(nextId) },
      create: {
        venueId: tenant.venueId,
        key: counterKey,
        value: String(nextId),
      },
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
