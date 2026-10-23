# Vercel frontend transport to Render

The three frontends keep same-origin API URLs. Their server-only `proxy.ts`
entrypoints forward browser APIs and website logo media to the fixed origin
`https://api.vynic.ge`, keeping the full path/query and original method/body.
`vercel.json` limits middleware invocation to Platform `/platform` + `/customer`,
SaaS `/api/website`, CUSTOM `/api`, and shared `/media/website-logos`. Other files
use normal static handling and SPA fallback; API/static failures never become HTML.

## Gateway authority

`VYNIC_WEB_PROXY_SECRET` is one independent server-only secret, stored in Render
and the Production environment of each Vercel project. Never use a `VITE_` name,
put its value in Git, reuse an authentication key, or log credentials. Vercel's
Node routing middleware reads the secret at runtime. Static route rules never
attach credentials, so bypassing middleware cannot authenticate caller metadata.

`packages/website-client/server/vercel-gateway.ts` constructs authority from the
actual Request URL and Vercel's `x-vercel-forwarded-for` system header. A Host/URL
discrepancy, non-HTTPS request, invalid system IP or missing secret fails closed.
Caller-supplied private/generic proxy headers and middleware control headers are
removed. Only server-derived `x-vynic-web-proxy-host`, `-proto`, `-ip` and `-secret`
are sent upstream. Do not replace this with generic X-Forwarded headers: combined
caller headers were observed surviving external static rewrites on live Vercel,
and Render does not preserve a valid X-Real-IP through this deployment.

Render keeps `TRUST_PROXY_HOST` disabled. Before CORS/body parsing, the backend
checks the credential using a timing-safe comparison and validates the private
hostname, HTTPS marker and visitor IP. It then normalizes Host and per-peer
admission IP. Generic forwarded headers never supply gateway authority, even
with a credential. Private credentials/metadata are removed before handlers run.
Wrong credentials or malformed metadata fail explicitly with JSON; diagnostics
identify only field names, never values. Native transports, direct health checks
and signed payment callbacks retain their existing authorization boundaries.

This authenticates a gateway, not a user or Venue. Restaurant authority remains
Host -> active VenueDomain -> active Venue. Unknown domains fail closed. Existing
PlatformUser/CustomerAccount authorization, website cookies and CSRF remain in
force. There is no client-selected Venue ID or production default Venue.

Rewrites preserve method, body, query, Authorization, Cookie, Set-Cookie and CSRF
headers. The body is not read or reserialized by middleware. APIs use private,
no-store caching; content-addressed public website logos retain original caching.
Cookies stay host-only, Secure and SameSite=Strict; CORS uses no wildcard.

## Configuration changes for this integration

| Destination | Environment | Added name | Kind | Purpose/value |
| --- | --- | --- | --- | --- |
| Render vynic-api | Service runtime | VYNIC_WEB_PROXY_SECRET | Secret | Authenticate server-derived metadata; value never documented |
| Render vynic-api | Service runtime | SAAS_WEBSITE_PREVIEW_ORIGIN | Nonsecret | https://vynic-restaurant-web.vercel.app |
| Vercel vynic-platform-web | Production only | VYNIC_WEB_PROXY_SECRET | Sensitive secret | Same gateway credential |
| Vercel vynic-restaurant-web | Production only | VYNIC_WEB_PROXY_SECRET | Sensitive secret | Same gateway credential |
| Vercel vynic-vankisi-custom-web | Production only | VYNIC_WEB_PROXY_SECRET | Sensitive secret | Same gateway credential |

Existing authentication/database keys, DNS/domain bindings, CORS origins and
Render automatic deployment settings are not changed by this integration.
Manage keys in Render's service Environment page and each Vercel project's
Settings -> Environment Variables. A future rotation must update all four
server environments and deploy the matching backend/frontends together.

## Verification and rollout

Tests cover server-derived authority under combined hostile headers, missing
configuration, fixed upstream/path/query, unconsumed bodies, real rewrite helpers,
backend loopback HTTP, PostgreSQL tenant separation, secure cookie/CSRF handling
and native/callback compatibility. Database tests require fresh owned loopback
fixtures, never business data or the Render database.

Deploy the exact tested main commit to all three Vercel projects and Render;
Render automatic deployment remains off. Verify live health, JSON API errors,
SPA refresh, real assets, CSRF freshness, no-store caching and forged metadata.
Check actual secret absence in committed content and deployed client bundles
and responses, including internal middleware request headers being consumed.

A working transport does not create business data. Empty deployments still need
separately approved PlatformUser setup, Venue/domain assignments, entitlements,
publication and CUSTOM binding before full restaurant testing.

References: [Vercel routing middleware](https://vercel.com/docs/routing-middleware/js-reference),
[Vercel system request headers](https://vercel.com/docs/headers/request-headers).
