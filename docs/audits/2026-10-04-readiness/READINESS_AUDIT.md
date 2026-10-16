# Vynic deployment and safe-update readiness audit

**2026-10-06 scope supersession:** the owner requires multi-POS now, together with
LAN/Windows cabled station printing and optional explicitly compatible sound.
Follow [the current readiness plan](../../POS_MULTI_TERMINAL_READINESS_PLAN.md).
The single-terminal proposal below is historical; its evidence and unresolved
gates remain valid, but its product exclusions no longer define the chosen scope.

**Audit date:** 2026-10-04 UTC. **Decision: NO-GO for a real restaurant deployment today; GO for isolated staging and scoped feature development.**

**Smallest proposed release:** one restaurant, one enrolled primary Windows POS, approved printer models, manual card reconciliation, manual subscription administration. Keep Manager operational writes, public customer accounts, paid website reservations and multi-POS outside that first release. The owner has not yet confirmed this target. A menu/contact-only website is a separate, smaller alternative; it still needs the Cloud security, publication, hosting and recovery gates below.

This is an audit, not deployment approval. It does not authorize implementation, publishing, physical printing, a new release, or changes to the running Windows POS.

Plan inputs: [September 29 master plan](../2026-09-29-f7bb982/VYNIC_MASTER_STABILIZATION_AND_RELEASE_PLAN_2026-09-29.md), [master backlog](../2026-09-29-f7bb982/MASTER_BACKLOG.md), [current project state](../../agent-state/VYNIC_PROJECT_STATE.md) and [Windows installer handoff](../../POS02_WINDOWS_INSTALLER_HANDOFF.md).

**Authorized follow-up:** [Configuration and dependency review](CONFIGURATION_AND_DEPENDENCY_REVIEW.md) records the completed npm scan and a redacted, read-only environment review. Production configuration requires separate runtime/build/install settings; changing env values alone does not close this audit's code, hardware or release gates.

## Executive assessment

The first five milestones in the September 29 plan have been completed, and additional Menu and single-POS integrity work is present. Repeating “start SEC-01” would send development backwards. The remaining work is concentrated in release qualification and a few still-unsafe product tracks.

The strongest fresh evidence is **235 Flutter tests, 137 backend unit/service tests, 25 PostgreSQL/HTTP tests, 27 release-tool tests, all 65 migrations applied and checksum-verified, repeat migration, and a synthetic database restore**. Production-scope TypeScript checking passes. These are valuable checks, not end-to-end production qualification.

The next release must close these gates, in order of dependency:

1. **OPS-01 / PROD-01:** choose the first product scope, hosting/DB/media provider, real Windows device and deployment owner; freeze a reviewable candidate independently of unrelated WIP.
2. **POS-02:** fix and qualify the Windows acceptance launcher, decide receipt/paper/no-byte retry policy, and complete physical printer and x64 Windows qualification. The installed 1.0.14 development build does not close this gate.
3. **OPS-01:** produce production-signed, traceable artifacts; establish stable HTTPS endpoints and metadata/key/certificate renewal ownership; prove the exact upgrade and rollback pair against retained data and journals.
4. **OPS-01 / SEC-05:** rehearse complete Cloud and POS replacement recovery, including media, encryption keys, enrollment/fencing and pending work. Set recovery objectives and custody controls before live data.
5. **OPS-01 / OPS-03 / TECH-01:** validate the selected candidate through a repeatable release gate, current supply-chain assessment, minimal operational alerts and an attended pilot. Do not inherit a green status from another commit or narrower test run.

**Additional scope blockers:** Manager writes remain blocked by MGR-02/05 and incomplete delivery/freshness presentation. Paid reservations remain blocked by WEB-01/03/04. Multi-POS remains blocked by EDGE-01. These do not all have to be implemented for a deliberately restricted one-POS release; their exclusion must be enforced at the API/product boundary.

| Target | Go/no-go now |
|---|---|
| Isolated staging, synthetic acceptance, scoped feature development | **GO** within the existing boundaries and shared-checkout ownership rules |
| One working restaurant POS | **NO-GO** pending POS-02 and production release/recovery/security gates |
| Menu/contact-only website | **NO-GO for publication from this audit**; smaller qualification path, current web candidate and target infrastructure unqualified |
| POS + mutating Manager | **NO-GO** pending Manager integrity/status gates in addition to POS gates |
| Paid bookings / public website accounts | **NO-GO** pending payment/concurrency/auth gates |
| Multiple operational POS terminals | **NO-GO**; shadow coordination is not production authority |

## 1. Scope, evidence and preservation

Baseline: branch `codex/docker-deployment-foundation`, HEAD `275688e1e5c5dc0e26e62705ab0c7670cf16d99a`, empty index, existing stash `9df454225caec647f67ad4f70ef6038dbbbe41d6`. Extensive pre-existing tracked/untracked work spans POS, backend, deployment, documentation and Claude-owned `apps/platform-web`. The audit inspected current working files. It did not treat HEAD as their complete source identity.

- Startup followed `AGENTS.md`, project state, task sections of the code map, skill routing and `.agents/skills/vynic-engineering/SKILL.md`; relevant decisions and engineering invariants were checked.
- The initial file-hash/status inventory is [baseline.json](evidence/baseline.json). It contains 2,437 file hashes, excludes files >=20 MB, and excludes this audit directory. It is not a secrets inventory.
- All audit-authored files are under this new directory. Tests used an isolated source/Flutter SDK copy under `/tmp`, temporary Hive and fake printer/HTTP transports. The database proof created and stopped its own new PostgreSQL cluster; it never connected to an existing restaurant DB. No VM interaction, physical jobs, commit, push, branch/index/stash manipulation, dependency upgrade or production change was performed.
- The audit does not attest to the current running Cloud images, current production infrastructure, full authenticated browser UX, live payment provider, physical printer output or live Windows database contents.
- Evidence labels below: **CODE** = inspected implementation; **FRESH** = executed in this audit; **RECORDED** = reviewed existing proof, not rerun on its original platform; **GAP** = qualification is missing, not a claim that the feature is broken.

