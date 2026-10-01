import { validateMediaReferences } from './website-media';
import { requireCommercialFeature } from '../../entitlements/commercial-state';
import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma.service';
import {
  activeCategory,
  activeSubcategory,
  activeMenuItem,
} from '../../menu-catalog/menu-active';
import {
  websiteMenuPresentationInput,
  type WebsiteMenuPresentationInput,
} from './website-menu';

/**
 * The website presentation layer over the operational menu.
 *
 * Core menu authority stays with POS/Cloud: nothing here creates, renames,
 * reprices or deletes a `MenuItem`. It answers one question per existing
 * item — whether and how it appears publicly — and then reads the live
 * operational tree through that filter, so an item the restaurant stops
 * selling simply stops being returned instead of leaving a stale public copy.
 */
const itemArgs = Prisma.validator<Prisma.MenuItemDefaultArgs>()({
  select: {
    id: true,
    nameKa: true,
    nameEn: true,
    price: true,
    enabled: true,
    sortOrder: true,
    subcategoryId: true,
    variants: {
      where: { retiredAt: null },
      select: { id: true, size: true, price: true },
      orderBy: [{ size: 'asc' }, { id: 'asc' }],
    },
    websitePresentation: {
      select: {
        visibleOnWebsite: true,
        displayName: true,
        description: true,
        imageUrl: true,
        sortOrder: true,
      },
    },
  },
});

type MenuRow = Prisma.MenuItemGetPayload<typeof itemArgs>;

/**
 * Where an item sits on the website.
 *
 * An item the owner has never touched keeps its operational position, so the
 * public menu reads the way the POS menu does until the owner deliberately
 * reorders it.
 */
function position(item: MenuRow) {
  return item.websitePresentation?.sortOrder ?? item.sortOrder;
}
function byPosition(a: MenuRow, b: MenuRow) {
  return (
    position(a) - position(b) ||
    a.sortOrder - b.sortOrder ||
    a.nameEn.localeCompare(b.nameEn)
  );
}

@Injectable()
export class WebsiteMenuService {
  constructor(private readonly db: PrismaService) {}

  private tree(venueId: string) {
    return this.db.menuCategory.findMany({
      where: { venueId, ...activeCategory },
      orderBy: [{ sortOrder: 'asc' }, { nameEn: 'asc' }],
      select: {
        id: true,
        slug: true,
        nameKa: true,
        nameEn: true,
        sortOrder: true,
        items: { ...itemArgs, where: activeMenuItem },
        subcategories: {
          where: activeSubcategory,
          orderBy: [{ sortOrder: 'asc' }, { nameEn: 'asc' }],
          select: {
            id: true,
            slug: true,
            nameKa: true,
            nameEn: true,
            sortOrder: true,
            items: { ...itemArgs, where: activeMenuItem },
          },
        },
      },
    });
  }

  /**
   * The menu as visitors see it: visible items only, presentation applied.
   *
   * Categories and subcategories that end up with nothing visible are dropped
   * rather than rendered as empty headings.
   */
  async publicMenu(venueId: string) {
    const categories = await this.tree(venueId);
    const shown = categories
      .map((category) => {
        const direct = category.items
          .filter((item) => !item.subcategoryId)
          .filter(
            (item) =>
              item.enabled !== false &&
              item.websitePresentation?.visibleOnWebsite !== false,
          )
          .sort(byPosition)
          .map((item) => this.publicItem(item));
        const subcategories = category.subcategories
          .map((sub) => ({
            id: sub.id,
            slug: sub.slug,
            name: { ka: sub.nameKa, en: sub.nameEn },
            items: sub.items
              .filter(
                (item) =>
                  item.enabled !== false &&
                  item.websitePresentation?.visibleOnWebsite !== false,
              )
              .sort(byPosition)
              .map((item) => this.publicItem(item)),
          }))
          .filter((sub) => sub.items.length > 0);
        return {
          id: category.id,
          slug: category.slug,
          name: { ka: category.nameKa, en: category.nameEn },
          items: direct,
          subcategories,
        };
      })
      .filter(
        (category) =>
          category.items.length > 0 || category.subcategories.length > 0,
      );
    return { categories: shown };
  }

