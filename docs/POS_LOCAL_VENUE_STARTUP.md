# POS local Venue binding and startup

## Reported failure and verified cause

The reported `Stored Menu belongs to another Venue` exception comes from
`MenuLocalStore._checkVenue`: a persisted canonical Menu's Venue ID differs from
the loaded Device enrollment metadata. That check protects the restaurant's
local data and must remain fail-closed.

The prior enrollment path could store a new Venue identity without checking
the retained Menu. The existing checkout's local-binding work now validates
canonical state, baseline, pending local commit/projection/journal and restored
Venue ownership before saving enrollment and before startup recovery. This fix
preserves and qualifies those changes rather than replacing them.

The read-only macOS snapshot taken for this investigation already had matching
Device, canonical and baseline Venue IDs, sequence 0 and no Menu journal rows.
The original mismatching Menu ID was not captured, so the old conflict cannot be
reproduced from that later snapshot and no claim is made about who changed its
data. No live Hive file or credential was edited. The credential itself was
neither copied to the snapshot nor printed.

Three new red regression cases proved a separate identity reload defect: a
cleared, malformed or different-directory identity file could retain the prior
credential in static memory. A JSON parsing error could also include secret
file contents in its diagnostic.

## Current source behavior

- `DatabaseCore.open` opens the selected data directory, loads its Device
  identity and validates Venue binding before local restore/order/Menu recovery,
  migrations, defaults or startup workers.
- Identity reload starts with empty cached identity fields, including installation
  metadata. A missing/cleared/different file cannot inherit the previous Device
  credential. Malformed identity files are retained, and diagnostics report the
  error type without their contents. Existing offline startup semantics remain.
- `startPos` uses the identity already loaded during database opening and does
  not reload it after the restaurant data has been admitted.
- Menu mismatch still throws, using the shared typed `LocalVenueMismatch` with
  stored/target IDs and an explicit reconnect/backup/fresh-installation message.
- Foreign enrollment is refused before local credential memory/disk changes.
  Clearing credentials does not detach ownership of retained canonical or
  restored restaurant data. Same-Venue reconnects remain supported.

## Qualification

Evidence: `docs/proofs/POS_STARTUP_VENUE_3463ee40_2026-10-14/qualification.json`.

The focused Hive tests create only synthetic temporary data and forbid network
access. They retain a confirmed unpaid Order, its stable Order UUID, Table
ownership, captured item identity/price, an unresolved Menu edit and its
mutation ID across rejected foreign enrollment and cold-style Hive reopen.
Foreign startup and pending WAL projection ownership are refused before those
records change. Existing enrollment/local-binding/startup health tests also run.

The existing MENU-02 native-process proof kills only its owned synthetic writer
at the interrupted projection checkpoint and reopens with a different reader
process. A separate temporary macOS POS debug build is compiled without launch
or live-data access. Windows/hardware and a real running-app hot restart are not
qualified by these checks.

The complete Flutter run's four printer/POS-02 fixture failures were reproduced
with the task's three changed production Dart files restored in a private
before-task copy. Printer source/tests remain unchanged in the repository.
The non-printer selection and any retry results are recorded exactly; no full
aggregate PASS is claimed while those deferred fixtures fail.

Focused reproduction:

```sh
cd apps/operations
flutter test --no-pub \
  test/unit/edge_device_credential_store_test.dart \
  test/unit/local_venue_binding_test.dart \
  test/unit/pos_startup_venue_test.dart \
  test/unit/pos_enrollment_test.dart \
  test/unit/pos_startup_health_test.dart
```

## An installation that still has a real conflict

Keep its complete POS data directory and pending offline work. Reconnect to the
original Venue through the authorized enrollment flow. A different restaurant
needs a separate fresh installation/data directory and an explicit controlled
handoff. If the original Cloud Venue was deleted, support must decide that
recovery/handoff; changing local IDs to make the guard pass does not establish
tenant authority. The code fix prevents recurrence and provides an actionable
error, but does not silently repair an already mismatched real installation.

Next independent non-printer plan step: OPS-03 current dependency/advisory
inventory and build composition/provenance. Dependency upgrades, accepted
residual risk, deployment, session/MFA/recovery policy and unanswered inventory
business rules remain separate decisions or acceptance work.
