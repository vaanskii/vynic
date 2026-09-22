// Isolated HTTP harness: real Website Core/owner auth, no operational workers.
//
// It serves exactly the routes the generic SaaS website consumes plus the owner
// routes the Customer Portal calls, so `apps/restaurant-web` and the portal can
// be driven locally without starting the full backend. It is a development
// tool, not a production server.
async function serveWebsiteW3() {
  const raw = process.env.W3_TEST_DATABASE_URL;
  if (!raw || process.argv[2] !== '--confirm-local')
    throw Error('Explicit local URL and --confirm-local required');
  const u = new URL(raw);
  if (
    u.hostname !== '127.0.0.1' ||
    u.port !== '55439' ||
    u.pathname !== '/vynic_w3_disposable'
  )
    throw Error('Only the disposable website database is permitted');
  process.env.DATABASE_URL = raw;
  process.env.JWT_SECRET = 'w3-disposable-http-harness-only';
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
    WebsiteMenuService,
  } = require('../src/website/core/website-menu.service');
  const {
    WebsitePreviewTokens,
  } = require('../src/website/core/website-preview');
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
    SAAS_WEBSITE_PREVIEW_ORIGIN: 'http://restaurant-a.vynic.local:5175',
  });
  const access = new VenueEntitlementsService(db);
  const jwt = new JwtService();
  const menus = new WebsiteMenuService(db);
  const previews = new WebsitePreviewTokens(db, jwt);
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
          menus,
        ),
      },
      { provide: WebsiteMenuService, useValue: menus },
      { provide: WebsitePreviewTokens, useValue: previews },
      { provide: ConfigService, useValue: config },
      // Only venue ownership is exposed through CustomerWebsiteController.
      {
        provide: CustomerService,
        useValue: new CustomerService(db, access, undefined, undefined),
      },
      {
        provide: CustomerAuth,
        useValue: new CustomerAuth(db, jwt, new EnrollmentRateLimiter()),
      },
    ],
  }).compile();
  const app = mod.createNestApplication();
  // The local frontends run on their own dev ports; the Host header they send
  // through their proxy stays the tenancy authority.
  app.enableCors({
    origin: /^http:\/\/[a-z0-9.-]*vynic\.local(:\d+)?$/,
    credentials: false,
  });
  await app.listen(3102, '0.0.0.0');
  const stop = async () => {
    await app.close();
    await db.$disconnect();
    process.exit(0);
  };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  console.log('W3 local Website Core listening on 0.0.0.0:3102');
}
serveWebsiteW3().catch((error) => {
  console.error('W3 local server failed; check explicit local inputs.', error);
  process.exitCode = 1;
});