### Fresh validation

| Check | Result | Evidence and limits |
|---|---|---|
| Backend focused unit/service suites | 8 suites, **137 pass** | [backend-tests.json](evidence/backend-tests.json); deployment validation, Platform throttle, booking pricing/ownership, Host/capability rules, public-info review, exact Menu retry. No real bank calls. |
| Actual-service fault probes | **4 defects reproduced** | [probe source](evidence/boundary-probes.cjs), [results](evidence/boundary-probes.json). In-memory persistence fakes; no claim of real concurrency or PostgreSQL failure injection. |
| Flutter unit suites | 11 suites, **215 pass** | [log](evidence/flutter-tests-approved.log); Menu durability/backup/retry/compatibility, Close Day, transfers, ownership, printing/launcher/local printers and update admission. macOS Flutter 3.44.1/Dart 3.12.1; not Windows qualification. |
| Printer widget suites | 3 suites, **20 pass** | [log](evidence/flutter-printer-widget-tests.log); developer access, kitchen entry points and journal actions. HTTP is blocked by the test fixture; printer transport is synthetic. |
| Windows release tooling | **27 pass** | [log](evidence/python-release-tests.log); temporary fixtures/mocks, including same-artifact metadata renewal and rejecting changed bytes under an issued version. No VM publisher was invoked. |
| Fresh PostgreSQL migration chain | **65 applied**, repeat succeeds, **all checksums match** | [proof](evidence/postgres-proof.json), [runner](evidence/disposable-postgres.py), `pg-migrate*.log`. PostgreSQL 17 toolchain, new private loopback cluster. |
| SEC-02 real HTTP/PostgreSQL suite | **25 pass, zero skips** | [results](evidence/postgres-http-tests.json); real Nest/DB tenant and ownership boundaries, mocked payment provider. |
| Synthetic DB dump/restore | **PASS** | Fresh second DB retained a synthetic marker and all migration ledger entries. Does not prove existing-site upgrade, media/key recovery, RPO/RTO or Windows machine replacement. |
| Generated JSON contracts | **PASS** | [log](evidence/contracts-check.log), `node packages/contracts/scripts/generate.mjs --check`; Go/Dart protobuf regeneration was not rerun. |
| Production Compose syntax | **PASS** | [log](evidence/compose-validation.log); synthetic settings only, no services started. |
| Backend runtime TypeScript | **PASS** | `tsc -p tsconfig.build.json --noEmit --incremental false`, [log](evidence/backend-runtime-typecheck.log). Host Node 24 differs from Docker Node 22; this is not an image build. |
| Full backend TypeScript incl. tests | **FAIL: 5 diagnostics in 3 test files** | [log](evidence/backend-typecheck.log): invalid UUID literal inference, nullable audit actor, incomplete PlatformPrincipal test fixtures. Runtime build excludes specs; do not mislabel this as a production compile failure. |
| Current backend production npm advisories | **13 affected entries: 11 high, 2 moderate, zero critical** | After explicit user approval, the bounded scan completed once; exit 1 means findings, not a scan failure. [Summary](evidence/npm-audit-summary.json), [raw result](evidence/npm-audit-approved.json), [scope and payload preflight](CONFIGURATION_AND_DEPENDENCY_REVIEW.md). Transitive/meta entries are included; reachability is unassessed. No fixes/upgrades. Initial DNS/approval denial is retained as history and resolved for this scan. |
| Go tests, full Flutter analysis, all web builds/tests, broad integration/load/browser matrix | **NOT RUN** | Go executable unavailable in PATH and prior tool location. No tool install. Platform-web is concurrent owner WIP; no browser/UX readiness claim. |

Initial Flutter attempts were blocked by shared-SDK writes and test loopback restrictions. The successful run used an owned SDK copy, analytics/version checks suppressed, and approved loopback test access. Failed setup logs are retained separately; they are not product test regressions.

### Windows recovery evidence, correctly bounded

The [October 4 recovery receipt](../../proofs/POS02_WINDOWS_RECOVERY_2026-10-04/proof.json) records POS **1.0.14 / release 15**, Edge 1.0.1, startup verification `SUCCESS`, 24 installed files matching the reviewed ZIP, 883 sealed candidate files and a prepared-source hash. The build is explicitly **development**, with API `http://10.10.10.3:3000`; the VM is Windows 11 ARM running amd64 POS. Metadata expires **2026-10-11T20:20:59.657262Z**. The publication watcher is disabled.

It records **96 product checks passing**, **39 standalone-runner checks passing**, **1 runner failure**, **1 physical-entry skip**. The aggregate is **FAILED**, not “all Windows tests pass.” The known failure is the raw path comparison at `apps/operations/tool/pos02_acceptance_request.dart:97–104`; a Windows separator difference rejects valid owned output before storage/transport. This tool is not shipped in the POS binary, but blocks trustworthy physical acceptance.

The recorded endpoint migration preserved the keys, Edge and data path and compared all 23 data files before launch. After launch the live Hive files were locked, so the receipt explicitly does not claim byte-identical post-launch data. The migration helper has a retained hash but lacks exact-source provenance. None of these facts was re-inspected on the active VM. [Receipt review](evidence/recovery-receipt-review.json).

