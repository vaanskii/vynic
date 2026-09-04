import { PrismaService } from '../../../prisma.service';
import { MenuSyncService } from './menu-sync.service';
import type { TenantContext } from '../../../auth/pos-auth-context';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

/**
 * Menu identity through the mirror, against real PostgreSQL.
 *
 * The property under test is the one a mocked Prisma cannot show: that turning
 * identity on does not multiply a restaurant's menu. An already-mirrored
 * Vankisi menu has rows with no `posMenuItemId`; the first snapshot from a POS
 * that sends one must adopt those rows in place, and every snapshot after it
 * must keep updating the same rows through renames and moves — never leaving a
 * retired duplicate behind for the manager app and the website to show.
 */
describeDatabase('Menu identity in the Cloud mirror (PostgreSQL)', () => {
  let prisma: PrismaService;
  let service: MenuSyncService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `b0000000-0000-4000-8000-${suffix}`;
  const venueAId = `b1000000-0000-4000-8000-${suffix}`;
  const venueBId = `b2000000-0000-4000-8000-${suffix}`;
  const venueIds = [venueAId, venueBId];

  const tenantA: TenantContext = { venueId: venueAId, organizationId };
  const tenantB: TenantContext = { venueId: venueBId, organizationId };

  const KHINKALI = 'menu-item-khinkali-0001';

  /** One category holding one item, in the shape the POS snapshot sends. */
  function menu(
    item: {
      id?: string;
      nameEn: string;
      nameKa?: string;
      price?: number;
      variants?: Array<{ size: number; price: number }>;
    },
    opts: { categorySlug?: string; subcategorySlug?: string } = {},
  ) {
    const line = {
      ...(item.id ? { id: item.id } : {}),
      nameEn: item.nameEn,
      nameKa: item.nameKa ?? item.nameEn,
      price: item.price ?? 2,
      sendToKitchen: true,
      variants: item.variants ?? [],
    };
    const category = {
      slug: opts.categorySlug ?? 'hot',
      nameEn: 'Hot',
      nameKa: 'ცხელი',
      sendToKitchen: true,
      items: opts.subcategorySlug ? [] : [line],
      subcategories: opts.subcategorySlug
        ? [
            {
              slug: opts.subcategorySlug,
              nameEn: 'Soups',
              nameKa: 'სუპები',
              items: [line],
            },
          ]
        : [],
    };
    return [category];
  }

  const itemsOf = (venueId: string) =>
    prisma.menuItem.findMany({
      where: { venueId },
      orderBy: { nameEn: 'asc' },
    });

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    service = new MenuSyncService(prisma);

    const venue = (id: string, name: string) => ({
      id,
      name,
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
    });
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Menu identity fixture',
        venues: {
          create: [venue(venueAId, 'Venue A'), venue(venueBId, 'Venue B')],
        },
      },
    });
  });

  afterAll(async () => {
    await prisma.menuItem.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.menuCategory.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  afterEach(async () => {
    await prisma.menuItem.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.menuCategory.deleteMany({
      where: { venueId: { in: venueIds } },
    });
  });

  it('stores the POS identity a new item arrives with', async () => {
    await service.sync(tenantA, menu({ id: KHINKALI, nameEn: 'Khinkali' }));

    const items = await itemsOf(venueAId);
    expect(items).toHaveLength(1);
    expect(items[0].posMenuItemId).toBe(KHINKALI);
    // The Cloud row key is untouched: the website already publishes it.
    expect(items[0].id).not.toBe(KHINKALI);
  });

  it('adopts an already-mirrored row instead of duplicating it', async () => {
    // The menu as it stands today: mirrored by name, no POS identity.
    await service.sync(tenantA, menu({ nameEn: 'Khinkali', price: 2 }));
    const before = await itemsOf(venueAId);
    expect(before).toHaveLength(1);
    expect(before[0].posMenuItemId).toBeNull();

    // The first snapshot from a POS that has been through the rollout.
    await service.sync(
      tenantA,
      menu({ id: KHINKALI, nameEn: 'Khinkali', price: 2 }),
    );

    const after = await itemsOf(venueAId);
    expect(after).toHaveLength(1);
    expect(after[0].id).toBe(before[0].id);
    expect(after[0].posMenuItemId).toBe(KHINKALI);
  });

  it('follows a rename instead of creating a second product', async () => {
    await service.sync(tenantA, menu({ id: KHINKALI, nameEn: 'Khinkali' }));
    const before = await itemsOf(venueAId);

    await service.sync(
      tenantA,
      menu({ id: KHINKALI, nameEn: 'Royal Khinkali', price: 3 }),
    );

    const after = await itemsOf(venueAId);
    expect(after).toHaveLength(1);
    expect(after[0].id).toBe(before[0].id);
    expect(after[0].nameEn).toBe('Royal Khinkali');
    expect(after[0].price).toBe(3);
  });

  it('follows a move between categories', async () => {
    await service.sync(tenantA, menu({ id: KHINKALI, nameEn: 'Khinkali' }));
    const before = await itemsOf(venueAId);
    expect(before[0].subcategoryId).toBeNull();

    await service.sync(
      tenantA,
      menu(
        { id: KHINKALI, nameEn: 'Khinkali' },
        { subcategorySlug: 'dumplings' },
      ),
    );

    const after = await itemsOf(venueAId);
    expect(after).toHaveLength(1);
    expect(after[0].id).toBe(before[0].id);
    expect(after[0].subcategoryId).not.toBeNull();
  });

  it('is idempotent across repeated snapshots', async () => {
    for (let i = 0; i < 3; i++) {
      await service.sync(tenantA, menu({ id: KHINKALI, nameEn: 'Khinkali' }));
    }

    const items = await itemsOf(venueAId);
    expect(items).toHaveLength(1);
  });

  it('does not steal a row that belongs to a different product', async () => {
    // Two items sharing a name under the same parent is degenerate, but the
    // adoption rule must not merge them: only an unclaimed row is adoptable.
    await service.sync(tenantA, menu({ id: 'menu-item-a', nameEn: 'Khinkali' }));
    await service.sync(tenantA, menu({ id: 'menu-item-b', nameEn: 'Khinkali' }));

    const items = await itemsOf(venueAId);
    expect(items).toHaveLength(2);
    expect(items.map((it) => it.posMenuItemId).sort()).toEqual([
      'menu-item-a',
      'menu-item-b',
    ]);
  });

  it('keeps identity Venue-scoped', async () => {
    await service.sync(tenantA, menu({ id: KHINKALI, nameEn: 'Khinkali' }));
    await service.sync(
      tenantB,
      menu({ id: KHINKALI, nameEn: 'Khinkali B', price: 9 }),
    );

    const a = await itemsOf(venueAId);
    const b = await itemsOf(venueBId);
    expect(a).toHaveLength(1);
    expect(b).toHaveLength(1);
    // The same POS id in two restaurants is two different products, and each
    // Venue's sync reached only its own row.
    expect(a[0].id).not.toBe(b[0].id);
    expect(a[0].nameEn).toBe('Khinkali');
    expect(b[0].nameEn).toBe('Khinkali B');
  });

  it('still mirrors a snapshot from a POS that sends no identity', async () => {
    await service.sync(tenantA, menu({ nameEn: 'Khinkali', price: 2 }));
    await service.sync(tenantA, menu({ nameEn: 'Khinkali', price: 4 }));

    const items = await itemsOf(venueAId);
    expect(items).toHaveLength(1);
    expect(items[0].posMenuItemId).toBeNull();
    expect(items[0].price).toBe(4);
  });
});
