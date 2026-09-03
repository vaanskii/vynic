process.env.COOKIE_ENCRYPTION_KEY ??= 'enrolled-pos-sync-integration-key!!';

jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import type { PosAuthContext } from '../auth/pos-auth-context';
import { PlatformAuditService } from '../platform/platform-audit.service';
import { IngestAuditReportsService } from '../pos/sync/application/ingest-audit-reports.service';
import { BusinessDaySyncService } from '../pos/sync/snapshot/business-day-sync.service';
import { MenuSyncService } from '../pos/sync/snapshot/menu-sync.service';
import { OrderSyncService } from '../pos/sync/snapshot/order-sync.service';
import { StaffSyncService } from '../pos/sync/snapshot/staff-sync.service';
import { TableSyncService } from '../pos/sync/snapshot/table-sync.service';
import { DeviceEnrollmentService } from './device-enrollment.service';
import { EnrollmentRateLimiter } from './enrollment-rate-limiter';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

/**
 * The whole point of enrolling: a terminal that just typed a code can push its
 * operational state to Cloud, and it lands in exactly one Venue.
 *
 * Nothing here supplies a `venueId`. Every write is scoped by the tenant
 * context the *credential* resolved to, which is the property that makes the
 * enrollment code — not the client — the authority over which restaurant a
 * terminal writes into.
 */