## 2. Reconciliation of the September plan

Keep the existing issue IDs. This report updates their **readiness assessment**, not the historical audit files. “Implemented” and “qualified for this release” remain separate states.

| Existing work | Current assessment | Current basis / remaining qualification |
|---|---|---|
| SEC-01 trusted booking amount | **DONE, retain closure** | `website/reservation/reservation.service.ts:154–188` uses server-pricing output for persisted amount and provider request; fresh booking-payment tests pass. All payment lifecycle work is not thereby done. |
| SEC-02 ownership | **DONE, retain closure** | `website/user/user.service.ts:35–45` uses Venue plus authenticated user ID; status routes no longer return private rows. Fresh 25-case real HTTP/DB proof passes. |
| WEB-02 publication migration | **DONE implementation/proof; target DB review still required** | Capture/restore migrations `20261010110000` / `20261012120000`, `website/core/public-info-review.ts`, recorded upgrade/already-migrated proofs in [runbook](../../WEB02_SAFE_PUBLICATION_MIGRATION.md). Fresh full chain passes. Do not infer an already-upgraded target's publication consent from that result. |
| MENU-02 local acknowledgment durability | **DONE, retain closure** | Recoverable Menu WAL before projection/journal acknowledgment and startup replay; fresh durability suite passes. [Runbook](../../MENU02_LOCAL_MENU_DURABILITY.md). |
| MENU-01 complete backup/restore | **DONE at implemented local boundary** | `core/database/pos_backup_format.dart` lists 17 stores and authenticated portable encryption; `backup_repository.dart` validates/restores with markers and Venue/identity constraints. Fresh suite passes. Actual Windows replacement and production recovery remain OPS-01/SEC-05. |
| MENU-03 exact retry | **DONE, retain closure** | `menu-catalog/menu-mutation-result.ts`, persisted `acceptedResult`; fresh backend and POS retry tests pass. |
| MENU-06 retirement | **DONE, retain closure** | `retiredAt`, retained identity/recipe relations, tombstones and explicit restore; [recorded real DB/native proof](../../MENU06_SAFE_MENU_RETIREMENT.md). Do not roll back to destructive writers. |
| MENU-09 client admission | **DONE for Menu boundary** | `menu-client-policy.ts`, `menu-client.guard.ts`; fresh POS compatibility suite; 38/38 recognized source hashes still match recorded proof. Not a whole-product binary attestation or fleet rollback policy. |
| POS-01 Close Day | **DONE local implementation; Windows release proof remains** | `close_day_transaction.dart`, local admission and startup recovery; fresh recovery suite passes. |
| POS-03 item transfer | **DONE local implementation; Windows release proof remains** | `order_item_transfer.dart`, durable transfer journal, startup/backup integration; fresh suite passes. Windows smoke document is still pending. |
| POS-05 one table/one order | **DONE for accepted implementation; requalify selected candidate** | Recorded exact-commit ec430880 proof; current mutation/recovery logic plus fresh tests. Current POS-02 WIP is not that exact commit. |
| POS-02 printing | **IMPLEMENTED CANDIDATE, NOT_DONE** | Durable print jobs, frozen bytes/destination, uncertain outcomes, developer-only printer scope and audited kitchen copies are present; fresh tests pass. Physical acceptance, receipt policy and Windows runner remain open. |
| MGR-01 / 02 / 03 / 04 / 05 | **OPEN** | Hardcoded layout filter, Cloud-only free-table, untransactional order edits and incomplete status/freshness treatment remain; details below. |
| COM-01 | **OPEN if POS-only owner Menu is offered** | `customer/restaurant-foundation.service.ts:54–87` still requires WEBSITE for owner catalog read, retired view and mutation. CLOUD Menu and POS presence independence did not remove this commercial requirement. |
| WEB-01 / 03 / 04 / 06 | **OPEN** | Current code confirms concurrency/lifecycle/dispatch/readiness gaps below. |
| SEC-03 | **PARTIALLY IMPROVED, still OPEN** | Platform login throttling is implemented and freshly tested. Account disable is checked on requests. No complete MFA/recovery/per-session revocation lifecycle; public website sign-in lacks equivalent throttle. |
| SEC-05 | **PARTIALLY IMPROVED, still OPEN** | Portable backup encryption exists; device identity is excluded. Live PIN storage and device credential custody remain local plaintext/file protection. |
| OPS-01 / OPS-02 / OPS-03 | **OPEN with narrower gaps than old plan** | Fresh DB/native proofs now exist; physical qualification, production provenance/DR/updates/alerts and current supply-chain assessment remain. Prior ingress proof narrows OPS-02: loopback/default and opt-in native LAN allowlist exist; no fresh target-host exposure attestation. |
| EDGE-01 | **BLOCKED / deliberately unsupported** | Phase 0 one-primary fencing; Go Orders/Tables coordination remains shadow. No 3/10 operational writer claim. |
| Other P2/product work | **Deferred, not silently closed** | INV-01/02/04, MENU-05/07/08/10, MGR-06, UX-01/02, WEB-05/07, SEC-04/06, PROD-01/02 and TECH-01 still require their own scoped acceptance. Specific rechecked items are distinguished below; this audit is not a full UX or Inventory re-audit. |

[Prior-proof hash comparison](evidence/prior-proof-hash-check.json) is deliberately limited to recognized file-hash fields. It finds differences in older POS and Menu proofs, including expected later work; differences are **not** automatic regressions. For example, 356/382 recognized POS-05 hashes match, while 26 differ. It establishes why historical pass counts cannot be transferred wholesale to the entire dirty checkout. Zero recognized hashes means “not compared by this parser,” not “proof verified.”

