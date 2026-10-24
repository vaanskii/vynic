# POS-02 — durable print delivery

Status: **IMPLEMENTED_CANDIDATE / PHYSICAL_ACCEPTANCE_PENDING / NOT_DONE**.
Base commit: 275688e1. POS-02 changes remain uncommitted. This milestone requires
model-qualified physical proof; passing synthetic checks cannot close it.

## Durable admission and delivery

The POS flushes an immutable job to the existing Hive meta store under
print_job:v1:<id> before acknowledging admission. Each job records its target,
host/port, captured Venue binding, label, frozen ESC/POS payload and SHA-256,
attempt identities, and audit history. Hive stays at schema v9 and portable
backup format stays at v2 with its existing 17 stores.

The worker serializes kitchen and receipt work, including when both roles use
the same endpoint. It flushes sending before attempting a write. Connection
failures may retry only before any write attempt. An error after Socket.add
is uncertain, with no automatic retry or persistent-to-new-socket fallback.
A clean TCP flush/close records sent: **paper output remains unconfirmed**.
No model-specific printer ACK or Windows spooler/driver guarantee is claimed.

Startup changes sending to uncertain before business writers. Restored queued
work is held because the source terminal may still be operating. Venue changes,
including an unbound terminal becoming enrolled, hold the frozen job instead of
retagging it to a new Venue. The binding is checked again immediately before
Socket.add. Corrupt/unsupported jobs fail visibly before startup or restore
replacement; a persistence failure stops automatic delivery.

Initial Order confirmation uses OrderConfirmationPrint: frozen ticket admission
precedes confirmed-status persistence under the same mutation owner. The worker
checks the saved Order under that owner and again before sending. Interruption
leaves a pending Order, a durable held ticket, or one queued original. Concurrent
confirmations reuse the original Order UUID. Remote Order creation replays its
existing creation receipt to repair missing initial admission after a crash.
Existing jobs retain their frozen payload when an Order, menu, clock or printer
setting changes.

## Operator reconciliation

Home and printer administration expose the journal. It distinguishes queued,
sending, sent, uncertain, confirmed, copy queued and no-byte connection failure.
A sent ticket remains reachable for staff even when no uncertain jobs exist.

An operator paper check requires an authenticated, freshly resolved local Staff
identity, reason and stable request ID. A deliberate copy adds one flushed,
audited attempt to the original job and prints only the short `COPY` label.
Ordinary output has no technical header. Job/attempt IDs and delivery diagnostics
remain in the durable journal and application logs (and Windows spooler document
name), not customer/kitchen paper. The ASCII copy label is safe on supported
ESC/POS devices without assuming Georgian native text support. Uncertainty and
the paper-check decision remain in the operator flow. A no-byte failure permits a deliberate
retry of the same attempt. Replaying an accepted action adds no attempt or write,
including after a copy's connection failure/retry. Legacy Sale copies and manual
Order/reservation copies also require a labeled-copy prompt and recorded actor/
reason. They freeze the selected historical data at their own admission; they
do not claim to reconstruct an old paper payload that was never journaled.

**Owner policy is pending:** administrators only, or authenticated printing
staff. Current production default is unconfigured/read-only. Synthetic tests
set the policy explicitly in disposable fixtures. No owner policy has been
silently chosen for the real restaurant.

## Verification and limits

The candidate is a clean archive of the base commit with only POS-02 task files
overlaid; the original 267 unrelated WIP files are excluded. Evidence:
[POS02_CANDIDATE_275688e1_2026-10-02.json](proofs/POS02_CANDIDATE_275688e1_2026-10-02.json).

The synthetic transport accepts only synthetic.invalid:9100. Real HTTP is
blocked. Fixtures use owned temporary Hive directories, frozen test bytes and
synthetic Staff/Orders. Native proof checks the test child's process ancestry,
kills only that child, and verifies recovery in a different process without
writer cleanup. It flushes the completed storage prefix before signaling:
this establishes process-kill recovery, not arbitrary controller/storage power
loss. Physical printer power interruption is still untested.

