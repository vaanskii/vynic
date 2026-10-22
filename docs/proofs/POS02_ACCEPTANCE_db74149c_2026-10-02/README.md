# POS-02 one-shot acceptance preparation

Status: **software preparation verified; POS-02 NOT_DONE, uncommitted**.
Current physical allowance is **zero**. VM operations are **HELD**. No printer,
paper, cutter, cable, power, Windows VM or normal POS process was touched here.
This task finishes with this handoff and waits for the user's next instruction.

## Frozen candidate

The runner extends the revised Admin candidate `d194367f` through seven new files.
Its 876 existing source files and all 44 integrated owned paths are unchanged.
Source manifest SHA-256:
`db74149c4680d05e16a3a1f53906b269bf76be3d1d71e78796119633d15ff51a`.
The 883-file source and proof kit are in
`docs/proofs/POS02_ACCEPTANCE_db74149c_2026-10-02/`.

The normal product does not import this runner. It uses storage-only bootstrap,
blocked HTTP, synthetic Staff/contents and a separate owned Hive directory.
Originals call the candidate `PrinterService` background admission methods.
The candidate Georgian renderers produce synthetic rasters with an additional
ASCII `TEST / DO NOT PREPARE` marker. Kitchen copies call
`PrintReconciliation.reprint`, preserving the frozen payload and recording fresh
synthetic Staff, the fixed reason and stable request ID.

The physical ledger root is fixed at
`%LOCALAPPDATA%\VynicPos02Acceptance\d194367f8fd0e2f6d9dcfea86f52d09cb605b32779b7904613b00466bd084de8`.
It is separate from `%LOCALAPPDATA%\Vynic` and normal restaurant Hive.
Any already-open candidate Hive box/journal or Staff session is refused.
Owned roots, files and box paths are checked; linked/unowned data is refused.

## Budget and recovery contract

Each explicitly approved immutable window binds the candidate hash, literal
private IPv4/9100, role, model/firmware, 80 mm paper, approval reference, UTC
start/end (at most five minutes), original/copy action and stable job/action IDs.
The default allowance is zero; a later explicitly approved window can have one.
The program never creates positive approval or renews a window itself.

An exclusive root lock spans storage and transport. Reservation is appended and
flushed before rendering/admission. Separate connect and write markers are
flushed before their actions. Each latch is spent before delegation, including
failures. Expiry and exact frozen attempt/bytes are checked after rendering and
after durable flushes, immediately before connect/add. One socket cannot resend.

Failures, cancellation, expiry and restarts never refund a reservation. A repeat
with the same identity reads status and cannot dispatch. Recovery holds prior
queued/admitted work as uncertain; the queue starts only for the newly armed
attempt. Missing spec/journal pairs, partial JSONL, invalid hash chains or changed
window specifications fail closed. **Do not delete, truncate, rename or replace
the ledger to obtain another allowance.** A new print/copy needs a separately
approved window, never a retry of an uncertain action.

`sent` means TCP accepted bytes. Observation records preserve reported slip count
and external evidence; they never set the product state to paper-confirmed.
Receipt copies, paper confirmation and no-byte retry remain disabled by the
unconfigured owner policy. The runner does not choose that policy.

## Minimal Windows procedure — only after the hold is lifted

Use the existing Windows account, cached Flutter **3.44.1** SDK and cached locked
dependencies. Do not install/update tooling or change PowerShell/security policy
to make the launcher run. PowerShell execution itself has not been verified on
Windows for this revision. If existing policy/cache blocks it, retain the error.
The cached-Dart launch path and native runner were exercised on macOS only.

1. Copy the sealed kit `source.zip` to an isolated new folder, and extract it.
   Do not overlay the workspace, installed POS, or old proof kits.
2. From that extracted folder, run `./Run-Pos02-Acceptance.ps1`.
   This default **only verifies source**. It starts no tests, app, VM or socket.