## 3. Findings and release acceptance criteria

Severity means impact within the named scope. **P0** blocks that scope; **P1** is required before broader/unattended release or a stated feature promise; **P2** improves maintainability/product quality. Qualification gaps are explicitly called gaps.

### OPS-01.a / PROD-01 — No selected, immutable production candidate (P0, all deployment)

**CODE + RECORDED + GAP.** Current checkout contains unrelated WIP and an uncommitted POS-02 candidate. Recovery provides strong POS artifact traceability, but it is a development artifact. Compose uses `${IMAGE_TAG:-local}` and mutable base tags (`compose.yaml:3,50,60,70,80`; backend/frontend Dockerfiles). No checked-in `.github/workflows`, GitLab CI or Jenkins release gate was found. Existing proof does not identify a complete production backend/frontend/DB/POS/Edge combination.

**Acceptance:** a source manifest/approved commit plus explicitly included WIP, clean generated-contract check, lockfile/toolchain identities, migration names/checksums, immutable image digests, signed native hashes, runtime configuration identity and test results all refer to one candidate. A clean runner reproduces it without using arbitrary working-tree files. Separate Claude's platform work until its owner declares a candidate. Verify Docker Node 22 and the real Windows build toolchain, not just host Node 24/macOS compilation. Require review of exceptions; never relabel the existing development binary as production.

### POS-02 — Physical delivery and receipt policy remain unaccepted (P0, working POS)

**CODE + FRESH + RECORDED + GAP.** `print_job_repository.dart`, `print_queue.dart` and `printer_transport.dart` provide durable admission and uncertainty handling. `print_reconciliation.dart:10–23` defaults policy to `unconfigured`; receipt copy, paper confirmation and no-byte retry cannot be treated as finished workflows. Kitchen copies use authenticated Staff, fixed reason and stable action identity (`:54–61,101–121`). Printer configuration checks `DeveloperScope.printers` in `local_printer_catalog.dart:51` and `settings_repository.dart:427,477`; managers alone cannot configure it. Keep this requirement.

**Acceptance:** first repair the Windows launcher path handling with positive Windows canonical-path cases and negative wrong-owner/link/stale-output cases, without loosening provenance. Record the owner receipt/reconciliation decision as persisted, audited policy. Test the final signed artifact on supported physical x64 Windows and named printer model/firmware/driver/paper width: no paper, cable loss, partial transmission, spool/driver failure where applicable, power interruption, process kill and restart. Prove no automatic resend after uncertain writes, explicit labeled/audited copies and stable dedup. Keep kitchen Run/Cancel only. Do not add a free-text kitchen reason or manager configuration access. A VM or fake transport cannot close this gate.

### OPS-01.b — Address and metadata lifecycle can strand update/repair (P0, distributed POS)

**CODE + FRESH + RECORDED.** Installed feed and signed repair baseline are intentionally retained: `apps/edge/internal/setup/setup.go:235–251` reads the installation's distribution/repair URL and rejects changed baseline fields. Rerunning a newer installer is not endpoint migration. `updater/manifest.go:94,122` checks key expiry, manifest expiry, signatures, compatibility and monotonic release. Expiry is a trust boundary, not a defect to remove.

The October incident combined a saved `172.20.10.2` endpoint, server `10.10.10.3`, and September 28 metadata expiry. Recovery renewed through October 11 and migrated the installed feed. The lab publisher already supports same-artifact renewal (`publish_local_pos.py:197–201`; `local_windows_release_test.py:441–466`), freshly tested. It remains an invoked tool, not a verified unattended distribution/alert service; the watcher is off.

**Acceptance:**

- Use stable deployment-owned HTTPS DNS for production feed, immutable artifacts, repair metadata and API. Keep API configuration separate from feed configuration and tenant identity. Use a documented stable local name or approved explicit migration for the development lab; do not infer a trusted origin from arbitrary LAN discovery.
- Assign an operator/automation to check expiry and HTTPS reachability daily, renew before expiry and retain supported historical repair metadata/artifacts. A proposed operational policy is renewal at <=72 hours remaining, alert at <=48 hours and escalation at <=24 hours; owner must adopt actual thresholds. Automating signing requires a controlled signer, never embedding the private key in clients/public hosting.
- Renewal must verify the existing digest/size and retain version/release/product/channel/URLs. The tests already support this rule. Do not increment a version merely to refresh metadata or reset the client high-water mark.
- Exercise expiry, offline beyond expiry, skewed clock, DNS/server move, bad TLS, missing historical repair artifact, revoked/expired key and interrupted config migration. Existing POS must remain able to operate offline; update/repair failure must be distinguishable and diagnosable.
- A signed or locally authenticated, explicit endpoint migration must be traceable to reviewed source, preserve keys/identity/Hive path/anti-rollback state, update receipt and config consistently, and recover after interruption. The retained recovery helper is evidence of a successful repair, not a qualified production migration tool.

This is proposed implementation/operations work, not a newly scheduled renewal task.

### OPS-01.c — Binary rollback is narrower than safe application rollback (P0, versioned updates)

**CODE + GAP.** The updater admits protocol 1, Hive 9, Edge schema 2 and `hive9-no-migration` (`manifest.go:122`). It health-checks then rolls back binaries (`updater.go:616–657`), not data. POS startup recovers restore/print/ownership/transfer/Close Day/Menu state before normal use (`database_core.dart:211–238`); readiness checks include closure/ownership/Edge recovery (`pos_updater.dart:247–266`). These are useful controls.

