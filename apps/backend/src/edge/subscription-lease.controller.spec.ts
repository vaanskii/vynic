import { Test } from '@nestjs/testing';
import request from 'supertest';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { EdgeDeviceGuard } from './edge-device.guard';
import { generateKeyPairSync, verify } from 'node:crypto';
import {
  leaseDecision,
  MAX_OFFLINE_MS,
  SubscriptionLeaseController,
} from './subscription-lease.controller';

const now = 1800000000000;
const state = (
  status = 'ACTIVE',
  cutoff: number | null = now + 500000000,
  enabled = true,
) =>
  ({
    features: enabled ? ['POS'] : [],
    venue: {
      status: 'ACTIVE',
      subscription: {
        status,
        trialEndsAt: cutoff == null ? null : new Date(cutoff),
        currentPeriodEndsAt: cutoff == null ? null : new Date(cutoff),
      },
    },
  }) as any;

describe('subscription lease', () => {
  afterEach(() => {
    delete process.env.VYNIC_LICENSE_SIGNING_KEY;
    jest.restoreAllMocks();
  });
  test.each(['TRIAL', 'ACTIVE', 'PAST_DUE'])(
    '%s deadline is capped by expiry and 24h',
    (status) => {
      expect(leaseDecision(state(status), now).deadline).toBe(
        now + MAX_OFFLINE_MS,
      );
      expect(leaseDecision(state(status, now + 60000), now).deadline).toBe(
        now + 60000,
      );
      expect(leaseDecision(state(status, now), now).status).toBe('EXPIRED');
    },
  );
  test('revoked/disabled access never issues a positive lease', () => {
    expect(leaseDecision(state('CANCELLED', null, false), now)).toMatchObject({
      status: 'REVOKED',
      deadline: now,
    });
    expect(leaseDecision(state('ACTIVE', null, false), now).status).toBe(
      'REVOKED',
    );
  });
  test('authenticated device relationship and fresh challenge are signed', async () => {
    const { privateKey, publicKey } = generateKeyPairSync('ed25519');
    process.env.VYNIC_LICENSE_SIGNING_KEY = privateKey
      .export({ type: 'pkcs8', format: 'pem' })
      .toString();
    jest.spyOn(Date, 'now').mockReturnValue(now);
    const tx = {
      $queryRaw: jest.fn(),
      device: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({
          id: 'device-a',
          venueId: 'venue-a',
          installationId: 'install-a',
          status: 'ACTIVE',
        }),
      },
      venue: {
        findUnique: jest.fn().mockResolvedValue({
          ...state().venue,
          legacyCommercialAccess: false,
          planAssignment: { plan: { features: [{ feature: { key: 'POS' } }] } },
          featureOverrides: [],
        }),
      },
    };
    const controller = new SubscriptionLeaseController({
      $transaction: (f: any) => f(tx),
    } as any);
    const envelope = await controller.issue(
      { deviceId: 'device-a', venueId: 'venue-a' } as any,
      { nonce: 'ab'.repeat(32) },
    );
    const bytes = Buffer.from(envelope.payload, 'base64');
    expect(
      verify(null, bytes, publicKey, Buffer.from(envelope.signature, 'base64')),
    ).toBe(true);
    expect(JSON.parse(bytes.toString())).toMatchObject({
      version: 1,
      deviceId: 'device-a',
      venueId: 'venue-a',
      installationId: 'install-a',
      nonce: 'ab'.repeat(32),
      issuedAt: now,
      deadline: now + MAX_OFFLINE_MS,
    });
    expect(tx.device.findUniqueOrThrow).toHaveBeenCalledWith({
      where: { id: 'device-a' },
    });
    expect(tx.venue.findUnique).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'venue-a' } }),
    );
    expect(
      verify(
        null,
        Buffer.from(bytes.toString().replace('venue-a', 'venue-b')),
        publicKey,
        Buffer.from(envelope.signature, 'base64'),
      ),
    ).toBe(false);
  });
  test('malformed challenges and missing signer fail closed', async () => {
    const controller = new SubscriptionLeaseController({} as any);
    await expect(controller.issue({} as any, { nonce: 'old' })).rejects.toThrow(
      'nonce',
    );
    await expect(
      controller.issue({} as any, { nonce: 'ab'.repeat(32) }),
    ).rejects.toThrow('not configured');
  });
  test('HTTP requires a device credential and derives tenant and installation server-side', async () => {
    const { privateKey, publicKey } = generateKeyPairSync('ed25519');
    process.env.VYNIC_LICENSE_SIGNING_KEY = privateKey
      .export({ type: 'pkcs8', format: 'pem' })
      .toString();
    const tx = {
      $queryRaw: jest.fn(),
      device: {
        findUniqueOrThrow: jest
          .fn()
          .mockResolvedValue({
            id: 'device-a',
            venueId: 'venue-a',
            installationId: 'install-a',
            status: 'ACTIVE',
          }),
      },
      venue: {
        findUnique: jest
          .fn()
          .mockResolvedValue({
            status: 'ACTIVE',
            legacyCommercialAccess: false,
            subscription: {
              status: 'TRIAL',
              trialEndsAt: new Date(Date.now() + 60000),
              billingManaged: false,
            },
            planAssignment: {
              plan: { features: [{ feature: { key: 'POS' } }] },
            },
            featureOverrides: [],
          }),
      },
    };
    const module = await Test.createTestingModule({
      controllers: [SubscriptionLeaseController],
      providers: [
        EdgeDeviceGuard,
        {
          provide: PrismaService,
          useValue: { $transaction: (f: any) => f(tx) },
        },
        {
          provide: DeviceCredentialService,
          useValue: {
            isDeviceCredential: (value: string) => value === 'synthetic-device',
            verifyCredential: async () => ({
              deviceId: 'device-a',
              venueId: 'venue-a',
              authenticationMode: 'device',
            }),
          },
        },
      ],
    }).compile();
    const app = module.createNestApplication();
    await app.init();
    try {
      await request(app.getHttpServer())
        .post('/edge/subscription-lease')
        .send({ nonce: 'ab'.repeat(32) })
        .expect(401);
      const result = await request(app.getHttpServer())
        .post('/edge/subscription-lease')
        .set('X-POS-Sync-Key', 'synthetic-device')
        .send({
          nonce: 'ab'.repeat(32),
          venueId: 'attacker-venue',
          deviceId: 'attacker-device',
          installationId: 'attacker-install',
        })
        .expect(200);
      const bytes = Buffer.from(result.body.payload, 'base64');
      expect(
        verify(
          null,
          bytes,
          publicKey,
          Buffer.from(result.body.signature, 'base64'),
        ),
      ).toBe(true);
      expect(JSON.parse(bytes.toString())).toMatchObject({
        deviceId: 'device-a',
        venueId: 'venue-a',
        installationId: 'install-a',
        kind: 'TRIAL',
        status: 'VALID',
      });
    } finally {
      await app.close();
    }
  });
});
