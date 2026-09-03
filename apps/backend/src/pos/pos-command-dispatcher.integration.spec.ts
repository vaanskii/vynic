jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { DeviceStatus, EdgeCommandStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { EdgeCommandService } from '../edge/edge-command.service';
import { PosCommandDispatcher } from './pos-command-dispatcher.service';
import { PosCallbackClient } from './pos-callback.client';
import {
  EDGE_IDEMPOTENT_COMMAND_TYPES,
  EdgeCommandTypes,
} from '../shared/contracts/edge-command';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

/**
 * How Cloud-originated restaurant work actually reaches a POS.
 *
 * The properties here are the ones the migration turns on: an enrolled Venue's
 * work becomes a queued command rather than an HTTP call into a LAN, a Venue
 * with no enrolled terminal still has the transitional path, and neither of
 * them can put work in another restaurant's queue.
 */
describeDatabase('Cloud → POS command dispatch (PostgreSQL)', () => {
  let prisma: PrismaService;
  let credentials: DeviceCredentialService;
  let commands: EdgeCommandService;
  let dispatcher: PosCommandDispatcher;

  const outboxRows: Array<{ endpoint: string; venueId: string }> = [];
  const legacyPosts: string[] = [];

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `a0000000-0000-4000-8000-${suffix}`;
  /** Has an enrolled terminal: work goes on the Edge queue. */
  const enrolledVenueId = `a1000000-0000-4000-8000-${suffix}`;
  /** Has none: the transitional LAN path is still the only way in. */
  const unenrolledVenueId = `a2000000-0000-4000-8000-${suffix}`;
  /** A second enrolled Venue, to prove queues do not leak. */
  const otherVenueId = `a3000000-0000-4000-8000-${suffix}`;
  const venueIds = [enrolledVenueId, unenrolledVenueId, otherVenueId];

  const enrolled = { venueId: enrolledVenueId };
  const unenrolled = { venueId: unenrolledVenueId };
  const other = { venueId: otherVenueId };

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    credentials = new DeviceCredentialService(prisma);
    commands = new EdgeCommandService(prisma);

    const posCallback = {
      deliverToPos: (endpoint: string) => {
        legacyPosts.push(endpoint);
        return Promise.resolve({ ok: true, status: 200 });
      },
    } as unknown as PosCallbackClient;
    const posOutbox = {
      enqueue: (
        item: { endpoint: string },
        tenant: { venueId: string },
      ): Promise<void> => {
        outboxRows.push({ endpoint: item.endpoint, venueId: tenant.venueId });
        return Promise.resolve();
      },
    } as never;

    dispatcher = new PosCommandDispatcher(
      prisma,
      commands,
      posCallback,
      posOutbox,
    );

    const venue = (id: string, name: string) => ({
      id,
      name,
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
    });
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Command dispatch fixture',
        venues: {
          create: [
            venue(enrolledVenueId, 'Enrolled venue'),
            venue(unenrolledVenueId, 'Unenrolled venue'),
            venue(otherVenueId, 'Other venue'),
          ],
        },
      },
    });

    await credentials.issueCredential({
      venueId: enrolledVenueId,
      installationId: `a4000000-0000-4000-8000-${suffix}`,
      displayName: 'Enrolled POS',
      platform: 'windows',
    });
    await credentials.issueCredential({
      venueId: otherVenueId,
      installationId: `a5000000-0000-4000-8000-${suffix}`,
      displayName: 'Other POS',
      platform: 'windows',
    });
  });

  afterAll(async () => {
    await prisma.edgeCommand.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.device.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  afterEach(async () => {
    await prisma.edgeCommand.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    outboxRows.length = 0;
    legacyPosts.length = 0;
  });

  it('queues an enrolled Venue’s work instead of dialling its LAN', async () => {
    const delivery = await dispatcher.dispatch(enrolled, {
      type: EdgeCommandTypes.ORDER_STATUS_UPDATE,
      payload: { posOrderId: 7, status: 'cancelled' },
    });

    expect(delivery.transport).toBe('edge');
    expect(delivery.status).toBe('QUEUED');
    expect(outboxRows).toHaveLength(0);
    expect(legacyPosts).toHaveLength(0);

    const rows = await prisma.edgeCommand.findMany({
      where: { venueId: enrolledVenueId },
    });
    expect(rows).toHaveLength(1);
    expect(rows[0].type).toBe(EdgeCommandTypes.ORDER_STATUS_UPDATE);
    expect(rows[0].status).toBe(EdgeCommandStatus.PENDING);
    // Venue-addressed, not machine-addressed: any terminal of this restaurant
    // may take it, which is what a single-till venue needs.
    expect(rows[0].deviceId).toBeNull();
  });

  it('falls back to the LAN only for a Venue with no enrolled terminal', async () => {
    const delivery = await dispatcher.dispatch(unenrolled, {
      type: EdgeCommandTypes.ORDER_STATUS_UPDATE,
      payload: { posOrderId: 7, status: 'cancelled' },
    });

    expect(delivery.transport).toBe('legacy');
    expect(outboxRows).toEqual([
      { endpoint: '/mobile-order-status', venueId: unenrolledVenueId },
    ]);
    expect(
      await prisma.edgeCommand.count({ where: { venueId: unenrolledVenueId } }),
    ).toBe(0);
  });

  it('stops falling back the moment that Venue enrols a terminal', async () => {
    const issued = await credentials.issueCredential({
      venueId: unenrolledVenueId,
      installationId: `a6000000-0000-4000-8000-${suffix}`,
      displayName: 'Newly enrolled POS',
      platform: 'windows',
    });
    try {
      const delivery = await dispatcher.dispatch(unenrolled, {
        type: EdgeCommandTypes.ORDER_CANCEL,
        payload: { posOrderId: 9 },
      });
      expect(delivery.transport).toBe('edge');
      expect(outboxRows).toHaveLength(0);
    } finally {
      await prisma.edgeCommand.deleteMany({
        where: { venueId: unenrolledVenueId },
      });
      await prisma.device.delete({ where: { id: issued.deviceId } });
    }
  });

  it('goes back to the LAN when the Venue’s only terminal is revoked', async () => {
    const issued = await credentials.issueCredential({
      venueId: unenrolledVenueId,
      installationId: `a7000000-0000-4000-8000-${suffix}`,
      displayName: 'Retired POS',
      platform: 'windows',
    });
    await prisma.device.update({
      where: { id: issued.deviceId },
      data: { status: DeviceStatus.REVOKED },
    });
    try {
      const delivery = await dispatcher.dispatch(unenrolled, {
        type: EdgeCommandTypes.ORDER_CANCEL,
        payload: { posOrderId: 9 },
      });
      // A revoked device cannot claim, so queueing for it would strand the work.
      expect(delivery.transport).toBe('legacy');
    } finally {
      await prisma.device.delete({ where: { id: issued.deviceId } });
    }
  });

  it('keeps one Venue’s work out of another’s queue', async () => {
    await dispatcher.dispatch(enrolled, {
      type: EdgeCommandTypes.ORDER_CANCEL,
      payload: { posOrderId: 1 },
    });
    await dispatcher.dispatch(other, {
      type: EdgeCommandTypes.ORDER_CANCEL,
      payload: { posOrderId: 1 },
    });

    const mine = await prisma.edgeCommand.findMany({
      where: { venueId: enrolledVenueId },
    });
    const theirs = await prisma.edgeCommand.findMany({
      where: { venueId: otherVenueId },
    });
    expect(mine).toHaveLength(1);
    expect(theirs).toHaveLength(1);
    expect(mine[0].id).not.toBe(theirs[0].id);
  });

  it('two edits of one order become two commands, not one collapsed edit', async () => {
    // The legacy outbox collapsed pending pushes for the same order, because it
    // pushed and the newest push won. A pull queue drains in order, so the
    // second edit must be its own command or a manager's change disappears.
    await dispatcher.dispatch(enrolled, {
      type: EdgeCommandTypes.ORDER_UPDATE,
      payload: { posOrderId: 3, totalAmount: 10 },
    });
    await dispatcher.dispatch(enrolled, {
      type: EdgeCommandTypes.ORDER_UPDATE,
      payload: { posOrderId: 3, totalAmount: 20 },
    });

    const rows = await prisma.edgeCommand.findMany({
      where: { venueId: enrolledVenueId },
      orderBy: { createdAt: 'asc' },
    });
    expect(rows).toHaveLength(2);
    expect((rows[1].payload as { totalAmount: number }).totalAmount).toBe(20);
  });

  it('an explicit idempotency key makes a repeated intent one command', async () => {
    const key = 'RESERVATION_CREATE:website:booking-1';
    const first = await dispatcher.dispatch(enrolled, {
      type: EdgeCommandTypes.RESERVATION_CREATE,
      payload: { reservationId: '1756900000000123' },
      idempotencyKey: key,
    });
    const second = await dispatcher.dispatch(enrolled, {
      type: EdgeCommandTypes.RESERVATION_CREATE,
      payload: { reservationId: '1756900000000123' },
      idempotencyKey: key,
    });

    expect(second.commandId).toBe(first.commandId);
    expect(
      await prisma.edgeCommand.count({ where: { venueId: enrolledVenueId } }),
    ).toBe(1);
  });

  it('reports the POS’s own outcome once it acknowledges', async () => {
    const delivery = await dispatcher.dispatch(enrolled, {
      type: EdgeCommandTypes.ORDER_CHECK_PRINT,
      payload: { posOrderId: 5 },
    });
    expect(delivery.status).toBe('QUEUED');

    await prisma.edgeCommand.update({
      where: { id: delivery.commandId },
      data: {
        status: EdgeCommandStatus.FAILED,
        resultCode: 'order_not_found',
        acknowledgedAt: new Date(),
      },
    });

    const after = await dispatcher.statusOf(enrolled, delivery.commandId!);
    expect(after?.status).toBe('FAILED');
    expect(after?.code).toBe('order_not_found');
  });

  it('will not report another Venue’s command status', async () => {
    const delivery = await dispatcher.dispatch(other, {
      type: EdgeCommandTypes.ORDER_CANCEL,
      payload: { posOrderId: 1 },
    });
    expect(await dispatcher.statusOf(enrolled, delivery.commandId!)).toBeNull();
  });

  it('every type it can dispatch is one the queue will accept', async () => {
    // `enqueue()` refuses a type that is not declared idempotent, so a dispatch
    // path for such a type would be a route that always throws.
    for (const type of Object.values(EdgeCommandTypes)) {
      expect(EDGE_IDEMPOTENT_COMMAND_TYPES.has(type)).toBe(true);
    }
  });
});
