import { authoritativeRequestHost } from './website-host';

/**
 * Whether a browser request was sent by a page on the very host it addresses.
 *
 * Custom and SaaS restaurant sites call `/api` on their own origin through a
 * host-preserving proxy, because the request Host is what selects the Venue.
 * Such a request needs no cross-origin permission at all, but browsers still
 * attach `Origin` to its POSTs, and the CORS layer would otherwise refuse every
 * restaurant domain that is not listed in ALLOWED_ORIGINS. Listing each
 * customer's domain in deployment configuration does not scale and would drift
 * from `VenueDomain`.
 *
 * So an `Origin` whose host:port is exactly the request's authoritative host is
 * accepted as same-origin. A page cannot make a browser send another site's
 * Origin, and a genuinely cross-origin caller (a frontend on one host calling
 * the API on another) is still subject to the explicit allow-list — which is
 * right, because across origins the Host would name the API rather than the
 * restaurant, and the site's SameSite cookies would not travel either.
 */
export function isSameOriginRequest(
  origin: string,
  headers: Record<string, string | string[] | undefined>,
  options: { trustForwardedHost: boolean },
): boolean {
  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    return false;
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return false;
  if (parsed.origin !== origin.replace(/\/$/, '').toLowerCase()) return false;

  const forwarded = options.trustForwardedHost
    ? first(headers['x-forwarded-host'])
    : undefined;
  const raw = (forwarded ?? first(headers['host']) ?? '').trim().toLowerCase();
  // The same normalization the tenant lookup uses must accept it as a host.
  if (
    !raw ||
    !authoritativeRequestHost({ host: raw }, { trustForwardedHost: false })
  )
    return false;
  const defaultPort = parsed.protocol === 'https:' ? ':443' : ':80';
  const requestHost = raw.endsWith(defaultPort)
    ? raw.slice(0, -defaultPort.length)
    : raw;
  return parsed.host === requestHost;
}

function first(value: string | string[] | undefined): string | undefined {
  const flat = Array.isArray(value) ? value[0] : value;
  return flat?.split(',')[0]?.trim() || undefined;
}
