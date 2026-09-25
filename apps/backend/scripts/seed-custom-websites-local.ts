// Explicit fixture for one fresh disposable database. Never reads a production env URL.
//
// Provisions the local CUSTOM website proof through the same services the
// Platform Admin routes call, so the fixture exercises the operator workflow
// rather than writing rows by hand:
//
//   custom-a.vynic.localhost  CUSTOM, frontend custom-a-web, ACTIVE, own BOG
//   custom-b.vynic.localhost  CUSTOM, frontend custom-b-web, ACTIVE, own BOG
//   <assigned>.vynic.local    SAAS (must never be served as CUSTOM)
//
// Usage (from apps/backend):
//   CUSTOM_WEBSITE_LOCAL_DATABASE_URL=postgresql://…@127.0.0.1:55439/disposable_… \
//   PAYMENT_INTEGRATION_MASTER_KEY=<64 hex> \
//   npx ts-node -T scripts/seed-custom-websites-local.ts --confirm-local
async function seedCustomWebsites() {
  const raw = process.env.CUSTOM_WEBSITE_LOCAL_DATABASE_URL;
  if (!raw || process.argv[2] !== '--confirm-local')
    throw Error('Explicit local URL and --confirm-local required');
  const { isFreshDisposableDatabase } = require('../test/disposable-database');
  if (!isFreshDisposableDatabase(raw))
    throw Error('Only a fresh loopback disposable_* database is permitted');
  if (!process.env.PAYMENT_INTEGRATION_MASTER_KEY)
    throw Error(
      'PAYMENT_INTEGRATION_MASTER_KEY is required to encrypt fixture BOG settings',
    );
  process.env.DATABASE_URL = raw;
  process.env.SAAS_WEBSITE_BASE_DOMAIN = 'vynic.local';
  const { PrismaService } = require('../src/prisma.service');
  const {
    VenueEntitlementsService,
  } = require('../src/entitlements/venue-entitlements.service');
  const {
    PlatformAuditService,
  } = require('../src/platform/platform-audit.service');
  const {
    PlatformDirectoryService,
  } = require('../src/platform/platform-directory.service');
  const {
    PlatformVenueConfigService,
  } = require('../src/platform/platform-venue-config.service');
  const {
    PaymentIntegrationsService,
  } = require('../src/payment-integrations/payment-integrations.service');
  const {
    WebsiteMenuService,
  } = require('../src/website/core/website-menu.service');
  const {
    CustomWebsiteService,
  } = require('../src/website/custom/custom-website.service');

  const db = new PrismaService({ datasourceUrl: raw });
  if (
    await db.venueDomain.findFirst({
      where: { hostname: 'custom-a.vynic.localhost' },
    })
  )
    throw Error('Fixture already present; use a new disposable database');
  const access = new VenueEntitlementsService(db);
  const audit = new PlatformAuditService(db);
  const platform = new PlatformVenueConfigService(
    db,
    access,
    new PlatformDirectoryService(db, audit),
    audit,
  );
  const custom = new CustomWebsiteService(
    db,
    access,
    new WebsiteMenuService(db),
  );
  const payments = new PaymentIntegrationsService(db, access);
  const operator = await db.platformUser.create({
    data: {
      email: 'local-operator@vynic.localhost',
      displayName: 'Local operator',
      passwordHash: 'not-a-login',
    },
  });
  const actor = { platformUserId: operator.id, role: 'SUPER_ADMIN' };
  const onlinePayments = await db.feature.findUniqueOrThrow({
    where: { key: 'ONLINE_PAYMENTS' },
  });

  const fixtures = [
    {
      key: 'a',
      name: 'Custom A Grill',
      mode: 'CUSTOM',
      dishes: [
        ['მწვადი', 'Mtsvadi', 24],
        ['ლობიანი', 'Lobiani', 9],
      ],
    },
    {
      key: 'b',
      name: 'Custom B Wine Bar',
      mode: 'CUSTOM',
      dishes: [
        ['საფერავი', 'Saperavi', 18],
        ['ყველი', 'Cheese plate', 22],
      ],
    },
    { key: 's', name: 'Saas S Cafe', mode: 'SAAS', dishes: [] },
  ] as const;

  for (const f of fixtures) {
    const org = await db.organization.create({ data: { name: f.name } });
    const venue = await db.venue.create({
      data: {
        organizationId: org.id,
        name: f.name,
        address: `${f.key.toUpperCase()} Street 1, Tbilisi`,
        phone: `+995 555 00 00 0${f.key === 'a' ? 1 : f.key === 'b' ? 2 : 3}`,
        timezone: 'Asia/Tbilisi',
        currency: 'GEL',
        // The commercial state a dated Website Trial leaves.
        planAssignment: {
          create: { plan: { connect: { key: 'WEBSITE_ONLY' } } },
        },
        subscription: {
          create: {
            status: 'TRIAL',
            startedAt: new Date(),
            trialEndsAt: new Date(Date.now() + 30 * 86_400_000),
          },
        },
        featureOverrides:
          f.mode === 'CUSTOM'
            ? { create: { featureId: onlinePayments.id, effect: 'ENABLED' } }
            : undefined,
      },
    });
    // Operator: select the implementation.
    await platform.setWebsiteMode(actor, venue.id, f.mode);
    if (f.mode !== 'CUSTOM') {
      console.log(
        `${f.name}: SAAS ${JSON.stringify(await db.venueDomain.findMany({ where: { venueId: venue.id }, select: { hostname: true } }))}`,
      );
      continue;
    }
    const hostname = `custom-${f.key}.vynic.localhost`;
    // Operator: bind the domain, record the frontend, mark it live.
    await platform.registerDomain(actor, venue.id, hostname);
    await custom.platformUpdate(actor, venue.id, {
      siteKey: `custom-${f.key}-web`,
      status: 'ACTIVE',
      statusNote: 'Local proof fixture',
    });
    // Owner-equivalent: this Venue's own (fake) BOG credentials.
    await payments.save(
      venue.id,
      {
        clientId: `local-client-${f.key}`,
        clientSecret: `local-secret-${f.key}`,
        returnOrigin: `http://${hostname}:5176`,
      },
      { importOperator: 'seed-custom-websites-local' },
    );
    const category = await db.menuCategory.create({
      data: {
        venueId: venue.id,
        slug: 'menu',
        nameKa: 'მენიუ',
        nameEn: 'Menu',
      },
    });
    for (const [i, [nameKa, nameEn, price]] of f.dishes.entries())
      await db.menuItem.create({
        data: {
          venueId: venue.id,
          categoryId: category.id,
          nameKa,
          nameEn,
          price,
          sortOrder: i,
        },
      });
    for (let n = 1; n <= 3; n++)
      await db.websiteTable.create({
        data: {
          venueId: venue.id,
          websiteTableNumber: `table${n}`,
          posTableNumber: String(n),
          posFloor: 'first',
          capacity: 2 + n,
        },
      });
    console.log(`${f.name}: ${hostname} → custom-${f.key}-web (ACTIVE)`);
  }
  await db.$disconnect();
}

seedCustomWebsites().catch((error) => {
  console.error(
    'CUSTOM website local fixture failed; check the disposable database and explicit arguments.',
    error,
  );
  process.exitCode = 1;
});
