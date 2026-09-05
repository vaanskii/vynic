import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from '../tenancy/tenant-context';
import {
  InventoryAuditAction,
  writeInventoryAudit,
  type InventoryActor,
} from './inventory-audit';
import {
  perUnitQuantity,
  perUnitQuantityText,
  positiveQuantity,
  quantityText,
  recipeUnitsFor,
  resolveRecipeQuantity,
} from './inventory-quantity';
import { inventoryUnit } from './inventory-unit';

export interface RecipeComponentInput {
  stockItemId?: unknown;
  quantity?: unknown;
  unit?: unknown;
  notes?: unknown;
}

export interface RecipeInput {
  menuItemId?: unknown;
  variantId?: unknown;
  yieldQuantity?: unknown;
  notes?: unknown;
  isActive?: unknown;
  components?: unknown;
}

export interface RecipeMenuQuery {
  search?: string;
  /** `configured` / `unconfigured`; anything else lists everything. */
  status?: string;
}

/** A component after validation, ready to persist. */
interface PreparedComponent {
  sequence: number;
  stockItemId: string;
  stockItemNameSnapshot: string;
  quantity: Prisma.Decimal;
  unit: string;
  baseQuantity: Prisma.Decimal;
  baseUnit: string;
  baseQuantityPerUnit: Prisma.Decimal;
  notes: string | null;
}

const MAX_COMPONENTS = 60;

/**
 * Menu consumption definitions — "technological cards".
 *
 * One model answers the same question for every shape of product: when this
 * Menu Item is sold, which Stock Items should eventually be consumed and how
 * much of each. A bottled drink is a one-component definition, a draft beer is
 * a one-component definition in litres, and khinkali are a four-component one.
 * They are not three subsystems; the Manager UI merely presents the first two
 * more simply.
 *
 * Nothing here writes a StockMovement. Step 3 defines consumption; Step 4 is
 * what performs it.
 */
@Injectable()
export class RecipeService {
  constructor(private readonly prisma: PrismaService) {}

  // ── Reads ───────────────────────────────────────────────────────────────

  /**
   * The Menu, annotated with what each item consumes.
   *
   * Menu-oriented on purpose: a Manager configuring a recipe starts from the
   * product they sell, not from a list of recipes that already exist. An item
   * with no definition is a first-class row here, marked unconfigured, so the
   * gap is visible rather than absent.
   */
  async listMenuItems(tenant: TenantContext, query: RecipeMenuQuery = {}) {
    const search = query.search?.trim();
    const rows = await this.prisma.menuItem.findMany({
      where: {
        venueId: tenant.venueId,
        ...(search
          ? {
              OR: [
                { nameKa: { contains: search, mode: 'insensitive' as const } },
                { nameEn: { contains: search, mode: 'insensitive' as const } },
              ],
            }
          : {}),
      },
      orderBy: [{ sortOrder: 'asc' }, { nameKa: 'asc' }, { id: 'asc' }],
      include: {
        category: { select: { nameKa: true, nameEn: true } },
        subcategory: { select: { nameKa: true, nameEn: true } },
        variants: { orderBy: { size: 'asc' } },
        consumptionRecipes: {
          include: { _count: { select: { components: true } } },
        },
      },
    });

    const items = rows.map((row) => {
      const byKey = new Map(
        row.consumptionRecipes.map((recipe) => [recipe.variantKey, recipe]),
      );
      return {
        menuItemId: row.id,
        posMenuItemId: row.posMenuItemId,
        nameKa: row.nameKa,
        nameEn: row.nameEn,
        price: row.price,
        categoryName:
          row.subcategory?.nameKa ?? row.category?.nameKa ?? null,
        recipe: summarise(byKey.get('')),
        variants: row.variants.map((variant) => ({
          variantId: variant.id,
          posMenuVariantId: variant.posMenuVariantId,
          size: variant.size,
          price: variant.price,
          recipe: summarise(byKey.get(variant.id)),
        })),
      };
    });

    const status = query.status?.trim().toLowerCase();
    if (status === 'configured') {
      return items.filter((item) => isConfigured(item));
    }
    if (status === 'unconfigured') {
      return items.filter((item) => !isConfigured(item));
    }
    return items;
  }

