// Intentionally does not load a legacy env file. Supply explicitly selected
// variables through the operator's secret manager / controlled environment.

async function main() {
  const [venueId, operator, confirmation] = process.argv.slice(2);
  const url = process.env.DATABASE_URL;
  if (
    !/^[a-fA-F0-9]{64}$/.test(
      process.env.PAYMENT_INTEGRATION_MASTER_KEY ?? '',
    ) ||
    !venueId ||
    !operator ||
    confirmation !== '--confirm-import' ||
    !url ||
    url.includes('vankisi_database')
  )
    throw Error(
      'Explicit permitted DATABASE_URL, Venue ID, operator ID and --confirm-import required',
    );
  const legacy = {
    clientId: process.env.BOG_CLIENT_ID,
    clientSecret: process.env.BOG_CLIENT_SECRET,
    returnOrigin: process.env.BOG_RETURN_ORIGIN ?? process.env.FRONTEND_URL,
  };
  const { PrismaService } = require('../src/prisma.service');
  const {
    PaymentIntegrationsService,
  } = require('../src/payment-integrations/payment-integrations.service');
  const {
    VenueEntitlementsService,
  } = require('../src/entitlements/venue-entitlements.service');
  const db = new PrismaService({ datasourceUrl: url });
  try {
    await db.venue.findUniqueOrThrow({
      where: { id: venueId },
      select: { id: true },
    });
    const service = new PaymentIntegrationsService(
      db,
      new VenueEntitlementsService(db),
    );
    await service.save(venueId, legacy, { importOperator: operator }, true);
    console.log('BOG import complete. Entitlements unchanged.');
  } finally {
    await db.$disconnect();
  }
}
main().catch(() => {
  console.error(
    'BOG import failed. Check explicit inputs, registered domain, encryption key and existing configuration.',
  );
  process.exitCode = 1;
});
