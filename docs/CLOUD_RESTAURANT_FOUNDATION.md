# Cloud Restaurant Foundation

Website is independently sellable. New shells have NO_PLAN, POS menu authority,
and cloudMenuEditingEnabled=false. Explicit operator Website trial/plan assignment
plus SAAS setup can enable Cloud menu editing through the existing admission
checks. WEBSITE and allowed commercial state are required for owner catalog
reads/writes. POS-authoritative Venues remain protected; assigning a package never
silently hands operational authority to Cloud. Existing stored authority/editing
flags are preserved by migration. Adding POS uses the same Venue and never changes
menu authority. See `COMMERCIAL_ACCESS_HARDENING.md` for access policy.

## Domain authority matrix

Evidence: Prisma Venue/Menu*/VenueWebsiteConfig/PaymentIntegration, Flutter
menu_item_db.dart, table.dart, table_layout.dart, SettingsRepository,
PosVenueProfile, PosEnrollmentService and DatabaseCore. “Post adoption” below
means after enrollment; production handover remains disabled.

| Domain | Existing authority | Website-only authority/classification | Post adoption / bootstrap | Decision |
|---|---|---|---|---|
| Venue UUID, Organization ownership | Cloud | CLOUD_CANONICAL | Same UUID, Device-bound profile | A/B; never create a replacement Venue |
| Restaurant/branch name, address, phone, legal ID | Cloud Venue; authorized Owner/Manager/Device writes | CLOUD_CANONICAL | Profile in snapshot; existing profile cache unchanged | A/B; revisioned profile handover needed before activation |
| Currency/timezone | Cloud Venue | CLOUD_CANONICAL | Included in profile snapshot | B; creation defaults GEL/Asia-Tbilisi; no new currency conversion workflow |
| Logo, branding, main photo/gallery | Website draft/publication; separate POS receipt bytes | CLOUD_CANONICAL | Website URLs in staged snapshot | A/B; receipt raster conversion/download remains future activation work |
| Opening hours, public contact/social information | Website config | CLOUD_CANONICAL | Website draft preserved in staging | A/B; not a service-hours enforcement policy |
| Categories/subcategories, order | POS mirror, stable POS identity columns | CLOUD_BOOTSTRAP_TO_POS, Cloud author | Same canonical rows/UUIDs, explicit numeric order | A/B; menu handover required |
| Menu items, price, hierarchy | POS mirror | CLOUD_BOOTSTRAP_TO_POS, Cloud author | Canonical IDs equal POS identity columns for newly Cloud-created nodes | A/B; menu handover required |
| Variants/sizes/prices | POS MenuVariantDB numeric size (litres), not arbitrary labels | CLOUD_BOOTSTRAP_TO_POS | Same variant IDs and numeric values | A/B; no new variant-label model |
| Item enabled state | Existing POS has no persisted enabled field | Cloud catalog enabled, default true for old rows | Retained in staging; public menu excludes disabled items | A/B; POS availability projection required before activation |
| Website visibility, display-name override, description, item photo, public order | Separate MenuItemWebsitePresentation | CLOUD_CANONICAL | Does not mutate catalog, inventory or kitchen semantics | A; independent of menu authority |
| Floor/zone identity | POS RestaurantZone in activeTableLayoutJson | POS_CANONICAL; not authored in this phase | Not bootstrapped | C/D; stable zone identity needs dedicated foundation contract |
| Physical tables, UUIDs | POS TableModel/table layout definitions | POS_CANONICAL | Not bootstrapped | C/D; never merge by label or number |
| Table geometry/positions/decorative layout objects | POS RestaurantTableLayout | POS_CANONICAL | Not bootstrapped | C/D; editor and runtime projection remain local |
| Service fee percent/default, close/receipt display policies | SettingsRepository | POS_CANONICAL | Not bootstrapped | C/D; policy needs complete offline cache and writer fencing |
| Bank terminal selection, cash/card/split tenders | Local payment service and settings | POS_CANONICAL | Not bootstrapped | C; transaction/tender state never copied |
| Receipt identity/header layout/logo bytes | Local settings plus Cloud profile cache | POS_CANONICAL presentation; Cloud identity | Profile/URL staged only; live receipts unchanged | B/C; raster and receipt-layout activation deferred |
| Printer endpoints | Device runtime config/local cache | POS_CANONICAL device resources | Not restaurant foundation; existing pull unchanged | C; no Cloud-to-LAN calls |
| Kitchen routing | POS category/item sendToKitchen | POS_CANONICAL, Cloud-created rows use existing default | Preserved in snapshot, not exposed in owner editor | C; routing must be reviewed before production activation |
| Packages, staff/PIN access, inventory recipes/suppliers/stock | Existing local/Cloud domain authorities | NOT_IN_SCOPE | No new bootstrap of these domains | C/D; no copied credentials or inventory state |
| POS language, input/display preferences | Local settings | POS_CANONICAL | Not bootstrapped | C; terminal preferences are not Venue branding |
| Open Orders, occupancy, reservations in execution, payments/attempts | POS/Edge | POS_OPERATIONAL_ONLY | Never imported, overwritten or Cloud-authored | C |
| Sales/recovery, closure/cancel/restore journals, Close Day | POS; immutable Cloud mirrors where established | POS_OPERATIONAL_ONLY | Never imported | C |
| Printer queue, Edge command/update journals, outboxes, temporary operational drafts, transient UI | POS/Edge | POS_OPERATIONAL_ONLY | Never imported | C |

