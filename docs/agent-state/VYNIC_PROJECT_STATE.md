# Vynic Project State

Compact snapshot of implemented facts. This is not a changelog or an
architecture manual. Current code, schema, migrations, contracts, and tests win
if this file becomes stale.

Some phase documents preserve the state at the time they were written. In
particular, older deferred lists for enrollment, tenancy, and Platform Admin
predate Step 6C; use this snapshot and `docs/EDGE_COMMAND_MIGRATION.md` for the
current transport status.

## Current Product Shape

- `apps/operations/` is one Flutter codebase for the offline-first desktop POS
  and the mobile/desktop Manager client.
  POS targets Windows first; Manager targets Windows/macOS/Android/iOS. This
  macOS development host does not replace Windows release/device qualification.
- `apps/backend/` is the modular NestJS service over PostgreSQL through Prisma.
- `apps/platform-web/` is one customer-facing product: the public Vynic site
  (`/ka`, `/en`; `/features`, `/pricing` open home sections), owner sign-in
  (`/login`, `/request-access`, `/invite#token=…`) and the owner dashboard
  (`/dashboard/<section>`), plus the internal Platform Admin at `admin.vynic.ge`
  (locally `admin.localhost:5173`, sign-in `/login` on that host). Old
  `/admin` and `/admin/*` addresses return to `/` on the same host. Owner routes use only the CustomerAccount session
  and Admin only the PlatformUser session. Old `/portal…`, `/signup` and `/start` links
  redirect to their `/login`, `/request-access`, `/invite` or `/dashboard` equivalents.
- `apps/vankisi-custom-web/` (package `vankisi`) is Vankisi's bespoke website and
  the first production CUSTOM frontend. It stays standalone and does not use the
  starter or the shared client. Future CUSTOM clients may start from
  `templates/custom-site/` as `apps/<client>-web` over the optional shared client
  `packages/website-client/`; one backend serves all of them.
- `apps/restaurant-web/` is the generic multi-Venue SaaS restaurant website. One
  build serves every SAAS Venue; the request Host decides which restaurant.
- `packages/contracts/` owns the generated Cloud/Edge command, table-identity
  and Go/Dart foundation protobuf wire contracts.
- `apps/edge/` provides the non-authoritative Go foundation and Phase 2A shadow
  Order/Table coordination. Explicit Flutter observers compare proposals/results;
  production operation remains owned by the Phase 0 Primary POS.

## Current Architecture

- The POS owns live restaurant operation and persists it in Hive. Cloud mirrors
  operational state and coordinates Manager, website, and Edge work.
- PostgreSQL uses shared `pos` and `website` schemas with explicit
  `Organization -> Venue` ownership; Venue is the operational tenant boundary.
- Tenant authority is server-owned: Device -> Venue for POS, Staff -> Venue for
  Manager, Host -> VenueDomain -> Venue for public website requests, and booking
  identity -> Venue for payment callbacks.
- `PlatformUser` is a separate cross-tenant principal. It is not Staff and has
  no Venue membership. Platform sign-in is rate-limited per client IP and per
  normalized email in 15-minute windows, before any account lookup, with the
  same limits as owner sign-in; there is no Platform MFA, email recovery or
  session revocation.
- Website signup/signin/password-change inputs are bounded before password
  work; `/api/auth` JSON/form bodies have an 8 KiB ceiling. Valid CSRF tokens
  must be present and match. Per-process 15-minute windows admit at most 20
  attempts per peer and 10 per normalized global identifier (or authenticated
  user for password changes); successful attempts count and changing Host
  cannot reset an identifier window. Real HTTP/PG regression passes in
  `docs/SEC03_WEBSITE_AUTH_ADMISSION.md`. Shared multi-replica limits, session
  revocation/refresh/logout semantics and Platform MFA/recovery remain open
  SEC-03 release gates; this source qualification is not rollout evidence.
- The staff plain-PIN vault (`staff:plain_pins`) is one encrypted `setting` row
  per Venue, and every read/write requires a resolved tenant. There is no
  bootstrap-Venue default: an unestablished Venue raises rather than being
  served the bootstrap Venue's credentials.
- Staff creation, PIN changes and reactivation reject PINs held by another
  active Staff in the same Venue, including Platform-managed access. Manager
  role promotion checks retained credentials too. Manager CRUD, Platform access
  and POS staff sync serialize on the Venue lock; credential and vault writes
  are atomic. Manager Staff mutations also record their existing POS delivery
  intent in that transaction; pending/claimed Edge and pending legacy Staff work
  protect the Cloud identity, role and credential from an older POS snapshot.
  Queue persistence failure rolls back the mutation. Unchanged legacy snapshots
  remain idempotent, but existing
  duplicate Manager PINs still fail login until an authorized PIN change.
- Cloud-originated POS work uses a persistent pull queue. The Edge initiates the
  connection, executes locally, journals the outcome, and acknowledges it.
- Vercel browser API routes can reach Render through an authenticated same-origin
  gateway. `VYNIC_WEB_PROXY_SECRET` stays server-only; verified metadata supplies
  the public Host and visitor admission IP before CORS/tenant reads. Vercel Node
  routing middleware derives private metadata from Request URL/system IP; generic
  forwarded headers supply no gateway authority. Global
  forwarded-host trust stays disabled. Website cookies/CSRF and Device/Staff/
  PlatformUser/CustomerAccount authority remain unchanged. Configuration and
  verification: `docs/VERCEL_RENDER_INTEGRATION.md`.

## Current Phase

- Beta subscription licensing source uses a Device/installation/Venue-bound
  Ed25519 lease capped at server verification + 24 hours and known commercial
  expiry. Native suspend-aware time and action admission enforce it. Same-boot
  app restart restores the original signed deadline from the OS vault; uncertain
  boot/clock/storage continuity requires online verification. Georgian/English restriction UI
  preserves records/sync and unchanged pre-existing bill settlement. This is
  separate from the timeless explicit nonfiscal capability. Production signing,
  deployment and Windows qualification remain gates. See
  `docs/OFFLINE_SUBSCRIPTION_LICENSE.md` for evidence and limitations.


- Commercial subscription lifecycle connects explicit Trial approval to atomic
  provisioning and adds anchored paid periods, server upgrade quotes, deferred
  downgrades/cancellation, suspension/resume and trusted/manual payment receipts.
  Platform Commercial owns state-aware lifecycle actions and exact local timestamps
  with timezone; Product owns capabilities/overrides/menu policy; Website owns
  provisioning, publication, domains and hostname review. EXTEND_TRIAL preserves
  the start and requires a later end; confirmed END_TRIAL immediately cancels
  commercial access with actor/reason/before/after audit and retains data.
  There is no production billing provider. See `docs/COMMERCIAL_SUBSCRIPTION_LIFECYCLE.md`.
  Commercial Access Hardening separates ownership from product assignment. New Venues start NO_PLAN, with Cloud menu editing off.
  Website plans need no POS/Manager. Operators can admit empty Website Venues
  to CLOUD catalog authority; existing operational authority is preserved.
  Admin Plans includes WEBSITE_ONLY (WEBSITE alone); Venue Product offers an
  audited Dashboard menu editing on/off control without acknowledgement.
  First enable checks for no devices, enrollment, catalog, or operational history.
  Disabling editing preserves Cloud authority, catalog and public presentation.
  The Menu is one canonical Cloud catalog (D030, `docs/CANONICAL_MENU_SYNC.md`):
  per-node revisions, idempotent mutations recorded once per (Venue,
  mutationId) with actor/source, explicit conflicts, tombstones and
  changes-since catch-up. MENU-03 stores the complete accepted response in the
  mutation transaction; retries preserve its outcome after edit/delete/restart.
  Legacy null results force resync/review; conflicts are not persisted. Real
  HTTP/PostgreSQL and native POS lost-ACK proof: `docs/MENU03_EXACT_RETRY_OUTCOME.md`.
  MENU-06 removal retires retained identities (`retiredAt`, separate from
  `enabled`) and emits the existing DELETE/tombstone projection contract.
  Recipes and website presentation survive; ordinary edits cannot resurrect.
  Authenticated retired views and explicit revisioned `patch.restore: true`
  restore the same ID, with active parents required. Parent removal rejects
  active children; item retirement also retires its active variants. Pending
  historical POS edits remain in the journal but cannot recreate an absent
  canonical ordering node. Delayed consumption, reversal, same-ID restoration,
  native Hive restart and portable restore are proven in
  `docs/MENU06_SAFE_MENU_RETIREMENT.md`. MENU-05 UI remains separate.
  MENU-09 requires authenticated current-request `CANONICAL_MENU_V2` support
  for CLOUD enrollment, bootstrap/runtime-config and Menu/full-sync boundaries;
  optional deployment-owned integer build floors supplement capability admission.
  Full canonical snapshots return HTTP 426 before any snapshot writes. All ACTIVE
  Devices need fresh compatible reports and a final primary legacy sync before
  an explicit Owner cutover, with stable UUID/adoption checks and offline-edit
  confirmations. Native Hive/portable restore and real HTTP/PG proof pass in
  `docs/MENU09_CLIENT_COMPATIBILITY_GATE.md`; physical old Windows artifacts
  remain OPS-01 qualification. Offline operation and primary containment remain.
  Writers are the owner Dashboard (not blocked by POS
  presence) and ANY enrolled POS Device (no primary requirement); Manager and
  both website renderers read it. POS Menu edits use a shared local queue and
  flushed write-ahead commit before journal/state/projection writes and UI
  success (MENU-02, `docs/MENU02_LOCAL_MENU_DURABILITY.md`). Startup replays
  interrupted commits before migrations/defaults; sync HTTP waits use a separate
  queue. Reapply and multi-entry discard are recoverable; mutation IDs survive
  restart. Hive remains v9, with additive local Menu protocol v1 and unchanged
  journal entry format. The operational menu is a projection of canonical state
  plus the journal, with explicit conflict
  choices in Admin Menu. New Venues are created canonical (CLOUD); established
  POS Venues (Vankisi) stay in legacy POS-snapshot compatibility until an
  explicit Owner cutover through the MENU-09 fleet/readiness gate. Canonical
  snapshot HTTP requests fail explicitly; compatible clients use separate
  journal/change-feed sync. Device-bound bootstrap v1 staging remains. See
  `docs/CLOUD_RESTAURANT_FOUNDATION.md` for the wider domain matrix.

- MENU-01 complete restaurant backup/restore is implemented and proven on native
  macOS processes (`docs/MENU01_BACKUP_RESTORE.md`). Format 2 includes 17 explicitly
  classified stores, stable Menu generation/cursor/intents, closure/Sale lifecycle
  and command outcomes; a local admission boundary drains Menu WAL before snapshot.
  Checksum/model/Venue validation precedes replacement, a flushed restore marker
  replays before startup defaults, and a digest receipt makes repeat restore a no-op.
  Admin portable export uses password-authenticated encryption; fresh installations
  keep their own Device identity and require matching enrollment/operator handoff.
  Legacy imports retain an incomplete-history sync quarantine. Hive remains v9;
  SEC-05 local secret custody and OPS-01 Windows replacement qualification remain.

- Local POS releases have a one-command Mac publisher:
  `apps/edge/tool/publish-local-pos.sh`. It uses the existing Parallels Windows VM,
  detects the active registered LAN, builds real Windows POS, transfers/validates
  its ZIP, signs and verifies the development feeds. Pending builds retry without
  another version increment; unchanged published source is reused. Publication
  rejects changed binaries under an issued version and rejects backward feeds. Signing keys
  remain on Mac; publication never installs POS or replaces Edge. See
  `docs/LOCAL_WINDOWS_RELEASE_TEST.md`.

- Private R2 release preparation verifies qualified beta ZIPs, signed metadata
  and complete conditional-upload readback. The private `vynic-installers`
  bucket exists; no live upload/credentials/deployment are configured. Opt-in
  backend authority + Worker direct R2 streaming retain per-request revocation,
  HEAD/Range and quotas. Manual release approval remains required; no automatic
  Windows release CI exists. See `docs/PRIVATE_R2_RELEASES.md`.
- Setup supports explicit downloaded signed POS+Edge pair upgrades with retained
  binary recovery and authenticated startup probation. It preserves data,
  identity and monotonic counters; the coordinator is not downgraded on rollback.
  Native Windows qualification of the new integrated beta is still pending.
  The active TCP/Windows RAW printing path remains bundled; the held standalone
  printer-agent is not activated. See `docs/WINDOWS_INTEGRATED_BETA.md`.

- Current Windows beta is POS 1.0.1 build 18 / Edge and Setup 1.0.1.18 from
  reviewed accounting/entitlement source 1dea4294, with current main and build 16
  printer fixes. Native Windows and macOS each pass 335 Flutter regressions.
  The complete offline ZIP is GitHub draft asset 673319647, selected by three
  nonsecret backend values; the existing repository-limited read credential is
  preserved. Both Ed25519 envelopes and immutable storage readback/hash pass;
  original build 16 assets remain unchanged. Technical release root/catalog,
  anonymous assets and automatic feed stay closed. Setup receipts pin their
  baseline; this is a fresh-install package, not an existing-terminal upgrade or
  a permitted downgrade from lab 1.0.14. Authenticode, clean install/runtime,
  existing-terminal handoff and physical printers remain unqualified. End-user
  browser delivery is blocked by a confirmed storage-provider 403 on the
  backend's authorized HEAD request. Earlier storage readback used the desktop
  release credential and did not verify the Render-held credential. Safe provider
  diagnostics are implemented; client transfer remains unverified.
  Current delivery and owner checklist: `docs/PROTECTED_WINDOWS_DOWNLOADS.md`,
  `docs/WINDOWS_BETA_TEST_INSTALL.md`.

- POS touch input shares TEXT/NUMBER/DECIMAL/PIN modes, controller-backed fields,
  one text keyboard and one numeric/PIN pad. Login, lock and Staff authentication
  pads remain available when the optional operational keyboard is off. PIN digits
  update masked displays immediately; Lock unlocks automatically on a matching PIN,
  while Login and Staff submit by action/Enter.
  Reservations, Menu, Packages, settings and Inventory search edit their actual
  controllers live; keyboard docks retain real field focus and a blinking caret,
  reveal only obscured input, and do not resize the whole POS page. Standalone
  prompts own one visible input, while form keyboards have no second text box.
  Inventory remains read-only apart from search/filter controls. Management Center
  persists `posOnScreenInputEnabled` (default on); Manager does not load it.
  The POS locale observes the persisted language above its Navigator, with SDK
  locale delegates and a shared UI catalog for navigation, authentication, input,
  settings and the affected operational surfaces. Open routes/dialogs update without
  discarding drafts. Menu's language action uses the same persisted setting.
  Quit uses a responsive Vynic modal and the existing safe shutdown coordinator.
  Login/lock date and time sit at the right edge; Home keeps a neutral work-date
  indicator beside the clock at compact/fullscreen widths. Regression proof:
  `test/widget/pos_interaction_pass_test.dart` under `apps/operations/`.

- POS Home now uses a default-collapsed right action panel that allocates its
  own layout width; the service dashboard and duplicate Reservations button
  are removed. Quick checkout uses virtual takeaway and existing durable
  Order/closure journals without a physical table. Local estimates and takeaway
  collect optional full name/phone and search actual saved contacts/amount;
  estimate deletion re-reads the current stored Manager role. Reservation
  entry is compact with guest +/-; the staff lock keeps a 320 px PIN pad and
  unchanged authentication/back protection. This is uncommitted source;
  qualification and remaining gates: `docs/POS_CHECKOUT_RESERVATIONS.md`.

