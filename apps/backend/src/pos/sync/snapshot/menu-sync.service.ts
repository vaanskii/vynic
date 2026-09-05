import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../../prisma.service';
import type { TenantContext } from '../../../auth/pos-auth-context';
import type {
  MenuCategorySync,
  MenuItemSync,
  MenuSubcategorySync,
  MenuVariantSync,
} from '../sync-payload';

type Parent = { categoryId: string | null; subcategoryId: string | null };

/** Mirrors one complete, POS-authoritative menu snapshot. */
@Injectable()
export class MenuSyncService {
  constructor(private readonly prisma: PrismaService) {}

  private stableId(raw: unknown): string | null {
    const value = typeof raw === 'string' ? raw.trim() : '';
    return value.length > 0 ? value : null;
  }

  private async upsertCategory(
    db: Prisma.TransactionClient,
    tenant: TenantContext,
    category: MenuCategorySync,
    sortOrder: number,
  ) {
    const posMenuCategoryId = this.stableId(category.id);
    let existing = posMenuCategoryId
      ? await db.menuCategory.findFirst({
          where: { venueId: tenant.venueId, posMenuCategoryId },
          select: {
            id: true,
            posMenuCategoryId: true,
            slug: true,
            nameKa: true,
            nameEn: true,
            sendToKitchen: true,
            sortOrder: true,
          },
        })
      : null;
    existing ??= await db.menuCategory.findFirst({
      where: {
        venueId: tenant.venueId,
        slug: category.slug,
        ...(posMenuCategoryId ? { posMenuCategoryId: null } : {}),
      },
      select: {
        id: true,
        posMenuCategoryId: true,
        slug: true,
        nameKa: true,
        nameEn: true,
        sendToKitchen: true,
        sortOrder: true,
      },
    });
    const data = {
      venueId: tenant.venueId,
      slug: category.slug,
      nameKa: category.nameKa,
      nameEn: category.nameEn,
      sendToKitchen: category.sendToKitchen ?? true,
      sortOrder,
      ...(posMenuCategoryId ? { posMenuCategoryId } : {}),
    };
    if (
      existing &&
      existing.slug === data.slug &&
      existing.nameKa === data.nameKa &&
      existing.nameEn === data.nameEn &&
      existing.sendToKitchen === data.sendToKitchen &&
      existing.sortOrder === data.sortOrder &&
      (!posMenuCategoryId || existing.posMenuCategoryId === posMenuCategoryId)
    ) {
      return existing;
    }
    return existing
      ? db.menuCategory.update({ where: { id: existing.id }, data })
      : db.menuCategory.create({ data });
  }

  private async upsertSubcategory(
    db: Prisma.TransactionClient,
    tenant: TenantContext,
    categoryId: string,
    subcategory: MenuSubcategorySync,
    sortOrder: number,
  ) {
    const posMenuSubcategoryId = this.stableId(subcategory.id);
    let existing = posMenuSubcategoryId
      ? await db.menuSubcategory.findFirst({
          where: {
            posMenuSubcategoryId,
            category: { venueId: tenant.venueId },
          },
          select: {
            id: true,
            categoryId: true,
            posMenuSubcategoryId: true,
            slug: true,
            nameKa: true,
            nameEn: true,
            sortOrder: true,
          },
        })
      : null;
    existing ??= await db.menuSubcategory.findFirst({
      where: {
        categoryId,
        slug: subcategory.slug,
        ...(posMenuSubcategoryId ? { posMenuSubcategoryId: null } : {}),
      },
      select: {
        id: true,
        categoryId: true,
        posMenuSubcategoryId: true,
        slug: true,
        nameKa: true,
        nameEn: true,
        sortOrder: true,
      },
    });
    const data = {
      categoryId,
      slug: subcategory.slug,
      nameKa: subcategory.nameKa,
      nameEn: subcategory.nameEn,
      sortOrder,
      ...(posMenuSubcategoryId ? { posMenuSubcategoryId } : {}),
    };
    if (
      existing &&
      existing.categoryId === data.categoryId &&
      existing.slug === data.slug &&
      existing.nameKa === data.nameKa &&
      existing.nameEn === data.nameEn &&
      existing.sortOrder === data.sortOrder &&
      (!posMenuSubcategoryId ||
        existing.posMenuSubcategoryId === posMenuSubcategoryId)
    ) {
      return existing;
    }
    return existing
      ? db.menuSubcategory.update({ where: { id: existing.id }, data })
      : db.menuSubcategory.create({ data });
  }

