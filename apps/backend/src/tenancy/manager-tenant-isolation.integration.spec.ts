jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { ForbiddenException } from '@nestjs/common';
import {
  FeatureOverrideEffect,
  StaffRole as PrismaStaffRole,
} from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { ManagerTenantService } from '../auth/manager-tenant.service';
import type { TenantContext } from './tenant-context';
import { FeatureKeys } from '../entitlements/feature-keys';
import { FeatureGuard } from '../entitlements/feature.guard';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { MobileUsersService } from '../mobile/services/mobile-users.service';
import { MobileDevicesService } from '../mobile/services/mobile-devices.service';
import { OrderSyncService } from '../pos/sync/snapshot/order-sync.service';
import { TableSyncService } from '../pos/sync/snapshot/table-sync.service';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

describeDatabase('Manager tenant isolation (PostgreSQL)', () => {
  let prisma: PrismaService;
  let managerTenant: ManagerTenantService;
  let entitlements: VenueEntitlementsService;
  let users: MobileUsersService;
  let devices: MobileDevicesService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `60000000-0000-4000-8000-${suffix}`;
  // Venue A buys Manager. Venue B, under the same Organization, does not.
  const venueAId = `61000000-0000-4000-8000-${suffix}`;
  const venueBId = `62000000-0000-4000-8000-${suffix}`;
  const venueIds = [venueAId, venueBId];

  const tenantA: TenantContext = { venueId: venueAId, organizationId };
  const tenantB: TenantContext = { venueId: venueBId, organizationId };

  let managerAId: string;
  let managerBId: string;

  async function planId(key: string) {
    return (await prisma.plan.findUniqueOrThrow({ where: { key } })).id;
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    managerTenant = new ManagerTenantService(prisma);
    entitlements = new VenueEntitlementsService(prisma);
    // Only the tenant-scoped reads are exercised here; POS callback and vault
    // collaborators are never reached by them.
    users = new MobileUsersService(
      prisma,
      {} as never, // posCallback — not reached by the tenant-scoped reads here
      {} as never, // posOutbox
      {
        read: jest.fn(() => Promise.resolve({})),
        write: jest.fn(() => Promise.resolve(undefined)),
      } as never, // pinVault
    );
    devices = new MobileDevicesService(prisma);

    const venue = (id: string, name: string) => ({
      id,
      name,
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
    });
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Manager isolation fixture',
        venues: {
          create: [venue(venueAId, 'Venue A'), venue(venueBId, 'Venue B')],
        },
      },
    });

    await prisma.venuePlanAssignment.createMany({
      data: [
        { venueId: venueAId, planId: await planId('POS_WEBSITE_MANAGER') },
        // POS only: Venue B never bought the Manager product.
        { venueId: venueBId, planId: await planId('POS') },
      ],
    });

    // Same username in both Venues — the case a global lookup would confuse.
    const managerA = await prisma.staff.create({
      data: {
        venueId: venueAId,
        username: 'admin',
        pinHash: 'venue-a-hash',
        role: PrismaStaffRole.MANAGER,
      },
    });
    const managerB = await prisma.staff.create({
      data: {
        venueId: venueBId,
        username: 'admin',
        pinHash: 'venue-b-hash',
        role: PrismaStaffRole.MANAGER,
      },
    });
    managerAId = managerA.id;
    managerBId = managerB.id;

    await prisma.staff.create({
      data: {
        venueId: venueBId,
        username: 'venue-b-only-waiter',
        pinHash: 'x',
        role: PrismaStaffRole.WAITER,
      },
    });
  });

  afterAll(async () => {
    await prisma.quickOrderDraft.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.pushDevice.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.managerNotification.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venuePlanAssignment.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venueFeatureOverride.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.order.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.table.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.staff.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  describe('identity resolves the tenant', () => {
    it('gives each manager their own Venue despite identical usernames', async () => {
      const a = await managerTenant.resolveByStaffId(managerAId);
      const b = await managerTenant.resolveByStaffId(managerBId);

      expect(a).toMatchObject({ username: 'admin', venueId: venueAId });
      expect(b).toMatchObject({ username: 'admin', venueId: venueBId });
      expect(a!.venueId).not.toBe(b!.venueId);
    });

    it('resolves the Organization that owns the Venue', async () => {
      await expect(
        managerTenant.resolveByStaffId(managerAId),
      ).resolves.toMatchObject({ organizationId });
    });
  });

  describe('Venue A manager cannot reach Venue B', () => {
    it('reads only its own staff', async () => {
      const usernames = async (tenant: TenantContext): Promise<string[]> =>
        ((await users.getUsers(tenant)) as { username: string }[])
          .map((u) => u.username)
          .sort();

      expect(await usernames(tenantA)).toEqual(['admin']);
      expect(await usernames(tenantB)).toEqual([
        'admin',
        'venue-b-only-waiter',
      ]);
    });

    it('cannot read another Venue counted menus', async () => {
      await prisma.quickOrderDraft.create({
        data: {
          venueId: venueBId,
          draftId: 'shared-draft-id',
          subtotal: 10,
          serviceFeeAmount: 0,
          total: 10,
          createdBy: 'admin',
        },
      });

      expect(
        await prisma.quickOrderDraft.count({ where: { venueId: venueAId } }),
      ).toBe(0);
      expect(
        await prisma.quickOrderDraft.count({ where: { venueId: venueBId } }),
      ).toBe(1);

      // The same client-generated draft id is legal in another Venue.
      await prisma.quickOrderDraft.create({
        data: {
          venueId: venueAId,
          draftId: 'shared-draft-id',
          subtotal: 99,
          serviceFeeAmount: 0,
          total: 99,
          createdBy: 'admin',
        },
      });
      await expect(
        prisma.quickOrderDraft.create({
          data: {
            venueId: venueAId,
            draftId: 'shared-draft-id',
            subtotal: 1,
            serviceFeeAmount: 0,
            total: 1,
            createdBy: 'admin',
          },
        }),
      ).rejects.toMatchObject({ code: 'P2002' });
    });

    it('cannot read another Venue notifications addressed to the same username', async () => {
      await prisma.managerNotification.create({
        data: {
          venueId: venueBId,
          wsType: 'order_updated',
          title: 'Venue B only',
          body: 'secret',
          envelope: {},
          deliveries: {
            create: [{ staffUsername: 'admin', channel: 'SOCKET' }],
          },
        },
      });

      expect(await devices.getNotifications(tenantA, 'admin')).toEqual([]);
      expect(await devices.getNotifications(tenantB, 'admin')).toHaveLength(1);
    });

    it('cannot unregister another Venue push device', async () => {
      await devices.registerPushDevice(tenantB, 'admin', {
        fcmToken: `token-${suffix}`,
        platform: 'android',
      });

      await devices.unregisterPushDevice(tenantA, 'admin', {
        fcmToken: `token-${suffix}`,
      });
      expect(
        await prisma.pushDevice.count({ where: { venueId: venueBId } }),
      ).toBe(1);

      await devices.unregisterPushDevice(tenantB, 'admin', {
        fcmToken: `token-${suffix}`,
      });
      expect(
        await prisma.pushDevice.count({ where: { venueId: venueBId } }),
      ).toBe(0);
    });

    it('cannot mutate another Venue staff', async () => {
      await expect(
        users.deleteUser(tenantA, 'venue-b-only-waiter'),
      ).rejects.toThrow();

      expect(
        await prisma.staff.count({
          where: { venueId: venueBId, username: 'venue-b-only-waiter' },
        }),
      ).toBe(1);
    });
  });

  describe('MANAGER_APP entitlement', () => {
    it('is held by Venue A and not by Venue B', async () => {
      await expect(
        entitlements.hasFeature(venueAId, FeatureKeys.MANAGER_APP),
      ).resolves.toBe(true);
      await expect(
        entitlements.hasFeature(venueBId, FeatureKeys.MANAGER_APP),
      ).resolves.toBe(false);
    });

    it('denies the Manager product to Venue B without revealing anything about it', async () => {
      const guard = makeFeatureGuard();

      await expect(guard(venueBId)).rejects.toBeInstanceOf(ForbiddenException);
      await expect(guard(venueAId)).resolves.toBe(true);
    });

    it('can be granted to Venue B by override without a new plan', async () => {
      const managerFeature = await prisma.feature.findUniqueOrThrow({
        where: { key: FeatureKeys.MANAGER_APP },
      });
      await prisma.venueFeatureOverride.create({
        data: {
          venueId: venueBId,
          featureId: managerFeature.id,
          effect: FeatureOverrideEffect.ENABLED,
          note: 'Manager trial.',
        },
      });

      await expect(
        entitlements.hasFeature(venueBId, FeatureKeys.MANAGER_APP),
      ).resolves.toBe(true);

      await prisma.venueFeatureOverride.delete({
        where: {
          venueId_featureId: {
            venueId: venueBId,
            featureId: managerFeature.id,
          },
        },
      });
    });
  });

  it('keeps POS sync working for the Venue that never bought Manager', async () => {
    // The invariant Step 5A established, re-proved now that MANAGER_APP is
    // actually enforced on the Manager API: denying the product must not touch
    // the synchronization path underneath it.
    await expect(
      entitlements.hasFeature(venueBId, FeatureKeys.MANAGER_APP),
    ).resolves.toBe(false);

    await new TableSyncService(prisma).sync(
      tenantB,
      [
        {
          tableNumber: '9',
          floor: 'first',
          isReserved: true,
          activeOrderId: 909,
          currentBill: 30,
        },
      ],
      false,
    );
    await new OrderSyncService(prisma).sync(
      tenantB,
      [
        {
          posOrderId: 909,
          status: 'open',
          totalAmount: 30,
          waiterName: 'admin',
          floor: 'first',
          businessDate: '2026-08-31',
          tableNumbers: ['9'],
          items: [],
        },
      ],
      '2026-08-31',
    );

    expect(await prisma.table.count({ where: { venueId: venueBId } })).toBe(1);
    expect(
      await prisma.order.findFirstOrThrow({
        where: { venueId: venueBId, posOrderId: 909 },
      }),
    ).toMatchObject({ status: 'open', totalAmount: 30 });
  });

  /** The guard the Manager controller carries, driven exactly as Nest drives it. */
  function makeFeatureGuard() {
    const reflector = {
      getAllAndOverride: () => FeatureKeys.MANAGER_APP,
    } as never;
    const guard = new FeatureGuard(reflector, entitlements);
    return (venueId: string) =>
      guard.canActivate({
        getHandler: () => () => undefined,
        getClass: () => class {},
        switchToHttp: () => ({
          getRequest: () => ({ user: { venueId, organizationId } }),
        }),
      } as never);
  }
});
