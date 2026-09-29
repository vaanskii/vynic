import 'reflect-metadata';
jest.mock('axios');
jest.mock('../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
import axios from 'axios';
const providerPost = jest.spyOn(axios, 'post');
import {
  BadRequestException,
  ForbiddenException,
  type ExecutionContext,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import type { PrismaService } from '../../prisma.service';
import type { PaymentIntegrationsService } from '../../payment-integrations/payment-integrations.service';
import type { WebsiteAuthService } from '../auth/auth.service';
import { MenuService } from '../menu/menu.service';
import { ReservationService } from '../reservation/reservation.service';
import { TableController } from '../reservation/reservation.controller';
import { WebsiteCapabilityGuard } from '../tenancy/website-capability.guard';
import type { WebsiteCapabilitiesService } from '../tenancy/website-capabilities.service';
import { BogController } from './payment.controller';
import { BogService } from './payment.service';
import {
  bookingAmountInGel,
  type BookingPaymentIntent,
} from './booking-pricing';

const tenant = { venueId: 'venue-a', organizationId: 'org-a' };
const request = {} as Request;
const routes = ['bog', 'tables'] as const;
const input = (overrides: Record<string, unknown> = {}) => ({
  selectedTables: ['table1'],
  selectedDate: '2026-12-10',
  selectedTime: '18:00',
  menuItems: [{ id: 'meal', quantity: 1 }],
  ...overrides,
});

function setup() {
  const catalog: Array<{
    id: string;
    venueId: string;
    price: number;
    enabled: boolean;
    nameEn: string;
    nameKa: string;
    variants: Array<{ id: string; size: number; price: number }>;
    websitePresentation: { visibleOnWebsite: boolean } | null;
  }> = [
    {
      id: 'meal',
      venueId: 'venue-a',
      price: 100,
      enabled: true,
      nameEn: 'Meal',
      nameKa: 'Meal',
      variants: [],
      websitePresentation: null,
    },
    {
      id: 'foreign',
      venueId: 'venue-b',
      price: 1,
      enabled: true,
      nameEn: 'Foreign',
      nameKa: 'Foreign',
      variants: [{ id: 'foreign-v', size: 1, price: 1 }],
      websitePresentation: null,
    },
    {
      id: 'disabled',
      venueId: 'venue-a',
      price: 1,
      enabled: false,
      nameEn: 'Disabled',
      nameKa: 'Disabled',
      variants: [],
      websitePresentation: null,
    },
    {
      id: 'hidden',
      venueId: 'venue-a',
      price: 1,
      enabled: true,
      nameEn: 'Hidden',
      nameKa: 'Hidden',
      variants: [],
      websitePresentation: { visibleOnWebsite: false },
    },
    {
      id: 'drink',
      venueId: 'venue-a',
      price: 0,
      enabled: true,
      nameEn: 'Drink',
      nameKa: 'Drink',
      variants: [
        { id: 'small', size: 0.5, price: 10 },
        { id: 'large', size: 1, price: 20 },
      ],
      websitePresentation: null,
    },
    {
      id: 'decimal',
      venueId: 'venue-a',
      price: 0.35,
      enabled: true,
      nameEn: 'Decimal',
      nameKa: 'Decimal',
      variants: [],
      websitePresentation: null,
    },
  ];
  const table = {
    id: 'table-a',
    venueId: tenant.venueId,
    posFloor: 'first',
    websiteTableNumber: 'table1',
    posTableNumber: '1',
    capacity: 4,
  };
  type Stored = {
    venueId: string;
    totalAmount: number;
    menuItems: string;
    userId?: string;
  };
  const stored: Stored[] = [];
  const db = {
    menuItem: {
      findFirst: jest.fn(
        ({ where }: { where: { id: string; venueId: string } }) =>
          Promise.resolve(
            catalog.find(
              (item) => item.id === where.id && item.venueId === where.venueId,
            ) ?? null,
          ),
      ),
    },
    menuItemVariant: {
      findFirst: jest.fn(
        ({
          where,
        }: {
          where: { id: string; menuItem: { venueId: string } };
        }) => {
          const item = catalog.find(
            (item) =>
              item.venueId === where.menuItem.venueId &&
              item.variants.some((v) => v.id === where.id),
          );
          return Promise.resolve(
            item
              ? {
                  ...item.variants.find((v) => v.id === where.id),
                  menuItem: item,
                }
              : null,
          );
        },
      ),
    },
    websiteTable: { findMany: jest.fn().mockResolvedValue([table]) },
    websiteReservation: {
      create: jest.fn(
        ({ data }: { data: Stored & { date: Date; timeSlot: string } }) => {
          stored.push(data);
          return Promise.resolve({
            ...data,
            id: 'reservation-a',
            status: 'PENDING',
            tables: [{ table }],
            user: null,
          });
        },
      ),
      update: jest.fn().mockResolvedValue({}),
    },
  };
  const integrations = {
    requireEnabled: jest.fn().mockResolvedValue({ id: 'integration-a' }),
    credentials: jest.fn().mockResolvedValue({
      clientId: 'synthetic',
      clientSecret: 'synthetic',
      returnOrigin: 'https://a.invalid',
    }),
  };
  const bog = new BogService(
    new MenuService(db as unknown as PrismaService),
    integrations as unknown as PaymentIntegrationsService,
    db as unknown as PrismaService,
  );
  const reservations = new ReservationService(
    db as unknown as PrismaService,
    bog,
    { areWebsiteTablesAvailable: jest.fn().mockResolvedValue(true) } as never,
  );
  const auth = {
    tryGetUserFromRequest: jest
      .fn()
      .mockResolvedValue({ id: 'session-account' }),
  };
  const bogController = new BogController(
    bog,
    reservations,
    auth as unknown as WebsiteAuthService,
  );
  const tableController = new TableController(
    reservations,
    auth as unknown as WebsiteAuthService,
  );
  providerPost.mockImplementation((url: string) =>
    Promise.resolve({
      data: url.includes('openid-connect')
        ? { access_token: 'fake-token' }
        : {
            id: 'fake-order',
            _links: { redirect: { href: 'https://bank.invalid/fake' } },
          },
    }),
  );
  const create = (route: (typeof routes)[number], body: unknown) =>
    route === 'bog'
      ? bogController.createOrder(tenant, request, body)
      : tableController.createReservation(tenant, body, request);
  const provider = () =>
    providerPost.mock.calls.find(([url]) =>
      url.includes('/ecommerce/orders'),
    )?.[1] as {
      external_order_id: string;
      purchase_units: {
        currency: string;
        total_amount: number;
        basket: Array<{ unit_price: number }>;
      };
    };
  return { create, stored, db, integrations, provider, bog, catalog };
}

beforeEach(() => jest.resetAllMocks());

describe.each(routes)(
  'SEC-01 %s creation boundary (mock persistence/provider)',
  (route) => {
    it('prices a normal cart once and persists exactly the provider amount', async () => {
      const f = setup();
      await f.create(route, input());
      expect(f.stored[0].totalAmount).toBe(110);
      expect(f.provider().purchase_units).toMatchObject({
        currency: 'GEL',
        total_amount: 110,
        basket: [{ unit_price: 110 }],
      });
      expect(f.db.menuItem.findFirst).toHaveBeenCalledTimes(1);
      expect(f.stored[0].userId).toBe('session-account');
    });

    it.each([1, 0, -50, 99999, '1', null, { amount: 1 }])(
      'legacy client money cannot change the payable amount: %p',
      async (totalAmount) => {
        const f = setup();
        await f.create(
          route,
          input({
            totalAmount,
            currency: 'USD',
            serviceCharge: -100,
            serviceFee: 0,
            payment: { amountMinor: 1, currency: 'USD' },
            venueId: 'venue-b',
            userId: 'victim',
            menuItems: [
              {
                id: 'meal',
                quantity: 1,
                price: 0.01,
                total: 0.01,
                name: 'Fake',
              },
            ],
          }),
        );
        expect(f.stored[0]).toMatchObject({
          venueId: 'venue-a',
          totalAmount: 110,
          userId: 'session-account',
        });
        expect(JSON.parse(f.stored[0].menuItems)).toMatchObject([
          { id: 'meal', price: 100, name: 'Meal', quantity: 1 },
        ]);
        expect(f.provider().purchase_units.total_amount).toBe(110);
        expect(f.provider().purchase_units.currency).toBe('GEL');
      },
    );

    it.each([
      [{ id: 'foreign', quantity: 1 }],
      [{ id: 'missing', quantity: 1 }],
      [{ id: 'disabled', quantity: 1 }],
      [{ id: 'hidden', quantity: 1 }],
      [{ id: 'drink', variantId: 'foreign-v', quantity: 1 }],
      [{ id: 'meal', variantId: 'small', quantity: 1 }],
      [{ id: 'foreign-v', quantity: 1 }],
      [{ id: 'drink', quantity: 1 }],
      [{ id: 'small', variantId: 'large', quantity: 1 }],
    ])(
      'rejects missing, foreign, unavailable or ambiguous selections %j',
      async (line) => {
        const f = setup();
        await expect(
          f.create(route, input({ menuItems: [line] })),
        ).rejects.toBeInstanceOf(BadRequestException);
        expect(f.stored).toHaveLength(0);
        expect(providerPost).not.toHaveBeenCalled();
      },
    );

    it.each([
      0,
      -1,
      1.5,
      '2',
      null,
      undefined,
      NaN,
      Infinity,
      1001,
      Number.MAX_SAFE_INTEGER,
    ])(
      'rejects invalid quantity %p without a write/provider call',
      async (quantity) => {
        const f = setup();
        await expect(
          f.create(route, input({ menuItems: [{ id: 'meal', quantity }] })),
        ).rejects.toBeInstanceOf(BadRequestException);
        expect(f.stored).toHaveLength(0);
        expect(providerPost).not.toHaveBeenCalled();
      },
    );

    it('bounds duplicate quantities and cart size', async () => {
      const f = setup();
      for (const cart of [
        Array.from({ length: 101 }, () => ({ id: 'meal', quantity: 1 })),
        [
          { id: 'meal', quantity: 600 },
          { id: 'meal', quantity: 600 },
        ],
      ]) {
        await expect(
          f.create(route, input({ menuItems: cart })),
        ).rejects.toBeInstanceOf(BadRequestException);
      }
      expect(f.stored).toHaveLength(0);
    });

    it.each([
      { id: 'drink', variantId: 'large', quantity: 2 },
      { id: 'large', quantity: 2 },
    ])(
      'prices the exact selected variant, including Vankisi legacy IDs: %j',
      async (line) => {
        const f = setup();
        await f.create(route, input({ menuItems: [line] }));
        expect(f.stored[0].totalAmount).toBe(44);
        expect(JSON.parse(f.stored[0].menuItems)).toMatchObject([
          { id: 'drink', variantId: 'large', price: 20, quantity: 2 },
        ]);
        expect(f.provider().purchase_units.total_amount).toBe(44);
      },
    );

    it('preserves the table-only 1 GEL minimum', async () => {
      const f = setup();
      await f.create(route, input({ menuItems: [], totalAmount: 100 }));
      expect(f.stored[0].totalAmount).toBe(1);
      expect(f.provider().purchase_units.total_amount).toBe(1);
    });

    it('uses exact minor-unit subtotal and half-up service rounding', async () => {
      const f = setup();
      await f.create(
        route,
        input({ menuItems: [{ id: 'decimal', quantity: 3 }] }),
      );
      expect(f.stored[0].totalAmount).toBe(1.16); // 1.05 + 0.105 -> 0.11
      expect(f.provider().purchase_units.total_amount).toBe(1.16);
    });

    it('fails closed before persistence when the integration/entitlement is unavailable', async () => {
      const f = setup();
      f.integrations.requireEnabled.mockRejectedValue(new ForbiddenException());
      await expect(f.create(route, input())).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(f.stored).toHaveLength(0);
      expect(providerPost).not.toHaveBeenCalled();
    });

    it.each([
      null,
      [],
      {},
      input({ menuItems: null }),
      input({ menuItems: {} }),
      input({ selectedTables: 'table1' }),
    ])('rejects malformed runtime DTO %j', async (body) => {
      const f = setup();
      await expect(f.create(route, body)).rejects.toBeInstanceOf(
        BadRequestException,
      );
      expect(f.stored).toHaveLength(0);
    });

    it('declares payment capability on the actual creation handler', async () => {
      const controller = route === 'bog' ? BogController : TableController;
      const handler = Reflect.get(
        controller.prototype,
        route === 'bog' ? 'createOrder' : 'createReservation',
      ) as BogController['createOrder'] | TableController['createReservation'];
      const context = {
        getClass: () => controller,
        getHandler: () => handler,
        switchToHttp: () => ({
          getRequest: () => ({ websiteContext: { tenant } }),
        }),
      } as unknown as ExecutionContext;
      const capabilities = {
        launched: () => Promise.resolve(true),
        states: () =>
          Promise.resolve([
            {
              key: 'RESERVATIONS',
              commercial: true,
              enabled: true,
              label: 'Reservations',
            },
            {
              key: 'ONLINE_PAYMENTS',
              commercial: true,
              enabled: false,
              label: 'Payments',
            },
          ]),
      };
      const guard = new WebsiteCapabilityGuard(
        new Reflector(),
        capabilities as unknown as WebsiteCapabilitiesService,
      );
      await expect(guard.canActivate(context)).rejects.toMatchObject({
        status: 404,
      });
    });
  },
);

it('both entrypoints return the same trusted amount and corrected variant carts remain valid', async () => {
  const f = setup();
  const result = await f.create(
    'bog',
    input({ menuItems: [{ id: 'large', quantity: 2 }], totalAmount: 1 }),
  );
  const corrected = (
    result as Awaited<ReturnType<BogController['createOrder']>>
  ).validation.correctedCartItems;
  expect(corrected[0].id).toBe('large');
  await f.create('tables', input({ menuItems: corrected }));
  expect(f.stored.map((r) => r.totalAmount)).toEqual([44, 44]);
});

it('rejects invalid provider intents and changed integration revisions before bank calls', async () => {
  const f = setup();
  for (const intent of [
    { amountMinor: 1, currency: 'GEL' },
    { amountMinor: 100.5, currency: 'GEL' },
    { amountMinor: 100, currency: 'USD' },
  ]) {
    await expect(
      f.bog.createOrder(
        tenant,
        'integration-a',
        'r',
        intent as BookingPaymentIntent,
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  }
  await expect(
    f.bog.createOrder(tenant, 'old-revision', 'r', {
      amountMinor: 11000,
      currency: 'GEL',
    }),
  ).rejects.toBeInstanceOf(BadRequestException);
  expect(providerPost).not.toHaveBeenCalled();
});

it('refuses money that cannot survive the existing numeric wire contract exactly', () => {
  expect(() => bookingAmountInGel(Number.MAX_SAFE_INTEGER)).toThrow(
    BadRequestException,
  );
});
