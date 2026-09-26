# Shared website foundation

SAAS and CUSTOM websites use **the same Venue-level backend**. `WebsiteMode`
only selects the renderer: `apps/restaurant-web` (one generic frontend) or a
bespoke build (`apps/vankisi-custom-web`, `apps/<client>-web`). It never
decides who owns data or which backend features exist.

```text
Commercial entitlement (Features: plan + override, Product tab)
  → Venue policy        (operator switch per capability, default on; Website tab)
  → configuration       (the data the capability needs: menu, hours, tables, BOG …)
  → frontend consumes   (GET /api/website/venue → capabilities.* are "live")
```

Companion documents: [CUSTOM_WEBSITES.md](CUSTOM_WEBSITES.md) (bespoke
frontends, operator provisioning), [PUBLIC_TENANCY.md](PUBLIC_TENANCY.md)
(Host authority, route table), [CLOUD_RESTAURANT_FOUNDATION.md](CLOUD_RESTAURANT_FOUNDATION.md)
(menu authority), [WEBSITE_PHASE_W3.md](WEBSITE_PHASE_W3.md) (generic renderer).

## Domain matrix

| Domain | Storage (after this change; before) | Authority | Shared canonical target | SAAS use | CUSTOM use | Platform control | Customer control |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Venue profile | `Venue` name/branch/address/phone/timezone/currency (unchanged) | Venue (owner edits, live) | Same | Bootstrap `profile` | `/api/website/venue` `profile` | Venue details | Restaurant profile |
| Menu / catalog | `MenuCategory/Subcategory/Item/Variant` (unchanged) | `Venue.menuAuthority`: CLOUD for Website without POS, POS when the package has POS | Same (one catalog) | `/api/website/menu` | `/api/website/venue/menu`, Vankisi `/api/menu` | Product → Dashboard menu editing; capability MENU | Menu → catalog editor when CLOUD |
| Menu presentation | `MenuItemWebsitePresentation` (unchanged) | Owner | Same | Applied to `/api/website/menu` | Applied to `/api/website/venue/menu` | — | Menu → presentation (images in either mode) |
| Opening hours | `VenuePublicProfile.workingHours` (was SAAS `draft/published.workingHours`) | Owner, live | Same | Projected into `content.workingHours` | `info.workingHours` | Capability HOURS | Hours (any mode, when HOURS available) |
| Gallery | `VenuePublicProfile.gallery` → `WebsiteMediaAsset` (was SAAS draft `gallery`) | Owner, live | Same | Projected into `content.gallery` | `info.gallery` | Capability GALLERY | Photos → gallery (any mode) |
| SAAS page media | Draft `logoUrl/heroImageUrl/aboutImageUrl` → `WebsiteMediaAsset` (unchanged) | Owner, draft → publish | Renderer-specific (stays) | Page | — | — | Photos (SAAS only) |
| Contact / socials / map | `VenuePublicProfile.contactEmail/mapUrl/socials` (was SAAS draft) | Owner, live | Same | Projected into `content` | `info` | — | Website → Contact (any mode) |
| Page text / design / SEO | `VenueWebsiteConfig.draft/published` (unchanged; now page-only) | Owner, draft → publish | Renderer-specific (stays) | Page | Bespoke frontend owns its own | Website mode | Website (SAAS only) |
| Reservations | `WebsiteTable`, `WebsiteReservation*` (unchanged) | Venue; POS bridge | Same | Not rendered by restaurant-web | `/api/tables*` | Capability RESERVATIONS; tables | — (bookings in Manager/POS) |
| Customer accounts | `WebsiteUser` (global), bookings Venue-scoped (unchanged) | Global account, per-site offering | Same | Not rendered | `/api/auth/*`, `/api/user/*` | Capability CUSTOMER_ACCOUNTS | — |
| Online payments | `PaymentIntegration` per Venue, encrypted (unchanged) | Owner configures; ONLINE_PAYMENTS entitlement | Same | Not rendered | `/api/bog/create-order` | Product ONLINE_PAYMENTS; capability ONLINE_PAYMENTS | Payments |
| Events | — (Vankisi shows static frontend content) | — | Not built | — | — | Listed, no switch | — |
| Banquets | — | — | Not built | — | — | Listed, no switch | — |
| Online ordering | — | — | Not built | — | — | Listed, no switch | — |
| Launch | SAAS `VenueWebsiteConfig.status=PUBLISHED`; CUSTOM once provisioned | Owner publishes / operator provisions | Renderer lifecycle | Publish | Operator | Website mode, CUSTOM binding | Publish (SAAS) |