- POS modal routes share a scoped theme and keyboard viewport. Admin, Home,
  Order and estimate reservation entry use the same guarded form; guest fields,
  admin PIN forms and Menu product add/edit forms are shared. Form headers remain
  anchored while the dock opens; close/discard confirmations center in the usable
  viewport. Count exposes reservation/edit/print directly without a management
  modal; Takeaways uses two panes with direct menu editing and payment, separate
  from order cancellation. At 1024×768 their main targets paint at about 48 px.
  POS selects the bundled Georgian font at its root; Admin button/feedback
  themes retain that font. Shared page/Admin/modal controls use the scaled
  desktop touch target; short auxiliary windows keep a compact keyboard.
  The approved connected Count workspace is implemented and shared with
  Takeaways/Reservations; Menu/Order, payment/amount forms and internal Admin
  use the same typography, controls and hierarchy. Compact Admin dropdowns
  retain Georgian glyphs. Final source qualification is recorded below.
  Source qualification, isolated screenshots, keyboard latency evidence and
  existing printer aggregate failures: `docs/POS_UI_REWORK.md`. Native Windows
  rendering/performance qualification has not been run for this rework.

- Windows POS uses native borderless fullscreen with monitor/DPI refitting;
  Manager keeps its normal window. Login, About, the POS tray menu and Alt+F4
  share confirmed clean Quit:
  the existing readiness barrier excludes active transactions/startup probation,
  POS workers stop and local journals/Hive flush before only POS exits. Durable
  open Orders/Tables and Cloud backlog remain recoverable and do not block Quit.
  Home opens მართვის ცენტრი; restaurant settings and About are distinct. About
  is horizontally centered with responsive terminal details. Version labels prefer
  the running POS launch identity over transient Edge state; the last rollback
  remains visible across background checks. About shows release/download state
  and distinguishes feed/Edge connectivity failures
  from installation failures. Update readiness names active blockers and clears
  completed blockers; data preparation/install/restart have distinct indicators.
  Cloud claim/ack network waits do not own mutation admission; command execution
  and journal completion do, with a freeze recheck after claim. Local release profiles trust both 10.10.10.3 and
  172.20.10.2; changing networks does not rewrite installed endpoints.
  Local development POS publication is 1.0.14 / signed release 15, built from the
  sealed POS-02 candidate and verified through the existing signed updater in the
  Windows 11 ARM VM. The HTTPS server is running at 10.10.10.3:8443 with its
  publication watcher disabled; signed metadata expires October 11. See
  `docs/WINDOWS_POS_FULLSCREEN_QUIT.md` and `docs/POS02_WINDOWS_INSTALLER_HANDOFF.md`.

- Windows POS has an opt-in Go Edge updater: signed Ed25519 release manifests,
  silent verified ZIP staging, explicit Georgian Update Now/Later in About,
  one readiness/admission barrier, startup health and binary-only rollback.
  Durable open Orders/Tables and Cloud outboxes do not block; uncertain intents,
  projection recovery and in-flight payment/close/write operations do. Manager,
  Phase 0 fencing and Phase 2A production authority remain unchanged. macOS
  simulations pass. `VynicSetup.exe` provisions a per-user Windows host from
  signed Edge/POS bundles, with native Win32 UI/Shell Link integration (no runtime
  PowerShell), a per-user destination wizard and explicit Update POS entry point
  with download-first monitoring, byte/percentage progress and required recovery
  stage/elapsed reporting,
  restricted ACLs, local-only Edge host startup,
  updater-aware branded shortcuts and data-preserving repair/uninstall. Ordinary
  POS launches show only POS, with health monitoring and error reporting retained. Uninstall
  requires stopped processes but not successful update recovery; interrupted
  journals are retained and removed installations offer Install of the current
  signed POS while keeping Edge pinned. POS resolves its pinned Hive data directory
  before database startup, independent of Windows publisher metadata; failed
  health failures are visible and bounded. Go monitors startup stabilization in
  the background while POS shows login; login/enrollment admission waits for its
  verified result. Windows login shows the installed POS version and a responsive,
  right-aligned work date; its Program Update action is removed. Updates remain
  in About and the first-run screen, including percentage/MB download progress.
  A real Windows VM startup proof reopens
  an isolated legacy Hive copy through the authenticated health handshake.
  The Go source now skips repeated stabilization for an already verified ordinary
  launch, while requiring a fresh authenticated data-ready heartbeat; install,
  repair and rollback still stabilize. The explicitly approved Windows lab
  upgrade pins Edge 1.0.1 / bootstrap 3; current POS publication is 1.0.14 / release 15.
  The lab serves Setup 1.0.8.0 built from the committed native source on the
  primary origin and both LAN profiles (reproducible; hashes in
  `docs/WINDOWS_DEFENDER_REVIEW.md`); the served bytes scanned clean on the VM.
  A fresh Windows launch reached verified health in under one second (previously
  30 seconds), with restaurant data, Edge identity and POS binary verified unchanged.
  This was manual local maintenance, not an Edge self-update feature. POS binaries use
  bounded `current/staging/rollback` slots: 30-second authenticated stabilization
  precedes permanent rollback/temp cleanup; cleanup crashes retry deletion only.
  Signed bootstrap metadata requires a layout-2-capable Edge; repair never changes
  its pinned baseline. Deferred updates stay staged. Authenticode-ready PE
  metadata/signing tools exist; production signing and
  Windows qualification remain required. The native Setup builds scan clean
  under Defender on the lab VM and install/update/repair without detection;
  the earlier PowerShell-era Bearfoos.A!ml detection stays unexplained because
  its bytes were never hashed. See `docs/WINDOWS_DEFENDER_REVIEW.md`. See
  `docs/POS_WINDOWS_UPDATER.md` and `docs/WINDOWS_SETUP.md`.

- Edge Phase 2A adds SHADOW Order/Table revisions, request idempotency, a durable
  event sequence, tombstones and replay/snapshots over Phase 1 TLS pairing.
  Two separate terminal processes/Hive stores converge against one Go Edge.
  Hive v9 adds stable Order/OrderLine UUIDs; existing Table UUIDs are reused.
  Explicit observers capture supported proposals before primary Hive writes and
  compare the result. They are unattached by default. Production authority remains
  Phase 0: no operational Edge selection or cutover gate is enabled. Remaining
  writer coverage and cutover prerequisites: `docs/EDGE_PHASE2A_ORDERS_TABLES.md`;
  foundation/fencing: `docs/EDGE_PHASE1_FOUNDATION.md`, `docs/EDGE_PHASE0_PRIMARY_DEVICE.md`.
- Current multi-POS work adds a separate ISOLATED_PROOF client with protocol 1.3,
  explicit operational/control/audit/financial/Staff/policy entity kinds, one
  dedicated flushed Hive frame, stable pending intents, exact result receipts
  and contiguous replay retaining frozen effects. It is not attached to normal
  POS boxes or startup. Scripted-transport tests are not actual Go/RPC/LAN proof;
  full writer coverage, three-terminal acceptance and controlled cutover remain
  required by `docs/POS_MULTI_TERMINAL_READINESS_PLAN.md`.
- The latest completed sequence covers Money Integrity 1A/1B, POS enrollment
  1C, incremental audit sync, Edge Step 6C, Menu Identity Phases 4.5/4.6, and
  the Phase 5 Cloud Sale Ledger/Manager financial experience.
- Inventory Steps 1, 2, 3 and 4 are implemented after the Cloud Sale Ledger. Stock
  Items, Suppliers, Receiving/waybill documents, the StockMovement quantity
  ledger, Menu consumption definitions and automatic Sale consumption/restore
  reversal are present. Step 4.5 adds food/beverage catalog classification, supplier
  product links, business-date daily receiving and current weighted purchase /
  theoretical Menu costs. The procurement rework supersedes historical-purchase
  averaging with moving stock valuation and separates supplier payments from receipts.
  Step 4.6 consolidates procurement Financials, responsive
  Manager Inventory and read-only POS Admin inspection; historical Sale COGS,
  waste and stocktake remain later steps. Step 4.7 adds Staff payroll and recurring
  obligations/reserve planning; module entitlements and manual Platform commercial control are implemented in SaaS Phase 2.

## Completed Foundations

- SaaS Manager Phase 1 is implemented: stable Venue login codes + PIN,
  Staff-resolved socket rooms, tenant-carrying notifications/push/presence,
  Venue-local echo suppression and removal of unused `/sync/diff`.
  Old Vankisi PIN-only clients require an explicit expiry setting capped at
  2026-12-01; migration/client rollout is not established by repository code.
  Manager now validates and remembers Venue selection per device/API origin:
  first launch is Restaurant Code entry, subsequent launches are PIN-only.
  Logout retains selection; restaurant switching clears session/cache/selection.
  Production login/settings hide API controls. Platform and owner Manager setup
  display/copy the existing immutable code. See `docs/MANAGER_SAAS_PHASE1.md`.
  Platform Manager access shows pending delivery to the selected Primary POS,
  its last-seen status and a device-selection link; enrollment does not replace
  Primary automatically. Access/enrollment/device mutations show busy feedback
  and prevent repeated submission while pending.

- Manager presentation uses a shared light/dark Material theme and Georgian
  typography, with named desktop navigation, a compact rail and phone More menu.
  Management uses Team, Reports, Audit and Settings primary sections. Reports is
  a four-link directory into actual report/Sales workspaces; Audit presents the
  entitled Activity feed with operational Audit in secondary access. Team keeps
  its toolbar inside connected rows and access details in a secondary view.
  Financial planning uses centered dialogs and actual obligation summaries;
  receiving, recipes and order detail/editor/cart use connected bounded forms
  with advanced fields and guarded workflows retained.
  Connection feedback starts with the authenticated monitoring session, avoiding
  a false outage at the remembered-venue PIN screen.
  Count is one destination with New/Saved tabs and retained in-progress drafts;
  Reservations retains adjacent new reservation and walk-in actions. Wide Tables includes the actual order-detail
  inspector; forms and selectors use bounded content and centered dialogs.
  Existing auth, entitlements, financial/inventory workflows, freshness and
  retained POS requests remain on their established services. Actual-widget
  synthetic renders and regression evidence: `docs/proofs/MANAGER_PARITY_2026-10-17/README.md`.
  Dashboard revenue/occupancy charts use the approved preview geometry with real
  API data; missing values remain unavailable. Dashboard outflows/balance read
  the existing financial response only when its business date matches.
  Native/physical interaction and printer qualification are not implied by that
  UI proof.

- Organization/Venue foundation and Venue-scoped operational data are
  implemented (Steps 4A and 4B1).
- Manager Staff -> Venue resolution and `MANAGER_APP` enforcement are
  implemented (Step 4B2A).
- Public Host -> Venue resolution, Venue-owned website tables/bookings, and
  `WEBSITE` enforcement are implemented (Step 4B2B).
- Plan, Feature, Venue assignment/override, and WebsiteMode are implemented
  (Step 5A). Effective features come from `VenueEntitlementsService`.
- Edge queue/backend transport, POS claim/execute/journal/ack, and real command
  migration are implemented (Steps 6A-6C).
- Platform principal/API and the authenticated Platform Admin UI are implemented
  (Steps 7A-7B).
- One-time, Venue-bound POS self-enrollment is implemented (Phase 1C).
- Inventory Step 1 is implemented: Venue-owned Stock Items and Suppliers use
  immutable UUIDs, optional Venue-unique normalized SKUs, soft activation, and
  exact minimum-stock thresholds.
- Inventory Step 2 is implemented: Venue-owned `Receiving` documents
  (`DRAFT`/`POSTED`/`CANCELLED`), frozen `ReceivingLine` purchase snapshots,
  item-specific `StockItemPurchaseUnit` packaging ratios, and the append-only
  `StockMovement` ledger with the `RECEIVING` and `RECEIVING_REVERSAL` types.
- Inventory Step 3 is implemented: `MenuConsumptionRecipe` +
  `MenuConsumptionComponent` define what one sold Menu Item consumes. One
  generalized model covers direct bottled products, draft pours by volume and
  multi-ingredient recipes; editing a definition writes no `StockMovement`.
- INV-01 F1 has a backend location foundation: one stable default per Venue,
  historical Receiving/StockMovement location backfill, composite tenant FKs,
  movement-derived per-location quantities and additive Manager location APIs.
  Receipt selection and exact reversals retain their document location; old
  version-1 POS consumption retains the default. D015 Venue-wide valuation is
  unchanged. This is a partial candidate, not full Inventory: F2 transfers,
  location UI and configured POS issue locations remain pending the product
  decisions in `docs/INV01_LOCATIONS_TRANSFERS_CHECKPOINT.md`.
- Inventory Step 4 snapshots new close-time consumption inside the durable POS
  Sale, then independently retries Device-authenticated effects to Cloud.
  Cloud atomically materializes `CONSUMPTION` and exact
  `CONSUMPTION_REVERSAL` movements; restore/re-close preserves old snapshots
  and uses a new Sale identity. No historical Sale backfill occurs. Internal
  closes are explicitly excluded because current data cannot distinguish
  physical internal use from bookkeeping. Unmapped lines never block close and
  remain visible in Manager history. See `docs/INVENTORY_STEP4.md`.

- Inventory Step 4.5 is implemented: `SupplierProduct` uses composite Venue-safe
  foreign keys; Stock Items persist FOOD/BEVERAGE classification; Receiving has a
  separate businessDate and full-day procurement summaries. The procurement
  rework now uses movement-derived remaining quantity/value for current
  theoretical Menu costs. Historical phase context: `docs/INVENTORY_STEP45.md`.

- Inventory Step 4.6 makes POSTED Receiving the sole purchasing entry point.
  Known legacy Market Expense categories are rejected and excluded from Expense
  reporting; shared Expense storage/audit remain. Legacy salary Expense history
  is retained read-only after Step 4.7. Financials separates purchases,
  supplier payments, other expenses, payroll and obligation payments. Only actual
  payments enter outflows; receipt totals are purchases. Dashboard links
  procurement/stock warnings into Inventory. POS
  Admin exposes read-only stock, recent movements/receipts, recipe status and
  unmapped sold products from catalog v5. See `docs/INVENTORY_STEP46.md`.

