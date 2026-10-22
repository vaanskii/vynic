# SEC-02 — Guest booking ownership

**Status: DONE.** Closed 2026-09-30 Asia/Tbilisi (2026-09-29 UTC).
The original disclosure was reproduced on real PostgreSQL/Nest HTTP before the
fix. The final run passes 14 service/controller tests and 25 PostgreSQL/HTTP
tests with zero skips. SEC-01 remains DONE. This closes only SEC-02, not a
website/payment release gate.

## Baseline and scope

- Branch: `codex/docker-deployment-foundation`.
- Starting HEAD: `a4036379931387e5a36bdcf03e297e0893558ee8`.
- SEC-02 implementation/tests commit: `038ece4e8e216098175dac9d7a17d306a251c8c1`.
  Proof documentation follows in a separate focused commit; no push.
- SEC-01 implementation: `cb283d9e483a2d757d845faccd2519987a0051bd`;
  proof documentation: `a4036379931387e5a36bdcf03e297e0893558ee8`.
  Current evidence: [SEC01_TRUSTED_BOOKING_AMOUNT.md](SEC01_TRUSTED_BOOKING_AMOUNT.md)
  and [SEC01 proof](proofs/SEC01_2026-09-29.json).
- Initial worktree: 30 modified tracked files, two owner untracked files and
  the untracked historical audit directory. Native ingress/deployment,
  commercial/subscription, provisioning and frontend WIP are user-owned.
  A private baseline records 1,958 file hashes and the exact initial status.
- Auth and user-read files had no changes between audit HEAD `f7bb982` and
  this baseline. The email ownership defect remained. SEC-01 changed/proved
  authenticated identity at booking creation; that existing secure binding is
  reused. No partial guest claim or email verification lifecycle was found.
- Verification uses the current HEAD **plus recorded WIP** in an isolated source
  copy. Existing installed dependencies were copied; no owner `.env` or `.git`
  was copied. The focused commits do not incorporate unrelated WIP.

