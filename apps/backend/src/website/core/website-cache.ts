import { createHash } from 'node:crypto';
import type { Request, Response } from 'express';

/**
 * Caching for public generic-website responses.
 *
 * The policy is deliberately revalidate-always rather than a timed public
 * cache. Every request still reaches the backend, so removing an entitlement,
 * switching a Venue to CUSTOM or disabling a domain stops the site on the next
 * request; publishing a new revision is observable immediately, with no
 * deployment step and no cache to purge. What revalidation buys is the body:
 * an unchanged website answers 304 and sends nothing.
 *
 * `private` keeps shared proxies out of it. A host-keyed shared cache would
 * need publication *and* entitlement invalidation designed first — see
 * `docs/WEBSITE_PHASE_W3.md` — so it is not enabled here.
 */
export const PUBLIC_WEBSITE_CACHE_CONTROL = 'private, no-cache';
export const PRIVATE_WEBSITE_CACHE_CONTROL = 'private, no-store';

/** A strong validator over exactly the bytes that would be sent. */
export function websiteEtag(payload: unknown): string {
  return `"${createHash('sha256')
    .update(JSON.stringify(payload))
    .digest('base64url')
    .slice(0, 32)}"`;
}

function matches(header: string | undefined, etag: string) {
  if (!header) return false;
  return header
    .split(',')
    .map((value) => value.trim())
    .some((value) => value === etag || value === `W/${etag}` || value === '*');
}

/**
 * Send a public website payload, answering 304 when the client already has it.
 *
 * Never used for drafts: preview responses must not be stored or revalidated
 * against a public identity, so they go out with [PRIVATE_WEBSITE_CACHE_CONTROL].
 */
export function sendPublicWebsite(
  request: Request,
  response: Response,
  payload: unknown,
) {
  const etag = websiteEtag(payload);
  response.setHeader('Cache-Control', PUBLIC_WEBSITE_CACHE_CONTROL);
  response.setHeader('ETag', etag);
  response.setHeader('Vary', 'Accept-Encoding');
  if (matches(request.headers['if-none-match'], etag)) {
    response.status(304).end();
    return;
  }
  response.json(payload);
}

/** Send a draft/preview payload, which no cache may keep. */
export function sendPrivateWebsite(response: Response, payload: unknown) {
  response.setHeader('Cache-Control', PRIVATE_WEBSITE_CACHE_CONTROL);
  // A draft must never be indexed, even if it is fetched directly.
  response.setHeader('X-Robots-Tag', 'noindex, nofollow');
  response.json(payload);
}
