# MENU-01 — recoverable POS backup and fresh installation restore

Status: **DONE**, 2026-10-01 (Asia/Tbilisi). Native macOS process proof and focused regressions pass. This milestone implements backup/restore durability only. SEC-01, SEC-02, WEB-02 and MENU-02 remain completed; no later roadmap milestone is started. Evidence: [MENU01_2026-10-01.json](proofs/MENU01_2026-10-01.json).

## Baseline and scope

Branch: `codex/docker-deployment-foundation`. Starting HEAD: `e5997d63bb4da0bea4c0bcbcd6c3a79fff785cc5`. MENU-02 implementation: `a6da94a19ee293498ec0d01d0343e312a9c73dfb`; report/proof: `e5997d63bb4da0bea4c0bcbcd6c3a79fff785cc5`, [MENU02 report](MENU02_LOCAL_MENU_DURABILITY.md), [MENU02 proof](proofs/MENU02_2026-09-30.json).

Hive package remains 2.2.3; target data schema remains 9. Canonical wire format remains 2 and local Menu protocol remains 1. Previous backup was unversioned JSON; its `meta.db_version` described Hive, not a portable backup format. Additive historical variants carried `settingsAll` and `auditLogKeys`. New portable format is 2, deliberately distinct from Hive and Menu protocol versions. The fallback app version is pubspec `1.0.0+1`; packaging can supply `VYNIC_APP_VERSION`.

The initial dirty status and SHA-256 hashes of 556 existing WIP files were captured before edits. Implementation changes use 23 initially clean/new files. Only narrow new entries are added to the already dirty project state/map; their pre-existing hunks stay unstaged. No reset, stash, rebase, push, migration, generated contract change, production database or active POS storage access occurred. All Hive proof directories were newly created under temporary storage and removed by their harnesses.

Authoritative task sections were read in MASTER_BACKLOG, IMPLEMENTATION_ROADMAP, POS_MENU_EDGE, SECURITY_AND_RELIABILITY, EVIDENCE_AND_MATRICES, the Master Stabilization Plan and current MENU-02 material. Current implementation/tests determined behavior.

## Complete store inventory

A = durable business/recovery authority, B = rebuildable, C = installation secret/identity, D = ephemeral. Mixed stores need field-level handling. The search of production and tool Hive opens found **25 named stores: 23 runtime stores and two lab-only stores**. Format 2 includes 17 stores. No unknown box is implicitly assumed portable.