A = owner manages now; B = stored for future bootstrap; C = existing sole author;
D = future Backoffice work. No bulk copying of the mixed settings box is allowed.

## Catalog contract and fencing

`GET /customer/venues/:venueId/catalog` and `PUT .../catalog/:kind` resolve
CustomerAccount -> OWNER membership -> Organization -> Venue first. Parent and
existing node identities are checked within the Venue. Kinds are category,
subcategory, item and variant. Each mutation supplies expectedRevision, increments
catalogRevision and writes CustomerAuditEvent in one transaction under the Venue
row lock. Stale revisions conflict. No destructive catalog deletion endpoint is
introduced; products can be disabled. Variant sizes retain the current numeric
litre model and existing size ordering.

POS menu snapshots acquire the same Venue lock and reject CLOUD authority,
including legacy snapshots. POS authority rejects owner catalog writes. Website
presentation stays independently editable. Existing CUSTOM Vankisi code and BOG
semantics are untouched. Public reads retain Host -> VenueDomain -> Venue and
ignore client tenant IDs. Prices/menu availability remain live catalog reads, as
in W2; website text uses the existing draft/publication workflow.

## Bootstrap v1 and exact retry

`POST /edge/restaurant-foundation/bootstrap` accepts Device credentials only,
resolves Device -> Venue, and requires POS entitlement. It accepts no tenant
selector. A CLOUD Venue and Device without firstSyncAt may obtain a snapshot.
The Venue lock serializes snapshot creation with catalog/profile writes. One
JSON snapshot is persisted in Device.foundationBootstrap before returning it.
Subsequent requests return that same snapshot, even if the catalog changes.

The snapshot contains version=1, venueId, deviceId, catalogRevision, profile,
website draft URLs/content, categories/subcategories/items/variants (including
stable IDs, prices, enabled and order), authority=CLOUD,
operationalActivationAllowed=false, and a SHA-256 snapshotId over the original
normalized payload. The hash identifies content; Device authentication provides
transport authority. No operational rows or secrets are included.

Flutter RestaurantFoundationImport stages the complete snapshot in a dedicated
Hive String box, bound to the enrolled Venue and Device. A single durable value
contains both data and completion identity. Exact retry is a no-op; a different
snapshot conflicts. Initial staging requires supplied operational boxes to be
open and empty, and refuses a missing empty-state check. Existing operational
boxes are never written. Reopening the staging box needs no Cloud connection.
The API/Hive proof transfers the actual server-produced JSON without replacing
IDs or rebuilding the hierarchy from display names.

This is **staging, not activation**: the importer is deliberately not connected
to ordinary enrollment/startup and does not write the live MenuCategoryDB box.
No production POS adoption/authority handover is claimed. This conservative
boundary avoids allowing local POS editors to diverge from a Cloud-authored menu.

## Required future activation/transition contract

1. Freeze Cloud catalog writes at a specific revision under the Venue lock.
2. Prove one selected operational Device, bound snapshot/version and a complete
   local freshness inventory (Orders, Tables, Sales, reservations, drafts, all
   recovery journals/outboxes); never trust a client “empty” flag alone.
3. Implement all catalog/availability/profile/media projections with the same
   UUIDs, crash-safe staging/activation and exact-retry journals. Cache receipt
   logo bytes for offline use; no network dependency on operational paths.
4. Fence every POS menu writer (repository, Admin UI, backup restore, seed/import,
   Manager/Edge paths) until the chosen authority epoch is durably accepted.
5. Atomically move server authority CLOUD -> POS using expected revision,
   snapshotId and Device identity. Cloud writes must remain blocked afterward.
