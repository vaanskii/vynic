jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../auth/pos-auth-context';
import { TableSyncService } from '../pos/sync/snapshot/table-sync.service';
import { OrderSyncService } from '../pos/sync/snapshot/order-sync.service';
import { MenuSyncService } from '../pos/sync/snapshot/menu-sync.service';
import { StaffSyncService } from '../pos/sync/snapshot/staff-sync.service';
import { BusinessDaySyncService } from '../pos/sync/snapshot/business-day-sync.service';
import { IngestAuditReportsService } from '../pos/sync/application/ingest-audit-reports.service';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

describeDatabase('POS operational tenant isolation (PostgreSQL)', () => {
  let prisma: PrismaService;
  const suffix = `${process.pid}`;
  const organizationId = `10000000-0000-4000-8000-${suffix.padStart(12, '0')}`;
  const venueA: TenantContext = {
    venueId: `20000000-0000-4000-8000-${suffix.padStart(12, '0')}`,
    organizationId,
  };
  const venueB: TenantContext = {
    venueId: `30000000-0000-4000-8000-${suffix.padStart(12, '0')}`,
    organizationId,
  };

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Tenant isolation fixture',
        venues: {
          create: [
            {
              id: venueA.venueId,
              name: 'Venue A',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            },
            {
              id: venueB.venueId,
              name: 'Venue B',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            },
          ],
        },
      },
    });
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('allows overlapping local identity and prevents Venue A sync from reading or mutating Venue B', async () => {
    await prisma.table.create({
      data: {
        venueId: venueB.venueId,
        tableNumber: '1',
        floor: 'first',
        isReserved: true,
        activeOrderId: 77,
        currentBill: 99,
      },
    });
    await prisma.order.create({
      data: {
        venueId: venueB.venueId,
        posOrderId: 77,
        status: 'open',
        totalAmount: 99,
        waiterName: 'admin',
        businessDate: '2026-08-30',
      },
    });
    await prisma.staff.create({
      data: {
        venueId: venueB.venueId,
        username: 'admin',
        pinHash: 'venue-b-hash',
      },
    });
    await prisma.menuCategory.create({
      data: {
        venueId: venueB.venueId,
        slug: 'drinks',
        nameKa: 'სასმელები B',
        nameEn: 'Drinks B',
      },
    });
    await prisma.setting.create({
      data: {
        venueId: venueB.venueId,
        key: 'currentBusinessDate',
        value: '2026-08-30',
      },
    });
    await prisma.expense.create({
      data: {
        venueId: venueB.venueId,
        description: 'Venue B expense',
        amount: 5,
        category: 'fixture',
      },
    });
    await prisma.auditReport.create({
      data: {
        venueId: venueB.venueId,
        reportId: 'report-77',
        posOrderId: 77,
        tableNumbers: ['1'],
        openedById: 'admin',
        openedByName: 'Admin B',
        openedAt: new Date('2026-08-30T10:00:00.000Z'),
        status: 'OPEN',
      },
    });
    await prisma.dailySnapshot.create({
      data: { venueId: venueB.venueId, date: '2026-08-30' },
    });

    const tables = new TableSyncService(prisma);
    const orders = new OrderSyncService(prisma);
    const menu = new MenuSyncService(prisma);
    const pinVault = {
      read: jest.fn(() => Promise.resolve({})),
      write: jest.fn(() => Promise.resolve(undefined)),
    } as unknown as ConstructorParameters<typeof StaffSyncService>[1];
    const staff = new StaffSyncService(prisma, pinVault);
    const businessDay = new BusinessDaySyncService(prisma);
    const audit = new IngestAuditReportsService(prisma, {
      broadcastUpdate: jest.fn(),
    } as never);

    await tables.sync(
      venueA,
      [
        {
          tableNumber: '1',
          floor: 'first',
          isReserved: true,
          activeOrderId: 77,
          currentBill: 25,
        },
      ],
      false,
    );
    await orders.sync(
      venueA,
      [
        {
          posOrderId: 77,
          status: 'open',
          totalAmount: 25,
          waiterName: 'admin',
          floor: 'takeaway',
          businessDate: '2026-08-30',
          tableNumbers: [],
          items: [],
        },
      ],
      '2026-08-30',
    );
    await menu.sync(venueA, [
      {
        slug: 'drinks',
        nameKa: 'სასმელები A',
        nameEn: 'Drinks A',
        items: [
          {
            nameKa: 'წყალი',
            nameEn: 'Water',
            price: 2,
            sendToKitchen: false,
          },
        ],
      },
    ]);
    await staff.sync(venueA, [
      { username: 'admin', role: 'MANAGER', pin: '1234' },
    ]);
    await businessDay.recordExpenses(venueA, [
      { description: 'Venue A expense', amount: 3, category: 'fixture' },
    ]);
    await businessDay.trackBusinessDate(venueA, '2026-08-30');
    await businessDay.trackBusinessDate(venueA, '2026-08-31');
    await audit.ingestReports(
      {
        reports: [
          {
            reportId: 'report-77',
            orderId: 77,
            tableNumbers: ['1'],
            openedById: 'admin',
            openedByName: 'Admin A',
            openedAt: '2026-08-30T10:00:00.000Z',
            status: 'OPEN',
          },
        ],
        fullSync: true,
      },
      venueA,
    );
    await prisma.dailySnapshot.create({
      data: { venueId: venueA.venueId, date: '2026-08-30' },
    });

    await expect(
      prisma.table.create({
        data: {
          venueId: venueA.venueId,
          tableNumber: '1',
          floor: 'first',
        },
      }),
    ).rejects.toMatchObject({ code: 'P2002' });

    expect(
      await prisma.table.count({
        where: {
          venueId: { in: [venueA.venueId, venueB.venueId] },
          tableNumber: '1',
          floor: 'first',
        },
      }),
    ).toBe(2);
    expect(
      await prisma.order.count({
        where: {
          venueId: { in: [venueA.venueId, venueB.venueId] },
          posOrderId: 77,
        },
      }),
    ).toBe(2);
    expect(
      await prisma.staff.count({
        where: {
          venueId: { in: [venueA.venueId, venueB.venueId] },
          username: 'admin',
        },
      }),
    ).toBe(2);
    expect(
      await prisma.menuCategory.count({
        where: {
          venueId: { in: [venueA.venueId, venueB.venueId] },
          slug: 'drinks',
        },
      }),
    ).toBe(2);
    expect(
      await prisma.setting.count({
        where: {
          venueId: { in: [venueA.venueId, venueB.venueId] },
          key: 'currentBusinessDate',
        },
      }),
    ).toBe(2);
    expect(
      await prisma.auditReport.count({
        where: {
          venueId: { in: [venueA.venueId, venueB.venueId] },
          reportId: 'report-77',
        },
      }),
    ).toBe(2);
    expect(
      await prisma.dailySnapshot.count({
        where: {
          venueId: { in: [venueA.venueId, venueB.venueId] },
          date: '2026-08-30',
        },
      }),
    ).toBe(2);

    const bTable = await prisma.table.findFirstOrThrow({
      where: { venueId: venueB.venueId, tableNumber: '1', floor: 'first' },
    });
    const bOrder = await prisma.order.findFirstOrThrow({
      where: { venueId: venueB.venueId, posOrderId: 77 },
    });
    const bStaff = await prisma.staff.findFirstOrThrow({
      where: { venueId: venueB.venueId, username: 'admin' },
    });
    expect(bTable).toMatchObject({
      isReserved: true,
      activeOrderId: 77,
      currentBill: 99,
    });
    expect(bOrder).toMatchObject({ status: 'open', totalAmount: 99 });
    expect(bStaff.pinHash).toBe('venue-b-hash');
    expect(
      await prisma.auditReport.findFirstOrThrow({
        where: { venueId: venueB.venueId, reportId: 'report-77' },
      }),
    ).toMatchObject({ openedByName: 'Admin B', status: 'OPEN' });

    expect(
      await prisma.order.findMany({ where: { venueId: venueA.venueId } }),
    ).toHaveLength(1);
    expect(
      await prisma.order.findMany({ where: { venueId: venueB.venueId } }),
    ).toHaveLength(1);
    expect(
      await prisma.expense.count({ where: { venueId: venueA.venueId } }),
    ).toBe(1);
    expect(
      await prisma.expense.count({ where: { venueId: venueB.venueId } }),
    ).toBe(1);
  });
});
