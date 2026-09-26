import { spawn } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { requireLocalDocker } from '../src/local-tools/local-docker-guard';
requireLocalDocker();
// Use the backend-generated engine already baked into this image. No runtime download.
const clientDir = dirname(require.resolve('.prisma/client/default'));
const engines = readdirSync(clientDir).filter((name) =>
  /^libquery_engine-.+\.so\.node$/.test(name),
);
if (engines.length !== 1)
  throw new Error('Expected one generated Linux Prisma query engine');
// The isolated Postgres service has no TLS; Studio uses a separate query engine.
// Append this only AFTER rejecting all caller-supplied connection options.
// No browser inside the container; only the local override publishes this port.
const child = spawn(
  'node_modules/.bin/prisma',
  [
    'studio',
    '--schema',
    'prisma/schema.prisma',
    '--hostname',
    '0.0.0.0',
    '--port',
    '5555',
    '--browser',
    'none',
  ],
  {
    stdio: 'inherit',
    env: {
      ...process.env,
      PRISMA_QUERY_ENGINE_LIBRARY: join(clientDir, engines[0]),
      CHECKPOINT_DISABLE: '1',
      DATABASE_URL: `${process.env.DATABASE_URL}?sslmode=disable`,
    },
  },
);
for (const signal of ['SIGTERM', 'SIGINT'] as const)
  process.on(signal, () => child.kill(signal));
child.on('error', (error) => {
  console.error(error.message);
  process.exitCode = 1;
});
child.on('exit', (code) => {
  process.exitCode = code ?? 1;
});
