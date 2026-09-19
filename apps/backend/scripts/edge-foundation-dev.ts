// Isolated Nest runtime using the production provisioning controller/guard/service.
// No AppModule bootstrap, website, payments, or production environment loading.
import { writeFileSync } from 'node:fs';
import { foundationFixture } from '../test/edge-foundation.fixture';
async function main() {
  const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
  const output = process.env.EDGE_DEV_INFO_FILE;
  if (!url || !output)
    throw Error('Explicit disposable database URL and info file required');
  const f = await foundationFixture(url);
  await f.app.listen(0, '127.0.0.1');
  writeFileSync(
    output,
    JSON.stringify({
      url: await f.app.getUrl(),
      venueId: f.venueId,
      venueB: f.venueB,
      token: f.token,
      publicKey: f.publicKey,
    }),
    { mode: 0o600 },
  );
  let closing = false;
  for (const signal of ['SIGTERM', 'SIGINT'] as const)
    process.on(signal, async () => {
      if (closing) return;
      closing = true;
      try {
        await f.cleanup();
        process.exit(0);
      } catch (error) {
        console.error(error);
        process.exit(1);
      }
    });
}
main().catch((error) => {
  console.error(error);
  process.exit(1);
});