## Capabilities

`website/tenancy/website-capabilities.ts` (pure rules),
`website-capabilities.service.ts` (facts, operator switch with audit
`venue.website_capability_changed`), `website-capability.guard.ts` (public
routes). Policy rows: `VenueWebsiteCapability` (no row = on). There is no
existing Feature/Policy able to say "included, but switched off for this
Venue's website" without turning a commercial override into operational policy
(see D006), so a small policy table was added.

| Capability | Commercial | Ready when | Public route gate |
| --- | --- | --- | --- |
| MENU | WEBSITE | ≥1 enabled menu item | `/api/menu`, `/api/website/venue/menu`, SAAS `/api/website/menu` (empty when off) |
| HOURS | WEBSITE | hours saved | Projected empty when off; owner edits refused |
| RESERVATIONS | WEBSITE | bookable website tables **and** online payments live (the booking flow takes a BOG deposit) | `/api/tables*`, `/api/bog/create-order` |
| GALLERY | WEBSITE | ≥1 photo | Projected empty when off; owner edits refused |
| CUSTOMER_ACCOUNTS | WEBSITE | always | `/api/auth/signup`, `/signin`, `/api/user/reservations` |
| ONLINE_PAYMENTS | WEBSITE + ONLINE_PAYMENTS | BOG integration configured and enabled | `/api/bog/create-order` |
| EVENTS, BANQUETS, ONLINE_ORDERING | never (not built) | — | — |

Route gate = commercial and enabled (403 if not in the package, 404 if the
operator switched it off); deeper checks (tables exist, BOG enabled) stay where
they were. `capabilities.*` in the public contract = commercial, enabled and
ready. Platform shows each capability's commercial state, the switch (disabled
when it could not be honoured; absent when not built), readiness with the
reason, and whether the current renderer shows it (SAAS: menu, hours, gallery;
CUSTOM: decided by the build).

Launch is the one renderer-specific gate: shared routes answer only once a SAAS
site is published or a Venue is CUSTOM, so an unpublished SAAS restaurant's
catalog, hours or bookings are not reachable early.

## Shared contracts

| Route | Both modes | Notes |
| --- | --- | --- |
| `GET /api/website/venue` | yes | `{schemaVersion 1, mode, site (CUSTOM binding or null), profile, info, capabilities}` |
| `GET /api/website/venue/menu` | yes | Canonical catalog with presentation |
| `/api/menu`, `/api/tables*`, `/api/bog/*`, `/api/auth/*`, `/api/user/*` | yes | Capability-gated as above |
| `GET /api/website/bootstrap`, `/api/website/menu` | SAAS renderer | Published page + projected Venue info; unchanged shape |
| `PUT /customer/venues/:id/website/public-info` | yes | Owner, `expectedRevision`, partial, live, audited `website.public_info_saved` |
| `GET|PUT /platform/venues/:id/website-capabilities[/:key]` | yes | Operator; SUPPORT_READONLY reads |

## Migration

`20261010120000_shared_website_foundation` creates `VenuePublicProfile` and
`VenueWebsiteCapability`, copies hours/contact/socials/gallery from each SAAS
page document (the latest saved draft wins; published-only sites keep their
published values) and strips those keys from `draft` and `published`. Those
values are live from then on: an edit saved but not yet published becomes
public at deploy. `referencedMedia` counts the Venue gallery, so moved photos
are never collected. No capability rows are created: every Venue keeps today's
behaviour.

## Dashboard

One draft state and one save bar, two writes: Venue public information goes to
`public-info` (live, both modes), page fields to the SAAS draft. Hours, gallery
and contacts are offered by capability, not mode; hero/about/logo images, page
text, design and publish stay SAAS-only. A capability the operator switched off
shows a short "switched off" notice instead of an editor.
