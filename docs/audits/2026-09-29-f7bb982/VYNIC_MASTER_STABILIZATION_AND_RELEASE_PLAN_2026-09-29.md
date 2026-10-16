# Vynic — Master Stabilization, Product Completion & Release Plan

**Basis:** 2026-09-29 audit set, HEAD `f7bb982` + the WIP that existed when the audit started.  
**Purpose:** turn the audit into one execution plan that can be followed without losing track of what is fixed, what is proven, what is still blocked, and what may be sold.  
**Important:** this plan does not itself change application code. Each implementation milestone must be a separate task with its own tests, proof and review.

**2026-10-06 scope update:** multi-POS, LAN/Windows cabled printer stations and
optional explicitly compatible sound are required current readiness work.
Follow [Windows POS and multi-terminal readiness](../../POS_MULTI_TERMINAL_READINESS_PLAN.md).
This supersedes the single-POS-only proposal and EDGE-01 deferral. Historical
evidence and unfinished acceptance gates remain authoritative.

---

## 0. Operating rules for the next phase

1. **Feature freeze for non-essential new features.** Do not add KDS, delivery, loyalty, extra themes, recurring billing, advanced analytics or broad rewrites until the release gates below are closed.
2. **One milestone at a time.** Implement → test → manual proof → commit → update audit/backlog → move on.
3. **No hidden scope expansion.** A task that starts as a booking-price fix must not become an auth rewrite.
4. **No “green by weakening tests”.** Existing production guards stay authoritative.
5. **No live customer data for verification.** Use synthetic/disposable environments only.
6. **Do not touch `vankisi_database` during audit/fix verification.**
7. **Do not treat build success as product proof.**
8. **Do not treat a hidden button as authorization.** Server enforcement is required.
9. **Do not treat multiple enrolled POS devices as multi-POS operational readiness.**
10. **Every release candidate gets a dossier:** source commit/WIP identity, migrations, image/binary version, test result, restore proof, known limitations and rollback compatibility.

---

# 1. Current product reality

Vynic is already a real multi-surface restaurant platform:

- NestJS + Prisma + PostgreSQL Cloud backend
- Windows Flutter POS with local Hive operational state
- Flutter Manager
- Platform Admin
- Customer Dashboard
- generic SAAS restaurant website
- standalone CUSTOM websites
- canonical Cloud Menu with POS local projection/mutation journal
- commercial plan/subscription lifecycle
- per-Venue capabilities and policies
- BOG restaurant-payment infrastructure
- Go Edge foundation/updater/shadow coordination
- signed Windows installer/updater foundation
- Docker/Traefik production-like deployment foundation

However, the audit does **not** justify selling the full package to a real restaurant yet.

The main issue is no longer “missing lots of screens”. It is that several financial, privacy, recovery and operational paths can still report success before the action is durably safe or can lose/contradict state after failure.

---

# 2. Evidence baseline

## Executed in the audit

- Backend non-integration/unit/service/HTTP suite: **536 passed**, 7 blocked by the audit environment's socket-listener restriction.
- Platform/customer web: **158 passed**.
- SAAS restaurant web: **19 passed**.
- shared website client: **6 passed**.
- custom-site template: **3 passed**.
- Five relevant builds passed.
- Python release tooling: **31 passed**.
- Synthetic reproductions confirmed:
  - `SEC-01`
  - `SEC-02`
  - `MENU-03`
  - `MGR-01`
  - `MGR-02`

## Not re-proven in that audit run

- 38 PostgreSQL integration suites
- migration replay / upgrade / backfill / fresh restore
- Flutter test/analyze
- Go Edge tests
- current Docker image ↔ source provenance
- Windows executable / printer / physical payment terminal
- BOG sandbox
- full authenticated browser workflows
- representative load/capacity
- current dependency advisory counts

These are verification gates, not proof that those components are broken.

---

# 3. Single source of truth for work

Use `MASTER_BACKLOG.md` issue IDs.  
Do **not** create parallel duplicate task lists.

Aliases already consolidated by the audit:

