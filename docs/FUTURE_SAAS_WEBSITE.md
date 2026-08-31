# Future phase: generic SaaS restaurant website

**Status: not built. Recorded so it is not confused with the existing custom
site.**

Step 4B2B built the backend half it will need and nothing more: a registered
hostname resolves a Venue, and the public APIs are scoped to that Venue. The
generic frontend still does not exist, and the boundary it will use is the same
one the custom site already uses — see [PUBLIC_TENANCY.md](PUBLIC_TENANCY.md).

## The requirement

Vynic will later have a *second*, separate website product: one codebase that
serves many restaurants from Venue configuration, rather than a bespoke build
per customer.

```text
one SaaS website codebase
        ↓
Venue configuration
        ↓
branding · menu · tables · booking · features · domain
```

It must not require a custom frontend build for every restaurant. Onboarding a
new Venue onto it should be configuration, not a release.

Later requirements, when that phase starts:

- one codebase, many Venues;
- Host/domain → Venue resolution;
- Venue branding and presentation configuration;
- Venue-specific menu;
- Venue-specific tables;
- feature-aware booking (booking behaviour follows the Venue's entitlements).

## Relationship to the existing custom site

`apps/venue-web/` is **not** this. It is the custom website built for Vankisi,
and it stays a custom website: its branding, layout, SVG floor plans, Three.js
behaviour, booking UX, and restaurant-specific presentation are the product,
not scaffolding to be generalised away.

The generic SaaS website must be a separate application from the Vankisi custom
implementation unless a later explicit architecture decision says otherwise.
Its folder name is not decided here.

The two are already distinguishable in data without either being built:

| | Custom | SaaS |
| --- | --- | --- |
| `WEBSITE` feature | enabled | enabled |
| `WebsiteMode` | `CUSTOM` | `SAAS` |
| Serving code | restaurant-specific build | one shared application |

Both are configurations of the same commercial `WEBSITE` feature, not two
products to be sold separately. See
[PRODUCT_ENTITLEMENTS.md](PRODUCT_ENTITLEMENTS.md).

The runtime and deployment model for the `CUSTOM` side is an open decision —
see [CUSTOM_WEBSITE_RUNTIME.md](CUSTOM_WEBSITE_RUNTIME.md). Both sides share
one invariant: each must resolve an authoritative Venue before touching
Venue-owned Cloud data.
