// Explicit fixture for one disposable database. Never reads a production env URL.
async function seedWebsiteW2() {
  const raw = process.env.W2_TEST_DATABASE_URL;
  if (!raw || process.argv[2] !== '--confirm-local')
    throw Error('Explicit local URL and --confirm-local required');
  const u = new URL(raw);
  if (
    u.hostname !== '127.0.0.1' ||
    u.port !== '55439' ||
    u.pathname !== '/vynic_w2_disposable'
  )
    throw Error('Only disposable W2 database permitted');
  process.env.DATABASE_URL = raw;
  const { PrismaService } = require('../src/prisma.service');
  const { ConfigService } = require('@nestjs/config');
  const {
    VenueEntitlementsService,
  } = require('../src/entitlements/venue-entitlements.service');
  const {
    WebsiteTenantService,
  } = require('../src/website/tenancy/website-tenant.service');
  const {
    WebsiteCoreService,
  } = require('../src/website/core/website-core.service');
  const {
    emptyWebsiteContent,
  } = require('../src/website/core/website-content');
  const argon2 = require('argon2');
  const db = new PrismaService({ datasourceUrl: raw });
  const config = new ConfigService({ SAAS_WEBSITE_BASE_DOMAIN: 'vynic.local' });
  const core = new WebsiteCoreService(
    db,
    new VenueEntitlementsService(db),
    new WebsiteTenantService(db, config),
    config,
  );
  try {
    const feature = await db.feature.findUniqueOrThrow({
      where: { key: 'WEBSITE' },
    });
    for (const slug of ['restaurant-a', 'restaurant-b', 'vankisi']) {
      const email = `${slug}@w2.test.invalid`;
      let account = await db.customerAccount.findUnique({ where: { email } });
      if (!account) {
        const passwordHash = await argon2.hash('Local W2 owner password!', {
          type: argon2.argon2id,
        });
        account = await db.customerAccount.create({
          data: {
            email,
            passwordHash,
            displayName: 'Local W2 owner',
            organization: { create: { name: `W2 local ${slug}` } },
          },
        });
      }
      let venue = await db.venue.findFirst({
        where: { organizationId: account.organizationId },
      });
      if (!venue)
        venue = await db.venue.create({
          data: {
            organizationId: account.organizationId,
            name: `Local ${slug}`,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            websiteConfig: {
              create: { mode: slug === 'vankisi' ? 'CUSTOM' : 'SAAS' },
            },
            domains: { create: { hostname: `${slug}.vynic.local` } },
            featureOverrides: {
              create: { featureId: feature.id, effect: 'ENABLED' },
            },
          },
        });
      const state = await core.settings(venue.id);
      if (slug !== 'vankisi' && state.revision === 0) {
        await core.save(
          venue.id,
          {
            expectedRevision: 0,
            content: {
              ...emptyWebsiteContent,
              slug,
              heroTitle: `Welcome to ${slug}`,
            },
          },
          account.id,
        );
        await core.publish(venue.id, { expectedRevision: 1 }, account.id);
      }
      console.log(
        JSON.stringify({
          email,
          venueId: venue.id,
          host: `${slug}.vynic.local`,
        }),
      );
    }
  } finally {
    await db.$disconnect();
  }
}
seedWebsiteW2().catch(() => {
  console.error(
    'W2 local fixture failed; check the disposable database and explicit arguments.',
  );
  process.exitCode = 1;
});
