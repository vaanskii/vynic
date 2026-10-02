# POS-01: Recoverable Close Day

**Status: DONE — 2026-10-02 (verified local implementation).**

Close Day now records a stable transition and resumes interrupted local work
before business writers are admitted. A failure after the date write can no
longer leave the new date open with the previous day's daily total. The change
is confined to POS-01 and passed final coordinator review. POS-03 transfer durability is documented in
[its runbook](POS03_CRASH_SAFE_ITEM_TRANSFER.md).

## Transition and admission

`CloseDayTransaction.run` captures the requested business date before waiting
for admission. The Admin confirmation passes the date it displayed, so an old
confirmation cannot close a subsequently selected or recovered day. Existing
active-Order and live-table checks remain inside exclusive admission.

`LocalDataAdmission` drains admitted actions and queues new actions before
their business-state reads or in-memory mutations. Its existing queue policy
is retained, including when the optional updater is disabled. Waiters recheck
the gate after release, covering immediately successive exclusive operations.
Close Day requests never acquire exclusive admission from inside a tracked
write. A second concurrent close reports failure without poisoning the first
owner's healthy transition.

The additive `meta.closeDayTransitionV1` value contains protocol version 1,
a UUID transition ID, fixed from/to dates, actor/source, start time, exact
Order/Table/Reservation targets, immutable audit snapshots, and the last
completed phase. Closed legacy Orders are rewritten and flushed before the
intent so adapter-generated UUID defaults become stable on disk. No generated
adapter is edited.

The durable phases are:

1. intent;
2. stale tables released;
3. reservations finalized;
4. operated date remembered;
5. date advanced;
6. daily total reset;
7. captured closed Orders archived;
8. remaining captured tables released;
9. completion audit stored;
10. completed.

Each phase flushes its effects before its receipt is flushed. Replay repeats
an unreceipted effect safely, using the same target date and captured identity.
It never computes another next day during recovery. The target is the next
calendar date, preserving UTC/local representation and wall-clock time rather
than adding 24 hours across a daylight-saving boundary.

Once an intent may have been written, a storage or validation failure latches
recovery failure **inside the exclusive operation**, before queued writers can
resume. The UI displays the concrete restart/recovery reason and exits the
loading dialog. Startup executes interrupted restore recovery, Close Day
recovery, then Menu recovery, migrations and defaults; workers and normal UI
admission follow startup. A malformed or incompatible journal fails closed.
Its digest detects corruption; it is not an authenticity or trust claim.

`AuditEventService.appendDurableOnce` writes and flushes deterministic audit
IDs derived from the transition ID. An existing event must match its action,
actor, entity, timestamp, device type and immutable data. Its existing synced
receipt is retained. A crash after audit append and before phase receipt
therefore neither duplicates the event nor loses its original details. Ordinary
best-effort logging remains unchanged. HTTP is never awaited under the Close
Day gate; the existing audit sync worker sends durable events afterward.

## Writer coverage

| Boundary | Admission scope |
| --- | --- |
| Business date selection and totals/history helpers | Entire `setCurrentDate`, `refreshDailySalesTotalForDate`, and `rememberOperatedBusinessDate` action |
| Order/Table repositories; cancellation and settlement | Existing `UpdateReadiness.track` actions share the same gate, including payment close |
| Order helper mutations | Admission precedes mutable Hive-object changes; helper saves are awaited |
| POS Menu and Order detail | Whole place-order, service-fee, advance/manual-adjustment and table-change actions |
| POS Home and Takeaway | Reserved-table activation and Takeaway settlement actions |
| Remote/Edge command execution | Existing command execution tracking drains before transition; queued creation reads the newly admitted date |
| Low-level Hive writes | Existing tracked boxes and model persistence remain a final shared boundary |
| Snapshot/restore | Existing exclusive admission; a restored pending Close Day finishes before restore releases writers |

The change preserves the established current-date blockers, genuine booking
classification and lifecycle, completed/no-show counts, original `system` /
`SYSTEM` reservation actor/source, completion operator/source, operated-date
history, and familiar `closeDayCompleted` entity/date/details. It adds the
stable `transitionId`. Only captured already-closed operational Order rows
are deleted; Sales and historical totals are not repriced or recreated.
Stale-table repair remains separate from the completion `tablesFreed` count.

## Existing data, portable backup and rollback

