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

const url = process.env.POS_CHECKOUT_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'counted-menu deletion / real HTTP and PostgreSQL',
  () => {
    let db: PrismaService;
    let app: INestApplication;
    let venueA: string;
    let venueB: string;
    let manager: string;
    let supervisor: string;
    let waiter: string;
    let inactive: string;
    let demoted: string;
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
    const post = (id: string, auth?: string) => {
      const query = request(app.getHttpServer())
        .post(`/mobile/counted-menu/${id}/delete`)
        .set('x-venue-id', venueB)
        .send({ venueId: venueB, role: 'MANAGER' });
      return auth ? query.set('Authorization', `Bearer ${auth}`) : query;
    };
    const makeDraft = (venueId: string, draftId: string) =>
      db.quickOrderDraft.create({
        data: {
          venueId,
          draftId,
          subtotal: 10,
          total: 10,
          serviceFeeAmount: 0,
          createdBy: 'synthetic',
        },
      });
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('pos_checkout')
      )
        throw Error('Use an owned disposable_pos_checkout database');
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
      supervisor = await staff('supervisor', StaffRole.SUPERVISOR);
      waiter = await staff('waiter', StaffRole.WAITER);
      inactive = await staff('inactive', StaffRole.MANAGER, false);
      demoted = await staff('demoted', StaffRole.MANAGER);
      await makeDraft(venueA, 'protected');
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
    it('anonymous deletion is refused before persistence', async () => {
      expect((await post('protected')).status).toBe(401);
      expect(
        await db.quickOrderDraft.count({
          where: { venueId: venueA, draftId: 'protected' },
        }),
      ).toBe(1);
    });
    it.each(['supervisor', 'waiter', 'inactive'])(
      'current %s identity cannot delete despite signed Manager claims',
      async (kind) => {
        const id =
          kind === 'supervisor'
            ? supervisor
            : kind === 'waiter'
              ? waiter
              : inactive;
        expect((await post('protected', token(id))).status).toBe(401);
        expect(
          await db.quickOrderDraft.count({
            where: { venueId: venueA, draftId: 'protected' },
          }),
        ).toBe(1);
        expect(broadcast).not.toHaveBeenCalled();
      },
    );
    it('demotion revokes a previously issued Manager token immediately', async () => {
      const old = token(demoted);
      await db.staff.update({
        where: { id: demoted },
        data: { role: StaffRole.SUPERVISOR },
      });
      expect((await post('protected', old)).status).toBe(401);
      expect(
        await db.quickOrderDraft.count({
          where: { venueId: venueA, draftId: 'protected' },
        }),
      ).toBe(1);
    });
    it('authenticated Manager deletes only its Staff-owned Venue despite forged tenant inputs', async () => {
      await makeDraft(venueA, 'same-id');
      await makeDraft(venueB, 'same-id');
      expect((await post('same-id', token(manager))).status).toBe(201);
      expect(
        await db.quickOrderDraft.count({
          where: { venueId: venueA, draftId: 'same-id' },
        }),
      ).toBe(0);
      expect(
        await db.quickOrderDraft.count({
          where: { venueId: venueB, draftId: 'same-id' },
        }),
      ).toBe(1);
      expect(broadcast).toHaveBeenCalledTimes(1);
      expect(broadcast.mock.calls[0][0]).toMatchObject({ venueId: venueA });
    });
  },
);
