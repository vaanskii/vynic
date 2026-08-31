/**
 * Hostname handling for public website requests.
 *
 * The host is the only thing a public request offers that can identify a
 * restaurant, so it is normalized conservatively before it is used to look
 * anything up: anything that is not plainly a hostname is rejected rather than
 * repaired, and a rejected host resolves to no Venue at all.
 */

/** A hostname whose ownership is never taken from a request header. */
const MAX_HOSTNAME_LENGTH = 253;

const HOSTNAME_PATTERN =
  /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/;
const IPV6_BRACKET_PATTERN = /^\[([0-9a-f:.]+)\](:\d+)?$/;
const TRAILING_PORT_PATTERN = /:\d+$/;

/**
 * The comparable form of a host header value, or null when it is not a
 * hostname at all.
 *
 * Lowercased, port removed, trailing root dot removed. A value carrying a
 * scheme, path, query, fragment, userinfo or whitespace is refused outright —
 * those are signs the caller sent something other than a host, and guessing
 * what they meant is how a lookup ends up on the wrong restaurant.
 */
export function normalizeHostname(
  raw: string | null | undefined,
): string | null {
  const trimmed = (raw ?? '').trim();
  if (!trimmed || trimmed.length > MAX_HOSTNAME_LENGTH) return null;
  if (/[/\\?#@\s]/.test(trimmed)) return null;

  const lowered = trimmed.toLowerCase();

  const ipv6 = IPV6_BRACKET_PATTERN.exec(lowered);
  if (ipv6) return `[${ipv6[1]}]`;
  if (lowered.includes('[') || lowered.includes(']')) return null;

  const withoutPort = lowered.replace(TRAILING_PORT_PATTERN, '');
  if (withoutPort.includes(':')) return null;

  const withoutRootDot = withoutPort.endsWith('.')
    ? withoutPort.slice(0, -1)
    : withoutPort;
  if (!withoutRootDot || !HOSTNAME_PATTERN.test(withoutRootDot)) return null;

  return withoutRootDot;
}

/**
 * The hostnames a request offers, most trusted first.
 *
 * `X-Forwarded-Host` is read only when the deployment says a proxy is in front
 * of the process (`TRUST_PROXY_HOST`). Without that, any client could set the
 * header and pick its own restaurant, so it is ignored entirely rather than
 * accepted "just in case" — the direct `Host` header is what the process
 * actually received.
 *
 * Only the first entry of a forwarded chain is considered: it is the host the
 * client actually asked for. Walking further down the chain would let whoever
 * appended the later hops choose a restaurant.
 */
export function requestHostnames(
  headers: Record<string, string | string[] | undefined>,
  options: { trustForwardedHost: boolean },
): string[] {
  const candidates: string[] = [];

  if (options.trustForwardedHost) {
    candidates.push(...firstEntry(headers['x-forwarded-host']));
  }
  candidates.push(...firstEntry(headers['host']));

  const normalized: string[] = [];
  for (const candidate of candidates) {
    const hostname = normalizeHostname(candidate);
    if (hostname && !normalized.includes(hostname)) normalized.push(hostname);
  }
  return normalized;
}

/**
 * Whether a host is a local development address rather than a public name.
 *
 * Used only to decide whether the non-production development fallback applies.
 * It is never a reason to serve a Venue in production.
 */
export function isLocalDevelopmentHost(hostname: string): boolean {
  if (hostname === 'localhost' || hostname.endsWith('.localhost')) return true;
  if (hostname === '[::1]' || hostname === '[0:0:0:0:0:0:0:1]') return true;
  if (/^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  if (hostname === '0.0.0.0') return true;
  if (/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  if (/^192\.168\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  if (/^172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
  return false;
}

function firstEntry(value: string | string[] | undefined): string[] {
  if (!value) return [];
  const flat = Array.isArray(value) ? value[0] : value;
  const first = (flat ?? '').split(',')[0]?.trim();
  return first ? [first] : [];
}
