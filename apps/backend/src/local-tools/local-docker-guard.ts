import { existsSync } from 'node:fs';

/** Validate before constructing a client: URL query parameters can override hosts. */
export function requireLocalDocker(
  env = process.env,
  inDocker = existsSync('/.dockerenv'),
) {
  let url: URL;
  try {
    url = new URL(env.DATABASE_URL || '');
  } catch {
    throw new Error('Local Docker database required');
  }
  if (
    env.VYNIC_LOCAL_DOCKER !== 'true' ||
    !inDocker ||
    url.protocol !== 'postgresql:' ||
    url.hostname !== 'postgres' ||
    url.port !== '5432' ||
    url.pathname !== '/vynic_local_prod' ||
    url.username !== 'vynic' ||
    !url.password ||
    url.search ||
    url.hash
  )
    throw new Error(
      'Refusing: requires isolated Docker postgres:5432/vynic_local_prod, user vynic, and VYNIC_LOCAL_DOCKER=true',
    );
}
export function localDockerEnabled() {
  try {
    requireLocalDocker();
    return true;
  } catch {
    return false;
  }
}