- Inventory procurement rework is implemented: stock creation supports
  existing Menu goods, ingredients and bulk beverages, retaining StockItem and
  generalized recipes. Receiving has explicit Post/Draft actions, exact price or
  line-value entry, and retry identities. SupplierPayment is append-only with
  derived debt/partial/paid states and explicit reversal. Old settlement is
  unverified until reconciled; cancellation requires verified zero net payments.
  StockMovement freezes current moving-average issue costs and exact reversal
  values under item locks, in Cloud acceptance order. Historical values are
  explicitly reconstructed; negative/unknown bases are provisional. Manager
  and read-only POS inspection show current values; checkout is unchanged.
  Manager recipe/current stock labels distinguish current, provisional and
  reconstructed bases from historical close-time COGS. Movement details show
  frozen original/reversal values and their source. Financials separates fiscal
  revenue, close payments/applied advance, recorded outflows and supplier debt;
  revenue minus outflows is not presented as realized profit or full cashflow.
  Manager consumption and Stock movement histories use bounded keyset pages,
  load-more and complete-filter CSV export. A creation window excludes new/late
  arrivals until refresh; reversal state is current per request, not an MVCC
  snapshot. Legacy array/POS excerpt contracts remain. See
  `docs/INV02_INV04_INVENTORY_PROVENANCE_HISTORY.md`.
  Manager Inventory is a main destination beside Financials with a Dashboard entry;
  it is removed from Management. Its home prioritizes new receiving, daily work
  and secondary supplier/Menu catalog maintenance. Receiving includes payment choices and supports self-purchase
  source snapshots without fake Suppliers. Dish/drink composition reuses the
  existing recipe engine. Inventory uses a grouped home and section menu for
  receipts/stock/supplier/composition/payments. Main and Management tab reactivation
  resets vertical scroll. The shell reserves bottom navigation height, so the final
  composition product/variant remains tappable. Receiving requires explicit goods
  selection and creates missing stock/packaging inline with retry identity. Goods
  entry and payment/review are separate steps; advancing writes nothing and going
  back preserves inputs. Creating a supplier opens its detail with a searchable
  assortment: existing stock can be linked or created inline, and links can be
  removed without stock/receipt effects. Failed linking retries the same stock
  identity. Assortment goods are prioritized when receiving from that supplier.
  Detail keeps receipts and filtered payments; Menu setup and dish shortcuts
  remain separate. Composition and Menu selection
  share category/subcategory/variant browsing; incomplete variants remain in the
  unfinished filter. Stock supports confirmed archive
  and same-identity restore with history retained. Payments/debt have supplier,
  date and status filters; payment dates are distinct from receipt dates, and
  cancelled receipt payment/reversal history remains visible. Moving cost and
  active Menu usage remain on stock cards.
  See `docs/INVENTORY_PROCUREMENT_REWORK.md` and `docs/INVENTORY_DAILY_UX.md`.

- Financials Step 4.7 adds Venue/Staff compensation rules, frozen PayrollPeriod
  snapshots and append-only payroll accrual/payment history. Daily wages require
  explicit payable dates; no hours/attendance are inferred. Legacy salary Expense
  rows stay unmapped/read-only with no destructive migration. Payroll references
  retain Staff identities when login removal/sync deactivates them.
- Manager Payroll separates overview, daily staff, monthly staff and payments.
  Salary-type selection shows only the relevant rate input. The daily sheet
  defaults to the Venue business date (including its month across midnight),
  excludes monthly/manual periods, and rejects future days. Worked toggles use
  request UUIDs, a period lock and linked append-only signed accrual adjustments;
  reversals cannot reduce accrued pay below paid pay. Original day identity,
  period rate snapshots and audit history survive reversal and Close Day.
  Totals use exact Decimal; only payments enter Financials outflows. Compensation
  changes still take effect in an unopened month, not midway through a frozen one.
- Recurring obligations use monthly snapshots and exact Decimal reserves/payments.
  Payments consume available reserve under a cycle lock; reserves are planning,
  never outflows. Daily recommendations include today and the due date, clamp
  overdue divisors to one, and round upward to cents. Changes preserve opened
  periods. Dashboard deep-links into the separate Payroll/Obligations screens.
  Global Audit and Staff -> Venue authority cover every new mutation; no new
  entitlement or POS/Close Day dependency is introduced. See
  `docs/FINANCIALS_STEP47.md` for rules, preservation and rollout.

## POS / Edge State

- A Device credential resolves the Device and Venue; the legacy shared POS key
  cannot claim Device-specific Edge work.
- Enrollment is available through Platform Admin and `POST /edge/enroll`; the
  POS stores the issued credential outside Hive in `edge_device.json`.
- Contract v2 declares 20 types: `NOOP` plus 19 real commands covering orders,
  dine-in/takeaway, reservations, expenses, staff, and three print operations, plus guarded table repair and Order editing.
- All declared command types have POS handlers. Legacy operations converge on
  `PosCommandApplier`, shared by Edge and the legacy LAN adapter; guarded repair
  and Order edit use durable repositories through Edge only.
- Delivery is at least once. The Hive `edge_command_journal` prevents replay of
  completed work; interrupted print commands fail visibly instead of printing
  a possibly duplicated check.
- Enrolled Venues use Edge dispatch. The old callback client/outbox/listener are
  frozen fallback only for a Venue with no enrolled Device and for rollout
  compatibility; no new operations belong there.
- Fleet-wide enrollment is not established by repository code. Until every
  deployed POS has a Device credential, the fallback cannot be retired.

## Money Integrity State

- Phase 1A and 1B are implemented: material money mutations are locally audited,
  expense and adjustment data reaches Cloud, and legacy POS ingest fails closed.
- Supported fiscal and internal payment closes use `CloseTableTransaction` with
  a durable `closureId` and Hive closure journal. Cancellation, hard-delete,
  emptied-by-transfer, and Close Day paths are separate. Startup recovery
  treats the Sale as the financial boundary and never recreates it. A shared,
  journaled post-Sale step idempotently completes the Order, physical Table
  where applicable, genuine linked Reservation, and typed/locked closure audit
  before the journal becomes complete; crash-before-Sale recovery still
  abandons the attempt without revenue or closure effects.
- Successful fiscal closes emit the typed `CLOSE` audit event, while internal
  closes emit `INTERNAL_CLOSE`; `CANCEL_TABLE` remains cancellation-only. Close
  events carry structured closure identity and money details locally and in the
  Cloud audit mirror. Every close event also carries `details.source`
  (`AuditSource` wire values `POS`, `MANAGER`, `EDGE`, `SYSTEM`,
  `SYSTEM_RECOVERY`, `DEVELOPER`); a close finished by startup recovery keeps
  its type and operator actor but records `source=SYSTEM_RECOVERY` and
  `recoveryAction=finished`. A closure already finalized is never re-stamped.
- Every genuine Order cancellation goes through `CancelOrderTransaction`: the
  POS detail screen, the Takeaway home panel, the Admin close-day repair list,
  and the Manager commands `ORDER_CANCEL` and `ORDER_STATUS_UPDATE
  status=cancelled`. It writes exactly one `CANCEL_TABLE` event (with
  `orderKind`, `tableRefs`, `source`, `actorId`, `actorName`, `approvedBy`,
  `reason`, `businessDate`), locks the report as CANCELLED, writes one
  non-fiscal `isCancelled` record with zero collection, moves a genuine linked
  Reservation to cancelled without touching its identity or link, frees
  physical tables (never for Takeaway), and writes the Order status last so a
  crash retry or a repeated Manager delivery converges on one cancellation. A
  closed Order is not cancellable until restored.
- Normal operations no longer hard-delete business Orders or their audit
  reports. `ORDER_CANCEL` is a cancellation, not a delete. The only physical
  delete of a live Order is the repair primitive
  `OrderRepository.hardDeleteOrderForRepair`, which has no operational caller,
  preserves the audit report, and logs `ORDER_HARD_DELETED`. Close Day still
  deletes already-closed Order rows because their Sale is the durable record.
- POS-01 Close Day has a stable, flushed protocol-v1 intent in existing Hive
  `meta` and idempotent phase/audit replay before Menu recovery, migrations,
  defaults or business admission. The shared local gate drains admitted
  actions and queues new writers before their date reads and mutable model
  changes, including when the updater is disabled. Stale confirmations cannot
  close the next day. Format-2 backup validates and preserves pending/completed
  transitions; Hive remains v9. Native SIGKILL/restart proof and compatibility
  limits: `docs/POS01_RECOVERABLE_CLOSE_DAY.md`; physical Windows remains OPS-01.
- POS-03 item transfer journals stable request/Order identities and lossless
  before/after effects in existing `meta`, with exclusive admission and startup/
  restore replay before business writers. Both audits and empty-source closure,
  exact table release and genuine booking completion are one operation, with no
  Sale or menu repricing. Completed ID retries preserve later normal edits;
  malformed/pending identity conflicts fail closed. Format-2 snapshots preserve
  frozen line totals, package/advance fields and pending/completed receipts; Hive
  remains v9. Status DONE, with verified native crash recovery and development
  build evidence: `docs/POS03_CRASH_SAFE_ITEM_TRANSFER.md`. Windows smoke remains
  pending (`docs/POS03_WINDOWS_SMOKE.md`); physical release qualification is OPS-01.
- POS-05 is accepted for exact committed ec430880 operational source: shared
  reentrant writer admission, detached expected Order/Table images and
  durable create/activation/move/cancel intents enforce one active Order
  per physical Table. Stale/cross-writer actions refuse before audit;
  simultaneous views remain usable. Startup and format-2 restore complete
  exact interrupted intent before writers; completed stable-ID retries do
  not overwrite later edits. Existing ambiguity stays readable with a Home
  repair report and blocks unsafe mutation/rollback. Hive remains v9 with
  an additive durable legacy Reservation line-identity bootstrap.
  Clean Git copies of ec430880 pass 738 distinct Flutter tests in 62 suites,
  280 ownership plus 88 transfer SIGKILL/restart checkpoints, 52-file format,
  55-file analysis and main_pos development build on committed runtime hashes.
  Three pre-existing development URL WIP changes are excluded and not needed;
  they remain untouched. Authoritative exact-commit proof:
  `docs/proofs/POS05_COMMITTED_ec430880_2026-10-02.json`; runbook:
  `docs/POS05_ORDER_TABLE_OWNERSHIP.md`. Windows smoke remains
  PENDING_NOT_RUN/HELD (`docs/POS05_WINDOWS_SMOKE.md`), using a clean frozen
  commit export. Physical release remains OPS-01.
- POS-02 is an uncommitted implemented candidate, NOT_DONE until supported-model
  physical printer acceptance and the owner reconciliation policy are resolved.
  Legacy print_job:v1 rows remain readable; new routed print_job:v2 rows freeze
  Device/queue/driver/port or TCP destination, station revision and capability
  profile beside bytes/Venue/attempts/audit. A flushed sending marker precedes
  TCP or Windows RAW submission; post-write failure and interrupted sending stay
  uncertain without retry. Native timeouts retain identity/update admission until
  the original platform call settles. Accepted bytes never confirm paper.
  Optional compatible sound uses a separate flushed, spent per-attempt reservation
  after primary delivery settles; unknown/unsupported sound skips and failures
  do not alter print/cut/copy results. Isolated Windows amd64 POS Release
  compilation/linking now passes in the existing Windows 11 ARM guest using
  cached Flutter/MSVC/Firebase, with all 815 prepared source hashes unchanged.
  The corrected launcher passes the 483-test/32-suite Windows selection and
  48-file analysis. The actual read-only Win32 channel harness passes 208
  assertions plus 110 fake-core assertions, covering UI replies, FIFO, admission
  and a queued completion across teardown/recreation. No print documents or
  product startup/install/publication occur. The 23 built artifact hashes match;
  the retained archive's backslash entry names are not release-qualified.
  Evidence: docs/proofs/POS_WINDOWS_NATIVE_abf7e6b3_2026-10-06/.
  Driver/model/sound qualification and v2 reader/rollback compatibility remain
  pending; blocked/in-flight Winspool and valid RAW jobs are not established by
  the read-only harness.
  The journal remains in Admin; its Home entry was removed.
  Kitchen/bar/additional copies use Georgian Run/Cancel, fresh authenticated Staff,
  stable request IDs and a recorded fixed operator reason. Receipt copies and
  paper confirmation still require the unconfigured owner policy. Initial Order
  confirmation and remote creation replay preserve durable admission.
  Ordinary paper contains no job/attempt diagnostics; deliberate copies carry
  only `COPY`. IDs, reasons and uncertain outcomes stay in the durable journal
  and logs; no-byte retries keep the original/copy distinction and uncertain
  delivery still requires explicit operator reconciliation.
  The printer-scoped developer panel configures revisioned kitchen/bar/receipt/
  additional TCP or locally inventoried Windows routes and explicit paper/raster/
  cutter/sound capabilities. Legacy name/IP registrations remain unassigned.
  Navigation, handlers and repository reads/writes enforce that scope; managers
  alone cannot configure printers.
  A detached explicit line/destination planner prepares frozen station effects;
  shared operation/production dispatch integration is not yet activated.
  A dedicated isolated proof client retains flushed pending requests, exact
  outcomes and replay/effect receipts. Detached ordinary physical/takeaway
  create, physical move and cancellation use complete canonical views, explicit
  stable identity maps, frozen policy inputs and control CAS. A detached Manager
  retained-line quantity/removal planner and validating adapter preserve exact
  item-diff audits, retained UUIDs and existing fee/payment/ownership state.
  Eight focused macOS suites pass 143 tests; all 19 new cases, including three
  real local-Hive command-applier parity cases, also pass on Windows with clean
  three-file analysis. Legacy UUID/wall-clock differences are explicit in the
  parity comparison. New items, POS modification PRINT, status/fee changes and
  production command ingestion/ACK remain pending. Evidence:
  docs/proofs/POS_MANAGER_ITEMS_275688e1_2026-10-06/. These planners do not attach
  to production Hive writers or establish full writer/LAN coverage; see
  docs/POS_MULTI_TERMINAL_WRITER_COVERAGE.md. The isolated Go candidate now has
  generated protocol-1.3 proof contracts, schema-6 SQLite store migrations,
  signed origin enrollment and atomic business/effect/print admission. Actual
  synthetic Dart-to-Go mutual TLS tests qualify that detached proof boundary;
  production enrollment, complete business writers and older Edge rollback
  after an upgrade remain unqualified.
  The authoritative generic printer design is now
  `docs/VYNIC_PRINT_ARCHITECTURE.md`: business routing -> logical station/job ->
  physical attempt/fixed controller -> printer. The additive Go `printstation`
  domain supports configurable LOCAL/shared stations, source-independent routing,
  ordered compatible backups and strict station FIFO. Its existing-Raft adapter
  and no-quorum SQLite LOCAL proof retain immutable admission and separate
  attempts. Synthetic controller dispatch allows fallback only after definitive
  non-submission; UNCERTAIN never retries or falls back. Queue leadership does
  not move physical ownership. POS-02.B connects the station queue to
  signed production configuration and authenticated Go peer RPC. Normal Flutter
  admission, retained controller receipts, writer cutover and installed-service
  qualification remain pending. The station storage now uses schema-2 normalized transactional rows and
  checksum-addressed immutable payloads, deduplicated bounded snapshots and
  explicit 30-day terminal-history compaction with an admission time floor.
  Unresolved work and originals pinned by retained reprints are never expired.
  Older stores/proof peers are refused; no automatic migration is supplied.
  Production scheduling of retention, Flutter admission and
  cutover remain pending; POS-02.B supplies authenticated peer queue transport. Current status is NOT_DONE; current storage evidence:
  `docs/POS_PRINTER_PRODUCTION_INTEGRATION_REPORT_2026-10-09.md`.
  Historical architecture proof: `docs/POS_PRINTER_ARCHITECTURE_REPORT_2026-10-09.md`.
  The selected migration target retains Flutter rendering/business UI and uses
  one independent Go service per Windows host. Explicit LOCAL queues operate
  without shared quorum; VENUE_SHARED defaults to three full data-bearing voters,
  with additional hosts as clients. An inert Hashicorp Raft/Bolt/SQLite queue
  qualifies immutable majority admission, lost ACK, process SIGKILL/rejoin,
  logical assignment and interrupted primary/beep uncertainty on a frozen
  candidate. It cannot fence physical RAW output: the logical eligibility proof
  deliberately refuses physical dispatch, and paused-old-writer/buffered-byte
  counterexamples are retained. The native Go-owned helper passes actual
  Windows Job Object/parent-death tests and inventory/invalid-request checks on
  both amd64 and native ARM64; no valid print document is submitted. A runnable
  held agent, authenticated loopback API/Dart client, explicit developer status
  UI and installer/bundles now have isolated software qualification separately
  from the current updater. The final 1,109-file export passes 623 Flutter tests
  and 68-file analysis on macOS and Windows. Both shipped CLI architectures pass
  Windows foreground lifecycle/queue tests under the interactive user; the
  prepared POS amd64 Release build produces 23 pinned artifacts using cached SDKs.
  These tests do not qualify the future service principal or physical output.
  POS-02.A production provisioning is DONE: Device-authenticated, key-possession
  enrollment derives Venue from the server; audited Platform CAS configuration
  signs explicit station/controller and stable voter/client membership. Separate
  Go identities use Windows MachineGuid, current-principal DPAPI and protected
  storage with durable generation/revocation checks. Cached grants allow up to
  seven offline days; learned revocation is immediate locally, unknown revocation
  remains bounded by expiry. New POS joins as a client; controller eligibility is
  independent of queue leadership. Real isolated HTTP/PostgreSQL-to-Go and native
  Windows proofs: `docs/POS02_A_PROVISIONING.md`. Additive migration
  `20261018120000_printer_provisioning` is tested only on disposable databases.
  The candidate validator remains separate. No production credentials/service
  activation or live Flutter change is implied. POS-02.B now wires the same protected
  identities into real TCP/TLS peer RPC and Hashicorp Raft, with durable exact
  station receipts, explicit stable 1/3-voter membership, client-only sources and
  recoverable signed 1-to-3 expansion. Separate process/partition/crash and native
  Windows evidence is in `docs/POS02_B_PEER_TRANSPORT.md`. Physical dispatch remains
  HELD; production admission/cutover as a whole is NOT_DONE. POS-02.C
  Flutter/local Go admission and business routing is in progress. A detached
  Flutter station planner consumes Go's complete business-routing projection,
  freezes compatible per-station bytes and emits exact Go job identities/JSON.
  LOCAL ownership, precedence, fan-out and retry parity are tested; no normal
  business caller or production admission API is attached. Authenticated Flutter
  origin registration and durable submission remain next within C. Checkpoint:
  `docs/POS02_C_FLUTTER_ADMISSION.md`.
  Service-account/SCM/OS restart, printer
  models, downstream fencing, production writer cutover and physical acceptance
  remain pending. These new components do not replace production Hive or attach
  a production printer writer to startup. October 6 evidence and its exact
  18-case acceptance matrix: docs/POS_PRINTER_IMPLEMENTATION_REPORT_2026-10-06.md
  and docs/proofs/POS_SHARED_PRINT_GO_275688e1_2026-10-06/.
  The bound Cloud v2 reader controls every role and holds PREPARED, absent,
  disabled or unsupported routes without local fallback. Sync preserves a
  flushed last good configuration and refuses stale identity, downgrade and
  changed data at the same revision. Publication/rollback hold native, identity,
  local and updater admission; an unconfirmed restoration latches recovery
  failure. The Owner/Platform backend prepares v2 under Venue/Device/Owner locks,
  with CAS, immutable exact success/conflict receipts and transactional audit;
  legacy writes refuse v2 and readers require header version 2. Preparation
  never activates routes. Controlled compatibility/cutover proof remains required
  before Cloud Windows routes can be activated.
  Format-2 restore holds source queued work and validates rows before replacement;
  cross-protocol duplicate IDs are rejected before replacement. Hive
  remains v9. The generic printing design covers 1/2/3/4/10+ sources independently
  of operational multi-POS authority; see `docs/VYNIC_PRINT_ARCHITECTURE.md`.
  Historical evidence:
  docs/POS02_PRINT_DELIVERY.md and
  docs/POS02_ADMIN_REVISION.md. User-reported Windows native tests and basic ASCII
  printing/cutting concern the earlier frozen candidate; supported-model
  cable/paper/power/recovery acceptance remains pending.
  The sealed `db74149c` preparation-only one-shot runner adds a persistent locked
  per-window budget, reserve-before-render/connect/write, exact frozen-byte guards,
  zero physical allowance by default and no refunds/replay after failure/restart.
  macOS synthetic final-source acceptance passes 895 checks plus fake native-entry
  and four budget-ledger process-kill/restart checkpoints. On October 4, the
  authorized isolated Windows build of that sealed source was published as
  development POS 1.0.14 / release 15, prepared source `0bf6dd5b`, artifact
  `4534e35e`, using cached Flutter 3.44.2 and offline locked dependencies.
  The existing Windows 11 ARM Parallels VM at 10.10.10.9 was migrated to the
  signed 10.10.10.3 feed using the supported lab-network utility, then updated
  through normal POS Update Now consent. All 24 installed artifact files match;
  updater startup verification was SUCCESS and the app opened at PIN login for
  user testing at that checkpoint. The October 6 read-only inventory finds no
  running POS process and VM address 10.10.10.12. The data path, signing keys and
  Edge 1.0.1/bootstrap 3 are unchanged.
  All 23 original data files matched immediately after feed migration; active
  Hive locks prevent a full post-launch byte comparison. Seven Windows product
  suites pass 96 checks; the separate runner has 39 passes and one failure from
  mixed Windows path separators in owned-output validation, refusing before
  storage/transport. Its physical entry remains skipped, and the runner is not
  shipped in the product. The corrected October 6 launcher regression now passes;
  physical/driver gates and owner Receipt/paper policy still block DONE. No physical jobs,
  commits, tooling installs or security/trust changes occurred. Signed metadata
  expires October 11; the HTTPS server remains at `https://10.10.10.3:8443` with
  its publication watcher disabled. Evidence:
  `docs/proofs/POS02_WINDOWS_RECOVERY_2026-10-04/proof.json`; runbooks:
  `docs/POS02_ONE_SHOT_ACCEPTANCE.md`, `docs/POS02_WINDOWS_INSTALLER_HANDOFF.md`.
