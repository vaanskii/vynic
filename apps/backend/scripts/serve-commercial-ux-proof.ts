/** Disposable browser fixture with real owner/operator guards and no operational workers. */
import 'reflect-metadata';
import { writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { hash } from 'argon2';
import { PrismaService } from '../src/prisma.service';
import { onboardingApp } from '../test/onboarding-app.fixture';

async function main() {
  const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
  const target = new URL(url ?? 'http://invalid');
  if (
    target.hostname !== '127.0.0.1' ||
    target.port !== '55447' ||
    target.pathname !== '/vynic_website_provisioning_v2' ||
    process.argv[2] !== '--confirm-disposable'
  )
    throw Error('Explicit disposable database required');
  process.env.JWT_SECRET = 'commercial-ux-disposable-only';
  process.env.COOKIE_ENCRYPTION_KEY = 'commercial-ux-disposable-cookie';
  process.env.SAAS_WEBSITE_BASE_DOMAIN = 'vynic.localhost';
  const db = new PrismaService({ datasourceUrl: url });
  const tag = randomUUID().slice(0, 8);
  const passwordHash = await hash('DisposableUX-proof-2026!');
  const admin = await db.platformUser.create({
    data: {
      email: `ux-${tag}@test.invalid`,
      displayName: 'UX Operator',
      passwordHash,
    },
  });
  const org = await db.organization.create({
    data: { name: 'Disposable control UX' },
  });
  const owner = await db.customerAccount.create({
    data: {
      email: `ux-owner-${tag}@test.invalid`,
      displayName: 'UX Owner',
      passwordHash,
      memberships: { create: { organizationId: org.id } },
    },
  });
  const venue = await db.venue.create({
    data: {
      organizationId: org.id,
      name: 'Restaurant Vankisi',
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
      subscription: { create: { status: 'NO_PLAN' } },
    },
  });
  const app = await onboardingApp(db, [
    'http://localhost:5197',
    'http://admin.localhost:5197',
  ]);
  await app.listen(3117, '127.0.0.1');
  writeFileSync(
    '/tmp/vynic-commercial-ux-fixture.json',
    JSON.stringify({
      venueId: venue.id,
      adminEmail: admin.email,
      ownerEmail: owner.email,
    }),
  );
  console.log('Disposable commercial UX API listening on 3117');
}
main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
