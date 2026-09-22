// Isolated HTTP harness: real Website Core/owner auth, no operational workers.
async function serveWebsiteW2() {
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
  process.env.JWT_SECRET = 'w2-disposable-http-harness-only';
  const { Test } = require('@nestjs/testing');
  const { JwtService } = require('@nestjs/jwt');
  const { ConfigService } = require('@nestjs/config');
  const { PrismaService } = require('../src/prisma.service');
  const {
    WebsiteCoreService,
  } = require('../src/website/core/website-core.service');
  const {
    WebsiteCoreController,
  } = require('../src/website/core/website-core.controller');
  const {
    WebsiteTenantService,
  } = require('../src/website/tenancy/website-tenant.service');
  const {
    CustomerWebsiteController,
  } = require('../src/customer/customer-website.controller');
  const {
    CustomerAuthController,
  } = require('../src/customer/customer.controller');
  const { CustomerService } = require('../src/customer/customer.service');
  const { CustomerAuth } = require('../src/customer/customer-auth');
  const {
    EnrollmentRateLimiter,
  } = require('../src/edge/enrollment-rate-limiter');
  const {
    VenueEntitlementsService,
  } = require('../src/entitlements/venue-entitlements.service');
  const db = new PrismaService({ datasourceUrl: raw });
  const config = new ConfigService({
    SAAS_WEBSITE_BASE_DOMAIN: 'vynic.local',
    TRUST_PROXY_HOST: 'false',
  });
  const access = new VenueEntitlementsService(db);
  const mod = await Test.createTestingModule({
    controllers: [
      WebsiteCoreController,
      CustomerWebsiteController,
      CustomerAuthController,
    ],
    providers: [
      {
        provide: WebsiteCoreService,
        useValue: new WebsiteCoreService(
          db,
          access,
          new WebsiteTenantService(db, config),
          config,
        ),
      },
      // Only venue ownership is exposed through CustomerWebsiteController.
      {
        provide: CustomerService,
        useValue: new CustomerService(db, access, undefined, undefined),
      },
      {
        provide: CustomerAuth,
        useValue: new CustomerAuth(
          db,
          new JwtService(),
          new EnrollmentRateLimiter(),
        ),
      },
    ],
  }).compile();
  const app = mod.createNestApplication();
  await app.listen(3102, '127.0.0.1');
  const stop = async () => {
    await app.close();
    await db.$disconnect();
    process.exit(0);
  };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  console.log('W2 local Website Core listening on 127.0.0.1:3102');
}
serveWebsiteW2().catch(() => {
  console.error('W2 local server failed; check explicit local inputs.');
  process.exitCode = 1;
});
