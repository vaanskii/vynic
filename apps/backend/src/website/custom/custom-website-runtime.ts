import { localDockerHost } from '../../shared/deployment-config';
import { lookup as dnsLookup } from 'node:dns/promises';
import * as http from 'node:http';
import * as https from 'node:https';
import { BlockList, isIP } from 'node:net';
import { createHash } from 'node:crypto';

/**
 * Whether a CUSTOM site answers on its domain, observed on demand.
 *
 * Separate from the provisioning status an operator records: a site can be
 * attested ACTIVE and still be down. UNKNOWN means nobody has checked in this
 * view; nothing is stored or monitored.
 */
export type RuntimeAvailability = 'UNKNOWN' | 'REACHABLE' | 'UNREACHABLE';

/** Whether the shared backend answers for this Venue through the same domain. */
export type RuntimeApiState =
  | 'OK'
  | 'WRONG_SITE'
  | 'UNVERIFIED'
  | 'FAILED'
  | 'NOT_CHECKED';

export interface RuntimeTarget {
  hostname: string;
  /** What an operator opens; never built from request input. */
  url: string;
  /** A local dev frontend: loopback only, port from server configuration. */
  local: boolean;
  dockerProxy?: boolean;
}

export interface RuntimeCheck {
  availability: Exclude<RuntimeAvailability, 'UNKNOWN'>;
  checkedAt: string;
  hostname: string;
  url: string;
  frontend: { status: number | null; detail: string };
  api: { state: RuntimeApiState; status: number | null; detail: string };
  build: {
    state: 'VERIFIED' | 'UNRECORDED' | 'WRONG_BUILD' | 'FAILED' | 'NOT_CHECKED';
    status: number | null;
    detail: string;
    observedBuildId: string | null;
    expectedBuildId: string | null;
    siteKey: string | null;
  };
  /** Local or Docker observations never constitute a production acceptance. */
  environment: 'LOCAL_DEVELOPMENT' | 'LOCAL_DOCKER' | 'PUBLIC_HTTPS';
  rendererDeployed: boolean;
  bindingIdentityVerified: boolean;
}

const TIMEOUT_MS = 5000;
const MAX_BODY_BYTES = 64 * 1024;

// Everything that is not a routable public unicast address. A server-owned
// domain can still resolve here (misconfiguration, rebinding), and the check
// must never become a way to reach the backend's own network.
const nonPublic = new BlockList();
for (const [net, prefix] of [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.0.0.0', 24],
  ['192.0.2.0', 24],
  ['192.168.0.0', 16],
  ['198.18.0.0', 15],
  ['198.51.100.0', 24],
  ['203.0.113.0', 24],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4],
] as const)
  nonPublic.addSubnet(net, prefix, 'ipv4');
for (const [net, prefix] of [
  ['::', 128],
  ['::1', 128],
  ['64:ff9b::', 96],
  ['100::', 64],
  ['2001:db8::', 32],
  ['fc00::', 7],
  ['fe80::', 10],
  ['ff00::', 8],
] as const)
  nonPublic.addSubnet(net, prefix, 'ipv6');

export function isPublicAddress(address: string): boolean {
  const family = isIP(address);
  if (family === 4) return !nonPublic.check(address, 'ipv4');
  if (family !== 6) return false;
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(address);
  if (mapped) return isPublicAddress(mapped[1]);
  return !nonPublic.check(address, 'ipv6');
}

/** A registered public domain: `https://<domain>/`, public addresses only. */
export function publicTarget(hostname: string): RuntimeTarget {
  return { hostname, local: false, url: `https://${hostname}/` };
}

/**
 * A CUSTOM frontend's dev server on this machine: a `.localhost` domain the
 * Venue owns plus a port from trusted server configuration
 * (`custom-website-local.ts`). The caller builds it only outside production.
 */
export function localTarget(hostname: string, port: number): RuntimeTarget {
  if (!hostname.endsWith('.localhost'))
    throw new Error('Only a .localhost domain has a local frontend');
  if (!Number.isInteger(port) || port < 1024 || port > 65535)
    throw new Error('Local frontend port must be 1024-65535');
  return { hostname, local: true, url: `http://${hostname}:${port}/` };
}

/** The fixed Compose ingress, with a server-owned registered Host. */
export function dockerTarget(hostname: string): RuntimeTarget {
  if (!localDockerHost(hostname))
    throw new Error('Not a local Docker website host');
  return {
    hostname,
    url: `http://${hostname}/`,
    local: false,
    dockerProxy: true,
  };
}

type Resolve = (hostname: string) => Promise<string[]>;

const resolveAll: Resolve = async (hostname) =>
  (await dnsLookup(hostname, { all: true, verbatim: true })).map(
    (entry) => entry.address,
  );

