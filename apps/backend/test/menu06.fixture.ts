import { supportedMenuClientHeader } from './menu-client.fixture';
import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { PrismaService } from '../src/prisma.service';
import { MenuCatalogService } from '../src/menu-catalog/menu-catalog.service';
import { EdgeTransportController } from '../src/edge/edge-transport.controller';
import { InventoryService } from '../src/inventory/inventory.service';
import { RecipeService } from '../src/inventory/recipe.service';
import { ReceivingService } from '../src/inventory/receiving.service';
import { SaleConsumptionService } from '../src/inventory/sale-consumption.service';
import { MenuController } from '../src/website/menu/menu.controller';
import { MenuService } from '../src/website/menu/menu.service';
import { WebsiteVenueController } from '../src/website/core/website-venue.controller';
import { WebsiteVenueService } from '../src/website/core/website-venue.service';
import { onboardingApp } from './onboarding-app.fixture';
import { isFreshDisposableDatabase } from './disposable-database';
import { seedMenu03, type Menu03Venue } from './menu03.fixture';

function identity(row: unknown): string {
  if (
    !row ||
    typeof row !== 'object' ||
    !('id' in row) ||
    typeof row.id !== 'string'
  )
    throw Error('Fixture setup did not return a durable identity');
  return row.id;
}

export async function menu06App(url: string) {
  if (!isFreshDisposableDatabase(url)) throw Error('Disposable DB required');
  process.env.JWT_SECRET = 'menu06-disposable-signing-only';
  process.env.COOKIE_ENCRYPTION_KEY = 'menu06-disposable-cookie-only';
  const db = new PrismaService({ datasourceUrl: url });
  const app = await onboardingApp(db, undefined, {
    controllers: [
      EdgeTransportController,
      MenuController,
      WebsiteVenueController,
    ],
    providers: [
      InventoryService,
      RecipeService,
      ReceivingService,
      SaleConsumptionService,
      MenuService,
      WebsiteVenueService,
    ],
  });
  await app.listen(0, '127.0.0.1');
  return { app, db, base: await app.getUrl() };
}

export async function seedMenu06(db: PrismaService, app: INestApplication) {
  const fixture = await seedMenu03(db, app);
  const venues: (Menu03Venue & { host: string })[] = [];
  for (const [index, venue] of fixture.venues.entries()) {
    const assignment = await db.venuePlanAssignment.findUniqueOrThrow({
      where: { venueId: venue.venueId },
    });
    for (const key of ['POS', 'INVENTORY', 'PROFITABILITY']) {
      const feature = await db.feature.upsert({
        where: { key },
        create: { key, name: key },
        update: {},
      });
      await db.planFeature.upsert({
        where: {
          planId_featureId: {
            planId: assignment.planId,
            featureId: feature.id,
          },
        },
        create: { planId: assignment.planId, featureId: feature.id },
        update: {},
      });
    }
    const device = await db.device.findFirstOrThrow({
      where: { venueId: venue.venueId },
    });
    await db.venue.update({
      where: { id: venue.venueId },
      data: { activeOperationalDeviceId: device.id },
    });
    const host = `${randomUUID()}.menu06.localhost`;
    await db.venueWebsiteConfig.create({
      data: {
        venueId: venue.venueId,
        mode: index === 0 ? 'SAAS' : 'CUSTOM',
        status: 'PUBLISHED',
        slug: host.split('.')[0],
        assignedSlug: host.split('.')[0],
        revision: 1,
        published: { showMenu: true },
        publishedRevision: 1,
        publishedAt: new Date(),
      },
    });
    await db.venueDomain.create({
      data: { venueId: venue.venueId, hostname: host },
    });
    venues.push({ ...venue, host });
  }
  return { venues };
}

