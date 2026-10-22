import type { PrismaService } from '../../prisma.service';
import { MenuService } from './menu.service';

const tenant = { venueId: 'venue-a', organizationId: 'org-a' };

describe('website menu adapters', () => {
  it('includes direct items and subcategory items once in the legacy sections', async () => {
    const direct = {
      id: 'direct',
      nameEn: 'Direct',
      nameKa: 'Direct ka',
      price: 8,
      subcategoryId: null,
      enabled: false,
      websitePresentation: { visibleOnWebsite: false, displayName: 'Override' },
    };
    const nested = {
      id: 'nested',
      nameEn: 'Nested',
      nameKa: 'Nested ka',
      price: 12,
      subcategoryId: 'sub',
    };
    const db = {
      menuCategory: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'category',
            slug: 'food',
            nameEn: 'Food',
            nameKa: 'Food ka',
            items: [direct, nested],
            subcategories: [
              {
                id: 'sub',
                slug: 'specials',
                nameEn: 'Specials',
                nameKa: 'Specials ka',
                items: [nested],
              },
            ],
          },
        ]),
      },
    };
    const [category] = await new MenuService(
      db as unknown as PrismaService,
    ).getAllCategories(tenant);
    expect(category.sections.map((s) => s.items.map((i) => i.id))).toEqual([
      ['direct'],
      ['nested'],
    ]);
    expect(category.itemCount).toBe(2);
    // This bespoke route intentionally keeps raw operational presentation.
    expect(category.items[0]).toMatchObject({
      nameEn: 'Direct',
      imageUrl: null,
    });
    expect(db.menuCategory.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { venueId: tenant.venueId, retiredAt: null },
      }),
    );
  });

  it.each([
    ['pos-item', 'pos-variant', 'pos-item', 'pos-variant'],
    [null, null, 'cloud-item', 'cloud-variant'],
  ])(
    'resolves accepted booking identities without reapplying retirement: %s/%s',
    async (posItem, posVariant, expectedItem, expectedVariant) => {
      const db = {
        menuItem: {
          findFirst: jest
            .fn()
            .mockResolvedValue({ id: 'cloud-item', posMenuItemId: posItem }),
        },
        menuItemVariant: {
          findFirst: jest
            .fn()
            .mockResolvedValue({
              id: 'cloud-variant',
              posMenuVariantId: posVariant,
            }),
        },
      };
      const menu = new MenuService(db as unknown as PrismaService);
      expect(await menu.getPosItemIdByCloudId(tenant, 'cloud-item')).toBe(
        expectedItem,
      );
      expect(
        await menu.getPosVariantIdByCloudId(
          tenant,
          'cloud-item',
          'cloud-variant',
        ),
      ).toBe(expectedVariant);
      expect(db.menuItem.findFirst).toHaveBeenCalledWith({
        where: { id: 'cloud-item', venueId: 'venue-a' },
        select: { id: true, posMenuItemId: true },
      });
      expect(db.menuItemVariant.findFirst).toHaveBeenCalledWith({
        where: {
          id: 'cloud-variant',
          menuItemId: 'cloud-item',
          menuItem: { venueId: 'venue-a' },
        },
        select: { id: true, posMenuVariantId: true },
      });
    },
  );
});
