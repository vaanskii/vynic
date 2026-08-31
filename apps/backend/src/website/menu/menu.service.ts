import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../shared/prisma/prisma.service';
import type { TenantContext } from '../../tenancy/tenant-context';

type MenuItemRow = {
  id: string;
  nameKa: string;
  nameEn: string;
  price: number;
  subcategoryId?: string | null;
  sortOrder?: number;
  variants?: Array<{ id: string; size: number; price: number }>;
};

type MenuSubcategoryRow = {
  id: string;
  slug: string;
  nameKa: string;
  nameEn: string;
  sortOrder?: number;
  items: MenuItemRow[];
};

type MenuCategoryRow = {
  id: string;
  slug: string;
  nameKa: string;
  nameEn: string;
  sortOrder?: number;
  items: MenuItemRow[];
  subcategories: MenuSubcategoryRow[];
};

type SubcategoryContext = {
  id: string;
  slug: string;
  nameEn: string;
  nameKa: string;
};

@Injectable()
export class MenuService {
  constructor(private readonly prisma: PrismaService) {}

  /** Full menu tree — categories in POS order, for the resolved Venue only. */
  async getAllCategories(tenant: TenantContext) {
    const categories = await this.prisma.menuCategory.findMany({
      where: { venueId: tenant.venueId },
      include: this.menuInclude(),
      orderBy: { sortOrder: 'asc' },
    });

    return categories.map((category) => this.toWebsiteCategory(category));
  }

  /** Single category — use when user picks e.g. "beer" / "ლუდი". */
  async getCategoryBySlug(tenant: TenantContext, slug: string) {
    const category = await this.prisma.menuCategory.findUnique({
      where: {
        venueId_slug: { venueId: tenant.venueId, slug },
      },
      include: this.menuInclude(),
    });

    if (!category) {
      throw new NotFoundException(`Menu category "${slug}" not found`);
    }

    return this.toWebsiteCategory(category);
  }

  async getMenuItemById(tenant: TenantContext, itemId: string) {
    const item = await this.prisma.menuItem.findFirst({
      where: { id: itemId, venueId: tenant.venueId },
      include: { variants: true, category: true, subcategory: true },
    });
    if (!item) return null;

    const sub = item.subcategory
      ? {
          id: item.subcategory.id,
          slug: item.subcategory.slug,
          nameEn: item.subcategory.nameEn,
          nameKa: item.subcategory.nameKa,
        }
      : undefined;

    return this.toWebsiteMenuItem(item, sub);
  }

  private menuInclude() {
    return {
      items: {
        include: { variants: true },
        orderBy: { sortOrder: 'asc' as const },
      },
      subcategories: {
        include: {
          items: {
            include: { variants: true },
            orderBy: { sortOrder: 'asc' as const },
          },
        },
        orderBy: { sortOrder: 'asc' as const },
      },
    };
  }

  private toWebsiteCategory(category: MenuCategoryRow) {
    const directItems = category.items
      .filter((item) => !item.subcategoryId)
      .map((item) => this.toWebsiteMenuItem(item));

    const subcategories = category.subcategories.map((sub) => {
      const subCtx: SubcategoryContext = {
        id: sub.id,
        slug: sub.slug,
        nameEn: sub.nameEn,
        nameKa: sub.nameKa,
      };

      return {
        id: sub.id,
        slug: sub.slug,
        sortOrder: sub.sortOrder ?? 0,
        nameEn: sub.nameEn,
        nameKa: sub.nameKa,
        translations: [
          { language: 'en', name: sub.nameEn },
          { language: 'ka', name: sub.nameKa },
        ],
        items: sub.items.map((item) => this.toWebsiteMenuItem(item, subCtx)),
      };
    });

    const hasSubcategories = subcategories.length > 0;

    // Unified sections for the frontend: always iterate `sections`, never guess from empty `items`.
    const sections = hasSubcategories
      ? subcategories.map((sub) => ({
          type: 'subcategory' as const,
          id: sub.id,
          slug: sub.slug,
          sortOrder: sub.sortOrder,
          nameEn: sub.nameEn,
          nameKa: sub.nameKa,
          translations: sub.translations,
          items: sub.items,
        }))
      : [
          {
            type: 'items' as const,
            id: null as string | null,
            slug: null as string | null,
            sortOrder: 0,
            nameEn: null as string | null,
            nameKa: null as string | null,
            translations: [] as Array<{ language: string; name: string }>,
            items: directItems,
          },
        ];

    const totalItemCount = hasSubcategories
      ? subcategories.reduce((sum, sub) => sum + sub.items.length, 0)
      : directItems.length;

    return {
      id: category.id,
      slug: category.slug,
      sortOrder: category.sortOrder ?? 0,
      nameEn: category.nameEn,
      nameKa: category.nameKa,
      translations: [
        { language: 'en', name: category.nameEn },
        { language: 'ka', name: category.nameKa },
      ],
      /** true when user must pick a subcategory tab (beer, vodka, wine, …) */
      hasSubcategories,
      /** `flat` = show category.items; `grouped` = show category.sections (subcategory tabs) */
      displayMode: hasSubcategories ? ('grouped' as const) : ('flat' as const),
      /** Direct items only — empty when hasSubcategories (use sections instead) */
      items: directItems,
      subcategories,
      /** Preferred for UI: list of item groups to render */
      sections,
      itemCount: totalItemCount,
    };
  }

  private toWebsiteMenuItem(
    item: MenuItemRow,
    subcategory?: SubcategoryContext,
  ) {
    const variants = item.variants ?? [];
    const basePrice =
      variants.length > 0
        ? Math.min(...variants.map((v) => v.price))
        : item.price;

    return {
      id: item.id,
      sortOrder: item.sortOrder ?? 0,
      price: basePrice,
      imageUrl: null as string | null,
      nameEn: item.nameEn,
      nameKa: item.nameKa,
      translations: [
        { language: 'en', name: item.nameEn },
        { language: 'ka', name: item.nameKa },
      ],
      subcategoryId: subcategory?.id ?? null,
      subcategorySlug: subcategory?.slug ?? null,
      subcategoryNameEn: subcategory?.nameEn ?? null,
      subcategoryNameKa: subcategory?.nameKa ?? null,
      hasVariants: variants.length > 0,
      variants: variants.map((v) => ({
        id: v.id,
        size: v.size,
        price: v.price,
      })),
    };
  }
}
