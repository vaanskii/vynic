import { PrismaService } from '../prisma.service';
import type { ManagerAuthContext } from '../auth/manager-auth-context';
import { InventoryService } from './inventory.service';
import { RecipeService } from './recipe.service';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

describeDatabase('Inventory tenancy and constraints (PostgreSQL)', () => {
  let prisma: PrismaService;
  let service: InventoryService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `c0000000-0000-4000-8000-${suffix}`;
  const venueAId = `c1000000-0000-4000-8000-${suffix}`;
  const venueBId = `c2000000-0000-4000-8000-${suffix}`;
  const venueIds = [venueAId, venueBId];
  const actor = (venueId: string, staffId: string): ManagerAuthContext => ({
    venueId,
    organizationId,
    staffId,
    username: staffId,
    role: 'MANAGER',
  });

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    service = new InventoryService(prisma, new RecipeService(prisma));
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Inventory fixture',
        venues: {
          create: venueIds.map((id, index) => ({
            id,
            name: `Inventory Venue ${index}`,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
          })),
        },
      },
    });
  });

  afterAll(async () => {
    await prisma.auditEventLog.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.stockItem.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.supplier.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  it('enforces Venue-scoped SKU uniqueness and isolates both domains', async () => {
    const a = actor(venueAId, 'staff-a');
    const b = actor(venueBId, 'staff-b');
    const stockA = await service.createStockItem(a, {
      name: 'Lemonade bottle',
      sku: 'LEM-05',
      baseUnit: 'piece',
    });
    await service.createStockItem(b, {
      name: 'Lemonade bottle',
      sku: 'LEM-05',
      baseUnit: 'piece',
    });
    const supplierB = await service.createSupplier(b, { name: 'Bottler' });

    await expect(service.listStockItems(a)).resolves.toHaveLength(1);
    await expect(service.listSuppliers(a)).resolves.toHaveLength(0);
    await expect(
      service.updateStockItem(b, stockA.id, { name: 'Cross tenant' }),
    ).rejects.toThrow('Stock item not found');
    await expect(
      service.updateSupplier(a, supplierB.id, { name: 'Cross tenant' }),
    ).rejects.toThrow('Supplier not found');
    await expect(
      service.createStockItem(a, {
        name: 'Duplicate',
        sku: 'lem-05',
        baseUnit: 'piece',
      }),
    ).rejects.toThrow('SKU already exists in this Venue');
  });
});
