import { lookup as dnsLookup } from 'node:dns/promises';
import * as http from 'node:http';
import * as https from 'node:https';
import { BlockList, isIP } from 'node:net';

/**
 * Whether a CUSTOM site answers on its domain, observed on demand.
 *
 * Separate from the provisioning status an operator records: a site can be
 * attested ACTIVE and still be down. UNKNOWN means nobody has checked in this
 * view; nothing is stored or monitored.
 */
export type RuntimeAvailability = 'UNKNOWN' | 'REACHABLE' | 'UNREACHABLE';

/** Whether the shared backend answers for this Venue through the same domain. */
export type RuntimeApiState = 'OK' | 'WRONG_SITE' | 'FAILED' | 'NOT_CHECKED';

export interface RuntimeTarget {
  hostname: string;
  /** What an operator opens; never built from request input. */
  url: string;
  /** A local dev frontend: loopback only, port from server configuration. */
  local: boolean;
}

export interface RuntimeCheck {
  availability: Exclude<RuntimeAvailability, 'UNKNOWN'>;
  checkedAt: string;
  hostname: string;
  url: string;
  frontend: { status: number | null; detail: string };
  api: { state: RuntimeApiState; status: number | null; detail: string };
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
        port: url.port || undefined,
        path: url.pathname,
        method: 'GET',
        agent: false,
        timeout: TIMEOUT_MS,
        headers: {
          Accept: readBody ? 'application/json' : 'text/html,*/*',
          'User-Agent': 'Vynic-CustomWebsite-Check/1',
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
            response.destroy();
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
        response.on('close', done);
        response.on('error', reject);
        if (!readBody) response.resume();
      },
    );
    request.on('timeout', () =>
      request.destroy(new Error('No answer within 5 seconds')),
    );
    request.on('error', reject);
    request.end();
  });
}

function parseBootstrap(
  body: string,
): { mode?: unknown; profile?: { name?: unknown } } | null {
  try {
    const value: unknown = JSON.parse(body);
    return value && typeof value === 'object' ? value : null;
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
  expected: { venueName: string },
  resolve: Resolve = resolveAll,
): Promise<RuntimeCheck> {
  const checkedAt = new Date().toISOString();
  const base = { checkedAt, hostname: target.hostname, url: target.url };
  const where = await destination(target, resolve);
  if ('refused' in where)
    return {
      ...base,
      availability: 'UNREACHABLE',
      frontend: { status: null, detail: where.refused },
      api: { state: 'NOT_CHECKED', status: null, detail: where.refused },
    };

  let frontend: RuntimeCheck['frontend'];
  try {
    const page = await fetchPinned(target, where.address, '/', false);
    const ok = page.status >= 200 && page.status < 400;
    frontend = {
      status: page.status,
      detail: ok
        ? page.status >= 300
          ? `Answers with a redirect (${page.status})`
          : 'Frontend answers'
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
    const json =
      answer.status === 200 && answer.contentType.includes('json')
        ? parseBootstrap(answer.body)
        : null;
    api = !json
      ? {
          state: 'FAILED',
          status: answer.status,
          detail:
            answer.status === 200
              ? '/api is not proxied to the Vynic backend'
              : `/api answered ${answer.status}`,
        }
      : json.profile?.name === expected.venueName
        ? { state: 'OK', status: 200, detail: 'Backend answers for this Venue' }
        : {
            state: 'WRONG_SITE',
            status: 200,
            detail: 'Backend answered for a different restaurant',
          };
  } catch (error) {
    api = { state: 'FAILED', status: null, detail: failure(error) };
  }

  return {
    ...base,
    availability:
      frontend.status !== null && frontend.status < 400
        ? 'REACHABLE'
        : 'UNREACHABLE',
    frontend,
    api,
  };
}
