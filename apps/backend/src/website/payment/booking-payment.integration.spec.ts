import 'reflect-metadata';
jest.mock('axios');
jest.mock('../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
import axios from 'axios';
const providerPost = jest.spyOn(axios, 'post');
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import { ValidationPipe, type INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import cookieParser from 'cookie-parser';
import request from 'supertest';
import type { SubscriptionStatus, WebsiteMode } from '@prisma/client';
import { PrismaService } from '../../prisma.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { encryptPaymentConfig } from '../../payment-integrations/payment-config.crypto';
import { PaymentIntegrationsService } from '../../payment-integrations/payment-integrations.service';
import { WebsiteAuthService } from '../auth/auth.service';
import { CryptoService } from '../common/crypto.service';
import { emptyWebsiteContent } from '../core/website-content';
import { MenuService } from '../menu/menu.service';
import { ReservationService } from '../reservation/reservation.service';
import { TableController } from '../reservation/reservation.controller';
import { WebsiteTenantService } from '../tenancy/website-tenant.service';
import { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import { BogController } from './payment.controller';
import { BogService } from './payment.service';

const url = process.env.SEC01_TEST_DATABASE_URL;
const routes = ['/api/bog/create-order', '/api/tables/reservations'];

// No default URL, migrations, reset or cleanup of a developer/customer database.
// The runner must first create and migrate its own uniquely named empty DB.
(url ? describe : describe.skip)(
  'SEC-01 disposable PostgreSQL / real HTTP',
  () => {
    let db: PrismaService;
    let app: INestApplication;
    let planId: string;
    let sessionUserId: string;
    let otherUserId: string;
    let sessionCookie: string;
    const fixtures: Array<{
      venueId: string;
      host: string;
      itemId: string;
      variantItemId: string;
      variantId: string;
      integrationId: string;
    }> = [];
    const tag = randomUUID();
    const originalKey = process.env.PAYMENT_INTEGRATION_MASTER_KEY;
    const originalCookieKey = process.env.COOKIE_ENCRYPTION_KEY;
    const http = () => request(app.getHttpServer() as Server);
    const body = (i: number, extra: Record<string, unknown> = {}) => ({
      selectedTables: ['table1'],
      selectedDate: '2026-12-10',
      selectedTime: '18:00',
      menuItems: [{ id: fixtures[i].itemId, quantity: 1 }],
      ...extra,
    });
    const post = (
      route: string,
      i: number,
      extra: Record<string, unknown> = {},
    ) => http().post(route).set('Host', fixtures[i].host).send(body(i, extra));
    const providerBodies = () =>
      providerPost.mock.calls
        .filter(([target]) => target.includes('/ecommerce/orders'))
        .map(
          ([, payload]) =>
            payload as {
              external_order_id: string;
              purchase_units: {
                currency: string;
                total_amount: number;
                basket: Array<{ unit_price: number }>;
              };
            },
        );

    beforeAll(async () => {
      const parsed = new URL(url!);
      if (
        !isFreshDisposableDatabase(parsed) ||
        !/^\/disposable_sec01_[a-z0-9_]+$/.test(parsed.pathname)
      )
        throw new Error(
          'SEC-01 requires a fresh, audit-owned disposable_sec01_* database on 127.0.0.1',
        );
      process.env.PAYMENT_INTEGRATION_MASTER_KEY = '31'.repeat(32);
      process.env.COOKIE_ENCRYPTION_KEY = 'sec01-synthetic-cookie-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const features = await db.feature.findMany({
        where: { key: { in: ['WEBSITE', 'ONLINE_PAYMENTS'] } },
      });
      expect(features).toHaveLength(2);
      const plan = await db.plan.create({
        data: {
          key: `sec01-${tag}`,
          name: 'SEC01 synthetic',
          features: {
            create: features.map((feature) => ({ featureId: feature.id })),
          },
        },
      });
      planId = plan.id;
      for (const mode of ['CUSTOM', 'SAAS'] satisfies WebsiteMode[]) {
        const org = await db.organization.create({
          data: { name: `SEC01 ${mode} ${tag}` },
        });
        const host = `sec01-${mode.toLowerCase()}-${tag}.localhost`;
        const venue = await db.venue.create({
          data: {
            name: `SEC01 ${mode}`,
            organizationId: org.id,
            currency: 'GEL',
            timezone: 'Asia/Tbilisi',
            websiteConfig: {
              create:
                mode === 'CUSTOM'
                  ? { mode }
                  : {
                      mode,
                      status: 'PUBLISHED',
                      slug: `sec01-${tag}`,
                      revision: 1,
                      publishedRevision: 1,
                      publishedAt: new Date(),
                      published: {
                        ...emptyWebsiteContent,
                        slug: `sec01-${tag}`,
                      },
                    },
            },
            domains: { create: { hostname: host } },
            planAssignment: { create: { planId } },
            subscription: { create: { status: 'ACTIVE' } },
          },
        });
        await db.websiteTable.create({
          data: {
            venueId: venue.id,
            websiteTableNumber: 'table1',
            posTableNumber: '1',
            posFloor: 'first',
          },
        });
        const item = await db.menuItem.create({
          data: {
            venueId: venue.id,
            nameEn: 'Meal',
            nameKa: 'Meal',
            price: 100,
          },
        });
        const variantItem = await db.menuItem.create({
          data: {
            venueId: venue.id,
            nameEn: 'Drink',
            nameKa: 'Drink',
            price: 0,
            variants: {
              create: [
                { size: 0.5, price: 10 },
                { size: 1, price: 20 },
              ],
            },
          },
          include: { variants: { orderBy: { price: 'desc' } } },
        });
        const integrationId = randomUUID();
        await db.paymentIntegration.create({
          data: {
            id: integrationId,
            venueId: venue.id,
            provider: 'BOG',
            revision: 1,
            encryptedConfig: encryptPaymentConfig(venue.id, integrationId, {
              clientId: `client-${mode}`,
              clientSecret: `synthetic-${mode}`,
              returnOrigin: `http://${host}`,
            }),
          },
        });
        fixtures.push({
          venueId: venue.id,
          host,
          itemId: item.id,
          variantItemId: variantItem.id,
          variantId: variantItem.variants[0].id,
          integrationId,
        });
      }
      const entitlements = new VenueEntitlementsService(db);
      const integrations = new PaymentIntegrationsService(db, entitlements);
      const bog = new BogService(new MenuService(db), integrations, db);
      const reservations = new ReservationService(db, bog, {
        areWebsiteTablesAvailable: () => Promise.resolve(true),
      } as never);
      const crypto = new CryptoService();
      const auth = new WebsiteAuthService(
        db,
        new JwtService(),
        new ConfigService({
          JWT_SECRET: 'sec01-synthetic-signing-key',
          JWT_REFRESH_SECRET: 'sec01-synthetic-refresh-key',
        }),
        crypto,
      );
      for (const identity of ['session', 'other']) {
        const user = await db.websiteUser.create({
          data: { phone: `sec01-${identity}-${tag}`, password: 'unused' },
        });
        if (identity === 'session') {
          sessionUserId = user.id;
          const tokens = await auth.signToken(user.id, user.phone, user.role);
          sessionCookie = `access_token=${encodeURIComponent(crypto.encrypt(tokens.access_token))}`;
        } else otherUserId = user.id;
      }
      const module = await Test.createTestingModule({
        controllers: [BogController, TableController],
        providers: [
          { provide: BogService, useValue: bog },
          { provide: ReservationService, useValue: reservations },
          {
            provide: WebsiteAuthService,
            useValue: auth,
          },
          { provide: VenueEntitlementsService, useValue: entitlements },
          {
            provide: WebsiteCapabilitiesService,
            useValue: new WebsiteCapabilitiesService(db, entitlements),
          },
          {
            provide: WebsiteTenantService,
            useValue: new WebsiteTenantService(
              db,
              new ConfigService({ NODE_ENV: 'production' }),
            ),
          },
        ],
      }).compile();
      app = module.createNestApplication({ rawBody: true });
      app.use(cookieParser());
      app.useGlobalPipes(
        new ValidationPipe({
          whitelist: true,
          forbidNonWhitelisted: true,
          transform: true,
        }),
      );
      await app.init();
    });

    beforeEach(() => {
      expect(jest.isMockFunction(providerPost)).toBe(true);
      providerPost.mockReset();
      providerPost.mockImplementation((target: string) =>
        Promise.resolve({
          data: target.includes('openid-connect')
            ? { access_token: 'synthetic-token' }
            : {
                id: `synthetic-bank-${randomUUID()}`,
                _links: { redirect: { href: 'https://bank.invalid/fake' } },
              },
        }),
      );
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
      if (originalKey === undefined)
        delete process.env.PAYMENT_INTEGRATION_MASTER_KEY;
      else process.env.PAYMENT_INTEGRATION_MASTER_KEY = originalKey;
      if (originalCookieKey === undefined)
        delete process.env.COOKIE_ENCRYPTION_KEY;
      else process.env.COOKIE_ENCRYPTION_KEY = originalCookieKey;
    });

    describe.each(routes)('%s', (route) => {
      it.each([0, 1])(
        'prices normal and forged money identically for CUSTOM/SAAS fixture %i',
        async (i) => {
          await post(route, i).expect(201);
          await post(route, i, {
            venueId: fixtures[1 - i].venueId,
            totalAmount: 1,
            serviceCharge: -100,
            serviceFee: 0,
            currency: 'USD',
            menuItems: [{ id: fixtures[i].itemId, quantity: 1, price: 0.01 }],
          }).expect(201);
          for (const payload of providerBodies()) {
            const stored = await db.websiteReservation.findUniqueOrThrow({
              where: { id: payload.external_order_id },
            });
            expect(stored).toMatchObject({
              venueId: fixtures[i].venueId,
              totalAmount: 110,
              paymentIntegrationId: fixtures[i].integrationId,
            });
            expect(JSON.parse(stored.menuItems!)).toMatchObject([
              { price: 100, quantity: 1 },
            ]);
            expect(payload.purchase_units).toMatchObject({
              currency: 'GEL',
              total_amount: 110,
              basket: [{ unit_price: 110 }],
            });
          }
          expect(providerBodies()).toHaveLength(2);
        },
      );

      it.each([0, -1, 1.5, '2', null, 1001])(
        'rejects invalid quantity %p before persistence',
        async (quantity) => {
          const before = await db.websiteReservation.count();
          await post(route, 0, {
            menuItems: [{ id: fixtures[0].itemId, quantity }],
          }).expect(400);
          expect(await db.websiteReservation.count()).toBe(before);
          expect(providerPost).not.toHaveBeenCalled();
        },
      );

      it('rejects aggregate quantity overflow and oversized carts before persistence', async () => {
        const before = await db.websiteReservation.count();
        for (const menuItems of [
          Array.from({ length: 101 }, () => ({
            id: fixtures[0].itemId,
            quantity: 1,
          })),
          Array.from({ length: 2 }, () => ({
            id: fixtures[0].itemId,
            quantity: 600,
          })),
        ])
          await post(route, 0, { menuItems }).expect(400);
        expect(await db.websiteReservation.count()).toBe(before);
        expect(providerPost).not.toHaveBeenCalled();
      });

      it('takes identity from the encrypted session cookie and ignores body userId', async () => {
        await http()
          .post(route)
          .set('Host', fixtures[0].host)
          .set('Cookie', sessionCookie)
          .send(body(0, { userId: otherUserId }))
          .expect(201);
        await post(route, 0, { userId: otherUserId }).expect(201);
        const userIds: Array<string | null> = [];
        for (const payload of providerBodies()) {
          const stored = await db.websiteReservation.findUniqueOrThrow({
            where: { id: payload.external_order_id },
          });
          userIds.push(stored.userId);
        }
        expect(userIds).toEqual([sessionUserId, null]);
      });

      it('rejects foreign/missing item IDs and foreign/mismatched variants', async () => {
        const a = fixtures[0],
          b = fixtures[1];
        const before = await db.websiteReservation.count();
        for (const line of [
          { id: b.itemId, quantity: 1 },
          { id: randomUUID(), quantity: 1 },
          { id: a.variantItemId, variantId: b.variantId, quantity: 1 },
          { id: a.itemId, variantId: a.variantId, quantity: 1 },
          { id: b.variantId, quantity: 1 },
          { id: a.variantItemId, quantity: 1 },
        ])
          await post(route, 0, { menuItems: [line] }).expect(400);
        expect(await db.websiteReservation.count()).toBe(before);
        expect(providerPost).not.toHaveBeenCalled();
      });

      it('rejects disabled and hidden menu items', async () => {
        const itemId = fixtures[0].itemId;
        const before = await db.websiteReservation.count();
        try {
          await db.menuItem.update({
            where: { id: itemId },
            data: { enabled: false },
          });
          await post(route, 0).expect(400);
          await db.menuItem.update({
            where: { id: itemId },
            data: { enabled: true },
          });
          await db.menuItemWebsitePresentation.create({
            data: {
              menuItemId: itemId,
              venueId: fixtures[0].venueId,
              visibleOnWebsite: false,
            },
          });
          await post(route, 0).expect(400);
          expect(await db.websiteReservation.count()).toBe(before);
          expect(providerPost).not.toHaveBeenCalled();
        } finally {
          await db.menuItem.update({
            where: { id: itemId },
            data: { enabled: true },
          });
          await db.menuItemWebsitePresentation.deleteMany({
            where: { menuItemId: itemId },
          });
        }
      });

      it('accepts the selected variant and the existing Vankisi variant-ID payload', async () => {
        const a = fixtures[0];
        for (const line of [
          { id: a.variantItemId, variantId: a.variantId, quantity: 2 },
          { id: a.variantId, quantity: 2 },
        ]) {
          await post(route, 0, { menuItems: [line], totalAmount: 1 }).expect(
            201,
          );
        }
        expect(
          providerBodies().map((p) => p.purchase_units.total_amount),
        ).toEqual([44, 44]);
      });

      it.each(['ONLINE_PAYMENTS', 'RESERVATIONS'] as const)(
        'enforces the operator %s switch',
        async (capability) => {
          const venueId = fixtures[0].venueId;
          try {
            await db.venueWebsiteCapability.create({
              data: { venueId, capability, enabled: false },
            });
            await post(route, 0).expect(404);
            expect(providerPost).not.toHaveBeenCalled();
          } finally {
            await db.venueWebsiteCapability.deleteMany({
              where: { venueId, capability },
            });
          }
        },
      );

      it('fails closed for a disabled integration', async () => {
        const id = fixtures[0].integrationId;
        try {
          await db.paymentIntegration.update({
            where: { id },
            data: { enabled: false },
          });
          await post(route, 0).expect(403);
          expect(providerPost).not.toHaveBeenCalled();
        } finally {
          await db.paymentIntegration.update({
            where: { id },
            data: { enabled: true },
          });
        }
      });

      it('fails closed when an entitled Venue has no payment integration', async () => {
        const host = `sec01-missing-${randomUUID()}.localhost`;
        const venue = await db.venue.create({
          data: {
            name: 'SEC01 missing integration',
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            organization: { create: { name: 'SEC01 missing integration' } },
            websiteConfig: { create: { mode: 'CUSTOM' } },
            domains: { create: { hostname: host } },
            planAssignment: { create: { planId } },
            subscription: { create: { status: 'ACTIVE' } },
          },
        });
        await db.websiteTable.create({
          data: {
            venueId: venue.id,
            websiteTableNumber: 'table1',
            posTableNumber: '1',
            posFloor: 'first',
          },
        });
        const item = await db.menuItem.create({
          data: {
            venueId: venue.id,
            nameEn: 'Meal',
            nameKa: 'Meal',
            price: 100,
          },
        });
        const before = await db.websiteReservation.count();
        await http()
          .post(route)
          .set('Host', host)
          .send(body(0, { menuItems: [{ id: item.id, quantity: 1 }] }))
          .expect(403);
        expect(await db.websiteReservation.count()).toBe(before);
        expect(providerPost).not.toHaveBeenCalled();
      });

      it.each([
        'NO_PLAN',
        'SUSPENDED',
        'CANCELLED',
        'TRIAL',
      ] satisfies SubscriptionStatus[])(
        'denies commercial state %s (TRIAL is expired)',
        async (status) => {
          const venueId = fixtures[0].venueId;
          try {
            await db.venueSubscription.update({
              where: { venueId },
              data: {
                status,
                trialEndsAt:
                  status === 'TRIAL' ? new Date(Date.now() - 60000) : null,
              },
            });
            // Expiry reconciliation may disable the domain before feature checks.
            const result = await post(route, 0);
            expect([403, 404]).toContain(result.status);
            expect(providerPost).not.toHaveBeenCalled();
          } finally {
            await db.venueSubscription.update({
              where: { venueId },
              data: { status: 'ACTIVE', trialEndsAt: null },
            });
            await db.venueDomain.updateMany({
              where: { venueId },
              data: { status: 'ACTIVE' },
            });
          }
        },
      );

      it('rejects unknown/disabled Host or disabled Venue despite a supplied venueId', async () => {
        await http()
          .post(route)
          .set('Host', 'unknown.invalid')
          .send(body(0, { venueId: fixtures[0].venueId }))
          .expect(404);
        try {
          await db.venueDomain.update({
            where: { hostname: fixtures[0].host },
            data: { status: 'DISABLED' },
          });
          await post(route, 0).expect(404);
          await db.venueDomain.update({
            where: { hostname: fixtures[0].host },
            data: { status: 'ACTIVE' },
          });
          await db.venue.update({
            where: { id: fixtures[0].venueId },
            data: { status: 'DISABLED' },
          });
          await post(route, 0).expect(404);
          expect(providerPost).not.toHaveBeenCalled();
        } finally {
          await db.venue.update({
            where: { id: fixtures[0].venueId },
            data: { status: 'ACTIVE' },
          });
          await db.venueDomain.update({
            where: { hostname: fixtures[0].host },
            data: { status: 'ACTIVE' },
          });
        }
      });
    });

    it('still rejects forged callbacks before reservation mutation', async () => {
      const before = await db.websiteReservation.findMany({
        select: { id: true, status: true, paymentStatus: true },
      });
      await http()
        .post('/api/bog/payment-callback')
        .send({
          event: 'order_payment',
          body: {
            external_order_id: before[0]?.id,
            order_status: { key: 'completed' },
          },
        })
        .expect(401);
      expect(
        await db.websiteReservation.findMany({
          select: { id: true, status: true, paymentStatus: true },
        }),
      ).toEqual(before);
      expect(providerPost).not.toHaveBeenCalled();
    });
  },
);
