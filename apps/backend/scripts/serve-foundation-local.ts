// Validate the disposable URL before any application imports.
async function main() {
  const raw = process.env.FOUNDATION_TEST_DATABASE_URL;
  const url = raw ? new URL(raw) : null;
  if (
    process.argv[2] !== '--confirm-local' ||
    url?.hostname !== '127.0.0.1' ||
    url.port !== '55439' ||
    url.pathname !== '/vynic_foundation_phase3_disposable'
  )
    throw Error('Explicit disposable foundation database required');
  process.env.DATABASE_URL = raw;
  process.env.JWT_SECRET = 'foundation-local-disposable-signing';
  process.env.COOKIE_ENCRYPTION_KEY = 'foundation-local-disposable-cookie';
  const { PrismaService } = require('../src/prisma.service');
  const { onboardingApp } = require('../test/onboarding-app.fixture');
  const db = new PrismaService({ datasourceUrl: raw });
  const website = await db.feature.findUniqueOrThrow({
    where: { key: 'WEBSITE' },
  });
  const plan = await db.plan.upsert({
    where: { key: 'website-only-local' },
    create: {
      key: 'website-only-local',
      name: 'Website',
      features: { create: { featureId: website.id } },
    },
    update: {},
  });
  await db.onboardingPolicy.upsert({
    where: { id: 'default' },
    create: { enabled: true, trialPlanId: plan.id, defaultWebsiteMode: 'SAAS' },
    update: { enabled: true, trialPlanId: plan.id, defaultWebsiteMode: 'SAAS' },
  });
  const app = await onboardingApp(db);
  await app.listen(Number(process.env.FOUNDATION_PORT || 3000), '127.0.0.1');
  console.log('Disposable foundation backend ready');
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
