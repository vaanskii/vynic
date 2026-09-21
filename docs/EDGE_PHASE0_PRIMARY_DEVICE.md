# Phase 0 — Primary POS containment

One Venue now stores `activeOperationalDeviceId`, a nullable, unique reference to
an existing Device. Enrollment and credential activity remain separate from
operational authority. A secondary Device can remain ACTIVE and authenticate;
that status does not grant permission to publish restaurant operations.

```text
1 Venue + 1 POS
→ works normally

1 Venue + multiple enrolled Devices
→ only the selected primary may act as operational authority until Go Edge coordination is implemented
```

This is temporary Cloud-side containment of independent Hive databases. It does
not coordinate multiple local POS terminals, merge their histories, remotely stop
an offline POS, or copy a database to a replacement. Hive/POS still owns live
operation without Internet. Operators must not use secondary installations as
independent working terminals.

## Admission and transactions

`edge/operational-authority.ts` is the admission boundary. Authenticated Device
→ Venue remains the tenant authority; payload Venue IDs never grant access.
The selected Device must also be ACTIVE. Missing or mismatched selection returns
HTTP 403 with `PRIMARY_POS_REQUIRED` on operational uploads.

The complete `POST /sync/manager-data` request is fenced, including realtime
snapshots, orders, tables, reservations, business-date rollover, menu, Staff,
expenses, summaries and sale ledger. `/sync/audit-reports`, `/sync/audit-logs`
and `/edge/inventory/consumption` are also fenced. Secondary Devices may still
read configuration/catalogs; profile/configuration ownership is not redesigned.

Each admitted HTTP upload holds the Venue row lock and uses one transaction-bound
Prisma client for all database writes. Menu and Staff transaction callbacks join
that transaction. A failed upload rolls back and leaves POS retry responsibility
unchanged. Reservation/audit write failures propagate within these transactions;
they cannot produce success ACKs for rolled-back writes. Snapshot/audit broadcasts
run after commit. Internal characterization calls without a transaction retain
their older partial-application behavior; they are not HTTP admission paths.

Enrollment, command claim/ACK and replacement use the same Venue row lock. A
replacement cannot pass an already-admitted upload and then receive stale writes
from it. Transactions have bounded timeouts: failure rolls back and the caller
retries; timeout never grants another Device access to uncommitted operations.

## Commands and legacy compatibility

- Only the selected primary can claim untargeted Venue commands.
- A primary can also claim commands specifically targeted to itself.
- A secondary can claim and acknowledge its own targeted `NOOP` diagnostics.
  Targeted business/printing commands wait until their Device is primary; they
  are unsafe against an independent secondary Hive store.
- Old-primary operational ACKs are refused after replacement.
- Replacement marks already-attempted, nonterminal operational work `FAILED`
  with `primary_replaced_outcome_unknown`. This includes pending retries and
  claimed work, so lease expiry cannot move a possibly executed intent into a
  different Hive store. Device-targeted NOOPs retain their diagnostic semantics.
  Unattempted untargeted work remains queued for the new primary.
- Operators must reconcile uncertain outcomes with the old local journal before
  deliberately issuing new work. Already delivered local actions cannot be
  recalled by a Cloud pointer change.
- The shared sync key remains accepted only for a Venue with **zero Device
  history**. It cannot bypass enrollment, ambiguous selection, or revocation.
- Any Device history routes new commands into Edge, even if every Device is
  disabled/revoked. It never restores legacy fallback. Old callback outbox work
  is held with `primary_pos_enrolled_reconcile_legacy_work`; no new legacy
  callback operation is introduced.

## Migration and enrollment

Migration `20260922120000_operational_primary` is additive: nullable reference,
unique index and foreign key with SET NULL on deletion. Normal lifecycle actions
retain Device identity. Service selection checks the target belongs to the Venue
and is ACTIVE. No Order identity or Hive migration is required.

Backfill counts **all historical Devices**, not only ACTIVE rows:

| Existing Devices | Backfill |
| --- | --- |
| Zero | Null; existing legacy single-POS operation remains available. |
| Exactly one, ACTIVE | That Device becomes primary. |
| Exactly one, DISABLED/REVOKED | Null; operator selection required after reactivation. |
| Multiple, regardless of status | Null; explicit selection required. |

