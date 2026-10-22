# SaaS Website Hostnames

Current contract for the public address of a generic (SAAS) restaurant website.
Commercial entitlement, WebsiteMode and provisioning are described in
`PLATFORM_COMMERCIAL_WEBSITE_UX.md`; this file covers only the hostname.

## Authority

```text
Host -> VenueDomain -> Venue -> WebsiteMode -> Website content
```

- The one authoritative SaaS binding is the `VenueDomain` row
  `<VenueWebsiteConfig.assignedSlug>.<SAAS_WEBSITE_BASE_DOMAIN>`
  (`vynic.localhost` locally, `vynic.ge` in production).
- `assignedSlug` is the server-owned identity (globally unique). The draft
  `slug`, published `slug` and the `VenueWebsiteConfig.slug` column are mirrors
  the server keeps equal to it; a draft save or publication that carries any
  other value is refused (403). Content never chooses or moves an address.
- Owners have no write path to `VenueDomain` or hostname requests. Address changes
  require contacting support. The compatibility request POST returns 403, and
  `hostnameChangeAllowed` is always false, including ACTIVE plans.
- Platform Admin can register Vynic subdomains and external domains for both
  SAAS and CUSTOM. Additional registered names are aliases; `assignedSlug`
  remains the one generated SAAS identity. Platform apex/api/admin/preview/www
  origins cannot be assigned to restaurant websites. Every hostname is globally
  unique, including disabled/retained bindings and assigned identities whose
  domain row is temporarily absent.
- The owner settings response carries `hostname` (the assigned SaaS address, or
  null outside SAAS) and `pendingHostnameRequest`; the dashboard displays these
  and never derives an address from the draft.

## Assignment

`assignHostname` (`apps/backend/src/website/provisioning/hostname.ts`) runs
from `provisionWebsite` whenever Platform provisions SAAS (access-request Trial
approval, manual TRIAL, GRANT_ACTIVE, prepared customers) and, once, for an
older SAAS row that has none.

- Name: lowercase, Georgian transliterated, accents stripped, **whitespace
  removed** (`Restaurant Vankisi` -> `restaurantvankisi`), other characters a
  hostname cannot carry dropped, at most 40 characters before a suffix.
- Reserved names (`www`, `api`, `admin`, `vynic`, `dashboard`, …) become
  `restaurant-<name>`; an empty result becomes `restaurant`.
- Collisions take a deterministic suffix, `-2`, `-3`, …, under a global advisory
  lock. A name is taken when any Venue's domain row (any status, including
  retention) or another Venue's `assignedSlug` holds it.
- Assigned once. Later restaurant display-name changes never rename it.
- Audited as `website.hostname_assigned` with `source` PLATFORM or SYSTEM.

## Platform Admin changes

Owners on Trial, ACTIVE or other plans see their current address read-only and
are directed to Vynic support. Saving/publishing content cannot rename it.

Platform Admin → Venue → Website → Domains:

- `POST /platform/venues/:id/domains {hostname}` registers a Vynic subdomain or
  external domain, for SAAS or CUSTOM. WEBSITE access is required; no paid-only
  restriction is applied to Admin changes.
- `PATCH /platform/venues/:id/domains/:domainId
  {hostname, expectedHostname, reason}` changes the displayed hostname. A stale
  expected hostname returns 409. A retry while the target hostname
  still belongs to the same domain adds no duplicate audit and returns its current
  state. A later different rename is protected by the expected-hostname check. Domain ID, creation time, status and
  retention deadline are preserved. Another Venue's domain ID returns 404.
- The Venue/configuration/global-name lock order protects concurrent registration,
  provisioning, rename and release. Domain and audit commit atomically. No domain
  can silently move to another restaurant.
- Renaming the assigned SAAS address requires a valid label under the configured
  base domain. Assigned/draft/published mirrors and revisions move atomically;
  unpublished edits remain unpublished, and stale editor submissions are refused.
  External domains can be registered separately as aliases. CUSTOM and alias
  renames accept external or Vynic hostnames.
- A direct assigned-address change closes previous pending requests with the
  Admin actor/time/reason. Historical requests remain readable and reviewable.

Registration/rename updates the Host → Venue binding. It does not change DNS,
TLS or a CUSTOM frontend route. Deploy/check those separately; the old renamed
hostname stops resolving and has no automatic redirect. Review payment return
origins when renaming; existing encrypted integrations and payment history are
not rewritten by this operation.

## Previous owner requests

New submissions are disabled. The retained GET endpoints expose historical
requests, with operator identities omitted from customer reads. The review path
below remains for requests saved before this policy change.

## Platform review

`POST /platform/venues/:id/hostname-requests/:requestId/review
{status: APPROVED|REJECTED, reason}` (SUPPORT_READONLY cannot mutate).

Approval takes the Venue row lock, the config row lock and the global hostname
lock, re-requires ACTIVE WEBSITE and SAAS, re-validates the name and re-checks
availability. If another Venue claimed it meanwhile, approval returns 409 and
nothing changes; the request stays PENDING for the operator to reject. On
success, in one transaction:

1. the new `VenueDomain` is created, inheriting the old binding's status;
2. the old SaaS `VenueDomain` is deleted (custom domains are untouched);
3. `assignedSlug`, draft/published slugs and revision move together; a site
   that was fully published stays fully published.

Rejection changes no binding. Both decisions are audited
(`website.hostname_change_approved` / `_rejected`) with actor, request,
requester, previous hostname, requested hostname, resulting active hostname
and reason. Requests are audited as `website.hostname_change_requested`.

## Old hostname

The old SaaS hostname stops resolving immediately on approval and becomes
available to other Venues. There is no redirect or alias: the domain model has
no redirect concept and adding one would create a second active SaaS binding.

## Losing access and release

When WEBSITE access is lost, every domain of the Venue enters the existing
30-day retention (`releaseAfter`). During retention the SaaS name stays
reserved: the domain row and `assignedSlug` both hold it, and regaining access
cancels retention with the address intact.

When retention expires, `CommercialLifecycleService` deletes the domain row
and, in the same transaction, `releaseSaasIdentity` clears the Venue's
`assignedSlug` and closes its pending hostname request (REJECTED, system
reason), audited as `website.hostname_released`. An operator Release of the
SaaS domain does the same. Nothing then reserves the name: the published
`slug` column is only a history mirror (its unique index was dropped), so
another Venue can be assigned or approved for it. Content and history remain;
if the Venue regains access it is assigned a fresh address and its draft and
published names follow it.

## Migration

`20261005120000_website_hostname_requests` copied existing `slug` into
`assignedSlug`; `20261006120000_hostname_request_current` adds the nullable
`currentHostname` column; `20261007120000_release_published_slug_reservation`
drops the unique index on the published `slug` mirror;
`20261008120000_hostname_request_fk_on_update` aligns the request's Venue foreign
key with the schema (ON UPDATE CASCADE). Existing hostnames (for example
`restaurant-vankisi.vynic.localhost`) are never regenerated; the whitespace
rule applies only to new assignments and approved changes.