However, MENU/POS durable formats evolved additively while Hive stayed v9. The manifest does not declare each local journal/backup/domain protocol or a minimum compatible reader. No exact N→N+1→N Windows data compatibility matrix for the proposed production release was found. A same-schema label or successful process heartbeat cannot establish it. This is a **proof/design gap**, not a reproduced data-loss incident.

**Acceptance:** one release compatibility manifest names backend/API contract, Menu capability/build floor, POS durable-format readers/writers, backup format, Hive/Edge schemas, Setup/Edge minimums and approved rollback destination. Prove update interruption and failed-start rollback with representative open orders, completed/pending closures/transfers, menu intents, uncertain printing and queued commands; compare quantities, amounts, identities and audit receipts. Do not install a binary unable to interpret retained state. For incompatible migrations, declare a forward-repair release and maintenance/recovery procedure instead of promising binary rollback. Retain anti-rollback counters. Edge self-update remains separate and unsupported by POS update consent.

The optional `MENU_CANONICAL_MIN_BUILD_*` policy exists in `menu-client-policy.ts:51–58`, but those keys are absent from Compose's explicit backend environment map. If the release depends on a build floor, wiring and testing it in the actual container configuration is required; adding it only to an env file does not pass it through automatically. Capability-only admission remains the current default.

### OPS-01.d / SEC-05 — Complete recovery and secret custody are not operationally proven (P0, real data)

**CODE + FRESH + GAP.** Portable format 2 is materially better than the old backup gap: 17 classified stores, encrypted export, recovery markers and restored-Venue checks exist. Device secrets remain outside the portable backup (`edge_device_credential_store.dart:8–20,108–116`). Fresh synthetic DB dump/restore and local POS tests pass.

Production docs still prescribe operator `pg_dump`/media tar and leave coordinated backup/PITR/keys/provider restoration open (`docs/DEPLOYMENT.md:395–447,473–480`). There is no supplied end-to-end proof restoring the chosen DB, website media and encryption keys, then replacing a physical Windows terminal and reconciling offline work. Current Compose shares one DB URL between migration and runtime; separate least-privilege identities remain provider work.

**Acceptance:** agree measurable RPO/RTO and retention, custodian and alternate custodian; back up DB/media/key versions consistently into encrypted separate storage; verify restore on a fresh target with media checksums and decryptable synthetic payment/PIN-vault records. Exercise Windows machine loss/replacement from encrypted POS backup, fresh Device enrollment and primary fencing with the old terminal held/revoked appropriately. Prove pending Menu/print/command/closure work and sales are preserved without double posting. Record restoration duration and audit results. Prove backups are usable without relying on the failed host's only copy of credentials/keys. Test additive upgrade from a representative previous DB as well as fresh migration. Never restore an old Cloud snapshot over newer acknowledged operations without explicit reconciliation.

### SEC-03 / SEC-05 / SEC-06 — Security baseline is incomplete for broad account/device use (P1; gates the affected pilot exposure)

**CODE + FRESH.** Principal boundaries are well established: Device→Venue, Staff→Venue, Host→VenueDomain→Venue, owner membership and separate PlatformUser. Platform tokens have audience/type/issuer checks and live disabled-account resolution (`platform-auth.service.ts`); readonly support writes are denied (`platform-auth.guard.ts`). Platform login now has IP/email limits (`platform-auth.controller.ts:37–57`), freshly tested. Production URL/secret checks and proxy trust are present (`shared/deployment-config.ts`). These improvements must not be lost in a rewrite.

Remaining verified limits:

- Hive opens without an encryption cipher (`database_core.dart:180–207`) and `User.pinCode` is a stored string (`models/user.dart:12–14`). Device credentials use per-user files, explicitly not an OS vault (`edge_device_credential_store.dart:16–20`). File ACLs do not protect against another process under that user.
- Website signup/signin (`website/auth/auth.controller.ts:38–67`) has CSRF/capability checks but no equivalent application throttle. Password update does not revoke previously issued access tokens (`auth.service.ts:174–188`). Platform has no complete MFA/per-session revocation/recovery lifecycle; account disable is a real containment control, not the same feature.
- EnrollmentRateLimiter stores counters in process memory. Multiple backend instances/restarts do not share one global limit. Do not claim horizontally consistent brute-force protection from current code.
- Privacy/retention/export/deletion and backup-expiry policies are not established by the selected release evidence. No legal compliance conclusion is made here.

**Acceptance:** keep public CUSTOMER_ACCOUNTS off until its throttle/session/recovery tests pass. Use restricted operator access and an agreed MFA/revocation policy before exposing cross-tenant administration broadly. For real pilot devices, implement OS-bound custody/encrypted local sensitive state with tested recovery, or explicitly approve a time-bounded controlled-device risk decision with full-disk encryption, unique non-admin OS login, verified ACLs, physical protection and recovery custody; do not call plaintext storage encrypted. Verify manager/waiter/developer boundaries through direct handlers and storage APIs as well as UI. Set data retention/support-access rules before real personal data onboarding. The authorized follow-up inspected local env values in memory for presence/classification only; secret values were not printed, copied into audit evidence or sent to npm. Referenced credential files were not opened.

### MGR-02 / MGR-05 / MGR-03 — Manager mutation outcomes are unsafe (P0, Manager operational writes)