/** The one address to connect to, or why the domain must not be contacted. */
async function destination(
  target: RuntimeTarget,
  resolve: Resolve,
): Promise<{ address: string } | { refused: string }> {
  if (target.dockerProxy) {
    if (!localDockerHost(target.hostname))
      return { refused: 'Local Docker mode is disabled' };
    // Fixed deployment-owned destination, never DNS supplied by a Venue domain.
    return { address: '172.30.89.2' };
  }
  if (target.local) return { address: '127.0.0.1' };
  if (isIP(target.hostname) || target.hostname.startsWith('['))
    return { refused: 'IP-address domains are not checked' };
  let addresses: string[];
  try {
    addresses = await resolve(target.hostname);
  } catch {
    return { refused: 'The domain does not resolve' };
  }
  if (addresses.length === 0) return { refused: 'The domain does not resolve' };
  // All, not any: a mixed answer is how rebinding reaches an internal host.
  if (!addresses.every(isPublicAddress))
    return { refused: 'The domain resolves to a non-public address' };
  return { address: addresses[0] };
}

interface Fetched {
  status: number;
  contentType: string;
  body: string;
}

/**
 * One GET to a fixed path on the validated address, with the domain as Host
 * and TLS name. No redirects are followed and the body is capped, so nothing
 * but the status and a small JSON answer come back.
 */
function fetchPinned(
  target: RuntimeTarget,
  address: string,
  path: string,
  readBody: boolean,
): Promise<Fetched> {
  const url = new URL(path, target.url);
  const client = url.protocol === 'https:' ? https : http;
  const family = isIP(address);
  return new Promise((resolve, reject) => {
    const request = client.request(
      {
        protocol: url.protocol,
        hostname: target.hostname,
        port: target.dockerProxy ? 8080 : url.port || undefined,
        path: url.pathname,
        method: 'GET',
        agent: false,
        timeout: TIMEOUT_MS,
        headers: {
          Host: url.host,
          Accept: readBody ? 'application/json' : 'text/html,*/*',
          'User-Agent': 'Vynic-CustomWebsite-Check/1',
          'Cache-Control': 'no-cache',
        },
        // Connect only to the address that was validated above.
        lookup: (_host, options, callback) => {
          if (options.all) callback(null, [{ address, family }]);
          else callback(null, address, family);
        },
      },
      (response) => {
        const chunks: Buffer[] = [];
        let size = 0;
        response.on('data', (chunk: Buffer) => {
          if (!readBody) return;
          size += chunk.length;
          if (size > MAX_BODY_BYTES) {
            response.destroy(new Error('Response exceeds 64 KB'));
            return;
          }
          chunks.push(chunk);
        });
        const done = () =>
          resolve({
            status: response.statusCode ?? 0,
            contentType: String(response.headers['content-type'] ?? ''),
            body: Buffer.concat(chunks).toString('utf8'),
          });
        response.on('end', done);
        response.on('close', () => {
          if (!response.complete) reject(new Error('Incomplete response'));
        });
        response.on('error', reject);
        if (!readBody) response.resume();
      },
    );
    request.on('timeout', () =>
      request.destroy(new Error('No answer within 5 seconds')),
    );
    request.on('error', reject);
    const deadline = setTimeout(
      () => request.destroy(new Error('No complete answer within 5 seconds')),
      TIMEOUT_MS,
    );
    request.on('close', () => clearTimeout(deadline));
    request.end();
  });
}

const object = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === 'object' && !Array.isArray(value);
const fingerprint = (value: unknown): value is string =>
  typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const digest = (text: string) =>
  createHash('sha256').update(text).digest('hex');
function parseJson(answer: Fetched): Record<string, unknown> | null {
  if (answer.status !== 200 || !answer.contentType.includes('json'))
    return null;
  try {
    const value: unknown = JSON.parse(answer.body);
    return object(value) ? value : null;
  } catch {
    return null;
  }
}

function failure(error: unknown) {
  const code = (error as { code?: string })?.code;
  if (code === 'ECONNREFUSED') return 'Connection refused';
  if (code === 'ENOTFOUND') return 'The domain does not resolve';
  if (code?.startsWith('ERR_TLS') || code?.includes('CERT'))
    return `TLS certificate problem (${code})`;
  return error instanceof Error && error.message
    ? error.message
    : 'Request failed';
}

/**
 * Checks one server-owned domain: does the frontend answer, and does the
 * shared backend (`/api/website/venue`) answer for the expected Venue through
 * that same domain.
 *
 * The caller passes only a hostname it read from an ACTIVE VenueDomain of the
 * Venue; there is no URL, port or path input.
 */
