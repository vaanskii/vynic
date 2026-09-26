import { isSiteKey } from './custom-website';

/**
 * Where each CUSTOM frontend's dev server runs on a developer's machine.
 *
 * A VenueDomain is domain identity (`vankisi.localhost`, `vankisi.ge`) and
 * never carries a port. The port a frontend's dev server listens on is a fact
 * about the developer's machine, not about the restaurant, so it lives in the
 * backend environment, keyed by the frontend identity the operator already
 * records (`siteKey`):
 *
 *     CUSTOM_WEBSITE_LOCAL_FRONTENDS=vankisi-web=5174,custom-b-web=5176
 *
 * It is read only outside production, is never tenant authority (the Host
 * still selects the Venue), and has no default: an unmapped frontend is
 * reported as not configured rather than guessed.
 */
export const LOCAL_FRONTENDS_ENV = 'CUSTOM_WEBSITE_LOCAL_FRONTENDS';

/** The former single global port. Ignored; reported so a stale .env shows. */
export const LEGACY_DEV_PORT_ENV = 'CUSTOM_WEBSITE_DEV_PORT';

const MIN_PORT = 1024;
const MAX_PORT = 65535;

export interface LocalFrontendRegistry {
  ports: ReadonlyMap<string, number>;
  /** Refused entries and stale settings, worded for the operator. */
  problems: string[];
}

/**
 * Parses `<siteKey>=<port>[,…]`. A malformed, duplicated or clashing entry is
 * dropped and reported; it never falls back to some other port.
 */
export function parseLocalFrontends(
  raw: string | undefined,
): LocalFrontendRegistry {
  const ports = new Map<string, number>();
  const problems: string[] = [];
  const ambiguous = new Set<string>();
  for (const entry of (raw ?? '').split(',')) {
    const text = entry.trim();
    if (!text) continue;
    const match = /^([^=\s]+)\s*=\s*(\d+)$/.exec(text);
    if (!match || !isSiteKey(match[1])) {
      problems.push(`"${text}" is not <frontend identity>=<port>`);
      continue;
    }
    const [, key, digits] = match;
    const port = Number(digits);
    if (port < MIN_PORT || port > MAX_PORT) {
      problems.push(`${key}: port must be ${MIN_PORT}-${MAX_PORT}`);
      continue;
    }
    if (ports.has(key)) {
      problems.push(`${key} is listed more than once`);
      ambiguous.add(key);
      continue;
    }
    // One port is one dev server, which is one build.
    const clash = [...ports].find(([, p]) => p === port)?.[0];
    if (clash) {
      problems.push(`${clash} and ${key} both claim port ${port}`);
      ambiguous.add(clash).add(key);
    }
    ports.set(key, port);
  }
  for (const key of ambiguous) ports.delete(key);
  return { ports, problems };
}

export function isLocalHostname(hostname: string): boolean {
  return hostname.endsWith('.localhost');
}

export type LocalFrontendState =
  | 'CONFIGURED'
  | 'NO_SITE_KEY'
  | 'NO_LOCAL_DOMAIN'
  | 'NOT_CONFIGURED';

/** The operator's development-only view of where this Venue's frontend runs. */
export interface LocalFrontend {
  state: LocalFrontendState;
  siteKey: string | null;
  /** The Venue's ACTIVE `.localhost` domain the dev server is opened on. */
  hostname: string | null;
  port: number | null;
  /** `http://<hostname>:<port>/`, only when fully configured. */
  url: string | null;
  /** The setting to edit, so nobody has to guess where a port came from. */
  source: typeof LOCAL_FRONTENDS_ENV;
  detail: string;
  problems: string[];
}

export function localFrontend(
  facts: { siteKey: string | null; hostname: string | null },
  registry: LocalFrontendRegistry,
): LocalFrontend {
  const base = {
    siteKey: facts.siteKey,
    hostname: facts.hostname,
    source: LOCAL_FRONTENDS_ENV,
    problems: registry.problems,
  } as const;
  if (!facts.siteKey)
    return {
      ...base,
      state: 'NO_SITE_KEY',
      port: null,
      url: null,
      detail: 'Record the custom frontend identity first',
    };
  const port = registry.ports.get(facts.siteKey) ?? null;
  if (!facts.hostname)
    return {
      ...base,
      state: 'NO_LOCAL_DOMAIN',
      port,
      url: null,
      detail: 'Register an active .localhost domain for local development',
    };
  if (port === null)
    return {
      ...base,
      state: 'NOT_CONFIGURED',
      port: null,
      url: null,
      detail: `Local frontend for ${facts.siteKey} is not configured: add ${facts.siteKey}=<port> to ${LOCAL_FRONTENDS_ENV} in the backend environment and restart it`,
    };
  return {
    ...base,
    state: 'CONFIGURED',
    port,
    url: `http://${facts.hostname}:${port}/`,
    detail: `${facts.siteKey}=${port} in ${LOCAL_FRONTENDS_ENV}`,
  };
}