**CODE + FRESH.** `mobile-dashboard.service.ts:482–513` frees only the Cloud table and returns success with no POS command. The fresh MGR-02 probe reproduces this. `mobile-orders.service.ts:192–205` deletes order lines then creates replacements individually; injected create failure leaves them absent. Dispatch happens later (`:358–383`), so simply wrapping the line replacement alone would not fix all Cloud/command failure windows.

Backend operations often return `posDelivery`, but clients still collapse outcomes: `mobile_api_service.dart:244–256` interprets any 200/201 as free-table success, even a `{success:false}` response. Cloud acceptance must not be displayed as authoritative POS completion.

**Acceptance:** one explicit intent/request identity, correct authoritative POS operation and durable Cloud queue boundary; typed QUEUED/CLAIMED/SUCCEEDED/FAILED/UNAVAILABLE/conflict responses; client follows final status and does not optimistically free a live table. Prove database error, duplicate request, offline POS, lost ACK, stale revisions and retry under real HTTP/PG plus native POS. A failed edit leaves a complete old or complete new state and a recoverable command disposition. For the smallest pilot, disable MANAGER_APP entirely. A read-only Manager pilot requires an explicitly enforced/tested server mode; no such general mode is assumed here. Hiding mutation buttons is insufficient. Keep POS operational authority and the Cloud→Edge pull model.

### MGR-01 / MGR-04 / COM-01 — Multi-restaurant Manager truth and package boundaries (P1 when offered)

**CODE.** Manager table filtering still uses fixed first-floor 1–9 / second-floor 1–4 sets (`mobile-dashboard.service.ts:34–37,149–157,459–466`). A legitimate restaurant layout can disappear. `mobile_api_service.dart:235–239` returns cached tables after a request failure without a freshness envelope. Owner catalog access still requires WEBSITE (`restaurant-foundation.service.ts:54–87`), so do not sell POS-only Dashboard Menu authoring as already available.

**Acceptance:** venue-owned table/floor identity with synthetic 1/13/30-table layouts, nonnumeric labels and multiple floors; API/POS source timestamps and last known completeness; explicit offline/stale rendering and write rules. Decide the POS-only catalog entitlement, then test that precise entitlement while preserving owner membership and menu-editing permission. Inventory history still contains `take:100` (`sale-consumption.service.ts:350`, `inventory.service.ts:367`); if complete searchable history is promised, add bounded pagination and 101+ record tests under INV-04.

### WEB-01 / WEB-03 / WEB-04 / WEB-06 — Paid reservations remain NO-GO (P0 for paid bookings; WEB-06 P1)

**CODE + FRESH.** Trusted pricing/ownership fixes do not complete payment lifecycle correctness:

- **WEB-01:** `reservation.service.ts:139–159` checks availability and then creates separately. `WebsiteReservationTable` only has `[reservationId,tableId]` uniqueness (`schema.prisma:1899–1908`), not a date/table hold constraint. Concurrent overbooking is a code-supported risk; this audit did not run a concurrent provider test.
- **WEB-03:** payment status commits before dispatch (`reservation.service.ts:405–435`); the bridge writes `posReservationId` before queue insertion (`website-pos-reservation-bridge.service.ts:231–257`). Fresh probe shows an enqueue failure after linkage leaves a confirmed booking that subsequent payment outcomes no longer hand off. Cancellation also catches/logs dispatch failure (`:281–309`); reconciliation must cover it.
- **WEB-04:** callback signatures are checked, but the status path does not compare expected paid amount/currency or record a durable provider event/state transition. It maps `partial_completed` and `auth_requested` directly to confirmation (`payment.controller.ts:195–215`, `reservation.service.ts:368–411`). The fresh probe shows CONFIRMED becoming PENDING on a delayed outcome. The billing receipt/event model elsewhere in Prisma is for Vynic subscriptions; its presence does not prove restaurant BOG reconciliation.
- **WEB-06:** readiness uses unordered `paymentIntegration.findFirst({venueId,provider:'BOG'})` without current enabled revision selection (`website-capabilities.service.ts:46–50`). Rotated integrations can yield inconsistent availability.

**Acceptance:** decide whole-day vs time-slot and late-payment policy; serialize/constraint-check holds; use trusted expected amount/currency and verified provider evidence; preserve every event with idempotency and legal monotonic transitions/refund semantics. Booking confirmation/linkage/durable dispatch must share a transaction or explicit recoverable outbox. Prove two simultaneous bookings, replay/out-of-order callback, partial/authorization-only payment, wrong amount/currency, timeout after provider success, queue failure, cancellation and integration rotation. Use provider sandbox only after code-level gates pass. Keep RESERVATIONS and ONLINE_PAYMENTS disabled server-side until accepted.

### EDGE-01 — More than one operational POS remains unsupported (P0 for multi-POS)

**CODE + RECORDED.** `backend/src/edge/operational-authority.ts:15–60` locks Venue and fences snapshot authority to one selected active Device. Separate Hive writers are not a shared operational database. Go Phase 2A observers/shadow coordination do not cover/fence the entire operational surface. Enrollment and multiple Menu writers are not evidence of multi-POS order/payment authority.

**Acceptance for first pilot:** exactly one operational POS and a controlled replacement procedure; exclude any extra live writer. **Acceptance later:** explicit selected Edge/epoch, all writer domains fenced, partition behavior, old-primary containment, handover/rollback, printer ownership, duplicate/reconnect semantics; three-device correctness before ten-device/load proof. Preserve this as a later EDGE-01 phase.

### OPS-03 / TECH-01 — Repeatable quality/supply-chain gate is missing (P1; minimal gate needed for first release)