export async function menu06Http(
  base: string,
  venue: Menu03Venue,
  path: string,
  body?: unknown,
  method = body === undefined ? 'GET' : 'POST',
  owner = false,
) {
  const response = await fetch(base + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Vynic-Menu-Client': supportedMenuClientHeader,
      ...(owner
        ? { Authorization: `Bearer ${venue.ownerToken}` }
        : { 'X-POS-Sync-Key': venue.credential }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return {
    status: response.status,
    body: (await response.json()) as Record<string, unknown>,
  };
}

export async function menu06Product(
  db: PrismaService,
  app: INestApplication,
  venue: Menu03Venue,
  variants = false,
) {
  const categoryId: string = randomUUID();
  const subcategoryId: string = randomUUID();
  const itemId: string = randomUUID();
  const variantId: string = randomUUID();
  const catalog = app.get(MenuCatalogService);
  const actor = {
    type: 'DEVICE' as const,
    id: 'synthetic-setup',
    source: 'POS',
  };
  const create = (
    entityType: 'CATEGORY' | 'SUBCATEGORY' | 'ITEM' | 'VARIANT',
    entityId: string,
    patch: object,
  ) =>
    catalog.apply(venue.venueId, actor, {
      mutationId: randomUUID(),
      entityType,
      entityId,
      operation: 'UPSERT',
      expectedRevision: 0,
      patch,
    });
  await create('CATEGORY', categoryId, {
    nameKa: 'Synthetic',
    nameEn: 'Synthetic',
  });
  await create('SUBCATEGORY', subcategoryId, {
    categoryId,
    nameKa: 'Synthetic',
    nameEn: 'Synthetic',
  });
  await create('ITEM', itemId, {
    subcategoryId,
    nameKa: 'Synthetic flour dish',
    nameEn: 'Synthetic flour dish',
    price: 10,
  });
  if (variants)
    await create('VARIANT', variantId, {
      menuItemId: itemId,
      size: 1,
      price: 10,
    });
  const venueRow = await db.venue.findUniqueOrThrow({
    where: { id: venue.venueId },
  });
  const tenant = {
    organizationId: venueRow.organizationId,
    venueId: venue.venueId,
    staffId: 'synthetic-manager',
    username: 'Synthetic manager',
    role: 'MANAGER' as const,
  };
  const inventory = app.get(InventoryService),
    recipes = app.get(RecipeService),
    receiving = app.get(ReceivingService);
  const stockId = identity(
    await inventory.createStockItem(tenant, {
      name: 'Synthetic flour ' + randomUUID(),
      baseUnit: 'kg',
    }),
  );
  await recipes.save(tenant, {
    menuItemId: itemId,
    ...(variants ? { variantId } : {}),
    components: [{ stockItemId: stockId, quantity: '0.200', unit: 'kg' }],
  });
  const recipe = (await recipes.projection(venue.venueId)).find(
    (r) => r.menuItemId === itemId,
  )!;
  const supplierId = identity(
    await inventory.createSupplier(tenant, {
      name: 'Synthetic supplier ' + randomUUID(),
    }),
  );
  const receivingId = identity(
    await receiving.createDraft(tenant, {
      supplierId,
      documentDate: '2026-10-01',
      lines: [
        {
          stockItemId: stockId,
          enteredQuantity: '10',
          enteredUnit: 'kg',
          unitPurchaseCost: '3',
        },
      ],
    }),
  );
  await receiving.post(tenant, receivingId);
  await db.menuItemWebsitePresentation.create({
    data: {
      venueId: venue.venueId,
      menuItemId: itemId,
      displayName: 'Preserved public name',
      description: 'Preserved configuration',
      sortOrder: 7,
    },
  });
  return {
    categoryId,
    subcategoryId,
    itemId,
    variantId: variants ? variantId : null,
    recipe,
    stockId,
    tenant,
  };
}

export function menu06Intent(
  product: Awaited<ReturnType<typeof menu06Product>>,
) {
  return {
    posSaleId: randomUUID(),
    closureId: randomUUID(),
    orderId: 6,
    businessDate: '2026-10-01',
    closedAt: '2026-10-01T10:00:00.000Z',
    snapshot: {
      version: 1,
      policy: 'FISCAL_CLOSE',
      catalogGeneratedAt: '2026-10-01T09:00:00.000Z',
      lines: [
        {
          lineSeq: 0,
          itemName: 'Captured historical name',
          menuItemId: product.itemId,
          variantId: product.variantId,
          soldQuantity: 10,
          status: 'MAPPED',
          reason: null,
          recipeId: product.recipe.recipeId,
          recipeRevision: product.recipe.revision,
          components: product.recipe.components.map((c) => ({
            ...c,
            totalBaseQuantity: '2.000000',
          })),
        },
      ],
    },
  };
}