- `MENU-04` → `COM-01`
- `INV-03` → `MENU-06`
- `EDGE-02` → `OPS-01`
- `POS-04` is an intentional limitation handled under `PROD-01`

---

# 4. Master issue inventory — nothing omitted

## P0 — release blockers for the affected scope

### Security / Website / payment
- `SEC-01` — all website booking creation paths must use server-trusted amount
- `SEC-02` — guest booking ownership must not be inferred from unverified email
- `WEB-01` — reservation hold/create must be concurrency-safe; late-payment policy required
- `WEB-02` — unpublished draft must not become public during shared-foundation migration/upgrade
- `WEB-03` — confirmed paid booking + durable POS dispatch must share a recoverable boundary
- `WEB-04` — BOG callback/event ledger must validate expected amount/currency and enforce legal state transitions

### Canonical Menu / local durability
- `MENU-01` — backup must include durable menu/closure/command recovery state
- `MENU-02` — acknowledged local menu edits must survive sync/projection/crash
- `MENU-06` — menu retirement must preserve historical/offline inventory consumption authority

### Single-POS operational integrity
- `POS-01` — Close Day must be recoverable and must block/admit concurrent mutations safely
- `POS-03` — item transfer must preserve quantity/value atomically across crash boundaries
- `POS-05` — one table must not acquire two active orders through concurrent writers

### Manager operational integrity
- `MGR-02` — “free table” cannot mutate only Cloud and falsely report completion
- `MGR-05` — Manager order edit cannot delete/recreate Cloud lines non-transactionally

### Multi-POS
- `EDGE-01` — 3/10 simultaneous operational writers are not currently production-supported

## P1 — required before broader launch / promised capability

- `MENU-03` — exact idempotent mutation retry must return original durable outcome
- `MENU-09` — canonical Menu protocol/version negotiation for old POS builds
- `COM-01` — POS-only owner Dashboard Menu must not depend on WEBSITE
- `MGR-01` — remove hardcoded 9+4 Manager table-layout filtering
- `MGR-03` — Manager UI must distinguish QUEUED/CLAIMED/SUCCEEDED/FAILED/UNAVAILABLE
- `MGR-06` — payroll/obligation/reserve payments need immutable correction/reversal workflow
- `SEC-03` — public/admin account throttling, password/session lifecycle, revocation/MFA decisions
- `SEC-05` — local PIN/device/backup confidentiality and key recovery
- `SEC-06` — privacy notices, retention/export/deletion/backup-expiry governance and legal review
- `WEB-06` — rotated BOG readiness must deterministically select current enabled integration
- `WEB-07` — Vankisi should consume supported shared hours/contact/gallery data where promised
- `POS-02` — durable/uncertain printer delivery and physical printer qualification
- `OPS-01` — reproducible release/DB/migration/restore/native Windows qualification
- `OPS-03` — current supply-chain scans, SBOM/digests/provenance/advisory triage
- `UX-01` — public demo form must persist a real request or route to the canonical flow
- `PROD-01` — explicit product contract: one-primary-POS scope, manual card recording, manual billing, disabled/unsupported modules

## P2 — important quality / product-completeness work

- `INV-01` — full Inventory domain: locations, transfers, waste/internal use, stocktake/adjustments, then returns/production
- `UX-02` — Manager daily-work IA redesign after correctness fixes
- `INV-02` — correct labels/provenance for current cost vs historical COGS vs cashflow vs realized profit
- `INV-04` — inventory consumption/history pagination beyond silent 100-row limit
- `MGR-04` — source/freshness/completeness metadata; stale cache must not look live
- `MENU-05` — restore/re-enable disabled items without recreating identities
- `MENU-07` — unify exact money representation instead of mixed Float/double semantics
- `MENU-08` — audit “Use current” conflict resolution/discard
- `MENU-10` — bounded menu feed pagination/retention/high-water behavior
- `WEB-05` — CUSTOM binding must prove deployed build identity, not only operator attestation
- `SEC-04` — explicit policy for public media after entitlement/subscription removal
- `OPS-02` — verify suspected local Docker/LAN exposure and bind only intended interfaces
- `TECH-01` — static-analysis debt management without blanket rewrites