| Store | Class | Contents / writers | Loss / replay risk | Restore |
| --- | --- | --- | --- | --- |
| `meta` | A | Schema/migration facts; HiveMigrationService | Schema compatibility and restore receipts; No business replay; retain schema, filter installation-only receipt | Replace; receipt regenerated |
| `users` | A | Staff identities, roles, offline PINs; UserRepository/commands | Offline login/actor loss; sensitive PIN; Duplicate staff possible with append | Exact keys/values; encrypted portable export |
| `tables` | A | Layout occupancy and revisions; TableRepository/transactions/commands | Open occupancy lost; Duplicates/wrong occupancy with append | Exact keys, closure recovery |
| `orders` | A | Open/captured lines, closure IDs; OrderRepository/transactions/commands | Acknowledged work/money lost; Duplicate operational order/close | Exact keys and stable UUIDs |
| `packages` | A | Package catalog/captured identities; PackageRepository | Captured package definition lost; Duplicate catalog | Exact keys |
| `menu` | A/B | Legacy catalog or canonical projection; MenuRepository/MenuLocalStore | Legacy authority lost; canonical rebuildable; Duplicate/corrupt projection | Include; canonical rebuild from state+journal |
| `settings` | A/C/B | Business date/counters/config/Sale ACKs/profile intent; repositories/sync/security | Counter reuse/intent/config lost; Device secrets/authority cloned if wholesale | Filter device-local keys; preserve destination identity; retain business config |
| `sales` | A | Sale/advance/void/restore history, outbound ledger/consumption intent; SalesRepository/transactions/sync | Money/history and pending outbound lost; Duplicate financial effects if identities lost | Exact Hive keys, posSaleId/closureId/revisions |
| `expenses` | A | Local expense business records; ExpenseRepository | Financial data loss; Duplicate expense | Exact keys |
| `auditLog` | A | Order/venue/legacy audit and unsent revisions; audit services | Business provenance lost; Duplicate report/events | Exact keys |
| `errorLog` | D | Diagnostic errors; ErrorRepository | No authority lost; No business effect | Exclude; rebuild empty |
| `reservations` | A | Bookings/preorders/lifecycle; ReservationRepository/commands | Guest/preorder/advance context lost; Duplicate booking | Exact keys |
| `quickOrders` | A | Acknowledged saved cart drafts; QuickOrderRepository | Draft/order intent lost; Duplicate draft | Exact keys and draft IDs |
| `closureJournal` | A | Started/Sale-written/post-Sale/completed/reversed/abandoned; ClosureJournalRepository | Recorded Sale cannot finish cleanup/recovery; Duplicate close prevented by closureId | Exact keys; startup recoverPending |
| `inventoryCatalog` | B (include) | Cloud cached stock/recipes/features/inspection; InventoryRepository/InventoryCatalogSync | Cloud rebuildable, but offline captured consumption requires recipe cache; No authoritative stock replay | Include cached value for offline continuity, never Cloud ledger |
| `menuCanonical` | A | Cloud cursor/canonical/baseline/generation/v1 WAL; MenuLocalStore | Pending projection recovery/cursor lost; Wrong capture or lost intent | Drain/recover WAL before snapshot; exact keys |
| `menuMutationJournal` | A | Pending/retryable/conflict/rejected/synced IDs/revisions; MenuLocalStore/MenuMutationJournal | Acknowledged local intent lost; New IDs cause duplicate effects | Exact sequence keys, IDs and statuses |
| `edge_command_journal` | A | Payload-free command start/interrupted/terminal outcomes; EdgeCommandJournal/transport | Already executed effects may replay; Same command guard prevents repeat | Exact IDs/outcomes; startup settles running; original retention policy |
| `audit_sync_state` | B | Content-revision ACKs; AuditSyncState | Costs idempotent reupload, no data loss; Server report IDs/revisions converge | Exclude; clear destination ACKs |
| `staff_credential_sync_state` | B | PIN fingerprints ACKs; StaffCredentialSyncState | Costs Staff reupload; Server identity/fingerprint converges | Exclude; clear destination ACKs |
| `auth_tokens` | C | Manager JWT/login identity; AuthTokenService | Session sign-in required; Clones authenticated session | Exclude; sign in anew |
| `mobile_manager_cache` | B | Manager read models/TTLs; MobileCacheService | No POS authority; No operational writer | Exclude; Cloud refresh |
| `manager_preferences` | C/D | Manager selected Venue/backend/appearance; ManagerAppPreferences | Preference loss only; Stale selection risks UX, not server authority | Exclude |
| `coordination (tool only)` | D | Explicit Phase2A lab frame/outbox/diagnostics; OrderTableCoordinator | Not production restaurant authority; Lab replay only | Exclude; attached shadow makes backup refuse until detached |
| `outbox (tool only)` | D | Synthetic updater readiness tool primitive outbox; tool/pos_update_hive_proof.dart | No production authority; Lab-only | Exclude; never a production POS store |

`settings` includes business dates, local counters, layout/printers/language, totals, reporting configuration, runtime feature/cache values, pending Venue profile work and Sale ledger ACKs. Sale ledger IDs/revisions and consumption/reversal ACK/retry state live in the complete Sale maps and settings; there is no additional production Hive outbox to omit. `closureJournal` includes completed, reversed and abandoned lifecycle history as well as unfinished work.

Installation-only settings excluded from both portable store rows and compatibility settings are: `posIngestConnectionKey`, `developerTerminalId`, `developerClockHighWater`, `developerOtpTip`, `enrolledDeviceName`, `deviceRuntimeConfig`, `restoreVenueBinding`, `restoreSourceDeviceId`, `restoreLegacyIncomplete`. The last three become destination restore guards rather than imported source installation settings. Destination copies of installation settings survive in-place replacement. `meta.backupRestoreReceipt` is destination-local and regenerated.

Non-Hive artifacts are intentionally separate: `edge_device.json`/provisioning drop files, developer unlock/OTP files, updater host identity/high-water state, device-bound bootstrap staging and lab Edge SQLite/TLS pairing stores. They are not portable restaurant Hive authority and are never copied by this backup. The Phase 2A shadow must be detached before backup; no production multi-POS coordination is added.