6. Activate the matching local projection and prove crashes/ACK loss/restarts;
   repeat requests converge. A conflict requires explicit operator handling.
   No automatic failover, reseed, enrollment-triggered switch or dual-write mode.

There is no transition endpoint in this milestone. Ordinary existing POS startup,
Hive migration and offline restaurant operation are unchanged.

## Local proof and reproduction

Use only `postgresql://vaanskii@127.0.0.1:55439/vynic_foundation_phase3_disposable`.
Never point these commands at live restaurant data. The foundation harness rejects
any other host/port/database before importing application code.

- Apply Prisma migrations with DATABASE_URL explicitly set to that disposable DB.
- Run `FOUNDATION_TEST_DATABASE_URL=... npx jest restaurant-foundation.integration --runInBand`
  from apps/backend. It seeds Website-only plan `website-only-local`, creates two
  disposable owners, verifies no Device/Manager requirement, authors catalog,
  uploads/serves a logo, edits presentation, previews/publishes, checks Hosts and
  tenant/authority fences, adds POS entitlement, enrolls and checks frozen retry.
- The proof exports `/private/tmp/vynic-foundation-bootstrap.json`.
- Run `FOUNDATION_BOOTSTRAP_FIXTURE=/private/tmp/vynic-foundation-bootstrap.json flutter test test/unit/restaurant_foundation_import_test.dart`
  from apps/operations. Hive uses a new temporary directory for each test.
- `FOUNDATION_TEST_DATABASE_URL=... npx ts-node -T scripts/serve-foundation-local.ts --confirm-local`
  starts the isolated harness on 3000; FOUNDATION_PORT can select a safe free port.
- Dashboard 5173 and restaurant-web 5175 keep `vynic.localhost` Host tenancy.
  During this implementation 3000 was already occupied, so browser API/media
  traffic was explicitly routed to the disposable harness on 3103. No request
  was made to the unknown backend on 3000.

Migration: 20260928120000_restaurant_foundation is additive (authority defaults
POS, catalog revision 0, old items enabled, nullable frozen Device snapshot).
All 45 migrations applied from empty to the disposable database. No live Vankisi
DB, existing Hive store or custom website was used or changed.

## Validation results

- Empty PostgreSQL migration chain: 45 migrations; Prisma validation passed.
- Foundation HTTP/DB: 7 tests; existing POS menu identity: 12 tests;
  existing onboarding: 6 tests; existing W2/W3 website integration: 23 tests.
- Targeted menu/media/feature backend units: 19 tests.
- Dashboard: 90 tests; restaurant-web: 19 tests; both production builds pass.
- Hive import: 3 tests, including the exported real server snapshot; targeted
  Flutter analysis passes. No operational Hive data was opened.
- Browser proof covers signup, logo/address first run, Cloud hierarchy and variant
  creation, item photo/presentation, real preview, publish, public menu and 390px
  layout. Screenshots are temporary local artifacts under /private/tmp/foundation-*.
  Reproduction script: apps/backend/scripts/prove-foundation-browser.cjs (supply
  PLAYWRIGHT_MODULE and BROWSER_EXECUTABLE if not installed locally).
- Backend production build passes. Full test-inclusive tsc still reports the
  pre-existing UUID-template inference error in edge-foundation.integration.spec.ts
  line 97; it is outside this milestone and was not changed.

Remaining work is the explicitly disabled production activation/authority handover,
complete local freshness inventory/writer fencing, offline receipt-media projection,
and future table/layout/policy Backoffice domains. Staging is not a working POS
bootstrap, and this milestone does not claim a Cloud-to-POS production cutover.

## Admin setup

The standard catalog includes `WEBSITE_ONLY` with only the WEBSITE feature.
Migration `20260929120000_website_only_plan` seeds it; existing installations
can also use **Admin → Plans → Add Website-only plan**, an idempotent, audited
SUPER_ADMIN operation. Neither action reassigns existing venues.

For a previously created but unused venue, open **Admin → Venues → Product →
მენიუს მართვა Dashboard-ში**. Enable/disable acts directly without an
acknowledgement checkbox. Disabling only stops owner catalog writes; it preserves
the catalog, public presentation and CLOUD authority. Reenabling resumes editing.
The server rechecks admission under the Venue lock, blocks CUSTOM websites,
devices/enrollment history, catalogs and operational records, and audits the
editing/authority change. This is not a migration path for an established POS.
Plan assignment alone does not change menu authority. Cloud-to-POS production
activation remains outside this milestone.