## P3 — later differentiators / optional capability

- `PROD-02` — automatic subscription collection, KDS/delivery integration, additional themes, advanced analytics

---

# 5. Mandatory first five milestones — preserve audit order

These are the first five reviewable implementation milestones chosen by the audit.

## Milestone 1 — SEC-01: trusted server-side booking amount

### Why first
A real service path allowed a synthetic 110 GEL booking to persist/send 1 GEL supplied by the client.

### Implementation boundary
- one shared server pricing/booking application service
- all public booking/payment creation entrypoints use it
- validate Venue ownership, item existence, enabled state, quantities, capabilities
- provider adapter receives only server-produced payment intent/amount
- prefer exact monetary representation/minor units at this trust boundary

### Must not change
- BOG merchant ownership
- Host-derived Venue authority
- POS historical captured prices
- manual Vynic subscription billing

### Acceptance
- client `totalAmount=1` cannot determine stored/provider total
- altered item price rejected/ignored
- foreign Venue item denied
- missing/disabled item denied
- invalid quantity denied
- expired/disabled capability denied
- both creation routes yield the same trusted amount
- no real charge; stub/sandbox only

### Exit
`SEC-01` closed; paid website still **not** releasable because WEB-01/03/04/06 remain.

---

## Milestone 2 — SEC-02: guest booking ownership

### Why
An account created with an unverified victim email could see matching guest booking personal data.

### Implementation boundary
- stop implicit historical ownership by raw email equality
- use authenticated user binding or explicit booking-scoped claim
- if email verification is selected, it must be a real verified state, not text equality
- claim must be Venue-scoped, expiring, replay-safe and auditable

### Acceptance
- attacker signup with victim email returns no victim booking
- legitimate explicit claim works
- wrong Venue denied
- claim replay/expiry tested
- existing user-bound booking remains accessible

---

## Milestone 3 — WEB-02: safe publication upgrade

### Why
The shared-foundation migration preferred draft values over published values, which can make unpublished content public.

### Implementation boundary
- never rewrite old applied migration
- create read-only affected-state report
- build pre-upgrade fixtures:
  - published only
  - draft only
  - divergent published + draft
  - empty
- create repair/reconciliation only where provenance is trustworthy

### Acceptance
- published A + private draft B → public remains A after upgrade
- private B remains recoverable/private
- no guessed replacement where provenance was already destroyed
- upgrade + restore proof in disposable DB

---

## Milestone 4 — MENU-02: crash-safe local menu mutation boundary

### Why
A POS edit acknowledged locally can be overwritten by a concurrent projection rewrite; reapply has a remove→put crash gap.

### Implementation boundary
- one recoverable local mutation coordinator/journal-first boundary
- serialize local writers against projection replacement
- projection rewrite must not erase acknowledged local intent
- reapply/discard transitions must be crash-safe

### Acceptance
Fault injection at:
- local save ↔ journal
- sync await + second local edit
- projection clear/write
- Cloud commit ↔ ACK
- reapply replacement
- restart after each point

Every acknowledged edit must resolve to:
- pending
- accepted
- explicit conflict
- explicitly/auditably discarded

Never silent loss.

---

## Milestone 5 — MENU-01: complete backup / fresh-machine restore

### Why
Current backup omits canonical menu state/journal, closure journal and Edge command journal and serializes sensitive PIN material.

### Implementation boundary
- versioned backup manifest/checksum
- include canonical state/cursor + unresolved menu mutations
- include closure/recovery and command journals required for correctness
- define device identity handoff/fencing instead of blindly cloning credentials
- integrate SEC-05 confidentiality/key recovery design

### Acceptance
Backup with:
- pending menu edit
- unresolved conflict
- uncertain closure
- unsent Sale
- cached catalog

Restore to fresh isolated installation:
- no duplicate Sale/charge/print
- no lost acknowledged edit
- corrupt/incompatible backup fails clearly
- wrong-Venue restore denied
- key-loss behavior documented
- actual Windows replacement proof later under OPS-01

---

# 6. After the first five — release-specific tracks