Existing attempted work whose previous claimant is not the selected primary (or
whose claimant is unknown) is held with `primary_selection_outcome_unknown`.
A selected one-Device Venue's existing claim remains retryable as before.
No Device or business record is deleted by the migration.

For new Venues, creation/redemption of the first Device selects it inside the
same locked transaction. Later Devices remain secondary. Concurrent enrollment
serializes on the Venue; polling never elects a primary. Re-enrollment and secret
rotation do not replace an already-selected primary.

The migration does not inspect the live Vankisi deployment. Before production
rollout, inspect Device identities through the operator surface and arrange any
explicit selection/restoration. A zero-Device legacy Vankisi or sole-ACTIVE-Device
Vankisi follows the compatibility rules above; multiple historical Devices must
not be guessed from names, timestamps, or recent polling.

## Controlled replacement

Platform Admin → Venue → POS devices shows name, primary/secondary role,
credential status and last seen. Customer portal shows the same role and directs
owners to Vynic support; owners do not acquire cross-tenant Platform authority.

1. Stop the previous POS; preserve its Hive backup and execution journal.
2. Restore/verify the correct restaurant data on the replacement. Enrollment
   alone does not prepare the operational data.
3. Choose the ACTIVE replacement and confirm **Make Primary POS** in Platform.
4. Reconcile held commands and verify the replacement's first successful sync.

`PUT /platform/venues/:venueId/operational-primary` uses existing Platform auth
(including read-only Support restrictions), with:

```json
{
  "deviceId": "replacement-device-uuid",
  "expectedDeviceId": "current-primary-uuid-or-null",
  "previousPosStopped": true,
  "reason": "Previous POS stopped; replacement data restored and verified"
}
```

Use JSON null, not a string, when no primary is selected. The expected identity
is mandatory: stale operator requests return 409 and require refresh. An invalid,
inactive or foreign-Venue target returns 404. Missing stop confirmation returns
400. Change and `venue.operational_primary_changed` audit commit together, with
actor, Venue, old/new Device IDs, reason and count of uncertain commands. Failure
to persist audit rolls back the selection. The previous Device remains enrolled
with its identity/history, but is inactive for authoritative writes and claims.
Disabling the primary does not auto-promote another Device.

## Custom website and BOG boundary

`apps/venue-web` is the custom Vankisi website. Its current BOG integration and
related payment backend are not the Vynic restaurant SaaS website product.
Their one-restaurant assumptions are not SaaS defects. Neither the website nor
BOG integration is migrated or redesigned by Phase 0, and neither supplies the
tenancy model for the future generic product.

The generic SaaS restaurant website has not been built. Its intended operational
path is `Website → NestJS Cloud → durable Venue command → Vynic Edge → POS`.
Payment-provider callbacks and merchant/payment authority remain Cloud-side.
Website payments do not move through Go Edge.

## Next phases

```text
Phase 0: Primary Device fencing (this implementation)
Phase 1: Go Edge foundation
Phase 2: Go Edge becomes Venue-local multi-POS authority
```

The future Go runtime coordinates local terminals and durable ordered state;
this Cloud Device pointer does neither. Phase 1 still needs the approved service
identity/enrollment contract, authority handover rules, durable-state/recovery
contract, protocol versioning and Mac development harness. Go must remain
non-authoritative until Phase 2 has coordinated mutation/replay and cutover proof.
No Go, gRPC, SQLite, replication, printer/updater, financial or RBAC redesign is
included here.

## Verification

- `src/edge/operational-authority.integration.spec.ts`: real HTTP credentials,
  PostgreSQL snapshots/claims/replacement, cross-Venue isolation, rollback,
  in-flight serialization, legacy-key/outbox fencing and safe targeted NOOPs.
- Existing enrollment, Edge transport, dispatcher, enrolled sync, Platform and
  customer integration suites cover deployed-client compatibility.
- `src/test/devices-audit.integration.test.tsx` (Platform web): role labels,
  ambiguous selection and replacement confirmation/CAS body.
- To reproduce backfill evidence, create a disposable database, deploy migrations
  preceding Phase 0, run
  `test/fixtures/operational-primary-before.sql`, deploy Phase 0, then run
  `test/fixtures/operational-primary-after.sql` with `psql -v ON_ERROR_STOP=1`.
  Never run these fixtures against an application database.
- Validate migrations from empty, `prisma validate`, and `prisma migrate diff`
  against the final schema using a separate disposable database.
