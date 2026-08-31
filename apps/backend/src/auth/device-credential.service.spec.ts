import { DeviceStatus, VenueStatus } from '@prisma/client';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from './device-credential.service';

const DEVICE_ID = '11111111-1111-4111-8111-111111111111';
const VENUE_ID = '22222222-2222-4222-8222-222222222222';
const ORGANIZATION_ID = '33333333-3333-4333-8333-333333333333';
const CORRECT_SECRET = 'A'.repeat(43);
const WRONG_SECRET = 'B'.repeat(43);

function credential(secret: string, deviceId = DEVICE_ID): string {
  return `vynic-device-v1.${deviceId}.${secret}`;
}

interface DeviceDelegateMock {
  create: jest.Mock;
  findUnique: jest.Mock;
  update: jest.Mock;
}

interface CreateDeviceCall {
  data: { credentialHash: string; venueId: string };
}

interface UpdateLastSeenCall {
  where: { id: string };
  data: { lastSeenAt: Date };
}

function makeService(): {
  service: DeviceCredentialService;
  device: DeviceDelegateMock;
} {
  const device: DeviceDelegateMock = {
    create: jest.fn(),
    findUnique: jest.fn(),
    update: jest.fn(),
  };
  const prisma = { device } as unknown as PrismaService;
  return { service: new DeviceCredentialService(prisma), device };
}

async function activeDevice(secret: string, lastSeenAt: Date | null = null) {
  return {
    id: DEVICE_ID,
    credentialHash: await argon2.hash(secret, { type: argon2.argon2id }),
    status: DeviceStatus.ACTIVE,
    lastSeenAt,
    venue: {
      id: VENUE_ID,
      organizationId: ORGANIZATION_ID,
      status: VenueStatus.ACTIVE,
    },
  };
}

describe('DeviceCredentialService', () => {
  it('requires a canonical Venue UUID when issuing a credential', async () => {
    const { service, device } = makeService();

    await expect(
      service.issueCredential({
        venueId: 'client-selected-venue',
        installationId: '22222222-2222-4222-8222-222222222222',
        displayName: 'Kitchen POS',
        platform: 'windows',
      }),
    ).rejects.toThrow(new TypeError('venueId must be a UUID'));
    expect(device.create).not.toHaveBeenCalled();
  });

  it('requires a high-entropy UUID installation identity', async () => {
    const { service, device } = makeService();

    await expect(
      service.issueCredential({
        venueId: VENUE_ID,
        installationId: 'KAPRISI-7K3QM',
        displayName: 'Kitchen POS',
        platform: 'windows',
      }),
    ).rejects.toThrow(new TypeError('installationId must be a UUID'));
    expect(device.create).not.toHaveBeenCalled();
  });

  it('issues a versioned credential once and persists only its verifier', async () => {
    const { service, device } = makeService();
    device.create.mockResolvedValue({});

    const issued = await service.issueCredential({
      venueId: VENUE_ID,
      installationId: '22222222-2222-4222-8222-222222222222',
      displayName: 'Kitchen POS',
      platform: 'windows',
    });

    expect(issued.credential).toMatch(
      new RegExp(`^vynic-device-v1\\.${issued.deviceId}\\.[A-Za-z0-9_-]{43}$`),
    );
    const rawSecret = issued.credential.split('.')[2];
    const createCalls = device.create.mock.calls as unknown as [
      [CreateDeviceCall],
    ];
    const createData = createCalls[0][0].data;
    expect(createData).toMatchObject({ venueId: VENUE_ID });
    expect(createData.credentialHash).not.toBe(rawSecret);
    await expect(
      argon2.verify(createData.credentialHash, rawSecret),
    ).resolves.toBe(true);
  });

  it('verifies an active Device and updates lastSeenAt after authentication', async () => {
    const { service, device } = makeService();
    device.findUnique.mockResolvedValue(await activeDevice(CORRECT_SECRET));
    device.update.mockResolvedValue({});

    await expect(
      service.verifyCredential(credential(CORRECT_SECRET)),
    ).resolves.toEqual({
      authenticationMode: 'device',
      deviceId: DEVICE_ID,
      venueId: VENUE_ID,
      organizationId: ORGANIZATION_ID,
    });
    const updateCalls = device.update.mock.calls as unknown as [
      [UpdateLastSeenCall],
    ];
    expect(updateCalls[0][0].where.id).toBe(DEVICE_ID);
    expect(updateCalls[0][0].data.lastSeenAt).toBeInstanceOf(Date);
  });

  it('rejects an invalid Device secret without updating lastSeenAt', async () => {
    const { service, device } = makeService();
    device.findUnique.mockResolvedValue(await activeDevice(CORRECT_SECRET));

    await expect(
      service.verifyCredential(credential(WRONG_SECRET)),
    ).resolves.toBeNull();
    expect(device.update).not.toHaveBeenCalled();
  });

  it('rejects an unknown Device without attempting an activity write', async () => {
    const { service, device } = makeService();
    device.findUnique.mockResolvedValue(null);

    await expect(
      service.verifyCredential(
        credential(CORRECT_SECRET, '33333333-3333-4333-8333-333333333333'),
      ),
    ).resolves.toBeNull();
    expect(device.update).not.toHaveBeenCalled();
  });

  it.each([DeviceStatus.DISABLED, DeviceStatus.REVOKED])(
    'rejects a %s Device before secret verification',
    async (status) => {
      const { service, device } = makeService();
      const row = await activeDevice(CORRECT_SECRET);
      device.findUnique.mockResolvedValue({ ...row, status });

      await expect(
        service.verifyCredential(credential(CORRECT_SECRET)),
      ).resolves.toBeNull();
      expect(device.update).not.toHaveBeenCalled();
    },
  );

  it('rejects a Device whose Venue is disabled', async () => {
    const { service, device } = makeService();
    const row = await activeDevice(CORRECT_SECRET);
    device.findUnique.mockResolvedValue({
      ...row,
      venue: { ...row.venue, status: VenueStatus.DISABLED },
    });

    await expect(
      service.verifyCredential(credential(CORRECT_SECRET)),
    ).resolves.toBeNull();
    expect(device.update).not.toHaveBeenCalled();
  });

  it.each([
    '',
    'device-only',
    'vynic-device-v1',
    'vynic-device-v1.device-only',
    'vynic-device-v1..secret',
    'vynic-device-v1.device.',
    'vynic-device-v1.not-a-uuid.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'vynic-device-v1.11111111-1111-4111-8111-111111111111.short-secret',
    'vynic-device-v2.device.secret',
  ])(
    'rejects malformed credentials without a database lookup: %p',
    async (raw) => {
      const { service, device } = makeService();

      await expect(service.verifyCredential(raw)).resolves.toBeNull();
      expect(device.findUnique).not.toHaveBeenCalled();
    },
  );

  it('throttles lastSeenAt writes inside the five-minute window', async () => {
    const { service, device } = makeService();
    device.findUnique.mockResolvedValue(
      await activeDevice(CORRECT_SECRET, new Date()),
    );

    await expect(
      service.verifyCredential(credential(CORRECT_SECRET)),
    ).resolves.toEqual({
      authenticationMode: 'device',
      deviceId: DEVICE_ID,
      venueId: VENUE_ID,
      organizationId: ORGANIZATION_ID,
    });
    expect(device.update).not.toHaveBeenCalled();
  });
});