- MGR-01 is DONE from the POS's strictly validated
  saved configuration. Additive nullable Cloud Table metadata carries physical/
  virtual type, labels and ordering; an explicit complete membership claim retires
  stale/carrier rows without deleting occupancy. Legacy partial snapshots preserve
  metadata, unknown legacy rows stay visible, and cold full/empty snapshots retain
  occupied state. Actual aliases and UUID-linked retained Orders cannot drift through
  historical prefix/second-floor decoding. Dashboard/UI count physical rows equally
  and merged payable contributes once per Order. Manager JSON/cache carries metadata
  without a Hive v9 adapter change. Real HTTP/PG and compact/desktop repeated-route
  proof and compatibility policy: `docs/MGR01_GENERIC_TABLE_LAYOUT.md`. Clean-source
  receipt: `docs/proofs/MGR01_COMMITTED_a7c64c5_2026-10-07.json`.
- MGR-02 is DONE for exact operational source 4c4c5d9. Manager ghost-table repair
  uses one immutable, selected-primary
  `TABLE_REPAIR` pull command. Cloud leaves the mirror unchanged while queued;
  only an authenticated POS `table_repaired` ACK applies a snapshot comparison
  guard. POS refuses live Order/Reservation ownership, journals one durable
  repair/audit and recovers before writers or restored-data admission. Retained
  retries preserve later occupancy even after transport journal pruning. Manager
  persists request IDs by origin/principal and shows actual pending, failed,
  unavailable or completed delivery; changed sessions cannot send stale actions.
  No new frozen LAN callback exists. Clean-source synthetic qualification and
  rollback limits: `docs/MGR02_GUARDED_TABLE_REPAIR.md`. Exact committed receipt:
  `docs/proofs/MGR02_COMMITTED_4c4c5d9_2026-10-07.json`. Printer work is deferred
  at the user's request; POS-02 physical/driver acceptance remains pending.
  Broader Manager delivery and release gates remain separate.
- MGR-05 is DONE from `424fbadd206137dae0bd14d482f42d1102af632e` on a fresh
  exact-commit export. It adds guarded atomic Order editing through an immutable
  selected-primary
  `ORDER_EDIT` pull request. Queue acceptance never edits the Cloud mirror.
  POS journals complete Order/audit effects and retains exact results across
  interrupted writes, pruning and later edits; startup/public restore recover
  before writers. A validated POS ACK atomically replaces Cloud lines/total/bills
  under snapshot/revision guards. Stable lines, package/advance/adjustment values,
  comments and actual effective fee survive the lossless POS projection.
  Manager persists request IDs/drafts, fences changed sessions and old Cloud
  routes, and reports saved only after POS success. Unknown terminal outcomes
  require reconciliation. The runbook and synthetic qualification boundaries are
  `docs/MGR05_ATOMIC_ORDER_EDIT.md`; exact committed evidence is
  `docs/proofs/MGR05_COMMITTED_424fbad_2026-10-07.json`. Windows release gates remain separate; POS-02 printer/driver acceptance is
  deferred and VM work stays HELD.
- MGR-03 is DONE from `4c020120893cc8f360fe29e34c4e6237af8927bd` on a fresh
  exact-commit export. It retains delivery for seven Manager cancellation/creation/
  reservation paths. Staff/Venue-authorized immutable MANAGER_OPERATION commands
  are pulled by the selected active POS; admission and ACK leave Cloud mirrors
  unchanged until POS sync. Guarded Order work uses existing recoverable receipts;
  uncertain/interrupted reservation effects are retained for onsite reconciliation,
  never automatically replayed. Manager flushes scoped UUID/drafts before HTTP,
  restores pending forms, fences changed sessions and reports completion only on
  POS SUCCEEDED. Fresh identical creations allocate new identities after completion.
  The unsupported reservation Complete action is removed; seating/completion stays
  at the POS. Delivery/pruning/rollback policy and qualification:
  `docs/MGR03_OPERATION_DELIVERY.md`. Exact qualification: 416 Flutter tests,
  24 HTTP/PG cases, 55 backend tests and 21 selected SIGKILL checkpoints;
  `docs/proofs/MGR03_COMMITTED_4c02012_2026-10-07.json`. POS-02 remains deferred; VM stays HELD.
- MGR-04 is DONE from `4a46db340e9b29d0da95dd11ed75e6a379099e30` on a fresh
  exact-commit export. It implements scoped read freshness/completeness. Accepted
  Device/Venue snapshots atomically stamp only applied blocks and ledger dates;
  concurrent generations, changed primary and uncovered ledger ranges are unknown.
  Dashboard snapshotAt preserves POS source time. API availability, cache/read age,
  POS source age and completeness remain distinct; failed subrequests retain their
  original visible data or show unavailable instead of false zero/empty success.
  Query/account/origin cache envelopes are flushed together and session-fenced.
  Dashboard, Tables/Takeaway, Financials, Reservations, Counted Menus and Menu
  Calculator expose bound source/status details and refresh on resume. The POS
  mirror retries failed startup uploads and attests idle sources every two minutes;
  accepted snapshots clear only the local revision they captured. Dashboard product
  quantities use the existing date-scoped Sale ledger analytics. Financials binds
  summary, analytics and every Sale page to one business-date range, fences late
  refresh/session responses, and preserves per-page warning state. Access denials
  clear retained protected values; successful refresh retires abandoned read states
  without clearing another query's errors. Open days remain partial until Close Day;
  missing history remains explicit. Creator and closer analytics now use immutable
  CloudSale actor snapshots separately; recorded usernames are not stable Staff
  IDs and historical attribution is never inferred from today's staff directory.
  The legacy staff-performance/top-items adapters use the same ledger and scoped
  freshness as detailed analytics. Daily history preserves missing/corrupt indexed
  rows as unavailable, not zero. If a completed retained day has fewer Cloud rows
  than declared, the additive retry-date response resets only that day's local
  Sale ACKs; the existing bounded uploader replays the same genuine identities.
  Phase-one proof: `docs/proofs/MANAGER_SYNC_2026-10-17/README.md`; backend-first
  reporting/recovery proof: `docs/proofs/BACKEND_SHARED_REPORTING_2026-10-17/README.md`. Original runbook:
  `docs/MGR04_DATA_FRESHNESS.md`. Exact qualification passed 492 Flutter tests,
  88 backend cases and 44 actual HTTP/PG cases;
  `docs/proofs/MGR04_COMMITTED_4a46db3_2026-10-07.json`. Further analytics beyond the
  recorded Sale product/actor projections remain deferred. POS-02 is
  deferred and VM operations stay HELD.
- MGR-06 is DONE from `e9b5f0f45966bae091205506b78605b8f719d012`. A clean Git-tree export
  qualified before the conditional local commit; the actual committed archive
  then matched every tested Git blob. It adds one immutable linked full negative
  payroll-payment, obligation-payment or reserve correction. Current Manager
  Staff/Venue and existing feature guards apply to fresh and retained requests.
  Original effective dates net historical totals; server correction date and
  createdAt preserve chronology. Existing locks and atomic audits serialize writes;
  payment reversals restore original reserve consumption. Fresh reserve corrections
  conservatively refuse nonzero cycle consumption. Manager durably retains scoped
  frozen UUID/reason, validates and flushes Cloud receipts, resumes uncertain results
  after reversed history reopen and fences displayed sessions. Runbook:
  `docs/MGR06_FINANCIAL_CORRECTIONS.md`. Exact qualification: 569 Flutter cases
  (42 MGR-06), 104 backend cases, 27 actual HTTP/PG cases, nine static checks,
  preserved nine original records across eight tables after migration/PG restart,
  zero schema drift and Manager/POS macOS development builds. Proof:
  `docs/proofs/MGR06_COMMITTED_e9b5f0f_2026-10-07.json`. POS-02 remains deferred and
  Windows VM operations stay HELD; broader release gates remain separate.
- Every Order audit report opens with a typed creation event carrying
  `orderKind` (`WALK_IN`, `TAKEAWAY`, `PACKAGE`, `RESERVATION`), `tableRefs`,
  `source`, `actorId`, `actorName`, `businessDate`: `CREATE_WALKIN` for POS
  and Manager table Orders (and the carrier of a Package), `CREATE_TAKEAWAY`
  for POS and Manager Takeaway (report exists from creation, guest details in
  `details`), `ACTIVATE_RESERVATION` for a seated genuine booking
  (`reservationId`, `customerName`; `source=SYSTEM` at day-open), followed by
  `APPLY_PACKAGE` (package fields and lines) for a Package Order. Initial
  `ADD_ITEM` rows follow the creation event at the same instant and are ordered
  by the report's `sequence`, not by that instant. Moving items between open Orders writes
  `MOVE_ITEMS` on both reports (`direction`, `fromOrderId`, `toOrderId`,
  quantities still set so older readers degrade to add/remove). An Order
  emptied by transfer closes its report with a locked `TRANSFER_CLOSE`
  (`closeReason=EMPTIED_BY_TRANSFER`, `transferredToOrderId`) and still writes
  no Sale. The backend normalizer stores all of these as themselves; it must be
  deployed before a POS build that emits them. Manager `DELETE /mobile/takeaway-orders/:id` now queues a guarded
  retained cancellation without changing the Cloud row; authoritative POS sync
  subsequently projects its state.
- Close payment semantics are structured, not textual: `CLOSE` /
  `INTERNAL_CLOSE` stay the only closure types and `details.paymentMethod`,
  `paymentBreakdown`, `cashAmount`, `cardAmount`, `advanceApplied`,
  `collectedNow`, `isFiscal`, `closureId` are the truth; a close of a genuine
  linked booking also carries `details.reservationId`. Both audit UIs render
  payment chips (`Cash`, `Card — TBC`, `Cash 40.00 + TBC 60.00`, advance
  shown separately, provider derived from the method) through
  `CloseEventPresentation` and fall back to the historical `note` only when
  an event has no structured details. The Manager endpoint returns `details`.