  private publicItem(item: MenuRow) {
    const presentation = item.websitePresentation;
    return {
      id: item.id,
      name: { ka: item.nameKa, en: item.nameEn },
      displayName: presentation?.displayName ?? null,
      description: presentation?.description ?? null,
      imageUrl: presentation?.imageUrl ?? null,
      price: item.price,
      variants: item.variants.map((variant) => ({
        id: variant.id,
        size: variant.size,
        price: variant.price,
      })),
    };
  }

  /**
   * The same tree for the owner editor, including hidden items.
   *
   * Operational fields are read-only here; the editor writes presentation only.
   */
  async ownerMenu(venueId: string) {
    await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    const categories = await this.tree(venueId);
    const ownerItem = (item: MenuRow) => ({
      menuItemId: item.id,
      name: { ka: item.nameKa, en: item.nameEn },
      price: item.price,
      variantCount: item.variants.length,
      variants: item.variants.map((variant) => ({
        id: variant.id,
        size: variant.size,
        price: variant.price,
      })),
      visibleOnWebsite: item.websitePresentation?.visibleOnWebsite ?? true,
      displayName: item.websitePresentation?.displayName ?? null,
      description: item.websitePresentation?.description ?? null,
      imageUrl: item.websitePresentation?.imageUrl ?? null,
      sortOrder: position(item),
      configured: !!item.websitePresentation,
    });
    return {
      categories: categories.map((category) => ({
        id: category.id,
        slug: category.slug,
        name: { ka: category.nameKa, en: category.nameEn },
        items: category.items
          .filter((item) => !item.subcategoryId)
          .sort(byPosition)
          .map(ownerItem),
        subcategories: category.subcategories.map((sub) => ({
          id: sub.id,
          slug: sub.slug,
          name: { ka: sub.nameKa, en: sub.nameEn },
          items: sub.items.sort(byPosition).map(ownerItem),
        })),
      })),
    };
  }

  /**
   * Apply a batch of presentation rows for one Venue.
   *
   * Every id is proven to belong to the resolved Venue inside the transaction,
   * so a forged or borrowed `menuItemId` writes nothing at all rather than
   * partially succeeding.
   */
  async savePresentation(
    venueId: string,
    body: unknown,
    customerAccountId: string,
  ) {
    await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    const rows = websiteMenuPresentationInput(body);
    if (rows.length)
      await this.db.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
        await requireCommercialFeature(tx, venueId, 'WEBSITE');
        const owned = await tx.menuItem.findMany({
          where: {
            venueId,
            ...activeMenuItem,
            id: { in: rows.map((r) => r.menuItemId) },
          },
          select: { id: true },
        });
        if (owned.length !== rows.length)
          throw new BadRequestException('Unknown menu item');
        const prior = await tx.menuItemWebsitePresentation.findMany({
          where: { venueId },
        });
        await validateMediaReferences(tx, venueId, rows, prior);
        for (const row of rows) await this.upsert(tx, venueId, row);
        await tx.customerAuditEvent.create({
          data: {
            customerAccountId,
            action: 'website.menu_presentation_saved',
            targetType: 'MenuItemWebsitePresentation',
            targetId: venueId,
            metadata: { items: rows.length },
          },
        });
      });
    return this.ownerMenu(venueId);
  }

  private upsert(
    tx: Prisma.TransactionClient,
    venueId: string,
    row: WebsiteMenuPresentationInput,
  ) {
    const data = {
      visibleOnWebsite: row.visibleOnWebsite,
      displayName: row.displayName,
      description: row.description,
      imageUrl: row.imageUrl,
      sortOrder: row.sortOrder,
    };
    return tx.menuItemWebsitePresentation.upsert({
      where: { menuItemId: row.menuItemId },
      create: { menuItemId: row.menuItemId, venueId, ...data },
      update: data,
    });
  }
}