## Previous gaps and format 2

The old JSON covered ordinary restaurant records and most settings, but omitted canonical Menu state/cursor/generation/journal, closure recovery and command outcomes. Restore appended some values rather than preserving keys. It could lose acknowledged Menu intent, strand cleanup after a recorded Sale, or forget a delivered command. Wholesale settings also copied local callback/developer identity. Order deserialization recalculated totals using destination pricing, and saved QuickOrder display names were omitted. Format 2 preserves captured totals and draft names.

The envelope contains product `vynic-pos`, `formatVersion: 2`, UTC creation time, app version, Hive schema 9, Menu local protocol 1, Venue/source Device display metadata, confidentiality flags, recovery completeness, compatibility requirements and an exact 17-store manifest. Every store has a row count and SHA-256 of canonical JSON. An envelope SHA-256 covers all fields except its own integrity field. Keys remain exact string/integer Hive keys. Tagged durable values preserve nested maps and primitive keys, lists, DateTime and Uint8List; unsupported values fail explicitly. Typed models use their existing serializers, with complete captured Order values retained. Sales preserve complete dynamic maps or tagged SaleRecord models.

Compatibility roots such as `settingsAll`, `auditLogKeys`, ordinary arrays and `errorLog: []` remain for existing readers/tests; authoritative restore uses keyed `stores`. Checksums cover compatibility roots too. Older readers lack the recovery guarantee and must not be used to perform machine replacement from this format.

Restore rejects unsupported format/product/schema/protocol, unknown/missing/duplicate manifest entries, malformed/duplicate Hive rows, wrong hashes, invalid typed records/captured prices, Menu Venue/protocol/sequence mismatches, unfinished Menu frames and invalid command/closure identities before modifying good data. Format 2 is replacement only; merging is explicitly refused.

## Consistency and recovery protocol

`LocalDataAdmission` is an always-active process-local gate, independent of updater enablement. Existing tracked repository/model/box operations drain; new root mutations wait. MenuLocalStore's complete queue operation owns admission, covering its WAL, journal, canonical state and projection. Nested writes belonging to an admitted operation can finish. Delayed callbacks cannot inherit a completed operation's permission.

A backup drains to a stable Menu boundary, ensures stable Sale identities, flushes the included Hive stores/journal, and detaches a complete payload while holding admission. It then releases admission before hashing, encryption and portable file writing. A two-second drain deadline reports a busy/retry error and releases admission. Cloud is unnecessary. Concurrent snapshots fail explicitly. Backup opens a previously closed command journal without pruning its present rows. The normal transport retention policy is unchanged.

This is a single POS process boundary, not a lock across independent POS installations. Menu HTTP runs outside the gate and merges into live state using the established MENU-02 queue. Existing operational root admission can include a slow local print/payment path; backup refuses on the bounded drain rather than waiting indefinitely.

Restore is recoverable in-place because current Hive ownership does not support swapping open directories. The order is:

1. Decode/decrypt, check all integrity/compatibility/model/Venue constraints and build the restore plan before destructive writes.
2. Acquire admission; recheck destination identity. By default capture/write a safety backup inside the same gate, so acknowledged work between an older backup and replacement has a copy.
3. Atomically write and flush `pos_restore_pending.json`: protocol 1, the complete validated payload, payload receipt, destination installation settings, actor/source, safety path and descriptor checksum. This local recovery descriptor contains sensitive data.
4. Replace exact keyed stores, flushing each; replace command outcomes and give restored executions a new run boundary, settling captured running work to interrupted immediately. Reset rebuildable audit/credential ACK stores.
5. Set restore Venue/source identity guards, initialize the existing Menu local protocol and run existing closure recovery. Write/flush the digest receipt and all included stores, then delete the marker.
6. Release admission and notify readers. The Admin flow no longer forces a Manager upload during recovery.

Failure after marker creation freezes new writes and reports an error. DatabaseCore loads local enrollment metadata and replays the marker before Menu recovery, migrations, defaults or UI. Replay replaces the same keyed values and reruns deterministic existing recovery. A damaged marker blocks startup/admission; it is retained for diagnosis. Recovery finishes forward; it does not claim automatic rollback. Preserve a damaged directory and restore a verified backup into another clean installation rather than deleting a marker and operating half-restored data.

