import { randomUUID } from 'node:crypto';
import { DeviceStatus, VenueStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { PlatformAuditService } from '../platform/platform-audit.service';
import { DeviceEnrollmentService } from './device-enrollment.service';
import { EdgeCommandService } from './edge-command.service';
import { EnrollmentRateLimiter } from './enrollment-rate-limiter';
import { EdgeCommandTypes } from '../shared/contracts/edge-command';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

/**
 * POS self-enrollment against real PostgreSQL.
 *
 * Mocked Prisma cannot prove any of the properties that matter here: that a
 * code is spent exactly once, that a unique installation cannot become two
 * Devices, that a credential stops authenticating the instant it is rotated, or
 * that Venue A's code cannot produce a Device in Venue B. Every assertion below
 * goes through the real service against the real constraint.
 */
describeDatabase('POS self-enrollment (PostgreSQL)', () => {
  let prisma: PrismaService;
  let credentials: DeviceCredentialService;
  let enrollments: DeviceEnrollmentService;
  let edgeCommands: EdgeCommandService;

  const suffix = `${process.pid}`.padStart(12, '0');
  let adminId: string;
  let organizationId: string;
  let venueAId: string;
  let venueBId: string;

  const actor = () => ({ platformUserId: adminId });

  // A fresh address per redemption. The limiter is per-IP by design, so a suite
  // that reused one would be testing the limiter instead of the enrollment.
  let addressCounter = 0;
  const nextIp = () =>
    `10.9.${Math.floor(addressCounter / 250)}.${(addressCounter++ % 250) + 1}`;

  async function newCode(venueId: string, ttlMinutes?: number) {
    const created = await enrollments.create(actor(), venueId, {
      displayName: 'Front POS',
      platform: 'WINDOWS',
      ttlMinutes,
    });
    return created;
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    credentials = new DeviceCredentialService(prisma);
    edgeCommands = new EdgeCommandService(prisma);
    enrollments = new DeviceEnrollmentService(
      prisma,
      credentials,
      new PlatformAuditService(prisma),
      new EnrollmentRateLimiter(),
    );

    const admin = await prisma.platformUser.create({
      data: {
        email: `enroll-admin-${suffix}@vynic.test`,
        displayName: 'Enrollment Admin',
        passwordHash: 'not-a-real-hash',
      },
      select: { id: true },
    });
    adminId = admin.id;

    const organization = await prisma.organization.create({
      data: { name: `Enrollment Org ${suffix}` },
      select: { id: true },
    });
    organizationId = organization.id;

    const [venueA, venueB] = await Promise.all([
      prisma.venue.create({
        data: {
          organizationId,
          name: 'Venue A',
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
        },
        select: { id: true },
      }),
      prisma.venue.create({
        data: {
          organizationId,
          name: 'Venue B',
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
        },
        select: { id: true },
      }),
    ]);
    venueAId = venueA.id;
    venueBId = venueB.id;
  });

  afterAll(async () => {
    const venueIds = [venueAId, venueBId];
    await prisma.deviceEnrollment.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.edgeCommand.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.device.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.deleteMany({ where: { id: organizationId } });
    await prisma.platformAuditEvent.deleteMany({
      where: { platformUserId: adminId },
    });
    await prisma.platformUser.deleteMany({ where: { id: adminId } });
    await prisma.$disconnect();
  });

  // ── The happy path ────────────────────────────────────────────────────────

  it('turns a typed code into a working Device credential for the right venue', async () => {
    const created = await newCode(venueAId);
    expect(created.code).toMatch(
      /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/,
    );
    expect(created.status).toBe('PENDING');

    const installationId = randomUUID();
    const result = await enrollments.redeem({
      code: created.code,
      installationId,
      platform: 'WINDOWS',
      clientIp: '10.0.0.11',
    });

    expect(result.venue).toMatchObject({ id: venueAId, name: 'Venue A' });
    expect(result.device.installationId).toBe(installationId);
    expect(result.reusedExistingDevice).toBe(false);

    // The credential actually authenticates, and resolves the enrollment's
    // Venue — not one the caller named, because the caller never named one.
    const auth = await credentials.verifyCredential(result.credential);
    expect(auth).toMatchObject({
      authenticationMode: 'device',
      deviceId: result.device.id,
      venueId: venueAId,
    });

    const row = await prisma.deviceEnrollment.findUniqueOrThrow({
      where: { id: created.id },
    });
    expect(row.redeemedAt).not.toBeNull();
    expect(row.deviceId).toBe(result.device.id);
    expect(row.redeemedInstallationId).toBe(installationId);
  });

  it('never stores the code, only its verifier', async () => {
    const created = await newCode(venueAId);
    const row = await prisma.deviceEnrollment.findUniqueOrThrow({
      where: { id: created.id },
      select: { codeHash: true, codeSelector: true },
    });
    const normalized = created.code.replace(/-/g, '');
    expect(row.codeHash).toMatch(/^\$argon2id\$/);
    expect(row.codeHash).not.toContain(normalized);
    expect(row.codeHash).not.toContain(normalized.slice(4));
    // The selector is half a code and cannot enroll anything on its own.
    expect(row.codeSelector).toBe(normalized.slice(0, 4));
  });

  it('reports the enrollment as ENROLLED once a terminal has taken it', async () => {
    const created = await newCode(venueAId);
    await enrollments.redeem({
      code: created.code,
      installationId: randomUUID(),
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });

    const listed = await enrollments.list(venueAId);
    expect(listed.find((row) => row.id === created.id)?.status).toBe(
      'ENROLLED',
    );
  });

  // ── Refusals ──────────────────────────────────────────────────────────────

  it('refuses a code that was never issued', async () => {
    await expect(
      enrollments.redeem({
        code: 'ZZZZ-ZZZZ-ZZZZ',
        installationId: randomUUID(),
        platform: 'WINDOWS',
        clientIp: nextIp(),
      }),
    ).rejects.toMatchObject({ status: 401 });
  });

  it('refuses a wrong secret against a real selector, and counts the attempt', async () => {
    const created = await newCode(venueAId);
    const selector = created.code.slice(0, 4);

    await expect(
      enrollments.redeem({
        code: `${selector}-0000-0000`,
        installationId: randomUUID(),
        platform: 'WINDOWS',
        clientIp: nextIp(),
      }),
    ).rejects.toMatchObject({ status: 401 });

    const row = await prisma.deviceEnrollment.findUniqueOrThrow({
      where: { id: created.id },
      select: { attemptCount: true, redeemedAt: true },
    });
    expect(row.attemptCount).toBe(1);
    expect(row.redeemedAt).toBeNull();
  });

  it('fails a code closed after too many wrong secrets', async () => {
    const created = await newCode(venueAId);
    const selector = created.code.slice(0, 4);
    await prisma.deviceEnrollment.update({
      where: { id: created.id },
      data: { attemptCount: 5 },
    });

    // Even the correct code no longer works once the ceiling is reached.
    await expect(
      enrollments.redeem({
        code: created.code,
        installationId: randomUUID(),
        platform: 'WINDOWS',
        clientIp: `10.0.0.${(process.pid % 200) + 1}`,
      }),
    ).rejects.toMatchObject({ status: 401 });
    expect(selector).toHaveLength(4);
  });

  it('refuses an expired code', async () => {
    const created = await newCode(venueAId);
    await prisma.deviceEnrollment.update({
      where: { id: created.id },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });

    await expect(
      enrollments.redeem({
        code: created.code,
        installationId: randomUUID(),
        platform: 'WINDOWS',
        clientIp: nextIp(),
      }),
    ).rejects.toMatchObject({ status: 401 });

    const listed = await enrollments.list(venueAId);
    expect(listed.find((row) => row.id === created.id)?.status).toBe('EXPIRED');
  });

  it('refuses a cancelled code and reports it as cancelled', async () => {
    const created = await newCode(venueAId);
    const cancelled = await enrollments.cancel(actor(), venueAId, created.id);
    expect(cancelled.status).toBe('CANCELLED');

    await expect(
      enrollments.redeem({
        code: created.code,
        installationId: randomUUID(),
        platform: 'WINDOWS',
        clientIp: nextIp(),
      }),
    ).rejects.toMatchObject({ status: 401 });
  });

  it('refuses a second terminal on a code another terminal already used', async () => {
    const created = await newCode(venueAId);
    await enrollments.redeem({
      code: created.code,
      installationId: randomUUID(),
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });

    await expect(
      enrollments.redeem({
        code: created.code,
        installationId: randomUUID(),
        platform: 'WINDOWS',
        clientIp: nextIp(),
      }),
    ).rejects.toMatchObject({ status: 409 });

    expect(
      await prisma.deviceEnrollment.count({
        where: { id: created.id, deviceId: { not: null } },
      }),
    ).toBe(1);
  });

  it('stops a stranger grinding through codes from one address', async () => {
    const address = '198.51.100.7';
    // A different selector every time, so it is the per-address limit being
    // measured and not the per-code one.
    const attempt = (index: number) =>
      enrollments.redeem({
        code: `Z${index.toString(32).toUpperCase().padStart(3, '0')}-ZZZZ-ZZZZ`,
        installationId: randomUUID(),
        platform: 'WINDOWS',
        clientIp: address,
      });

    const statuses: number[] = [];
    for (let i = 0; i < 14; i++) {
      statuses.push(
        await attempt(i).then(
          () => 200,
          (error: { status?: number }) => error.status ?? 500,
        ),
      );
    }
    expect(statuses.filter((status) => status === 401).length).toBe(12);
    expect(statuses.filter((status) => status === 429).length).toBe(2);
    expect(statuses.slice(-2)).toEqual([429, 429]);
  });

  it('refuses a disabled venue', async () => {
    const created = await newCode(venueBId);
    await prisma.venue.update({
      where: { id: venueBId },
      data: { status: VenueStatus.DISABLED },
    });
    try {
      await expect(
        enrollments.redeem({
          code: created.code,
          installationId: randomUUID(),
          platform: 'WINDOWS',
        }),
      ).rejects.toMatchObject({ status: 401 });
    } finally {
      await prisma.venue.update({
        where: { id: venueBId },
        data: { status: VenueStatus.ACTIVE },
      });
    }
  });

  // ── Tenancy ───────────────────────────────────────────────────────────────

  it('will not move a terminal between venues on a typed code', async () => {
    const installationId = randomUUID();
    const first = await newCode(venueAId);
    const enrolled = await enrollments.redeem({
      code: first.code,
      installationId,
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });
    expect(enrolled.venue.id).toBe(venueAId);

    const foreign = await newCode(venueBId);
    await expect(
      enrollments.redeem({
        code: foreign.code,
        installationId,
        platform: 'WINDOWS',
        clientIp: nextIp(),
      }),
    ).rejects.toMatchObject({ status: 409 });

    // The Device stayed with Venue A, and Venue B gained nothing.
    const device = await prisma.device.findUniqueOrThrow({
      where: { installationId },
      select: { venueId: true },
    });
    expect(device.venueId).toBe(venueAId);
    expect(
      await prisma.deviceEnrollment.count({
        where: { id: foreign.id, redeemedAt: { not: null } },
      }),
    ).toBe(0);
  });

  // ── Reinstall, retry and rotation ─────────────────────────────────────────

  it('re-enrolls the same installation onto the Device it already had', async () => {
    const installationId = randomUUID();
    const first = await enrollments.redeem({
      code: (await newCode(venueAId)).code,
      installationId,
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });

    const second = await enrollments.redeem({
      code: (await newCode(venueAId)).code,
      installationId,
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });

    expect(second.device.id).toBe(first.device.id);
    expect(second.reusedExistingDevice).toBe(true);
    expect(await prisma.device.count({ where: { installationId } })).toBe(1);

    // Rotation, not a second valid secret: the first credential is dead.
    expect(await credentials.verifyCredential(first.credential)).toBeNull();
    expect(
      await credentials.verifyCredential(second.credential),
    ).not.toBeNull();
  });

  it('lets the same terminal retry a code it redeemed but could not persist', async () => {
    const created = await newCode(venueAId);
    const installationId = randomUUID();
    const first = await enrollments.redeem({
      code: created.code,
      installationId,
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });

    // The POS received this and failed to write it to disk. Repeating the
    // redemption from the same installation must recover, not strand it.
    const retry = await enrollments.redeem({
      code: created.code,
      installationId,
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });

    expect(retry.device.id).toBe(first.device.id);
    expect(await prisma.device.count({ where: { installationId } })).toBe(1);
    expect(await credentials.verifyCredential(first.credential)).toBeNull();
    expect(await credentials.verifyCredential(retry.credential)).not.toBeNull();
  });

  it('brings a revoked terminal back only through a new enrollment', async () => {
    const installationId = randomUUID();
    const first = await enrollments.redeem({
      code: (await newCode(venueAId)).code,
      installationId,
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });

    await prisma.device.update({
      where: { id: first.device.id },
      data: { status: DeviceStatus.REVOKED },
    });
    expect(await credentials.verifyCredential(first.credential)).toBeNull();

    const revived = await enrollments.redeem({
      code: (await newCode(venueAId)).code,
      installationId,
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });
    expect(revived.device.id).toBe(first.device.id);
    expect(revived.device.status).toBe(DeviceStatus.ACTIVE);
    // The revoked secret is still dead. Only the new one works.
    expect(await credentials.verifyCredential(first.credential)).toBeNull();
    expect(
      await credentials.verifyCredential(revived.credential),
    ).not.toBeNull();
  });

  it('refuses a disabled Device until it is enrolled or activated again', async () => {
    const installationId = randomUUID();
    const enrolled = await enrollments.redeem({
      code: (await newCode(venueAId)).code,
      installationId,
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });
    await prisma.device.update({
      where: { id: enrolled.device.id },
      data: { status: DeviceStatus.DISABLED },
    });

    expect(await credentials.verifyCredential(enrolled.credential)).toBeNull();
  });

  // ── The transport it exists to join ───────────────────────────────────────

  it('claims and acknowledges a NOOP with a credential issued by enrollment', async () => {
    const installationId = randomUUID();
    const enrolled = await enrollments.redeem({
      code: (await newCode(venueAId)).code,
      installationId,
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });

    const auth = await credentials.verifyCredential(enrolled.credential);
    expect(auth?.deviceId).toBe(enrolled.device.id);
    const device = {
      deviceId: auth!.deviceId!,
      venueId: auth!.venueId,
      organizationId: auth!.organizationId,
    };

    const queued = await edgeCommands.enqueue(
      { venueId: venueAId },
      {
        deviceId: enrolled.device.id,
        type: EdgeCommandTypes.NOOP,
        payload: {},
        idempotencyKey: `enroll-noop-${installationId}`,
      },
    );
    expect(queued.status).toBe('PENDING');

    const claimed = await edgeCommands.claim(device, { limit: 5 });
    expect(claimed.map((command) => command.commandId)).toContain(queued.id);

    const acknowledged = await edgeCommands.acknowledge(device, {
      commandId: queued.id,
      status: 'SUCCEEDED',
      code: 'noop',
      detail: null,
    });
    expect(acknowledged.status).toBe('SUCCEEDED');
  });

  // ── Audit ─────────────────────────────────────────────────────────────────

  it('audits the invitation, the redemption and a failure', async () => {
    const created = await newCode(venueAId);
    const selector = created.code.slice(0, 4);
    await enrollments
      .redeem({
        code: `${selector}-1111-1111`,
        installationId: randomUUID(),
        platform: 'WINDOWS',
        clientIp: nextIp(),
      })
      .catch(() => undefined);
    const redeemed = await enrollments.redeem({
      code: created.code,
      installationId: randomUUID(),
      platform: 'WINDOWS',
      clientIp: nextIp(),
    });

    const events = await prisma.platformAuditEvent.findMany({
      where: { platformUserId: adminId },
      orderBy: { createdAt: 'desc' },
      take: 40,
      select: {
        action: true,
        targetType: true,
        targetId: true,
        metadata: true,
      },
    });

    const createdEvent = events.find(
      (event) =>
        event.action === 'device.enrollment_created' &&
        (event.metadata as { enrollmentId?: string })?.enrollmentId ===
          created.id,
    );
    expect(createdEvent?.targetId).toBe(venueAId);

    expect(
      events.some(
        (event) =>
          event.action === 'device.enrollment_failed' &&
          (event.metadata as { enrollmentId?: string })?.enrollmentId ===
            created.id,
      ),
    ).toBe(true);

    const redeemedEvent = events.find(
      (event) =>
        event.action === 'device.enrollment_redeemed' &&
        event.targetId === redeemed.device.id,
    );
    expect(redeemedEvent?.targetType).toBe('Device');
    expect(redeemedEvent?.metadata).toMatchObject({ redeemedBy: 'device' });

    // Nothing in the trail is a credential or a code.
    const serialized = JSON.stringify(events);
    expect(serialized).not.toContain(created.code.replace(/-/g, '').slice(4));
    expect(serialized).not.toContain('vynic-device-v1.');
  });

  // ── The path enrollment replaces ──────────────────────────────────────────

  it('leaves a file-provisioned Device working and unenrolled', async () => {
    const installationId = randomUUID();
    const issued = await credentials.issueCredential({
      venueId: venueAId,
      installationId,
      displayName: 'Legacy POS',
      platform: 'WINDOWS',
    });

    expect(await credentials.verifyCredential(issued.credential)).toMatchObject(
      {
        deviceId: issued.deviceId,
        venueId: venueAId,
      },
    );
    expect(
      await prisma.deviceEnrollment.count({
        where: { deviceId: issued.deviceId },
      }),
    ).toBe(0);
  });
});
