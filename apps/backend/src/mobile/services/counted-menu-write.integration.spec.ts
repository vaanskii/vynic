jest.mock('../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
// UUID allocation is not the security boundary under test; the repository's
// CommonJS Jest runner cannot load the installed ESM-only UUID entrypoint.
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));

import { Test } from '@nestjs/testing';
import { PassportModule } from '@nestjs/passport';
import { JwtService } from '@nestjs/jwt';
import { INestApplication } from '@nestjs/common';
import { StaffRole } from '@prisma/client';
import request from 'supertest';
import { PrismaService } from '../../prisma.service';
import { MobileController } from '../mobile.controller';
import { MobileMenuService } from './mobile-menu.service';
import { MobileMutationSupport } from './mobile-mutation-support.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { ManagerTenantService } from '../../auth/manager-tenant.service';
import { JwtStrategy } from '../../auth/jwt.strategy';
import { JwtAuthGuard } from '../../auth/jwt-auth.guard';
import { RolesGuard } from '../../auth/roles.guard';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)(
  'counted-menu atomic writes / real HTTP and PostgreSQL',
  () => {
    let db: PrismaService;
    let app: INestApplication;
    let venueA: string;
    let venueB: string;
    let manager: string;
    const priorSecret = process.env.JWT_SECRET;
    const secret = 'synthetic-pos-checkout-test-only-signing-key';
    const jwt = new JwtService({ secret });
    const broadcast = jest.fn();
    const token = (id: string) =>
      jwt.sign({
        sub: id,
        username: 'forged-name',
        role: 'MANAGER',
        venueId: venueB,
      });
    beforeAll(async () => {
      if (!url || !isFreshDisposableDatabase(url))
        throw Error('Use an owned fresh disposable database');
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const organization = await db.organization.create({
        data: { name: 'Synthetic estimate deletion' },
      });
      const plan = await db.plan.findUniqueOrThrow({
        where: { key: 'POS_WEBSITE_MANAGER' },
      });
      for (const label of ['A', 'B']) {
        const venue = await db.venue.create({
          data: {
            organizationId: organization.id,
            name: `Synthetic deletion ${label}`,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            subscription: { create: { status: 'ACTIVE' } },
            planAssignment: { create: { planId: plan.id } },
          },
        });
        if (label === 'A') venueA = venue.id;
        else venueB = venue.id;
      }
      const staff = async (
        username: string,
        role: StaffRole,
        isActive = true,
      ) =>
        (
          await db.staff.create({
            data: {
              venueId: venueA,
              username,
              role,
              isActive,
              pinHash: 'synthetic-test-only-noncredential',
            },
          })
        ).id;
      manager = await staff('manager', StaffRole.MANAGER);
      await db.setting.createMany({
        data: [
          { venueId: venueA, key: 'restaurant:serviceFeePercent', value: '10' },
          {
            venueId: venueA,
            key: 'restaurant:serviceFeeEnabled',
            value: 'true',
          },
        ],
      });
      const entitlements = new VenueEntitlementsService(db);
      const tenants = new ManagerTenantService(db);
      const menu = new MobileMenuService(
        db,
        { broadcastUpdate: broadcast } as never,
        {} as never,
      );
      const collaborators: Function[] = Reflect.getMetadata(
        'design:paramtypes',
        MobileController,
      );
      const values = new Map<Function, unknown>([
        [VenueEntitlementsService, entitlements],
        [MobileMenuService, menu],
        [MobileMutationSupport, { wsExcludeOpts: () => undefined }],
      ]);
      process.env.JWT_SECRET = secret;
      const module = await Test.createTestingModule({
        imports: [PassportModule.register({ defaultStrategy: 'jwt' })],
        controllers: [MobileController],
        providers: [
          ...collaborators.map((provide) => ({
            provide,
            useValue: values.get(provide) ?? {},
          })),
          { provide: PrismaService, useValue: db },
          { provide: ManagerTenantService, useValue: tenants },
          { provide: JwtStrategy, useValue: new JwtStrategy(tenants) },
          JwtAuthGuard,
          RolesGuard,
          FeatureGuard,
        ],
      }).compile();
      app = module.createNestApplication();
      app.useLogger(false);
      await app.init();
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
      if (priorSecret === undefined) delete process.env.JWT_SECRET;
      else process.env.JWT_SECRET = priorSecret;
    });
    beforeEach(() => broadcast.mockClear());
    const body = {
      displayName: 'Synthetic count',
      subtotal: 100,
      includeServiceFee: true,
      serviceFeeRate: 0.175,
      createdBy: 'Synthetic manager',
      items: [
        {
          itemName: 'First',
          quantity: 2,
          unitPrice: 25,
          comment: 'Frozen comment',
        },
        { itemName: 'Second', quantity: 1, unitPrice: 50 },
      ],
    };
    const write = (path: string, payload: object) =>
      request(app.getHttpServer())
        .post(`/mobile/counted-menu/${path}`)
        .set('Authorization', `Bearer ${token(manager)}`)
        .send(payload);
    it('creates header and all lines with the selected rate', async () => {
      const result = await write('save', body).expect(201);
      const saved = await db.quickOrderDraft.findUniqueOrThrow({
        where: {
          venueId_draftId: { venueId: venueA, draftId: result.body.id },
        },
        include: { items: { orderBy: { name: 'asc' } } },
      });
      expect(saved).toMatchObject({
        subtotal: 100,
        serviceFeeRate: 0.175,
        serviceFeeAmount: 17.5,
        total: 117.5,
      });
      expect(saved.items).toHaveLength(2);
      expect(saved.items[0]).toMatchObject({
        name: 'First',
        quantity: 2,
        price: 25,
        comment: 'Frozen comment',
      });
      expect(broadcast).toHaveBeenCalledTimes(1);
    });
    it('a rejected second create line leaves no draft or earlier line', async () => {
      const before = await db.quickOrderDraft.count({
        where: { venueId: venueA },
      });
      const linesBefore = await db.quickOrderDraftItem.count();
      await write('save', {
        ...body,
        items: [body.items[0], { itemName: 'Invalid', quantity: 1 }],
      }).expect(500);
      expect(
        await db.quickOrderDraft.count({ where: { venueId: venueA } }),
      ).toBe(before);
      expect(await db.quickOrderDraftItem.count()).toBe(linesBefore);
      expect(broadcast).not.toHaveBeenCalled();
    });
    it('a rejected second replacement line preserves the complete original header and cart', async () => {
      const draft = await db.quickOrderDraft.create({
        data: {
          venueId: venueA,
          draftId: 'rollback',
          displayName: 'Original',
          subtotal: 7,
          serviceFeeAmount: 0,
          total: 7,
          createdBy: 'Original manager',
          items: {
            create: [
              { name: 'Original', quantity: 1, price: 7, comment: 'Keep' },
            ],
          },
        },
        include: { items: true },
      });
      await write('rollback/update', {
        ...body,
        items: [body.items[0], { itemName: 'Invalid', quantity: 1 }],
      }).expect(500);
      const after = await db.quickOrderDraft.findUniqueOrThrow({
        where: { id: draft.id },
        include: { items: true },
      });
      expect(after).toEqual(draft);
      expect(broadcast).not.toHaveBeenCalled();
    });
    it('replaces only the authenticated Venue draft and keeps a custom rate when omitted', async () => {
      for (const venueId of [venueA, venueB])
        await db.quickOrderDraft.create({
          data: {
            venueId,
            draftId: 'shared-id',
            subtotal: 10,
            serviceFeeAmount: 2,
            total: 12,
            includeServiceFee: true,
            serviceFeeRate: 0.2,
            createdBy: 'Original',
            items: { create: [{ name: 'Old', quantity: 1, price: 10 }] },
          },
        });
      const { serviceFeeRate: _rate, ...update } = body;
      await write('shared-id/update', { ...update, venueId: venueB }).expect(
        201,
      );
      const own = await db.quickOrderDraft.findUniqueOrThrow({
        where: { venueId_draftId: { venueId: venueA, draftId: 'shared-id' } },
        include: { items: true },
      });
      const other = await db.quickOrderDraft.findUniqueOrThrow({
        where: { venueId_draftId: { venueId: venueB, draftId: 'shared-id' } },
        include: { items: true },
      });
      expect(own).toMatchObject({
        subtotal: 100,
        total: 120,
        serviceFeeRate: 0.2,
      });
      expect(own.items.map((i) => i.name).sort()).toEqual(['First', 'Second']);
      expect(other).toMatchObject({ subtotal: 10, total: 12 });
      expect(other.items.map((i) => i.name)).toEqual(['Old']);
    });
    it('missing update returns 404 without a draft or broadcast', async () => {
      await write('absent/update', body).expect(404);
      expect(broadcast).not.toHaveBeenCalled();
    });
  },
);