Files use a flushed sibling `.staging` and rename. POSIX staging files receive mode 0600 before content. Existing staging collisions and disk/rename failures fail explicitly; staging cleanup does not overwrite a good file. Tests prove process interruption safety, not arbitrary power-loss/filesystem/controller durability or OS-directory fsync guarantees.

## Menu, money and commands

The shared Menu queue recovers/drains `localCommit`/`rebuilding` before snapshot. Backups carry canonical cursor/state/baseline, generation and every existing pending, failedRetryable, conflict, rejected and retained synced diagnostic row. Restore retains sequence keys, mutation IDs and decisions; it does not recapture the restored projection as new operator intent. An active paused WAL test proves backup waits and includes the acknowledged edit. MENU-02 fault tests remain passing.

The financial fixture records a real Sale while the journal still says `started`, alongside the closing Order/Table and a separate open Order. Existing ClosureRecoveryService recognizes Sale authority, completes post-Sale effects and clears occupancy without writing another Sale. Re-running recovery and restoring the same backup again produces no duplicate Sale. Stable Order UUIDs, Sale Hive keys, posSaleId, closureId, lifecycle revisions, original unit prices and outbound batches survive. Existing closure/cancel/consumption tests cover reversed/abandoned lifecycle and frozen inventory intent. If a required Order is absent or post-Sale effects cannot complete, the existing recovery routine retains a pending/deferred closure; restore preserves it without inventing a Sale or historical Order. Close Day is not redesigned.

Command backup includes payload-free command IDs, idempotency keys/types, first-seen/run identity, terminal outcomes and uncertain outcomes. Actual EdgeTransportService redelivery with mock HTTP verifies zero handler executions: completed work is acknowledged as already executed; an interrupted print becomes `interrupted_not_repeated`, requiring deliberate operator reconciliation. No physical printer or Cloud is contacted. The journal's ordinary seven-day terminal retention/5,000-entry ceiling remains a pre-existing boundary; backup preserves present rows and cannot recreate history already pruned. The existing ceiling can trim older nonterminal rows during normal transport open; that adjacent retention concern is deferred, and no unbounded historical exactly-once guarantee is claimed.

A successful restore writes a payload-digest receipt outside the portable snapshot. A second restore of that same payload is a no-op, preserving recovered/newer work and IDs. This detects accidental immediate repeats; restoring a different backup remains an explicit replacement operation.

## Confidentiality and device replacement procedure

Portable backup contains Staff raw PINs/roles, destructive-password hash/salt/hint, guest contacts/preorders/notes, receipt/Sale/financial details, audit actor identities and business configuration. Active Device credentials, provisioning secrets, Manager JWTs, developer identities and the local callback key are excluded. Source Device ID/Venue/name are nonsecret guard metadata, not tenant authority. Server authority still derives Device -> Venue.

Admin export requires a password of at least 12 characters and confirmation. AES-256-GCM authenticates/encrypts the entire payload using a random 12-byte salt and nonce, 16-byte tag and PBKDF2-HMAC-SHA256 with 210,000 iterations. Product/version/KDF/algorithm/iterations/salt are authenticated header data. Wrong password, ciphertext damage and invalid encryption metadata fail before restore. Passwords are not persisted. Keep the passphrase separately; there is no lost-key recovery.

The API explicitly permits passwordless local backups for protected safety/developer use. Those files, and the local restore marker, are **plaintext** despite checksums and POSIX 0600. SEC-05 still owns local Hive/PIN vault/device keystore hardening, production passphrase/key custody and managed recovery, Windows ACL qualification and wider secret lifecycle. Checksums alone are not authenticated provenance; password custody establishes the encrypted backup's authentication boundary. Encryption timing is outside backup mutation admission, but UI frame responsiveness was not benchmarked.

Fresh replacement runbook:

