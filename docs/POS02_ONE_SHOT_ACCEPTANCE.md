# POS-02 one-shot acceptance preparation

Status: **POS-02 NOT_DONE, uncommitted**. The sealed macOS preparation proof is
unchanged. An explicitly authorized Windows build/update window on October 4
installed development POS 1.0.14 / release 15 in the existing Parallels VM and
left it open at PIN login for user testing. Seven Windows product suites pass;
the standalone Windows acceptance runner has a path-validation failure below.
Current physical allowance remains **zero**; no physical printer jobs occurred.

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

## Windows runner procedure — qualification remains pending

The October 4 build/tests used the existing Windows account, cached Flutter
**3.44.2** / Dart **3.12.2** and `--offline --enforce-lockfile`; the earlier macOS
proof used Flutter 3.44.1. No SDK/dependency installation occurred. Windows
refused an inspection `.ps1` file because script execution is disabled; policy
was unchanged. Existing EXE/BAT and direct commands completed the bounded build
and synthetic tests. The sealed PowerShell launcher remains unqualified.

The standalone runner passed 39 checks and failed one: owned-output validation
compares a Windows backslash `entry.path` with a mixed-separator `marker.path`,
rejecting a valid fresh result directory before storage/transport. Do not use
this revision for physical acceptance. The following sealed procedure is a
reference for a later authorized window after source correction, resealing and
Windows qualification. Do not install/update tooling or change security policy
to make the launcher run.

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

- Historical macOS proof: 895 distinct passing acceptance checks, prior 855 plus 40 runner checks;
  73 passing suites, with the additional physical entry skipped by default.
- One fake-only native-entry smoke: actual Georgian renderer/service/worker,
  zero physical allowance, unchanged final source hashes.
- Four native Dart SIGKILL/restart checkpoints (reserved/admitted/connect/write),
  cross-process lock refusals, retained identical hash chains and no refund.
- New-path analysis and formatting pass; `main_pos` macOS development build
  passes without launch. The existing product build configuration names that
  development artifact `Vynic Manager.app`; it used `lib/main_pos.dart`.
- Historical macOS core/preflight/launcher review found no remaining P1/P2;
  the subsequent Windows path failure is recorded separately below.
- An exploratory all-tests run had 1824 passes and 13 failed checks in unrelated
  Edge/Inventory HTTP fixtures, Manager login and an unconfigured MENU09 native
  fixture. Those failed logs are retained; no full-repository green claim is made.
- October 4 Windows proof: seven product suites pass 96 checks; the standalone
  runner has 39 passes / one failure, with the physical entry skipped. The
  nine-suite aggregate is FAILED; no all-green Windows acceptance claim is made.
- The reviewed candidate is built, published and installed as development
  POS 1.0.14 / release 15. All 24 installed artifact files, signed feed and
  startup SUCCESS match; the visible app is at PIN login. No Staff login or
  operational/physical print action was exercised. Driver/model acceptance,
  runner/launcher qualification and owner policy remain pending. See
  `docs/proofs/POS02_WINDOWS_RECOVERY_2026-10-04/proof.json` and
  `docs/POS02_WINDOWS_INSTALLER_HANDOFF.md` for provenance and data limits.

No commit, push or later milestone was performed. The authorized development
publication/update does not close POS-02 or the physical release gates.
