import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { generateKeyPairSync, randomUUID } from 'node:crypto';
import { PrismaService } from '../src/prisma.service';
import {
  EdgeFoundationController,
  EdgeFoundationService,
} from '../src/edge-foundation/edge-foundation';
import { PlatformAuthGuard } from '../src/platform/platform-auth.guard';
import { PlatformAuthService } from '../src/platform/platform-auth.service';
import { DeviceCredentialService } from '../src/auth/device-credential.service';

export async function foundationFixture(url: string) {
  const parsed = new URL(url);
  if (
    !['localhost', '127.0.0.1'].includes(parsed.hostname) ||
    !/^\/phase1_[a-z0-9_]+$/.test(parsed.pathname)
  )
    throw Error('Disposable loopback phase1_ database required');
  const tag = randomUUID();
  const db = new PrismaService({ datasourceUrl: url });
  await db.$connect();
  const org = await db.organization.create({
    data: {
      name: tag,
      venues: {
        create: ['A', 'B', 'Disabled'].map((name) => ({
          name,
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          status: name === 'Disabled' ? 'DISABLED' : 'ACTIVE',
        })),
      },
    },
    include: { venues: true },
  });
  const venue = (name: string) => org.venues.find((v) => v.name === name)!.id;
  const primary = await new DeviceCredentialService(db).issueCredential({
    venueId: venue('A'),
    displayName: 'Phase 0 primary',
    installationId: randomUUID(),
    platform: 'WINDOWS',
  });
  const admin = await db.platformUser.create({
    data: {
      email: `${tag}@phase1.invalid`,
      displayName: 'Foundation test operator',
      passwordHash: 'not-a-login-password',
      role: 'SUPER_ADMIN',
    },
  });
  const support = await db.platformUser.create({
    data: {
      email: `support-${tag}@phase1.invalid`,
      displayName: 'Readonly test operator',
      passwordHash: 'not-a-login-password',
      role: 'SUPPORT_READONLY',
    },
  });
  const jwt = new JwtService();
  const secret = randomUUID();
  const config = new ConfigService({ PLATFORM_JWT_SECRET: secret });
  const keys = generateKeyPairSync('ed25519');
  const oldSigningKey = process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM;
  process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM = keys.privateKey
    .export({ type: 'pkcs8', format: 'pem' })
    .toString();
  const module = await Test.createTestingModule({
    controllers: [EdgeFoundationController],
    providers: [
      EdgeFoundationService,
      PlatformAuthGuard,
      PlatformAuthService,
      { provide: PrismaService, useValue: db },
      { provide: JwtService, useValue: jwt },
      { provide: ConfigService, useValue: config },
    ],
  }).compile();
  const app = module.createNestApplication();
  const token = (id: string) =>
    jwt.sign(
      { sub: id, typ: 'PLATFORM' },
      { secret, audience: 'vynic-platform', issuer: 'vynic', expiresIn: '10m' },
    );
  await app.init();
  return {
    app,
    db,
    venueId: venue('A'),
    venueB: venue('B'),
    disabledVenue: venue('Disabled'),
    primary,
    token: token(admin.id),
    supportToken: token(support.id),
    publicKey: keys.publicKey
      .export({ type: 'spki', format: 'pem' })
      .toString(),
    cleanup: async () => {
      await app.close();
      await db.platformAuditEvent.deleteMany({
        where: { platformUserId: { in: [admin.id, support.id] } },
      });
      await db.edgeFoundationInstallation.deleteMany({
        where: { venueId: { in: org.venues.map((v) => v.id) } },
      });
      await db.device.deleteMany({
        where: { venueId: { in: org.venues.map((v) => v.id) } },
      });
      await db.venue.deleteMany({ where: { organizationId: org.id } });
      await db.organization.delete({ where: { id: org.id } });
      await db.platformUser.deleteMany({
        where: { id: { in: [admin.id, support.id] } },
      });
      await db.$disconnect();
      if (oldSigningKey === undefined)
        delete process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM;
      else process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM = oldSigningKey;
    },
  };
}