**CODE + FRESH + GAP.** Dockerfiles use `npm ci`, lockfiles and non-root runtime, but base images are mutable and no automated monorepo release gate was found. Full TypeScript has five test-only diagnostics while runtime scope passes. Historical lint/advisory numbers from September 29/26 are not current measurements. The subsequently authorized backend production npm scan reports **13 affected dependency entries (11 high, 2 moderate, zero critical)**. Reachability is unassessed; frontend/Dart/Go/container coverage remains missing. The [follow-up review](CONFIGURATION_AND_DEPENDENCY_REVIEW.md) lists versions, scope, triage acceptance and why npm's suggested Prisma downgrade is not an approved fix.

**Acceptance:** before release, run scanner/SBOM checks for the exact JS, Dart, Go and image artifacts with authorized tools and triage reachability/severity. Record approved exceptions with owner/expiry. Pin deployable images by digest and archive signed provenance. A minimal gate runs changed-boundary tests, full runtime typecheck, contract drift, selected real DB isolation/upgrade tests and native release checks; quarantined baseline failures must be explicit and unrelated to the candidate. Fix the five test typing errors in their owning tasks rather than disable checking. CI can start with one serial verification script and an attended release job; no new orchestration platform is required for a one-site pilot.

### OPS-01.e — Operational visibility is insufficient for unattended release (P1; basic pilot monitoring required)

**CODE + GAP.** HealthController checks `SELECT 1`; proxy access logs identify routes; POS/Edge have local state/journal/errors and domain audit trails. No checked-in end-to-end alert/telemetry setup was found. A healthy process/DB does not report stalled command ACKs, old POS data, uncertain prints, restore failures or imminent feed expiry.

**Acceptance:** one support view/runbook can correlate release digest/version, Device/Venue, request/command/mutation/job IDs and source freshness without logging credentials or unnecessary guest data. Minimum alerts: backend/DB availability, backup age and failed restore check, feed/TLS/key expiry, blocked/failed update, long-lived failed/uncertain command and POS sync lag. Establish one incident owner, log retention and an operator export path. An attended pilot may use a small read-only checklist and alerts; broad unattended rollout requires automation. No new telemetry service was installed by this audit.

## 4. Product boundaries and feature-development safety

Keep the current modular monolith and local-first POS. There is no evidence-based reason here to introduce microservices, replace Hive, merge SAAS/CUSTOM frontends, move live restaurant authority to Cloud, or activate Go shadow authority.

| Boundary | Preserve | Small change that speeds safer work |
|---|---|---|
| POS local domain → persistence | Hive + shared admission; durable intents before acknowledgment; replay before business use | Declare each durable format's reader/writer version and fixtures; every new store must have backup/recovery classification. |
| Cloud → POS | persistent pull queue, request identity, local outcome journal | Shared typed operation-result envelope and one status UI adapter; feature code must distinguish accepted vs executed. |
| Backend tenant/principal | principal-derived Venue and explicit owner/platform separation | One negative-test fixture for each principal/route family; reusable transaction-aware domain entry points. |
| Manager | client of authoritative operational commands / Cloud-owned finance | Extract command-result and freshness handling before adding more mutating screens. |
| Web renderer → backend | Host-derived venue, capabilities, one backend, separate CUSTOM/SAAS rendering | Contract tests for disabled capabilities and actual published content; deployment identity for custom bindings (WEB-05). |
| Build → installed version | fixed POS/Manager entrypoints; signed manifests and source/artifact hashes | One machine-readable release dossier and release-candidate validation command. Promote the same bytes between qualification and release. |

There are substantial files—`pos_command_applier.dart` 1,452 lines, `manager_sync_service.dart` 1,798, `backup_repository.dart` 2,379, mobile controller 903, mobile orders 981, mobile dashboard 785 and subscription service 861. Size is a maintenance signal, not proof of a defect. Refactor only when the next feature touches that boundary, using behavior-preserving extraction and existing failure fixtures. First candidates: typed command results, domain-specific command handlers behind the existing applier, backup store codec/validation units behind the current format, and separated sync domain uploaders with unchanged acknowledgment ordering. Never combine extraction with a storage/protocol change.

A feature is ready to merge into a candidate when its owner has written: authority/principal, capability gate, failure/retry identity, durable-state impact, compatibility matrix, tests and rollback/disable behavior. Use a feature flag that can safely be disabled; do not use a flag to erase already accepted intents. Add only the contracts shared by real independent consumers to `packages/contracts`.

The current completed durability work is a useful foundation for faster development. Release discipline and narrow typed boundaries will improve speed more safely than a general folder rewrite or new feature freeze with no exit criteria.

## 5. Ordered implementation plan

This is the proposed replacement for the old plan's “start SEC-01” next action. It reuses backlog IDs; it does not create parallel feature roadmaps. No implementation in this table was performed during the audit.