- Reservations have their own append-only timeline written by the repository
  (`ReservationAuditAction`: `CREATE_RESERVATION`, `UPDATE_RESERVATION`,
  `CONFIRM_RESERVATION`, `CANCEL_RESERVATION`, `NO_SHOW_RESERVATION`,
  `COMPLETE_RESERVATION`, `DELETE_RESERVATION`) with `reservationId`,
  customer, date/time, `guestCount`, `tableRefs`, `previousStatus`,
  `newStatus`, `source` (`POS`, `MANAGER`, `WEBSITE`, `SYSTEM`), actor,
  `businessDate`, `reason`. Every POS, Admin, Manager, website-bridge, Close
  Day, activation, close, cancel, restore, delete path goes through it; a
  status already in force, an existing id, or an absent row writes nothing.
  Seating writes `UPDATE_RESERVATION` (to `in-progress`) beside the Order's
  `ACTIVATE_RESERVATION`; a delete writes the booking's last snapshot first.
  Legacy `reservation_cancelled` rows are read as `CANCEL_RESERVATION` and
  never written again. Future tentative holds use the distinct `hold` status,
  block whole-day availability and require confirmation before seating/kitchen
  work; they are not auto-activated or expired. Overdue holds remain visible.
  POS reservation advances flush a recoverable receipt intent, count collection
  on the original business day and transfer to the seated Order for one-time
  settlement. Startup and complete restore replay pending receipts. Fully prepaid
  closes require confirmation; excess advances and receipt reuse are refused.
  Cancellation preserves received funds and deletion is refused. Automatic
  refunds/forfeiture/transfer remain undecided. The additive Cloud mirror migration
  `20261024120000_pos_reservation_advances` is qualified on disposable databases
  only; `docs/POS_CHECKOUT_RESERVATIONS.md` records the exact source proof.
- Current stock is derived, never stored: `SUM(StockMovement.quantityDeltaBase)`
  per Stock Item, computed in PostgreSQL as `Decimal`. There is no editable
  balance column. Receiving quantities are `Decimal(18,3)`, GEL totals `Decimal(18,2)`,
  unit purchase cost `Decimal(18,4)`, effective base-unit cost `Decimal(18,6)`;
  every value crosses the wire as fixed-scale decimal text.
- StockMovement quantities are `Decimal(21,6)` so six-decimal recipe amounts
  are preserved without narrowing the previous integer range. Derived negative
  stock is allowed and explicitly shown as `NEGATIVE`, including without a
  minimum. Receiving quantity/cost scales remain unchanged.
- A posted Receiving is inventory history: it cannot be edited or deleted, and
  cancelling it adds reversal movements beside the originals rather than
  removing them. Posting and cancelling both take `SELECT ... FOR UPDATE` on the
  document, and two database rules make them idempotent under concurrency —
  `@@unique([receivingLineId, movementType])` and a unique
  `StockMovement.reversalOfMovementId`. A repeat returns `already_posted` /
  `already_cancelled` and writes nothing.
- Receiving unit conversion resolves base unit -> item-specific
  `StockItemPurchaseUnit` -> global mass/volume, then refuses. Count packaging
  (`box`, `pack`) is never globalised: one venue's box is 24 bottles of lemonade
  and 6 of wine, so the ratio belongs to the Stock Item.
- Stock Item unit edits, recipe saves and Receiving posting lock affected items
  in sorted Venue-scoped order. A base unit cannot change after any stock
  movement, even if its old recipe component has since been removed. A recipe
  portion that rounds below the six-decimal minimum is rejected; malformed
  consumption shapes fail explicitly before persistence.
- Recipe conversion is deliberately narrower than receiving conversion: base
  unit or the global mass/volume table only, then refuse. Item packaging is
  never a consumption unit — a box is how a venue buys lemonade, never how it
  serves it. `recipeUnitsFor` is the one authority and offers `g`/`kg` for mass,
  `ml`/`L` for volume and the base unit itself for a counted item.
- There is exactly one active consumption definition per Menu Item + variant,
  enforced by `@@unique([menuItemId, variantKey])` where
  `variantKey = variantId ?? ''`. PostgreSQL treats NULLs as distinct, so the
  non-null discriminator is what makes the rule a database rule. Identity is
  `MenuItem.id` / `MenuItemVariant.id`; names are display snapshots only.
- Each component stores `baseQuantityPerUnit` (`Decimal(18,6)`), already divided
  by the recipe yield, so a batch definition ("100 khinkali from 3.5 kg beef")
  and the per-sale-unit number can never disagree. Recipes carry no purchase
  cost: a definition is physical consumption, not procurement price. Editing,
  creating or disabling one writes no `StockMovement` and leaves current stock
  unchanged; close-time snapshots preserve its `revision` instead of joining
  today's recipe onto a past sale.
- Manager Inventory labels are Georgian (`კგ`, `გ`, `ლ`, `მლ`, `ცალი`,
  `ბოთლი`, `შეკვრა`, `ყუთი`; `მინიმალური მარაგი`, `როგორ ვითვლით?`) while
  storage and the wire keep the stable English enum codes, so no persisted value
  depends on language.
- Venue-wide accountability lives in the append-only `AuditEventLog`, which is
  now readable. Every row carries `entityType`/`entityId`
  (`STAFF`, `MENU_ITEM`, `MENU_CATEGORY`, `MENU_VARIANT`, `PACKAGE`, `EXPENSE`,
  `CLOSE_DAY`, `BACKUP`, `RESERVATION`, `ORDER`, `SALE`, `BUSINESS_DATE`,
  `SETTINGS`, `DEVELOPER`, `STOCK_ITEM`, `SUPPLIER`, `RECEIVING`, `RECIPE`),
  written by
  `GlobalAudit`
  and additive in Hive, on
  the wire and in Cloud. Rows written before those fields existed are never
  rewritten: both
  the backend (`audit-log-entity.ts`) and the POS
  (`global_audit_registry.dart`) derive the entity from the action name and the
  row's own details at read time, and an action outside the registry stays
  unclassified rather than being guessed at.
