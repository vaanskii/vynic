import { isIP } from 'node:net';
import type { RequestHandler } from 'express';
import { normalizeHostname } from '../website/tenancy/website-host';
import {
  proxyCredentialVerifier,
  validateProxyRotation,
  type ProxyRotation,
} from './web-proxy-rotation';

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

/**
 * Convert authenticated gateway metadata into the normal request authority.
 *
 * Vercel's server middleware replaces private metadata with the actual request
 * URL and its system-provided visitor IP. Render receives api.vynic.ge as Host
 * for routing. Only after the gateway secret is verified do we replace
 * that Host with the public site requested by the visitor. All existing tenant,
 * CORS and authentication admission code then sees the same authority.
 *
 * No secret/unknown gateway: ignore forwarded Host. A supplied wrong secret or
 * malformed authenticated metadata fails explicitly. Native transports and
 * direct health/payment callbacks keep their existing authorization boundary.
 */
export function webProxyIngress(
  secret: string | undefined,
  rotation: ProxyRotation = {},
): RequestHandler {
  validateProxyRotation(secret, rotation);
  if (!secret) return (_request, _response, next) => next();
  if (secret.length < 32)
    throw new Error('VYNIC_WEB_PROXY_SECRET is too short');
  const acceptsCredential = proxyCredentialVerifier(secret, rotation);

  return (request, response, next) => {
    const credential = request.headers[WEB_PROXY_SECRET_HEADER];
    delete request.headers[WEB_PROXY_SECRET_HEADER];
    const forwardedHost = request.headers['x-vynic-web-proxy-host'];
    const forwardedProtocol = request.headers['x-vynic-web-proxy-proto'];
    const forwardedIp = request.headers['x-vynic-web-proxy-ip'];
    delete request.headers['x-vynic-web-proxy-host'];
    delete request.headers['x-vynic-web-proxy-proto'];
    delete request.headers['x-vynic-web-proxy-ip'];
    delete request.headers['x-forwarded-host'];

    if (!isWebProxyPath(request.path) || credential === undefined) {
      next();
      return;
    }
    if (!acceptsCredential(credential)) {
      response
        .status(403)
        .json({ statusCode: 403, message: 'Invalid web proxy credentials' });
      return;
    }
    const rawHost = one(forwardedHost);
    const hostname = normalizeHostname(rawHost);
    const protocol = one(forwardedProtocol);
    const clientIp = one(forwardedIp);
    if (!hostname || protocol !== 'https' || !clientIp || !isIP(clientIp)) {
      const invalidFields = [
        ...(!hostname ? ['host'] : []),
        ...(protocol !== 'https' ? ['protocol'] : []),
        ...(!clientIp || !isIP(clientIp) ? ['clientIp'] : []),
      ];
      response.status(400).json({
        statusCode: 400,
        message: 'Invalid web proxy metadata',
        invalidFields,
      });
      return;
    }

    request.headers.host = hostname;
    // Generic forwarded headers never supply authority, even with a credential.
    // Only server-derived private metadata affects per-peer admission here.
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