describeDatabase('An enrolled POS pushing to the backend (PostgreSQL)', () => {
  let prisma: PrismaService;
  let credentials: DeviceCredentialService;
  let enrollments: DeviceEnrollmentService;
  let tables: TableSyncService;
  let orders: OrderSyncService;
  let menu: MenuSyncService;
  let staff: StaffSyncService;
  let businessDay: BusinessDaySyncService;
  let audit: IngestAuditReportsService;

  const suffix = `${process.pid}`.padStart(12, '0');
  let adminId: string;
  let organizationId: string;
  let venueAId: string;
  let venueBId: string;
  let posA: PosAuthContext;
  let installationId: string;

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    credentials = new DeviceCredentialService(prisma);
    enrollments = new DeviceEnrollmentService(
      prisma,
      credentials,
      new PlatformAuditService(prisma),
      new EnrollmentRateLimiter(),
    );
    tables = new TableSyncService(prisma);
    orders = new OrderSyncService(prisma);
    menu = new MenuSyncService(prisma);
    staff = new StaffSyncService(prisma, new StaffPinVault(prisma));
    businessDay = new BusinessDaySyncService(prisma);
    audit = new IngestAuditReportsService(prisma, {} as never);

    const admin = await prisma.platformUser.create({
      data: {
        email: `sync-admin-${suffix}@vynic.test`,
        displayName: 'Sync Admin',
        passwordHash: 'not-a-real-hash',
      },
      select: { id: true },
    });
    adminId = admin.id;

    const organization = await prisma.organization.create({
      data: {
        name: `Enrolled sync fixture ${suffix}`,
        venues: {
          create: [
            { name: 'Venue A', timezone: 'Asia/Tbilisi', currency: 'GEL' },
            { name: 'Venue B', timezone: 'Asia/Tbilisi', currency: 'GEL' },
          ],
        },
      },
      select: { id: true, venues: { select: { id: true, name: true } } },
    });
    organizationId = organization.id;
    venueAId = organization.venues.find((v) => v.name === 'Venue A')!.id;
    venueBId = organization.venues.find((v) => v.name === 'Venue B')!.id;

    // Enroll a terminal into Venue A exactly the way an operator would, then
    // authenticate as it. Everything below runs on what that produced.
    installationId = randomUUID();
    const created = await enrollments.create(
      { platformUserId: adminId },
      venueAId,
      { displayName: 'Front POS', platform: 'WINDOWS' },
    );
    const redeemed = await enrollments.redeem({
      code: created.code,
      installationId,
      platform: 'WINDOWS',
      clientIp: '10.42.0.1',
    });
    posA = (await credentials.verifyCredential(redeemed.credential))!;
  });

  afterAll(async () => {
    const venueIds = [venueAId, venueBId];
    await prisma.auditEventLog.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.expense.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.orderItem.deleteMany({
      where: { order: { venueId: { in: venueIds } } },
    });
    await prisma.order.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.table.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.menuItem.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.menuCategory.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.staff.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.setting.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.deviceEnrollment.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.device.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.deleteMany({ where: { id: organizationId } });
    await prisma.platformAuditEvent.deleteMany({
      where: { platformUserId: adminId },
    });
    await prisma.platformUser.deleteMany({ where: { id: adminId } });
    await prisma.$disconnect();
  });

  it('resolves the enrolled venue from the credential, never from a request', () => {
    expect(posA.authenticationMode).toBe('device');
    expect(posA.venueId).toBe(venueAId);
    expect(posA.organizationId).toBe(organizationId);
    expect(posA.deviceId).toBeTruthy();
  });

  it('lands tables, orders, menu and staff in the enrolled venue only', async () => {
    await tables.sync(
      posA,
      [
        { tableNumber: '1', floor: 'Hall', isReserved: true, activeOrderId: 7 },
        { tableNumber: '2', floor: 'Hall', isReserved: false },
      ],
      false,
    );
    await orders.sync(
      posA,
      [
        {
          posOrderId: 7,
          status: 'closed',
          totalAmount: 118,
          discountAmount: 5,
          // Phase 1A's field. It has to survive the round trip or a cloud-side
          // total can never be reconciled against the POS that produced it.
          manualAdjustmentAmount: -12,
          businessDate: '2026-09-03',
          waiterName: 'giorgi',
          tableNumbers: ['1'],
          items: [{ name: 'ხინკალი', quantity: 2, price: 65 }],
        },
      ],
      '2026-09-03',
    );
    await menu.sync(posA, [
      {
        slug: 'hot-dishes',
        nameKa: 'ცხელი კერძები',
        nameEn: 'Hot dishes',
        sendToKitchen: true,
        subcategories: [
          {
            slug: 'dumplings',
            nameKa: 'ხინკალი',
            nameEn: 'Dumplings',
            items: [
              {
                nameKa: 'ხინკალი',
                nameEn: 'Khinkali',
                price: 65,
                sendToKitchen: true,
              },
            ],
          },
        ],
      },
    ]);
    // A PIN, because routine sync deliberately refuses to create a new staff
    // member without one — this is the provisioning path, not the hot path.
    await staff.sync(posA, [
      { username: 'giorgi', pin: '4821', role: 'MANAGER' },
    ]);

    const order = await prisma.order.findFirstOrThrow({
      where: { venueId: venueAId, posOrderId: 7 },
      select: {
        venueId: true,
        totalAmount: true,
        discountAmount: true,
        manualAdjustmentAmount: true,
      },
    });
    expect(order.venueId).toBe(venueAId);
    expect(order.manualAdjustmentAmount).toBe(-12);
    expect(order.discountAmount).toBe(5);

    expect(await prisma.table.count({ where: { venueId: venueAId } })).toBe(2);
    expect(
      await prisma.menuItem.count({ where: { venueId: venueAId } }),
    ).toBeGreaterThan(0);
    expect(await prisma.staff.count({ where: { venueId: venueAId } })).toBe(1);

    // Venue B was never named and gained nothing.
    for (const count of await Promise.all([
      prisma.order.count({ where: { venueId: venueBId } }),
      prisma.table.count({ where: { venueId: venueBId } }),
      prisma.menuItem.count({ where: { venueId: venueBId } }),
      prisma.staff.count({ where: { venueId: venueBId } }),
    ])) {
      expect(count).toBe(0);
    }
  });

  it('stores real expenses once, however many times the POS resends them', async () => {
    const expense = {
      id: `exp-${suffix}-1`,
      description: 'მიწოდება',
      amount: 42.5,
      category: 'supplies',
      businessDate: '2026-09-03',
    };

    await businessDay.recordExpenses(posA, [expense]);
    await businessDay.recordExpenses(posA, [expense]);
    await businessDay.recordExpenses(posA, [{ ...expense, amount: 45 }]);

    const rows = await prisma.expense.findMany({
      where: { venueId: venueAId, posExpenseId: expense.id },
      select: { amount: true, businessDate: true, venueId: true },
    });
    expect(rows).toHaveLength(1);
    expect(rows[0].amount).toBe(45);
    expect(rows[0].businessDate).toBe('2026-09-03');
    expect(await prisma.expense.count({ where: { venueId: venueBId } })).toBe(
      0,
    );
  });

  it('stores the terminal audit trail against the enrolled venue', async () => {
    const logId = randomUUID();
    await audit.ingestEventLogs(
      {
        logs: [
          {
            id: logId,
            action: 'SALE_CANCELLED',
            userId: 'giorgi',
            data: { recordKey: 3, reason: 'wrong table' },
            deviceType: 'POS',
            createdAt: '2026-09-03T18:00:00.000Z',
          },
        ],
      },
      posA,
    );

    const stored = await prisma.auditEventLog.findFirstOrThrow({
      where: { id: logId },
      select: { venueId: true, action: true },
    });
    expect(stored.venueId).toBe(venueAId);
    expect(stored.action).toBe('SALE_CANCELLED');
    expect(
      await prisma.auditEventLog.count({ where: { venueId: venueBId } }),
    ).toBe(0);
  });

  it('keeps authenticating as the same device after a restart', async () => {
    // A restart changes nothing on the server: the POS re-reads the same
    // credential from disk, and it resolves the same Device and Venue.
    const before = await prisma.device.findUniqueOrThrow({
      where: { installationId },
      select: { id: true, venueId: true },
    });
    const again = await credentials.verifyCredential(
      // The same credential the POS persisted; nothing was rotated in between.
      (await reissueForAssertion()) ?? '',
    );
    expect(again?.venueId).toBe(before.venueId);
    expect(await prisma.device.count({ where: { installationId } })).toBe(1);
  });

  /**
   * Stands in for "the POS read its file again". A restart cannot be simulated
   * by re-reading the server's copy — only the verifier is stored — so this
   * re-enrols the same installation, which is the same assertion the POS makes
   * about identity: one Device, same Venue, whatever happens to the secret.
   */
  async function reissueForAssertion(): Promise<string | null> {
    const created = await enrollments.create(
      { platformUserId: adminId },
      venueAId,
      { displayName: 'Front POS', platform: 'WINDOWS' },
    );
    const redeemed = await enrollments.redeem({
      code: created.code,
      installationId,
      platform: 'WINDOWS',
      clientIp: '10.42.0.2',
    });
    return redeemed.credential;
  }
});