Do not execute all tracks simultaneously. Select the product scope you want to pilot.

---

## Track A — Single-POS controlled pilot

Dependency order:

1. `MENU-03` — exact retry outcome
2. `MENU-06` — archive/retired menu identity + historical recipe authority
3. `MENU-09` — minimum supported canonical POS protocol/version gate
4. `POS-01` — recoverable Close Day + mutation admission barrier
5. `POS-03` — crash-safe transfer
6. `POS-05` — one active order per table
7. `POS-02` — durable/uncertain print jobs + physical printer testing
8. `SEC-05` — local credentials / encrypted backup
9. `OPS-01` — real Windows, migration/restore, release dossier
10. `PROD-01` — lock product claims to what is actually supported

### Pilot acceptance
- one Windows POS
- Cloud outage works within declared limits
- order/payment/close/restart
- no silent lost acknowledged edit
- Close Day crash recovery
- transfer crash recovery
- table double-create denied
- printer paper/cable/power tests
- backup → fresh machine restore
- card payment described as manual recording unless certified acquiring exists

---

## Track B — POS + Manager

Start only after Track A core gates are closed.

Order:
1. `MGR-01` — generic Venue floors/tables
2. `MGR-02` — free-table must be authoritative POS/Edge action
3. `MGR-05` — atomic/durable order-edit intent
4. `MGR-03` — visible delivery states and command IDs
5. `MGR-04` — stale/source/completeness envelope
6. `MGR-06` — immutable financial correction/reversal

### Acceptance
- two different Venue layouts, including non-9+4 layout
- POS offline: Manager shows pending/unavailable, not false success
- queued/claimed/succeeded/failed survive screen reopen
- invalid edit cannot partially rewrite Cloud mirror
- cache fallback shows source age
- financial correction preserves original history

---

## Track C — Menu/contact-only Website pilot

Order:
1. `WEB-02`
2. `OPS-01`
3. security/tenant negative subset
4. for CUSTOM: `WEB-05`
5. for Vankisi/shared promise: `WEB-07`
6. `SEC-04` public-media policy if media is included
7. `SEC-06` before collecting real personal data broadly

### Scope to keep disabled initially
- website accounts
- paid reservations
- online payments

### Acceptance
- correct Host→Venue
- correct build/renderer identity
- public content only after intended publication rule
- cross-Venue negative tests
- reproducible deployment/restore
- SAAS publish time measured
- CUSTOM manual deployment steps honestly shown

---

## Track D — Paid reservations / Website payments

Only after `SEC-01` and `SEC-02`.

Order:
1. `WEB-01` atomic hold/concurrency
2. `WEB-03` durable paid-booking dispatch outbox
3. `WEB-04` immutable provider event ledger/state machine
4. `WEB-06` current integration readiness selection
5. `SEC-03` website account/session/throttle hardening
6. `OPS-01`
7. real BOG sandbox proof

### Acceptance
- 20 concurrent booking attempts produce one valid hold
- late payment/expired hold has deterministic reconciliation
- amount/currency mismatch cannot confirm booking
- duplicate/out-of-order callbacks are harmless
- captured/refunded/authorized states do not move backward
- dispatch survives crash and reaches POS exactly once logically
- existing initiated payment can settle after entitlement/integration change according to policy

---

## Track E — Existing Inventory subset

Before claiming the current subset is dependable:

1. `MENU-06`
2. sale-consumption retry/integrity proof
3. receipt create/post retry proof
4. supplier debt/payment reconciliation proof
5. `INV-02` labels/provenance
6. `MGR-06` corrections
7. `INV-04` history pagination

### Allowed claim
“Receiving, supplier payment/debt registry, recipes and theoretical sale consumption.”

### Do not call it
“Full warehouse/inventory management.”

---

## Track F — Full Inventory product

Only after Track E.

`INV-01` must be implemented in sub-phases:

### F1. Locations
- default location backfill
- per-location quantity ledger
- Venue total = sum of locations

### F2. Transfers
- immutable transfer document
- source −Q / destination +Q
- Venue total net zero
- idempotency and approval/handoff as product requires