  private async upsertItem(
    db: Prisma.TransactionClient,
    tenant: TenantContext,
    item: MenuItemSync,
    parent: Parent,
    sortOrder: number,
  ) {
    const posMenuItemId = this.stableId(item.id);
    let existing = posMenuItemId
      ? await db.menuItem.findFirst({
          where: { venueId: tenant.venueId, posMenuItemId },
          select: {
            id: true,
            categoryId: true,
            subcategoryId: true,
            posMenuItemId: true,
            nameKa: true,
            nameEn: true,
            price: true,
            sendToKitchen: true,
            sortOrder: true,
          },
        })
      : null;
    existing ??= await db.menuItem.findFirst({
      where: {
        venueId: tenant.venueId,
        nameEn: item.nameEn,
        categoryId: parent.categoryId,
        subcategoryId: parent.subcategoryId,
        ...(posMenuItemId ? { posMenuItemId: null } : {}),
      },
      select: {
        id: true,
        categoryId: true,
        subcategoryId: true,
        posMenuItemId: true,
        nameKa: true,
        nameEn: true,
        price: true,
        sendToKitchen: true,
        sortOrder: true,
      },
    });
    const data = {
      venueId: tenant.venueId,
      categoryId: parent.categoryId,
      subcategoryId: parent.subcategoryId,
      nameKa: item.nameKa,
      nameEn: item.nameEn,
      price: item.price,
      sendToKitchen: item.sendToKitchen ?? true,
      sortOrder,
      ...(posMenuItemId ? { posMenuItemId } : {}),
    };
    if (
      existing &&
      existing.categoryId === data.categoryId &&
      existing.subcategoryId === data.subcategoryId &&
      existing.nameKa === data.nameKa &&
      existing.nameEn === data.nameEn &&
      existing.price === data.price &&
      existing.sendToKitchen === data.sendToKitchen &&
      existing.sortOrder === data.sortOrder &&
      (!posMenuItemId || existing.posMenuItemId === posMenuItemId)
    ) {
      return existing;
    }
    return existing
      ? db.menuItem.update({ where: { id: existing.id }, data })
      : db.menuItem.create({ data });
  }

  private async upsertVariant(
    db: Prisma.TransactionClient,
    menuItemId: string,
    variant: MenuVariantSync,
  ): Promise<void> {
    const posMenuVariantId = this.stableId(variant.id);
    let existing = posMenuVariantId
      ? await db.menuItemVariant.findFirst({
          where: { menuItemId, posMenuVariantId },
          select: { id: true, posMenuVariantId: true, size: true, price: true },
        })
      : null;
    existing ??= await db.menuItemVariant.findFirst({
      where: {
        menuItemId,
        size: variant.size,
        ...(posMenuVariantId ? { posMenuVariantId: null } : {}),
      },
      select: { id: true, posMenuVariantId: true, size: true, price: true },
    });
    const data = {
      menuItemId,
      size: variant.size,
      price: variant.price,
      ...(posMenuVariantId ? { posMenuVariantId } : {}),
    };
    if (
      existing &&
      existing.size === data.size &&
      existing.price === data.price &&
      (!posMenuVariantId || existing.posMenuVariantId === posMenuVariantId)
    ) {
      return;
    }
    if (existing) {
      await db.menuItemVariant.update({ where: { id: existing.id }, data });
    } else {
      await db.menuItemVariant.create({ data });
    }
  }

