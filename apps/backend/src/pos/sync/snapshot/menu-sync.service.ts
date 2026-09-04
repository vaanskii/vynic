import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../../prisma.service';
import type { TenantContext } from '../../../auth/pos-auth-context';

/**
 * Mirrors the POS menu tree onto the server.
 *
 * Four levels deep. Categories and subcategories still match on slug, and
 * variants are still rewritten wholesale because they carry no stable key.
 * Items match on `posMenuItemId` — the POS's own stable id — falling back to
 * (nameEn, parent) only for a row that has not been adopted yet. Payload
 * position becomes `sortOrder`, which is how the manager app reproduces the
 * POS's ordering.
 *
 * Matching by name was the reason a rename produced two products: the mirror
 * could not tell "Khinkali became Khinkali Classic" from "Khinkali Classic is
 * new", so it created a second row and left the first behind for the manager
 * app and the website to show side by side. With identity on the wire the
 * rename is an update, and the move between categories is a re-parent.
 *
 * Skipped entirely on the realtime fast path — the caller decides that.
 */
type MenuItemParent = { categoryId: string | null; subcategoryId: string | null };

@Injectable()
export class MenuSyncService {
  constructor(private readonly prisma: PrismaService) {}

  /** The POS-owned identity on a payload item, or null for an older build. */
  private posItemId(it: any): string | null {
    const raw = typeof it?.id === 'string' ? it.id.trim() : '';
    return raw.length > 0 ? raw : null;
  }

  /**
   * Finds the mirror row this payload item is, and updates it — or creates it.
   *
   * Lookup order matters, and it is the whole point of this method:
   *
   * 1. by `posMenuItemId`, wherever in the tree that row currently sits, so a
   *    rename or a move updates the product rather than duplicating it;
   * 2. failing that, by name under the same parent, but only among rows that
   *    have not been claimed by another item — this is the one-time adoption
   *    that lets an already-mirrored Vankisi menu take on POS identity without
   *    a single new row appearing;
   * 3. failing that, create.
   */
  private async upsertItem(
    tenant: TenantContext,
    it: any,
    parent: MenuItemParent,
    sortOrder: number,
  ): Promise<{ id: string }> {
    const posMenuItemId = this.posItemId(it);
    const data = {
      venueId: tenant.venueId,
      categoryId: parent.categoryId,
      subcategoryId: parent.subcategoryId,
      nameKa: it.nameKa,
      nameEn: it.nameEn,
      price: it.price,
      sendToKitchen: it.sendToKitchen,
      sortOrder,
      ...(posMenuItemId ? { posMenuItemId } : {}),
    };

    let existing: { id: string } | null = null;
    if (posMenuItemId) {
      existing = await (this.prisma as any).menuItem.findFirst({
        where: { venueId: tenant.venueId, posMenuItemId },
        select: { id: true },
      });
    }
    if (!existing) {
      existing = await (this.prisma as any).menuItem.findFirst({
        where: {
          venueId: tenant.venueId,
          nameEn: it.nameEn,
          categoryId: parent.categoryId,
          subcategoryId: parent.subcategoryId,
          // Adopt only an unclaimed row: one already carrying a different
          // POS id belongs to a different product that happens to share a
          // name, and stealing it would merge two menu items into one.
          ...(posMenuItemId ? { posMenuItemId: null } : {}),
        },
        select: { id: true },
      });
    }

    if (existing) {
      return (this.prisma as any).menuItem.update({
        where: { id: existing.id },
        data,
      });
    }
    return (this.prisma as any).menuItem.create({ data });
  }

  /** Variants carry no stable key, so they are rewritten wholesale. */
  private async syncVariants(menuItemId: string, it: any): Promise<void> {
    if (!it.variants) return;
    await (this.prisma as any).menuItemVariant.deleteMany({
      where: { menuItemId },
    });
    for (const v of it.variants) {
      await (this.prisma as any).menuItemVariant.create({
        data: { menuItemId, size: v.size, price: v.price },
      });
    }
  }

  async sync(tenant: TenantContext, menu: any[]): Promise<void> {
    console.log(`[SYNC] Syncing ${menu.length} categories...`);
    for (let catIndex = 0; catIndex < menu.length; catIndex++) {
      const cat = menu[catIndex];
      const category = await (this.prisma as any).menuCategory.upsert({
        where: {
          venueId_slug: { venueId: tenant.venueId, slug: cat.slug },
        },
        update: {
          nameKa: cat.nameKa,
          nameEn: cat.nameEn,
          sendToKitchen: cat.sendToKitchen,
          sortOrder: catIndex,
        },
        create: {
          venueId: tenant.venueId,
          slug: cat.slug,
          nameKa: cat.nameKa,
          nameEn: cat.nameEn,
          sendToKitchen: cat.sendToKitchen,
          sortOrder: catIndex,
        },
      });

      // Sync Subcategories
      if (cat.subcategories) {
        for (
          let subIndex = 0;
          subIndex < cat.subcategories.length;
          subIndex++
        ) {
          const sub = cat.subcategories[subIndex];
          const subcategory = await (this.prisma as any).menuSubcategory.upsert(
            {
              where: {
                slug_categoryId: { slug: sub.slug, categoryId: category.id },
              },
              update: {
                nameKa: sub.nameKa,
                nameEn: sub.nameEn,
                sortOrder: subIndex,
              },
              create: {
                slug: sub.slug,
                nameKa: sub.nameKa,
                nameEn: sub.nameEn,
                categoryId: category.id,
                sortOrder: subIndex,
              },
            },
          );

          if (sub.items) {
            for (let itemIndex = 0; itemIndex < sub.items.length; itemIndex++) {
              const it = sub.items[itemIndex];
              const item = await this.upsertItem(
                tenant,
                it,
                { categoryId: null, subcategoryId: subcategory.id },
                itemIndex,
              );
              await this.syncVariants(item.id, it);
            }
          }
        }
      }

      if (cat.items) {
        for (let itemIndex = 0; itemIndex < cat.items.length; itemIndex++) {
          const it = cat.items[itemIndex];
          const item = await this.upsertItem(
            tenant,
            it,
            { categoryId: category.id, subcategoryId: null },
            itemIndex,
          );
          await this.syncVariants(item.id, it);
        }
      }
    }
  }
}