### F3. Waste / internal consumption
- reason
- quantity
- location
- actor/approval threshold
- negative stock movement

### F4. Stocktake
- count session
- cutoff/business sequence
- expected vs counted
- approval creates signed adjustment
- no direct balance editing

### F5. Purchase orders / partial receipt / returns / credit notes
- ordered / received / remaining
- receipt remains distinct from payment
- return quantity, debt credit and cash refund are separate facts

### F6. Production / yield
- consume ingredients
- produce finished/semi-finished stock
- actual yield and waste

### F7. Historical costing if product decision requires it
Current moving average/current theoretical recipe cost is not realized historical COGS.

### Mandatory flour acceptance
- receive 20 kg @ 3 GEL/kg → 20 kg / 60 GEL / debt 60
- pay 30 → stock unchanged / debt 30 / outflow 30
- transfer 4 kg → total stock remains 20
- consume 2.5 kg → 17.5
- waste 0.5 → 17
- count 16.6 → discrepancy −0.4
- approve adjustment → 16.6 kg / 49.80 GEL
- supplier debt stays 30 GEL

Every balance must link to its source document.

---

## Track G — Multi-POS 3 terminals, then 10

Start EDGE-01 as required current work alongside the printer boundary. Activation
still requires single-POS integrity, complete writer fencing and three-terminal
correctness proof.

`EDGE-01` is a separate major architecture milestone.

### Required operational authority
- Venue-local table/order/payment/day authority
- epochs/fencing
- durable command results
- one active order per table
- settlement exclusion
- transfer atomicity
- Close Day barrier
- crash/restart recovery
- old primary return rejection

### 3-terminal proof first
- A opens table, B/C observe bounded state
- simultaneous table create: exactly one wins
- same order edits: no lost update
- transfer conflicts safe
- payment/cancel conflict safe
- Close Day versus new order safe
- Edge crash + reconnect
- primary handoff

### 10-terminal proof only after correctness
Then measure:
- contention
- p50/p95/p99
- memory
- error rate
- bounded dataset/load
- partition behavior

Never market 10 active terminals from canonical Menu tests alone.

---

# 7. Commercial / product contract

## Current safe principle
Account/Venue ownership ≠ paid access.

## Before pilot
`PROD-01` must make the selected scope explicit:

- one operational primary POS unless Edge multi-POS is released
- POS card choice records an externally confirmed payment; it is not acquiring authorization
- manual Vynic subscription billing may be used
- automatic recurring billing must not be advertised
- unsupported Inventory modules hidden/blocked server-side
- unsupported website accounts/payments/reservations disabled in a narrow website pilot
- NON_FISCAL_CLOSE stays explicit Venue override, never a plan default

## Manual subscription billing
Can be a pilot scope once the PostgreSQL lifecycle/replay/open-session matrix and OPS-01 are proven.

Automatic collection remains `PROD-02`.

---

# 8. Security plan

## Immediate
- `SEC-01`
- `SEC-02`

## Before public accounts / broader personal data
- `SEC-03`
- `SEC-06`

## Before device/backup rollout
- `SEC-05`

## Media/product policy
- `SEC-04`

## Supply chain
- `OPS-03`

### Required security verification
- direct API negative tests
- two-Venue isolation
- session disable/logout/password-change matrix
- cookie/CSRF/CORS browser matrix
- SSRF adversarial cases
- upload quota/ownership/concurrency
- secret backup/rotation recovery
- Docker exposed ports
- current npm/Go/Dart/container advisories with reachability analysis

No “secure” claim without these proofs.

---

# 9. Manager UX / Inventory redesign plan

Correctness comes before visual redesign.

## First fix operational truth
- `MGR-01`
- `MGR-02`
- `MGR-05`
- `MGR-03`
- `MGR-04`
- `MGR-06`

## Then `UX-02` information architecture

Recommended Manager inventory navigation:

1. **მარაგების მიმოხილვა**
   - quantity, value, low/negative
   - data source and last update

2. **მიღებები**
   - drafts
   - posted receipts
   - receiving review
   - document totals

