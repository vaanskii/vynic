import { timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';
import type { RequestHandler } from 'express';
import { normalizeHostname } from '../website/tenancy/website-host';

export const WEB_PROXY_SECRET_HEADER = 'x-vynic-web-proxy-secret';

/** Only browser transports are forwarded by the three frontend projects. */
export function isWebProxyPath(path: string): boolean {
  return (
    /^\/(?:api|customer|platform)(?:\/|$)/.test(path) ||
    /^\/media\/website-logos(?:\/|$)/.test(path)
  );
}

function one(value: string | string[] | undefined): string | undefined {
  return typeof value === 'string' && !value.includes(',')
    ? value.trim()
    : undefined;
}

function matchesSecret(
  value: string | string[] | undefined,
  expected: Buffer,
): boolean {
  if (typeof value !== 'string') return false;
  const actual = Buffer.from(value);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

/**
 * Convert authenticated gateway metadata into the normal request authority.
 *
 * Vercel replaces the secret header at its edge and supplies the visitor's
 * forwarded host/protocol/IP. Render must receive api.vynic.ge as its upstream
 * Host for routing. Only after the gateway secret is verified do we replace
 * that Host with the public site requested by the visitor. All existing tenant,
 * CORS and authentication admission code then sees the same authority.
 *
 * No secret/unknown gateway: ignore forwarded Host. A supplied wrong secret or
 * malformed authenticated metadata fails explicitly. Native transports and
 * direct health/payment callbacks keep their existing authorization boundary.
 */
export function webProxyIngress(secret: string | undefined): RequestHandler {
  if (!secret) return (_request, _response, next) => next();
  if (secret.length < 32)
    throw new Error('VYNIC_WEB_PROXY_SECRET is too short');
  const expected = Buffer.from(secret);

  return (request, response, next) => {
    const credential = request.headers[WEB_PROXY_SECRET_HEADER];
    delete request.headers[WEB_PROXY_SECRET_HEADER];
    const forwardedHost = request.headers['x-forwarded-host'];
    delete request.headers['x-forwarded-host'];

    if (!isWebProxyPath(request.path) || credential === undefined) {
      next();
      return;
    }
    if (!matchesSecret(credential, expected)) {
      response
        .status(403)
        .json({ statusCode: 403, message: 'Invalid web proxy credentials' });
      return;
    }
    const rawHost = one(forwardedHost);
    const hostname = normalizeHostname(rawHost);
    const protocol = one(request.headers['x-forwarded-proto']);
    const clientIp = one(request.headers['x-real-ip']);
    if (!hostname || protocol !== 'https' || !clientIp || !isIP(clientIp)) {
      const invalidFields = [
        ...(!hostname ? ['host'] : []),
        ...(protocol !== 'https' ? ['protocol'] : []),
        ...(!clientIp || !isIP(clientIp) ? ['clientIp'] : []),
      ];
      response
        .status(400)
        .json({
          statusCode: 400,
          message: 'Invalid web proxy metadata',
          invalidFields,
        });
      return;
    }

    request.headers.host = hostname;
    // Existing per-peer admission uses req.ip. Never trust a caller's arbitrary
    // X-Forwarded-For chain, and never turn on global Express proxy trust here.
    Object.defineProperty(request, 'ip', {
      configurable: true,
      value: clientIp,
    });
    Object.defineProperty(request, 'ips', {
      configurable: true,
      value: [clientIp],
    });
    next();
  };
}
