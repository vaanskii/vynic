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
- Owners have no write path to `VenueDomain`. Operators register custom domains
  only: `POST /platform/venues/:id/domains` refuses any hostname inside the SaaS
  namespace, so a Venue never holds two SaaS addresses.
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

## Trial

Trial owners see `თქვენი ვებსაიტის მისამართი` with the assigned address
read-only and a note that it cannot change during the Trial. The server refuses
their hostname requests (403); no request form is rendered.

## Paid change requests

Only an ACTIVE Website owner of a SAAS Venue may request another address.

- `POST /customer/venues/:id/website/hostname-requests {slug}` validates the
  label (format + reserved names), refuses the Venue's current name and any
  taken name, and stores `WebsiteHostnameRequest` with the requester, current
  hostname, requested hostname and `PENDING` status. Nothing is bound.
- One pending request per Venue: service check under the Venue/config/name
  locks plus the partial unique index `WebsiteHostnameRequest_one_pending`.
  A second submission is 409; the dashboard shows the pending status instead of
  the form. After APPROVED or REJECTED a new request may follow.
- `GET …/website/address/:slug` is an advisory availability check only.
- Owners see their requests without the reviewing operator's identity.

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

## Migration

`20261005120000_website_hostname_requests` copied existing `slug` into
`assignedSlug`; `20261006120000_hostname_request_current` adds the nullable
`currentHostname` column. Existing hostnames (for example
`restaurant-vankisi.vynic.localhost`) are never regenerated; the whitespace
rule applies only to new assignments and approved changes.