3. **მომწოდებლები და ვალდებულებები**
   - supplier catalog
   - payable balance
   - payments linked to receipts

4. **ნაშთები და ადგილები** *(after INV-01 F1)*
   - Venue total
   - warehouse/kitchen/bar breakdown

5. **გადაადგილება** *(after F2)*
   - source
   - destination
   - quantity
   - status/handoff

6. **დანაკარგი / შიდა მოხმარება** *(after F3)*

7. **აღწერა / ინვენტარიზაცია** *(after F4)*

8. **რეცეპტები / მენიუს შემადგენლობა**

9. **მოძრაობების ისტორია**
   - every balance → source document
   - pagination/export

10. **პრობლემები**
    - sale without consumption
    - unknown cost
    - pending movement
    - negative stock

### UX principle
For every operation the UI must answer:
- What am I entering?
- Where did it come from?
- Where does it go?
- When does stock change?
- When does supplier debt change?
- When does money move?
- Which document caused this balance?
- How do I correct an error without deleting history?

---

# 10. Website SAAS / CUSTOM plan

## Architecture that should remain
- one backend
- same restaurant foundation
- Host→VenueDomain→Venue authority
- SAAS/CUSTOM selects renderer, not a separate data backend
- Vankisi can remain standalone
- templates/shared client remain optional

## Simplify operator workflow
One operator review surface should show five independent facts:

1. Commercial package/status
2. Interface type: NONE / SAAS / CUSTOM
3. Domain(s)
4. Deployed build / custom frontend identity
5. Publication/live readiness

Do not combine “ACTIVE” with “frontend actually deployed”.

## SAAS
Target business flow:
request/owner → plan/mode → invitation → menu/profile → preview/publish.

## CUSTOM
Additional real steps remain:
frontend build/deploy → siteKey → domain → router/DNS/TLS → same-origin API → build/backend identity proof → READY/ACTIVE.

Do not promise automatic deployment unless it is actually built.

---

# 11. UI/UX quality plan

Do not begin broad visual redesign before correctness blockers are closed.

## P1 UI
- `UX-01` real durable lead/request submit
- `MGR-03` delivery status
- Platform website readiness facts
- clear product limitations

## P2 UI
- `UX-02` Manager daily-work IA
- `MGR-04` stale/source metadata
- `MENU-05` inactive item restore
- `INV-04` history pagination
- accessibility/responsive cleanup

## Final release QA
Web:
- 375/390
- 768
- 1280/1440
- zoom/reflow
- focus/modal behavior
- screen-reader labels/errors/status

POS:
- Windows 1024×768
- supported desktop sizes
- touch + external keyboard
- PIN/numeric/text live synchronization
- offline/restart/error states

Manager:
- supported phone/tablet/desktop targets
- large font
- portrait/landscape
- long Georgian copy
- reconnect/stale state
- notifications

---

# 12. Deployment / Operations plan

`OPS-01` is a cross-cutting release gate.

Prove:

- exact source revision → image/binary digest
- migration checksum/state
- same-Mac + native ingress
- Socket.IO/native routes
- fresh DB migration replay
- upgrade/backfill
- DB + media + encryption-key backup
- restore into fresh environment
- old/new client compatibility
- Windows install/update/rollback
- supported printer hardware
- production limitations documented

`OPS-02` verifies local/LAN exposure.

`OPS-03` handles dependency/container supply-chain.

Do not claim deployment-ready from Compose files alone.

---

# 13. Market-competitiveness plan

The audit compared RestIQ, FINA and r_keeper/UCS using vendor public sources only.

Do not target “more features than everyone”.

Target three measurable advantages:

## Advantage 1 — Recoverable offline POS
Benchmark:
- 1,000 synthetic orders
- kill after every critical write boundary
- 60-minute Cloud outage
- lost acknowledged mutation = 0
- duplicate settlement = 0

## Advantage 2 — understandable Georgian daily management
Benchmark:
- 5 novice managers
- receipt 20 kg / payment 30 GEL / stock-document tracing
- complete in ≤5 minutes
- ≥90% correctly distinguish stock / debt / cash / pending/stale

