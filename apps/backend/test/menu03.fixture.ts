import { supportedMenuClientHeader } from './menu-client.fixture';
import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import { PrismaService } from '../src/prisma.service';
import { CustomerAuth } from '../src/customer/customer-auth';
import { DeviceCredentialService } from '../src/auth/device-credential.service';
import type { MutationAccepted } from '../src/menu-catalog/menu-catalog.service';
import { onboardingApp } from './onboarding-app.fixture';
import { isFreshDisposableDatabase } from './disposable-database';

export interface Menu03Venue {
  venueId: string;
  ownerId: string;
  ownerToken: string;
  credential: string;
}
export interface Menu03Fixture {
  venues: Menu03Venue[];
}

export async function menu03App(url: string) {
  if (!isFreshDisposableDatabase(url)) throw Error('Disposable DB required');
  process.env.JWT_SECRET = 'menu03-disposable-signing-only';
  process.env.COOKIE_ENCRYPTION_KEY = 'menu03-disposable-cookie-only';
  const db = new PrismaService({ datasourceUrl: url });
  const app = await onboardingApp(db);
  await app.listen(0, '127.0.0.1');
  return { db, app, base: await app.getUrl() };
}

export async function seedMenu03(db: PrismaService, app: INestApplication) {
  const tag = randomUUID();
  const website = await db.feature.upsert({
    where: { key: 'WEBSITE' },
    create: { key: 'WEBSITE', name: 'Website' },
    update: {},
  });
  const plan = await db.plan.create({
    data: {
      key: `menu03-${tag}`,
      name: 'MENU03 synthetic',
      features: { create: { featureId: website.id } },
    },
  });
  const venues: Menu03Venue[] = [];
  for (const label of ['a', 'b']) {
    const organization = await db.organization.create({
      data: { name: `MENU03 ${label} ${tag}` },
    });
    const venue = await db.venue.create({
      data: {
        organizationId: organization.id,
        name: `MENU03 ${label}`,
        timezone: 'Asia/Tbilisi',
        currency: 'GEL',
        menuAuthority: 'CLOUD',
        cloudMenuEditingEnabled: true,
        subscription: { create: { status: 'ACTIVE' } },
        planAssignment: { create: { planId: plan.id } },
      },
    });
    const owner = await db.customerAccount.create({
      data: {
        email: `${label}-${tag}@menu03.test.invalid`,
        displayName: 'Synthetic owner',
        passwordHash: 'unused; session issued by test setup',
        memberships: { create: { organizationId: organization.id } },
      },
    });
    const session = await app.get(CustomerAuth).session(owner);
    const device = await app.get(DeviceCredentialService).issueCredential({
      venueId: venue.id,
      installationId: randomUUID(),
      displayName: 'Synthetic POS',
      platform: 'WINDOWS',
    });
    venues.push({
      venueId: venue.id,
      ownerId: owner.id,
      ownerToken: session.access_token,
      credential: device.credential,
    });
  }
  return { venues };
}

export async function menu03Request(
  base: string,
  venue: Menu03Venue,
  body: unknown,
  writer: 'DEVICE' | 'OWNER' = 'DEVICE',
) {
  const response = await fetch(
    base +
      (writer === 'DEVICE'
        ? '/edge/menu/mutations'
        : `/customer/venues/${venue.venueId}/catalog/mutations`),
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Vynic-Menu-Client': supportedMenuClientHeader,
        ...(writer === 'DEVICE'
          ? { 'X-POS-Sync-Key': venue.credential }
          : { Authorization: `Bearer ${venue.ownerToken}` }),
      },
      body: JSON.stringify(body),
    },
  );
  return {
    status: response.status,
    body: (await response.json()) as MutationAccepted & {
      code?: string;
      resyncRequired?: boolean;
      conflict?: { currentRevision: number };
    },
  };
}

/** duplicate is per-delivery metadata; every business-result field is exact. */
export function menu03Outcome(body: MutationAccepted) {
  const { duplicate, ...outcome } = body;
  void duplicate;
  return outcome;
}