- Audited venue-wide actions: `STAFF_CREATED` / `STAFF_UPDATED` /
  `STAFF_ROLE_CHANGED` / `STAFF_PIN_CHANGED` / `STAFF_DELETED` (a PIN change
  records only that it happened — never a PIN value), `MENU_ITEM_*` and
  `MENU_CATEGORY_*` and `MENU_VARIANT_*` (a subcategory is a category node with
  `details.nodeKind=SUBCATEGORY`; price, availability and kitchen routing come
  through as `changes` field deltas, never a menu snapshot), `PACKAGE_CREATED` /
  `PACKAGE_UPDATED` / `PACKAGE_DELETED` (definitions only — applying one to an
  Order stays `APPLY_PACKAGE` on that Order's report), `EXPENSE_CREATED`,
  `RECEIVING_CREATED` / `RECEIVING_UPDATED` / `RECEIVING_POSTED` /
  `RECEIVING_CANCELLED` (document summary and status transition only —
  StockMovement is already ledger history and is never mirrored row by row),
  `RECIPE_CREATED` / `RECIPE_UPDATED` / `RECIPE_DISABLED` (Menu Item, variant,
  yield, component count and revision — a summary, never the card itself),
  `CLOSE_DAY_COMPLETED` / `CLOSE_DAY_BLOCKED`, and `BACKUP_RESTORED`. Each
  writer is a no-op when nothing moved, and a redelivered Manager command
  produces no second row. `BACKUP_RESTORED` is written after the payload is
  applied, because `clearExisting` empties the box it lives in.
- The Manager reads that feed at `GET /mobile/audit-log` (filters: date range,
  action, `entityType`, `entityId`, actor; keyset pagination by
  `createdAt desc, id desc`) with `GET /mobile/audit-log/facets` for the
  actions a Venue has actually recorded. Both are Staff -> Venue scoped; an
  entity filter also matches the actions that mean that entity, so history with
  no `entityType` is still found. The POS reads the same rows locally in the
  Admin "აქტივობა" section. A single Order's lifecycle is deliberately not in
  this feed — it has its own report.
- Both Admin audit screens render one Order's report chronologically: ordered
  by `sequence` ascending and numbered `sequence + 1`, so the creation event
  reads as step 1 and the close as the last step. The venue-wide feed stays
  newest-first.
- A Manager upsert that lands on an existing Order now diffs its items against
  storage and writes the same `ADD_ITEM` / `REDUCE_QTY` / `DELETE_ITEM` events a
  POS edit would, with `source=MANAGER`, through the one
  `AuditOrderDiffService`. A redelivered identical payload writes nothing.
- Every persisted POS Menu node has stable offline identity: category,
  subcategory and variant IDs are UUID v4 fields alongside `MenuItemDB.id`.
  Hive migration v8 runs `MenuRepository.ensureStableMenuIds` once for legacy
  rows; older backups run the same idempotent pass after restore. IDs are never
  minted while decoding. Renames, slug/size/price edits, Manager edits,
  restart, backup and repeated sync preserve them. New `MENU_CATEGORY_*`,
  `MENU_ITEM_*` and `MENU_VARIANT_*` audit rows use the stable ID as
  `entityId`; mutable paths and labels remain details. Historical audit is not
  rewritten.
- Cloud preserves POS identity beside its public row keys as
  `posMenuCategoryId`, `posMenuSubcategoryId`, `posMenuItemId`, and
  `posMenuVariantId`. Menu ingestion matches identity first, adopts only an
  unclaimed legacy row through its prior natural key, and updates only changed
  fields. Snapshots carrying `menuIdentityVersion >= 1` reconcile absent
  POS-owned variants/items/subcategories/categories in one child-first
  retirement transaction; Venue scoping and explicit non-null POS ownership protect
  foreign, website/custom, and unclaimed legacy content. Older snapshots never
  trigger retirement. Reappearance restores retained IDs in POS-authority mode.
  `MenuItem.id` remains the Cloud/public website key.
- `OrderItem` and `PackageItem` carry additive nullable `menuItemId` and
  `variantId` references. POS/Manager selection, Edge/LAN commands, reservation
  activation, Takeaway, Walk-In, package application, quick drafts, transfer,
  sync and backup preserve them. Manual and legacy lines remain null. Names,
  prices, quantities, comments and package contents remain frozen transaction
  snapshots and are never refreshed from the live Menu. Order item audit
  details carry the IDs when available. This makes future per-product
  SaleLine attribution ready without name inference.
- New Reservation ids are uuids. Two bookings taken in the same millisecond used
  to collide on a clock-derived id. Cloud-supplied ids are still used verbatim
  and historical numeric ids are untouched; nothing parses a reservation id.
- Money mutations on an open Order are mirrored into its visible report:
  `RECORD_ADVANCE` (`previousAmount`, `newAmount`, `receiptId`,
  `collectedOn`), `ADJUST_ORDER` (`field` `manualAdjustment` or `serviceFee`,
  `previousValue`, `newValue`, totals). A Sale void appends `VOID_SALE`
  (`saleId`, `closureId`, `grossAmount`, `reason`) to the closed, locked
  report without changing its status or lock; it is not `CANCEL_TABLE`. The
  log rows (`ADVANCE_RECORDED`, `ORDER_MANUAL_ADJUSTMENT_CHANGED`,
  `ORDER_SERVICE_FEE_CHANGED`, `SALE_CANCELLED`) are still written; they are no
  longer write-only duplicates but the Order-entity content of the venue-wide
  feed, which the per-Order report cannot serve. Cancellation stores `approvedById` /
  `approvedByName` beside the note.
- Restore-to-order keeps the original close and Sale as history, marks closure
  A reversed, clears the Order closure identity, and emits `RESTORE` in the same
  unlocked audit report; re-close creates closure B and appends a new `CLOSE`.
  The restored Sale retains its tender detail but is excluded by the existing
  revenue predicate. A consumed advance is put back on the open Order and is
  applied to closure B only.
- Table-based audit cleanup preserves non-terminal Orders even when their
  opening table snapshot is reused after a move. Editing can repair old synthetic
  cleanup locks only when no terminal audit event, Sale or closure intent exists;
  the repair is recorded in the audit trail.
- Restoring a table Order occupies its tables locally again. Takeaway restore
  has no physical-table dependency, Package fields remain on the existing
  Order, and a genuine linked Reservation moves from completed back to
  in-progress without changing its identity or Order link, then completes on
  re-close.
- Internal/non-fiscal close preserves operational gross and advance identity
  while recording `paymentMethod=non-fiscal`, zero cash/card, and
  `collectedNow=0`; the transaction boundary normalizes legacy caller input so
  it cannot masquerade as collected tender.
- Advances are receipts on the collection day and are applied at close; they do
  not reduce the sale's gross value.
- Gross sales and money collected are separate derived figures. POS X/Z/monthly
  totals continue to use the local Sale store and its one revenue predicate;
  open-table payable remains a separate operational metric.
- Each genuine retained local Sale now has a backup-stable `posSaleId` and
  monotonic lifecycle revision. Full (never realtime) manager snapshots upload
  at most 250 unacknowledged Sale revisions at a time and keep retrying until
  Cloud acknowledges them. Closing remains entirely local/offline: the ledger
  is an asynchronous mirror and an old backend can ignore the additive payload
  without losing the Sale.
- Sale Ledger wire normalization gives non-fiscal/cancelled lifecycle semantics
  precedence over stale retained `collectedNow` and `paymentBreakdown`: it sends
  zero collection and no payments, preserving operational gross and history
  without rewriting Hive. Cancelled wire rows are non-fiscal. Stored collection
  wins only for fiscal, non-cancelled Sales; restored fiscal snapshots retain
  tender while the revenue predicate excludes them. Cloud permits preserved
  non-fiscal advance context with no payment rows; fiscal advances still require
  an exactly matching advance part. Any non-fiscal payment row is rejected.
  Legacy fiscal `split` rows without stored collection derive their balance
  normally: `split` describes tender parts, not a no-collection lifecycle.
- `CloudSale`, `SaleLine`, and `SalePayment` are the durable Venue-scoped Cloud
  financial mirror. Ledger money is `Decimal(18,2)` and crosses the wire as
  fixed two-decimal strings. `(venueId,posSaleId)` is the primary idempotency
  key and `(venueId,closureId)` is the secondary audit/closure link. Frozen
  line names/prices stay transaction truth; nullable POS `menuItemId` and
  `variantId` provide attribution without live-Menu joins or name inference.
  Revision updates mutate only legitimate void/restore lifecycle state, never
  frozen financial snapshots or child rows.
- `SaleLedgerDay` records `COMPLETE`, `PARTIAL`, or
  `LEGACY_SUMMARY_ONLY` provenance and `MATCHED`, `MISMATCH`, `INCOMPLETE`, or
  `LEGACY_ONLY` reconciliation. Close Day plus a fully acknowledged retained
  Sale set is the completeness boundary; Cloud independently compares count
  and revenue before marking a day complete. Aggregate settings never create
  fake Sales. Manager ranges use complete ledger days, non-overlapping legacy
  daily fallback where only summaries exist, and an explicit warning for any
  partial range.
- Tenant-safe Manager endpoints provide exact financial summary, keyset Sale
  history/detail, stable-ID product aggregation, and honest closer attribution.
  Dashboard/Financials use ledger values when complete, preserve operational
  occupancy from its existing source, and surface stale/legacy/partial status.
  A disconnected Venue continues operating locally and Manager catches up on
  the next successful full sync.

## Platform / Admin State

- SaaS Phase 2 adds Inventory, Payroll, Financial Planning, Profitability,
  Manager Reservations and Advanced Audit to the existing entitlement engine.
  Manager consumes effective features; optional POS sections use cached catalog
  keys. Controller and route feature requirements intersect. Existing Manager
  plans/Vankisi retain all previously bundled modules at migration.
- VenueSubscription is separate from operational Venue status. New shells
  default to NO_PLAN. Dated TRIAL and paid ACTIVE periods grant plan access.
  New paid activations have stable UTC billing anchors and frozen agreement prices.
  Upgrades require trusted payment success; downgrades/cancellation wait until renewal.
  Unpaid timed renewals deny access as PAST_DUE; historical manual agreements retain
  their existing manually managed grace until explicitly migrated to billing terms. Expired/missing-end trials deny immediately and reconcile to SUSPENDED
  with one SYSTEM audit, on reads and a 60-second sweep. Only pre-migration
  missing-subscription Venues carry the server-owned legacy compatibility marker.
  Suspended/cancelled clients receive no effective module keys. POS critical/offline
  work, frozen inventory effects, enrolled Device sync and payment settlement stay
  independent. See `docs/COMMERCIAL_ACCESS_HARDENING.md`.
- Platform can create/reset/disable real Manager/Admin Staff with atomic audit,
  PIN-vault and durable Edge writes. Platform-managed rows resist stale POS sync;
  the Phase 2 POS handles revision ordering and retains disabled login identities.
  Upgrade POS before using these access actions. Platform user management supports
  SUPER_ADMIN and SUPPORT_READONLY with server-enforced read-only authority.
  See `docs/SAAS_PHASE2_CONTROL_PLANE.md` for policy, tests and deployment order.
- Initial Manager activation uses one POS enrollment code with explicit first
  Manager permission (default validity 30 minutes). Owner or Platform Admin can
  issue it only before any Manager history exists. Redemption binds setup to the
  enrolled Primary Device; POS asks for name/PIN without a second human code.
  Ordinary/additional codes remain unprivileged. Additional POS waits for the
  Primary registration or existing Staff delivery. Device authentication, current
  issuer authority, expiry and POS/Manager entitlements gate completion; an
  enrollment code alone or a Manager session cannot register. Legacy invitation
  routes remain compatible. Platform cannot bypass first POS
  registration by creating initial Staff. Completion, PIN
  uniqueness, vault, audit and Edge delivery commit under the Venue lock; an
  identical lost-response retry is idempotent. Activated Staff are platform-managed
  so stale POS snapshots cannot restore their credentials. Existing Manager access
  cannot be created/reset/disabled from the owner cabinet; Platform Admin retains
  recovery, while authenticated POS/Manager operational permissions are unchanged.
  POS ignores disabled identities when admitting PIN changes and fails closed on
  ambiguous active PINs. First-run restaurant details and touch/keyboard preference
  save before setup completion. Implementation and isolated tests do not establish
  deployment or repair an existing account conflict.

- Platform Admin can manage Organizations, Venues, plan assignment, feature
  overrides, WebsiteMode, domains, Devices, credentials, enrollment codes, and
  platform audit records. It can issue a fixed `NOOP` connection test.
- Device credentials and enrollment codes are one-time values; verifier hashes
  are never returned by normal reads.
- POS reconnect validates existing canonical Menu, baseline, pending commit,
  mutation journal and restored Venue binding before replacing credentials.
  Cross-Venue enrollment returns a conflict and preserves local identity/data;
  missing Venue IDs in enrollment responses are rejected. Startup checks this
  binding before operational recovery or seeding, with explicit recovery guidance
  for already-mismatched installations. Same-Venue rotation remains supported.
  Identity reload discards stale cached fields and redacts malformed-file errors;
  POS startup uses the validated identity without a second post-recovery reload.
  Synthetic unpaid Orders/Table ownership and pending Menu intent survive rejected
  foreign enrollment/startup. Proof: `local_venue_binding_test.dart`,
  `pos_startup_venue_test.dart` and `edge_device_credential_store_test.dart` under
  `apps/operations/test/unit/`; scope and qualification:
  `docs/POS_LOCAL_VENUE_STARTUP.md`. A real conflicting installation still needs
  original-Venue reconnect or an explicitly controlled data handoff.
- CustomerAccount owner access is separate from PlatformUser/Staff/WebsiteUser.
  Public `/request-access` collects an access request without creating account, tenant,
  session, plan or trial; the old signup POST is denied. Platform approval creates
  a safe Organization/Venue shell and owner invitation, with an explicit choice of
  NO_PLAN or a selected dated Trial in the same transaction. Acceptance grants OWNER
  membership and dashboard access, independently of product access. Invitation
  registration reuses the approved access request’s personal name; only manual
  invitations without a saved applicant name ask for it. Existing
  accounts use the same invited-email sign-in and membership flow. Owners can
  resume password setup after refresh through an expiring, host-only HttpOnly
  continuation that rechecks the original invitation. Lost-link requests are
  rate-limited, enumeration-safe Admin review requests; operators reissue manually
  with optional Google SMTP delivery after committed issuance/regeneration. Mail is
  disabled by default, fails closed on placeholders, reports SMTP acceptance separately
  from delivery, and retains explicit operator recovery without automatic message retries
  (see `docs/MAIL_SENDER.md`). Windows installer links now use audited,
  revocable 15-minute capabilities issued to Platform operators or current POS
  owners, with ownership/entitlement rechecks and a streaming private-asset proxy.
  There is no public installer landing/catalog: the release root is technical-only
  and generic `/download` redirects to the main site. Only issued per-grant links
  enter the backend fragment-to-cookie handshake. They are bearer capabilities,
  not recipient identity-bound links; forwarding grants temporary access while
  the issuer retains authority. Public binary distribution is withdrawn; delivery
  uses a repository-limited read credential configured on the backend. Platform can
  explicitly prepare a chosen TRIAL/ACTIVE plan during assisted onboarding or
  assign it later. Owners with current access cannot request a duplicate Trial.
  Operators control Trial dates, paid manual agreements, suspension/resume and
  immediate cancellation with reasons/audits. Owners can schedule and undo deferred
  changes; customer payment-success claims cannot activate access. CustomerAccount.organizationId is provenance
  only; live OrganizationMembership authorizes all owner operations.
- UX-01 is DONE: active Homepage `HomeContact` opens the existing `/request-access`
  flow with KA/EN copy and a keyboard-accessible link, replacing timeout-only fake
  success. Existing application/client/service policies remain unchanged; only a
  persisted pending request produces acceptance. Final proof: 186 frontend cases,
  7 new real HTTP/PG persistence cases, 16 commercial regressions, 851 backend
  aggregate passes and 375/768/1440 browser QA on synthetic loopback data.
  See `docs/UX01_REAL_DEMO_REQUEST.md`; no deployment is implied.
- Platform manages plan names/descriptions, prices/currency/period, retirement,
  included features and Website media quotas. Deliberate plan changes snapshot the
  agreed price; list-price edits and reselecting the same plan preserve agreements.
  Historical unknown agreed prices remain NULL. Request review and commercial
  mutations are audited; SUPPORT_READONLY cannot mutate.
- NO_PLAN owner dashboards expose identity, account settings, subscription and
  trial requests, plus locked Website/POS/Manager cards. Website/foundation,
  payment configuration, Manager credentials and POS setup are gated on the
  server. Internal Manager loginCode is hidden unless MANAGER_APP is effective.
  Platform Admin can disable an existing Manager after suspension.
- POS/Manager use fixed product entrypoints and isolated native build metadata.
  Manager supports Windows/macOS/Android/iOS; POS production is Windows only,
  with macOS debug development via `tool/dev.zsh` shortcuts. Those shortcuts
  stage a repository-shaped workspace so relative contract path dependencies
  resolve, and open the POS developer panel without a token through
  `VYNIC_DEVELOPER_UNLOCK`, which release and lab builds never pass. New builds
  use VYNIC_ENV/VYNIC_API_URL, ship no .env and read no shared POS sync key.
  Build helpers read only those two public keys from the source `.env`; its
  original bytes remain intact with a separate additions block. macOS developer
  shortcuts default to `http://api.vynic.localhost`, with explicit saved/shell
  overrides restricted to developer builds. Manager remembers its selected Venue
  per API origin; subsequent login asks only for PIN. New installations first
  redeem a Platform Admin-only, 30-minute one-use Manager linking code. It requires
  current issuer authority, MANAGER_APP access and an active Manager,
  grants no Staff authentication, and does not change PINs. Different installations
  cannot reuse it; same-installation retries are idempotent. Existing selections
  and sessions remain compatible; the owner cabinet directs users to support. See
  `docs/SINGLE_POS_ONBOARDING.md` for the current operator/user flow.
  Manager never initializes POS persistence/printing/ingest/sync.
  POS setup requires a name, offers optional restaurant details and persists
  touch/keyboard choice; it remains unfinished across restart/Staff delivery
  until saved. Missing identity/logo/menu never triggers Vankisi defaults.
- Device printer config is Cloud-authored, Device-authenticated pull and durable
  local cache. The owner portal configures printers without a developer token.
  Device names/features refresh every 10 seconds without restart; local menu
  changes refresh the open menu. NON_FISCAL_CLOSE requires an affirmative
  Device/Venue/installation/credential-bound runtime decision alongside enabled
  Staff permission at the close transaction. The verified device-only decision
  survives offline restart; unbound/missing configuration cannot grant it.
  Backups cannot replay it. Revocation applies on the next authenticated pull,
  independently of printer/profile state; no client time limit is imposed.
  Plan grants are removed and rejected by the API,
  resolver and database trigger; only explicit Venue overrides can enable it.
  First successful full sync records Device.firstSyncAt for onboarding readiness.
  See `docs/SAAS_BUILD_RUNTIME_ONBOARDING.md` for commands, rollout and limits.
- Venue profile shares restaurant name, optional branch name/address/phone/legal ID
  through authenticated Owner, Manager and Device routes. POS retains the profile
  offline, queues Venue-bound local edits, and refreshes idle identity UI on pull;
  an unrelated Venue backup cannot submit its pending profile. Existing local
  identity remains until a Cloud profile is explicitly configured. Logo/layout stay
  optional local receipt settings. Profile writes are atomically audited.
- NON_FISCAL_CLOSE also controls POS/Manager sales, report and dashboard
  presentation, including POS close-day non-fiscal summaries. Historical records,
  advances, cancellation evidence, audit and financial ledger rules remain intact.
  Manager uses explicit session features; customer API projections hide
  non-fiscal fields and filter Sale list/detail access. Open customer dialogs and
  reports react to revocation. Paid-sale labels do not assert fiscal receipt
  issuance. Financial profit excludes internal gross and includes selected-month
  expenses independently of feature presentation.
  New close snapshots preserve gross separately from advance/current collection;
  POS history never treats discounts or advance receipts as internal closures or
  adds an advance to an already-gross Sale. Beta proof and known unrelated test
  failures: `docs/NONFISCAL_ADVANCE_BETA.md`.
  Platform explains dependencies before changes without altering override precedence;
  profitability is described as current cost/valuation and Website as access to a
  separately configured site, not automatic SaaS site provisioning.
- Venue Policy is documented in `docs/VENUE_POLICY_PLAN.md` but not implemented.
  Current operational switches/settings remain local to the POS.
- Custom restaurant roles/permissions and a production SaaS billing provider do not exist.
  The provider-neutral subscription lifecycle, server quotes and audited manual
  confirmation boundary are implemented; restaurant BOG payments stay separate.
- Website W1 provides encrypted, versioned Venue BOG integrations, owner settings,
  Platform status inspection and independent ONLINE_PAYMENTS access.

## Website State

- Exact production host routing and onboarding are documented in
  `docs/DOMAIN_ROUTING_ONBOARDING.md`. Manually registered Admin domains start
  PENDING and require explicit activation; status reflects database admission,
  not DNS/TLS verification. Public restaurant document middleware returns branded
  404/unpublished/outage states without redirecting or disclosing tenant data;
  exact Vercel project aliases redirect public navigation to owned domains while
  authenticated SaaS preview entry stays on its configured origin. CUSTOM document
  admission checks Host-resolved renderer identity and ACTIVE binding.

- Public APIs resolve registered hostnames through `VenueDomain`; production
  fails closed for unknown or disabled hosts. Effective WEBSITE is required to
  claim/activate domains, edit/preview/publish content and serve SaaS or CUSTOM.
  Losing access stops serving immediately; names are reserved for 30 days from
  lifecycle reconciliation, then released with audit, including the Venue's
  assigned SaaS name, so another Venue can claim it. Reactivation during grace
  cancels retention; after release, republishing claims only an available address.
- WEBSITE entitlement (commercial right), WebsiteMode (operator-selected
  implementation) and hostname binding are separate. Every Platform path that
  assigns a WEBSITE plan with access (access-request Trial approval, lifecycle
  TRIAL/GRANT_ACTIVE, legacy status PUT with a plan, prepared customers) calls
  `provisionWebsite`, which requires an operator SAAS/CUSTOM choice unless one
  is already provisioned. Owners have no WebsiteMode write path. Customer
  projections expose a server `websiteState`: NOT_ENTITLED, SETUP_PENDING
  (entitled but no mode), SAAS or CUSTOM; the dashboard never re-derives it.
- `WebsiteUser` remains global; each `WebsiteReservation` is Venue-owned.
  SEC-02 ownership reads require both Host-derived Venue and authenticated
  `userId` in the database query. Unverified contact email never claims guest
  history; guest rows and existing user links remain intact. No guest claim
  lifecycle is implemented. Anonymous payment checks return only status, never
  the private reservation row. Status is DONE: 14 service/controller and 25 real
  PostgreSQL/HTTP cases pass, with SEC-01 and affected regressions passing.
  See `docs/SEC02_GUEST_BOOKING_OWNERSHIP.md`.
- WEB-02: migration is not publication consent. `20261010110000` (ordered
  before the shared-foundation migration; a no-op where that already ran)
  captures each Venue's pre-foundation draft/published hours, contact, map,
  socials and gallery; `20261012120000` restores the published values live and
  keeps a differing draft private in `VenuePublicInfoReview` (never read
  publicly; its images retained) until an explicit audited decision. Databases
  upgraded earlier are reported (PUBLISHED / DRAFT_ONLY / AMBIGUOUS) and decided
  through `apps/backend/scripts/web02-public-info.ts`, never guessed. Status is
  DONE with reproduction, upgrade, already-migrated and fresh-install PostgreSQL/
  HTTP proofs. See `docs/WEB02_SAFE_PUBLICATION_MIGRATION.md`.
- Payment callbacks derive Venue from the server-owned reservation.
- CUSTOM websites are bespoke frontends over the one backend
  (`docs/CUSTOM_WEBSITES.md`). `CustomWebsiteBinding` records the operator's
  frontend identity (`siteKey`, not tenant authority) and tracking status
  (none = NOT_CONFIGURED, SETUP_PENDING, READY, ACTIVE, ERROR); READY/ACTIVE
  require effective WEBSITE, CUSTOM, a site key and an ACTIVE domain. Platform
  `GET|PUT /platform/venues/:id/custom-website` and the Website-tab panel manage
  it with audit; owners see a read-only status/domain card and keep Menu,
  profile and payments. The panel also shows the primary ACTIVE domain, public
  URL and menu authority, and `POST .../custom-website/check` reports runtime
  availability (REACHABLE/UNREACHABLE, UNKNOWN until checked) on demand: only
  that server-owned domain, DNS-pinned, non-public addresses refused, no
  redirects, nothing stored. WEB-05 adds stable public Venue correlation,
  reviewed `expectedBuildId` metadata/audit and served HTML/manifest comparison;
  five evidence facts and local/public observation environment are distinct.
  Concurrent/stale replies cannot restore old verification. Source and local
  Docker candidates are qualified; production acceptance remains open.
  SETUP_PENDING/ERROR serving remains unchanged (operator tracking). See
  `docs/WEB05_BUILD_IDENTITY.md`. VenueDomain never carries a port; outside
  production a Venue's `.localhost` domain is checked at its local frontend,
  port from `CUSTOM_WEBSITE_LOCAL_FRONTENDS=<siteKey>=<port>,…` (no default;
  unmapped = NOT_CONFIGURED, ignored and absent in production; D029).
  Explicit isolated Docker HTTP mode instead uses registered `*.vynic.localhost`
  URLs and the fixed Host-preserving ingress, with no frontend port mapping;
  production public-address SSRF checks remain intact (`docs/DEPLOYMENT.md`).
  Vankisi runs at `http://vankisi.localhost:5174` behind a host-preserving
  Vite `/api` proxy. Menu authority never follows SAAS/CUSTOM (new Venues
  are canonical CLOUD; D030): Website provisioning without POS admits an empty
  Venue to the CLOUD catalog for either mode, and Platform flags a Website-only Venue
  left on POS authority (`needsCloudAuthority`) for repair. SAAS and CUSTOM
  share one Venue-level website foundation (`docs/WEBSITE_FOUNDATION.md`):
  hours, contact, socials and gallery live in `VenuePublicProfile` (live owner
  edits via `PUT .../website/public-info`, projected into the SAAS payload).
  Vankisi reads this Host-bound public contract through its guarded info provider:
  Footer/Contact, confirmed-payment contact email and the Atmosphere gallery
  teaser reflect live owner edits without redeploying. Loading/error/retry,
  fresh reads on route/focus and capability-off hiding are explicit; no static
  business-data fallback. Bespoke narrative/design assets remain frontend-owned.
  The informational binding check does not close WEB-05 deployment attestation
  or implement a global site-launch gate. See `docs/WEB07_SHARED_INFORMATION.md`.
  Shared capabilities (MENU, HOURS, RESERVATIONS, GALLERY,
  CUSTOMER_ACCOUNTS, ONLINE_PAYMENTS; events/banquets/ordering listed as not
  built) follow Features → per-Venue operator policy (`VenueWebsiteCapability`,
  default on, audited) → readiness, never the mode. `WebsiteCapabilityGuard`
  gates `/api/website/venue*`, `/api/menu`, `/api/tables*`,
  `/api/bog/create-order`, website sign-up/sign-in and `/api/user/reservations`
  for any launched site (published SAAS or CUSTOM); Platform shows a Website
  capabilities table and the Dashboard offers Hours/gallery/contacts by
  capability in either mode. Bookings take the account only from
  the session cookie, the anonymous booking map omits names/phones, and a
  website SUPER_ADMIN reads only its bound `adminVenueId`. Sites must be served
  behind a host-preserving same-origin `/api` proxy; CORS admits requests whose
  Origin equals their Host, a trusted forwarded host is the sole authority, and
  the development fallback applies only to anonymous local hosts. The existing Vankisi binding is backfilled
  ACTIVE without a site key; the operator records `vankisi-web` in Platform. W2
  extends VenueWebsiteConfig with private drafts, explicit audited publication,
  revision conflicts and a Host-authorized generic bootstrap; Platform still
  controls mode and WEBSITE entitlement, and Venue profile remains the public
  identity source. See `docs/WEBSITE_PHASE_W2.md` for the publication contract.
- W3 implements the generic SaaS website product: `apps/restaurant-web` with a
  `themeKey` registry and one production `classic` theme, bilingual ka/en, a
  website presentation layer over the operational menu, owner preview of the
  real frontend, and a sectioned Georgian owner dashboard at `/dashboard`
  (one path per section; `restaurant` is the profile). First-run setup
  confirms the restaurant name and displays the server-assigned SaaS address
  read-only; logo is optional for ACTIVE Website customers; everything else is optional in dedicated sections (profile,
  website, menu, photos, hours, payments, POS devices, managers, subscription,
  settings) sharing one website draft with a save bar. SaaS provisioning assigns
  a collision-safe address with spaces removed. Existing assigned addresses never
  follow display-name changes. Website hostname changes are Platform Admin-only:
  owners see their address and contact support; the old request POST returns 403
  and draft saves/publication cannot choose an address. Platform can register
  Vynic subdomains or external domains for SAAS/CUSTOM, including aliases, and
  rename a stable domain with expected-hostname concurrency protection and atomic
  audit. Renaming the assigned SAAS address moves draft/published mirrors and
  revisions together without publishing unsaved content, and closes previous
  pending requests. Assigned identities and disabled/retained names remain
  protected across Venues. Apex/api/admin/preview/www platform origins are
  protected. Existing historical requests remain reviewable. DNS/TLS and CUSTOM
  frontend routing remain operator deployment work. See `docs/WEBSITE_SAAS_HOSTNAMES.md`. The menu section is the
  canonical category/subcategory/item/size tree with separate website presentation;
  canonical (CLOUD) Venues author it in the dashboard with per-node revisions and
  conflict choices, alongside their POS terminals; legacy POS-authority Venues
  retain POS authoring. SEO and exact map pins use
  progressive disclosure; map visibility defaults on and follows the current
  Venue Profile address unless an exact link is supplied. The additive `showMap`
  flag preserves hidden-map intent without duplicating the address. Disabled
  ONLINE_PAYMENTS removes owner payment configuration. Content is schema
  version 2; stored rows are completed from defaults on read, so older published
  snapshots keep rendering. Public bootstrap/menu are `private, no-cache` with
  ETag revalidation, preview is `private, no-store` and `noindex`, and only a
  published public page is indexable. Media are HTTPS or deployment-managed
  `/media/...` references, never inline bytes. Only ACTIVE Website customers upload raster logos/main photos; NO_PLAN and
  TRIAL uploads are denied. Decoded WebP files have Venue ownership, purpose, byte
  counts and reference retention; Plan file/byte quotas include unattached uploads.
  Referenced older local files are adopted before uploads or during hourly cleanup.
  Unused and crash-orphan files are collected after 24 hours; referenced draft,
  published and menu media survive. Local storage uses an
  explicit persistent `WEBSITE_MEDIA_DIR` in production and the
  `/media/website-logos/` reverse-proxy route. Uploads do not save or publish
  content. Gallery/about photos remain reference-based; object storage, DNS,
  TLS and SSR remain deployment-specific. See `docs/WEBSITE_PHASE_W3.md` for the
  product boundary, local runbook and the four-Venue isolation proof.
- `MenuItemWebsitePresentation` (migration `20260926120000_website_menu_presentation`)
  decides whether and how an existing `MenuItem` appears publicly. No MenuItem is
  duplicated; MENU-06 retains this row on retirement and restricts physical item
  deletion while it exists. An absent row means visible under
  the operational name, and presentation writes are proved Venue-scoped. Core
  menu authority remains POS/Cloud. Custom-site deployment, DNS/TLS and health
  are manual; only operator-attested status exists.
- SEC-01 public booking creation now shares runtime intent validation and one
  server pricing boundary inside ReservationService. Both creation routes use
  Venue-owned enabled/visible catalog selections and bounded quantities, ignore
  client money, and persist/send the same GEL amount calculated in minor units
  (existing 10% service and 1 GEL minimum). Both require payment capability;
  Vankisi's variant-ID payload remains compatible. Status is DONE: 83 regressions,
  45 real disposable PostgreSQL/HTTP cases and 89 affected integration tests pass;
  migrations, compatibility builds/type checks and zero real bank calls are
  verified. All verification-owned databases were removed. See
  `docs/SEC01_TRUSTED_BOOKING_AMOUNT.md`; later payment/security issues remain open.
- BOG credentials and return origins are encrypted per Venue using the deployment
  PAYMENT_INTEGRATION_MASTER_KEY. New payments require ONLINE_PAYMENTS and an
  enabled integration; reservations retain the original encrypted revision. Browser
  creation/status uses Host authority; signed callbacks use stored payment identity
  and remain Cloud-side after disconnect or entitlement removal. Controlled legacy
  import is explicit, audited, idempotent and never runs in Prisma migrations.
  See `docs/WEBSITE_PHASE_W1.md` for rollout and disposable two-Venue proof.
- WEB-06 is DONE at the read-only readiness boundary: Website capabilities,
  merchant status and the CUSTOM operator view share `latestBogIntegrationStatus`,
  selecting safe metadata
  from the greatest Venue/BOG revision. Rotation no longer reads an older disabled
  row; disconnect remains unavailable, and reconnect/newer revisions restore
  readiness. Ten real HTTP/PostgreSQL cases plus W1 and Website regressions
  preserve tenant isolation, entitlement/policy gating and historical credentials.
  No payment creation/settlement rules, encrypted revisions or schema change.
  It makes no money/hold policy changes; WEB-01/04 qualification is recorded below.
  See `docs/WEB06_CURRENT_PAYMENT_READINESS.md`.
- WEB-03 is DONE at the delivery boundary: server-owned payment outcomes and
  immutable Website reservation CREATE/CANCEL intents commit together under
  Venue -> booking locks. Worker queue admission, POS link and receipt commit
  atomically; replicas/restarts retain one identity and snapshot. Scoped receipt
  guards prevent terminal revival or payload rewrite. Existing Edge leases,
  Primary fencing and Hive idempotency apply; cancellation waits for CREATE ACK.
  Non-bootstrap unenrolled Venues wait for enrollment; only the frozen bootstrap
  legacy outbox is admitted. Platform's read-only Website delivery panel shows
  queued/claimed/ACK/failed/attention/unknown, plus historical untracked creation;
  no historical replay, automatic repair/refund or new booking/payment policy.
  Final proof: 26 new PG/HTTP cases, 1005 distinct backend passes, 176 frontend
  passes and 28 existing POS/Hive convergence/journal passes. WEB-01/04 now
  qualify the source money/hold boundary; real provider/fleet acceptance remains. See
  `docs/WEB03_DURABLE_BOOKING_DELIVERY.md`.
- WEB-01/04 are qualified in source with approved whole-day occupancy, frozen
  ten-minute holds and BOG TTL, exact money snapshots, immutable sanitized receipt
  observations, pinned reconciliation and monotonic refunds. Partial refunds keep
  confirmed bookings; genuinely late/unproved expired payments require restaurant
  owner review with no automatic restore/refund. Signed timely proof survives a
  delayed callback or provider outage; reassigned occupancy is never stolen.
  Owner/Platform read-only review survives entitlement loss. Vankisi redirects
  verify the server outcome and preserve the cart unless CONFIRMED. New hold day
  identities drive review and POS payloads. 32 new PG/HTTP cases, 1007 distinct
  backend cases, 208 frontend and 6 SDK cases pass. 684 opt-in backend cases remain
  unrun; live bank/fleet and stale/offline POS reconciliation remain release gates.
  See `docs/WEB0104_BOOKING_HOLDS_PAYMENT_LEDGER.md` and D038.
- Future SaaS operational work follows Website -> Cloud -> durable Venue command
  -> Edge -> POS; payment callbacks do not move through Go Edge.

## Current Transport and Sync State

- POS -> Cloud snapshot ingestion remains Edge-initiated and is not gated by a
  commercial feature. Phase 0 admits only `Venue.activeOperationalDeviceId` for
  authoritative snapshots, audit and sale-consumption intents. HTTP writes and
  replacement serialize under one Venue lock/transaction; success broadcasts
  follow commit. The primary alone claims untargeted Edge work; secondaries may
  claim only their targeted NOOP diagnostics. No multi-POS coordination exists.
- One Venue + one POS works normally. Multiple enrolled Devices require the
  selected primary as sole operational authority. Migration selects only a sole
  ACTIVE historical Device; multiple historical Devices require operator choice.
  First enrollment selects the first Device transactionally, never on polling.
  Platform replacement is audited, preserves old identity, and holds uncertain
  attempted work for reconciliation. Customers can see primary/secondary roles.
- Legacy shared-key sync/callback fallback remains only for zero-Device Venues.
  Revoking all Devices does not restore that fallback. Local secondary Hive
  operation is not remotely disabled: stop the old POS and restore/verify the
  replacement before switching. This is Cloud containment, not replication.
- POS/Manager show transient connection-loss and recovery feedback, without
  persistent connection/sync badges. Routine sync/retries stay silent; developer
  connection diagnostics remain available.
- Inventory administrative configuration is Cloud-authoritative. An enrolled
  POS pulls a complete Device -> Venue catalog through
  `GET /edge/inventory/catalog` into one atomically replaced Hive value at
  startup, after enrollment, and periodically. Failure leaves the last good
  offline projection intact and never blocks POS startup. Catalog version 5 adds
  a read-only inspection excerpt; version 4
  adds food/beverage classification and supplier links and carries each item's derived `currentStock`, `stockStatus`
  (`NEGATIVE`/`LOW`/`OK`/`NO_MINIMUM`) and `purchaseUnits`. New POS clients request
  catalog v5 for Admin inspection and item-specific keg packaging; older
  clients receive v3-compatible purchase units with all active recipes. The POS keeps exact
  decimal text and Cloud's own low-stock verdict; it never recomputes a balance
  and never posts a Receiving. Receiving and StockMovement stay Cloud
  financial history. The POS backup carries only the catalog's cached inspection
  excerpt (20 movements per item, up to 100 current-business-day receipts and
  derived totals), never an authoritative history ledger. The catalog
  additionally carries the active Menu consumption definitions — both identities (`menuItemId`/`posMenuItemId`,
  `variantId`/`posMenuVariantId`), the recipe `revision` and each component's
  `baseQuantityPerUnit` — for close-time offline snapshots. The POS authors no
  recipe; it multiplies frozen six-decimal per-unit quantities by sold integers using fixed-point
  arithmetic. Recipes ride inside the existing `inventoryCatalog` backup value,
  so no second recipe authority appears, and a pre-Step-3 backup restores with an empty list corrected by the
  next Device pull.
- Reservations now sync into `PosReservation`; Manager and website reads no
  longer make a synchronous LAN call to the POS.
- Audit reports sync incrementally in batches using content revisions and
  acknowledgments. Legacy `fullSync` remains accepted for older POS builds.
- The order of a report's events is a zero-based `sequence` the POS assigns
  when it appends them, not a sort of `timestamp` — a creation event and the
  initial `ADD_ITEM` rows share one instant deliberately. Events are appended
  at the next free sequence and never re-sorted, so a backdated clock, a
  reopen, or a re-close extends the timeline instead of rewriting it.
  `sequence` is serialized in Hive, carried on the wire, and included in the
  revision hash; it survives backup/restore because the backup stores the
  report row verbatim. Backend ingestion writes it straight into
  `AuditEvent.seq` when every event in a report carries one, and falls back to
  array position for an older POS build. `AuditReport.fromMap` numbers a
  report written before sequences existed from its stored array order (stable
  by timestamp), deterministically, so its revision still settles; the numbers
  reach the wire immediately and reach Hive on the report's next write.
  Historical rows are not rewritten eagerly.
- Cloud `AuditEvent` carries a denormalized `venueId`, copied from the parent
  report — that is, from the authenticated Device or Staff — and never from the
  payload. It is not a relation: the report's own foreign key is the tenant
  authority. `AuditReport.orderKind` (`WALK_IN`, `TAKEAWAY`, `PACKAGE`,
  `RESERVATION`) is derived at ingestion from the report's own creation event
  and is null when no creation event proves one; `floor` is never used as
  evidence. Both are query metadata; the events remain the semantics.
- `AuditReport` still has no foreign key to `Order`, deliberately: Close Day
  deletes the operational Order row and the report, its events and their
  sequences have to outlive it.
- Audit report deserialization resolves missing times from the record itself,
  never from the clock, and reports are listed once per id. Both are required
  for a revision to settle; without them a report is dirty on every sync.
- Backups carry the audit box's keys (`auditLogKeys`, additive) and restore
  files each row under its canonical key, so a repeated restore updates rows
  instead of duplicating them. Keyless older backups still restore.
- Tables, orders, staff, `salesHistoryByDate` and the legacy-Venue menu still use
  broad snapshot payloads; canonical Venues sync the Menu by entity mutations and
  change sequence instead. Further sync windowing/scaling is deferred.
- The home takeaway panel is Order-backed. `TakeawayTickets.forBusinessDate`
  builds the queue from takeaway orders (`isTakeawayOrder`, the one definition
  of the floor/`TA-` rule), and list, counts, items, totals, status and actions
  all come from `Order`. A takeaway order with no reservation row renders
  completely, including guest name, phone and pickup time when supplied. Those
  three are additive Hive fields on `Order`; local, mobile, remote and Edge
  Takeaway creation/upsert paths populate the values they carry. A legacy
  Reservation lookup remains only as a display fallback when an old Order's
  new fields are empty.
- Routine Order sync sends Takeaway guest/pickup metadata directly from
  `Order`; it does not join the bookkeeping Reservation. Close Day likewise
  derives pending Takeaways from the centralized Order-backed source, excluding
  completed, cancelled, Walk-In and Package Orders.
- New Takeaway Orders no longer create Reservation bookkeeping rows; local,
  mobile, remote and Edge paths are Order-only. Historical `isTakeAway` rows
  remain supported and backup/restore preserves them unchanged.
- New Walk-In and Package Orders likewise no longer create Reservation
  bookkeeping rows. Walk-In remains Order + Table, Package remains package data
  applied to an Order, and only genuine advance-booking flows create new
  Reservation records. Real Reservation activation creates the operational
  Order while preserving and linking the existing booking.
- Reservations are only status-transitioned, never purged, so local reservation
  storage stays deliberately mixed: bookings alongside Walk-In, Package and
  historical Takeaway bookkeeping rows. Nothing rewrites old history, and
  backup/restore preserves all of it verbatim.
- Home refreshes counts, table state and Order-backed cards immediately from
  completed local POS mutations. Close publishes an Order lifecycle event only
  after the local transaction completes; this UI refresh is independent of
  Cloud acknowledgement and the periodic sync scheduler.
- Cloud `PosReservation` is real-advance-bookings-only. The POS projects its box
  through `ReservationClassification.projectForCloud` when it builds a full
  snapshot, and the mirror's existing "the list is the authoritative set"
  contract reconciles previously mirrored bookkeeping rows away. The canonical
  rule is `isTakeAway` or a `notes` prefix of `Order #`; `linkedOrderId` is
  deliberately not part of it, because an activated booking is still a booking
  and close-day nulls that field on past rows. An unclassifiable legacy shape is
  sent, not dropped. Each full snapshot logs a `[ReservationProjection]` count
  line carrying no reservation content.
- The narrower three-clause predicates that do consult `linkedOrderId`
  (`isRealTableBooking`, `isRealPosTableBooking`, the Manager `getReservations`
  filter) answer "is this an un-activated table booking" and are unchanged;
  Cloud consumers now receive an already-clean mirror.
- `ReservationSyncService` still issues one `posReservation.upsert` per record
  sequentially plus one reconciling `deleteMany`, so its cost tracks the number
  of rows sent. Measured before the projection at Vankisi: 2004 records,
  617-685ms, under 10ms of which is enumeration and mapping. `preOrderItems`
  stays on the wire unread by the backend; the POS needs it because the home
  takeaway panel renders and totals from those rows.
- `salesHistoryByDate` and `MenuSyncService` have the same shape: one
  sequential upsert per business day and per menu node.
- A POS edit only marks pending. The single automatic push is a 30-second
  periodic flush, and it sends the full snapshot rather than the realtime fast
  path, so an ordinary edit waits 0-30s and then re-sends menu and history.
- The realtime path is built but unreached: `syncRealtimeToManagerApp()` has no
  caller in `apps/operations`, and the `...Debounced()` helpers that edits do
  call are deliberate no-ops that only mark pending ("manual-first mode"). The
  backend already honours `realtimeOnly`, skipping menu, staff, reservations,
  all-time and per-day history.
- A routine snapshot carries staff identity and role but no PINs. The POS sends
  `pin` only for a member whose credential the backend has not acknowledged, and
  records the acknowledgment in `staff_credential_sync_state`; a server that
  reports `staffNeedingPin` gets those PINs back on the next snapshot. Ingest
  additionally skips bcrypt for a supplied PIN that already matches the vault
  entry of an existing member, so an older POS that still sends every PIN costs
  no re-hashing either. Only a genuine create or PIN change runs bcrypt now.
- Both POS and backend print one `[SyncTiming]` line per sync, from monotonic
  timers, splitting trigger wait / build / encode / network / ingest / audit.

- The Order statuses this system writes are `pending`, `confirmed`, `closed`
  and `cancelled`. `preparing`, `served` and `paid` have no writer and are
  read-only: they stay parseable because historical rows carry them.
- `ORDER_STATUS_UPDATE` no longer forwards arbitrary strings. One rule,
  `RemoteOrderStatusRule` in `core/models/order_status.dart`, decides every
  remote request before anything is written, and both transports share it:
  only `confirmed` and `cancelled` are remotely assignable, `cancelled` is
  delegated to `CancelOrderTransaction` rather than assigned, `closed`/`paid`
  and the legacy `preparing`/`served` are refused (400), a closed or cancelled
  Order is not reopened by a status string (409), a request the Order already
  satisfies is a no-op success, and an unrecognized value is refused and never
  persisted or mapped onto a business state. `OrderRepository.updateOrderStatus`
  refuses an unparseable status outright and stores the canonical spelling, so
  no unreadable status reaches Hive from any caller.

## Local Docker Database Maintenance

- `scripts/docker.sh studio` exposes Prisma Studio only on `127.0.0.1:5555`
  through the local `tools` profile. Production Compose has no Studio service.
- `reset-customer-data --dry-run|--confirm-local` uses an audited deletion matrix
  and preserves Platform users, catalogs, onboarding/release settings and migrations.
  Local-only Platform Venue/Organization deletion requires typed confirmation;
  shared accounts and other Venues survive. Scoped deletes retain WebsiteUser
  identities; full customer reset removes them. Media cleanup uses retryable
  manifests in the retained volume. Guards require the isolated Docker DB.
  Implementation and proof boundaries: `docs/LOCAL_DATABASE_TOOLS.md`.

## Known Blockers

- Website holds serialize Cloud website bookings. Independent/offline POS and
  stale mirror conflicts still require delivery evidence and operator review;
  real bank/fleet acceptance remains a release gate.
- Local POS diagnostics/error-log/restore-wipe remain developer-gated. Customer
  printer setup is available through the owner portal; physical remote test-print
  and real Windows coexistence/hardware validation remain release checks.
- Production provider deployment (DNS/TLS issuance, registry publication, managed
  database, backups and host qualification) remains unprovisioned. The local
  production-like Compose/image foundation is implemented; see `docs/DEPLOYMENT.md`.
- POS/Manager native traffic uses a dedicated origin, `api.<base domain>`
  (`http://api.vynic.localhost`, `https://api.vynic.ge`), routed by Traefik only for
  `/edge/`, `/mobile/`, `/auth/`, `/sync/`, `/socket.io/`, `/healthz`; every other
  path there is a backend 404. `./scripts/docker.sh start-lan` opts into a
  `<MAC_LAN_IP>:8088` listener (native paths only, one bound private IP) for
  Windows/Parallels. Venue never comes from Host on these routes. POS Development
  API URL: explicit `http://host` with no port means port 80; bare `host` stays `:3000`.
  See `docs/DEPLOYMENT.md` "Native POS / Manager ingress".
- Full legacy callback retirement depends on real fleet enrollment, not merely
  the existence of enrollment code.

## Release Supply Chain

- OPS-03 compatible dependency and lock-graph fixes are integrated but not deployed
  across six npm projects. Offline inventory uses the existing npm Arborist reader
  and CycloneDX emitter with node flags that retain shared runtime/dev dependencies;
  required WASM lock closures are complete. All 12 build/runtime SBOMs qualify,
  with 19 Python and 4 Node regression cases. The final OSV snapshot queried 1,733
  public package/version pairs and matched 5 pairs / 11 IDs (initially 41 / 107),
  with no critical IDs in that bounded scope; presence is not exploit reachability.
  Private clean installs/builds passed, with 987 distinct backend cases, 284 web
  cases and 7 website-manifest cases; 814 other opt-in backend cases remain unrun.
  Intentional Prisma pins, unrelated fflate 0.8.3, source WIP, environment and
  printers are preserved. Deepmerge major and Vankisi Sharp minor-boundary decisions,
  unfixed build/test dependencies, Go graph/stdlib/call paths, image/OS layers,
  SDK/native and candidate provenance remain release gates. No residual risk was
  accepted. See `docs/OPS03_DEPENDENCY_REMEDIATION.md`; the initial container capture
  remains historical inventory evidence, not installed-image attestation.

## Deferred Work

- General Restaurant Backoffice, Venue Policy, custom roles/RBAC, Inventory
  historical Sale COGS / realized Gross Profit / Waste / Stocktake / inventory variance / expected
  yield and pour loss, cash management,
  hourly reservation slots and automatic SaaS billing/provider checkout. SaaS website ordering, SaaS online
  payments, generic customer accounts, additional themes, a page builder and
  custom-domain DNS/TLS automation remain deferred; the read-only generic SaaS
  website itself is implemented (W3).
- Physical printer-test command, lower-latency Edge long polling, OS
  keychain credential storage and production Venue-local multi-POS authority
  (Phase 2A is shadow/isolated proof only).
- Legacy shared sync key/callback removal after rollout evidence permits it.

## Current Migration Versions

- Prisma migration source tip: `20261023230000_pending_website_domains`
  (additive PENDING VenueDomainStatus; historical rows and defaults unchanged).
- Previous migration: `20261023120000_manager_venue_link`
  (additive ManagerVenueLink, Venue/Platform issuer foreign keys, verifier-only
  storage). Fresh 77 and populated 76→77 upgrades preserve existing Venue/Device/
  Staff/PIN/activation data and all 76 migration checksums; repeat deploy is a no-op.
  Source qualification does not prove live deployment.
- Previous migration: `20261022120000_single_pos_manager_setup`
  (ordinary enrollment defaults false; nullable Manager setup enrollment/Device
  links have composite Venue foreign keys). Fresh 76 and populated 75→76
  synthetic upgrades preserve existing values and all 75 historical migration
  checksums; repeat deployment is a no-op. This does not prove live deployment.
- Previous migration: `20261021120000_custom_website_build_identity`
  (nullable reviewed public build fingerprint; legacy values/statuses unchanged).
  Fresh 75 and populated 74→75 synthetic upgrades preserve history; all 74
  historical migration checksums and Prisma validation pass. Source presence
  does not prove deployment. Previous website holds/ledger proof retains two
  pre-existing printer runtime FK-name differences in its full-schema diff.
- Previous migration: `20261020120000_website_payment_holds_ledger`
  (additive money observations/whole-day occupancy; old rows remain UNTRACKED).
- Previous migrations: `20261014120000_menu06_safe_retirement`,
  `20261013120000_menu03_exact_mutation_result`,
  `20261012120000_web02_restore_public_info_authority`.
- Previous migrations: `20261011120000_canonical_menu_sync`,
  `20261010120000_shared_website_foundation`, and WEB-02's evidence capture
  `20261010110000_web02_capture_public_info_evidence`, ordered before the
  foundation (applied late, as a no-op, where the foundation already ran).
- Previous website migration: `20261009120000_custom_website_binding`.
- Previous hostname migrations: `20261008120000_hostname_request_fk_on_update`,
  `20261007120000_release_published_slug_reservation`,
  `20261006120000_hostname_request_current`,
  `20261005120000_website_hostname_requests`.
- Previous lifecycle migration: `20261004120000_subscription_lifecycle`.
- Previous acquisition migration: `20261003120200_customer_trial_requests`.
- Commercial access/media/pricing: `20261003120000_commercial_access_hardening`,
  `20261003120100_no_plan_default`.
- Preserved preceding migrations: `20261002120000_remove_non_fiscal_close_from_plans`,
  `20261001120000_payment_integration_fk_on_update_cascade`,
  `20260930120000_cloud_menu_editing`.
- Prior product migration: `20260929120000_website_only_plan`.
- Prior catalog migration: `20260928120000_restaurant_foundation`.
- Prior website migrations:
  `20260925120000_website_core`, `20260926120000_website_menu_presentation`.
- Immediately preceding state migrations:
  `20260924120000_venue_payment_integrations`,
  `20260923120000_edge_foundation`,
  `20260922120000_operational_primary`,
  `20260921120000_venue_profile`,
  `20260920120000_non_fiscal_close_feature`,
  `20260919120000_customer_onboarding_runtime`,
  `20260918120000_saas_phase2_control_plane`,
  `20260917120000_receiving_self_purchase`,
  `20260916123000_procurement_request_identity`,
  `20260916120000_inventory_procurement`,
  `20260915120000_manager_login_code`,
  `20260914120000_payroll_day_adjustments`,
  `20260913120000_payroll_obligations`,
  `20260912120000_inventory_step45_catalog_cost`,
  `20260911120000_inventory_step4_sale_consumption`,
  `20260910120000_inventory_step3_menu_consumption`,
  `20260909120000_inventory_step2_receiving`,
  `20260908120000_inventory_step1_core`,
  `20260907120000_cloud_sale_ledger`,
  `20260906140000_complete_menu_identity`,
  `20260906120000_menu_item_pos_identity`,
  `20260905140000_audit_event_log_entity`,
  `20260905090000_audit_event_sequence_tenancy`,
  `20260904120000_audit_closure_semantics`,
  `20260903140000_pos_reservation_mirror`, and
  `20260903120000_audit_report_sync_revision`.
- Flutter Hive database target version: `9` in
  `apps/operations/lib/core/database/hive_migration_service.dart`.
- A migration file in the repository does not prove deployment to any database.

## Important Recent Commits

- `1526db6` — wire the shared POS command module into backend consumers.
- `41cb9af` — remove unused callback operations and freeze the remaining fallback.
- `4c841bd` — complete Step 6C real-command migration and reservation mirror.
- `d3cc1a7` — add acknowledged, incremental audit-report sync.
- `89a38b9` / `f2f25e3` — add POS enrollment UI/client and backend redemption.
- `79ad18f` / `879084a` — implement atomic close/money integrity and Cloud fields.

## Maintenance

- Update this file only when a represented current fact changes. Replace stale
  facts; do not append session notes, dates, or a task history.
- Keep it compact. New detail belongs in task docs or the canonical engineering
  protocol, not here.
