# POS-02.C — Flutter/local Go admission and business routing

**Status: IN_PROGRESS. Overall POS-02: NOT_DONE.**

The current plan is the sequential printer integration in
[VYNIC_ROADMAP.md](VYNIC_ROADMAP.md). A supplies production-purpose Go identity;
B supplies authenticated peer transport. This checkpoint implements C's detached
business-routing boundary. It does not complete C or activate printing.

## Implemented boundary

Go `Catalog.Planning(device)` derives a read-only Flutter projection from the
validated complete station catalog. It retains all routing rules, disabled
stations and foreign LOCAL stations, so filtering cannot silently select a
fallback. It supplies the exact scope-specific queue digest and compatible
rendering profile; physical addresses and controller identities are omitted.
The eventual API must derive `device` from authenticated enrollment and obtain
the catalog from current signed inventory. This function itself grants no rights.

Flutter `StationRoutingCatalog` validates the projection, expected content digest
and expected Venue/Device context. Routing uses explicit station overrides, item,
subcategory, category and default mappings; order-specific rules win within each
level. Unknown, disabled and foreign LOCAL destinations refuse the complete plan.
Output IDs match Go's Venue/effect/station/kind algorithm and do not depend on
the source terminal. Intentional fan-out emits a separate stable station output.

Rendering receives each station's compatible profile and ordered line subset.
Each plan renders once, defensively copies bytes and returns all frozen jobs or
an error. JSON, payload digests, Unicode escaping and job IDs match the existing
Go station domain exactly. A failed render cannot return a partial job list.
The plan is in memory: it is not a durable journal, an admission receipt, or an
atomic business transaction. No print job is persisted or sent by this layer.

## Validation

- 64 Flutter tests passed across station planning, existing physical-route
  planning, cluster envelopes and printer-agent client suites. This includes
  30 new station-planning tests and the existing actual child-process mutual-TLS
  health/admission-hold test, with its compiled Go fixture supplied.
- The complete Go station suite passed 38 test/subtest records with no skips.
  Nine actual Dart-to-Go scenarios cover routing, Georgian/HTML/line-separator
  escaping, mixed LOCAL/shared output, foreign LOCAL and malformed selection.
  Go independently parses and validates frozen Dart jobs, compares exact JSON
  bytes/digests, and verifies that repeated domain admission does not duplicate
  the job or advance its station sequence. This is domain admission, not durable
  service/Raft admission or a crash-recovery test.
- Targeted Flutter analysis, Dart formatting, Go formatting and Go vet passed.
  Independent static review found no actionable issues in the new boundary.
- Source hashes and Go test log: [proof packet](proofs/POS02_C_PLANNING_2026-10-13/proof.json).

Validation used synthetic data on macOS. No Windows, installed-service or physical
printer qualification is claimed. The missing temporary Go sources were restored
with Go 1.26.8 in a task-local directory; locked dependencies were resolved without
upgrading repository dependency versions.

## Exact continuation within C

1. Register and persist the Flutter-origin certificate against the correct
   Device, Flutter enrollment installation and separate Go service installation.
   Current health-client pins only authorize observation. Bind admission to
   signed production identity, generation/revocation and the existing offline
   grant policy; never promote a profile digest or isolated-proof credential.
2. Extend the authenticated loopback contract to read the planning projection
   and submit/query exact station jobs through existing LOCAL/shared Go queues.
   Preserve production identity checks and distinguish durable ACCEPTED from
   unknown outcome and physical delivery.
3. Persist complete frozen requests before the first send. Recover the exact
   original identity/bytes after Flutter exit or lost ACK, including partial
   multi-station acceptance; never render retries from current menu/settings.
4. Connect normal business entry points with stable menu/line/effect identities,
   using the existing Flutter renderers and explicit route admission. Prove
   missing identity, unavailable service, stale configuration and restart behavior
   without falling back into the old Hive writer.

Controller receipts/recovery/reconciliation remain D. Hive writer cutover,
rollback and automatic service lifecycle remain E. Live physical output remains
held until the applicable gates are qualified. Existing production Hive behavior,
generated contracts, enrollment, backend schema and older proof packets are
unchanged by this checkpoint. No commit or publication was performed.
