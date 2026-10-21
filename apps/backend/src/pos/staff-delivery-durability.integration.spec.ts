jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));
import { randomUUID } from 'node:crypto';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { PrismaService } from '../prisma.service';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import { MobileUsersService } from '../mobile/services/mobile-users.service';
import { StaffSyncService } from './sync/snapshot/staff-sync.service';
import { PosCommandDispatcher } from './pos-command-dispatcher.service';
import { MobileDashboardService } from '../mobile/services/mobile-dashboard.service';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url && isFreshDisposableDatabase(url) ? describe : describe.skip)(
  'Staff and expense durable delivery (owned PostgreSQL)',
  () => {
    let db: PrismaService,
      vault: StaffPinVault,
      dispatcher: PosCommandDispatcher;
    const org = randomUUID();
    const venues: string[] = [];
    let sequence = 0;
    beforeAll(async () => {
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      await db.organization.create({
        data: { id: org, name: 'Synthetic queue durability' },
      });
      vault = new StaffPinVault(db);
      dispatcher = new PosCommandDispatcher(
        db,
        {} as never,
        {} as never,
        {} as never,
      );
    });
    afterAll(async () => {
      if (!db) return;
      const where = { venueId: { in: venues } };
      await db.edgeCommand.deleteMany({ where });
      await db.posCallbackOutbox.deleteMany({ where });
      await db.expense.deleteMany({ where });
      await db.setting.deleteMany({ where });
      await db.staff.deleteMany({ where });
      await db.device.deleteMany({ where });
      await db.venue.deleteMany({ where: { id: { in: venues } } });
      await db.organization.delete({ where: { id: org } });
      await db.$disconnect();
    });
    async function fixture(enrolled = true) {
      const venueId = randomUUID();
      venues.push(venueId);
      await db.venue.create({
        data: {
          id: venueId,
          organizationId: org,
          name: 'Synthetic',
          timezone: 'UTC',
          currency: 'GEL',
        },
      });
      if (enrolled)
        await db.device.create({
          data: {
            venueId,
            installationId: randomUUID(),
            displayName: 'Synthetic terminal',
            platform: 'TEST',
            credentialHash: 'synthetic-unused',
          },
        });
      const actor = {
        venueId,
        organizationId: org,
        staffId: randomUUID(),
        username: 'Synthetic manager',
      };
      const users = new MobileUsersService(db, dispatcher, vault);
      return { actor, users };
    }
    const failing = () => ({
      recordCloudMutation: () =>
        Promise.reject(new Error('synthetic queue persistence failure')),
      kickRecordedDelivery: jest.fn(),
    });

    it('rolls back a Staff create and vault write if the queue cannot persist', async () => {
      const { actor } = await fixture();
      const queue = failing();
      const users = new MobileUsersService(db, queue as never, vault);
      await expect(
        users.createUser(actor, {
          username: 'Created',
          pinCode: '4163',
          role: 'WAITER',
        }),
      ).rejects.toThrow('queue persistence failure');
      expect(await db.staff.count({ where: { venueId: actor.venueId } })).toBe(
        0,
      );
      expect(await vault.read(actor)).toEqual({});
      expect(
        await db.edgeCommand.count({ where: { venueId: actor.venueId } }),
      ).toBe(0);
      expect(queue.kickRecordedDelivery).not.toHaveBeenCalled();
    });

    it('commits Staff and pending work together, preserving it through an older snapshot', async () => {
      const { actor, users } = await fixture();
      const created = await users.createUser(actor, {
        username: 'Created',
        pinCode: '4163',
        role: 'WAITER',
      });
      expect(created.posDelivery).toMatchObject({
        transport: 'edge',
        status: 'QUEUED',
      });
      const queue = await db.edgeCommand.findUniqueOrThrow({
        where: { id: created.posDelivery.commandId },
      });
      expect(queue).toMatchObject({
        venueId: actor.venueId,
        type: 'STAFF_CREATE',
        status: 'PENDING',
      });
      await new StaffSyncService(db, vault).sync(actor, []);
      expect(
        await db.staff.findUnique({ where: { id: created.id } }),
      ).not.toBeNull();
    });

    it('a claimed rename cannot be undone or duplicate its retired name', async () => {
      const { actor, users } = await fixture();
      const created = await users.createUser(actor, {
        username: 'Old',
        pinCode: '4163',
        role: 'WAITER',
      });
      await db.edgeCommand.updateMany({
        where: { venueId: actor.venueId },
        data: { status: 'SUCCEEDED' },
      });
      const renamed = await users.renameUser(actor, 'Old', { username: 'New' });
      if (!('posDelivery' in renamed)) throw new Error('Rename did not queue');
      await db.edgeCommand.update({
        where: { id: renamed.posDelivery.commandId },
        data: { status: 'CLAIMED' },
      });
      await new StaffSyncService(db, vault).sync(actor, [
        { username: 'Old', role: 'WAITER', pin: '4163' },
      ]);
      expect(
        await db.staff.findUniqueOrThrow({ where: { id: created.id } }),
      ).toMatchObject({ username: 'New' });
      expect(await db.staff.count({ where: { venueId: actor.venueId } })).toBe(
        1,
      );
      expect(await vault.read(actor)).toEqual({ New: '4163' });
    });

    it('another Venue pending create cannot protect a missing local member', async () => {
      const first = await fixture(),
        other = await fixture();
      const local = await first.users.createUser(first.actor, {
        username: 'Shared',
        pinCode: '4163',
        role: 'WAITER',
      });
      await db.edgeCommand.updateMany({
        where: { venueId: first.actor.venueId },
        data: { status: 'SUCCEEDED' },
      });
      await other.users.createUser(other.actor, {
        username: 'Shared',
        pinCode: '4163',
        role: 'WAITER',
      });
      await new StaffSyncService(db, vault).sync(first.actor, []);
      expect(await db.staff.findUnique({ where: { id: local.id } })).toBeNull();
      expect(
        await db.staff.count({ where: { venueId: other.actor.venueId } }),
      ).toBe(1);
    });

    it('rolls back rename, role, PIN and delete when durable delivery fails', async () => {
      const { actor, users } = await fixture();
      const created = await users.createUser(actor, {
        username: 'Stable',
        pinCode: '4163',
        role: 'WAITER',
      });
      const original = await db.staff.findUniqueOrThrow({
        where: { id: created.id },
      });
      const broken = new MobileUsersService(db, failing() as never, vault);
      for (const mutate of [
        () => broken.renameUser(actor, 'Stable', { username: 'Changed' }),
        () => broken.updateUserRole(actor, 'Stable', { role: 'SUPERVISOR' }),
        () => broken.updateUserPin(actor, 'Stable', { pinCode: '7385' }),
        () => broken.deleteUser(actor, 'Stable'),
      ]) {
        await expect(mutate()).rejects.toThrow('queue persistence failure');
        expect(
          await db.staff.findUniqueOrThrow({ where: { id: created.id } }),
        ).toEqual(original);
        expect(await vault.read(actor)).toEqual({ Stable: '4163' });
      }
      expect(
        await db.edgeCommand.count({ where: { venueId: actor.venueId } }),
      ).toBe(1);
    });

    it('reports unavailable delivery for an unenrolled nonlegacy Venue', async () => {
      const { actor, users } = await fixture(false);
      const created = await users.createUser(actor, {
        username: 'Cloud only',
        pinCode: '4163',
        role: 'WAITER',
      });
      expect(created.posDelivery).toMatchObject({
        status: 'UNAVAILABLE',
        code: 'enrollment_required',
      });
      expect(
        await db.posCallbackOutbox.count({ where: { venueId: actor.venueId } }),
      ).toBe(0);
    });

    it('expense creation and its shared echo identity roll back with queue failure', async () => {
      const { actor } = await fixture();
      await db.setting.create({
        data: {
          venueId: actor.venueId,
          key: 'currentBusinessDate',
          value: '2026-10-18',
        },
      });
      const dashboard = new MobileDashboardService(
        db,
        {} as never,
        failing() as never,
        {} as never,
      );
      await expect(
        dashboard.createExpense(actor, {
          description: `Synthetic ${++sequence}`,
          amount: 5,
          category: 'other',
          paymentType: 'cash',
        }),
      ).rejects.toThrow('queue persistence failure');
      expect(
        await db.expense.count({ where: { venueId: actor.venueId } }),
      ).toBe(0);
    });
  },
);
