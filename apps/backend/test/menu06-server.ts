/** Private loopback bridge for the native MENU06 proof. No mocked guards. */
import 'reflect-metadata';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { menu06App, seedMenu06, menu06Product } from './menu06.fixture';
async function main() {
  const path = process.env.MENU06_HTTP_FIXTURE;
  if (!path?.startsWith('/private/tmp/vynic-menu06-proof-'))
    throw Error('Owned temporary fixture path required');
  const live = await menu06App(process.env.MENU06_TEST_DATABASE_URL!);
  const fixture = existsSync(path)
    ? (JSON.parse(readFileSync(path, 'utf8')) as Record<string, unknown>)
    : { venues: (await seedMenu06(live.db, live.app)).venues };
  if (!fixture.product)
    fixture.product = await menu06Product(
      live.db,
      live.app,
      (fixture.venues as Awaited<ReturnType<typeof seedMenu06>>['venues'])[0],
      true,
    );
  writeFileSync(
    path,
    JSON.stringify(
      { ...fixture, baseUrl: live.base, backendPid: process.pid },
      null,
      2,
    ) + '\n',
    { mode: 0o600 },
  );
  console.log('MENU06 bridge ready');
  const stop = async () => {
    await live.app.close();
    await live.db.$disconnect();
    process.exit(0);
  };
  process.once('SIGTERM', () => void stop());
}
void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