Hive remains database version 9. This is a primitive additive meta value, with
no new Hive box, adapter field, Cloud schema or wire contract. Existing Hive
without a journal opens without inventing a close or resetting its daily
total. True historical Order bytes missing UUID field 29 are covered by a
write/reopen fixture using the normal reader adapter.

MENU-01 format 2 already includes `meta` among its 17 stores. Completed and
pending transitions therefore survive a complete portable snapshot. Restore
validates the journal structure and pending business-date relation before
replacing stores, then replays the restored transition under existing
exclusive admission. A journal-less format 2 backup remains supported.
Incomplete legacy imports cannot replace a destination that contains Close
Day recovery state, matching the existing incomplete-history safeguards.
No journal or store version migration is performed on a healthy legacy file.

For a failed close, keep the complete data directory and restart with this or
a compatible newer binary. Successful replay finishes the same transition and
reopens admission. If replay still fails, retain the journal and the original
stores for repair; do not delete the marker or change the date to bypass it.

Older binaries ignore this new meta protocol and cannot safely complete a
pending transition. Binary rollback is only safe at a verified completed
boundary: use a compatible reader to confirm no pending journal and preserve a
complete backup first. A downgrade during pending recovery is not qualified
by this milestone. There is no destructive downgrade migration.

## Verification and evidence

Portable evidence and exact final source hashes are in
[`proofs/POS01_2026-10-02.json`](proofs/POS01_2026-10-02.json). The native checkpoint
matrix is preserved in
[`proofs/POS01_NATIVE_2026-10-02.json`](proofs/POS01_NATIVE_2026-10-02.json).
The isolated run's raw logs are under
`/private/tmp/vynic_pos01_aagr1iba/proof-output/`.

- A separate pristine-source property test confirmed the original bug: after
  a failed daily-total write and actual Hive reopen, the date was
  `2026-10-03` but the daily total remained `123` instead of `0`. The same
  harness passes on the final recovery core.
- Fault injection covers both sides of every actual put/delete/flush boundary
  in a representative multi-store close, followed by actual Hive reopen and
  repeat recovery. Admission tests cover local and remote creation, an already
  admitted real payment settlement, blocked creation, helper mutation,
  consecutive exclusive operations and simultaneous duplicate close.
- The native proof uses real Flutter/Hive child processes and SIGKILL at all
  88 boundaries, without closing Hive. Each reader has a different PID. It
  checks stable intent IDs where intent exists, one calendar-date advancement,
  one audit per captured event, preserved active/cancelled Orders and Sale,
  Reservation pre-status, recovery before Menu/migrations, repeat replay and
  stale-confirmation rejection. The harness flushes the stored prefix before
  signaling; this proves application interruption and replay, not arbitrary
  operating-system or filesystem corruption.
- Complete pending/completed portable restore, journal-less compatibility,
  valid-envelope journal corruption rejection, fail-closed startup and true
  missing-UUID legacy bytes are regression-tested. The widget checks exercise
  the displayed recovery reason, stale confirmation, route dismissal, loading
  text wrapping and normal toast dismissal without suppressing exceptions.
- Independent existing regressions passed 308 tests in 18 suites. Final
  changed-file formatting, analysis and focused checks are recorded in the
  proof.
- A native macOS POS debug build passed with `-t lib/main_pos.dart`,
  `APP_ROLE=pos` and `VYNIC_ENV=development`. The isolated build uses identical
  `pubspec.yaml` / lock content and the static macOS dependency lock. An initial
  missing generated Swift plugin package was resolved by offline `pub get`
  inside the owned build copy, without dependency drift. No normal app was
  launched and no source `.env` secrets were copied.

All fixtures use owned disposable directories and block application HTTP.
No customer Hive data, Vankisi operation, credentials, release feed,
deployment, push or merge was used. Source changes were prepared in an
isolated copy; integration and conditional local commit belong to the root
reviewer. Physical Windows replacement, power-loss/storage hardware,
and full release qualification remain OPS-01 work. Printer hardware is POS-02;
bank acquiring belongs to WEB-03/04/06 and SEC-03, with release evidence
collected in OPS-01.

After accepted POS-01, the linear sequence is POS-03 → POS-05 → POS-02 → SEC-05
→ OPS-01 → PROD-01. Those milestones are not part of this implementation.
