# Domain routing and restaurant onboarding

## Production host map

| Host | Destination | DNS |
| --- | --- | --- |
| `vynic.ge`, `www.vynic.ge` | `vynic-platform-web` | Existing records retained |
| `admin.vynic.ge` | `vynic-platform-web` | CNAME `1cbf110df1c0171b.vercel-dns-017.com` |
| `api.vynic.ge` | Render `vynic-api` | Existing `vynic-api.onrender.com` CNAME retained |
| `vankisi.vynic.ge` | `vynic-vankisi-custom-web` | CNAME `e3ac95a04e93ad0f.vercel-dns-017.com` |
| Future approved SaaS address | Shared `vynic-restaurant-web` | Obtain the exact record from that Vercel project |

The two new records use a one-hour TTL. Authoritative AWS nameservers remain
managed through the existing domenebi.ge Premium DNS dashboard. No wildcard,
registrar transfer, nameserver replacement, unrelated record deletion, plan
upgrade or persistent credential creation is part of this change.

## Visitor behavior

Restaurant document requests run a server-only admission check through the
existing authenticated Host/IP gateway. An absent/inactive domain returns a
branded HTML **404 at the same URL**, with a link to `https://vynic.ge`.
An entitled active SaaS host without published content returns a distinct
unpublished page with HTTP 404. Pending/disabled domains deliberately reveal
no restaurant identity. Network/timeouts/upstream failures return a retryable
503; authorization refusals retain 401/403, rate limits 429, incompatible
renderer bindings 421, and incompatible schemas 502. These are private/no-store,
noindex documents that work without JavaScript and never reflect caller data.

The shared `vynic-restaurant-web.vercel.app` address explains that visitors must
use the restaurant's own address (200, noindex). `/preview` and `/preview/*`
retain the existing fragment-token flow: only authenticated preview API requests
can read drafts. Similar prefixes such as `/preview-other` are ordinary pages.
A CUSTOM document requires the Host-resolved CUSTOM site key to match its build
and the binding to be ACTIVE. Missing production restaurant setup therefore
shows an unavailable restaurant page rather than the bespoke site's static shell.

Existing API/media middleware still forwards methods, bodies, query strings,
cookies and CSRF unchanged under its existing authenticated metadata boundary.
Static assets, manifest files and missing API paths do not become HTML fallback
pages. Public document probes forward only server-derived private Host/IP fields,
never caller cookies, authorization, conditionals or tenant/query selectors.
They time out after eight seconds. A valid public document then loads its SPA
and normal APIs; admission is not a replacement for API authorization.

## Operator workflow

1. Choose/create the actual approved restaurant and its commercial website access.
   PlatformUser setup and customer/restaurant identity need separate authorization.
2. Select SAAS or CUSTOM. SAAS uses one shared Vercel project for every restaurant.
   CUSTOM uses its client's project, even when its hostname is below `vynic.ge`.
3. Register the exact hostname in Platform Admin. New manually registered domains
   are **PENDING**, globally reserved to that Venue, and cannot resolve publicly.
   Existing domains and automatic SaaS provisioning/publication are unchanged.
4. Add the hostname to the correct Vercel project. Apply its exact recommended DNS
   record, retaining all unrelated DNS/email records. Verify DNS and valid HTTPS.
5. Activate the database binding in Admin, publish SaaS content or finish the
   CUSTOM binding (`vankisi-web` for Vankisi), and verify the public page.

The Admin screen explicitly separates renderer, address role, database binding
and publication. ACTIVE is not a live DNS/TLS verification result. Database saves
and activation do not provision Vercel, DNS, certificates or wildcard automation.
No production fixture or default restaurant may be used to bypass onboarding.

## Validation and rollout

- Backend build; fresh PostgreSQL migrations; domain HTTP tests (pending admission,
  uniqueness, concurrent edits, cross-Venue rejection, audit and lifecycle);
  website HTTP tests (unpublished code, two tenants, private drafts/preview);
  authenticated gateway HTTP/PostgreSQL, cookies/CSRF and host-resolution tests.
- SaaS typecheck, build, lint and component tests; focused Platform tests for
  domains, admin host, page admission, Vercel routing and hostile headers;
  all three emitted Node ESM proxies; all frontend production builds.
- Targeted changed Platform files pass lint. Whole Platform lint has 13 existing
  errors in unrelated dashboard/menu code and older test fixtures; those are deferred.
- Additive migration `20261023230000_pending_website_domains` adds one enum value.
  Historical migrations and existing rows/defaults are unchanged.
- Deploy the exact tested main SHA to Render (auto-deploy stays off) and all three
  Vercel projects. Check live HTTP status, static assets, preview rejection, TLS,
  forged headers and secure host-only CSRF cookies after deployment.

No environment variables are added or changed. Existing server-only
`VYNIC_WEB_PROXY_SECRET`, authentication/database credentials and
`SAAS_WEBSITE_PREVIEW_ORIGIN=https://vynic-restaurant-web.vercel.app` are retained.
The transport runbook remains `docs/VERCEL_RENDER_INTEGRATION.md`.