3. When the Windows verification window is approved, run:

   ```powershell
   ./Run-Pos02-Acceptance.ps1 -FlutterSdk 'C:\path\to\existing\flutter' -RunSyntheticTests
   ./Run-Pos02-Acceptance.ps1 -FlutterSdk 'C:\path\to\existing\flutter' -RunDryJob
   ```

   Both use synthetic data and fake transport. The dry job renders one original
   and creates fresh disposable Hive. It does not read the physical ledger.
   Copy/restart/failure/double-submit/cancel are covered by the synthetic suite;
   a fresh dry Go+copy config is explicitly refused. Keep the emitted result and
   JSONL/stderr paths under `VynicPos02Acceptance/results`.
4. **Do not execute physical mode now.** `window-zero.json` is a preparation
   example with allowance zero and undecided model/firmware. A later approved
   physical config needs all exact fields, source hash, one allowance and current
   times. Preserve its window ID/action ID permanently. The later command is:

   ```powershell
   ./Run-Pos02-Acceptance.ps1 -FlutterSdk 'C:\path\to\existing\flutter' -ConfigPath 'C:\approved\window.json' -ExecuteApprovedPhysical
   ```

   `go: false` records Cancel without rendering/admission/TCP. Once reserved,
   repeating the same config only retrieves the old job. After observing paper,
   a repeated config with the same unchanged window, `go: false` and an
   `observation` object (`slips`, `operator`, `evidence`, `note`) records evidence
   without sending. A Kitchen copy requires a new separately approved window:
   `action: copy`, old `jobId`, fresh `actionId/windowId`, same role/endpoint.

## Physical checks and decisions still pending

Before another physical page, the owner must specify the exact printer model(s),
firmware, private IP/role, 80 mm paper compatibility, cutter mode/driver path and
an explicit per-window allowance. Earlier two ASCII tickets count toward the
earlier total budget; this handoff grants no new paper allowance. Also confirm
the isolated lab printer has no customer work/buffer and the exact Windows build,
architecture/emulation, driver version and operator/evidence location.

For each supported model retain the approved config, candidate source/native
artifact hashes, persisted journal/result, observed slip count and photos/logs.
Acceptance still requires Georgian readability/layout/identifier/copy marker and
cut behavior; cable/no-byte failure; paper-out and subsequent paper handling;
power interruption; actual POS kill/restart around sending; uncertain no-retry;
explicit labeled copy; double submit/Cancel; and shared-endpoint serialization
where applicable. Interruptions and any additional prints require their own
explicit approved windows/allowances. One normal test ticket cannot close this
matrix. Simulated process kills here do not constitute physical printer proof.

The precise remaining policy decision is who may make **Receipt copies, confirm
paper and retry an attempt that wrote no bytes**: `administrators` (persisted
Manager Staff only), or `printingStaff` (all authenticated persisted Staff).
Kitchen copies already use the user-approved Staff Go/Cancel policy. Existing
audit reasons are 3–500 characters with stable IDs. The Admin journal currently
retains its developer-only access; a broader UI access change would need an
explicit corresponding decision. `PlatformUser` is not restaurant Staff.

## Verified evidence and limits

- 895 distinct passing acceptance checks: prior 855 plus 40 runner checks;
  73 passing suites, with the additional physical entry skipped by default.
- One fake-only native-entry smoke: actual Georgian renderer/service/worker,
  zero physical allowance, unchanged final source hashes.
- Four native Dart SIGKILL/restart checkpoints (reserved/admitted/connect/write),
  cross-process lock refusals, retained identical hash chains and no refund.
- New-path analysis and formatting pass; `main_pos` macOS development build
  passes without launch. The existing product build configuration names that
  development artifact `Vynic Manager.app`; it used `lib/main_pos.dart`.
- Independent read-only core/preflight/launcher review: no remaining P1/P2.
- An exploratory all-tests run had 1824 passes and 13 failed checks in unrelated
  Edge/Inventory HTTP fixtures, Manager login and an unconfigured MENU09 native
  fixture. Those failed logs are retained; no full-repository green claim is made.
- Revised native Windows/GUI/driver and physical acceptance remain pending.
  The installed/public installer is an older build; see
  `docs/POS02_WINDOWS_INSTALLER_HANDOFF.md` for exact verified addresses and trust.

No commit, push, publication, SEC-05 or new milestone occurs until its applicable
gates and the user's continuation instruction are satisfied.