| Order | Work / owner | Exit artifact and acceptance |
|---|---|---|
| 0 | **PROD-01 + OPS-01: owner/release lead** choose one-POS vs website-first and target infrastructure; confirm device/printers/card/receipt scope | One release scope sheet, deployment topology, support owner, explicitly disabled features. Identify RPO/RTO, certificate/signing/key custody and production origins. |
| 1 | **POS-02: POS owner** qualify runner and policy, then finish the existing candidate | Green Windows runner safety cases; approved persisted receipt policy; physical test matrix on supported device/printers. Keep developer-only config and kitchen Run/Cancel. A newly fixed launcher gets its own reviewed source identity; don't mutate sealed evidence. |
| 2 | **OPS-01/03 + TECH-01: release/backend owners** freeze selected source and build a minimal reproducible release gate | Clean owned checkout/export, signed source/artifact dossier, locked dependency/toolchain identities, authorized current scans, runtime builds and relevant tests; no unrelated platform WIP. Resolve release-affecting failures; track unrelated debt. |
| 3 | **OPS-01.b/c + SEC-05: release/POS owners** complete distribution and compatibility | Stable production HTTPS endpoints, Authenticode verification for Setup/Edge/POS with timestamped signing, separate Ed25519 feed trust, monitored renewal/expiry, reviewed endpoint migration and exact update/rollback fixture results. Keep lab roots separate. |
| 4 | **OPS-01.d + SEC-03/05: infrastructure/backend/POS owners** rehearse an isolated production-shaped deployment | Least-privilege DB/runtime roles, TLS/secret/media configuration, fresh+upgrade migration, DB/media/key recovery, physical POS replacement/enrollment/fencing and offline→reconnect reconciliation with measured RPO/RTO. No live data needed. |
| 5 | **OPS-01.e + PROD-01: release/support owners** run an attended acceptance day | Synthetic full shift: enroll/login, menu edit offline, order/change/transfer/close/receipt, Close Day, backend outage/reconnect, duplicate/lost ACK, app restart, supported update/rollback. Audit/amount/quantity invariants hold; alerts and operator runbook exercised. |
| 6 | **Controlled pilot approval** after the above evidence | First one-site release with exact artifact IDs, backup/restore receipt, trained operator and rollback/forward-repair decision. Pause on unexplained lost/duplicate money or order data, cross-Venue leakage, unresolved printer uncertainty, failed recovery or invalid update trust. No automatic rollout to more sites. |
| 7 | **MGR-02/05 → MGR-03/01/04 and COM-01** when expanding the package | Safe authoritative Manager commands, delivery/freshness truth, generic layout and decided catalog entitlement; real multi-surface acceptance before enabling it. Finance corrections/history claims need MGR-06/INV-04 work before being promised. |
| 8 | **WEB-01/03/04/06 + SEC-03** when paid booking/accounts are selected | Concurrency, durable outbox/event transitions, expected money, current provider revision, auth lifecycle and provider-sandbox reconciliation proofs; then a separate controlled payment pilot. |
| 9 | **EDGE-01 and full Inventory/product expansion** | Separate scoped phases; three-POS correctness before ten-POS scale. Full Inventory, new UX, KDS and automatic billing are not prerequisites for the constrained first deployment. |

For a **menu/contact-only website first**, omit POS hardware/update work from that website release, but still complete candidate provenance, Cloud security/DR/TLS, disabled-capability negative tests, actual SAAS/CUSTOM published content and browser/mobile acceptance. Validate WEB-02 against the target database state; keep paid reservations and customer accounts off. This audit did not requalify Claude's current platform web WIP, so it is not a ready-made website launch approval.

### Proposed staged-update policy

Start with an internal synthetic venue/device, then one attended restaurant/device, then a small explicitly selected cohort after a completed shift and restore/rollback review. Store cohort membership and promotion evidence outside ephemeral developer state. Current signed channel strings alone do not constitute a cohort/promotion system. Pause distribution by withholding promotion; never withdraw the only supported repair artifact or weaken signature/expiry/anti-rollback checks. POS installation remains explicit operator action, under the existing readiness gate. Allow enough offline support time to update returning devices through a qualified path.

## 6. Decisions still required

1. **First target and hosting:** one working POS, or menu/contact website first; production host/provider, DB/media storage, public/native/download domains and support owner. Provider-specific deployment work cannot be concretely qualified until these are selected.
2. **Printer/receipt policy:** exact supported hardware/driver, who may confirm paper/retry receipts, no-byte retry policy and acceptable manual fallback. Kitchen copies keep Run/Cancel with audit/dedup; configuration stays developer-only.
3. **Recovery and custody:** RPO/RTO, backup/password/key custody and replacement-device approval; local plaintext risk treatment for the limited pilot.
4. **Product contract:** single primary, manual card reconciliation, manual subscription billing, Inventory subset and excluded Manager/accounts/payment/multi-POS capabilities. Decide whether POS-only owner Menu authoring is promised.
5. **Signing/distribution:** certificate/key custodian, timestamping/signing environment, stable feed host, renewal/expiry owner and supported release/repair retention period.

No deployment-target answer has been received; target assumptions remain explicit. The user subsequently approved the bounded npm dependency-name/version disclosure; that scan is complete and its findings now require candidate-specific triage. The audit can be completed before the remaining target decisions. Implementation and actual deployment require the applicable decisions and evidence.

## 7. Deliverables and final audit checks

- This report: `docs/audits/2026-10-04-readiness/READINESS_AUDIT.md`.
- [Configuration and dependency follow-up](CONFIGURATION_AND_DEPENDENCY_REVIEW.md): authorized npm results and redacted env/build/runtime/install boundaries.
- Reproducible probes, fresh test output, synthetic PostgreSQL runner/proof, baseline and preservation evidence: `docs/audits/2026-10-04-readiness/evidence/`.
- [Validation summary](evidence/validation-summary.json) and [final preservation comparison](evidence/preservation.json) record exact outcomes and audit limitations.
- Existing master plan/backlog, project state and source were left intact; this scoped document reconciles their readiness claims without overwriting concurrent work.

**Assessment:** the project has enough implemented foundations to proceed with disciplined release preparation and scoped feature work. The smallest safe path is to finish POS-02 and the production release/recovery gates for one primary POS, then enable Manager, paid booking and multi-POS only through their separate acceptance gates. Focused green tests do not yet justify calling the application production-ready.
