import type { TenantContext } from '../../../auth/pos-auth-context';
import { MenuSyncService } from './menu-sync.service';

const tenant: TenantContext = {
  organizationId: 'organization-a',
  venueId: 'venue-a',
};

function makeDatabase() {
  const db = {
    menuCategory: {
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    menuSubcategory: {
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    menuItem: {
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    menuItemVariant: {
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
  };
  const prisma = {
    $transaction: jest.fn(
      (callback: (transaction: typeof db) => Promise<void>) => callback(db),
    ),
  };
  return {
    db,
    service: new MenuSyncService(
      prisma as unknown as ConstructorParameters<typeof MenuSyncService>[0],
    ),
  };
}

describe('MenuSyncService stable identity reconciliation', () => {
  it('updates the same category, subcategory, item and variant by POS identity', async () => {
    const { db, service } = makeDatabase();
    db.menuCategory.findFirst.mockResolvedValue({ id: 'cloud-category' });
    db.menuCategory.update.mockResolvedValue({ id: 'cloud-category' });
    db.menuSubcategory.findFirst.mockResolvedValue({ id: 'cloud-subcategory' });
    db.menuSubcategory.update.mockResolvedValue({ id: 'cloud-subcategory' });
    db.menuItem.findFirst.mockResolvedValue({ id: 'cloud-item' });
    db.menuItem.update.mockResolvedValue({ id: 'cloud-item' });
    db.menuItemVariant.findFirst.mockResolvedValue({ id: 'cloud-variant' });
    db.menuItemVariant.update.mockResolvedValue({ id: 'cloud-variant' });

    await service.sync(
      tenant,
      [
        {
          id: 'pos-category',
          slug: 'renamed-category',
          nameKa: 'კატეგორია',
          nameEn: 'Renamed category',
          subcategories: [
            {
              id: 'pos-subcategory',
              slug: 'renamed-subcategory',
              nameKa: 'ქვეკატეგორია',
              nameEn: 'Renamed subcategory',
              items: [
                {
                  id: 'pos-item',
                  nameKa: 'პროდუქტი',
                  nameEn: 'Renamed item',
                  price: 4,
                  variants: [{ id: 'pos-variant', size: 2, price: 7 }],
                },
              ],
            },
          ],
        },
      ],
      1,
    );

    expect(db.menuCategory.create).not.toHaveBeenCalled();
    expect(db.menuCategory.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'cloud-category' },
        data: expect.objectContaining({
          posMenuCategoryId: 'pos-category',
          slug: 'renamed-category',
        }),
      }),
    );
    expect(db.menuSubcategory.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'cloud-subcategory' } }),
    );
    expect(db.menuItem.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'cloud-item' } }),
    );
    expect(db.menuItemVariant.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'cloud-variant' },
        data: expect.objectContaining({ posMenuVariantId: 'pos-variant' }),
      }),
    );
  });

  it('adopts only an unclaimed legacy row when identity first arrives', async () => {
    const { db, service } = makeDatabase();
    db.menuCategory.findFirst
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ id: 'legacy-category' });
    db.menuCategory.update.mockResolvedValue({ id: 'legacy-category' });

    await service.sync(tenant, [
      {
        id: 'pos-category',
        slug: 'food',
        nameKa: 'საჭმელი',
        nameEn: 'Food',
      },
    ]);

    expect(db.menuCategory.findFirst).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: expect.objectContaining({
          venueId: 'venue-a',
          slug: 'food',
          posMenuCategoryId: null,
        }),
      }),
    );
    expect(db.menuCategory.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'legacy-category' },
        data: expect.objectContaining({ posMenuCategoryId: 'pos-category' }),
      }),
    );
  });

  it('reconciles only Venue-scoped POS-owned rows in child-first order', async () => {
    const { db, service } = makeDatabase();

    await service.sync(tenant, [], 1);

    const itemOrder = db.menuItem.deleteMany.mock.invocationCallOrder[0];
    const subcategoryOrder =
      db.menuSubcategory.deleteMany.mock.invocationCallOrder[0];
    const categoryOrder =
      db.menuCategory.deleteMany.mock.invocationCallOrder[0];
    expect(itemOrder).toBeLessThan(subcategoryOrder);
    expect(subcategoryOrder).toBeLessThan(categoryOrder);

    expect(db.menuItem.deleteMany).toHaveBeenCalledWith({
      where: {
        venueId: 'venue-a',
        posMenuItemId: { not: null },
      },
    });
    expect(db.menuSubcategory.deleteMany).toHaveBeenCalledWith({
      where: {
        category: { venueId: 'venue-a' },
        posMenuSubcategoryId: { not: null },
        items: { none: { posMenuItemId: null } },
      },
    });
    expect(db.menuCategory.deleteMany).toHaveBeenCalledWith({
      where: {
        venueId: 'venue-a',
        posMenuCategoryId: { not: null },
        items: { none: { posMenuItemId: null } },
        subcategories: {
          none: {
            OR: [
              { posMenuSubcategoryId: null },
              { items: { some: { posMenuItemId: null } } },
            ],
          },
        },
      },
    });
  });

  it('does not delete anything for a legacy snapshot without identityVersion', async () => {
    const { db, service } = makeDatabase();

    await service.sync(tenant, []);

    expect(db.menuItemVariant.deleteMany).not.toHaveBeenCalled();
    expect(db.menuItem.deleteMany).not.toHaveBeenCalled();
    expect(db.menuSubcategory.deleteMany).not.toHaveBeenCalled();
    expect(db.menuCategory.deleteMany).not.toHaveBeenCalled();
  });

  it('makes a repeated identical snapshot a persistence no-op', async () => {
    const { db, service } = makeDatabase();
    db.menuCategory.findFirst.mockResolvedValue({
      id: 'cloud-category',
      posMenuCategoryId: 'pos-category',
      slug: 'drinks',
      nameKa: 'სასმელები',
      nameEn: 'Drinks',
      sendToKitchen: false,
      sortOrder: 0,
    });
    db.menuItem.findFirst.mockResolvedValue({
      id: 'cloud-item',
      categoryId: 'cloud-category',
      subcategoryId: null,
      posMenuItemId: 'pos-item',
      nameKa: 'წყალი',
      nameEn: 'Water',
      price: 2,
      sendToKitchen: false,
      sortOrder: 0,
    });
    db.menuItemVariant.findFirst.mockResolvedValue({
      id: 'cloud-variant',
      posMenuVariantId: 'pos-variant',
      size: 0.5,
      price: 2,
    });

    await service.sync(
      tenant,
      [
        {
          id: 'pos-category',
          slug: 'drinks',
          nameKa: 'სასმელები',
          nameEn: 'Drinks',
          sendToKitchen: false,
          items: [
            {
              id: 'pos-item',
              nameKa: 'წყალი',
              nameEn: 'Water',
              price: 2,
              sendToKitchen: false,
              variants: [{ id: 'pos-variant', size: 0.5, price: 2 }],
            },
          ],
        },
      ],
      1,
    );

    expect(db.menuCategory.update).not.toHaveBeenCalled();
    expect(db.menuSubcategory.update).not.toHaveBeenCalled();
    expect(db.menuItem.update).not.toHaveBeenCalled();
    expect(db.menuItemVariant.update).not.toHaveBeenCalled();
    expect(db.menuCategory.create).not.toHaveBeenCalled();
    expect(db.menuItem.create).not.toHaveBeenCalled();
    expect(db.menuItemVariant.create).not.toHaveBeenCalled();
  });
});