  /**
   * One definition, addressed the way the Manager thinks of it: by product.
   *
   * Returns the Menu Item context and a null recipe when nothing is configured
   * yet, so the editor can open on an empty card without a second round trip.
   */
  async detail(
    tenant: TenantContext,
    menuItemId: string,
    variantId?: string | null,
  ) {
    const menuItem = await this.requireMenuItem(
      this.prisma,
      tenant.venueId,
      requiredText(menuItemId, 'menuItemId'),
      optionalText(variantId),
    );
    const recipe = await this.prisma.menuConsumptionRecipe.findFirst({
      where: {
        venueId: tenant.venueId,
        menuItemId: menuItem.id,
        variantKey: variantKeyOf(menuItem.variant?.id ?? null),
      },
      include: { components: { orderBy: { sequence: 'asc' } } },
    });
    return {
      menuItemId: menuItem.id,
      posMenuItemId: menuItem.posMenuItemId,
      menuItemName: menuItem.nameKa,
      price: menuItem.variant?.price ?? menuItem.price,
      variantId: menuItem.variant?.id ?? null,
      variantLabel: variantLabel(menuItem.variant),
      /** What the editor may offer for each chosen Stock Item. */
      recipe: recipe ? this.present(recipe) : null,
    };
  }

  /**
   * Every Menu Item that consumes one Stock Item.
   *
   * The reverse of the editor, and the question inventory administration
   * actually asks: before disabling or renaming beef, who is using it?
   */
  async usageForStockItem(tenant: TenantContext, stockItemId: string) {
    const rows = await this.prisma.menuConsumptionComponent.findMany({
      where: {
        venueId: tenant.venueId,
        stockItemId: requiredText(stockItemId, 'stockItemId'),
        recipe: { isActive: true },
      },
      include: { recipe: true },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    return rows.map((row) => ({
      recipeId: row.recipeId,
      menuItemId: row.recipe.menuItemId,
      menuItemName: row.recipe.menuItemNameSnapshot,
      variantId: row.recipe.variantId,
      variantLabel: row.recipe.variantLabelSnapshot,
      quantityPerUnit: perUnitQuantityText(row.baseQuantityPerUnit),
      baseUnit: row.baseUnit,
    }));
  }

  /**
   * The complete active projection an offline POS needs.
   *
   * Carries both identities: the Cloud key that Manager writes address, and the
   * POS's own Menu identity, which is what an offline terminal can match a sold
   * line against without asking Cloud anything.
   */
  async projection(venueId: string) {
    const rows = await this.prisma.menuConsumptionRecipe.findMany({
      where: { venueId, isActive: true },
      include: {
        components: { orderBy: { sequence: 'asc' } },
        menuItem: { select: { posMenuItemId: true } },
        variant: { select: { posMenuVariantId: true } },
      },
      orderBy: [{ menuItemId: 'asc' }, { variantKey: 'asc' }],
    });
    return rows.map((row) => ({
      recipeId: row.id,
      revision: row.revision,
      menuItemId: row.menuItemId,
      posMenuItemId: row.menuItem.posMenuItemId,
      variantId: row.variantId,
      posMenuVariantId: row.variant?.posMenuVariantId ?? null,
      menuItemName: row.menuItemNameSnapshot,
      variantLabel: row.variantLabelSnapshot,
      yieldQuantity: quantityText(row.yieldQuantity),
      components: row.components.map((component) => ({
        stockItemId: component.stockItemId,
        stockItemName: component.stockItemNameSnapshot,
        // The one number Step 4 will consume. Already divided by the yield.
        baseQuantityPerUnit: perUnitQuantityText(component.baseQuantityPerUnit),
        baseUnit: component.baseUnit,
      })),
    }));
  }

  // ── Writes ──────────────────────────────────────────────────────────────

  /**
   * Create or replace the definition for one Menu Item + variant.
   *
   * There is exactly one active definition per product, enforced by
   * `@@unique([menuItemId, variantKey])`, so saving twice edits rather than
   * forks. Every save bumps `revision`: a Step 4 snapshot can then say which
   * definition it consumed by, instead of joining today's recipe onto a sale
   * that happened last week.
   */
  async save(actor: InventoryActor, input: RecipeInput) {
    const menuItemId = requiredText(input.menuItemId, 'menuItemId');
    const variantIdRaw = optionalText(input.variantId);
    const yieldQuantity = positiveQuantity(
      input.yieldQuantity ?? '1',
      'yieldQuantity',
    );
    const notes = optionalText(input.notes);

    return this.prisma.$transaction(async (tx) => {
      const menuItem = await this.requireMenuItem(
        tx,
        actor.venueId,
        menuItemId,
        variantIdRaw,
      );
      const variantId = menuItem.variant?.id ?? null;
      const components = await this.prepareComponents(
        tx,
        actor,
        input.components,
        yieldQuantity,
      );
      if (components.length === 0) {
        throw new BadRequestException(
          'A recipe must consume at least one Stock Item',
        );
      }

      const existing = await tx.menuConsumptionRecipe.findFirst({
        where: {
          venueId: actor.venueId,
          menuItemId: menuItem.id,
          variantKey: variantKeyOf(variantId),
        },
        include: { components: true },
      });

      const header = {
        menuItemNameSnapshot: menuItem.nameKa,
        variantLabelSnapshot: variantLabel(menuItem.variant),
        yieldQuantity,
        notes,
        isActive: input.isActive == null ? true : requiredBoolean(input.isActive),
        updatedById: actor.staffId,
        updatedByName: actor.username,
      };

      let saved;
      if (existing) {
        // Components are replaced as one declared set: removing an ingredient
        // is expressed by sending the set without it.
        await tx.menuConsumptionComponent.deleteMany({
          where: { recipeId: existing.id },
        });
        saved = await tx.menuConsumptionRecipe.update({
          where: { id: existing.id },
          data: {
            ...header,
            revision: { increment: 1 },
            components: {
              create: components.map((component) => ({
                venueId: actor.venueId,
                ...component,
              })),
            },
          },
          include: { components: { orderBy: { sequence: 'asc' } } },
        });
      } else {
        saved = await tx.menuConsumptionRecipe.create({
          data: {
            venueId: actor.venueId,
            menuItemId: menuItem.id,
            variantId,
            variantKey: variantKeyOf(variantId),
            ...header,
            createdById: actor.staffId,
            createdByName: actor.username,
            components: {
              create: components.map((component) => ({
                venueId: actor.venueId,
                ...component,
              })),
            },
          },
          include: { components: { orderBy: { sequence: 'asc' } } },
        });
      }

      await writeInventoryAudit(tx, actor, {
        action: existing
          ? InventoryAuditAction.RECIPE_UPDATED
          : InventoryAuditAction.RECIPE_CREATED,
        entityType: 'RECIPE',
        entityId: saved.id,
        data: this.auditContext(saved),
      });
      return this.present(saved);
    });
  }

  /**
   * Stop applying a definition without deleting what it said.
   *
   * A disabled recipe leaves the POS projection and stops being a consumption
   * rule, but the row stays: a Step 4 snapshot may still name it, and a Manager
   * who disabled the wrong card wants it back, not retyped.
   */
  async disable(actor: InventoryActor, id: string) {
    const cleanId = requiredText(id, 'id');
    return this.prisma.$transaction(async (tx) => {
      const existing = await tx.menuConsumptionRecipe.findFirst({
        where: { id: cleanId, venueId: actor.venueId },
        include: { components: { orderBy: { sequence: 'asc' } } },
      });
      if (!existing) throw new NotFoundException('Recipe not found');
      if (!existing.isActive) {
        return { ...this.present(existing), result: 'already_disabled' as const };
      }
      const disabled = await tx.menuConsumptionRecipe.update({
        where: { id: existing.id },
        data: {
          isActive: false,
          revision: { increment: 1 },
          updatedById: actor.staffId,
          updatedByName: actor.username,
        },
        include: { components: { orderBy: { sequence: 'asc' } } },
      });
      await writeInventoryAudit(tx, actor, {
        action: InventoryAuditAction.RECIPE_DISABLED,
        entityType: 'RECIPE',
        entityId: disabled.id,
        data: { ...this.auditContext(disabled), previousIsActive: true },
      });
      return { ...this.present(disabled), result: 'disabled' as const };
    });
  }

  // ── Internals ───────────────────────────────────────────────────────────

  /**
   * The Menu Item, proven to belong to this Venue, with its variant resolved.
   *
   * The variant is checked against the item rather than trusted: a payload that
   * pairs one venue's item with another's variant is a tenancy question, not a
   * validation nicety.
   */
  private async requireMenuItem(
    tx: Prisma.TransactionClient | PrismaService,
    venueId: string,
    menuItemId: string,
    variantId: string | null,
  ) {
    const menuItem = await tx.menuItem.findFirst({
      where: { id: menuItemId, venueId },
      include: { variants: true },
    });
    if (!menuItem) throw new NotFoundException('Menu item not found');
    if (variantId == null) {
      return { ...menuItem, variant: null };
    }
    const variant = menuItem.variants.find((row) => row.id === variantId);
    if (!variant) {
      throw new NotFoundException(
        'Menu variant not found on this Menu item',
      );
    }
    return { ...menuItem, variant };
  }

  private async prepareComponents(
    tx: Prisma.TransactionClient,
    actor: InventoryActor,
    raw: unknown,
    yieldQuantity: Prisma.Decimal,
  ): Promise<PreparedComponent[]> {
    if (raw == null) return [];
    if (!Array.isArray(raw)) {
      throw new BadRequestException('components must be an array');
    }
    if (raw.length > MAX_COMPONENTS) {
      throw new BadRequestException(
        `A recipe may hold up to ${MAX_COMPONENTS} components`,
      );
    }

    const inputs = raw as RecipeComponentInput[];
    const ids = Array.from(
      new Set(
        inputs.map((row) => requiredText(row.stockItemId, 'stockItemId')),
      ),
    );
    const items = await tx.stockItem.findMany({
      where: { id: { in: ids }, venueId: actor.venueId },
      select: { id: true, name: true, baseUnit: true },
    });
    const byId = new Map(items.map((item) => [item.id, item]));

    const seen = new Set<string>();
    return inputs.map((row, index) => {
      const stockItemId = requiredText(row.stockItemId, 'stockItemId');
      const item = byId.get(stockItemId);
      if (!item) {
        throw new NotFoundException(
          `Stock item ${stockItemId} does not belong to this Venue`,
        );
      }
      if (seen.has(stockItemId)) {
        throw new BadRequestException(
          `${item.name} is listed twice; combine it into one component`,
        );
      }
      seen.add(stockItemId);

      const quantity = positiveQuantity(row.quantity, 'quantity');
      const unit = inventoryUnit(row.unit ?? item.baseUnit);
      const allowed = recipeUnitsFor(item.baseUnit);
      if (!allowed.includes(unit)) {
        throw new BadRequestException(
          `${item.name} is consumed in ${allowed.join(' or ')}, not ${unit}`,
        );
      }
      const { baseQuantity } = resolveRecipeQuantity({
        quantity,
        unit,
        baseUnit: item.baseUnit,
      });
      if (baseQuantity.lessThanOrEqualTo(0)) {
        throw new BadRequestException(
          `${item.name} must consume a positive quantity`,
        );
      }
      return {
        sequence: index,
        stockItemId,
        stockItemNameSnapshot: item.name,
        quantity,
        unit,
        baseQuantity,
        baseUnit: item.baseUnit,
        baseQuantityPerUnit: perUnitQuantity(baseQuantity, yieldQuantity),
        notes: optionalText(row.notes),
      };
    });
  }

  private auditContext(row: {
    id: string;
    menuItemId: string;
    menuItemNameSnapshot: string;
    variantId: string | null;
    variantLabelSnapshot: string | null;
    yieldQuantity: Prisma.Decimal;
    isActive: boolean;
    revision: number;
    components: unknown[];
  }) {
    // A summary, not the card: the components themselves are readable at the
    // recipe, and copying them into every audit row would bury the feed.
    return {
      recipeId: row.id,
      menuItemId: row.menuItemId,
      menuItemName: row.menuItemNameSnapshot,
      variantId: row.variantId,
      variantLabel: row.variantLabelSnapshot,
      yieldQuantity: quantityText(row.yieldQuantity),
      componentCount: row.components.length,
      isActive: row.isActive,
      revision: row.revision,
    };
  }

  private present(row: any) {
    return {
      id: row.id,
      menuItemId: row.menuItemId,
      menuItemName: row.menuItemNameSnapshot,
      variantId: row.variantId,
      variantLabel: row.variantLabelSnapshot,
      yieldQuantity: quantityText(row.yieldQuantity),
      isActive: row.isActive,
      notes: row.notes,
      revision: row.revision,
      createdByName: row.createdByName,
      updatedByName: row.updatedByName,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      components: (row.components ?? []).map((component: any) => ({
        id: component.id,
        sequence: component.sequence,
        stockItemId: component.stockItemId,
        stockItemName: component.stockItemNameSnapshot,
        quantity: quantityText(component.quantity),
        unit: component.unit,
        baseQuantity: quantityText(component.baseQuantity),
        baseUnit: component.baseUnit,
        baseQuantityPerUnit: perUnitQuantityText(component.baseQuantityPerUnit),
        notes: component.notes,
      })),
    };
  }
}

function summarise(
  recipe: { id: string; isActive: boolean; revision: number; _count?: { components: number } } | undefined,
) {
  if (!recipe) return null;
  return {
    id: recipe.id,
    isActive: recipe.isActive,
    revision: recipe.revision,
    componentCount: recipe._count?.components ?? 0,
  };
}

function isConfigured(item: {
  recipe: { isActive: boolean } | null;
  variants: { recipe: { isActive: boolean } | null }[];
}): boolean {
  if (item.recipe?.isActive) return true;
  return item.variants.some((variant) => variant.recipe?.isActive === true);
}

/**
 * `''` for a Menu Item with no variant.
 *
 * PostgreSQL treats NULLs as distinct, so this non-null discriminator is what
 * makes "one definition per Menu Item + variant" a database rule.
 */
function variantKeyOf(variantId: string | null): string {
  return variantId ?? '';
}

/** `0.5 L`-style label, frozen for display. Identity stays the variant id. */
function variantLabel(variant: { size: number } | null | undefined): string | null {
  if (!variant) return null;
  return `${variant.size}`;
}

function requiredText(raw: unknown, field: string): string {
  const value = typeof raw === 'string' ? raw.trim() : '';
  if (!value) throw new BadRequestException(`${field} is required`);
  if (value.length > 500) throw new BadRequestException(`${field} is too long`);
  return value;
}

function optionalText(raw: unknown): string | null {
  if (raw == null) return null;
  if (typeof raw !== 'string') throw new BadRequestException('Expected text');
  const value = raw.trim();
  if (value.length > 2000) throw new BadRequestException('Text is too long');
  return value || null;
}

function requiredBoolean(raw: unknown): boolean {
  if (typeof raw !== 'boolean') {
    throw new BadRequestException('isActive must be boolean');
  }
  return raw;
}
