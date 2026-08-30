/**
 * SSRF guard for the POS callback URL.
 *
 * The POS registers its own address (`posCallbackUrl`) in the sync payload and
 * the server later `fetch()`es it. A real POS is always on the local network,
 * so we only allow http(s) URLs whose host is a private/loopback IPv4 literal
 * (or `localhost`). Everything else — public IPs, `169.254.x` cloud-metadata,
 * and arbitrary hostnames (DNS-rebinding risk) — is rejected. This caps the
 * blast radius even if POS_SYNC_API_KEY leaks.
 */
export function isAllowedPosCallbackUrl(rawUrl: string): boolean {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    return false;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return false;

  const host = url.hostname.toLowerCase();
  if (host === 'localhost' || host === '::1') return true;

  // Require an IPv4 literal in a private/loopback range.
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!m) return false;
  const [a, b, c, d] = m.slice(1).map(Number);
  if ([a, b, c, d].some((n) => n > 255)) return false;

  if (a === 127) return true; // 127.0.0.0/8 loopback
  if (a === 10) return true; // 10.0.0.0/8
  if (a === 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
  if (a === 192 && b === 168) return true; // 192.168.0.0/16
  return false; // public, 169.254.x (link-local/metadata), 0.x, etc.
}
