import 'reflect-metadata';
import type { INestApplication } from '@nestjs/common';
import type { Organization, Venue } from '@prisma/client';
import type { Server } from 'node:http';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { generateKeyPairSync, randomUUID, verify } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import request from 'supertest';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';
import { PlatformAuthService } from '../platform/platform-auth.service';
import {
  PrinterEnrollmentController,
  PrinterConfigurationController,
} from './controller';
import { PrinterProvisioningService } from './service';
import {
  Enrollment,
  Catalog,
  Member,
  OFFLINE_SECONDS,
  signatureInput,
} from './contract';

interface Envelope {
  body: string;
  signature: string;
}
interface Snapshot {
  generation: number;
  issuedAt: number;
  expiresAt: number;
  revision: number;
  members: Member[];
  catalogRaw: string;
}
interface Inventory {
  revision: number;
  members: Member[];
}
function snapshot(envelope: Envelope): Snapshot {
  return JSON.parse(
    Buffer.from(envelope.body, 'base64').toString(),
  ) as Snapshot;
}
const url = process.env.POS02_A_DATABASE_URL;
(url ? describe : describe.skip)(
  'POS-02.A real HTTP/PostgreSQL and Go exchange',
  () => {
    let db: PrismaService,
      app: INestApplication,
      org: Organization & { venues: Venue[] },
      venue: string,
      foreign: string,
      actor: string,
      support: string,
      token: string,
      supportToken: string;
    let devices: { deviceId: string; credential: string }[];
    let requests: Enrollment[];
    let exchange: string;
    let catalog: Catalog;
    const keys = generateKeyPairSync('ed25519');
    const oldSigner = process.env.PRINTER_PRODUCTION_SIGNING_KEY_PEM;
    const proof = process.env.POS02_A_PROOF_DIR;
    const go = (name: string) => {
      const stdout = execFileSync(
        process.env.POS02_A_GO || 'go',
        [
          'test',
          './internal/printerprovisioning',
          '-count=1',
          '-json',
          '-run',
          `^${name}$`,
        ],
        {
          cwd: resolve(__dirname, '../../../edge'),
          env: { ...process.env, VYNIC_POS02A_EXCHANGE: exchange },
          timeout: 120000,
        },
      );
      if (proof) writeFileSync(join(proof, `${name}.jsonl`), stdout);
      expect(stdout.toString()).toContain('"Action":"pass"');
    };
    const enroll = async (
      i: number,
      b: object = requests[i],
      credential = devices[i].credential,
    ): Promise<{ status: number; body: Envelope }> => {
      const response = await request(app.getHttpServer() as Server)
        .post('/edge/printer-provisioning/enroll')
        .set('X-POS-Sync-Key', credential)
        .send(b);
      return response;
    };
    const platform = async (
      path = '',
      b?: object,
      bearer = token,
      target = venue,
    ): Promise<{ status: number; body: Inventory }> => {
      const req = request(app.getHttpServer() as Server);
      const endpoint = `/platform/venues/${target}/printer-provisioning${path}`;
      const response = await (
        b === undefined ? req.get(endpoint) : req.post(endpoint).send(b)
      ).set('Authorization', `Bearer ${bearer}`);
      return response;
    };
    const save = (name: string, b: unknown) => {
      writeFileSync(join(exchange, name + '.json'), JSON.stringify(b));
      if (proof) writeFileSync(join(proof, name + '.json'), JSON.stringify(b));
    };
    beforeAll(async () => {
      const parsed = new URL(url!);
      if (
        !['localhost', '127.0.0.1'].includes(parsed.hostname) ||
        !/^\/pos02a_[a-z0-9_]+$/.test(parsed.pathname)
      )
        throw Error('Disposable loopback pos02a_ database required');
      db = new PrismaService({ datasourceUrl: url! });
      await db.$connect();
      org = await db.organization.create({
        data: {
          name: 'POS02A disposable',
          venues: {
            create: [
              { name: 'A', timezone: 'Asia/Tbilisi', currency: 'GEL' },
              { name: 'B', timezone: 'Asia/Tbilisi', currency: 'GEL' },
            ],
          },
        },
        include: { venues: true },
      });
      venue = org.venues.find((v) => v.name === 'A')!.id;
      foreign = org.venues.find((v) => v.name === 'B')!.id;
      devices = [];
      const credentialService = new DeviceCredentialService(db);
      for (let i = 0; i < 5; i++)
        devices.push(
          await credentialService.issueCredential({
            venueId: i === 4 ? foreign : venue,
            installationId: randomUUID(),
            displayName: `POS ${i + 1}`,
            platform: 'WINDOWS',
          }),
        );
      actor = (
        await db.platformUser.create({
          data: {
            email: `${randomUUID()}@pos02a.invalid`,
            displayName: 'Test operator',
            passwordHash: 'not-login-material',
            role: 'SUPER_ADMIN',
          },
        })
      ).id;
      support = (
        await db.platformUser.create({
          data: {
            email: `${randomUUID()}@pos02a.invalid`,
            displayName: 'Readonly',
            passwordHash: 'not-login-material',
            role: 'SUPPORT_READONLY',
          },
        })
      ).id;
      const secret = randomUUID();
      const jwt = new JwtService();
      const config = new ConfigService({ PLATFORM_JWT_SECRET: secret });
      const sign = (id: string) =>
        jwt.sign(
          { sub: id, typ: 'PLATFORM' },
          {
            secret,
            audience: 'vynic-platform',
            issuer: 'vynic',
            expiresIn: '30m',
          },
        );
      token = sign(actor);
      supportToken = sign(support);
      const module = await Test.createTestingModule({
        controllers: [
          PrinterEnrollmentController,
          PrinterConfigurationController,
        ],
        providers: [
          PrinterProvisioningService,
          EdgeDeviceGuard,
          DeviceCredentialService,
          PlatformAuthGuard,
          PlatformAuthService,
          { provide: PrismaService, useValue: db },
          { provide: JwtService, useValue: jwt },
          { provide: ConfigService, useValue: config },
        ],
      }).compile();
      app = module.createNestApplication();
      await app.init();
      process.env.PRINTER_PRODUCTION_SIGNING_KEY_PEM = keys.privateKey
        .export({ type: 'pkcs8', format: 'pem' })
        .toString();
      exchange = mkdtempSync(join(tmpdir(), 'pos02a-exchange-'));
      writeFileSync(
        join(exchange, 'setup.json'),
        JSON.stringify({
          issuer: Buffer.from(
            keys.publicKey.export({ format: 'jwk' }).x!,
            'base64url',
          ).toString('base64'),
          devices: devices.map((d) => d.deviceId),
        }),
      );
      go('TestProductionBackendExport');
      requests = JSON.parse(
        readFileSync(join(exchange, 'requests.json'), 'utf8'),
      ) as Enrollment[];
      const controller = randomUUID(),
        printer = randomUUID(),
        station = randomUUID();
      catalog = {
        version: 1,
        venueId: venue,
        revision: 1,
        controllers: [
          {
            id: controller,
            installationId: requests[0].installationId,
            deviceId: devices[0].deviceId,
            name: 'Fixed kitchen controller',
          },
        ],
        printers: [
          {
            id: printer,
            name: 'Kitchen',
            controllerId: controller,
            destination: {
              physicalPrinterId: printer,
              workerHostId: controller,
              transport: 'tcp',
              host: '192.168.50.20',
              port: 9100,
              queueName: '',
              expectedDriverName: '',
              expectedPortName: '',
              documentName: 'Kitchen ticket',
            },
            profile: {
              protocol: 1,
              paperWidthMm: 80,
              rasterWidthDots: 576,
              language: 'escposRaster',
              cutter: 'full',
              encoding: 'georgianViaRaster',
            },
            enabled: true,
            failoverMode: 'FIXED_CONTROLLER',
          },
        ],
        stations: [
          {
            id: station,
            name: 'Kitchen',
            role: 'production',
            scope: 'VENUE_SHARED',
            enabled: true,
            sortOrder: 0,
            routes: [printer],
          },
        ],
        rules: [{ kind: 'default', matchId: '', stations: [station] }],
      };
      if (proof)
        writeFileSync(
          join(proof, 'exchange-path.json'),
          JSON.stringify({
            exchange,
            privateIdentities: 'disposable; excluded from proof packet',
          }),
        );
    }, 120000);
    afterAll(async () => {
      if (app) await app.close();
      if (db && org) {
        await db.platformAuditEvent.deleteMany({
          where: { platformUserId: { in: [actor, support] } },
        });
        await db.printerInstallation.deleteMany({
          where: { venueId: { in: [venue, foreign] } },
        });
        await db.printerVenueAuthority.deleteMany({
          where: { venueId: { in: [venue, foreign] } },
        });
        await db.edgeFoundationInstallation.deleteMany({
          where: { venueId: { in: [venue, foreign] } },
        });
        await db.venue.updateMany({
          where: { organizationId: org.id },
          data: { activeOperationalDeviceId: null },
        });
        await db.device.deleteMany({
          where: { venueId: { in: [venue, foreign] } },
        });
        await db.venue.deleteMany({ where: { organizationId: org.id } });
        await db.organization.delete({ where: { id: org.id } });
        await db.platformUser.deleteMany({
          where: { id: { in: [actor, support] } },
        });
        await db.$disconnect();
      }
      if (oldSigner === undefined)
        delete process.env.PRINTER_PRODUCTION_SIGNING_KEY_PEM;
      else process.env.PRINTER_PRODUCTION_SIGNING_KEY_PEM = oldSigner;
    });
    it('rejects unauthenticated, legacy and wrong-principal requests', async () => {
      expect((await enroll(0, requests[0], 'legacy-key')).status).toBe(401);
      expect((await enroll(0, requests[0], token)).status).toBe(401);
      expect(
        (await platform('/configuration', {}, devices[0].credential)).status,
      ).toBe(401);
      expect((await platform('/configuration', {}, supportToken)).status).toBe(
        403,
      );
    });
    it('requires a separately provisioned production signer; creates no identity when missing', async () => {
      const old = process.env.PRINTER_PRODUCTION_SIGNING_KEY_PEM;
      delete process.env.PRINTER_PRODUCTION_SIGNING_KEY_PEM;
      try {
        expect((await enroll(0)).status).toBe(503);
        expect(
          await db.printerInstallation.count({ where: { venueId: venue } }),
        ).toBe(0);
      } finally {
        process.env.PRINTER_PRODUCTION_SIGNING_KEY_PEM = old;
      }
    });
    it('refuses using the Foundation signer as the production printer signer', async () => {
      const old = process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM;
      process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM =
        process.env.PRINTER_PRODUCTION_SIGNING_KEY_PEM;
      try {
        expect((await enroll(0)).status).toBe(503);
      } finally {
        if (old === undefined)
          delete process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM;
        else process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM = old;
      }
    });
    it('binds enrollment to Device authority and Go key possession, never body Venue', async () => {
      expect(
        (await enroll(0, { ...requests[0], venueId: foreign })).status,
      ).toBe(400);
      expect((await enroll(1, requests[0])).status).toBe(400);
      expect(
        (
          await enroll(0, {
            ...requests[0],
            proof: Buffer.alloc(64).toString('base64'),
          })
        ).status,
      ).toBe(400);
      const result = await enroll(0);
      expect(result.status).toBe(201);
      const raw = Buffer.from(result.body.body, 'base64');
      expect(
        verify(
          null,
          signatureInput(raw),
          keys.publicKey,
          Buffer.from(result.body.signature, 'base64'),
        ),
      ).toBe(true);
      const body = snapshot(result.body);
      expect(body).toMatchObject({
        purpose: 'VYNIC_PRINTER_PRODUCTION',
        venueId: venue,
        revision: 0,
        topology: 'LOCAL_ONLY',
        catalogRaw: '',
      });
      expect(body.expiresAt - body.issuedAt).toBe(OFFLINE_SECONDS);
      expect(body.members).toEqual([
        expect.objectContaining({
          installationId: requests[0].installationId,
          deviceId: devices[0].deviceId,
          authorized: true,
          role: 'CLIENT',
        }),
      ]);
      const row = await db.printerInstallation.findUniqueOrThrow({
        where: { id: requests[0].installationId },
      });
      expect(row.venueId).toBe(venue);
      expect(row.deviceId).toBe(devices[0].deviceId);
      save('initial', result.body);
    });
    it('handles simultaneous exact retries without duplicate identity or binding changes', async () => {
      const results = await Promise.all([enroll(0), enroll(0)]);
      expect(results.map((x) => x.status)).toEqual([201, 201]);
      expect(
        await db.printerInstallation.count({
          where: { deviceId: devices[0].deviceId },
        }),
      ).toBe(1);
      const gens = results.map((x) => snapshot(x.body).generation);
      expect(new Set(gens).size).toBe(2);
      expect((await platform()).body.members).toHaveLength(1);
    });
    it('rejects cross-Venue/device rebind even with a valid proof for that Device', async () => {
      const cross = JSON.parse(
        readFileSync(join(exchange, 'cross-device.json'), 'utf8'),
      ) as Enrollment;
      expect((await enroll(4, cross)).status).toBe(409);
      expect(
        await db.printerInstallation.count({ where: { venueId: foreign } }),
      ).toBe(0);
    });
    it('refuses reuse of Foundation identity, then enrolls two more clients independently', async () => {
      await db.edgeFoundationInstallation.create({
        data: {
          id: requests[2].installationId,
          venueId: venue,
          publicKey: requests[2].publicKey,
        },
      });
      expect((await enroll(2)).status).toBe(409);
      await db.edgeFoundationInstallation.delete({
        where: { id: requests[2].installationId },
      });
      expect((await enroll(1)).status).toBe(201);
      expect((await enroll(2)).status).toBe(201);
      const inventory = await platform();
      expect(inventory.status).toBe(200);
      expect(inventory.body.members.every((m) => m.role === 'CLIENT')).toBe(
        true,
      );
    });
    const config = () => ({
      topology: 'THREE_REPLICAS',
      voters: requests.slice(0, 3).map((r) => r.installationId),
      endpoints: Object.fromEntries(
        requests
          .slice(0, 3)
          .map((r, i) => [r.installationId, `192.168.50.${i + 10}:8443`]),
      ),
      catalog,
    });
    it('configuration cannot invent membership, foreign scope, controller rights or RAW takeover', async () => {
      const invalid = [
        { ...config(), voters: [randomUUID(), ...config().voters.slice(1)] },
        { ...config(), catalog: { ...catalog, venueId: foreign } },
        {
          ...config(),
          catalog: {
            ...catalog,
            controllers: [
              { ...catalog.controllers[0], deviceId: devices[4].deviceId },
            ],
          },
        },
        {
          ...config(),
          catalog: {
            ...catalog,
            printers: [
              {
                ...catalog.printers[0],
                failoverMode: 'QUALIFIED_FENCED_FAILOVER',
              },
            ],
          },
        },
        { ...config(), voters: config().voters.slice(0, 2) },
      ];
      for (const configuration of invalid)
        expect(
          (
            await platform('/configuration', {
              expectedRevision: 0,
              configuration,
            })
          ).status,
        ).toBe(400);
      expect((await platform()).body.revision).toBe(0);
    });
    it('publishes explicit stable membership and signed configuration without changing business primary', async () => {
      const result = await platform('/configuration', {
        expectedRevision: 0,
        configuration: config(),
      });
      expect(result.status).toBe(201);
      expect(result.body).toEqual({ revision: 1, activation: 'NOT_ACTIVATED' });
      const response = await enroll(0);
      expect(response.status).toBe(201);
      save('configured', response.body);
      const b = snapshot(response.body);
      expect(b.members.filter((m) => m.role === 'VOTER')).toHaveLength(3);
      expect(
        JSON.parse(Buffer.from(b.catalogRaw, 'base64').toString()),
      ).toEqual(catalog);
      expect(
        (await db.venue.findUniqueOrThrow({ where: { id: venue } }))
          .activeOperationalDeviceId,
      ).toBe(devices[0].deviceId);
      expect(
        await db.platformAuditEvent.count({
          where: { targetId: venue, action: 'printer.configuration_published' },
        }),
      ).toBe(1);
      expect(
        (
          await platform('/configuration', {
            expectedRevision: 0,
            configuration: config(),
          })
        ).status,
      ).toBe(409);
    });
    it('rolls back publication when audit persistence fails', async () => {
      const service = app.get<PrinterProvisioningService>(
        PrinterProvisioningService,
      ) as unknown as {
        db: PrismaService;
      };
      const old = service.db;
      service.db = db.$extends({
        query: {
          platformAuditEvent: {
            create: () =>
              Promise.reject(new Error('Injected printer audit failure')),
          },
        },
      }) as unknown as PrismaService;
      try {
        expect(
          (
            await platform('/configuration', {
              expectedRevision: 1,
              configuration: {
                ...config(),
                catalog: { ...catalog, revision: 2 },
              },
            })
          ).status,
        ).toBe(500);
      } finally {
        service.db = old;
      }
      expect((await platform()).body.revision).toBe(1);
    });
    it('does not silently transfer existing physical ownership on configuration edits', async () => {
      const changed = {
        ...config(),
        catalog: {
          ...catalog,
          revision: 2,
          controllers: [
            {
              ...catalog.controllers[0],
              installationId: requests[1].installationId,
              deviceId: devices[1].deviceId,
            },
          ],
        },
      };
      expect(
        (
          await platform('/configuration', {
            expectedRevision: 1,
            configuration: changed,
          })
        ).status,
      ).toBe(409);
    });
    it('new POS joins existing inventory as client without voter churn', async () => {
      const result = await enroll(3);
      expect(result.status).toBe(201);
      save('joined', result.body);
      const b = snapshot(result.body);
      expect(b.revision).toBe(1);
      expect(b.members).toHaveLength(4);
      expect(
        b.members.find((m) => m.installationId === requests[3].installationId)!
          .role,
      ).toBe('CLIENT');
      expect(
        b.members
          .filter((m) => m.role === 'VOTER')
          .map((m) => m.installationId)
          .sort(),
      ).toEqual(config().voters.sort());
    });
    it('revocation is scoped, idempotent, durable and blocks renewal without shrinking membership', async () => {
      expect(
        (
          await platform(
            `/installations/${requests[1].installationId}/revoke`,
            {},
            token,
            foreign,
          )
        ).status,
      ).toBe(404);
      for (let i = 0; i < 2; i++)
        expect(
          (
            await platform(
              `/installations/${requests[1].installationId}/revoke`,
              {},
            )
          ).status,
        ).toBe(201);
      expect((await enroll(1)).status).toBe(409);
      const result = await enroll(0);
      expect(result.status).toBe(201);
      save('revoked', result.body);
      const b = snapshot(result.body);
      expect(
        b.members.find((m) => m.installationId === requests[1].installationId),
      ).toMatchObject({ authorized: false, role: 'VOTER' });
    });
    it('revoked POS credential cannot renew; other peers learn Device revocation', async () => {
      await db.device.update({
        where: { id: devices[2].deviceId },
        data: { status: 'REVOKED' },
      });
      expect((await enroll(2)).status).toBe(401);
      const result = await enroll(0);
      expect(result.status).toBe(201);
      const b = snapshot(result.body);
      expect(
        b.members.find((m) => m.deviceId === devices[2].deviceId)!.authorized,
      ).toBe(false);
      expect(
        (
          await db.printerInstallation.findUniqueOrThrow({
            where: { id: requests[2].installationId },
          })
        ).revokedAt,
      ).not.toBeNull();
    });
    it('Go consumes real HTTP-issued grants, authenticates peers and denies stale/revoked rights', () => {
      go('TestProductionBackendVerify');
    }, 120000);
    it('database composite FK rejects cross-Venue installation authority', async () => {
      await expect(
        db.printerInstallation.create({
          data: {
            id: randomUUID(),
            venueId: foreign,
            deviceId: devices[0].deviceId,
            publicKey: randomUUID(),
            certificateSha256: randomUUID(),
          },
        }),
      ).rejects.toThrow();
    });
  },
);
