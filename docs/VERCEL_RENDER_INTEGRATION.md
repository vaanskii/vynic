# Vercel frontend transport to Render

The three frontends keep same-origin API URLs. Their Vercel routes forward only
the browser API families and website logo media to `https://api.vynic.ge`, keeping
the complete path and query. Platform forwards `/platform` and `/customer`, SaaS
forwards `/api/website`, and Vankisi CUSTOM forwards `/api`. Files are served
before the SPA fallback; missing API paths and assets never become HTML.

## Gateway authority

`VYNIC_WEB_PROXY_SECRET` is a new independent server-only secret, configured on
Render and the three Vercel projects. Never use a `VITE_` name, put its value in
Git, reuse an authentication key, or log request headers containing it. Vercel
route transforms delete any visitor-supplied `x-vynic-web-proxy-secret`, then set
the value from the server environment at request time. The upstream URL is fixed.

Render keeps `TRUST_PROXY_HOST` disabled. Before CORS/body parsing, the backend
verifies the gateway credential using a timing-safe comparison and requires a
single valid forwarded hostname, HTTPS, and a valid visitor IP. Only authenticated
browser proxy requests normalize Host and the per-peer admission IP. The gateway
credential and forwarded Host are removed before handlers run. Missing gateway
credentials cannot make a forwarded Host authoritative; wrong credentials or
malformed authenticated metadata fail with JSON errors. Native routes, direct
health checks and signed payment callbacks retain their existing boundaries.

This authenticates the proxy, not a user or Venue. Restaurant authority remains
Host -> active VenueDomain -> active Venue. Unknown domains fail closed. Existing
PlatformUser/CustomerAccount bearer authorization, website cookies and CSRF remain
in force. There is no client-selected Venue ID and no production default Venue.

The transport preserves method, body, query, Authorization, Cookie, Set-Cookie
and CSRF headers. API responses are not cached by Vercel. Static files and public
content-addressed website logo media retain their existing handling. Website
cookies remain host-only, Secure and SameSite=Strict; no wildcard CORS is needed.

## Rollout and verification

1. Configure the new secret in all four server environments without displaying
   its value. Existing secrets and database contents stay unchanged.
2. Publish the tested code to main, deploy the exact backend commit on Render,
   and confirm `/healthz`. Render auto-deploy stays off.
3. Deploy all three Vercel projects from that commit. Verify API JSON failures,
   direct SPA navigation, static assets and malicious forwarded-header inputs.
4. Check that the secret value is absent from generated frontend bundles and
   responses. Missing environment interpolation must fail closed at the backend.

Tests include real loopback HTTP with the authoritative tenant resolver over two
synthetic domain records, header tampering, visitor-IP admission, exact request
transport, real CSRF issuance/validation, secure cookie attributes and direct
native/callback compatibility. Existing opt-in PostgreSQL tenant/auth regressions
must use a fresh owned local fixture, never the Render database or business data.

A healthy proxy does not provision business data. An empty database still needs
separately authorized PlatformUser setup, Venue/domain assignments, entitlements,
publication and CUSTOM binding before full restaurant testing. No DNS/domain
binding change or account creation is part of this transport rollout.

References: [Vercel external origin protection](https://vercel.com/docs/routing/rewrites#restricting-your-origin-to-vercel-traffic),
[server environment references in route transforms](https://vercel.com/docs/project-configuration/vercel-json#using-environment-variables-in-routes).
