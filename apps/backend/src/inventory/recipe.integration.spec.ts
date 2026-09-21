import { PrismaService } from '../prisma.service';
import type { ManagerAuthContext } from '../auth/manager-auth-context';
import { InventoryService } from './inventory.service';
import { RecipeService } from './recipe.service';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

/**
 * Menu consumption definitions against real PostgreSQL.
 *
 * The claims worth a database: that one generalized model really does cover a
 * bottle, a draft pour and a four-ingredient recipe; that "one definition per
 * Menu Item + variant" survives a second save; that editing a card moves no
 * stock; and that a Venue cannot reach another Venue's menu, stock or recipes.
 */
describeDatabase('Menu consumption recipes (PostgreSQL)', () => {
  let prisma: PrismaService;
  let inventory: InventoryService;
  let recipes: RecipeService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `e0000000-0000-4000-8000-${suffix}`;
  const venueAId = `e1000000-0000-4000-8000-${suffix}`;
  const venueBId = `e2000000-0000-4000-8000-${suffix}`;
  const venueIds = [venueAId, venueBId];

  const actor = (venueId: string, staffId: string): ManagerAuthContext => ({
    venueId,
    organizationId,
    staffId,
    username: staffId,
    role: 'MANAGER',
  });
  const a = actor(venueAId, 'manager-a');
  const b = actor(venueBId, 'manager-b');
  const tenantA = { venueId: venueAId, organizationId };
  const tenantB = { venueId: venueBId, organizationId };

  async function clean() {
    await prisma.menuConsumptionComponent.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.menuConsumptionRecipe.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.stockMovement.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.stockItemPurchaseUnit.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.stockItem.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.menuItemVariant.deleteMany({
      where: { menuItem: { venueId: { in: venueIds } } },
    });
    await prisma.menuItem.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.menuCategory.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.auditEventLog.deleteMany({
      where: { venueId: { in: venueIds } },
    });
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    recipes = new RecipeService(prisma);
    inventory = new InventoryService(prisma, recipes);
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Recipe fixture',
        venues: {
          create: venueIds.map((id, index) => ({
            id,
            name: `Recipe Venue ${index}`,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
          })),
        },
      },
    });
  });

  beforeEach(clean);

  afterAll(async () => {
    await clean();
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  let sequence = 0;

  /** One Menu Item, optionally with variants, as menu sync would mirror it. */
  async function menuItem(
    venueId: string,
    nameKa: string,
    variants: number[] = [],
  ) {
    sequence += 1;
    const category = await prisma.menuCategory.upsert({
      where: { venueId_slug: { venueId, slug: 'main' } },
      update: {},
      create: { venueId, slug: 'main', nameKa: 'მთავარი', nameEn: 'Main' },
    });
    return prisma.menuItem.create({
      data: {
        venueId,
        categoryId: category.id,
        posMenuItemId: `pos-item-${venueId.slice(0, 4)}-${sequence}`,
        nameKa,
        nameEn: nameKa,
        price: 10,
        variants: {
          create: variants.map((size, index) => ({
            posMenuVariantId: `pos-variant-${sequence}-${index}`,
            size,
            price: 10 + size,
          })),
        },
      },
      include: { variants: { orderBy: { size: 'asc' } } },
    });
  }

  function stockItem(venueId: string, name: string, baseUnit: string) {
    return inventory.createStockItem(actor(venueId, 'manager'), {
      name,
      baseUnit,
    });
  }

  // ── The three product shapes, one model ─────────────────────────────────

  it('maps a bottled product one-to-one', async () => {
    const cola = await menuItem(venueAId, 'Coca-Cola 0.5L');
    const stock = await stockItem(venueAId, 'Coca-Cola 0.5L', 'bottle');

    const saved = await recipes.save(a, {
      menuItemId: cola.id,
      components: [{ stockItemId: stock.id, quantity: '1', unit: 'bottle' }],
    });

    expect(saved.components).toHaveLength(1);
    expect(saved.components[0].baseQuantity).toBe('1.000');
    expect(saved.components[0].baseUnit).toBe('bottle');
    expect(saved.components[0].baseQuantityPerUnit).toBe('1.000000');
    // Identity stays separate: a Menu Item is never a Stock Item.
    expect(saved.components[0].stockItemId).not.toBe(cola.id);
  });

  it('maps three draft sizes onto one keg-filled Stock Item', async () => {
    const beer = await stockItem(venueAId, 'Draft Beer', 'L');
    const small = await menuItem(venueAId, 'Draft Beer 0.3L');
    const large = await menuItem(venueAId, 'Draft Beer 0.5L');
    const pitcher = await menuItem(venueAId, 'Pitcher 1L');

    const pours = [
      { item: small, ml: '300', expected: '0.300' },
      { item: large, ml: '500', expected: '0.500' },
      { item: pitcher, ml: '1000', expected: '1.000' },
    ];
    for (const pour of pours) {
      const saved = await recipes.save(a, {
        menuItemId: pour.item.id,
        components: [{ stockItemId: beer.id, quantity: pour.ml, unit: 'ml' }],
      });
      expect(saved.components[0].baseQuantity).toBe(pour.expected);
      expect(saved.components[0].baseUnit).toBe('L');
    }

    // One Stock Item, three products. Many-to-many, not a forced pairing.
    const usage = await recipes.usageForStockItem(tenantA, beer.id);
    expect(usage.map((row) => row.menuItemName).sort()).toEqual([
      'Draft Beer 0.3L',
      'Draft Beer 0.5L',
      'Pitcher 1L',
    ]);
    expect(usage.map((row) => row.quantityPerUnit).sort()).toEqual([
      '0.300000',
      '0.500000',
      '1.000000',
    ]);
  });

  it('persists and reloads a multi-ingredient recipe in order', async () => {
    const khinkali = await menuItem(venueAId, 'ხინკალი');
    const beef = await stockItem(venueAId, 'Beef', 'kg');
    const flour = await stockItem(venueAId, 'Flour', 'kg');
    const onion = await stockItem(venueAId, 'Onion', 'kg');
    const spices = await stockItem(venueAId, 'Spices', 'kg');

    await recipes.save(a, {
      menuItemId: khinkali.id,
      components: [
        { stockItemId: beef.id, quantity: '35', unit: 'g' },
        { stockItemId: flour.id, quantity: '25', unit: 'g' },
        { stockItemId: onion.id, quantity: '8', unit: 'g' },
        { stockItemId: spices.id, quantity: '2', unit: 'g' },
      ],
    });

    const reloaded = await recipes.detail(tenantA, khinkali.id);
    expect(reloaded.recipe?.components.map((c) => c.stockItemName)).toEqual([
      'Beef',
      'Flour',
      'Onion',
      'Spices',
    ]);
    expect(reloaded.recipe?.components.map((c) => c.baseQuantity)).toEqual([
      '0.035',
      '0.025',
      '0.008',
      '0.002',
    ]);
    // One Menu Item uses many Stock Items; the same items may serve others.
    expect(await recipes.usageForStockItem(tenantA, beef.id)).toHaveLength(1);
  });

  // ── Quantities and units ────────────────────────────────────────────────

  it('normalizes grams and millilitres and refuses incompatible dimensions', async () => {
    const beef = await stockItem(venueAId, 'Beef', 'kg');
    const beer = await stockItem(venueAId, 'Draft Beer', 'L');
    const burger = await menuItem(venueAId, 'Burger');

    const saved = await recipes.save(a, {
      menuItemId: burger.id,
      components: [{ stockItemId: beef.id, quantity: '150', unit: 'g' }],
    });
    expect(saved.components[0].baseQuantity).toBe('0.150');

    await expect(
      recipes.save(a, {
        menuItemId: burger.id,
        components: [{ stockItemId: beef.id, quantity: '1', unit: 'L' }],
      }),
    ).rejects.toThrow(/consumed in/);
    await expect(
      recipes.save(a, {
        menuItemId: burger.id,
        components: [{ stockItemId: beer.id, quantity: '1', unit: 'kg' }],
      }),
    ).rejects.toThrow(/consumed in/);
  });

  it('refuses purchase packaging as a consumption unit', async () => {
    const lemonade = await stockItem(venueAId, 'Lemonade', 'bottle');
    await prisma.stockItemPurchaseUnit.create({
      data: {
        venueId: venueAId,
        stockItemId: lemonade.id,
        unit: 'box',
        baseUnitMultiplier: '24',
      },
    });
    const glass = await menuItem(venueAId, 'Lemonade glass');

    // Receiving accepts "1 box = 24 bottle"; consumption never does.
    await expect(
      recipes.save(a, {
        menuItemId: glass.id,
        components: [{ stockItemId: lemonade.id, quantity: '1', unit: 'box' }],
      }),
    ).rejects.toThrow(/consumed in bottle/);
  });

  it('normalizes a batch definition to per-sale-unit consumption', async () => {
    const khinkali = await menuItem(venueAId, 'ხინკალი');
    const beef = await stockItem(venueAId, 'Beef', 'kg');
    const flour = await stockItem(venueAId, 'Flour', 'kg');

    const saved = await recipes.save(a, {
      menuItemId: khinkali.id,
      yieldQuantity: '100',
      components: [
        { stockItemId: beef.id, quantity: '3.5', unit: 'kg' },
        { stockItemId: flour.id, quantity: '2.5', unit: 'kg' },
      ],
    });

    expect(saved.yieldQuantity).toBe('100.000');
    expect(saved.components[0].baseQuantity).toBe('3.500');
    expect(saved.components[0].baseQuantityPerUnit).toBe('0.035000');
    expect(saved.components[1].baseQuantityPerUnit).toBe('0.025000');
  });

  // ── Variants ────────────────────────────────────────────────────────────

  it('keeps variant-specific definitions on stable variant identity', async () => {
    const pizza = await menuItem(venueAId, 'Pizza', [30, 45]);
    const [small, large] = pizza.variants;
    const dough = await stockItem(venueAId, 'Dough', 'kg');
    const cheese = await stockItem(venueAId, 'Cheese', 'kg');

    await recipes.save(a, {
      menuItemId: pizza.id,
      variantId: small.id,
      components: [
        { stockItemId: dough.id, quantity: '200', unit: 'g' },
        { stockItemId: cheese.id, quantity: '80', unit: 'g' },
      ],
    });
    await recipes.save(a, {
      menuItemId: pizza.id,
      variantId: large.id,
      components: [
        { stockItemId: dough.id, quantity: '320', unit: 'g' },
        { stockItemId: cheese.id, quantity: '130', unit: 'g' },
      ],
    });

    const smallRecipe = await recipes.detail(tenantA, pizza.id, small.id);
    const largeRecipe = await recipes.detail(tenantA, pizza.id, large.id);
    expect(smallRecipe.recipe?.components[0].baseQuantity).toBe('0.200');
    expect(largeRecipe.recipe?.components[0].baseQuantity).toBe('0.320');
    expect(smallRecipe.recipe?.id).not.toBe(largeRecipe.recipe?.id);

    // Renaming the Menu Item does not move either definition.
    await prisma.menuItem.update({
      where: { id: pizza.id },
      data: { nameKa: 'Pizza Napoletana' },
    });
    const afterRename = await recipes.detail(tenantA, pizza.id, large.id);
    expect(afterRename.recipe?.id).toBe(largeRecipe.recipe?.id);
    expect(afterRename.recipe?.components[0].baseQuantity).toBe('0.320');
  });

  it('refuses a variant that belongs to another Menu Item', async () => {
    const pizza = await menuItem(venueAId, 'Pizza', [30]);
    const pasta = await menuItem(venueAId, 'Pasta', [1]);
    const dough = await stockItem(venueAId, 'Dough', 'kg');

    await expect(
      recipes.save(a, {
        menuItemId: pizza.id,
        variantId: pasta.variants[0].id,
        components: [{ stockItemId: dough.id, quantity: '1', unit: 'kg' }],
      }),
    ).rejects.toThrow(/Menu variant not found/);
  });

  // ── One definition per product ──────────────────────────────────────────

  it('edits the one definition rather than forking a second', async () => {
    const khinkali = await menuItem(venueAId, 'ხინკალი');
    const beef = await stockItem(venueAId, 'Beef', 'kg');
    const flour = await stockItem(venueAId, 'Flour', 'kg');

    const first = await recipes.save(a, {
      menuItemId: khinkali.id,
      components: [{ stockItemId: beef.id, quantity: '35', unit: 'g' }],
    });
    const second = await recipes.save(a, {
      menuItemId: khinkali.id,
      components: [
        { stockItemId: beef.id, quantity: '40', unit: 'g' },
        { stockItemId: flour.id, quantity: '25', unit: 'g' },
      ],
    });

    expect(second.id).toBe(first.id);
    expect(second.revision).toBe(first.revision + 1);
    expect(second.components).toHaveLength(2);
    expect(
      await prisma.menuConsumptionRecipe.count({
        where: { menuItemId: khinkali.id },
      }),
    ).toBe(1);
  });

  it('does not touch stock when a recipe is created, edited or disabled', async () => {
    const khinkali = await menuItem(venueAId, 'ხინკალი');
    const beef = await stockItem(venueAId, 'Beef', 'kg');
    const before = await inventory.currentStock(venueAId, [beef.id]);

    const saved = await recipes.save(a, {
      menuItemId: khinkali.id,
      components: [{ stockItemId: beef.id, quantity: '35', unit: 'g' }],
    });
    await recipes.save(a, {
      menuItemId: khinkali.id,
      components: [{ stockItemId: beef.id, quantity: '90', unit: 'g' }],
    });
    await recipes.disable(a, saved.id);

    expect(before.get(beef.id)).toBeUndefined();
    expect(
      (await inventory.currentStock(venueAId, [beef.id])).get(beef.id),
    ).toBeUndefined();
    expect(
      await prisma.stockMovement.count({ where: { venueId: venueAId } }),
    ).toBe(0);
  });

  it('disables idempotently and keeps the card readable', async () => {
    const cola = await menuItem(venueAId, 'Coca-Cola 0.5L');
    const stock = await stockItem(venueAId, 'Coca-Cola 0.5L', 'bottle');
    const saved = await recipes.save(a, {
      menuItemId: cola.id,
      components: [{ stockItemId: stock.id, quantity: '1', unit: 'bottle' }],
    });

    const first = await recipes.disable(a, saved.id);
    const second = await recipes.disable(a, saved.id);
    expect(first.result).toBe('disabled');
    expect(second.result).toBe('already_disabled');
    expect(second.revision).toBe(first.revision);
    expect(second.components).toHaveLength(1);
    // A disabled definition leaves the projection but not the database.
    expect(await recipes.projection(venueAId)).toEqual([]);
    expect(await recipes.usageForStockItem(tenantA, stock.id)).toEqual([]);
  });

  // ── Menu-oriented list ──────────────────────────────────────────────────

  it('lists every Menu Item, configured or not', async () => {
    const khinkali = await menuItem(venueAId, 'ხინკალი');
    await menuItem(venueAId, 'Burger');
    const beef = await stockItem(venueAId, 'Beef', 'kg');
    await recipes.save(a, {
      menuItemId: khinkali.id,
      components: [{ stockItemId: beef.id, quantity: '35', unit: 'g' }],
    });

    const all = await recipes.listMenuItems(tenantA);
    expect(all.map((row) => row.nameKa).sort()).toEqual(['Burger', 'ხინკალი']);
    expect(all.find((row) => row.nameKa === 'ხინკალი')?.recipe).toMatchObject({
      componentCount: 1,
      isActive: true,
    });
    expect(all.find((row) => row.nameKa === 'Burger')?.recipe).toBeNull();

    expect(
      (await recipes.listMenuItems(tenantA, { status: 'unconfigured' })).map(
        (row) => row.nameKa,
      ),
    ).toEqual(['Burger']);
    expect(
      (await recipes.listMenuItems(tenantA, { search: 'ხინკ' })).map(
        (row) => row.nameKa,
      ),
    ).toEqual(['ხინკალი']);
  });

  // ── Reverse lookup on the Stock Item ────────────────────────────────────

  it('shows a Stock Item which products consume it', async () => {
    const beef = await stockItem(venueAId, 'Beef', 'kg');
    const khinkali = await menuItem(venueAId, 'ხინკალი');
    const burger = await menuItem(venueAId, 'Burger');
    await recipes.save(a, {
      menuItemId: khinkali.id,
      components: [{ stockItemId: beef.id, quantity: '35', unit: 'g' }],
    });
    await recipes.save(a, {
      menuItemId: burger.id,
      components: [{ stockItemId: beef.id, quantity: '150', unit: 'g' }],
    });

    const detail = await inventory.getStockItem(tenantA, beef.id);
    expect(detail.usedBy).toHaveLength(2);
    expect(detail.usedBy.map((row) => row.menuItemName).sort()).toEqual([
      'Burger',
      'ხინკალი',
    ]);
    expect(detail.recipeUnits).toEqual(['g', 'kg']);
  });

  // ── POS projection ──────────────────────────────────────────────────────

  it('projects active definitions with both identities for the POS', async () => {
    const pizza = await menuItem(venueAId, 'Pizza', [30]);
    const dough = await stockItem(venueAId, 'Dough', 'kg');
    await recipes.save(a, {
      menuItemId: pizza.id,
      variantId: pizza.variants[0].id,
      yieldQuantity: '10',
      components: [{ stockItemId: dough.id, quantity: '2', unit: 'kg' }],
    });

    const catalog = await inventory.getCatalog(tenantA);
    expect(catalog.version).toBe(4);
    expect(catalog.recipes).toHaveLength(1);
    expect(catalog.recipes[0]).toMatchObject({
      menuItemId: pizza.id,
      posMenuItemId: pizza.posMenuItemId,
      variantId: pizza.variants[0].id,
      posMenuVariantId: pizza.variants[0].posMenuVariantId,
      revision: 1,
    });
    expect(catalog.recipes[0].components[0]).toMatchObject({
      stockItemId: dough.id,
      baseQuantityPerUnit: '0.200000',
      baseUnit: 'kg',
    });
  });

  // ── Audit ───────────────────────────────────────────────────────────────

  it('audits create, update and disable as summaries', async () => {
    const cola = await menuItem(venueAId, 'Coca-Cola 0.5L');
    const stock = await stockItem(venueAId, 'Coca-Cola 0.5L', 'bottle');
    const saved = await recipes.save(a, {
      menuItemId: cola.id,
      components: [{ stockItemId: stock.id, quantity: '1', unit: 'bottle' }],
    });
    await recipes.save(a, {
      menuItemId: cola.id,
      components: [{ stockItemId: stock.id, quantity: '2', unit: 'bottle' }],
    });
    await recipes.disable(a, saved.id);

    const rows = await prisma.auditEventLog.findMany({
      where: { venueId: venueAId, entityType: 'RECIPE' },
      orderBy: { createdAt: 'asc' },
    });
    expect(rows.map((row) => row.action)).toEqual([
      'RECIPE_CREATED',
      'RECIPE_UPDATED',
      'RECIPE_DISABLED',
    ]);
    expect(rows.every((row) => row.entityId === saved.id)).toBe(true);
    const created = rows[0].data as Record<string, unknown>;
    expect(created).toMatchObject({
      recipeId: saved.id,
      menuItemId: cola.id,
      componentCount: 1,
      source: 'MANAGER',
    });
    // A summary, not the card itself.
    expect(created).not.toHaveProperty('components');
  });

  // ── Tenancy ─────────────────────────────────────────────────────────────

  it('refuses to link across Venues and hides one Venue from another', async () => {
    const itemA = await menuItem(venueAId, 'ხინკალი');
    const itemB = await menuItem(venueBId, 'Foreign dish');
    const beefA = await stockItem(venueAId, 'Beef', 'kg');
    const beefB = await stockItem(venueBId, 'Foreign Beef', 'kg');

    // Venue A cannot recipe-link Venue B's Menu Item.
    await expect(
      recipes.save(a, {
        menuItemId: itemB.id,
        components: [{ stockItemId: beefA.id, quantity: '35', unit: 'g' }],
      }),
    ).rejects.toThrow(/Menu item not found/);

    // Venue A cannot consume Venue B's Stock Item.
    await expect(
      recipes.save(a, {
        menuItemId: itemA.id,
        components: [{ stockItemId: beefB.id, quantity: '35', unit: 'g' }],
      }),
    ).rejects.toThrow(/does not belong to this Venue/);

    const mine = await recipes.save(a, {
      menuItemId: itemA.id,
      components: [{ stockItemId: beefA.id, quantity: '35', unit: 'g' }],
    });

    // Venue B cannot read or disable it, and does not see it in its own list.
    await expect(recipes.detail(tenantB, itemA.id)).rejects.toThrow(
      /Menu item not found/,
    );
    await expect(recipes.disable(b, mine.id)).rejects.toThrow(
      /Recipe not found/,
    );
    expect((await recipes.listMenuItems(tenantB)).map((r) => r.nameKa)).toEqual(
      ['Foreign dish'],
    );
    expect(await recipes.projection(venueBId)).toEqual([]);
  });
});