export async function checkCustomWebsite(
  target: RuntimeTarget,
  expected: {
    venueIdentity: string;
    siteKey: string | null;
    buildId: string | null;
  },
  resolve: Resolve = resolveAll,
): Promise<RuntimeCheck> {
  const checkedAt = new Date().toISOString();
  const base = {
    checkedAt,
    hostname: target.hostname,
    url: target.url,
    environment: target.local
      ? ('LOCAL_DEVELOPMENT' as const)
      : target.dockerProxy
        ? ('LOCAL_DOCKER' as const)
        : ('PUBLIC_HTTPS' as const),
  };
  const unchecked: RuntimeCheck['build'] = {
    state: 'NOT_CHECKED',
    status: null,
    detail: 'Not checked',
    observedBuildId: null,
    expectedBuildId: expected.buildId,
    siteKey: null,
  };
  const where = await destination(target, resolve);
  if ('refused' in where)
    return {
      ...base,
      availability: 'UNREACHABLE',
      frontend: { status: null, detail: where.refused },
      api: { state: 'NOT_CHECKED', status: null, detail: where.refused },
      build: { ...unchecked, detail: where.refused },
      rendererDeployed: false,
      bindingIdentityVerified: false,
    };

  let frontend: RuntimeCheck['frontend'];
  let html: string | null = null;
  try {
    const page = await fetchPinned(target, where.address, '/', true);
    const ok = page.status >= 200 && page.status < 300;
    html = ok && page.contentType.includes('text/html') ? page.body : null;
    frontend = {
      status: page.status,
      detail: ok
        ? 'Frontend answers'
        : page.status >= 300 && page.status < 400
          ? `Redirect refused (${page.status})`
          : `Frontend answered ${page.status}`,
    };
  } catch (error) {
    frontend = { status: null, detail: failure(error) };
  }

  let api: RuntimeCheck['api'];
  try {
    const answer = await fetchPinned(
      target,
      where.address,
      '/api/website/venue',
      true,
    );
    const json = parseJson(answer);
    if (!json || json.schemaVersion !== 1)
      api = {
        state: 'FAILED',
        status: answer.status,
        detail:
          answer.status === 200
            ? '/api is not a supported Vynic bootstrap'
            : `/api answered ${answer.status}`,
      };
    else if (!object(json.identity) || !fingerprint(json.identity.venue))
      api = {
        state: 'UNVERIFIED',
        status: 200,
        detail: 'Backend has no stable public Venue identity',
      };
    else if (
      json.identity.venue !== expected.venueIdentity ||
      json.mode !== 'CUSTOM' ||
      !object(json.site) ||
      json.site.key !== expected.siteKey ||
      !expected.siteKey
    )
      api = {
        state: 'WRONG_SITE',
        status: 200,
        detail: 'Backend Venue or CUSTOM binding identity differs',
      };
    else
      api = {
        state: 'OK',
        status: 200,
        detail: 'Stable Venue and CUSTOM binding match',
      };
  } catch (error) {
    api = { state: 'FAILED', status: null, detail: failure(error) };
  }

  let build: RuntimeCheck['build'];
  let rendererDeployed = false;
  try {
    const answer = await fetchPinned(
      target,
      where.address,
      '/vynic-site-manifest.json',
      true,
    );
    const manifest = parseJson(answer);
    const valid =
      manifest &&
      manifest.schemaVersion === 1 &&
      ['CUSTOM', 'SAAS'].includes(String(manifest.renderer)) &&
      fingerprint(manifest.buildId) &&
      fingerprint(manifest.htmlDigest) &&
      (manifest.renderer === 'CUSTOM'
        ? typeof manifest.siteKey === 'string' &&
          /^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/.test(manifest.siteKey)
        : manifest.siteKey === null);
    if (!valid || !manifest)
      build = {
        ...unchecked,
        state: 'FAILED',
        status: answer.status,
        detail: 'No valid build manifest; deployment is unverified',
      };
    else {
      rendererDeployed = html !== null && digest(html) === manifest.htmlDigest;
      const observed = {
        status: answer.status,
        observedBuildId: manifest.buildId as string,
        expectedBuildId: expected.buildId,
        siteKey: manifest.siteKey as string | null,
      };
      if (
        !rendererDeployed ||
        manifest.renderer !== 'CUSTOM' ||
        manifest.siteKey !== expected.siteKey ||
        !expected.siteKey
      )
        build = {
          ...observed,
          state: 'WRONG_BUILD',
          detail:
            'Served HTML or renderer/app key differs from the manifest/binding',
        };
      else if (!expected.buildId)
        build = {
          ...observed,
          state: 'UNRECORDED',
          detail:
            'Observed build; record the independently reviewed artifact fingerprint before verifying it',
        };
      else if (manifest.buildId !== expected.buildId)
        build = {
          ...observed,
          state: 'WRONG_BUILD',
          detail:
            'Observed build differs from the recorded artifact fingerprint',
        };
      else
        build = {
          ...observed,
          state: 'VERIFIED',
          detail: 'Served HTML and recorded CUSTOM build fingerprint match',
        };
    }
  } catch (error) {
    build = { ...unchecked, state: 'FAILED', detail: failure(error) };
  }
  return {
    ...base,
    availability:
      frontend.status !== null &&
      frontend.status >= 200 &&
      frontend.status < 300
        ? 'REACHABLE'
        : 'UNREACHABLE',
    frontend,
    api,
    build,
    rendererDeployed,
    bindingIdentityVerified: api.state === 'OK' && build.state === 'VERIFIED',
  };
}