## Advantage 3 — one managed Menu, two website renderers
Benchmark:
- new SAAS Venue plan→published site ≤15 min
- catalog edit→online renderer convergence p95 ≤60 sec
- cross-tenant leakage = 0
- CUSTOM manual deployment time measured separately

Only market these as advantages after proof.

---

# 14. Static quality / folder structure

No mass folder/framework rewrite.

Current top-level structure is broadly appropriate:

- apps = deployable products
- packages = shared libraries/contracts
- templates = starters
- deploy = deployment infrastructure
- scripts = guarded tooling

Fix boundaries only when a reliability task needs them:

- shared booking/pricing application service for SEC-01
- operational-command boundary for Manager fixes
- local mutation coordinator/journal API for POS durability
- inventory domain documents/screens after domain capability exists
- typed response envelope for queued/stale/completeness states

`TECH-01`:
- no new lint debt in touched code
- gradually type critical boundaries
- do not spend a reliability milestone fixing thousands of unrelated lint findings

---

# 15. Release gates by product

## Website menu/contact-only
Required:
- WEB-02
- OPS-01
- relevant tenant/security negatives
- CUSTOM additionally WEB-05/07
- disable accounts/reservations/payments if not in scope

## One primary POS
Required:
- MENU-01/02/03/06/09
- POS-01/03/05
- POS-02
- SEC-05
- OPS-01
- product limitations under PROD-01
- actual Windows proof

## POS + Manager
Single-POS gates +
- MGR-01/02/03/05
- MGR-04
- action permissions
- pending/failure semantics

## Inventory subset
- MENU-06
- receipt/debt/payment/consumption integrity proof
- INV-02 labels
- MGR-06 corrections
- INV-04 history

## Full Inventory
Subset +
- INV-01
- UX-02
- flour end-to-end scenario

## Paid reservations
- SEC-01
- SEC-02
- WEB-01/03/04/06
- SEC-03
- OPS-01
- BOG sandbox

## Manual subscription billing
- real PostgreSQL lifecycle matrix
- OPS-01
- PROD-01
- open-session revocation proof
- quote/replay/agreed-price/anchor preservation

## 3 terminals
All single-POS gates +
- EDGE-01 active authority design/cutover
- partition/fencing/settlement proof

## 10 terminals
3-terminal correctness first +
- measured load/contention/latency/capacity proof

---

# 16. Verification backlog that must be recovered after environment limitations

The audit environment could not execute:

- 38 PostgreSQL integration suites
- migration replay/upgrade/backfill/restore
- Flutter suite/analyze
- Go suite/scanner
- Docker image/source provenance
- native REST + Socket.IO/LAN
- npm registry advisory scan
- current container scan
- authenticated browser workflows
- real 375/768/1280/1440 viewport matrix
- real Windows install/restart
- physical printer
- payment hardware
- BOG sandbox
- representative capacity benchmark

Plan an explicit `OPS-01 / verification recovery` milestone as soon as the environment permits these checks.

---

# 17. Exact execution sequence

## Phase 0 — freeze and baseline
- choose first pilot scope
- preserve current WIP
- create implementation branch
- record commit/migration/image versions
- establish disposable PostgreSQL/Flutter/Windows test environments
- update MASTER_BACKLOG only from accepted findings

## Phase 1 — SEC-01
Trusted booking amount.

## Phase 2 — SEC-02
Guest booking ownership.

## Phase 3 — WEB-02
Publication/migration safety.

## Phase 4 — MENU-02
Crash-safe local mutation boundary.

## Phase 5 — MENU-01
Full durable backup/restore.

## Phase 6 — choose pilot branch
The October 6 selected scope is Windows printing and multi-POS readiness; follow
the linked current plan. Historical alternatives below do not defer EDGE-01.

Do not start all product branches simultaneously.

### If single POS selected
MENU-03 → MENU-06 → MENU-09 → POS-01 → POS-03 → POS-05 → POS-02 → SEC-05 → OPS-01 → PROD-01.

### If website selected
WEB-02 already done → OPS-01 → security/tenant negatives → WEB-05/07 if CUSTOM → SEC-04/06 as scope requires.