1. Stop the old operational POS and keep it stopped. Export through Admin with a separately retained passphrase; verify/copy the completed backup. Retain the old data and any uncertain-command evidence for reconciliation.
2. Install on the new machine using a fresh data directory. Do not copy `edge_device.json`, provision/developer/updater identity files or the old installation's callback key.
3. Restore restaurant data and enter the backup password. The storage API/proof supports offline restore before enrollment; the existing fresh-installer UI requires matching-Venue enrollment and Staff delivery to reach Admin, so enroll it as a secondary first when using that UI. Select the new primary only after restore. No first-run restore picker is added here. Offline Menu/financial recovery runs locally; the destination retains/generates its own installation ID and has no copied credential. Venue A data is refused in Venue B enrollment, conflicting local canonical/binding context, or ambiguous credential-without-Venue context.
4. Enroll the new installation for the same server-resolved Venue using existing enrollment. A later Device does not automatically become primary. An authorized operator selects it through the existing operational-primary action with the expected old Device ID and a reason.
5. Reconcile uncertain commands before deliberately reissuing work. Current replacement marks already-attempted nonterminal operational Cloud work `primary_replaced_outcome_unknown`; it does not silently transfer that uncertainty.
6. Disable/revoke the old Device through existing Platform Device management. Primary replacement fences its operational publication but does not itself revoke its credential; canonical Menu permits any ACTIVE enrolled Device. Verify the new selected primary and controlled sync before returning it to operation.

Old primary rejection is tested by invoking the current production replacement/authority functions with synthetic transaction state: before replacement old primary is allowed/new secondary denied; afterward old primary is denied/new primary allowed, cross-Venue and legacy contexts denied, uncertain work held and one operator audit recorded. This is a server-function test, not a new PostgreSQL integration proof. Existing Phase 0 row-lock/transaction authority remains unchanged. Cloud fencing cannot remotely stop offline work on the old machine or merge independent histories; physical retirement and operator control are required. EDGE-01 stays deferred.

## Old backups

Unversioned JSON exports with Hive schema at most 9, including curated settings, later `settingsAll` and optional audit keys, remain available through explicit **legacy incomplete import**. The UI warns that Menu/closure/command recovery journals are missing; API callers must pass `allowLegacyIncomplete: true`. Unsupported schema and malformed sections fail. Device-local settings are stripped. Legacy import refuses a destination containing canonical/journal/closure/command recovery state; use an isolated fresh installation for migration.

Missing pre-identity catalog, Order/OrderLine, Reservation, QuickOrder and Package IDs receive deterministic upgrade IDs based on payload/path before marker creation. Existing IDs remain. Missing historical timestamps use the legacy generated time or an explicit epoch fallback. This makes interruption/repeated import stable; it does not invent missing historical intent. Historical value-array Hive keys were never recorded and cannot be reconstructed exactly. Partial legacy merge is compatibility behavior and is not the format-2 completeness guarantee.

Legacy-imported or Venue-unknown data is locally recoverable but quarantined from credential-bearing Cloud sync. No automatic release invents a trusted historical Venue or missing recovery work. A controlled operator/data reconciliation is required; a generic release UI is outside this milestone. A new format-2 export can preserve the currently imported stores, but `legacy-history-incomplete` remains carried through subsequent backups/restores and cannot upgrade unknown past intent into a complete history.

## Validation and native proof

The final focused run passes **291 tests across 18 suites**, including 35 MENU-01 unit cases and two password-dialog widget cases. MENU-02 (41), canonical Menu (15), existing backup/audit, closure/money/cancel, stable identity, Sale ledger, command journal, startup/readiness and reservation/takeaway import regressions pass. Targeted analysis of all 21 changed Dart files reports no issues. `git diff --check` passes. Backend code/contracts are unchanged, so no backend PostgreSQL rerun was needed.

Boundary coverage A–G: stable, pending edit, conflict, paused local WAL/rebuilding, Sale with unfinished closure, pending outbound Sale, and immediate acknowledged edit. Failure coverage includes truncation, invalid JSON/encoding, wrong checksum, future format, missing store, envelope/nested Menu protocol mismatch, wrong Venue, invalid typed row/missing captured price, encryption/password damage, busy admission, disk rename failure, damaged marker and faults after clearing meta/users/orders/sales/closure/Menu canonical/Menu journal/settings. Eight clear-checkpoint cases reopen production startup and complete forward recovery; no half-restored active write admission is permitted.

