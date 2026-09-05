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
  const HOT = 'menu-category-hot-0001';
  const SOUPS = 'menu-subcategory-soups-0001';

  /** One category holding one item, in the shape the POS snapshot sends. */
  function menu(
    item: {
      id?: string;
      nameEn: string;
      nameKa?: string;
      price?: number;
      variants?: Array<{ id?: string; size: number; price: number }>;
    },
    opts: {
      categorySlug?: string;
      categoryNameEn?: string;
      subcategorySlug?: string;
    } = {},
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
      id: HOT,
      slug: opts.categorySlug ?? 'hot',
      nameEn: opts.categoryNameEn ?? 'Hot',
      nameKa: 'ცხელი',
      sendToKitchen: true,
      items: opts.subcategorySlug ? [] : [line],
      subcategories: opts.subcategorySlug
        ? [
            {
              id: SOUPS,
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

  const categoriesOf = (venueId: string) =>
    prisma.menuCategory.findMany({
      where: { venueId },
      orderBy: { slug: 'asc' },
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

  it('updates the same category row through a name and slug rename', async () => {
    await service.sync(
      tenantA,
      menu(
        { id: KHINKALI, nameEn: 'Khinkali' },
        { categorySlug: 'georgian-food', categoryNameEn: 'Georgian food' },
      ),
      1,
    );
    const before = await categoriesOf(venueAId);

    await service.sync(
      tenantA,
      menu(
        { id: KHINKALI, nameEn: 'Khinkali' },
        {
          categorySlug: 'georgian-cuisine',
          categoryNameEn: 'Georgian cuisine',
        },
      ),
      1,
    );

    const after = await categoriesOf(venueAId);
    expect(before).toHaveLength(1);
    expect(after).toHaveLength(1);
    expect(after[0].id).toBe(before[0].id);
    expect(after[0].posMenuCategoryId).toBe(HOT);
    expect(after[0].slug).toBe('georgian-cuisine');
    expect(after[0].nameEn).toBe('Georgian cuisine');
  });

  it('updates a variant without changing its Cloud row or POS identity', async () => {
    await service.sync(
      tenantA,
      menu({
        id: KHINKALI,
        nameEn: 'Khinkali',
        variants: [{ id: 'variant-large', size: 10, price: 20 }],
      }),
      1,
    );
    const item = (await itemsOf(venueAId))[0];
    const before = await prisma.menuItemVariant.findMany({
      where: { menuItemId: item.id },
    });

    await service.sync(
      tenantA,
      menu({
        id: KHINKALI,
        nameEn: 'Khinkali',
        variants: [{ id: 'variant-large', size: 12, price: 24 }],
      }),
      1,
    );

    const after = await prisma.menuItemVariant.findMany({
      where: { menuItemId: item.id },
    });
    expect(before).toHaveLength(1);
    expect(after).toHaveLength(1);
    expect(after[0].id).toBe(before[0].id);
    expect(after[0].posMenuVariantId).toBe('variant-large');
    expect(after[0].size).toBe(12);
    expect(after[0].price).toBe(24);
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
    const snapshot = menu({
      id: KHINKALI,
      nameEn: 'Khinkali',
      variants: [{ id: 'variant-10', size: 10, price: 20 }],
    });
    await service.sync(tenantA, snapshot, 1);
    const categoryBefore = (await categoriesOf(venueAId))[0];
    const itemBefore = (await itemsOf(venueAId))[0];
    const variantBefore = await prisma.menuItemVariant.findFirstOrThrow({
      where: { menuItemId: itemBefore.id },
    });

    await service.sync(tenantA, snapshot, 1);

    const categories = await categoriesOf(venueAId);
    const items = await itemsOf(venueAId);
    const variants = await prisma.menuItemVariant.findMany({
      where: { menuItemId: itemBefore.id },
    });
    expect(categories).toHaveLength(1);
    expect(items).toHaveLength(1);
    expect(variants).toHaveLength(1);
    expect(categories[0].id).toBe(categoryBefore.id);
    expect(categories[0].updatedAt).toEqual(categoryBefore.updatedAt);
    expect(items[0].id).toBe(itemBefore.id);
    expect(items[0].updatedAt).toEqual(itemBefore.updatedAt);
    expect(variants[0]).toEqual(variantBefore);
  });

  it('does not steal a row that belongs to a different product', async () => {
    // Two items sharing a name under the same parent is degenerate, but the
    // adoption rule must not merge them: only an unclaimed row is adoptable.
    await service.sync(
      tenantA,
      menu({ id: 'menu-item-a', nameEn: 'Khinkali' }),
    );
    await service.sync(
      tenantA,
      menu({ id: 'menu-item-b', nameEn: 'Khinkali' }),
    );

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

  it('reconciles deleted variants, items and categories from an authoritative snapshot', async () => {
    await service.sync(
      tenantA,
      menu({
        id: KHINKALI,
        nameEn: 'Khinkali',
        variants: [
          { id: 'variant-10', size: 10, price: 20 },
          { id: 'variant-20', size: 20, price: 35 },
        ],
      }),
      1,
    );

    const item = (await itemsOf(venueAId))[0];
    expect(
      await prisma.menuItemVariant.count({ where: { menuItemId: item.id } }),
    ).toBe(2);

    await service.sync(
      tenantA,
      menu({
        id: KHINKALI,
        nameEn: 'Khinkali',
        variants: [{ id: 'variant-20', size: 20, price: 35 }],
      }),
      1,
    );
    expect(
      await prisma.menuItemVariant.findMany({
        where: { menuItemId: item.id },
        select: { posMenuVariantId: true },
      }),
    ).toEqual([{ posMenuVariantId: 'variant-20' }]);

    const emptyCategory = menu({ id: KHINKALI, nameEn: 'Khinkali' });
    emptyCategory[0].items = [];
    await service.sync(tenantA, emptyCategory, 1);
    expect(await itemsOf(venueAId)).toHaveLength(0);
    expect(
      await prisma.menuCategory.count({ where: { venueId: venueAId } }),
    ).toBe(1);

    await service.sync(tenantA, [], 1);
    expect(
      await prisma.menuCategory.count({ where: { venueId: venueAId } }),
    ).toBe(0);
  });

  it('authoritative cleanup deletes only this Venue POS rows and keeps legacy content', async () => {
    await service.sync(
      tenantA,
      menu({
        id: KHINKALI,
        nameEn: 'Khinkali A',
        variants: [{ id: 'variant-a', size: 10, price: 20 }],
      }),
      1,
    );
    await service.sync(
      tenantB,
      menu({ id: KHINKALI, nameEn: 'Khinkali B' }),
      1,
    );
    await prisma.menuCategory.create({
      data: {
        venueId: venueAId,
        slug: 'website-specials',
        nameKa: 'სპეციალური',
        nameEn: 'Website specials',
        items: {
          create: {
            venueId: venueAId,
            nameKa: 'Custom cake',
            nameEn: 'Custom cake',
            price: 50,
          },
        },
      },
    });

    await service.sync(tenantA, [], 1);

    const venueAItems = await itemsOf(venueAId);
    const venueACategories = await categoriesOf(venueAId);
    const venueBItems = await itemsOf(venueBId);
    const venueBCategories = await categoriesOf(venueBId);
    expect(venueAItems).toHaveLength(1);
    expect(venueAItems[0].posMenuItemId).toBeNull();
    expect(venueAItems[0].nameEn).toBe('Custom cake');
    expect(venueACategories).toHaveLength(1);
    expect(venueACategories[0].posMenuCategoryId).toBeNull();
    expect(venueBItems).toHaveLength(1);
    expect(venueBItems[0].posMenuItemId).toBe(KHINKALI);
    expect(venueBCategories).toHaveLength(1);
    expect(venueBCategories[0].posMenuCategoryId).toBe(HOT);
  });
});