## Phase 7 — Manager
MGR-01 → MGR-02/MGR-05 → MGR-03 → MGR-04 → MGR-06.

## Phase 8 — Inventory subset
MENU-06 dependency → receipt/debt/payment/consumption proofs → INV-02 → INV-04 → MGR-06.

## Phase 9 — Full Inventory
INV-01 F1–F7 → UX-02.

## Phase 10 — Paid website reservations
WEB-01 → WEB-03 → WEB-04 → WEB-06 → SEC-03 → OPS-01 → bank sandbox.

## Phase 11 — Multi-POS
EDGE-01: 3 terminals first → then 10 terminals. Required current work under the
October 6 scope update; not deferred until Phase 11.

## Phase 12 — security/ops broadening
SEC-06, OPS-03, OPS-02, remaining SEC-04, current advisory triage, release dossier/restore drills.

## Phase 13 — polish / differentiators
MENU-05/07/08/10, TECH-01 targeted cleanup, UX-02 refinement, measurable market advantages.

## Phase 14 — P3
PROD-02 only after core gates:
automatic subscription collection, KDS/delivery, more themes, advanced analytics.

---

# 18. Per-task workflow

Every implementation task follows this exact loop:

1. Read the issue card and dependencies.
2. Reproduce before fix if practical.
3. Implement only that root cause.
4. Add regression test.
5. Run nearest unit tests.
6. Run real DB/integration proof where relevant.
7. Run manual UI/native proof where relevant.
8. Run migration replay/upgrade if schema changes.
9. Verify tenant isolation.
10. `git diff --check`.
11. Create focused commit(s).
12. Update issue status and evidence.
13. Do not mark DONE until acceptance criteria are met.
14. Only then start the next issue.

Statuses:
- NOT_STARTED
- IN_PROGRESS
- IMPLEMENTED_NOT_PROVEN
- TESTED
- MANUALLY_PROVEN
- BLOCKED
- DONE

---

# 19. Decision log required from owner

Before relevant milestones, explicitly decide:

1. First pilot: one POS or menu/contact-only website?
2. Guest booking claim UX after SEC-02.
3. Reservation scope: whole-day table vs time-slot; late-payment policy.
4. Is POS-only Dashboard Menu authoring officially offered?
5. Inventory pilot: limited subset or full Inventory?
6. Permanent menu deletion policy versus archive-only default.
7. Backup encryption/key custodian/recovery policy.
8. Printer models officially supported.
9. Card acquiring: manual recording only in pilot?
10. CUSTOM `ACTIVE`: public serving gate or operator attestation?
11. Public media retention/revocation policy.
12. Privacy/retention/deletion policy after Georgian legal review.
13. Multi-POS partition policy: deny unsafe writes when shared authority is unavailable?
14. Historical costing method if/when realized COGS is promised.

---

# 20. Definition of release-ready

A selected product/scope is only ready when:

- no unresolved P0 applies to that scope;
- its core user journeys pass end-to-end;
- cross-Venue negative tests pass;
- no known silent acknowledged-data-loss path remains;
- migration upgrade and fresh restore pass;
- server-side permissions match UI;
- hardware claims have real hardware proof;
- product limitations are explicit and enforced;
- the exact release artifacts are identified;
- rollback compatibility is known;
- support can investigate uncertain commands/payments without “just try again”.

No claim of zero bugs or absolute security is required or justified.

---

# 21. What not to do

Do not currently prioritize:

- KDS
- delivery integrations
- loyalty/gamification
- multiple website themes/page builder
- automatic recurring billing
- advanced analytics
- general ERP expansion
- mass folder rewrite
- microservices rewrite
- blanket lint autofix
- automatic Edge operational cutover
- Vankisi migration to the custom starter

These come after core integrity and proof.

---

# 22. Immediate next action

**Start SEC-01 only.**

After SEC-01 is accepted:
SEC-02 → WEB-02 → MENU-02 → MENU-01.

Then choose the first pilot branch and proceed through its dependency chain.

This keeps the project understandable and prevents another period of many partially completed parallel tasks.
