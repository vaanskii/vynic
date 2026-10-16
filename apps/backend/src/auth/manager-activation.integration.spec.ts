import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import {
  ConflictException,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { grantTrialPlan } from '../../test/commercial-access.fixture';
import { PrismaService } from '../prisma.service';
import { StaffPinVault } from './staff-pin-vault.service';
import { ManagerActivationService } from './manager-activation.service';
import type { PosAuthContext } from './pos-auth-context';
import { AuthService } from './auth.service';
import { PlatformCommercialService } from '../platform/platform-commercial.service';
import { StaffSyncService } from '../pos/sync/snapshot/staff-sync.service';

const url = process.env.MANAGER_ACTIVATION_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Manager initial activation (disposable PostgreSQL)',
  () => {
    let db: PrismaService,
      vault: StaffPinVault,
      service: ManagerActivationService;
    let venueId: string, organizationId: string, venueCode: string;
    let owner: { customerAccountId: string }, admin: { platformUserId: string };
    let pos: PosAuthContext;
    const complete = (body: Record<string, unknown>) =>
      service.complete(pos, body);
    const pin = '482951';
    beforeAll(async () => {
      if (!url || !isFreshDisposableDatabase(url))
        throw new Error('Fresh disposable loopback database required');
      process.env.COOKIE_ENCRYPTION_KEY = 'activation-isolated-fixture-only';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      vault = new StaffPinVault(db);
      service = new ManagerActivationService(db, vault);
      admin = {
        platformUserId: (
          await db.platformUser.create({
            data: {
              email: `${randomUUID()}@activation.invalid`,
              displayName: 'Test Admin',
              passwordHash: 'not-a-login',
            },
          })
        ).id,
      };
    });
    beforeEach(async () => {
      const org = await db.organization.create({
        data: { name: 'Synthetic activation restaurant' },
      });
      organizationId = org.id;
      const venue = await db.venue.create({
        data: {
          organizationId,
          name: 'Activation fixture',
          timezone: 'UTC',
          currency: 'GEL',
        },
      });
      venueId = venue.id;
      venueCode = venue.loginCode;
      await grantTrialPlan(db, venueId, 'POS_MANAGER');
      const device = await db.device.create({
        data: {
          venueId,
          installationId: randomUUID(),
          displayName: 'Synthetic Primary POS',
          platform: 'WINDOWS',
          credentialHash: 'not-a-login',
        },
      });
      await db.venue.update({
        where: { id: venueId },
        data: { activeOperationalDeviceId: device.id },
      });
      pos = {
        venueId,
        organizationId,
        deviceId: device.id,
        authenticationMode: 'device',
      };

      owner = {
        customerAccountId: (
          await db.customerAccount.create({
            data: {
              email: `${randomUUID()}@activation.invalid`,
              displayName: 'Synthetic owner',
              passwordHash: 'not-a-login',
              memberships: { create: { organizationId, role: 'OWNER' } },
            },
          })
        ).id,
      };
    });
    afterAll(async () => {
      await db?.$disconnect();
    });
    const body = (code: string) => ({
      code,
      name: 'Test manager',
      pin,
      requestId: randomUUID(),
    });

    it('invitation alone and legacy shared-key context cannot register a Manager', async () => {
      const input = body((await service.issue(owner, venueId)).code);
      for (const auth of [
        { ...pos, deviceId: null },
        { ...pos, authenticationMode: 'legacy_shared_key' as const },
      ])
        await expect(service.complete(auth, input)).rejects.toBeInstanceOf(
          UnauthorizedException,
        );
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
    });
    it('revoked or replaced POS loses activation authority even after credential verification', async () => {
      const input = body((await service.issue(owner, venueId)).code);
      await db.device.update({
        where: { id: pos.deviceId! },
        data: { status: 'REVOKED' },
      });
      await expect(complete(input)).rejects.toBeInstanceOf(ForbiddenException);
      await db.device.update({
        where: { id: pos.deviceId! },
        data: { status: 'ACTIVE' },
      });
      await db.venue.update({
        where: { id: venueId },
        data: { activeOperationalDeviceId: null },
      });
      await expect(complete(input)).rejects.toBeInstanceOf(ForbiddenException);
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
    });
    it('Platform cannot bypass first POS registration; later access changes stay available', async () => {
      const platform = new PlatformCommercialService(db, vault);
      const access = {
        requestId: randomUUID(),
        username: 'Additional manager',
        displayName: 'Additional manager',
        role: 'MANAGER',
        pin: '684235',
      };
      await expect(
        platform.managerAccess(admin, venueId, 'create', access),
      ).rejects.toThrow('Complete first registration');
      const input = body((await service.issue(admin, venueId)).code);
      await expect(
        platform.managerAccess(admin, venueId, 'create', access),
      ).rejects.toThrow('Complete first registration');
      await complete(input);
      await expect(
        platform.managerAccess(admin, venueId, 'create', access),
      ).resolves.toMatchObject({ staff: { username: access.username } });
    });
    it('POS entitlement is required for both invitation and completion', async () => {
      const input = body((await service.issue(owner, venueId)).code);
      const feature = await db.feature.findUniqueOrThrow({
        where: { key: 'POS' },
      });
      await db.venueFeatureOverride.create({
        data: { venueId, featureId: feature.id, effect: 'DISABLED' },
      });
      await expect(service.issue(owner, venueId)).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      await expect(complete(input)).rejects.toBeInstanceOf(ForbiddenException);
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
    });
    it('creates one protected Manager, vault and Edge delivery, then normal login succeeds', async () => {
      const grant = await service.issue(owner, venueId);
      const input = body(grant.code);
      const result = await complete(input);
      expect(result).toEqual({
        username: input.name,
        venueCode,
        completed: true,
      });
      const stored = await db.managerActivation.findUniqueOrThrow({
        where: { venueId },
      });
      expect(JSON.stringify(stored)).not.toContain(grant.code.split('.')[1]);
      const staff = await db.staff.findFirstOrThrow({ where: { venueId } });
      expect(staff.platformManaged).toBe(true);
      expect(staff.pinHash).not.toBe(pin);
      expect(await bcrypt.compare(pin, staff.pinHash)).toBe(true);
      expect((await vault.read({ venueId }))[input.name]).toBe(pin);
      expect(await db.edgeCommand.count({ where: { venueId } })).toBe(1);
      expect(
        (await new PlatformCommercialService(db, vault).managers(venueId))[0]
          .delivery?.status,
      ).toBe('PENDING');
      const auth = new AuthService(
        db,
        new JwtService({ secret: 'isolated-jwt' }),
      );
      expect((await auth.mobileLogin(pin, venueCode)).username).toBe(
        input.name,
      );
      expect(
        JSON.stringify(
          await db.customerAuditEvent.findMany({
            where: { customerAccountId: owner.customerAccountId },
          }),
        ),
      ).not.toContain(pin);
    });
    it('concurrent identical retries after a lost response produce one Staff and one command', async () => {
      const input = body((await service.issue(owner, venueId)).code);
      const responses = await Promise.all([complete(input), complete(input)]);
      expect(responses[0]).toEqual(responses[1]);
      expect(await db.staff.count({ where: { venueId } })).toBe(1);
      expect(await db.edgeCommand.count({ where: { venueId } })).toBe(1);
    });
    it('two different consumers cannot both activate', async () => {
      const input = body((await service.issue(owner, venueId)).code);
      const results = await Promise.allSettled([
        complete(input),
        complete({
          ...input,
          requestId: randomUUID(),
          name: 'Other manager',
        }),
      ]);
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      expect(await db.staff.count({ where: { venueId } })).toBe(1);
    });
    it('a storage failure rolls back credentials and consumption so the same code can retry', async () => {
      const input = body((await service.issue(owner, venueId)).code);
      const failure = jest
        .spyOn(vault, 'write')
        .mockRejectedValueOnce(new Error('Synthetic storage failure'));
      await expect(complete(input)).rejects.toThrow(
        'Synthetic storage failure',
      );
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
      expect(await db.edgeCommand.count({ where: { venueId } })).toBe(0);
      expect(
        (await db.managerActivation.findUniqueOrThrow({ where: { venueId } }))
          .consumedAt,
      ).toBeNull();
      failure.mockRestore();
      await complete(input);
    });
    it('reissuing revokes old code and expiry rejects without mutation', async () => {
      const old = await service.issue(owner, venueId);
      const next = await service.issue(owner, venueId);
      await expect(complete(body(old.code))).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      await db.managerActivation.update({
        where: { venueId },
        data: { expiresAt: new Date(0) },
      });
      await expect(complete(body(next.code))).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      expect(await db.staff.count({ where: { venueId } })).toBe(0);
    });
    it('token does not authorize another restaurant and revoked issuer loses access', async () => {
      const input = body((await service.issue(owner, venueId)).code);
      const foreign = await db.venue.create({
        data: {
          organizationId,
          name: 'Foreign fixture',
          timezone: 'UTC',
          currency: 'GEL',
        },
      });
      const device = await db.device.create({
        data: {
          venueId: foreign.id,
          installationId: randomUUID(),
          displayName: 'Foreign POS',
          platform: 'WINDOWS',
          credentialHash: 'not-a-login',
        },
      });
      await db.venue.update({
        where: { id: foreign.id },
        data: { activeOperationalDeviceId: device.id },
      });
      await expect(
        service.complete(
          { ...pos, venueId: foreign.id, deviceId: device.id },
          input,
        ),
      ).rejects.toBeInstanceOf(UnauthorizedException);
      await db.organizationMembership.deleteMany({
        where: { customerAccountId: owner.customerAccountId },
      });
      await expect(complete(input)).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
    });
    it('duplicate active staff PIN rolls back; same invitation can retry with unique PIN', async () => {
      const input = body((await service.issue(owner, venueId)).code);
      await db.staff.create({
        data: {
          venueId,
          username: 'waiter',
          role: 'WAITER',
          pinHash: await bcrypt.hash(pin, 4),
        },
      });
      await expect(complete(input)).rejects.toBeInstanceOf(ConflictException);
      expect(
        (await db.managerActivation.findUniqueOrThrow({ where: { venueId } }))
          .consumedAt,
      ).toBeNull();
      await complete({ ...input, pin: '681523' });
    });
    it('existing or inactive Manager cannot be bootstrapped from cabinet', async () => {
      await db.staff.create({
        data: {
          venueId,
          username: 'existing',
          role: 'MANAGER',
          isActive: false,
          pinHash: await bcrypt.hash(pin, 4),
        },
      });
      await expect(service.issue(owner, venueId)).rejects.toBeInstanceOf(
        ConflictException,
      );
      const platform = new PlatformCommercialService(db, vault);
      for (const action of ['create', 'reset', 'disable'] as const)
        await expect(
          platform.managerAccess(owner, venueId, action, {}),
        ).rejects.toBeInstanceOf(ForbiddenException);
    });
    it('delayed offline snapshot cannot restore PIN, role or activation state', async () => {
      const input = body((await service.issue(admin, venueId)).code);
      await complete(input);
      const staff = await db.staff.findFirstOrThrow({ where: { venueId } });
      const sync = new StaffSyncService(db, vault);
      await sync.sync({ venueId, organizationId }, [
        { username: input.name, pin: '111111', role: 'WAITER' },
      ]);
      const after = await db.staff.findUniqueOrThrow({
        where: { id: staff.id },
      });
      expect(after.pinHash).toBe(staff.pinHash);
      expect(after.role).toBe('MANAGER');
      expect(after.isActive).toBe(true);
    });
    it('used code cannot undo a later Platform reset, even on identical retry', async () => {
      const input = body((await service.issue(owner, venueId)).code);
      await complete(input);
      const staff = await db.staff.findFirstOrThrow({ where: { venueId } });
      await new PlatformCommercialService(db, vault).managerAccess(
        admin,
        venueId,
        'reset',
        { requestId: randomUUID(), pin: '684235' },
        staff.id,
      );
      await expect(complete(input)).rejects.toBeInstanceOf(ConflictException);
      await expect(service.issue(owner, venueId)).rejects.toBeInstanceOf(
        ConflictException,
      );
    });
    it('rejects inactive restaurant and foreign owner without creating a grant', async () => {
      await expect(
        service.issue({ customerAccountId: randomUUID() }, venueId),
      ).rejects.toThrow('Restaurant not found');
      await db.venue.update({
        where: { id: venueId },
        data: { status: 'DISABLED' },
      });
      await expect(service.issue(owner, venueId)).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(await db.managerActivation.count({ where: { venueId } })).toBe(0);
    });
  },
);
