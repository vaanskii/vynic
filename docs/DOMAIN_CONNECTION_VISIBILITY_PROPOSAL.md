# Domain connection visibility — proposal, not implemented

## Existing behavior

Platform Admin currently manages domains per Venue in `VenueWebsiteTab.tsx`:
globally unique hostname binding, SAAS/CUSTOM mode, PENDING/ACTIVE/DISABLED and
publication. These are database facts, not verification of DNS or TLS. The
Organization page lists its Venues, but has no domain/certificate inventory.

CUSTOM additionally has an authenticated on-demand check in
`CustomWebsitePanel.tsx` and `custom-website-runtime.ts`: public frontend response,
same-domain backend identity, build manifest, observation time and availability.
The observation is not persisted or scheduled. Its HTTPS request checks ordinary
certificate validity but does not expose certificate expiry as a separate field.
The checker already validates all resolved IPs and pins its connection; it does
not follow redirects. SUPPORT_READONLY can view configuration, not run a check.
There is no dedicated check rate limit in that controller today.

## Minimal proposed addition

One Platform Admin **Domains** view, filterable by Organization, Venue,
SAAS/CUSTOM, connection state and expiring certificate. An Organization's
Domains tab uses the same inventory filtered to its Venues. Each row opens the
existing Venue domain settings. A separate **Platform domains** view contains
apex, www, admin, API and an approved preview origin; these must not become
tenant bindings merely to appear in this inventory.

| Independent fact | Proposed display/source |
| --- | --- |
| Ownership / binding | Organization, Venue, hostname, renderer, PENDING/ACTIVE/DISABLED from DB |
| DNS | Resolved public A/AAAA/CNAME chain, expected record, match/mismatch/unknown |
| Project routing | Expected provider/project; observed frontend/build and backend identity; verified/mismatch/unverified |
| TLS | Hostname + trusted-chain validation, issuer, not-before/not-after, days remaining, valid/invalid/unknown |
| Observation | Last checked time, checking/failed/stale state, concise failure reason |

Persist only a bounded latest observation and binding/configuration revision.
An observation for an old hostname or renderer becomes stale immediately.
Timeouts and absent evidence remain unknown/failed, never “connected”. A valid
certificate alone does not prove the correct Venue or Vercel project. A public
404 from a not-yet-published restaurant is distinct from TLS or DNS failure.
No check automatically activates a DB binding or changes DNS. Initial scope can
be an operator “Check now” action; background checks/notifications are a separate
decision, not implied by a timestamp.

Public DNS resolution and a normal TLS handshake need no Vercel/Render API key.
Public build/API evidence can validate served identity where implemented; it
cannot authoritatively expose provider-side project ownership, pending issuance
jobs or all internal configuration. Provider-authoritative status would need a
separately approved, least-privilege server integration and persistent provider
credentials. Existing developer CLI/browser access must not be copied into the
application. No credentials or integration are created by this proposal.

Issuance and renewal stay with Vercel/Render. The app displays public certificate
metadata only; it must never collect TLS private keys or become a certificate
authority. See [Vercel SSL](https://vercel.com/docs/domains/working-with-ssl) and
[Render TLS](https://render.com/docs/tls).

## Checker boundary

Accept only a stored domain ID (or an allowlisted platform-domain key), never an
arbitrary URL. Require PlatformUser authorization; keep read-only support view
permissions distinct from initiating network work. Add per-actor/per-domain
cooldowns, global concurrency limits, bounded retries and audit metadata.
Normalize the stored hostname, reject IP literals/ports/userinfo, cap DNS chain
depth and reject every private, loopback, link-local, reserved or mixed-public
answer. Re-resolve and revalidate each attempt; pin the validated public IP while
retaining the original hostname for SNI, certificate and Host checks to prevent
rebinding. HTTPS port 443 only, fixed probe paths, no redirects, strict TLS,
timeouts and response-size limits. No caller cookies, bearer credentials or
proxy secrets go to probed domains. Public results never expose tenant data or
raw response bodies. No production-localhost exceptions. Existing development
checker exceptions stay separate and cannot count as public verification.

## Owned preview origin — specific future approval

Proposed hostname: **`preview.vynic.ge`**, assigned to **`vynic-restaurant-web`**.
Do not add a VenueDomain row: preview authority remains a short-lived owner token.
The current read-only Vercel domain-config endpoint for this unbound hostname
reports `cname.vercel-dns.com.`. This is provisional: after approving/adding the
project binding, read its exact assigned CNAME and use that value in domenebi.ge
Premium DNS (`preview`, TTL 3600), without touching other records or nameservers.
Verify DNS and trusted HTTPS before changing Render runtime
`SAAS_WEBSITE_PREVIEW_ORIGIN` from `https://vynic-restaurant-web.vercel.app` to
**`https://preview.vynic.ge`**, then deploy Render and verify generated preview
links, bearer-only API auth, fragment clearing and stored-token reloads. No new
secret is needed; same-origin API proxying retains the existing server secret.

Only after new preview links work should the old Vercel preview entry be retired
or show a safe instruction to reopen preview from the owner dashboard. Do not
forward fragment tokens across origins or silently break previously issued links.
Current canonical redirects deliberately preserve the old authenticated preview
entry. Historical immutable deployments and provider protection remain unchanged.
Redirecting a URL is not making that hostname inaccessible.

Approval needed: (1) this owned-preview binding/DNS/nonsecret env rollout;
(2) the inventory, snapshot and protected public checker implementation.
Persistent provider API integration or changing deployment protection is a later,
separate approval if desired. No paid plan, credential creation, privileged
account, production tenant fixture or certificate/key upload is implied.
