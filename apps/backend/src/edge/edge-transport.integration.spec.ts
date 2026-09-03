import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { DeviceStatus, EdgeCommandStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { TableSyncService } from '../pos/sync/snapshot/table-sync.service';
import { EdgeCommandService } from './edge-command.service';
import { EdgeDeviceGuard } from './edge-device.guard';
import { EdgeTransportController } from './edge-transport.controller';
import type { EdgeDeviceContext } from './edge-device-context';
import {
  EDGE_COMMAND_MAX_BATCH_SIZE,
  EdgeCommandTypes,
} from '../shared/contracts/edge-command';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

describeDatabase('Cloud → Edge transport (PostgreSQL)', () => {
  let prisma: PrismaService;
  let credentials: DeviceCredentialService;
  let commands: EdgeCommandService;
  let controller: EdgeTransportController;
  let guard: EdgeDeviceGuard;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `80000000-0000-4000-8000-${suffix}`;
  const venueAId = `81000000-0000-4000-8000-${suffix}`;
  const venueBId = `82000000-0000-4000-8000-${suffix}`;
  const venueIds = [venueAId, venueBId];

  let deviceA: EdgeDeviceContext;
  let deviceB: EdgeDeviceContext;
  let credentialA: string;
  let revokedDeviceCredential: string;

  const tenantA = { venueId: venueAId, organizationId };
  const tenantB = { venueId: venueBId, organizationId };

  /** Pretend a lease ran out without touching the clock. */
  async function expireLease(commandId: string) {
    await prisma.edgeCommand.update({
      where: { id: commandId },
      data: { claimExpiresAt: new Date(Date.now() - 1000) },
    });
  }

  function noop(key: string, extra: Record<string, unknown> = {}) {
    return {
      type: EdgeCommandTypes.NOOP,
      payload: { note: key },
      idempotencyKey: key,
      ...extra,
    };
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    credentials = new DeviceCredentialService(prisma);
    commands = new EdgeCommandService(prisma);
    controller = new EdgeTransportController(commands);
    guard = new EdgeDeviceGuard(credentials);

    const venue = (id: string, name: string) => ({
      id,
      name,
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
    });
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Edge transport fixture',
        venues: {
          create: [venue(venueAId, 'Venue A'), venue(venueBId, 'Venue B')],
        },
      },
    });

    const issuedA = await credentials.issueCredential({
      venueId: venueAId,
      installationId: `81000000-0000-4000-8000-${suffix}`,
      displayName: 'Venue A POS',
      platform: 'windows',
    });
    const issuedB = await credentials.issueCredential({
      venueId: venueBId,
      installationId: `82000000-0000-4000-8000-${suffix}`,
      displayName: 'Venue B POS',
      platform: 'windows',
    });
    const issuedRevoked = await credentials.issueCredential({
      venueId: venueAId,
      installationId: `83000000-0000-4000-8000-${suffix}`,
      displayName: 'Venue A retired POS',
      platform: 'windows',
    });
    await prisma.device.update({
      where: { id: issuedRevoked.deviceId },
      data: { status: DeviceStatus.REVOKED },
    });

    credentialA = issuedA.credential;
    revokedDeviceCredential = issuedRevoked.credential;
    deviceA = { deviceId: issuedA.deviceId, ...tenantA };
    deviceB = { deviceId: issuedB.deviceId, ...tenantB };
  });

  afterAll(async () => {
    await prisma.edgeCommand.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.table.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.device.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  afterEach(async () => {
    await prisma.edgeCommand.deleteMany({
      where: { venueId: { in: venueIds } },
    });
  });

  describe('authentication decides the tenant', () => {
    it('accepts a device credential and resolves its own venue', async () => {
      const request: Record<string, unknown> = {
        headers: { 'x-pos-sync-key': credentialA },
      };
      await expect(
        guard.canActivate({
          switchToHttp: () => ({ getRequest: () => request }),
        } as never),
      ).resolves.toBe(true);
      expect(request.posAuthContext).toMatchObject({
        deviceId: deviceA.deviceId,
        venueId: venueAId,
      });
    });

    it('refuses a revoked device', async () => {
      await expect(
        guard.canActivate({
          switchToHttp: () => ({
            getRequest: () => ({
              headers: { 'x-pos-sync-key': revokedDeviceCredential },
            }),
          }),
        } as never),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });
  });

  describe('two venues share a queue table and nothing else', () => {
    it('hands each device only its own venue work', async () => {
      await commands.enqueue(tenantA, noop('a-1'));
      await commands.enqueue(tenantB, noop('b-1'));

      const forA = await commands.claim(deviceA);
      const forB = await commands.claim(deviceB);

      expect(forA.map((c) => c.idempotencyKey)).toEqual(['a-1']);
      expect(forB.map((c) => c.idempotencyKey)).toEqual(['b-1']);
    });

    it('ignores a venueId a caller puts in the request body', async () => {
      await commands.enqueue(tenantB, noop('b-secret'));

      // The claim body has no venue field at all; supplying one changes nothing
      // because tenancy comes from the credential the guard verified.
      const response = await controller.claim(deviceA, {
        venueId: venueBId,
        deviceId: deviceB.deviceId,
      } as never);

      expect(response.commands).toEqual([]);
    });

    it('reports another venue command as missing rather than forbidden', async () => {
      const foreign = await commands.enqueue(tenantB, noop('b-2'));

      await expect(
        commands.acknowledge(deviceA, {
          commandId: foreign.id,
          status: 'SUCCEEDED',
        }),
      ).rejects.toBeInstanceOf(NotFoundException);

      expect(
        await prisma.edgeCommand.findUniqueOrThrow({
          where: { id: foreign.id },
          select: { status: true },
        }),
      ).toEqual({ status: EdgeCommandStatus.PENDING });
    });

    it('refuses to queue work for a device of another venue', async () => {
      await expect(
        commands.enqueue(
          tenantA,
          noop('a-wrong-device', {
            deviceId: deviceB.deviceId,
          }),
        ),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('routing', () => {
    it('gives venue-addressed work to any device of the venue', async () => {
      await commands.enqueue(tenantA, noop('a-venue-wide'));

      expect(
        (await commands.claim(deviceA)).map((c) => c.idempotencyKey),
      ).toEqual(['a-venue-wide']);
    });

    it('keeps device-addressed work away from the venue other devices', async () => {
      const other = await credentials.issueCredential({
        venueId: venueAId,
        installationId: `84000000-0000-4000-8000-${suffix}`,
        displayName: 'Venue A second POS',
        platform: 'windows',
      });
      const secondDevice: EdgeDeviceContext = {
        deviceId: other.deviceId,
        ...tenantA,
      };

      await commands.enqueue(
        tenantA,
        noop('a-for-second', { deviceId: other.deviceId }),
      );

      expect(await commands.claim(deviceA)).toEqual([]);
      expect(
        (await commands.claim(secondDevice)).map((c) => c.idempotencyKey),
      ).toEqual(['a-for-second']);

      await prisma.edgeCommand.deleteMany({ where: { venueId: venueAId } });
      await prisma.device.delete({ where: { id: other.deviceId } });
    });
  });

  describe('delivery and retry', () => {
    it('delivers pending work and leases it', async () => {
      await commands.enqueue(tenantA, noop('a-1'));
      const [envelope] = await commands.claim(deviceA);

      expect(envelope).toMatchObject({
        type: EdgeCommandTypes.NOOP,
        idempotencyKey: 'a-1',
        attempt: 1,
      });
      expect(new Date(envelope.leaseExpiresAt).getTime()).toBeGreaterThan(
        Date.now(),
      );
      // Leased, not done.
      expect(await commands.claim(deviceA)).toEqual([]);
    });

    it('offers an unacknowledged command again once its lease expires', async () => {
      await commands.enqueue(tenantA, noop('a-crash'));
      const [first] = await commands.claim(deviceA);
      await expireLease(first.commandId);

      const [second] = await commands.claim(deviceA);
      expect(second.commandId).toBe(first.commandId);
      expect(second.attempt).toBe(2);
    });

    it('gives up after the attempt budget without losing the command', async () => {
      await commands.enqueue(tenantA, noop('a-doomed', { maxAttempts: 2 }));

      for (let attempt = 0; attempt < 2; attempt += 1) {
        const [envelope] = await commands.claim(deviceA);
        await expireLease(envelope.commandId);
      }
      expect(await commands.claim(deviceA)).toEqual([]);

      const row = await prisma.edgeCommand.findFirstOrThrow({
        where: { venueId: venueAId, idempotencyKey: 'a-doomed' },
      });
      expect(row).toMatchObject({
        status: EdgeCommandStatus.FAILED,
        attemptCount: 2,
        resultCode: 'lease_expired_attempts_exhausted',
      });
    });

    it('returns a deterministic batch and honours the ceiling', async () => {
      for (let index = 0; index < 5; index += 1) {
        await commands.enqueue(
          tenantA,
          noop(`a-order-${index}`, {
            availableAt: new Date(Date.now() - (10 - index) * 1000),
          }),
        );
      }

      const firstTwo = await commands.claim(deviceA, { limit: 2 });
      expect(firstTwo.map((c) => c.idempotencyKey)).toEqual([
        'a-order-0',
        'a-order-1',
      ]);

      const rest = await commands.claim(deviceA, {
        limit: EDGE_COMMAND_MAX_BATCH_SIZE + 100,
      });
      expect(rest.map((c) => c.idempotencyKey)).toEqual([
        'a-order-2',
        'a-order-3',
        'a-order-4',
      ]);
    });

    it('refuses a nonsensical batch size', async () => {
      await expect(
        commands.claim(deviceA, { limit: 0 }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('withholds work an edge cannot understand', async () => {
      await commands.enqueue(
        tenantA,
        noop('a-future', { contractVersion: 99 }),
      );

      expect(
        await commands.claim(deviceA, { acceptedContractVersions: [1] }),
      ).toEqual([]);
      expect(
        (
          await commands.claim(deviceA, { acceptedContractVersions: [1, 99] })
        ).map((c) => c.idempotencyKey),
      ).toEqual(['a-future']);
    });
  });

  describe('acknowledgment', () => {
    it('records success and is safe to repeat', async () => {
      await commands.enqueue(tenantA, noop('a-ok'));
      const [envelope] = await commands.claim(deviceA);

      const first = await commands.acknowledge(deviceA, {
        commandId: envelope.commandId,
        status: 'SUCCEEDED',
      });
      const second = await commands.acknowledge(deviceA, {
        commandId: envelope.commandId,
        status: 'SUCCEEDED',
      });

      expect(first).toMatchObject({
        status: EdgeCommandStatus.SUCCEEDED,
        alreadyAcknowledged: false,
      });
      expect(second).toMatchObject({
        status: EdgeCommandStatus.SUCCEEDED,
        alreadyAcknowledged: true,
      });
      expect(await commands.claim(deviceA)).toEqual([]);
    });

    it('keeps the first outcome when a later acknowledgment disagrees', async () => {
      await commands.enqueue(tenantA, noop('a-fail'));
      const [envelope] = await commands.claim(deviceA);

      await commands.acknowledge(deviceA, {
        commandId: envelope.commandId,
        status: 'FAILED',
        code: 'printer_offline',
        detail: 'no response from 192.168.1.50',
      });
      const repeat = await commands.acknowledge(deviceA, {
        commandId: envelope.commandId,
        status: 'SUCCEEDED',
      });

      expect(repeat).toMatchObject({
        status: EdgeCommandStatus.FAILED,
        alreadyAcknowledged: true,
      });
      expect(
        await prisma.edgeCommand.findUniqueOrThrow({
          where: { id: envelope.commandId },
          select: { resultCode: true, resultDetail: true },
        }),
      ).toEqual({
        resultCode: 'printer_offline',
        resultDetail: 'no response from 192.168.1.50',
      });
    });

    it('refuses a device acknowledging work leased to another device', async () => {
      const other = await credentials.issueCredential({
        venueId: venueAId,
        installationId: `85000000-0000-4000-8000-${suffix}`,
        displayName: 'Venue A third POS',
        platform: 'windows',
      });
      const secondDevice: EdgeDeviceContext = {
        deviceId: other.deviceId,
        ...tenantA,
      };

      await commands.enqueue(tenantA, noop('a-leased'));
      const [envelope] = await commands.claim(deviceA);

      await expect(
        commands.acknowledge(secondDevice, {
          commandId: envelope.commandId,
          status: 'SUCCEEDED',
        }),
      ).rejects.toBeInstanceOf(ForbiddenException);

      await prisma.edgeCommand.deleteMany({ where: { venueId: venueAId } });
      await prisma.device.delete({ where: { id: other.deviceId } });
    });

    it('validates the acknowledgment before touching anything', async () => {
      await expect(
        controller.acknowledge(deviceA, { status: 'SUCCEEDED' }),
      ).rejects.toBeInstanceOf(BadRequestException);
      await expect(
        controller.acknowledge(deviceA, { commandId: 'x', status: 'MAYBE' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('enqueueing', () => {
    it('is idempotent per venue', async () => {
      const first = await commands.enqueue(tenantA, noop('a-same'));
      const second = await commands.enqueue(tenantA, noop('a-same'));

      expect(second.id).toBe(first.id);
      expect(
        await prisma.edgeCommand.count({ where: { venueId: venueAId } }),
      ).toBe(1);
    });

    it('lets two venues use the same idempotency key', async () => {
      const a = await commands.enqueue(tenantA, noop('shared-key'));
      const b = await commands.enqueue(tenantB, noop('shared-key'));

      expect(a.id).not.toBe(b.id);
    });

    it('revives a finished command when the same intent is re-issued', async () => {
      await commands.enqueue(tenantA, noop('a-redo'));
      const [envelope] = await commands.claim(deviceA);
      await commands.acknowledge(deviceA, {
        commandId: envelope.commandId,
        status: 'FAILED',
        code: 'printer_offline',
      });

      const reissued = await commands.enqueue(tenantA, noop('a-redo'));
      expect(reissued).toMatchObject({
        id: envelope.commandId,
        status: EdgeCommandStatus.PENDING,
      });
      expect((await commands.claim(deviceA))[0].attempt).toBe(1);
    });

    it('refuses a command type that is not declared idempotent', async () => {
      // At-least-once delivery will repeat a command eventually, so a type that
      // cannot absorb that must not enter the queue in the first place.
      await expect(
        commands.enqueue(tenantA, {
          type: 'PRINT_ORDER_CHECK',
          payload: {},
          idempotencyKey: 'a-print',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  it('leaves POS snapshot sync working exactly as before', async () => {
    // Transport is new infrastructure alongside the existing Edge → Cloud path,
    // not a replacement for it.
    await new TableSyncService(prisma).sync(
      tenantA,
      [
        {
          tableNumber: '3',
          floor: 'first',
          isReserved: false,
          activeOrderId: null,
          currentBill: 0,
        },
      ],
      false,
    );

    expect(await prisma.table.count({ where: { venueId: venueAId } })).toBe(1);
  });
});
