# MGR-02: guarded Manager table repair

Manager repair now submits one immutable command to the selected primary POS.
Queued acceptance leaves the Cloud mirror unchanged. The Manager retains the
request UUID before HTTP and refreshes that same request after lost responses,
screen reopen or restart. It reports QUEUED, CLAIMED, SUCCEEDED, FAILED,
UNAVAILABLE or unknown explicitly; a 202 response alone is never completion.

## Authority and local safety

The authenticated current Manager Staff supplies Venue, actor and role. The
client supplies only the table alias and UUID for retry. The canonical table
UUID and expected occupancy come from the Cloud snapshot. An active selected
primary is required; repairs never use the frozen LAN callback fallback.

POS checks the saved canonical layout and exactly one physical table row. Any
nonterminal Order or nonfinal Reservation owning the table, directly or through
its aliases, blocks repair. Unknown statuses remain active; reservation dates
do not make a live reservation disappear. Stale occupancy refuses before intent.
Repair does not cancel an Order or Reservation and creates no Sale.

One flushed journal retains the before/after table images and immutable
TABLE_REPAIRED actor/reason audit. Writer admission serializes repair. Startup
and public backup restore finish a pending repair before admitting writers.
Snapshots reject missing/conflicting audits, changed canonical identity, invalid
phase images, business-date mismatch or overlapping pending mutations before
replacing destination data. Completed retries return the historical result and
preserve later normal occupancy, including after Edge journal pruning.

The authenticated POS ACK and Cloud projection share one PostgreSQL transaction.
The projection compares the original canonical identity, occupancy and snapshot
updatedAt. A delayed ACK preserves a newer snapshot. Terminal command retries
keep the first result; a lost ACK retains the table_repaired result code.

## Compatibility and rollback

TABLE_REPAIR is additive to contract v2. Older registries reject the unknown
command before mutation. No schema migration or generated file hand edit is
required. The local receipt uses the existing orderTableMutationV1 namespace
with a new tableRepair kind: older ownership readers reject it during startup
or backup validation. After repairs exist, rollback requires a reader supporting
this kind; disabling the Manager action does not remove its history. Never
delete retained receipts or audits to make a rollback start.

Manager request history is scoped by API origin and principal and contains no
token. A changed/logged-out/malformed session cannot send the displayed action;
late old-session completions cannot toast or navigate the new session.

## Verification

Run with the already installed toolchains and a clean Git export:

```sh
flutter test --no-pub test/unit/mgr02_table_repair_test.dart test/unit/mgr02_table_repair_request_test.dart test/unit/mgr02_edge_repair_test.dart test/unit/mgr02_manager_session_test.dart test/widget/mgr02_table_repair_status_test.dart
python3 tool/prove_mgr02_recovery.py --flutter /path/to/flutter --output /tmp/mgr02-restart.json
python3 tool/prove_mgr02_postgres.py --postgres-bin /path/to/postgresql/bin --output /tmp/mgr02-http.json
node packages/contracts/scripts/generate.mjs --check
```

The first two commands run from apps/operations; the PostgreSQL command runs
from apps/backend; generation runs from the repository root. PostgreSQL proof
creates/migrates/stops/removes its own synthetic loopback cluster. The native
proof checks all 24 table/journal/audit I/O boundaries using SIGKILL of verified
owned native children and recovery in a different process. Tests include live
ownership refusals, lost-response/ACK retry, pending public restore, hostile
snapshot rejection, missing audit, changed date, pruned journal and small/wide
Manager screens. Related POS-05/POS-03/backup/Edge/auth regressions also run.

Candidate and exact committed source receipts are stored in docs/proofs.
These are synthetic software proofs on the development host. Printer work is
deferred by the user; physical printer/Windows driver acceptance and held VM
qualification remain pending. MGR-03 broader delivery UI, MGR-05 atomic item
editing and OPS-01 release qualification are separate milestones.
