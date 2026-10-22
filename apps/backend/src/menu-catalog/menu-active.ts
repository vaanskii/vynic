import { Prisma } from '@prisma/client';

/** Active selection includes the parent chain; history resolvers omit these. */
export const activeCategory = Prisma.validator<Prisma.MenuCategoryWhereInput>()(
  {
    retiredAt: null,
  },
);
export const activeSubcategory =
  Prisma.validator<Prisma.MenuSubcategoryWhereInput>()({
    retiredAt: null,
    category: activeCategory,
  });
export const activeMenuItem = Prisma.validator<Prisma.MenuItemWhereInput>()({
  retiredAt: null,
  AND: [
    { OR: [{ categoryId: null }, { category: activeCategory }] },
    { OR: [{ subcategoryId: null }, { subcategory: activeSubcategory }] },
  ],
});
export const activeVariant =
  Prisma.validator<Prisma.MenuItemVariantWhereInput>()({
    retiredAt: null,
    menuItem: activeMenuItem,
  });
