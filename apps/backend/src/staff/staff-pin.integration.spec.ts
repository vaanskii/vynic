import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { StaffRole } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { grantTrialPlan } from '../../test/commercial-access.fixture';
import { AuthService } from '../auth/auth.service';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import { MobileUsersService } from '../mobile/services/mobile-users.service';
import { PlatformCommercialService } from '../platform/platform-commercial.service';
import { PosCommandDispatcher } from '../pos/pos-command-dispatcher.service';
import { StaffSyncService } from '../pos/sync/snapshot/staff-sync.service';
import { StaffSync } from '../pos/sync/sync-payload';
import { PrismaService } from '../prisma.service';
import { TenantContext } from '../tenancy/tenant-context';

// Opt in only with a fresh loopback database. Never use the application's URL.
const url = process.env.STAFF_PIN_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Staff PIN admission — real PostgreSQL and bcrypt',
  () => {
    let db: PrismaService;
    let vault: StaffPinVault;
    let mobile: MobileUsersService;
    let platform: PlatformCommercialService;
    let sync: StaffSyncService;
    let auth: AuthService;
    let tenant: TenantContext;
    let venueCode: string;
    let actor: { platformUserId: string };
    const dispatch = jest.fn().mockResolvedValue({ status: 'QUEUED' });
    const pin = '483921'; // Fixed synthetic fixtures; never delivered to a POS.
    const otherPin = '571234';
    const thirdPin = '692481';

    beforeAll(async () => {
      if (!url || !isFreshDisposableDatabase(url)) {
        throw new Error('A fresh loopback disposable database is required');
      }
      process.env.COOKIE_ENCRYPTION_KEY = 'staff-pin-disposable-test-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      vault = new StaffPinVault(db);
      mobile = new MobileUsersService(
        db,
        {
          recordCloudMutation: dispatch,
          kickRecordedDelivery: () => undefined,
        } as unknown as PosCommandDispatcher,
        vault,
      );
      platform = new PlatformCommercialService(db, vault);
      sync = new StaffSyncService(db, vault);
      auth = new AuthService(
        db,
        new JwtService({ secret: 'staff-pin-disposable-jwt' }),
      );
      const user = await db.platformUser.create({
        data: {
          email: `${randomUUID()}@pin-test.invalid`,
          displayName: 'Synthetic operator',
          passwordHash: 'unused-test-only',
        },
      });
      actor = { platformUserId: user.id };
    });

    beforeEach(async () => {
      dispatch.mockClear();
      const org = await db.organization.create({
        data: { name: `PIN test ${randomUUID()}` },
      });
      const venue = await db.venue.create({
        data: {
          organizationId: org.id,
          name: 'Synthetic Venue',
          timezone: 'UTC',
          currency: 'GEL',
        },
      });
      tenant = { venueId: venue.id, organizationId: org.id };
      venueCode = venue.loginCode;
      await grantTrialPlan(db, venue.id, 'POS_MANAGER');
      // This suite exercises access mutations after an earlier POS registration.
      await db.managerActivation.create({
        data: {
          venueId: venue.id,
          secretHash: 'test-only-consumed',
          expiresAt: new Date(0),
          consumedAt: new Date(),
          issuerId: actor.platformUserId,
          issuerType: 'PLATFORM',
        },
      });
    });

    afterAll(async () => {
      await db?.$disconnect();
    });

    async function seed(
      username: string,
      value = pin,
      options: {
        role?: StaffRole;
        isActive?: boolean;
        platformManaged?: boolean;
        tenant?: TenantContext;
      } = {},
    ) {
      const target = options.tenant ?? tenant;
      const member = await db.staff.create({
        data: {
          venueId: target.venueId,
          username,
          pinHash: await bcrypt.hash(value, 4),
          role: options.role ?? 'MANAGER',
          isActive: options.isActive ?? true,
          platformManaged: options.platformManaged ?? false,
        },
      });
      const map = await vault.read(target);
      await vault.write({ ...map, [username]: value }, target);
      return member;
    }

    function platformCreate(
      username: string,
      value = pin,
      requestId = randomUUID(),
    ) {
      return platform.managerAccess(actor, tenant.venueId, 'create', {
        requestId,
        username,
        pin: value,
        displayName: 'Synthetic Manager',
        role: 'MANAGER',
      });
    }

    async function state() {
      return {
        staff: await db.staff.findMany({
          where: { venueId: tenant.venueId },
          orderBy: { username: 'asc' },
        }),
        vault: await vault.read(tenant),
        commands: await db.edgeCommand.count({
          where: { venueId: tenant.venueId },
        }),
        audit: await db.platformAuditEvent.count({
          where: { targetId: tenant.venueId },
        }),
      };
    }

    it.each(['MANAGER', 'ADMIN', 'WAITER'] as const)(
      'rejects mobile creation against an active %s, without changing state or dispatching',
      async (role) => {
        await seed('existing', pin, { role });
        const before = await state();
        await expect(
          mobile.createUser(tenant, {
            username: 'new',
            pinCode: pin,
            role: 'MANAGER',
          }),
        ).rejects.toThrow(ConflictException);
        expect(await state()).toEqual(before);
        expect(dispatch).not.toHaveBeenCalled();
      },
    );

    it('rejects creation and PIN updates against a Platform-managed hash even without its vault entry', async () => {
      await seed('platform', pin, { platformManaged: true });
      await seed('normal', otherPin);
      await vault.write({ normal: otherPin }, tenant);
      const before = await state();
      await expect(
        mobile.createUser(tenant, {
          username: 'new',
          pinCode: pin,
          role: 'WAITER',
        }),
      ).rejects.toThrow(ConflictException);
      await expect(
        mobile.updateUserPin(tenant, 'normal', { pinCode: pin }),
      ).rejects.toThrow(ConflictException);
      expect(await state()).toEqual(before);
      expect(dispatch).not.toHaveBeenCalled();
    });

    it('allows a member to keep their own PIN and keeps hash and vault consistent', async () => {
      await seed('normal');
      await mobile.updateUserPin(tenant, 'normal', { pinCode: pin });
      const after = await state();
      expect(after.vault).toEqual({ normal: pin });
      expect(await bcrypt.compare(pin, after.staff[0].pinHash)).toBe(true);
      expect(dispatch).toHaveBeenCalledTimes(1);
    });

    it('allows another Venue and inactive Staff to hold the same PIN', async () => {
      await seed('inactive', pin, { isActive: false });
      const venue = await db.venue.create({
        data: {
          organizationId: tenant.organizationId,
          name: 'Other Venue',
          timezone: 'UTC',
          currency: 'GEL',
        },
      });
      const otherTenant = { ...tenant, venueId: venue.id };
      await seed('other', pin, { tenant: otherTenant });
      await mobile.createUser(tenant, {
        username: 'new',
        pinCode: pin,
        role: 'MANAGER',
      });
      expect((await state()).staff.filter((s) => s.isActive)).toHaveLength(1);
      expect(await vault.read(otherTenant)).toEqual({ other: pin });
    });

    it.each(['mobile', 'sync'] as const)(
      'rejects a PIN-less legacy role promotion through %s',
      async (writer) => {
        await seed('manager', pin, { role: 'ADMIN', platformManaged: true });
        await seed('waiter', pin, { role: 'WAITER' });
        const before = await state();
        const change =
          writer === 'mobile'
            ? mobile.updateUserRole(tenant, 'waiter', { role: 'MANAGER' })
            : sync.sync(tenant, [{ username: 'waiter', role: 'ADMIN' }]);
        await expect(change).rejects.toThrow(ConflictException);
        expect(await state()).toEqual(before);
        expect(dispatch).not.toHaveBeenCalled();
      },
    );

    it.each([undefined, pin])(
      'rejects sync reactivation with supplied PIN %s',
      async (supplied) => {
        await seed('platform', pin, { platformManaged: true });
        await seed('inactive', pin, { isActive: false });
        const before = await state();
        await expect(
          sync.sync(tenant, [
            { username: 'inactive', role: 'MANAGER', pin: supplied },
          ]),
        ).rejects.toThrow(ConflictException);
        expect(await state()).toEqual(before);
      },
    );

    it.each(['mobile', 'sync'] as const)(
      'fails closed on a stale or absent own vault during %s promotion',
      async (writer) => {
        await seed('existing');
        await seed('waiter', pin, { role: 'WAITER' });
        const maps: Record<string, string>[] = [
          { existing: pin },
          { existing: pin, waiter: otherPin },
        ];
        for (const map of maps) {
          await vault.write(map, tenant);
          const before = await state();
          const change =
            writer === 'mobile'
              ? mobile.updateUserRole(tenant, 'waiter', { role: 'MANAGER' })
              : sync.sync(tenant, [
                  { username: 'existing', role: 'MANAGER' },
                  { username: 'waiter', role: 'MANAGER' },
                ]);
          await expect(change).rejects.toThrow(BadRequestException);
          expect(await state()).toEqual(before);
        }
      },
    );

    it('allows a unique PIN-less promotion and reactivation', async () => {
      await seed('waiter', pin, { role: 'WAITER' });
      await seed('inactive', otherPin, { isActive: false });
      await mobile.updateUserRole(tenant, 'waiter', { role: 'MANAGER' });
      await sync.sync(tenant, [
        { username: 'waiter', role: 'MANAGER' },
        { username: 'inactive', role: 'MANAGER' },
      ]);
      expect(
        (await state()).staff.every((s) => s.isActive && s.role === 'MANAGER'),
      ).toBe(true);
    });

    it('rolls back the whole staff snapshot on an internal duplicate', async () => {
      await seed('removed', thirdPin);
      const before = await state();
      await expect(
        sync.sync(tenant, [
          { username: 'first', role: 'WAITER', pin },
          { username: 'second', role: 'MANAGER', pin },
        ]),
      ).rejects.toThrow(ConflictException);
      expect(await state()).toEqual(before);
    });

    it('does not bypass bcrypt truncation for long legacy inputs in the same snapshot', async () => {
      const before = await state();
      const prefix = 'x'.repeat(72);
      await expect(
        sync.sync(tenant, [
          { username: 'first', role: 'WAITER', pin: prefix + 'a' },
          { username: 'second', role: 'WAITER', pin: prefix + 'b' },
        ]),
      ).rejects.toThrow(ConflictException);
      expect(await state()).toEqual(before);
    });

    it('rejects sync creation and PIN changes against Platform-managed Staff', async () => {
      await seed('platform', pin, { platformManaged: true });
      await seed('normal', otherPin);
      const before = await state();
      for (const username of ['new', 'normal']) {
        await expect(
          sync.sync(tenant, [{ username, role: 'MANAGER', pin }]),
        ).rejects.toThrow(ConflictException);
        expect(await state()).toEqual(before);
      }
    });

    it('validates the final sync set so replacement and PIN swaps are order independent', async () => {
      await seed('old', pin);
      await sync.sync(tenant, [
        { username: 'replacement', role: 'MANAGER', pin },
      ]);
      expect((await state()).staff.map((s) => s.username)).toEqual([
        'replacement',
      ]);
      await seed('second', otherPin);
      const snapshot: StaffSync[] = [
        { username: 'replacement', role: 'MANAGER', pin: otherPin },
        { username: 'second', role: 'WAITER', pin },
      ];
      await sync.sync(tenant, snapshot);
      expect(await sync.sync(tenant, snapshot)).toEqual({
        pinsHashed: 0,
        needsPin: [],
      });
      for (const row of (await state()).staff) {
        expect(
          await bcrypt.compare(
            row.username === 'second' ? pin : otherPin,
            row.pinHash,
          ),
        ).toBe(true);
      }
    });

    it('keeps existing conflicts idempotent but authentication fails closed until explicitly repaired', async () => {
      await seed('platform', pin, { platformManaged: true });
      await seed('normal');
      for (const supplied of [undefined, pin]) {
        expect(
          await sync.sync(tenant, [
            { username: 'normal', role: 'MANAGER', pin: supplied },
          ]),
        ).toEqual({ pinsHashed: 0, needsPin: [] });
        await expect(auth.mobileLogin(pin, venueCode)).rejects.toThrow(
          UnauthorizedException,
        );
      }
      await mobile.updateUserPin(tenant, 'normal', { pinCode: otherPin });
      expect((await auth.mobileLogin(pin, venueCode)).username).toBe(
        'platform',
      );
      expect((await auth.mobileLogin(otherPin, venueCode)).username).toBe(
        'normal',
      );
    });

    it('retains Platform control under sync and every mobile mutation', async () => {
      const managed = await seed('platform', pin, {
        platformManaged: true,
        isActive: false,
      });
      for (const change of [
        () => mobile.updateUserPin(tenant, 'platform', { pinCode: otherPin }),
        () => mobile.updateUserRole(tenant, 'platform', { role: 'WAITER' }),
        () => mobile.renameUser(tenant, 'platform', { username: 'renamed' }),
        () => mobile.deleteUser(tenant, 'platform'),
      ])
        await expect(change()).rejects.toThrow(/controlled by Platform/);
      await sync.sync(tenant, [
        { username: 'platform', role: 'WAITER', pin: otherPin },
      ]);
      expect((await state()).staff).toEqual([managed]);
      expect(dispatch).not.toHaveBeenCalled();
    });

    it('rejects Platform create/reset collisions and keeps idempotent self reset', async () => {
      const normal = await seed('normal', pin);
      await seed('other', otherPin, { role: 'WAITER' });
      const before = await state();
      await expect(platformCreate('new')).rejects.toThrow(ConflictException);
      await expect(
        platform.managerAccess(
          actor,
          tenant.venueId,
          'reset',
          { requestId: randomUUID(), pin: otherPin },
          normal.id,
        ),
      ).rejects.toThrow(ConflictException);
      expect(await state()).toEqual(before);
      const body = { requestId: randomUUID(), pin };
      const first = await platform.managerAccess(
        actor,
        tenant.venueId,
        'reset',
        body,
        normal.id,
      );
      const second = await platform.managerAccess(
        actor,
        tenant.venueId,
        'reset',
        body,
        normal.id,
      );
      expect(second.delivery.commandId).toBe(first.delivery.commandId);
      expect((await state()).commands).toBe(1);
      expect((await state()).audit).toBe(1);
    });

    it('checks Platform reset reactivation before enabling an inactive identity', async () => {
      await seed('active');
      const inactive = await seed('inactive', otherPin, { isActive: false });
      const before = await state();
      await expect(
        platform.managerAccess(
          actor,
          tenant.venueId,
          'reset',
          { requestId: randomUUID(), pin },
          inactive.id,
        ),
      ).rejects.toThrow(ConflictException);
      expect(await state()).toEqual(before);
    });

    it.each([
      'mobile/mobile',
      'mobile/platform',
      'mobile/sync',
      'platform/sync',
      'platform/platform',
    ] as const)(
      'serializes competing %s creates so exactly one PIN wins',
      async (pair) => {
        const [left, right] = pair.split('/');
        const create = (writer: string, username: string) => {
          if (writer === 'mobile')
            return mobile.createUser(tenant, {
              username,
              pinCode: pin,
              role: 'MANAGER',
            });
          if (writer === 'platform') return platformCreate(username);
          // Name the mobile contender too, so reconciliation cannot remove it.
          return sync.sync(tenant, [
            { username: 'left', role: 'MANAGER' },
            { username, role: 'MANAGER', pin },
          ]);
        };
        const results = await Promise.allSettled([
          create(left, 'left'),
          create(right, 'right'),
        ]);
        expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
        const rejected = results.find(
          (r) => r.status === 'rejected',
        ) as PromiseRejectedResult;
        expect(rejected.reason).toBeInstanceOf(ConflictException);
        const after = await state();
        expect(after.staff).toHaveLength(1);
        expect(Object.keys(after.vault)).toEqual([after.staff[0].username]);
      },
    );

    it('serializes concurrent PIN updates and retains the losing member credential', async () => {
      await seed('left', otherPin);
      await seed('right', thirdPin);
      const results = await Promise.allSettled([
        mobile.updateUserPin(tenant, 'left', { pinCode: pin }),
        mobile.updateUserPin(tenant, 'right', { pinCode: pin }),
      ]);
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      expect(results.filter((r) => r.status === 'rejected')).toHaveLength(1);
      const after = await state();
      for (const member of after.staff) {
        expect(
          await bcrypt.compare(after.vault[member.username], member.pinHash),
        ).toBe(true);
      }
      expect(Object.values(after.vault).filter((p) => p === pin)).toHaveLength(
        1,
      );
      expect(dispatch).toHaveBeenCalledTimes(1);
    });

    it('preserves both vault entries for concurrent distinct credentials', async () => {
      await Promise.all([
        mobile.createUser(tenant, {
          username: 'left',
          pinCode: pin,
          role: 'MANAGER',
        }),
        mobile.createUser(tenant, {
          username: 'right',
          pinCode: otherPin,
          role: 'WAITER',
        }),
      ]);
      expect((await state()).vault).toEqual({ left: pin, right: otherPin });
    });

    it('rolls back the Staff write if vault persistence fails and does not dispatch', async () => {
      const before = await state();
      const failure = jest
        .spyOn(vault, 'write')
        .mockRejectedValueOnce(new Error('synthetic vault failure'));
      try {
        await expect(
          mobile.createUser(tenant, {
            username: 'new',
            pinCode: pin,
            role: 'MANAGER',
          }),
        ).rejects.toThrow('synthetic vault failure');
      } finally {
        failure.mockRestore();
      }
      expect(await state()).toEqual(before);
      expect(dispatch).not.toHaveBeenCalled();
    });
  },
);
