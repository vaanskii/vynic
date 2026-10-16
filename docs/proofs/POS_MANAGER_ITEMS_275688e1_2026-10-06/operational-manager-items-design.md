# Detached Manager retained-item replacement candidate

Source is frozen in `/tmp/vynic-readiness-20261006-a2nbcprb/source`. This candidate
adds only `manager_items_planner.dart`, `manager_items_adapter.dart`, and
`operational_manager_items_test.dart`. Ten protected existing library and test
files retain their starting SHA256 values. It has no production startup,
repository, model, ingress, queue, or physical-dispatch attachment.

## Admitted operation

The typed command replaces the complete additional-item list of an unsettled
pending or confirmed Order with quantities for a subset of its existing
`itemKey` and `lineUuid` pairs. It can reduce or increase retained quantities and
remove retained lines. Supplied UUIDs must match the complete canonical
preimage; planning and retries never mint IDs. New keys, ambiguous duplicate
keys, zero or invalid quantities, and replacements without quantity-diff events
are refused. Package snapshots remain unchanged.

The planner and adapter independently require the frozen Manager source and
fresh Staff permission. This is a detached proof admission rule. Authenticated
Manager command origin, trusted complete canonical capture, and Staff proof at
a future runtime ingress remain required; a caller's source string does not
establish production authority.

## Existing business behavior reused

The planner uses `OrderItem.fromJson` for line totals, `Order.recalculateTotal`
with the explicitly frozen service-fee rate, and the existing
`AuditOrderDiffService` for quantity audit events. It preserves every non-item
field except recomputed Order total and frozen `updatedAt`, including purchased
package snapshots, fee selection and override, payments, advance, discounts,
closure references, table ownership, and status. Current Package definitions
are dependencies rather than a source for repricing purchased snapshots.

The complete existing unlocked audit report is retained. Its existing event
prefix, order, sequence numbers, and business fields remain exact; new typed
quantity events receive the next sequence and the frozen time. Unknown complex
historical audit-detail shapes fail closed in this bounded mapper. No report
repair, implicit report creation, cancellation Sale, status event, or unrelated
GlobalAudit entry is introduced.

With unchanged service-fee selection and override, the existing Manager money
audit path returns early. This slice consequently emits no additional
MoneyAudit. POS-originated item changes are refused because their modification
PRINT effects are outside this candidate.

## Complete detached intent

The adapter reconstructs the typed command and repeats planner authorization,
provenance, business calculation, and exact complete-draft comparison. A
caller-supplied journal cannot alter price, metadata, financial fields,
ownership, status, event time, retained report prefix, or additional canonical
fields. Known foreign links are regenerated and compared with the original
canonical envelopes; they are not accepted merely because they name registered
identities.

The resulting request atomically writes complete ORDER and AUDIT_REPORT
postimages plus an unchanged OPERATIONAL_CONTROL postimage with its captured
revision CAS. Every admitted edit participates in that control fence. It also
retains one stable immutable AUDIT effect containing the exact newly appended
typed events. This is an effect receipt, with no replay append or dispatch.
Caller result data contains the typed complete Order result and no hidden
settings mutations.

Read dependencies retain the original frozen view revisions. They include the
control, Day, policy, Staff, complete Order/Table ownership scans and the
actual known Package, Advance, and other foreign references. Original and
resulting table ownership are checked with the existing pure integrity
validator. Fresh state cannot silently replace operator read revisions.

Limits are explicit: 1,000 input lines, 256 dependencies, signed int64 quantities
and revisions/sequences, complete-document and effect limits from the proof
domain, retained-effect capacity, and the complete 16 MiB request limit.
Overflow, ambiguous references, missing dependencies, unsupported shapes, or
capacity excess refuse the candidate before client preparation or transport.

## Legacy comparison and identity qualification

Three tests execute the actual `PosCommandApplier.updateOrder` against isolated
temporary Hive boxes, covering zero/global fee, a custom override, and purchased
packages. They compare complete business Order and report fields, verify exact
retained report history and ownership, and observe the unchanged-fee money
audit early return.

Two legacy boundaries are deliberately explicit in those comparisons. The
current Manager parser regenerates retained line UUIDs; this canonical proof
requires the original stable IDs. The existing command also samples more than
one wall-clock instant; this proof freezes one supplied instant. Tests normalize
only those generated UUIDs and new wall-clock fields, assert the legacy UUID
regeneration, and compare all remaining fields. Pure tests enforce exact stable
IDs and exact frozen time. Production parser and clock behavior are untouched;
stable identity admission remains a future integration gate.

## Qualification captured

The final eight selected suites passed **143 tests**, including **19 new tests**
(16 isolated pure/scripted/recovery tests and three actual local-Hive legacy
parity cases). The new tests include forbidden global fee/clock reads, canonical
and authority refusals, ready-client frame immutability with no transport on
invalid drafts, arithmetic/sequence overflow, complete scan capacity, three
scripted-client contention, and lost ACK followed by real isolated Hive reopen.
The scripted coordinator proves one accepted change and one retained effect;
it does not qualify Go, gRPC, LAN, or real terminal behavior.

Targeted analysis includes the entire operational proof directory and the new
test. Read-only formatting covers the two new library files and new test, with
zero changes. New-file whitespace checks pass. Captured validation logs,
three-file source manifest, independent Astra review, and exact receipt are
adjacent to this document. Astra found no P1/P2 issue in the identified bounded
source; its review inspected captured results and did not independently rerun
the tests.

## Remaining integration gates

This is a qualified detached retained-item candidate, not complete ORDER_UPDATE
or shared-writer production integration. Runtime ingress and command ACK,
trusted complete capture and Manager authority, stable legacy identity
admission, new-item canonical catalog quotes, metadata/price/fee/status/no-op
variants, POS modification PRINT effects, and the other mandatory writer
families remain pending. Full Go/wire, real three-terminal LAN, cutover,
handover, rollback, and physical-device qualification are outside this result.
