# Detached ordinary operational planner candidate

2026-10-06, isolated proof only. No normal startup, production writer, dispatch,
Cloud publication or LAN/RPC adapter is attached. This candidate is separate from
the existing Hive business owner and covers only the ordinary operations below.

## Delivered boundary

- `planning_view.dart`: immutable canonical projection at one operator cursor,
  pinned proof binding, actor/time/request, complete control/Day/policy/Staff
  dependencies, retained effect identities and explicit stable identity maps.
- `ordinary_planner.dart`: pure ordinary physical and takeaway create, physical
  move, and cancellation. It does not create IDs, read Hive or a wall clock,
  invoke a live mutation or print. Model totals and the existing ownership
  journal validator remain the calculation and validation owners.
- `intent_adapter.dart`: exhaustive conversion from a validated detached journal
  to one immutable proof request, typed exact caller outcome and explicit
  canonical references. It has no client/store/transport argument.
- Approved additive purity seam in `order_table_mutation_repository.dart`:
  optional `serviceFeeRate` flows through intent decode, plan/cancellation
  validation and cancellation Sale construction. Existing callers omit it and
  preserve their previous behavior. New planning requires a validated frozen
  policy value, including zero, and never falls back to the global fee resolver.

Canonical documents keep the complete legacy business image inside a versioned
Venue/key envelope with canonical foreign references. Numeric order IDs, Hive
keys, usernames, booking IDs and table labels remain compatibility fields. An
explicit resolver binds them to supplied UUIDs; it never derives canonical
identity from their values. Identity bootstrap and persistence across products
remain future qualification work, not an implicit capability of this fixture.

## Complete operation and dependencies

| Journal effect | Proof representation |
| --- | --- |
| `orders` | Complete ORDER postimage |
| `tables` | Complete TABLE postimage, including canonical owner/staff/booking refs |
| `settings:lastOrderId` | OPERATIONAL_CONTROL allocator; other settings refuse |
| `auditReport` | Complete mutable AUDIT_REPORT with retained event prefix |
| `auditEvent` | Frozen immutable AUDIT effect with supplied stable UUID |
| `reservation` | Complete RESERVATION postimage and exact canonical links |
| `sales` | Validated cancelled SALE subtype; ADVANCE/other subtypes refuse |

Every operation CAS-writes the original control revision, including move/cancel
without an allocator change. Creation allocates only `control.lastOrderId + 1`.
Control CAS fences complete collection scans, absent identities and phantoms.
Read dependencies retain the original control/Day/policy/actor, every scanned
Order/Table/Reservation (plus Sales for cancel), touched preimages, approver and
resolved foreign entities. A fresh view cannot substitute for original request
provenance. Unsupported effects/keys, missing or ambiguous identities, unfrozen
timestamps, changed policy/catalog provenance and atomic capacity overflow fail
before client preparation, durable frame writes or transport.

Cancellation keeps the non-fiscal zero-collection Sale and locked report as
historical business entities, updates a genuine linked booking with its immutable
audit, releases every owned physical Table and cancels the Order. Existing
cancelled Sale history is reused exactly. A legacy cancellation recovery prefix
returns `recoveryRequired`; this planner never invents replacement history.
Purchased package amounts remain frozen in the Order; references bind the
existing canonical Package without repricing that historical snapshot.

Takeaway creation preserves the existing no-fee behavior and request shape.
`takeaway/TA-N` is a virtual compatibility label bound to its canonical ORDER,
never a fabricated physical TABLE. Physical movement retains the existing POS
audit source. Any ambiguous ownership in the detached projection refuses this
bounded proof candidate and requires repair.

## Validation and limitations

Captured combined command passed 92 tests: 20 new planner cases, 46 proof-client
cases, and four legacy suites (`pos05_order_table_mutation`,
`pos05_ownership_recovery`, `pos05_independent_ownership`,
`cancel_order_transaction`). Analysis reported no issues. New pure tests install
no production Hive globals and make the global fee/clock resolvers throw. They
exercise complete effects, zero/nonzero fee, booking/cancelled Sale variants,
unsupported input without preparation, original provenance, capacity, three
scripted clients contending on control/number/table, and exact lost-ACK recovery
through a real isolated Hive reopen. The legacy suites retain existing default
behavior and actual local put/flush recovery boundaries.

The adapter counts every genuine linked booking before filtering already-cancelled
rows. A direct-adapter regression passes legacy journal decoding, then rejects
ambiguous active/cancelled linkage before client preparation.

The synthetic coordinator tests do not prove Go, generated RPC, LAN operation,
real terminal identity bootstrap, hardware printing, a production authority
transition or coverage of the full writer matrix.

## Unsupported remaining writers

Activation/package creation, edits/items/status, confirmation/printing,
transfer/split/merge, payment/closure, financial reversal/advance/expense,
standalone Reservation/Package/Day/policy/layout/Staff changes, remote ingress,
restore/import/repair, startup defaults/migrations and local execution recovery
remain separate required writer families. Terminal/closed lifecycle no-op
outcomes and legacy cancellation-prefix recovery are also outside this planner.
Large global policy and Close Day operations require a reviewed atomic mechanism;
the current bounded transaction cannot truncate or split them. See the complete
`source/docs/POS_MULTI_TERMINAL_WRITER_COVERAGE.md` matrix.
