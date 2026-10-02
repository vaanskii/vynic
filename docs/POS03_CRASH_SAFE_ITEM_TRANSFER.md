# POS-03: Crash-safe Order item transfer

**Status: DONE — 2026-10-02 (verified local implementation).**

The POS now journals an item transfer before changing either bill. The same
operation finishes both Order audits and any empty-source cleanup. Startup
resumes a pending transfer before Menu recovery, migrations, defaults or
business writers. This milestone changes only POS-03; POS-05 is next.

POS is Windows-first. Manager targets Windows, macOS, Android and iOS. The
macOS build and native crash matrix below are development-host evidence;
Windows release/device qualification remains an OPS-01 release gate. No
Manager feature or runtime is changed here.

## Request, admission and durability

`OrderItemTransfer.apply` captures a deep, lossless source/destination snapshot,
index/quantity selection, actor/source, labels and expected business date
synchronously, before awaiting admission. The operator screen clones the
source before opening its picker and passes the displayed business date.
Under `LocalDataAdmission.exclusive`, the coordinator drains earlier writers,
then revalidates the persisted Order IDs, UUIDs, images, date, audit lock and
table ownership. Later writers queue using the existing POS-01 policy.
Transfer, Close Day and portable backup/restore cannot interleave. The updater
reports the transfer operation/failure through its existing readiness gate.

The additive primitive records live at `meta.orderTransferV1:<transferId>`.
Each protocol-v1 record holds a stable UUID, immutable request fingerprint,
before/after images, fixed timestamps, ordered effects, last confirmed effect
and recorded result. The digest detects damage; it is not a trust claim.
Legacy Order and line identities are persisted and flushed before intent.
Journal images normalize native Hive DateTimes to millisecond precision, so
cached microsecond timestamps compare identically after a process restart.

The effect sequence for a whole-bill transfer is:

1. durable intent;
2. destination Order, then source Order;
3. destination and source `MOVE_ITEMS` reports;
4. each exact owned source table released;
5. each genuine linked Reservation completed with its stable audit;
6. empty source Order closed;
7. source `TRANSFER_CLOSE` report stored and locked;
8. durable completed receipt.

Each effect is flushed before its phase receipt is flushed. Recovery accepts
the confirmed prefix and only the next effect's before/after image, covering
an interrupted write before its receipt. It never reapplies a completed
record's old images over later ordinary changes. Unsupported versions,
malformed plans, multiple pending transfers, changed identities or incompatible
pending images fail closed. After intent may have been written, failure is
latched inside exclusive admission before waiting writers resume. A concurrent
request cannot poison another healthy owner. UI refusals distinguish stale
selection, busy admission, ownership/locked history and required recovery.

An exact caller retry retains the transfer ID and original immutable payload.
It returns the completed result without another audit or bill write. Reusing
an ID with different selection, images, actor or labels is refused. Callers
that omit an explicit expected date reuse the recorded date for an exact ID
retry; a fresh transfer still validates the synchronously captured current
date. Explicit expected-date callers retain their original date on retry.

`releaseEmptiedOrder` remains a compatibility entrypoint. New transfers already
complete cleanup; a later call is a no-op. A genuinely empty legacy Order uses
the same durable coordinator. Tables are released only when owned by the exact
source Order; virtual Takeaway rows remain untouched. Genuine bookings are
completed without cancelling bookkeeping rows or changing their original
guest details/link. No Sale, payment or fiscal close is created.

## Frozen value, history and writer coverage

The existing transfer arithmetic splits a stored line total and preserves its
sum, menu/variant/comment identity and existing merge rules. It does not look
up current menu prices. Order creation/ownership, package lines and pricing,
advance fields, guest details, edge identity/revision and prior audit history
are preserved. A package line is not selected by the ordinary-item picker and
prevents an Order with remaining package items from being considered empty.

Each moved line has exactly one `MOVE_ITEMS` event on each report, with the
same transfer ID, ordinal, quantity/value and immutable identities. An emptied
source has exactly one additional `TRANSFER_CLOSE`, locked and non-fiscal.
Reservation audits use IDs derived from the transfer ID and strict durable
append, retaining existing sync acknowledgement. A crash between audit write
and receipt cannot duplicate an event. Post-commit sync notification failure
logs an error and leaves the confirmed transfer result successful. HTTP is
not awaited under admission. The explicit development Order/Table shadow
observes committed state outside admission; terminal cleanup remains outside
its established ordinary-open Phase 2A codec and produces diagnostics.

