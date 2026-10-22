# POS-02 printer administration revision

Status: **IMPLEMENTED_CANDIDATE / NOT_DONE**. Base HEAD remains `275688e1`;
no commit, push, deployment, VM operation or physical print was performed for
this revision. The older frozen Windows/preview archives remain unchanged.

The existing Kitchen and Receipt controls remain. The additional-printer panel
registers any number of named IPv4 endpoints on port 9100. Each record has a
stable ID and `routing: unassigned`; registration never sends a ticket or probes
the endpoint. Cloud device runtime configuration retains primary Kitchen/Receipt
authority. Shared senders, station routing and multi-terminal fencing remain
EDGE-01 work.

Printer configuration remains developer-only. Both Admin and the login support
screen require `DeveloperScope.printers` for printer navigation, content, save and
connection-test handlers. Repository catalog reads and configuration writes
also enforce that scope. A Manager session or diagnostics-only developer token
cannot configure printers. Invalid IPs, duplicate names/endpoints and malformed
legacy records fail visibly without overwriting the stored catalog. Primary
printer saves preserve the additional list; successful additions flush Hive.

The print-list entry was removed from Home. The journal remains in Admin's
printer panel. Kitchen manual reprints from Order Detail, Home reservations and
the journal show only Georgian **გაშვება** / **გაუქმება** buttons. They require
fresh authenticated Staff, keep stable action/job IDs, record the operator with
`Operator requested kitchen reprint`, and retain the visible REPRINT COPY label
and duplicate warning. Cancelling admits nothing. Repeated callbacks admit one
copy. Order Detail captures one deep-cloned Order before the dialog so a live
refresh cannot mix old food lines with new table/operator metadata.

Receipt copies, paper confirmation and no-byte retry keep their existing policy
and reason checks. Their production owner policy remains unconfigured. This
revision does not turn uncertain delivery into an automatic retry or infer
paper confirmation from TCP success.

## Revised source and verification

The new candidate is an isolated export of committed HEAD plus 44 owned task
paths, with 876 operations/contract source files. It excludes unrelated WIP,
including the existing enrollment/first-run/API URL overlays and concurrent
Claude platform-web edits.

Evidence: [POS02_ADMIN_d194367f_2026-10-02](proofs/POS02_ADMIN_d194367f_2026-10-02/).
Its verifier checks the source ZIP, every source hash, saved test/build/analyzer
logs, native recovery source bindings and independent review. It performs no
app, network, printer or VM action. Use `--check-owned-checkout` to compare the
44 task paths with the current checkout without treating unrelated WIP as drift.

- 855 passing tests across 72 suites, including the inherited acceptance set,
  developer/Manager access negatives, malformed-list preservation and real
  Home/Order Detail entry-point regressions with synthetic storage/transport.
- Dart analyzer clean; all 43 owned Dart files pass formatting verification.
- macOS `lib/main_pos.dart` debug compilation passes. The inherited display name
  is `Vynic Manager.app`; this is compilation evidence only, with no GUI launch.
- 102 native SIGKILL/different-process restart checkpoints pass, with source
  and raw-log bindings retained in this candidate's evidence.
- Independent read-only review found no remaining P1/P2 in this revision.

The ZIP includes a read-only PowerShell source verifier and Windows test command
list. They are provided for later execution using the existing SDK/cache;
**the revised candidate has not been run on Windows**. Earlier user-reported
50-test Windows success belongs to the earlier 867-file frozen source, not this
revision. Earlier TCP/ASCII print/cut observations establish basic connectivity
and cutter behavior only; supported-model acceptance is still pending.

## Remaining milestone gates and handoff

The physical matrix in [POS02_PRINT_DELIVERY.md](POS02_PRINT_DELIVERY.md) remains
open: supported model/firmware and intended roles, Georgian rendered output and
observed counts, paper-out, cable/power interruption, POS kill/restart compared
with physical paper, labeled copy/dedup and shared-endpoint serialization. Native
Windows GUI/toolchain and actual interface/driver qualification are unverified.
The broader receipt/paper-reconciliation owner policy remains undecided. No more
paper, device interruption or VM operation is authorized by this document.

The one-shot acceptance runner was deferred behind these UI changes and has not
yet been implemented. The next safe step is that runner's implementation and
synthetic verification, followed by a separately approved, bounded device window.
POS-02 cannot be marked DONE or locally committed before the required physical
criteria and final exact committed-runtime verification pass. SEC-05 stays next
in the linear master plan after POS-02 closes.

Website expansion is deferred because Claude currently owns platform-web.
The concrete overlap is `apps/platform-web/src/customer/OperationsSections.tsx`
(`PrinterForm`), `customer/portal-types.ts` (`PrinterSettings`/`RuntimeConfig`),
`customer/CustomerDashboard.tsx` (re-export) and
`platform/pages/OnboardingPage.tsx` (per-device printer form). Their current
Kitchen/Receipt contract is fixed; a website expansion also needs a coordinated
backend/runtime contract decision. No platform-web, shared contract or root
lock/config file was edited for this revision.