The requested milestone follows the historical [Master Plan, milestone 2](audits/2026-09-29-f7bb982/VYNIC_MASTER_STABILIZATION_AND_RELEASE_PLAN_2026-09-29.md#milestone-2--sec-02-guest-booking-ownership).
The SEC-02 sections of MASTER_BACKLOG, IMPLEMENTATION_ROADMAP,
WEB_COMMERCIAL_SECURITY, SECURITY_AND_RELIABILITY, SYSTEM_AND_ARCHITECTURE and
EVIDENCE_AND_MATRICES were checked. Historical audit documents are unchanged.

## Previous call graph and persistence

```text
Host -> WebsiteTenantGuard -> WebsiteTenantService.resolveRequest
     -> VenueDomain.hostname/status -> active Venue -> TenantContext

POST /api/auth/signup
  Website/launch/CUSTOMER_ACCOUNTS guards -> CSRF -> WebsiteAuthController
  -> WebsiteAuthService.signup -> WebsiteUser.create
     [global ID; normalized unique email; unique phone; hashed password]
  -> signToken/updateRefreshToken -> encrypted access/refresh cookies
  [no email-control verification, no reservation writes]

POST /api/auth/signin
  same guards/CSRF -> email-or-phone lookup -> password verification
  -> same token/cookie mechanism

POST /api/tables/reservations OR /api/bog/create-order
  Host + Website/launch/RESERVATIONS/ONLINE_PAYMENTS guards
  -> TableController OR BogController
  -> WebsiteAuthService.tryGetUserFromRequest
     -> decrypt cookie -> verify signed JWT -> reread WebsiteUser by sub
  -> ReservationService.createReservation(tenant, body, authenticatedUserId)
  -> bookingIntent discards body userId/venueId/money
  -> Venue table/availability checks + SEC-01 trusted pricing
  -> WebsiteReservation.create [venueId from Host, userId from session or NULL]
     + WebsiteReservationTable -> Venue-owned WebsiteTable
     + Venue-owned PaymentIntegration revision / fake-provider order in proof

GET /api/user/reservations (previous)
  WebsiteAuthGuard -> encrypted cookie/JWT/live user -> request.user.id
  + Host/Website/launch/CUSTOMER_ACCOUNTS guards
  -> UserController.getUserReservations(tenant, request.user.id)
  -> UserService: load account email
  -> query Venue's CONFIRMED/COMPLETED rows where userId matches OR
     [userId NULL and customerEmail non-null]
  -> in-memory filter: userId matches OR raw customerEmail == account.email
  -> menu enrichment + customer response with private fields
```

`WebsiteUser` is global. `WebsiteReservation.venueId` is a required Venue foreign
key and `userId` is an optional WebsiteUser foreign key. A guest has `userId=NULL`
and optional contact text; its UUID identifies a row, not its owner. Historical
email association happened **at read time**, with no persisted ownership change.
Consequently signup with an unused victim email immediately exposed matching
guest rows, including name, email, phone, notes, preorder, date, tables and amount.

Searches covered all production `websiteReservation` access, `customerEmail`
references, website controllers, auth/user services, related scripts and frontend
callers. This user-read method was the only raw-email booking ownership path.
WebsiteUser has no verified-email/claim token infrastructure. Owner invitation
verification belongs to the separate CustomerAccount principal and cannot grant
WebsiteUser booking ownership.

## New ownership contract and response audit

`GET /api/user/reservations` now applies **both `venueId` and authenticated
`userId` in the database query**, before enrichment/serialization. It no longer
loads guest rows or uses email as an ownership condition. The unused full
WebsiteUser relation is no longer loaded. The existing CONFIRMED/COMPLETED status
filter and legitimate customer's response fields remain unchanged.

An additional in-scope disclosure was found during the required response audit:
both anonymous payment-status routes returned the entire updated reservation.
The public map exposes reservation IDs, so treating those IDs as private-row
authority would leave guest data reachable after removing the email shortcut.
The controller now returns only its existing `success/status` envelope; it never
serializes the private reservation row. Provider identity, Venue checks, payment
reconciliation and callback behavior are unchanged. This is separate from, and
does not substitute for, the ownership predicate on customer reservation reads.

| Customer-facing response | Authority and final projection |
| --- | --- |
| `POST /api/tables/reservations` | Returns the newly created request's booking/contact/cart; no historical read. Host and session determine persisted ownership. |
| `POST /api/bog/create-order` | New booking ID, redirect and trusted cart validation; no historical private row. |
| `GET /api/user/reservations` | Host Venue **and** live session WebsiteUser ID; only owned confirmed/completed rows, with contact/preorder details. |
| `GET /api/tables/reservations?date=...` | Existing public occupancy projection for anonymous/ordinary users. Name/phone remain null; email/notes/preorder/payment references absent. |
| Same map route with restaurant admin | Live `SUPER_ADMIN` **and** `adminVenueId === Host Venue`; existing admin name/phone projection. Wrong-Venue/unbound admin gets only public occupancy. |
| Table list / availability routes | Venue-scoped tables and occupancy, no customer contact/preorder/payment detail. |
| `GET /api/bog/check-status/:orderId` | Stored payment ID + Host Venue -> provider receipt identity -> existing reconciliation -> only `success/status`. Foreign Venue returns 404 before provider call. |
| `GET /api/bog/check-reservation-status/:reservationId` | Reservation lookup constrained by Host Venue -> same status-only path. Foreign/missing row retains `{success:false,message:...}`; no payment lookup or private data. |
| Signed bank callback | Stored payment/reservation identity and signature; acknowledgement contains outcome, not private booking data. |

The restaurant administration path remains
`TableController.getReservationsForDate -> authenticated adminVenueId check ->
ReservationService.getReservationsForDate(tenant,date) -> Venue-scoped query`.
Manager reads use Staff-derived Venue and `PosReservationMirrorService`; there is
no email-based ownership there. CustomerAccount and PlatformUser principals are
unchanged and gain no website booking rights.

## Historical data, claims and compatibility

- **No claim flow was implemented.** No fake verified flag, token, automatic
  backfill, ownership transfer, account linking or new administrative right.
- Historical guest bookings remain stored and operational. Signup/signin with
  matching email intentionally no longer makes them appear in “my reservations.”
  Restaurant-authorized lookup remains available.
- Already user-bound bookings remain accessible to that user on the owning
  Venue's Host, even when the contact email differs from the account email.
- A global user may own bookings at both Venues; each Host lists only its own.
- No schema or migration change is required. No historical records are rewritten.
  There are no claim events/tokens to audit. Existing creation retains user ID,
  Venue ID and creation time; reads do not change ownership or log secrets.
- Owner decision still needed: whether/how to offer historical guest claiming.
  Any future flow needs explicit booking/Venue scope, real proof, expiry,
  one-time/replay/concurrency protection, revocation and audit. Raw email matching
  must not return as a fallback. Claim-specific acceptance K–Q is not applicable
  to this fail-closed implementation, as permitted by the current task.

Vankisi remains standalone. Its `services/api.ts -> /user/reservations` caller
uses the same list shape. `PaymentSuccess.tsx` reads `success/status`, not the
removed private `reservation` object. `packages/website-client` exposes
`myReservations()` and a `PaymentStatus` type already containing only
success/status/message. Generic `restaurant-web` remains a read-only renderer;
both published-SAAS and CUSTOM backend fixtures enforce the same ownership rule.
External consumers of the undocumented raw payment `reservation` property must
use authorized account reads instead; the property is intentionally removed.
No frontend files, dependencies or generated contracts changed.

## Executed proof

Private native PostgreSQL **17.10**, bound to `127.0.0.1:64598`, was initialized
under `/private/tmp/disposable_sec02_proof_20260929t200024z_2ee44ead/pgdata`.
Every exact database name was confirmed absent in that cluster before creation.
Acceptance database: `disposable_sec02_2ee44ead_sec02`. Separate owned databases
were used for before-fix reproduction and affected suites. The SEC-01 rerun uses
`disposable_sec01_sec02_2ee44ead_sec01` to retain its existing strict name guard.

All **60 real repository migrations** applied. Prisma validate/status/schema diff
pass; the schema diff is empty and all stored migration checksums match source.
The ledger is in `pos` for this runner's explicit `?schema=pos` URL. Tip:
`20261011120000_canonical_menu_sync`;
SHA-256 `25b9cbb8d6d8590b702acdf2a35f38852c8110f7c21a752887bbbf49061049ac`.

| Check | Result |
| --- | --- |
| Original-source unit/service reproduction | 5 expected failures, 9 passes: email disclosure/query and all three status outcomes |
| Original-source real PostgreSQL/HTTP reproduction | 3 expected failures, 22 passes: attacker receives victim row and both Venue status routes disclose private data |
| SEC-02 service/controller | **14 passed**, 0 failed/skipped |
| SEC-02 PostgreSQL/Nest HTTP | **25 passed**, 0 failed/skipped |
| SEC-01 trusted booking amount | **83 service + 45 PostgreSQL/HTTP passed**, 0 failed/skipped |
| Payment integration / public tenant isolation | **8 / 20 passed** |
| Website provisioning / CUSTOM | **14 / 15 passed** |
| Commercial access / subscription lifecycle | **16 / 16 passed** |
| Related Host/capability/entitlement/crypto/table regressions | **91 passed** across 11 suites |
| SaaS restaurant-web | **19 tests passed**, production build passed |
| Shared website-client | **6 tests passed**, typecheck passed |
| Standalone Vankisi CUSTOM | Production TypeScript/Vite build passed |
| Backend | Nest build and explicit SEC-02 source/test typecheck passed |
| New tests and UserService lint | **0 errors, 0 warnings** |
| Modified payment controller lint | Unchanged baseline **9 errors, 4 warnings** in existing untyped provider-status code; no new diagnostics |
| Git diff | `git diff --check` passed |

The real suite uses CSRF acquisition, signup, signin, Argon password hashing,
JWT signing/verification, encrypted HttpOnly cookies and live WebsiteUser reads.
Bank transport and the unrelated realtime gateway are mocked; operational
dispatch is outside this harness. Availability and map reads use the real
Prisma/Cloud mirror; separate dates avoid conflating
this test with WEB-01 concurrency. Payment publication/historical states are
explicit fixture updates; no real payment or operational dispatch is claimed.

Two synthetic Venues in separate Organizations, one CUSTOM and one published
SAAS, prove the matrix: matching email never owns a guest row; the same real
account sees only its own Venue-specific bookings; another account sees none;
forged body userId/venueId and query/reservation IDs grant nothing; unknown or
disabled Host/Venue fails closed; ordinary/unbound/foreign admin sees no guest
PII; legitimate admin access and anonymous occupancy remain functional.

Independent SQL before cleanup confirms 13 synthetic rows: 8 anonymous and 5
user-bound, including two original confirmed guests with private notes preserved
and one historical completed user-bound booking. Alice owns bookings at two
Venues; the victim-email attacker owns **0**. All 12 newly created priced bookings
remain 110 GEL despite client-supplied 1 GEL; provider IDs are synthetic only.

Initial harness corrections were limited to new test setup: mock the unused
gateway to avoid the existing Jest/UUID ESM import issue, fix the unit mock's OR
semantics, and use actual Venue/capability schema field names caught by typecheck.
An existing provisioning suite refused a disposable name lacking its required
`website_provisioning` suffix; it passed unchanged on a correctly named fresh DB.
The first ledger read used `public`, then discovery selected the actual `pos`
schema. No unrelated test, guard or migration was weakened.

## Cleanup and durable evidence

**Real bank network calls: 0. Real charges: 0.** Axios provider functions are
explicitly asserted to be mocks. A process-level socket guard blocks external
Node connections; blocked Prisma telemetry probes are recorded, not bank calls.
Only local HTTP and the existing CUSTOM suite's synthetic localhost checks were
allowed. No normal database URL or customer dataset was used.

All **10 recorded owned databases were dropped** and exact-name absence was
verified after each drop. The private cluster was stopped, its port verified
closed and its directory removed. Owned socket/scratch directories were removed.
The normal Docker container IDs/names/images/mount summaries/states match before
and after. No Docker mutation or connection to `vankisi_database`/normal local-prod
data occurred. Copied dependencies/build outputs are removed after verification;
private source snapshots/logs are retained.

Durable compact evidence: [SEC02_2026-09-30.json](proofs/SEC02_2026-09-30.json).
Raw logs: `/private/tmp/disposable_sec02_proof_20260929t200024z_2ee44ead/`.
Baseline, original/fixed Jest reports, migration hashes, SQL counts, network
guard records, cleanup and WIP-preservation evidence are retained there.

Changed application files: `website/user/user.service.ts` and
`website/payment/payment.controller.ts`. New tests:
`website/user/guest-booking-ownership.spec.ts` and
`website/user/guest-booking-ownership.integration.spec.ts`. Documentation includes
this note, the proof JSON and narrow project-state/code-map entries.

Remaining: next planned milestone **WEB-02**, then MENU-02/MENU-01; paid-booking
gates WEB-01/03/04/06, SEC-03 and OPS-01 remain open, as do the other historical
Master Plan issues. No full browser/bank sandbox journey or general session
hardening is claimed. **STOP after SEC-02.**
