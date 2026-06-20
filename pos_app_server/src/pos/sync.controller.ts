import {
  Controller,
  Post,
  Body,
  Get,
  Query,
  UseGuards,
  OnModuleInit,
  Inject,
  forwardRef,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { PosOutboxService } from './pos-outbox.service';
import { PosCallbackClient } from './pos-callback.client';
import { MonitoringGateway } from '../realtime/monitoring.gateway';
import { AuthService } from '../auth/auth.service';
import { PosSyncGuard } from '../auth/pos-sync.guard';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { normalizeAuditEventType } from './audit/audit-event-type';
import {
  filterSuppressedOrderIds,
  isPosAuditBroadcastSuppressed,
  isPosEchoSuppressed,
  isReservationEchoSuppressed,
  isTableEchoSuppressed,
} from './sync-echo-guard';
import * as bcrypt from 'bcrypt';
import { normalizeStaffRole, StaffRole } from '../staff/staff-role';

interface TableSync {
  tableNumber: string;
  floor: string;
  isReserved: boolean;
  activeOrderId?: number;
  currentBill?: number;
}

interface OrderSync {
  posOrderId: number;
  orderId?: number;
  status: string;
  totalAmount: number;
  paymentType?: string;
  guestCount?: number;
  waiterName?: string;
  createdBy?: string;
  /** Table numbers for dine-in (POS mirrors local order.tables). */
  tableNumbers?: string[];
  floor?: string;
  businessDate?: string;
  customerName?: string;
  customerPhone?: string;
  pickupTime?: string;
  items?: any[];
  includeServiceFee?: boolean;
  discountAmount?: number;
  serviceFeePercent?: number;
  customServiceFeePercentage?: number;
}

interface ExpenseSync {
  description: string;
  amount: number;
  category: string;
  paymentType?: string;
  createdAt?: string;
}

interface StaffSync {
  username: string;
  /** Optional — routine POS sync must not send PINs; only explicit provisioning. */
  pin?: string;
  role: 'ADMIN' | 'MANAGER' | 'SUPERVISOR' | 'WAITER';
}

interface AuditEventLogSync {
  id: string;
  action: string;
  userId: string;
  data: any;
  deviceType: string;
  createdAt: string;
}

interface SyncPayload {
  tables?: TableSync[];
  orders?: OrderSync[];
  expenses?: ExpenseSync[];
  menu?: any[];
  staff?: StaffSync[];
  syncedAt?: string;
  posCallbackUrl?: string;
  posConnectionKey?: string;
  /** Fast path: tables/orders only — skip menu, staff, sales history DB work. */
  realtimeOnly?: boolean;
  quickOrders?: any[];
  /** ISO date string (YYYY-MM-DD) for the current POS business day */
  businessDate?: string;
  /** Exact Windows X-report დღიური გაყიდვები for current business date */
  dailySalesTotal?: number;
  salesSummary?: {
    date: string;
    totalRevenue: number;
    orderCount: number;
    cashRevenue: number;
    cardRevenue: number;
    paymentBreakdown: Record<string, number>;
    totalExpenses?: number;
    profit?: number;
  };
  salesAllTimeSummary?: {
    totalRevenue: number;
    orderCount: number;
    cashRevenue: number;
    cardRevenue: number;
    paymentBreakdown: Record<string, number>;
    topItems?: Array<{ name: string; qty: number; revenue: number }>;
  };
  salesHistoryByDate?: Record<
    string,
    {
      date: string;
      totalRevenue: number;
      orderCount: number;
      totalOrders: number;
      cancelledOrders: number;
      cashRevenue: number;
      cardRevenue: number;
      paymentBreakdown: Record<string, number>;
      totalExpenses?: number;
      profit?: number;
      topItems?: Array<{ name: string; qty: number; revenue: number }>;
      closedTables?: Array<{
        orderId?: number;
        tableLabel?: string;
        tableNumbers?: string[];
        floor?: string;
        isFiscal?: boolean;
        totalAmount?: number;
        closedAt?: string;
        paymentBreakdown?: Record<string, number>;
        items?: Array<{ name: string; qty: number; unitPrice: number; total: number }>;
      }>;
    }
  >;
  openTablesPayable?: number;
  settings?: {
    serviceFeePercent?: number;
    serviceFeeEnabled?: boolean;
  };
  /**
   * POS sends hints when item lines were removed or quantities decreased (sync snapshot diff).
   * Each hint carries manager-notification context: business-app time and table label.
   */
  touchedOrderHints?: Array<{
    posOrderId: number;
    occurredAt?: string;
    tableLabel?: string;
    floor?: string;
    waiterName?: string;
    highlightItemKeys?: string[];
    changeSummary?: string;
  }>;
  /** Table became occupied or free since last POS snapshot (walk-in / close). */
  touchedTableHints?: Array<{
    tableNumber: string;
    floor: string;
    changeType: 'reserved' | 'freed';
    activeOrderId?: number;
    currentBill?: number;
    occurredAt?: string;
  }>;
  /** Reservation created/updated/deleted on the POS — relays to mobile. */
  touchedReservationHints?: Array<{
    reservationId: string;
    action?: string;
    customerName?: string;
    reservationDate?: string;
    reservationTime?: string;
    tableNumbers?: number[];
    linkedOrderId?: number;
    notes?: string;
    walkIn?: boolean;
    occurredAt?: string;
  }>;
}

/** Keep the latest hint per order so rapid service-fee toggles emit one touch. */
function dedupeOrderHintsByPosOrderId<
  T extends { posOrderId: number },
>(hints: T[]): T[] {
  const byId = new Map<number, T>();
  for (const h of hints) {
    if (!Number.isFinite(h.posOrderId)) continue;
    byId.set(h.posOrderId, h);
  }
  return [...byId.values()];
}

@Controller('sync')
export class SyncController implements OnModuleInit {
  private static readonly POS_CALLBACK_URL_KEY = 'pos:callback_url';
  private static readonly POS_CONNECTION_KEY_KEY = 'pos:connection_key';

  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: MonitoringGateway,
    @Inject(forwardRef(() => PosOutboxService))
    private readonly posOutbox: PosOutboxService,
    private readonly posCallback: PosCallbackClient,
    private readonly pinVault: StaffPinVault,
  ) {}

  async onModuleInit(): Promise<void> {
    await this.loadPosCallbackFromDb();
  }

  private async loadPosCallbackFromDb(): Promise<void> {
    const [urlSetting, keySetting] = await Promise.all([
      (this.prisma as any).setting.findUnique({
        where: { key: SyncController.POS_CALLBACK_URL_KEY },
      }),
      (this.prisma as any).setting.findUnique({
        where: { key: SyncController.POS_CONNECTION_KEY_KEY },
      }),
    ]);
    if (urlSetting?.value) {
      const url = String(urlSetting.value);
      this.posCallback.setCallbackUrl(url);
      console.log(`[Sync] Restored POS callback URL: ${url}`);
    }
    if (keySetting?.value) {
      this.posCallback.setConnectionKey(String(keySetting.value));
    }
  }

  private async persistPosCallback(
    url?: string,
    key?: string,
  ): Promise<void> {
    if (url && url.trim().length > 0) {
      const trimmedUrl = url.trim();
      this.posCallback.setCallbackUrl(trimmedUrl);
      await (this.prisma as any).setting.upsert({
        where: { key: SyncController.POS_CALLBACK_URL_KEY },
        update: { value: trimmedUrl },
        create: {
          key: SyncController.POS_CALLBACK_URL_KEY,
          value: trimmedUrl,
        },
      });
      console.log(`[Sync] POS callback URL registered: ${trimmedUrl}`);
    }
    if (key && key.trim().length > 0) {
      const trimmedKey = key.trim();
      this.posCallback.setConnectionKey(trimmedKey);
      await (this.prisma as any).setting.upsert({
        where: { key: SyncController.POS_CONNECTION_KEY_KEY },
        update: { value: trimmedKey },
        create: {
          key: SyncController.POS_CONNECTION_KEY_KEY,
          value: trimmedKey,
        },
      });
    }
  }

  /**
   * GET /sync/diff?since=2024-01-01T00:00:00.000Z
   * Returns only records updated after `since`.
   * Mobile clients call this after reconnection instead of full reload.
   * Manager-only (mobile JWT) — exposes live table/order deltas, so it must
   * not be reachable unauthenticated.
   */
  @Get('diff')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(StaffRole.MANAGER)
  async getDiff(@Query('since') since?: string) {
    const sinceDate = since ? new Date(since) : new Date(0);

    const [tables, orders] = await Promise.all([
      (this.prisma as any).table.findMany({
        where: { updatedAt: { gt: sinceDate } },
      }),
      this.prisma.order.findMany({
        where: { updatedAt: { gt: sinceDate } },
        select: {
          posOrderId: true,
          status: true,
          totalAmount: true,
          waiterName: true,
          updatedAt: true,
        },
      }),
    ]);

    return {
      tables,
      orders,
      serverTime: new Date().toISOString(),
    };
  }

  @Post('manager-data')
  @UseGuards(PosSyncGuard)
  async syncManagerData(@Body() data: SyncPayload) {
    const {
      tables,
      orders,
      expenses,
      menu,
      staff,
      quickOrders,
      salesSummary,
      salesAllTimeSummary,
      salesHistoryByDate,
    } = data;

    const realtimeOnly = data.realtimeOnly === true;
    if (realtimeOnly) {
      console.log(
        `[SYNC] Realtime snapshot: ${tables?.length ?? 0} tables, ${orders?.length ?? 0} orders`,
      );
    }

    // Store POS callback URL for reverse-push (mobile → POS)
    await this.persistPosCallback(data.posCallbackUrl, data.posConnectionKey);
    if (!this.posCallback.hasCallbackUrl()) {
      console.warn(
        '[Sync] manager-data received without posCallbackUrl — start Windows POS (ingest on :8081) so mobile edits reach Hive.',
      );
    }

    let didSyncTables = false;

    // Sync Menu
    if (menu && !realtimeOnly) {
      console.log(`[SYNC] Syncing ${menu.length} categories...`);
      for (let catIndex = 0; catIndex < menu.length; catIndex++) {
        const cat = menu[catIndex];
        const category = await (this.prisma as any).menuCategory.upsert({
          where: { slug: cat.slug },
          update: {
            nameKa: cat.nameKa,
            nameEn: cat.nameEn,
            sendToKitchen: cat.sendToKitchen,
            sortOrder: catIndex,
          },
          create: {
            slug: cat.slug,
            nameKa: cat.nameKa,
            nameEn: cat.nameEn,
            sendToKitchen: cat.sendToKitchen,
            sortOrder: catIndex,
          },
        });

        // Sync Subcategories
        if (cat.subcategories) {
          for (let subIndex = 0; subIndex < cat.subcategories.length; subIndex++) {
            const sub = cat.subcategories[subIndex];
            const subcategory = await (this.prisma as any).menuSubcategory.upsert({
              where: { slug_categoryId: { slug: sub.slug, categoryId: category.id } },
              update: {
                nameKa: sub.nameKa,
                nameEn: sub.nameEn,
                sortOrder: subIndex,
              },
              create: {
                slug: sub.slug,
                nameKa: sub.nameKa,
                nameEn: sub.nameEn,
                categoryId: category.id,
                sortOrder: subIndex,
              },
            });

            if (sub.items) {
              for (let itemIndex = 0; itemIndex < sub.items.length; itemIndex++) {
                const it = sub.items[itemIndex];
                let existingItem = await (this.prisma as any).menuItem.findFirst({
                  where: { nameEn: it.nameEn, subcategoryId: subcategory.id },
                });
                if (existingItem) {
                  existingItem = await (this.prisma as any).menuItem.update({
                    where: { id: existingItem.id },
                    data: {
                      nameKa: it.nameKa,
                      price: it.price,
                      sendToKitchen: it.sendToKitchen,
                      sortOrder: itemIndex,
                    },
                  });
                } else {
                  existingItem = await (this.prisma as any).menuItem.create({
                    data: {
                      subcategoryId: subcategory.id,
                      nameKa: it.nameKa,
                      nameEn: it.nameEn,
                      price: it.price,
                      sendToKitchen: it.sendToKitchen,
                      sortOrder: itemIndex,
                    },
                  });
                }

                // Sync Variants
                if (it.variants) {
                  await (this.prisma as any).menuItemVariant.deleteMany({
                    where: { menuItemId: (existingItem as any).id },
                  });
                  for (const v of it.variants) {
                    await (this.prisma as any).menuItemVariant.create({
                      data: {
                        menuItemId: (existingItem as any).id,
                        size: v.size,
                        price: v.price,
                      },
                    });
                  }
                }
              }
            }
          }
        }

        if (cat.items) {
          for (let itemIndex = 0; itemIndex < cat.items.length; itemIndex++) {
            const it = cat.items[itemIndex];
            let existingItem = await (this.prisma as any).menuItem.findFirst({
              where: { nameEn: it.nameEn, categoryId: category.id, subcategoryId: null },
            });

            if (existingItem) {
              existingItem = await (this.prisma as any).menuItem.update({
                where: { id: existingItem.id },
                data: {
                  nameKa: it.nameKa,
                  price: it.price,
                  sendToKitchen: it.sendToKitchen,
                  sortOrder: itemIndex,
                },
              });
            } else {
              existingItem = await (this.prisma as any).menuItem.create({
                data: {
                  categoryId: category.id,
                  nameKa: it.nameKa,
                  nameEn: it.nameEn,
                  price: it.price,
                  sendToKitchen: it.sendToKitchen,
                  sortOrder: itemIndex,
                },
              });
            }

            // Sync Variants
            if (it.variants) {
              await (this.prisma as any).menuItemVariant.deleteMany({
                where: { menuItemId: (existingItem as any).id },
              });
              for (const v of it.variants) {
                await (this.prisma as any).menuItemVariant.create({
                  data: {
                    menuItemId: (existingItem as any).id,
                    size: v.size,
                    price: v.price,
                  },
                });
              }
            }
          }
        }
      }
    }

    console.log(
      '[Sync][MoneyDebug][IN] businessDate=%s dailySalesTotal=%s openTablesPayable=%s salesSummary.totalRevenue=%s orders=%s tables=%s',
      data.businessDate ?? '',
      data.dailySalesTotal ?? 'null',
      data.openTablesPayable ?? 'null',
      data.salesSummary?.totalRevenue ?? 'null',
      data.orders?.length ?? 0,
      data.tables?.length ?? 0,
    );

    // Sync Tables
    // Strategy: The POS is the source of truth.
    // We only process a full table sync if the POS payload contains at least
    // one reserved table OR an explicit activeOrderId. If the POS sends ALL
    // tables as free (e.g., on a cold/uninitialized boot), we preserve the
    // existing cloud state to prevent data loss.
    if (tables && tables.length > 0) {
      const hasAnyReserved = tables.some(
        (t) =>
          t.isReserved ||
          (t.activeOrderId !== undefined && t.activeOrderId !== null),
      );

      // Get existing reserved count in DB to detect if POS data seems stale
      const existingReservedCount = await (this.prisma as any).table.count({
        where: { isReserved: true },
      });

      // If the DB has reserved tables but POS is saying all are free, it's
      // a stale push (POS just booted). Skip the "free all" to preserve state.
      // Only skip "all free" snapshot on cold full sync (POS boot). Realtime pushes
      // must always apply — e.g. manager closes a table on Windows.
      const isPosDataStale =
        !data.realtimeOnly &&
        existingReservedCount > 0 &&
        !hasAnyReserved;

      if (isPosDataStale) {
        console.log(
          `Skipping table sync: DB has ${existingReservedCount} reserved tables but POS sent 0. POS may be initializing.`,
        );
      } else {
        didSyncTables = true;
        console.log(
          `Syncing ${tables.length} tables (hasAnyReserved=${hasAnyReserved}, realtimeOnly=${!!data.realtimeOnly})...`,
        );
        for (const table of tables) {
          const isActuallyReserved =
            table.isReserved ||
            (table.activeOrderId !== undefined &&
              table.activeOrderId !== null);

          if (isActuallyReserved) {
            console.log(
              `  Table ${table.tableNumber}/${table.floor} → reserved (orderId=${table.activeOrderId})`,
            );
          }

          await (this.prisma as any).table.upsert({
            where: {
              tableIdentifier: {
                tableNumber: table.tableNumber,
                floor: table.floor,
              },
            },
            update: {
              isReserved: isActuallyReserved,
              activeOrderId: isActuallyReserved
                ? (table.activeOrderId ?? null)
                : null,
              currentBill: isActuallyReserved ? (table.currentBill ?? 0) : 0,
            },
            create: {
              tableNumber: table.tableNumber,
              floor: table.floor,
              isReserved: isActuallyReserved,
              activeOrderId: isActuallyReserved
                ? (table.activeOrderId ?? null)
                : null,
              currentBill: isActuallyReserved ? (table.currentBill ?? 0) : 0,
            },
          });
        }
      }
    } else if (tables && tables.length === 0) {
      console.log(
        'Skipping table sync: empty tables array received (POS may be initializing)',
      );
    }

    // Sync Orders
    let releasedTablesFromClosedOrders = false;
    if (orders) {
      const incomingPosOrderIds = orders
        .map((o) => o.posOrderId ?? o.orderId)
        .filter((id): id is number => id !== undefined && id !== null);

      // Orders with an undelivered mobile change (outbox) are authoritative on the
      // server until the POS confirms it applied them. Ignore the POS's (stale)
      // snapshot for these so a startup/realtime push can't revert the edit.
      const pendingOutboxRows = await (
        this.prisma as any
      ).posCallbackOutbox.findMany({
        where: { status: 'pending', posOrderId: { not: null } },
        select: { posOrderId: true },
      });
      const pendingOutboxOrderIds = new Set<number>(
        pendingOutboxRows
          .map((r: { posOrderId: number | null }) => r.posOrderId)
          .filter((id: number | null): id is number => id !== null),
      );

      const terminalStatuses = new Set([
        'paid',
        'closed',
        'cancelled',
      ]);

      for (const order of orders) {
        const pOrderId = order.posOrderId ?? order.orderId;
        if (pOrderId === undefined) continue;

        // Skip stale POS snapshot while a mobile change for this order is in flight.
        if (pendingOutboxOrderIds.has(pOrderId)) {
          console.log(
            `[Sync] Holding order #${pOrderId}: mobile change pending POS delivery — ignoring POS snapshot.`,
          );
          continue;
        }

        const dbOrder = await this.prisma.order.upsert({
          where: { posOrderId: pOrderId },
          update: {
            status: order.status,
            totalAmount: order.totalAmount,
            paymentType: order.paymentType ?? 'cash',
            guestCount: order.guestCount ?? 0,
            waiterName: order.waiterName ?? order.createdBy ?? 'პერსონალი',
            floor: order.floor ?? '',
            businessDate: order.businessDate ?? data.businessDate ?? '',
            customerName: order.customerName ?? '',
            customerPhone: order.customerPhone ?? '',
            pickupTime: order.pickupTime ?? '',
            includeServiceFee: order.includeServiceFee ?? false,
            discountAmount: order.discountAmount ?? 0,
            serviceFeePercent: order.serviceFeePercent ?? order.customServiceFeePercentage ?? 10,
          },
          create: {
            posOrderId: pOrderId,
            status: order.status,
            totalAmount: order.totalAmount,
            paymentType: order.paymentType ?? 'cash',
            guestCount: order.guestCount ?? 0,
            waiterName: order.waiterName ?? order.createdBy ?? 'პერსონალი',
            floor: order.floor ?? '',
            businessDate: order.businessDate ?? data.businessDate ?? '',
            customerName: order.customerName ?? '',
            customerPhone: order.customerPhone ?? '',
            pickupTime: order.pickupTime ?? '',
            includeServiceFee: order.includeServiceFee ?? false,
            discountAmount: order.discountAmount ?? 0,
            serviceFeePercent: order.serviceFeePercent ?? order.customServiceFeePercentage ?? 10,
          },
        });

        // Sync Items
        if (order.items) {
          await (this.prisma as any).orderItem.deleteMany({
            where: { orderId: dbOrder.id },
          });

          for (const item of order.items) {
            await (this.prisma as any).orderItem.create({
              data: {
                orderId: dbOrder.id,
                name: item.name,
                quantity: item.quantity,
                price: item.price,
              },
            });
          }
        }

        const status = (order.status ?? '').toLowerCase();
        const floor = order.floor ?? 'first';
        const isTakeaway = floor.toLowerCase().includes('takeaway');
        const tableNumbers = Array.isArray(order.tableNumbers)
          ? order.tableNumbers
          : [];

        // Active dine-in orders must reserve tables even when POS table snapshot is stale.
        if (!terminalStatuses.has(status) && !isTakeaway) {
          for (const rawNum of tableNumbers) {
            const tableNumber = String(rawNum)
              .replace(/^table\s*/i, '')
              .trim();
            if (!tableNumber) continue;
            await (this.prisma as any).table.upsert({
              where: {
                tableIdentifier: { tableNumber, floor },
              },
              update: {
                isReserved: true,
                activeOrderId: pOrderId,
                currentBill: order.totalAmount ?? 0,
              },
              create: {
                tableNumber,
                floor,
                isReserved: true,
                activeOrderId: pOrderId,
                currentBill: order.totalAmount ?? 0,
              },
            });
            didSyncTables = true;
            console.log(
              `[Sync] Linked table ${tableNumber}/${floor} → order #${pOrderId} (${status})`,
            );
          }
        }

        // When POS closes/pays an order, free linked tables even if table snapshot was skipped.
        if (terminalStatuses.has(status)) {
          for (const rawNum of tableNumbers) {
            const tableNumber = String(rawNum)
              .replace(/^table\s*/i, '')
              .trim();
            if (!tableNumber) continue;
            const result = await (this.prisma as any).table.updateMany({
              where: { tableNumber, floor },
              data: {
                isReserved: false,
                activeOrderId: null,
                currentBill: 0,
              },
            });
            if (result.count > 0) {
              releasedTablesFromClosedOrders = true;
              console.log(
                `[Sync] Freed table ${tableNumber}/${floor} (order #${pOrderId} ${status})`,
              );
            }
          }
        }
      }

      // Reconcile takeaway orders for the current business date:
      // if POS restore removed takeaways locally, backend must drop stale rows too.
      const currentBusinessDate = data.businessDate;
      if (currentBusinessDate) {
        // Never delete an order that still has an undelivered mobile change
        // queued (e.g. a mobile-created takeaway the POS hasn't received yet).
        const protectedPosOrderIds = [
          ...incomingPosOrderIds,
          ...pendingOutboxOrderIds,
        ];
        // Reconcile dine-in orders too (non-takeaway). Without this, stale
        // pre-restore rows can remain and dashboard open-payable gets doubled.
        const staleDineInOrders = await this.prisma.order.findMany({
          where: {
            businessDate: currentBusinessDate,
            NOT: {
              OR: [
                { floor: { contains: 'takeaway', mode: 'insensitive' } },
                { floor: { contains: 'take away', mode: 'insensitive' } },
              ],
            },
            ...(protectedPosOrderIds.length > 0
              ? { posOrderId: { notIn: protectedPosOrderIds } }
              : {}),
          },
          select: { id: true },
        });
        if (staleDineInOrders.length > 0) {
          const staleIds = staleDineInOrders.map((o) => o.id);
          await (this.prisma as any).orderItem.deleteMany({
            where: { orderId: { in: staleIds } },
          });
          await this.prisma.order.deleteMany({
            where: { id: { in: staleIds } },
          });
        }

        await (this.prisma as any).order.deleteMany({
          where: {
            floor: 'takeaway',
            businessDate: currentBusinessDate,
            ...(protectedPosOrderIds.length > 0
              ? { posOrderId: { notIn: protectedPosOrderIds } }
              : {}),
          },
        });
      }
    }

    // Sync Expenses
    if (expenses) {
      for (const expense of expenses) {
        await (this.prisma.expense.create as any)({
          data: {
            description: expense.description,
            amount: expense.amount,
            category: expense.category,
            paymentType: expense.paymentType ?? 'cash',
            createdAt: expense.createdAt
              ? new Date(expense.createdAt)
              : new Date(),
          },
        });
      }
    }

    // Sync Staff — username/role only unless pin explicitly provided (legacy).
    if (staff && staff.length > 0 && !realtimeOnly) {
      const plainPinsByUsername = await this.pinVault.read();
      let pinsMapChanged = false;
      const incomingUsernames = new Set<string>();
      for (const member of staff) {
        incomingUsernames.add(member.username);
        const pin =
          typeof member.pin === 'string' ? member.pin.trim() : '';
        const hasPin = pin.length > 0;

        if (hasPin) {
          const pinHash = await bcrypt.hash(pin, 12);
          await (this.prisma as any).staff.upsert({
            where: { username: member.username },
            update: {
              pinHash,
              role: normalizeStaffRole(member.role),
              isActive: true,
            },
            create: {
              username: member.username,
              pinHash,
              role: normalizeStaffRole(member.role),
              isActive: true,
            },
          });
          plainPinsByUsername[member.username] = pin;
          pinsMapChanged = true;
        } else {
          const existing = await (this.prisma as any).staff.findUnique({
            where: { username: member.username },
          });
          if (existing) {
            await (this.prisma as any).staff.update({
              where: { username: member.username },
              data: { role: normalizeStaffRole(member.role), isActive: true },
            });
          } else {
            console.warn(
              `[SYNC] Skipping new staff "${member.username}" without PIN (use mobile user create).`,
            );
          }
        }
      }
      if (pinsMapChanged) {
        await this.pinVault.write(plainPinsByUsername);
      }

      // Reconcile deletions: if user disappeared from Windows POS list,
      // remove it from backend too so mobile and Windows stay 1:1.
      const existing = await (this.prisma as any).staff.findMany({
        select: { username: true },
      });
      const stale = existing
        .map((u: any) => String(u.username ?? ''))
        .filter((username: string) => username.length > 0 && !incomingUsernames.has(username));
      if (stale.length > 0) {
        await (this.prisma as any).staff.deleteMany({
          where: { username: { in: stale } },
        });
      }
    }

    const touchedOrderHints = Array.isArray(data.touchedOrderHints)
      ? data.touchedOrderHints
          .map((h: any) => ({
            posOrderId: Number(h?.posOrderId),
            occurredAt:
              typeof h?.occurredAt === 'string' && h.occurredAt.trim().length > 0
                ? h.occurredAt.trim()
                : undefined,
            tableLabel:
              typeof h?.tableLabel === 'string' ? h.tableLabel.trim() : '',
            floor: typeof h?.floor === 'string' ? h.floor.trim() : undefined,
            waiterName:
              typeof h?.waiterName === 'string' ? h.waiterName.trim() : undefined,
            highlightItemKeys: Array.isArray(h?.highlightItemKeys)
              ? h.highlightItemKeys
                  .map((k: unknown) => String(k).trim())
                  .filter((k: string) => k.length > 0)
              : undefined,
            changeSummary:
              typeof h?.changeSummary === 'string' ? h.changeSummary.trim() : undefined,
            changeKind:
              typeof h?.changeKind === 'string' ? h.changeKind.trim() : undefined,
          }))
          .filter((h: any) => Number.isFinite(h.posOrderId))
      : [];
    const filteredOrderHints = dedupeOrderHintsByPosOrderId(
      touchedOrderHints.filter(
        (h: { posOrderId: number }) => !isPosEchoSuppressed(h.posOrderId),
      ),
    );
    const hadOrderLineTouch = filteredOrderHints.length > 0;
    if (hadOrderLineTouch) {
      this.gateway.broadcastUpdate('orders_bulk_touch', {
        touches: filteredOrderHints,
        posOrderIds: filteredOrderHints.map((h: { posOrderId: number }) => h.posOrderId),
        source: 'pos_sync',
      });
    }

    const touchedTableHints = Array.isArray(data.touchedTableHints)
      ? data.touchedTableHints
          .map((h: any) => ({
            tableNumber: String(h?.tableNumber ?? '').trim(),
            floor: String(h?.floor ?? 'first').trim(),
            changeType:
              h?.changeType === 'freed' ? ('freed' as const) : ('reserved' as const),
            activeOrderId:
              h?.activeOrderId !== undefined && h?.activeOrderId !== null
                ? Number(h.activeOrderId)
                : undefined,
            currentBill:
              h?.currentBill !== undefined && h?.currentBill !== null
                ? Number(h.currentBill)
                : undefined,
            occurredAt:
              typeof h?.occurredAt === 'string' && h.occurredAt.trim().length > 0
                ? h.occurredAt.trim()
                : undefined,
          }))
          .filter((h) => h.tableNumber.length > 0)
      : [];
    const filteredTableHints = touchedTableHints.filter((h) => {
      if (isTableEchoSuppressed(h.tableNumber, h.floor)) return false;
      if (
        h.activeOrderId !== undefined &&
        isPosEchoSuppressed(h.activeOrderId)
      ) {
        return false;
      }
      return true;
    });
    const hadTableTouch = filteredTableHints.length > 0;
    if (hadTableTouch) {
      const tableSnapshots: Array<Record<string, unknown>> = [];
      for (const hint of filteredTableHints) {
        const row = await (this.prisma as any).table.findFirst({
          where: { tableNumber: hint.tableNumber, floor: hint.floor },
        });
        if (row) {
          const occupied = !!(row.isReserved || row.activeOrderId);
          tableSnapshots.push({
            tableNumber: row.tableNumber,
            floor: row.floor,
            isReserved: occupied,
            isOccupied: occupied,
            activeOrderId: occupied ? row.activeOrderId : null,
            currentBill: occupied ? (row.currentBill ?? 0) : 0,
          });
        }
      }
      this.gateway.broadcastUpdate('tables_bulk_touch', {
        touches: filteredTableHints,
        tables: tableSnapshots,
        source: 'pos_sync',
      });
    }

    // Reservation changes from the POS → notify mobile (skip mobile-originated
    // round-trips, which are already echoed at create time).
    const reservationHints = Array.isArray(data.touchedReservationHints)
      ? data.touchedReservationHints
          .map((h) => ({
            reservationId: String(h?.reservationId ?? '').trim(),
            action: typeof h?.action === 'string' ? h.action : 'updated',
            customerName:
              typeof h?.customerName === 'string'
                ? h.customerName.trim()
                : undefined,
            reservationDate:
              typeof h?.reservationDate === 'string'
                ? h.reservationDate.trim()
                : undefined,
            reservationTime:
              typeof h?.reservationTime === 'string'
                ? h.reservationTime.trim()
                : undefined,
            tableNumbers: Array.isArray(h?.tableNumbers)
              ? h.tableNumbers
              : undefined,
            linkedOrderId:
              typeof h?.linkedOrderId === 'number' &&
              Number.isFinite(h.linkedOrderId)
                ? h.linkedOrderId
                : undefined,
            notes:
              typeof h?.notes === 'string' && h.notes.trim().length > 0
                ? h.notes.trim()
                : undefined,
            walkIn: h?.walkIn === true,
            occurredAt:
              typeof h?.occurredAt === 'string' && h.occurredAt.trim().length > 0
                ? h.occurredAt.trim()
                : undefined,
          }))
          .filter((h) => h.reservationId.length > 0)
      : [];
    const filteredReservationHints = reservationHints.filter(
      (h) => !isReservationEchoSuppressed(h.reservationId),
    );
    if (filteredReservationHints.length > 0) {
      const latest = filteredReservationHints[filteredReservationHints.length - 1];
      const customer = (latest.customerName ?? '').trim().toLowerCase();
      const walkIn =
        latest.walkIn === true ||
        customer === 'walk-in' ||
        customer.includes('walk-in');
      this.gateway.broadcastUpdate('data_updated', {
        type: 'reservations',
        reservationId: latest.reservationId,
        customerName: latest.customerName,
        reservationDate: latest.reservationDate,
        reservationTime: latest.reservationTime,
        tableNumbers: latest.tableNumbers,
        action: latest.action,
        touches: filteredReservationHints,
        source: 'pos_sync',
        ...(latest.linkedOrderId !== undefined
          ? { linkedOrderId: latest.linkedOrderId }
          : {}),
        ...(latest.notes !== undefined ? { notes: latest.notes } : {}),
        ...(walkIn ? { walkIn: true } : {}),
        ...(walkIn && latest.linkedOrderId !== undefined
          ? { posOrderId: latest.linkedOrderId }
          : {}),
      });
    }

    const changed =
      didSyncTables ||
      !!orders ||
      !!expenses ||
      !!menu ||
      !!staff;

    // Avoid duplicate "სალარო" + "მაგიდები" toasts: line changes use orders_bulk_touch only.
    if (orders && orders.length > 0 && !hadOrderLineTouch && !hadTableTouch) {
      const posOrderIds = filterSuppressedOrderIds(
        orders
          .map((o) => Number(o.posOrderId))
          .filter((id) => Number.isFinite(id)),
      );
      if (posOrderIds.length > 0) {
        this.gateway.broadcastUpdate('order_updated', {
          posOrderIds,
          source: 'pos_sync',
        });
      }
    }
    if (didSyncTables || releasedTablesFromClosedOrders) {
      this.gateway.broadcastUpdate('table_updated', { source: 'pos_sync' });
    }
    if (changed) {
      this.gateway.broadcastUpdate('data_updated', { type: 'all' });
    }

    // ── Business date tracking ──────────────────────────────────────────────
    // The POS sends its current business date (YYYY-MM-DD). Store it so the
    // mobile dashboard queries the correct date range instead of calendar-day.
    if (data.businessDate) {
      const newDate = data.businessDate; // e.g. "2026-04-30"
      const existing = await (this.prisma as any).setting.findUnique({
        where: { key: 'currentBusinessDate' },
      });
      const prevDate = existing?.value ?? null;

      await (this.prisma as any).setting.upsert({
        where: { key: 'currentBusinessDate' },
        update: { value: newDate },
        create: { key: 'currentBusinessDate', value: newDate },
      });

      const openedAtKey = `businessDayOpenedAt:${newDate}`;
      const openedAtExisting = await (this.prisma as any).setting.findUnique({
        where: { key: openedAtKey },
      });
      const dayAdvanced = prevDate !== null && prevDate !== newDate;
      if (dayAdvanced || !openedAtExisting?.value) {
        const openedAt = new Date().toISOString();
        await (this.prisma as any).setting.upsert({
          where: { key: openedAtKey },
          update: { value: openedAt },
          create: { key: openedAtKey, value: openedAt },
        });
      }

      // If the date actually advanced, the manager closed the day → notify mobile
      if (dayAdvanced) {
        console.log(`[Sync] Business date advanced: ${prevDate} → ${newDate}. Clearing all table reservations.`);
        // Reset every table to free so ghost tables from the previous business
        // day cannot persist. The stale-data protection in the table sync below
        // would otherwise block the next "all tables free" push from the POS.
        await (this.prisma as any).table.updateMany({
          data: { isReserved: false, activeOrderId: null, currentBill: 0 },
        });
        this.gateway.broadcastUpdate('day_closed', { date: newDate, prevDate });
      }
    }

    // Persist POS day sales summary (payment methods + totals) so mobile reads
    // exactly what Windows saved locally after table close.
    if (salesSummary?.date) {
      const summaryValue = JSON.stringify({
        date: salesSummary.date,
        totalRevenue: salesSummary.totalRevenue ?? 0,
        orderCount: salesSummary.orderCount ?? 0,
        cashRevenue: salesSummary.cashRevenue ?? 0,
        cardRevenue: salesSummary.cardRevenue ?? 0,
        paymentBreakdown: salesSummary.paymentBreakdown ?? {},
        totalExpenses: salesSummary.totalExpenses ?? 0,
        profit: salesSummary.profit ?? 0,
        syncedAt: new Date().toISOString(),
      });
      await (this.prisma as any).setting.upsert({
        where: { key: `salesSummary:${salesSummary.date}` },
        update: { value: summaryValue },
        create: { key: `salesSummary:${salesSummary.date}`, value: summaryValue },
      });
    }

    if (salesAllTimeSummary && !realtimeOnly) {
      const allTimeValue = JSON.stringify({
        totalRevenue: salesAllTimeSummary.totalRevenue ?? 0,
        orderCount: salesAllTimeSummary.orderCount ?? 0,
        cashRevenue: salesAllTimeSummary.cashRevenue ?? 0,
        cardRevenue: salesAllTimeSummary.cardRevenue ?? 0,
        paymentBreakdown: salesAllTimeSummary.paymentBreakdown ?? {},
        topItems: salesAllTimeSummary.topItems ?? [],
        syncedAt: new Date().toISOString(),
      });
      await (this.prisma as any).setting.upsert({
        where: { key: 'salesSummary:all_time' },
        update: { value: allTimeValue },
        create: { key: 'salesSummary:all_time', value: allTimeValue },
      });
    }

    if (salesHistoryByDate && typeof salesHistoryByDate === 'object' && !realtimeOnly) {
      for (const [date, summary] of Object.entries(salesHistoryByDate)) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
        const summaryValue = JSON.stringify({
          date,
          totalRevenue: summary.totalRevenue ?? 0,
          orderCount: summary.orderCount ?? 0,
          totalOrders: summary.totalOrders ?? 0,
          cancelledOrders: summary.cancelledOrders ?? 0,
          cashRevenue: summary.cashRevenue ?? 0,
          cardRevenue: summary.cardRevenue ?? 0,
          paymentBreakdown: summary.paymentBreakdown ?? {},
          totalExpenses: summary.totalExpenses ?? 0,
          profit: summary.profit ?? 0,
          topItems: summary.topItems ?? [],
          closedTables: summary.closedTables ?? [],
        });
        await (this.prisma as any).setting.upsert({
          where: { key: `salesSummary:${date}` },
          update: { value: summaryValue },
          create: { key: `salesSummary:${date}`, value: summaryValue },
        });
      }
      await (this.prisma as any).setting.upsert({
        where: { key: 'salesSummary:history_index' },
        update: { value: JSON.stringify(Object.keys(salesHistoryByDate).sort()) },
        create: {
          key: 'salesSummary:history_index',
          value: JSON.stringify(Object.keys(salesHistoryByDate).sort()),
        },
      });
    }

    if (data.settings) {
      const percent = Number(data.settings.serviceFeePercent ?? 10);
      const enabled = data.settings.serviceFeeEnabled === true;
      await (this.prisma as any).setting.upsert({
        where: { key: 'restaurant:serviceFeePercent' },
        update: { value: String(percent) },
        create: { key: 'restaurant:serviceFeePercent', value: String(percent) },
      });
      await (this.prisma as any).setting.upsert({
        where: { key: 'restaurant:serviceFeeEnabled' },
        update: { value: enabled ? 'true' : 'false' },
        create: {
          key: 'restaurant:serviceFeeEnabled',
          value: enabled ? 'true' : 'false',
        },
      });
    }

    if (data.dailySalesTotal !== undefined && data.businessDate) {
      await (this.prisma as any).setting.upsert({
        where: { key: `dailySalesTotal:${data.businessDate}` },
        update: { value: String(data.dailySalesTotal ?? 0) },
        create: {
          key: `dailySalesTotal:${data.businessDate}`,
          value: String(data.dailySalesTotal ?? 0),
        },
      });
    }

    if (data.businessDate) {
      const fromOccupiedTables = (tables ?? [])
        .filter(
          (t) =>
            t.isReserved ||
            (t.activeOrderId !== undefined && t.activeOrderId !== null),
        )
        .reduce((sum, t) => sum + Number(t.currentBill ?? 0), 0);

      const openTablesPayableToStore = fromOccupiedTables;

      await (this.prisma as any).setting.upsert({
        where: { key: `openTablesPayable:${data.businessDate}` },
        update: { value: String(openTablesPayableToStore) },
        create: {
          key: `openTablesPayable:${data.businessDate}`,
          value: String(openTablesPayableToStore),
        },
      });
      console.log(
        '[Sync][MoneyDebug][STORE] key=openTablesPayable:%s value=%s',
        data.businessDate,
        openTablesPayableToStore,
      );
    }

    if (data.dailySalesTotal !== undefined && data.businessDate) {
      console.log(
        '[Sync][MoneyDebug][STORE] key=dailySalesTotal:%s value=%s',
        data.businessDate,
        data.dailySalesTotal ?? 0,
      );
    }

    // POS just pushed (so it's online): flush any held mobile changes to Hive
    // now instead of waiting out the retry backoff. Runs after order sync so
    // this push's stale snapshot is already held, not overwritten.
    void this.posOutbox.kickPending();

    return { success: true, syncedAt: new Date().toISOString() };
  }

  /**
   * POST /sync/audit-reports
   * Windows POS pushes full AuditReport list (with events) here on every change.
   * Uses upsert-by-reportId so re-pushes are idempotent.
   */
  @Post('audit-reports')
  @UseGuards(PosSyncGuard)
  async syncAuditReports(@Body() body: { reports?: any[]; fullSync?: boolean }) {
    const reports = body?.reports;
    const fullSync = body?.fullSync === true;
    if (!Array.isArray(reports)) {
      console.log('[SyncAudit] Invalid reports payload');
      return { success: true, upserted: 0 };
    }

    console.log(`[SyncAudit] Processing batch of ${reports.length} reports...`);

    let upserted = 0;
    for (const r of reports) {
      const reportId = r.reportId as string | undefined;
      if (!reportId) continue;

      const syncedUpdatedAt = r.updatedAt ? new Date(r.updatedAt) : new Date();

      // Upsert the AuditReport row
      const dbReport = await (this.prisma as any).auditReport.upsert({
        where: { reportId },
        update: {
          posOrderId: r.orderId ?? 0,
          tableNumbers: Array.isArray(r.tableNumbers) ? r.tableNumbers : [],
          floor: r.floor ?? 'first',
          openedById: r.openedById ?? '',
          openedByName: r.openedByName ?? '',
          openedAt: r.openedAt ? new Date(r.openedAt) : new Date(),
          status: (r.status ?? 'OPEN').toUpperCase(),
          closedAt: r.closedAt ? new Date(r.closedAt) : null,
          closedById: r.closedById ?? null,
          closedByName: r.closedByName ?? null,
          locked: r.locked ?? false,
          updatedAt: syncedUpdatedAt,
        },
        create: {
          reportId,
          posOrderId: r.orderId ?? 0,
          tableNumbers: Array.isArray(r.tableNumbers) ? r.tableNumbers : [],
          floor: r.floor ?? 'first',
          openedById: r.openedById ?? '',
          openedByName: r.openedByName ?? '',
          openedAt: r.openedAt ? new Date(r.openedAt) : new Date(),
          status: (r.status ?? 'OPEN').toUpperCase(),
          closedAt: r.closedAt ? new Date(r.closedAt) : null,
          closedById: r.closedById ?? null,
          closedByName: r.closedByName ?? null,
          locked: r.locked ?? false,
          updatedAt: syncedUpdatedAt,
        },
      });

      // Optimized event sync: Delete and createMany
      await (this.prisma as any).auditEvent.deleteMany({
        where: { reportId: dbReport.id },
      });

      const events: any[] = Array.isArray(r.events) ? r.events : [];
      if (events.length > 0) {
        console.log(`  Report ${reportId}: syncing ${events.length} events...`);
        await (this.prisma as any).auditEvent.createMany({
          data: events.map((ev, seq) => ({
            reportId: dbReport.id,
            type: normalizeAuditEventType(
              ev.type,
              ev.previousQty,
              ev.newQty,
            ),
            itemName: ev.itemName ?? '',
            previousQty: ev.previousQty ?? 0,
            newQty: ev.newQty ?? 0,
            waiterId: ev.waiterId ?? '',
            waiterName: ev.waiterName ?? '',
            eventTime: ev.timestamp ? new Date(ev.timestamp) : new Date(),
            note: ev.note ?? null,
            seq,
          })),
        });
      }
      upserted++;
    }

    // Full reconciliation mode: remove stale backend reports not present in
    // current Windows snapshot (important after backup restore/import).
    if (fullSync) {
      const incomingReportIds = reports
        .map((r) => r?.reportId as string | undefined)
        .filter((id): id is string => !!id);

      const staleReports = await (this.prisma as any).auditReport.findMany({
        where:
          incomingReportIds.length > 0
            ? { reportId: { notIn: incomingReportIds } }
            : {},
        select: { id: true },
      });

      if (staleReports.length > 0) {
        const staleIds = staleReports.map((r: any) => r.id as string);
        await (this.prisma as any).auditEvent.deleteMany({
          where: { reportId: { in: staleIds } },
        });
        await (this.prisma as any).auditReport.deleteMany({
          where: { id: { in: staleIds } },
        });
      }
    }

    if (upserted > 0 && !isPosAuditBroadcastSuppressed()) {
      this.gateway.broadcastUpdate('audit_updated', { count: upserted });
    }
    return { success: true, upserted };
  }

  /**
   * POST /sync/audit-logs
   * Syncs generic audit event logs (append-only).
   * Idempotent based on UUID.
   */
  @Post('audit-logs')
  @UseGuards(PosSyncGuard)
  async syncAuditEventLogs(@Body() body: { logs?: AuditEventLogSync[] }) {
    const logs = body?.logs;
    if (!Array.isArray(logs) || logs.length === 0) {
      return { success: true, count: 0 };
    }

    let count = 0;
    for (const log of logs) {
      try {
        await (this.prisma as any).auditEventLog.upsert({
          where: { id: log.id },
          update: {}, // Immutable: do nothing if exists
          create: {
            id: log.id,
            action: log.action,
            userId: log.userId,
            data: log.data ?? {},
            deviceType: log.deviceType,
            createdAt: log.createdAt ? new Date(log.createdAt) : new Date(),
          },
        });
        count++;
      } catch (e) {
        // Log error but continue with other logs
        console.warn(`[Sync] Error upserting audit log ${log.id}:`, (e as Error).message);
      }
    }

    return { success: true, count };
  }
}

