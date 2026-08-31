# ADR: custom restaurant website runtime and deployment

**Status: open. Nothing here is decided, and Step 5A implemented none of it.**

This document exists so that the *distinction* between a custom and a SaaS
website survives until the runtime question is answered properly, rather than
being settled by accident the first time someone wires a domain up.

## Context

`apps/venue-web/` is the custom restaurant website built specifically for
Vankisi. It is a single compiled site with its own branding, layout, SVG floor
plans, Three.js behaviour, booking UX, and restaurant-specific presentation.
It is a real, live product and stays that way.

Separately, Vynic will later build a *generic* SaaS restaurant website: one
codebase serving many Venues from configuration. See
[FUTURE_SAAS_WEBSITE.md](FUTURE_SAAS_WEBSITE.md).

Step 5A modelled the product distinction only:

```text
WEBSITE feature   → is this Venue entitled to a restaurant website?
WebsiteMode       → NONE | SAAS | CUSTOM
```

Vankisi's Venue is recorded as `WEBSITE` entitled, mode `CUSTOM`. That is a
statement about what the customer bought and which kind of site serves them.
It is **not** a statement about how that site is built, hosted, deployed, or
routed to.

## The decision that is deferred

How a custom restaurant website is operated. Concretely, a future ADR must
answer at least:

- **Deployment ownership** — does each custom website get its own deployment,
  or are they served from shared infrastructure?
- **Build registration** — how does a specific custom build become known to
  Vynic as *the* site for a Venue?
- **Venue binding** — what ties a running custom website to a Venue ID, and
  what stops it claiming a different one?
- **Domain binding** — how are customer domains connected, verified, and
  renewed?
- **API authentication** — how does a custom website authenticate to Cloud, and
  with what credential lifecycle? (Notably *not* a POS Device credential.)
- **Deployment lifecycle** — build, promote, roll back, retire.
- **Environment and configuration** — where per-site config and secrets live,
  and who may change them.
- **Versioning and independent releases** — can one restaurant's site ship
  without releasing anything else?
- **Repository strategy** — do custom websites live in this monorepo or in
  separate repositories, and what does that cost in shared-contract drift?
- **Observability** — uptime, errors, and booking failures per custom site.
- **Deactivation** — what happens to a live custom site when the Venue's
  `WEBSITE` entitlement is withdrawn, or the Venue is disabled.

## The invariant that is decided

One property holds regardless of which runtime model wins:

> A custom website and a SaaS website must **both** ultimately resolve an
> authoritative Venue before accessing Venue-owned Cloud data.

Neither may read or write another Venue's menu, tables, reservations, or
orders. A SaaS site will most likely resolve its Venue from the request Host;
a custom site may resolve it from a build-time or credential-bound identity.
The mechanisms may differ; the requirement that the resolution be authoritative
and server-side does not.

That resolution is **not implemented**. `apps/venue-web/` today talks to a
single-restaurant backend, and the backend still pins website and Manager reads
to the bootstrap Venue (see [TENANT_SCOPING.md](TENANT_SCOPING.md)). Host and
domain → Venue resolution is later work.

## What was deliberately not done

To be explicit, because silently choosing one of these is exactly the failure
this ADR guards against:

- No domain routing, Host header parsing, or per-site request resolution.
- No deployment, hosting, or build-registration mechanism.
- No website credential, API key, or authentication path for a custom site.
- No change to `apps/venue-web/` — not its branding, layout, floor plans,
  Three.js behaviour, booking UX, or configuration. It does not read the new
  entitlement tables and behaves exactly as before.
- No repurposing of `apps/venue-web/` into the generic SaaS website.
- No monorepo-versus-separate-repository decision.
- No deployment or health status modelled anywhere. "Entitled to a custom
  website" says nothing about whether one is deployed or healthy, and Step 5A's
  schema deliberately cannot express that it is.
