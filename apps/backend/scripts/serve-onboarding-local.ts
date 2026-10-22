// Validate the explicit disposable URL before importing any application / dotenv code.
async function main() {
  const raw = process.env.ONBOARDING_TEST_DATABASE_URL;
  const url = raw ? new URL(raw) : null;
  if (
    process.argv[2] !== '--confirm-local' ||
    !url ||
    url.hostname !== '127.0.0.1' ||
    url.port !== '55439' ||
    url.pathname !== '/vynic_onboarding_phase3_disposable'
  )
    throw Error(
      'Explicit loopback onboarding disposable database and --confirm-local required',
    );
  process.env.DATABASE_URL = raw;
  process.env.JWT_SECRET = 'onboarding-disposable-local-signing-key';
  process.env.COOKIE_ENCRYPTION_KEY = 'onboarding-disposable-local-cookie-key';
  // Load only after validating the disposable URL, before dotenv can supply a database.
  const { PrismaService } =
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    require('../src/prisma.service') as typeof import('../src/prisma.service');
  const { onboardingApp } =
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    require('../test/onboarding-app.fixture') as typeof import('../test/onboarding-app.fixture');
  const argon2 = await import('argon2');
  const db = new PrismaService({ datasourceUrl: raw });
  await db.$connect();
  // Idempotent seed; no pilot owner or Venue is pre-created.
  await db.platformUser.upsert({
    where: { email: 'admin@onboarding.test.invalid' },
    create: {
      email: 'admin@onboarding.test.invalid',
      displayName: 'Local onboarding admin',
      passwordHash: await argon2.hash('Local onboarding admin password!'),
    },
    update: {},
  });
  let plan = await db.plan.findUnique({ where: { key: 'onboarding-local' } });
  if (!plan)
    plan = await db.plan.create({
      data: {
        key: 'onboarding-local',
        name: 'Local website trial',
        features: {
          create: ['POS', 'MANAGER_APP', 'WEBSITE'].map((key) => ({
            feature: { connect: { key } },
          })),
        },
      },
    });
  await db.onboardingPolicy.upsert({
    where: { id: 'default' },
    create: { enabled: true, trialPlanId: plan.id, defaultWebsiteMode: 'SAAS' },
    update: {},
  });
  const app = await onboardingApp(db);
  await app.listen(3000, '127.0.0.1');
  const stop = async () => {
    await app.close();
    await db.$disconnect();
    process.exit(0);
  };
  const shutdown = () => {
    void stop().catch(() => {
      console.error('Local harness shutdown failed');
      process.exitCode = 1;
    });
  };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
  console.log('Disposable onboarding backend ready on 127.0.0.1:3000');
}
main().catch(() => {
  console.error(
    'Local onboarding harness failed; verify the disposable URL, migrations and port availability.',
  );
  process.exitCode = 1;
});