The known 62-suite POS acceptance set is retained. Broad test discovery also
exposes existing fixture/environment failures in edge_transport_end_to_end,
inventory_projection_sync and the opt-in MENU09 live gate; these reproduce on
untouched HEAD. They are recorded as adjacent/deferred rather than changing the
network guard or providing live credentials for POS-02.

The macOS main_pos debug build is development compilation evidence. Its inherited
artifact display name is Vynic Manager.app; the compiled entrypoint and APP_ROLE
are POS. Windows executable/driver/device acceptance remains pending. The
Parallels Windows VM is held at the user's request.

## Minimum physical acceptance

Before any physical operation, the parent/user must supply:

1. Exact manufacturer/model, firmware, interface and paper width for every
   supported printer; Windows target architecture and driver/version where used.
2. Which device is kitchen, receipt or bar, and its intended endpoint/port.
   Current software roles are kitchen/receipt; bar and shared-printer routing
   require the later EDGE-01 design.
3. A separate noncustomer test unit/queue, or an explicitly approved maintenance
   window and exact test target. Existing production printers stay connected;
   the currently known live endpoints have not been probed or used.
4. The operator reconciliation policy and who can approve paper checks/copies.

For each supported model, use synthetic tickets clearly marked TEST / DO NOT
PREPARE and retain the job IDs, attempt/audit records, device/firmware details,
timestamps, observed slip counts and photos:

| Case | Required observation |
| --- | --- |
| Normal Georgian 80mm output | Correct glyphs, wrapping, totals/comments, feed and cut; no production diagnostic header. Test-only fixtures explicitly include their evidence ID; TCP sent still awaits paper check |
| Paper-out before/during send, then refill | Observed device behavior; sent/uncertain stays visible; no automatic duplicate after refill/restart |
| Cable interruption during transmission | Actual slip count/content and uncertain/no-byte state; no write retry after uncertainty |
| Printer power loss during transmission | Actual slip count/content after power recovery; no automatic duplicate |
| POS process kill before send and during send | Durable job recovered; sending held uncertain; observed paper compared with journal |
| Deliberate copy and repeated submit | Exactly one new labeled copy attempt, correct frozen content, actor/reason audit; repeated request adds no write |
| Windows/driver path | Tested native target and actual interface; no unsupported driver/USB/spooler acceptance inferred from macOS/raw TCP |
| Two configured roles on one endpoint | Sequential complete tickets; no interleaving within this POS process |

Reset paper/cable/power only on the approved test device. Do not interrupt live
restaurant work. Record model-specific status/ACK capability before considering
a stronger transport protocol. Do not represent raw TCP acceptance as physical
exactly-once printing.

After these milestone checks pass and the owner policy is resolved, validate
the final exact locally committed runtime again. Local commit is conditionally
authorized only at DONE. No push, deployment, merge, install or VM action is
authorized by this runbook.

## Existing Go and later plan mapping

EDGE-01 / Track G remains the planned multi-POS phase (3 terminals, then 10).
Go already supplies SQLite/WAL identity and session storage, authenticated TLS
gRPC infrastructure, shadow request deduplication, revisions, epochs, durable
events and snapshot/replay APIs in apps/edge/internal/store and internal/server.
The foundation currently grants shadow authority; it does not own production
restaurant writes or printer connections.

A shared kitchen/bar printer needs one durable sender per physical printer,
immutable request/payload identity, sequential admission and sender fencing
during authority handoff/partition. Reuse the existing Go foundation when that
phase is authorized, while preserving the POS domain rules and explicit cutover.
Owner/onboarding printer configuration is per Device; Platform Admin has no
print-job delivery projection. A later authenticated projection can show job/
attempt state and last-sync age without Cloud dialing LAN printers or asserting
paper confirmation. No Go authority migration, shared-printer service or Admin
status API is included in POS-02.
