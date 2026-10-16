import 'reflect-metadata';
import { randomUUID } from 'node:crypto';
import type { Type } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../src/prisma.service';
import { JwtStrategy } from '../src/auth/jwt.strategy';
import { ManagerTenantService } from '../src/auth/manager-tenant.service';
import { VenueEntitlementsService } from '../src/entitlements/venue-entitlements.service';
import { MobileController } from '../src/mobile/mobile.controller';
import { MobileDashboardService } from '../src/mobile/services/mobile-dashboard.service';
import { MobileSaleLedgerService } from '../src/mobile/services/mobile-sale-ledger.service';
import { InventoryService } from '../src/inventory/inventory.service';
import { RecipeService } from '../src/inventory/recipe.service';
import { ReceivingService } from '../src/inventory/receiving.service';
import { SaleConsumptionService } from '../src/inventory/sale-consumption.service';
import { onboardingApp } from './onboarding-app.fixture';
import { isFreshDisposableDatabase } from './disposable-database';
import { grantTrialPlan } from './commercial-access.fixture';

export async function inventoryPhase8Fixture(url: string) {
  if (!isFreshDisposableDatabase(url))
    throw Error('Owned disposable database required');
  process.env.JWT_SECRET = 'inventory-phase8-synthetic-only';
  const db = new PrismaService({ datasourceUrl: url });
  await db.$connect();
  const recipes = new RecipeService(db);
  const inventory = new InventoryService(db, recipes);
  const receiving = new ReceivingService(db);
  const consumption = new SaleConsumptionService(db);
  const ledger = new MobileSaleLedgerService(db);
  const dashboard = new MobileDashboardService(
    db,
    {} as never,
    {} as never,
    {} as never,
    ledger,
  );
  const services = new Map<Type<unknown>, unknown>([
    [RecipeService, recipes],
    [InventoryService, inventory],
    [ReceivingService, receiving],
    [SaleConsumptionService, consumption],
    [MobileDashboardService, dashboard],
    [MobileSaleLedgerService, ledger],
  ]);
  const deps = Reflect.getMetadata(
    'design:paramtypes',
    MobileController,
  ) as Type<unknown>[];
  const app = await onboardingApp(db, undefined, {
    controllers: [MobileController],
    providers: [
      ...deps
        .filter((t) => t !== VenueEntitlementsService)
        .map((t) => ({ provide: t, useValue: services.get(t) ?? {} })),
      JwtStrategy,
      ManagerTenantService,
    ],
  });
  await app.listen(0, '127.0.0.1');
  const base = await app.getUrl();
  const org = await db.organization.create({
    data: { name: 'Synthetic Inventory Phase 8' },
  });
  async function venue() {
    const v = await db.venue.create({
      data: {
        organizationId: org.id,
        name: 'Synthetic restaurant',
        timezone: 'UTC',
        currency: 'GEL',
      },
    });
    await grantTrialPlan(db, v.id, 'POS_MANAGER');
    for (const key of ['INVENTORY', 'PROFITABILITY']) {
      const feature = await db.feature.findUniqueOrThrow({ where: { key } });
      await db.venueFeatureOverride.create({
        data: { venueId: v.id, featureId: feature.id, effect: 'ENABLED' },
      });
    }
    const staff = await db.staff.create({
      data: {
        venueId: v.id,
        username: randomUUID(),
        role: 'MANAGER',
        pinHash: 'not-a-login',
      },
    });
    const tenant = { venueId: v.id, organizationId: org.id };
    const actor = {
      ...tenant,
      staffId: staff.id,
      username: staff.username,
      role: 'MANAGER' as const,
    };
    return {
      tenant,
      actor,
      token: new JwtService({ secret: process.env.JWT_SECRET }).sign({
        sub: staff.id,
      }),
    };
  }
  const a = await venue(),
    b = await venue();
  async function get(path: string, token = a.token) {
    const r = await fetch(base + path, {
      headers: token ? { Authorization: 'Bearer ' + token } : {},
    });
    return {
      status: r.status,
      body: (await r.json()) as Record<string, unknown>,
    };
  }
  return {
    db,
    app,
    base,
    a,
    b,
    inventory,
    receiving,
    recipes,
    consumption,
    ledger,
    dashboard,
    get,
    close: async () => {
      await app.close();
      await db.$disconnect();
    },
  };
}