The operational caller is the Order detail picker; it now calls only `apply`
for transfer and cleanup. Both persistent public methods converge on this
coordinator. Pure `move` is in-memory arithmetic only. Existing domain/model/
remote/payment writers share POS-01 admission, while general concurrent-write
serialization remains POS-05. Creating a previously absent destination still
precedes transfer admission: interruption before intent may leave an empty
new destination, but never claims that source items moved.
An old retained Hive Order handle is detached after the coordinator replaces
its stored image. A queued helper using that stale handle is explicitly refused
and cannot overwrite either committed bill; recovery stays healthy. General
writer handle revalidation remains POS-05. The screen reloads fresh stored
Orders after completion, as covered by its interaction test.

## Existing data, backup and rollback

Hive remains version 9, with no new box, generated adapter edit, Cloud schema
or backend contract. Existing files without a transfer journal open normally.
Format-2 complete backup already includes `meta` and preserves pending and
completed records. Restore validates structure, request/before identity,
conservation, exact audit snapshots and pending store/date images before
replacement, then replays under its exclusive gate before admitting writers.
Completed retry records permit newer Order images in a complete snapshot.
Incomplete legacy imports cannot replace a destination with transfer records.

The complete Order snapshot codec now preserves stored ordinary/package line
totals as well as all Order fields. The previous format-2 decoder multiplied
unit price by quantity, which lost legitimate frozen totals. The legacy loose
JSON import keeps its existing recalculation behavior; historical Sale maps
are untouched. Tests write actual Hive bytes missing Order UUID field 29 and
line UUID field 8, then reopen using unchanged production adapters.

Keep the complete data directory after failure and restart with this or a
compatible newer binary. If replay fails, retain the intent and all original
stores for repair. Deleting the marker, changing identities or restoring an
incomplete export to bypass recovery is unsupported. Older binaries do not
understand a pending protocol-v1 transfer. Downgrade during pending recovery
is unqualified; confirm completed recovery and preserve a complete backup
before a binary rollback. Completed receipts are retained for retry identity;
this milestone introduces no pruning policy.

## Evidence and limits

Portable evidence, exact commands, hashes and final counts are in
[`proofs/POS03_2026-10-02.json`](proofs/POS03_2026-10-02.json). The native matrix is
[`proofs/POS03_NATIVE_2026-10-02.json`](proofs/POS03_NATIVE_2026-10-02.json).
Raw owned-workspace logs are under `proof-output/` in the isolated POS-03 copy.

An independent pre-POS03 source test confirmed the old failure: after the
destination write and source failure, actual Hive reopen held seven units and
1,751 cents instead of five units and 1,251 cents. The unchanged harness passes
on final runtime code. Independent admission checks and existing regressions
also pass. Focused tests cover every put/flush boundary, queued-writer denial,
duplicate transfer/Close Day/backup contention, immutable stale selection,
completed retries after edits/date changes, locked reports, ownership,
Takeaway, lossless partial transfers, corrupted startup and compatibility.

The native matrix uses real Flutter/Hive children and SIGKILL at all 88
before/after put/flush boundaries, without closing Hive. Readers have different
PIDs and verify stable ID, five units/1,251 cents, exact audits, table/reservation
cleanup, no Sale, unchanged history/date, repeat recovery and exact retry.
The harness flushes the completed prefix before signalling; it proves process
interruption/replay, not arbitrary filesystem corruption or power-loss physics.
All fixtures are synthetic, HTTP is blocked and no normal customer app is
launched. A macOS debug build uses the actual `lib/main_pos.dart` entrypoint.
It neither deploys nor qualifies Windows production hardware.
The runnable Windows/Parallels smoke checklist is
[`POS03_WINDOWS_SMOKE.md`](POS03_WINDOWS_SMOKE.md). Windows execution remains
pending unless its own recorded evidence confirms a run; the VM is held on the
user's instruction. Full hardware acceptance follows the remaining plan.

The short Windows checkpoint is pending; follow
[the Windows smoke guide](POS03_WINDOWS_SMOKE.md) and record its actual result.
Remaining linear work is POS-05 -> POS-02 -> SEC-05 -> OPS-01 -> PROD-01.
Printer hardware belongs to POS-02; bank acquiring remains WEB-03/04/06,
SEC-03 and OPS-01 release qualification. None is started by POS-03.
