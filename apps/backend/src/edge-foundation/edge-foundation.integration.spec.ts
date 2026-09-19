import {
  generateKeyPairSync,
  randomUUID,
  verify,
  createPublicKey,
} from 'node:crypto';
import request from 'supertest';
import { EdgeFoundationService } from './edge-foundation';
import { PrismaService } from '../prisma.service';
import { foundationFixture } from '../../test/edge-foundation.fixture';
const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)(
  'Edge foundation provisioning HTTP/PostgreSQL',
  () => {
    let f: Awaited<ReturnType<typeof foundationFixture>>;
    const installationId = randomUUID();
    const publicKey = generateKeyPairSync('ed25519').publicKey.export({
      format: 'jwk',
    }).x!;
    const body = { installationId, publicKey };
    const post = (venue = f.venueId, token = f.token, payload = body) =>
      request(f.app.getHttpServer())
        .post(`/platform/venues/${venue}/edge-foundations`)
        .set('Authorization', `Bearer ${token}`)
        .send(payload);
    beforeAll(async () => {
      f = await foundationFixture(url!);
    });
    afterAll(async () => {
      if (f) await f.cleanup();
    });
    it('requires Platform mutation authority', async () => {
      expect((await post(f.venueId, 'invalid')).status).toBe(401);
      expect((await post(f.venueId, f.primary.credential)).status).toBe(401);
      expect((await post(f.venueId, f.supportToken)).status).toBe(403);
    });
    it('issues a verifiable foundation grant and preserves the Phase 0 primary', async () => {
      const r = await post();
      expect(r.status).toBe(201);
      const [payload, signature] = r.body.grant.split('.');
      expect(
        verify(
          null,
          Buffer.from(payload),
          createPublicKey(f.publicKey),
          Buffer.from(signature, 'base64url'),
        ),
      ).toBe(true);
      expect(
        JSON.parse(Buffer.from(payload, 'base64url').toString()),
      ).toMatchObject({
        mode: 'FOUNDATION_ONLY',
        venueId: f.venueId,
        installationId,
        publicKey,
      });
      expect(
        (await f.db.venue.findUniqueOrThrow({ where: { id: f.venueId } }))
          .activeOperationalDeviceId,
      ).toBe(f.primary.deviceId);
      expect(await f.db.device.count({ where: { venueId: f.venueId } })).toBe(
        1,
      );
      expect(
        await f.db.platformAuditEvent.count({
          where: {
            targetId: f.venueId,
            action: 'edge.foundation_grant_issued',
          },
        }),
      ).toBe(1);
    });
    it('reissues only the same immutable binding and refuses cross-Venue/key reuse', async () => {
      expect((await post()).status).toBe(201);
      expect((await post(f.venueB)).status).toBe(409);
      expect(
        (
          await post(f.venueId, f.token, {
            ...body,
            installationId: randomUUID(),
          })
        ).status,
      ).toBe(409);
      expect(
        (
          await post(f.disabledVenue, f.token, {
            installationId: randomUUID(),
            publicKey: generateKeyPairSync('ed25519').publicKey.export({
              format: 'jwk',
            }).x!,
          })
        ).status,
      ).toBe(404);
    });
    it('refuses malformed keys and ids', async () => {
      expect(
        (await post(f.venueId, f.token, { ...body, installationId: 'bad' }))
          .status,
      ).toBe(400);
      expect(
        (await post(f.venueId, f.token, { ...body, publicKey: 'bad' })).status,
      ).toBe(409);
    });
    it('fails closed when signer is missing', async () => {
      const old = process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM;
      delete process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM;
      try {
        expect((await post()).status).toBe(503);
      } finally {
        process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM = old;
      }
    });
    it('rolls registration back when audit persistence fails', async () => {
      const service = f.app.get(EdgeFoundationService);
      const original = (service as any).db;
      (service as any).db = f.db.$extends({
        query: {
          platformAuditEvent: {
            create: async () => {
              throw Error('Injected audit persistence failure');
            },
          },
        },
      }) as unknown as PrismaService;
      const candidate = {
        installationId: randomUUID(),
        publicKey: generateKeyPairSync('ed25519').publicKey.export({
          format: 'jwk',
        }).x!,
      };
      try {
        expect((await post(f.venueId, f.token, candidate)).status).toBe(500);
        expect(
          await f.db.edgeFoundationInstallation.findUnique({
            where: { id: candidate.installationId },
          }),
        ).toBeNull();
      } finally {
        (service as any).db = original;
      }
    });
    it('serializes simultaneous registration of the same installation', async () => {
      const candidate = {
        installationId: randomUUID(),
        publicKey: generateKeyPairSync('ed25519').publicKey.export({
          format: 'jwk',
        }).x!,
      };
      const responses = await Promise.all([
        post(f.venueId, f.token, candidate),
        post(f.venueId, f.token, candidate),
      ]);
      expect(responses.map((r) => r.status)).toEqual([201, 201]);
      expect(
        await f.db.edgeFoundationInstallation.count({
          where: { id: candidate.installationId },
        }),
      ).toBe(1);
    });
    it('revokes without deleting identity or changing operational authority', async () => {
      expect(
        (
          await request(f.app.getHttpServer())
            .post(
              `/platform/venues/${f.venueB}/edge-foundations/${installationId}/revoke`,
            )
            .set('Authorization', `Bearer ${f.token}`)
        ).status,
      ).toBe(404);
      const path = `/platform/venues/${f.venueId}/edge-foundations/${installationId}/revoke`;
      for (let i = 0; i < 2; i++)
        expect(
          (
            await request(f.app.getHttpServer())
              .post(path)
              .set('Authorization', `Bearer ${f.token}`)
          ).status,
        ).toBe(201);
      expect((await post()).status).toBe(409);
      expect(
        (
          await f.db.edgeFoundationInstallation.findUniqueOrThrow({
            where: { id: installationId },
          })
        ).revokedAt,
      ).not.toBeNull();
      expect(
        (await f.db.venue.findUniqueOrThrow({ where: { id: f.venueId } }))
          .activeOperationalDeviceId,
      ).toBe(f.primary.deviceId);
    });
  },
);
