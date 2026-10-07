# MGR-05 — recoverable Manager order editing

Status: milestone acceptance passed on the owned candidate; exact committed qualification follows the owned runtime commit.

## Operational boundary

The Manager freezes a stable request UUID, original POS projection/fingerprint,
stable line identities, requested quantities/prices/comments and fee choice in
its own flushed Hive journal before HTTP. The server resolves current Staff and
Venue and queues one immutable `ORDER_EDIT` command to the selected active POS.
HTTP 202 and QUEUED/CLAIMED are pending delivery; the Cloud Order, lines and
Table bills stay unchanged at admission. Cloud never calls a restaurant LAN.

The guarded endpoint is `POST /mobile/order/:id/edit-request`. An old Cloud has
no such route and cannot interpret a retained retry as its historical blind
`ORDER_UPDATE`. The upgraded historical route uses the same strict validation;
old bodies cannot delete/recreate lines or dispatch unguarded work. Old POS
registries refuse the additive type before mutation. Existing v1/v2 commands
and the frozen legacy LAN callback keep their previous behavior.

The complete DTO is validated before queueing. Stable line UUIDs are unique;
menu keys can repeat for different notes. Quantities are positive integers,
prices/totals are finite bounded cent values, and edited line totals must match
quantity times price. An unchanged historical line retains its exact original
hand-priced total. Client tenant/actor fields provide no authority.

## POS durability and exact result

`OrderEditRepository` shares the POS admission barrier and records a sealed
before/after intent in the existing fail-closed mutation namespace. It verifies
active status, business date, UUID, complete baseline and Table ownership before
intent. Order, Order audit report and durable Staff-attributed audit effects each
flush before the next phase; a final immutable receipt retains the exact result.
A failed write blocks business mutation until startup or public restore recovery
settles it. Backup validation rejects conflicting/corrupt receipts and forged
successful transport results before replacing data. Hive remains version 9.

Recovery runs before other ownership/transfer/day writers. An interrupted edit
stays unresolved on Edge rather than receiving a terminal failure ACK. This
also covers transport completion persistence failing after business success.
A retry reconstructs the original result from the business receipt even after
transport pruning or a later POS edit. It never overwrites that later edit.

The projection carries one canonical, lossless Order image string, its SHA-256,
Order UUID and actual effective service-fee percentage. It preserves package
lines, advances, historical adjustments, stable line UUIDs and comments. Times
are normalized to Hive millisecond precision. Default fees are resolved by POS,
including values other than 10 percent, and retained results keep that percentage
after a later setting change. Ordinary Order JSON is not the edit baseline.

Only an authenticated `order_edited` result atomically projects the complete
Cloud Order/line replacement and original Table bills in the same ACK transaction.
The original projection fingerprint, Cloud row revision and Table revisions are
comparison guards; later snapshots, closing and table-only changes win over a
delayed ACK. A snapshot omitting the modern projection clears stale edit authority.
Device identity survives the actual HTTP ingestion boundary and is never read
from the payload.

## Manager outcomes

The editor and detail-screen fee actions retain frozen drafts and delivery
status across navigation. Saved feedback and editor completion require a valid
SUCCEEDED POS result; pending, rejected, unavailable and unknown outcomes stay
visible. Unsent drafts survive remote refresh. Session/origin/Venue changes
cannot retarget the displayed Order, including while HTTP/Hive/dialog work awaits.

A failed result flush shadows optimistic Hive state as unknown with the original
request UUID. Retrying flushes intent before HTTP and preserves the frozen body.
A durable completed original draft returns its retained result without another
request; a new edit of a fresh POS result allocates a new UUID/fingerprint.
Terminal lease-exhaustion or primary-replacement uncertainty asks for POS
reconciliation and preserves the draft. It does not claim POS rejection or
permit blind discard/resubmit. Broader MGR-03 delivery/reconciliation policy is
separate. Discard write errors stay visible and preserve the displayed draft.

## Qualification and limits

Tests use synthetic Staff/Orders, fresh temporary Hive, and guarded owned
loopback HTTP/PostgreSQL only. No customer data, live restaurant access, printer
jobs, VM operation, installation, deployment, merge or push is part of this work.

- Native before/after put/flush failures, sealed receipt corruption, pending
  encrypted portable restore, hostile transport result/receipt associations,
  distinct same-key lines, frozen default fee and retained retries.
- Actual Edge lost ACK, pruning, later edit and transport completion write failures;
  interrupted storage produces no FAILED ACK and reopens to the same success.
- Actual Manager editor/detail flows at 320 and 1024 pixels: retained delivery,
  repeated navigation, session changes, old Cloud refusal and discard failure.
- Actual guarded HTTP/PostgreSQL acceptance, current Staff/Device/Venue authority,
  12 concurrent retries, delayed results and every mirror write failure. Scoped
  disposable database triggers fail after old-line deletion and after the first
  inserted line; the original Order, lines, Table and CLAIMED command remain whole.
- Fresh migration replay and populated immediate-previous schema upgrade preserve
  old Order/line/command rows while adding only nullable JSONB projections.
- Native SIGKILL at all 32 actual Hive I/O checkpoints uses verified owned child
  ancestry and separate reader processes; later edits and one audit are retained.
  This proves process interruption, not arbitrary storage/controller power loss.

Physical Windows release/replacement qualification stays under OPS-01. POS-02
printer/driver/paper acceptance remains deferred and VM work remains HELD.
This milestone does not activate multi-POS coordination, printer work, other
Manager mutations or the later full-plan release gates.

Reproduction entry points: `apps/backend/tool/prove_mgr05_postgres.py` and
`apps/operations/tool/prove_mgr05_recovery.py`. The final source-identified proof
records the exact committed export, selected tests, source/log hashes, owned WIP
preservation and independent review. Required cached SDKs/PostgreSQL and the
synthetic native fixture are explicit inputs; the tools install nothing.

## Compatibility and rollback

The migration adds nullable `Order.managerEditProjection` and
`EdgeCommand.resultProjection`; previous migration files are unchanged.
Existing transport outcomes remain readable and old snapshots invalidate edit
authority rather than manufacturing a baseline. Pending receipts and restored
source work must be retained. Older binaries that cannot read the new guarded
journal are not a qualified operational rollback; stop edits and recover with a
compatible reader. Device replacement and publication remain their own gates.
