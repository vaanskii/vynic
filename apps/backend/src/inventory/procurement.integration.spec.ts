jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
jest.mock('../pos/pos-command-dispatcher.service', () => ({
  PosCommandDispatcher: class {},
}));
jest.mock('../mobile/services/mobile-mutation-support.service', () => ({
  MobileMutationSupport: class {},
}));
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { InventoryService } from './inventory.service';
import { ReceivingService } from './receiving.service';
import { RecipeService } from './recipe.service';
import { procurementSummary } from './procurement-summary';
import { MobileDashboardService } from '../mobile/services/mobile-dashboard.service';
import type { InventoryActor } from './inventory-audit';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)(
  'Step 4.6 procurement consolidation (disposable PostgreSQL)',
  () => {
    const org = randomUUID(),
      venueId = randomUUID(),
      other = randomUUID();
    const actor: InventoryActor = {
      venueId,
      organizationId: org,
      staffId: 'manager',
      username: 'Manager',
    };
    let db: PrismaService,
      inventory: InventoryService,
      receiving: ReceivingService;
    beforeAll(async () => {
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      await db.organization.create({
        data: {
          id: org,
          name: 'Step46',
          venues: {
            create: [venueId, other].map((id) => ({
              id,
              name: 'Test',
              timezone: 'Asia/Tbilisi',
              currency: 'GEL',
            })),
          },
        },
      });
      inventory = new InventoryService(db, new RecipeService(db));
      receiving = new ReceivingService(db);
      await db.setting.create({
        data: { venueId, key: 'currentBusinessDate', value: '2026-09-05' },
      });
    });
    afterAll(async () => {
      const venues = { in: [venueId, other] };
      await db.stockMovement.deleteMany({ where: { venueId: venues } });
      await db.receiving.deleteMany({ where: { venueId: venues } });
      await db.stockItem.deleteMany({ where: { venueId: venues } });
      await db.supplier.deleteMany({ where: { venueId: venues } });
      await db.expense.deleteMany({ where: { venueId: venues } });
      await db.auditEventLog.deleteMany({ where: { venueId: venues } });
      await db.setting.deleteMany({ where: { venueId: venues } });
      await db.venue.deleteMany({ where: { id: venues } });
      await db.organization.delete({ where: { id: org } });
      await db.$disconnect();
    });
    it('counts POSTED purchases once, independently of invoice date, drafts, cancellation and other Venues', async () => {
      const supplier = await inventory.createSupplier(actor, {
        name: 'Supplier',
      });
      const item = await inventory.createStockItem(actor, {
        name: 'Flour',
        baseUnit: 'kg',
      });
      async function draft(amount: string, day = '2026-09-05') {
        return receiving.createDraft(actor, {
          supplierId: supplier.id,
          documentDate: '2026-08-01',
          businessDate: day,
          lines: [
            {
              stockItemId: item.id,
              enteredQuantity: '1',
              enteredUnit: 'kg',
              unitPurchaseCost: amount,
            },
          ],
        });
      }
      const posted = await draft('500');
      await receiving.post(actor, posted.id);
      await draft('900');
      const cancelled = await draft('300');
      await receiving.post(actor, cancelled.id);
      await receiving.cancel(actor, cancelled.id, 'Returned');
      const today = await draft('25', '2026-09-06');
      await receiving.post(actor, today.id);
      const previous = await draft('100', '2026-08-31');
      await receiving.post(actor, previous.id);
      const summary = await procurementSummary(
        db,
        actor,
        new Date('2026-09-05T22:00:00Z'),
      );
      expect(summary).toMatchObject({
        today: '2026-09-06',
        businessDate: '2026-09-05',
        calendarDay: { total: '25.00', count: 1 },
        businessDay: { total: '500.00', count: 1 },
        calendarMonth: { total: '525.00', count: 2 },
      });
      expect(
        (await procurementSummary(db, { ...actor, venueId: other })).businessDay
          .total,
      ).toBe('0.00');
      expect(await db.expense.count({ where: { venueId } })).toBe(0);
      await db.expense.createMany({
        data: [
          {
            venueId,
            description: 'Taxi',
            category: 'ტრანსპორტი',
            amount: 25,
            paymentType: 'cash',
            createdAt: new Date('2026-09-05T10:00:00Z'),
          },
          {
            venueId,
            description: 'Salary',
            category: 'პერსონალი',
            amount: 75,
            paymentType: 'cash',
            createdAt: new Date('2026-09-05T10:00:00Z'),
          },
          {
            venueId,
            description: 'Obsolete',
            category: 'ბაზარი',
            amount: 999,
            paymentType: 'cash',
            createdAt: new Date('2026-09-05T10:00:00Z'),
          },
        ],
      });
      const service = new MobileDashboardService(
        db,
        {} as any,
        {} as any,
        {} as any,
      );
      const auditBefore = await db.auditEventLog.count({ where: { venueId } });
      const financials = await service.getFinancials(actor);
      expect(financials.procurement.businessDay.total).toBe('500.00');
      expect(financials.otherExpenses).toBe('25.00');
      expect(financials.salaryPayments).toBe('75.00');
      expect(financials.totalOutflows).toBe('600.00');
      expect(financials.expenses).toBe(100);
      expect(financials.expenseEntries).toHaveLength(2);
      expect(await db.auditEventLog.count({ where: { venueId } })).toBe(
        auditBefore,
      );
      for (const category of ['Market', ' ბაზარი ', 'შესყიდვები'])
        await expect(
          service.createExpense(actor, {
            description: 'Goods',
            amount: 500,
            category,
          }),
        ).rejects.toThrow('დღიური მიღება');
      expect(await db.expense.count({ where: { venueId } })).toBe(3);
      const catalogue = await inventory.getCatalog(actor, 5);
      expect(catalogue.inspection?.procurement.businessDay.total).toBe(
        '500.00',
      );
      expect(catalogue.inspection?.receivings).toHaveLength(1);
      expect(catalogue.inspection?.movementsByItem[item.id]).toHaveLength(5);
      const foreign = await inventory.getCatalog(
        { ...actor, venueId: other },
        5,
      );
      expect(foreign.stockItems).toHaveLength(0);
      expect(foreign.inspection?.movementsByItem).toEqual({});
      expect((await inventory.getCatalog(actor, 4)).inspection).toBeUndefined();
      expect(
        (await inventory.listStockItems(actor, undefined, true))[0]
          .lastPurchaseUnitCost,
      ).toBe('25.000000');
    });
  },
);