  private staleOwnedIds(ids: Set<string>) {
    return { not: null, ...(ids.size > 0 ? { notIn: [...ids] } : {}) };
  }

  private async syncItemVariants(
    db: Prisma.TransactionClient,
    menuItemId: string,
    variants: MenuVariantSync[],
    authoritativeIdentity: boolean,
  ): Promise<void> {
    const ids = new Set<string>();
    for (const variant of variants) {
      await this.upsertVariant(db, menuItemId, variant);
      const id = this.stableId(variant.id);
      if (id) ids.add(id);
    }
    if (authoritativeIdentity) {
      await db.menuItemVariant.deleteMany({
        where: {
          menuItemId,
          posMenuVariantId: this.staleOwnedIds(ids),
        },
      });
    }
  }

  private async applySnapshot(
    db: Prisma.TransactionClient,
    tenant: TenantContext,
    menu: MenuCategorySync[],
    authoritativeIdentity: boolean,
  ): Promise<void> {
    const categoryIds = new Set<string>();
    const subcategoryIds = new Set<string>();
    const itemIds = new Set<string>();

    for (const [catIndex, cat] of menu.entries()) {
      const category = await this.upsertCategory(db, tenant, cat, catIndex);
      const catIdentity = this.stableId(cat.id);
      if (catIdentity) categoryIds.add(catIdentity);

      for (const [subIndex, sub] of (cat.subcategories ?? []).entries()) {
        const subcategory = await this.upsertSubcategory(
          db,
          tenant,
          category.id,
          sub,
          subIndex,
        );
        const subIdentity = this.stableId(sub.id);
        if (subIdentity) subcategoryIds.add(subIdentity);
        for (const [itemIndex, item] of (sub.items ?? []).entries()) {
          const row = await this.upsertItem(
            db,
            tenant,
            item,
            { categoryId: null, subcategoryId: subcategory.id },
            itemIndex,
          );
          const itemIdentity = this.stableId(item.id);
          if (itemIdentity) itemIds.add(itemIdentity);
          await this.syncItemVariants(
            db,
            row.id,
            item.variants ?? [],
            authoritativeIdentity,
          );
        }
      }

      for (const [itemIndex, item] of (cat.items ?? []).entries()) {
        const row = await this.upsertItem(
          db,
          tenant,
          item,
          { categoryId: category.id, subcategoryId: null },
          itemIndex,
        );
        const itemIdentity = this.stableId(item.id);
        if (itemIdentity) itemIds.add(itemIdentity);
        await this.syncItemVariants(
          db,
          row.id,
          item.variants ?? [],
          authoritativeIdentity,
        );
      }
    }

    if (!authoritativeIdentity) return;

    // Children first. Every predicate is Venue-scoped and only POS-claimed
    // rows are eligible. Unclaimed legacy/custom content is never inferred to
    // be deleted merely because its mutable name is absent.
    await db.menuItem.deleteMany({
      where: {
        venueId: tenant.venueId,
        posMenuItemId: this.staleOwnedIds(itemIds),
      },
    });
    await db.menuSubcategory.deleteMany({
      where: {
        category: { venueId: tenant.venueId },
        posMenuSubcategoryId: this.staleOwnedIds(subcategoryIds),
        items: { none: { posMenuItemId: null } },
      },
    });
    await db.menuCategory.deleteMany({
      where: {
        venueId: tenant.venueId,
        posMenuCategoryId: this.staleOwnedIds(categoryIds),
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
  }

  async sync(
    tenant: TenantContext,
    menu: MenuCategorySync[],
    identityVersion?: number,
  ): Promise<void> {
    console.log(`[SYNC] Syncing ${menu.length} categories...`);
    await this.prisma.$transaction((db) =>
      this.applySnapshot(db, tenant, menu, (identityVersion ?? 0) >= 1),
    );
  }
}
