// Local canonical-Menu proof harness (docs/CANONICAL_MENU_SYNC.md).
// Refuses anything but a fresh disposable loopback database, before importing
// application code. Seeds one Website-only Venue whose owner authors the Menu,
// then adds POS and enrolls terminals; writes their credentials to a local
// fixture file (never printed) for the live Flutter proof.
import { writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

async function main() {
  const raw = process.env.CANONICAL_MENU_TEST_DATABASE_URL;
  const { isFreshDisposableDatabase } = require('../test/disposable-database');
  if (
    process.argv[2] !== '--confirm-local' ||
    !raw ||
    !isFreshDisposableDatabase(raw)
  )
    throw Error('Explicit fresh disposable_* database on 127.0.0.1 required');
  const fixture = process.env.CANONICAL_MENU_LIVE_FIXTURE;
  if (!fixture) throw Error('CANONICAL_MENU_LIVE_FIXTURE path required');
  const port = Number(process.env.CANONICAL_MENU_PORT || 3110);
  process.env.DATABASE_URL = raw;
  process.env.JWT_SECRET = 'canonical-menu-local-disposable-signing';
  process.env.COOKIE_ENCRYPTION_KEY = 'canonical-menu-local-disposable-cookie';
  const { PrismaService } = require('../src/prisma.service');
  const { onboardingApp } = require('../test/onboarding-app.fixture');
  const {
    OwnerInvitationsService,
  } = require('../src/customer/owner-invitations.service');
  const {
    PlatformVenueConfigService,
  } = require('../src/platform/platform-venue-config.service');
  const db = new PrismaService({ datasourceUrl: raw });
  const app = await onboardingApp(db, [/^http:\/\/[a-z0-9.-]*localhost:\d+$/]);
  await app.listen(port, '127.0.0.1');
  const base = `http://127.0.0.1:${port}`;
  const post = async (
    path: string,
    body: unknown,
    headers: Record<string, string> = {},
  ) => {
    const response = await fetch(base + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify(body),
    });
    const json = await response.json();
    if (!response.ok)
      throw Error(`${path} ${response.status} ${JSON.stringify(json)}`);
    return json;
  };

  if (process.env.CANONICAL_MENU_SEED !== '0') {
    const tag = randomUUID().slice(0, 8);
    const feature = (key: string) =>
      db.feature.upsert({
        where: { key },
        create: { key, name: key },
        update: {},
      });
    const website = await feature('WEBSITE');
    const pos = await feature('POS');
    const plan = await db.plan.upsert({
      where: { key: 'website-only-local' },
      create: {
        key: 'website-only-local',
        name: 'Website',
        features: { create: { featureId: website.id } },
      },
      update: {},
    });
    const admin = await db.platformUser.create({
      data: {
        email: `menu-proof-${tag}@test.invalid`,
        displayName: 'Operator',
        passwordHash: 'unused',
      },
    });
    const actor = { platformUserId: admin.id, role: 'SUPER_ADMIN' };
    const password = `Canonical menu ${randomUUID()}!`;
    const email = `owner-${tag}@menu.test.invalid`;
    const prepared = await app.get(OwnerInvitationsService).provision(actor, {
      organizationName: `Canonical ${tag}`,
      name: 'Canonical Tavern',
      email,
      planId: plan.id,
      subscriptionStatus: 'ACTIVE',
      websiteMode: 'SAAS',
    });
    const owner = await post('/customer/invitations/register', {
      token: prepared.invitationPath.split('=')[1],
      displayName: 'Owner',
      password,
    });
    const venueId = prepared.venue.id as string;
    await app
      .get(PlatformVenueConfigService)
      .enableCloudMenu(actor, venueId, true);
    const auth = { Authorization: `Bearer ${owner.access_token}` };
    const mutate = (m: object) =>
      post(
        `/customer/venues/${venueId}/catalog/mutations`,
        {
          mutationId: randomUUID(),
          operation: 'UPSERT',
          expectedRevision: 0,
          ...m,
        },
        auth,
      );
    // Website-only: the owner authors Category -> Subcategory -> Item -> Variant.
    const ids = {
      category: randomUUID(),
      subcategory: randomUUID(),
      khinkali: randomUUID(),
      wine: randomUUID(),
      glass: randomUUID(),
    };
    await mutate({
      entityType: 'CATEGORY',
      entityId: ids.category,
      patch: { nameKa: 'სამზარეულო', nameEn: 'Kitchen' },
    });
    await mutate({
      entityType: 'SUBCATEGORY',
      entityId: ids.subcategory,
      patch: { categoryId: ids.category, nameKa: 'ცხელი', nameEn: 'Hot' },
    });
    await mutate({
      entityType: 'ITEM',
      entityId: ids.khinkali,
      patch: {
        subcategoryId: ids.subcategory,
        nameKa: 'ხინკალი',
        nameEn: 'Khinkali',
        price: 2,
      },
    });
    await mutate({
      entityType: 'ITEM',
      entityId: ids.wine,
      patch: {
        categoryId: ids.category,
        nameKa: 'ღვინო',
        nameEn: 'Wine',
        price: 0,
        sortOrder: 1,
      },
    });
    await mutate({
      entityType: 'VARIANT',
      entityId: ids.glass,
      patch: { menuItemId: ids.wine, size: 0.15, price: 9 },
    });
    // Later the owner buys POS for the SAME Venue and enrolls three terminals.
    await db.venueFeatureOverride.create({
      data: {
        venueId,
        featureId: pos.id,
        effect: 'ENABLED',
        note: 'local proof',
      },
    });
    const credentials: string[] = [];
    for (let i = 0; i < 3; i++) {
      const issued = await post(
        `/customer/venues/${venueId}/enrollments`,
        {},
        auth,
      );
      const enrolled = await post('/edge/enroll', {
        enrollmentCode: issued.code,
        installationId: randomUUID(),
        platform: 'WINDOWS',
      });
      credentials.push(enrolled.credential);
    }
    const settings = await (
      await fetch(`${base}/customer/venues/${venueId}/website`, {
        headers: auth,
      })
    ).json();
    writeFileSync(
      fixture,
      JSON.stringify({
        baseUrl: base,
        venueId,
        ownerToken: owner.access_token,
        ownerEmail: email,
        ownerPassword: password,
        credentials,
        ids,
        host: settings?.draft?.slug
          ? `${settings.draft.slug}.vynic.localhost`
          : null,
      }),
      { mode: 0o600 },
    );
  }
  console.log(`Disposable canonical Menu backend ready on ${base}`);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