`tool/prove_menu01_restore.py` launches real native Flutter/Hive processes against synthetic temp directories: writer PID 95186; fresh restorer PID 95296; interrupted restorer PID 95372; startup replay PID 95418. The restorer uses a different initially empty directory, restores the encrypted file, closes/reopens Hive and runs recovery. The crash restorer is paused after durable `sales.clear`, with marker present and Sales empty. The harness verifies it owns the PID through process ancestry, then sends SIGKILL without graceful Hive shutdown. Its runner exit 1 is expected. A separate startup process replays the marker, reopens and verifies the same identities/state. Actual HTTP is blocked throughout; command redelivery uses mock HTTP through the real transport.

Both destinations preserve cursor 15, generation 3, original pending/conflict/synced mutation IDs, prices 7 on captured Order/Sale, projected pending price 12 and conflict price 22. They contain exactly one Sale, completed closure, one pending outbound Sale, no Device credential, distinct fresh installation IDs, and Venue binding. Two delivered commands are skipped/acknowledged with zero handler executions. Same-backup repeated restore passes in both processes. Proof records backup/log hashes and temp cleanup.

| Dataset | Backup total / admission | Restore total / admission | File size |
| --- | --- | --- | --- |
| 500 menu items, 1,000 Sales | 165.435 ms / 23.737 ms | 415.594 ms / 288.001 ms | 1,326,348 bytes |
| Encrypted native fixture | 716.033 ms / 8.177 ms | 752.801 ms / 46.096 ms | 23,641 bytes |

The 500-item/1,000-Sale benchmark uses passwordless format 2 and restore with `backupBeforeRestore: false`; it measures capture/replacement, not a full user workflow with an additional safety copy. The separate native proof includes password encryption/decryption. These are individual synthetic measurements, not fleet or large-restaurant capacity claims.

Parallels CLI is present, but read-only `prlctl list --all --output uuid,name,status --json` returned an empty VM list for the current user. No Windows VM was started or modified. Windows machine replacement, filesystem/ACL behavior and release UI performance remain OPS-01 qualification.

## Files, commits and deferred scope

Implementation/test commit: `7493137` (`fix(pos): preserve recoverable state in versioned backups`). Documentation/proof commit is the focused commit containing this report. Full changed-file/source hashes and commands are in the JSON proof.

- `apps/operations/lib/apps/windows_pos/screens/admin_screen.dart`
- `apps/operations/lib/core/database/database_core.dart`
- `apps/operations/lib/core/database/repositories/backup_repository.dart`
- `apps/operations/lib/core/services/database_service.dart`
- `apps/operations/lib/core/services/edge/edge_command_journal.dart`
- `apps/operations/lib/core/services/edge/edge_device_credential_store.dart`
- `apps/operations/lib/core/services/menu/menu_local_store.dart`
- `apps/operations/lib/core/services/pos/update/update_readiness.dart`
- `apps/operations/lib/core/services/sync/audit_sync_state.dart`
- `apps/operations/lib/core/services/sync/staff_credential_sync_state.dart`
- `apps/operations/test/unit/backup_audit_restore_keys_test.dart`
- `apps/operations/test/unit/global_audit_test.dart`
- `apps/operations/test/unit/reservation_projection_test.dart`
- `apps/operations/test/unit/takeaway_order_source_test.dart`
- `apps/operations/test/unit/menu01_backup_restore_test.dart`
- `apps/operations/test/widget/backup_password_dialog_test.dart`
- `apps/operations/test/support/menu01_fixture.dart`
- `apps/operations/test/live/menu01_process_restore_test.dart`
- `apps/operations/lib/core/database/local_data_admission.dart`
- `apps/operations/lib/core/database/pos_backup_format.dart`
- `apps/operations/lib/apps/windows_pos/widgets/admin/backup_password_dialog.dart`
- `apps/operations/tool/prove_menu01_authority.cjs`
- `apps/operations/tool/prove_menu01_restore.py`

Docs: this report, `docs/proofs/MENU01_2026-10-01.json`, and narrowly updated `VYNIC_PROJECT_STATE.md`/`VYNIC_CODE_MAP.md`. Historical audit/decisions are not rewritten; unrelated WIP stays outside both commits. No push occurs.

Deferred: SEC-05 full secret/key lifecycle; OPS-01 Windows qualification; EDGE-01 independent-terminal coordination and existing retention-ceiling concern; POS-01 Close Day; MENU-03/05/06/07/08/09/10 and COM-01 (MENU-04 alias). No Inventory/Manager redesign or release/deployment was performed. **STOP after MENU-01.**
