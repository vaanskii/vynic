# POS02 isolated debug preview

Preparation is verified. POS-02 remains **NOT_DONE and uncommitted** pending its supported-printer acceptance and owner decisions. The agent's preview checks used synthetic Mac storage. Separately, the user supplied a passing Windows VM transcript for the frozen 50-check POS02 candidate. No physical printer, customer data, or installed POS was used for these synthetic checks.

## Mac: open the prepared preview

From Terminal on this development Mac:

```sh
cd /Users/vaanskii/Developer/vynic
python3 docs/proofs/POS02_PREVIEW_275688e1_2026-10-02/verify_preview.py
POS02_PREVIEW_DIR="$(mktemp -d /tmp/vynic-pos02-ui.XXXXXX)"
ditto -x -k "$PWD/docs/proofs/POS02_PREVIEW_275688e1_2026-10-02/mac-preview.zip" "$POS02_PREVIEW_DIR"
"$POS02_PREVIEW_DIR/Vynic Manager.app/Contents/MacOS/Vynic Manager"
```

The app has the inherited `Vynic Manager` bundle name, but this archive runs `tool/pos02_preview.dart`. Launch its extracted executable by the path above; do not select an installed Manager or the ordinary `main_pos` app by bundle name. This debug binary is arm64 for this Mac, with macOS 12 minimum. Native GUI launch has not been performed by the agent.

Every launch opens a new synthetic temporary database. Outbound HTTP is blocked, normal POS bootstrap and sync timers are skipped, the print worker stays stopped until an explicit sample action, and the compiled printer endpoint is empty. The physical-print button is disabled. No real LAN printer can be selected in this prepared build.

Choose kitchen or receipt and a simulated outcome, then click **Simulate one TEST job**. Open the print journal to inspect sent, failed, or uncertain results. Kitchen and receipt samples use the real ESC/POS renderers, with `TEST / DO NOT PREPARE` and a unique job ID. Socket completion still does not prove paper output. Reconciliation controls remain read-only because the production operator policy has not been chosen. A relaunch starts with a different empty database; this utility is for preparation, not restart-recovery acceptance.

## Windows: use the exact prepared source

`docs/proofs/POS02_PREVIEW_275688e1_2026-10-02/preview-source.zip` contains all 867 sealed POS02 candidate files plus the three preview files. It excludes existing unrelated WIP and Claude's platform work. The archive contains `POS02_SOURCE_SHA256.json` and `POS02_PROFILE.json`.

On Windows, extract into a fresh **Windows-local** directory, such as `%LOCALAPPDATA%\VynicPos02Preview\<new-guid>`. Do not run Hive tests from the Mac shared folder or use an installed restaurant database. The shared folder is only the archive source; verify its SHA256 against `CHECKSUMS.json` first. `flutter.bat` was located at `C:\Users\vaanskii\develop\flutter\bin\flutter.bat`. The user's later transcript confirms the existing native x64 test engine and offline locked package cache ran the frozen 50-check candidate in Windows 11 ARM. It does not verify Visual Studio C++ compilation, the preview GUI, or printer/driver acceptance.

**Windows core smoke passed, user-supplied evidence (2026-10-02 20:08:53 UTC):** the separate immutable `POS02_WINDOWS_CANDIDATE_275688e1_2026-10-02.zip` (SHA256 `6142021ae4e2164487356a0a422e0a050feb2fb206fc5cd4c9f1175818afe733`) and all 867 source hashes were verified, `pub get --offline --enforce-lockfile` succeeded, and the three POS02 suites finished `00:22 +50: All tests passed!` with `POS02_WINDOWS_SMOKE_EXIT=0`. The Windows-local log is `C:\Users\vaanskii\AppData\Local\VynicPos02Smoke\9595fa09-9c30-4e67-aea4-66d5de635c8c\pos02-smoke.log`. The agent did not retrieve this log or independently rerun Windows. [Evidence and remaining gates](proofs/POS02_WINDOWS_SMOKE_275688e1_2026-10-02.json).

This PowerShell block verifies the source after extraction; set the working directory to the fresh extraction root first:

```powershell
$pos02Hashes = Get-Content .\POS02_SOURCE_SHA256.json -Raw | ConvertFrom-Json
foreach ($entry in $pos02Hashes.PSObject.Properties) {
    $actual = (Get-FileHash -LiteralPath $entry.Name -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $entry.Value) { throw "POS02 source mismatch: $($entry.Name)" }
}
```

Before invoking Flutter, verify the existing SDK's cached `bin\cache\artifacts\engine\windows-x64\flutter_tester.exe` and `bin\cache\dart-sdk\bin\dart.exe` exist. If absent, stop and report the missing prerequisite rather than installing or downloading it. With the existing SDK, native engine, and already cached packages available:

```powershell
Set-Location .\apps\operations
flutter.bat --suppress-analytics pub get --offline --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw 'Existing package cache is incomplete; stop here.' }
flutter.bat --suppress-analytics test --no-pub --reporter=json test/unit/pos02_preview_safety_test.dart test/unit/pos02_print_delivery_test.dart test/unit/pos02_backup_restore_test.dart test/widget/pos02_print_jobs_test.dart
if ($LASTEXITCODE -ne 0) { throw 'POS02 synthetic smoke check failed.' }
```

There are 67 distinct checks in these four suites (17 preview, 50 POS02). They passed on the Mac native Flutter test engine. The user-reported Windows result covers the 50 POS02 checks from the frozen 867-file candidate; the additional 17 preview checks and Windows preview GUI remain unexecuted. The command above is an available future check, not a request to rerun the completed smoke. Save complete output and exit codes if that separate check is requested. Do not bypass PowerShell execution policy or modify VM/toolchain/security settings.

Only after the existing Windows desktop C++ toolchain and cached Windows Flutter build artifacts are verified, the safe preview entrypoint is:

```powershell
flutter.bat --suppress-analytics run -d windows --debug --no-pub -t tool/pos02_preview.dart --dart-define=APP_ROLE=pos --dart-define=VYNIC_ENV=development --dart-define=POS02_TEST_PRINTER_HOST=
```

No Windows executable is supplied or proven. Windows 11 ARM availability does not prove a physical printer model, driver, or supported production Windows configuration.

## Before a physical acceptance window

The user must identify each printer's manufacturer/model, kitchen or receipt role, connection mode, paper width, and the intended Windows/driver configuration for formal hardware qualification. A model name is not required to check TCP reachability. The user reported Windows `10.10.10.9/24`, gateway `10.10.10.1`, and **both `Test-NetConnection` checks to `.5`/`.6:9100` returned True**. This is user-supplied connectivity evidence; the agent has not contacted either endpoint. The checks sent no print payload and do not establish printer protocol or paper output. No VM network changes were made by this task.

The user has allowed an initial **2–3 test slips TOTAL across both printers**. The parent supplied a one-time PowerShell ASCII check: one short `VYNIC TEST - DO NOT PREPARE` message identifying the endpoint, followed by `Basic network print test` and feed, to each printer. It uses a 5-second TCP connection/write timeout, no automatic retry, no cutter or ESC/POS setting commands, and stops on error. The user then reported **“its working”**. Basic ASCII paper output is user-reported working; individual printer counts/photos have not been supplied. Account for the two issued text jobs within the three-slip maximum; at most one text job remains, with no additional print currently requested. Do not duplicate the command or add another text print.

The user separately asked for cutting. The parent supplied a **one-time cut-only** command to both endpoints using `1D 56 00` (`GS V 0`, Epson ESC/POS form), with TCP timeouts and no automatic retry, additional text, or feed. At 20:18:40 UTC the user reported that everything sent works. Basic printing and cutting are therefore **user-confirmed working**. Individual model/firmware details, photos, and exact paper counts remain unreported. This action-scoped approval does not authorize more test text, repetition, paper-out, or cable/power interruption. Do not duplicate either action. The confirmation is basic ASCII/cut observation, not full candidate, Georgian, driver, or recovery acceptance.

That ASCII check is basic transport/output inspection. It is not the POS02 candidate renderer, Georgian glyph/cutter qualification, driver qualification, or recovery acceptance. The 50 completed synthetic tests produce no paper. Paper-out, cable/power interruptions, driver operations, and uncontrolled copies are outside this initial window.

The existing preview transport has been inspected: it permits only the compiled literal private IPv4 endpoint on port 9100, requires a fresh dialog approval for a specific TEST job, expires permission after 60 seconds including rendering, and consumes permission before the single socket write. Pre-write connection retries cannot add paper bytes; any error after a write attempt becomes uncertain and has no automatic write retry. The UI prevents overlapping submissions and repeated dialog decisions. These guards have synthetic coverage; they do not establish physical compatibility.

The packaged Mac binary stays fake-only. Do not enable or launch a physical preview in addition to the parent's completed, user-confirmed ASCII/cut-only checks. The x64 test engine smoke does not prove the Windows C++ desktop toolchain, and no Windows GUI binary is proven. A future candidate-output window needs its exact endpoint/sample role, a verified isolated launch path, and a separately agreed slip budget. A missing toolchain does not authorize installation.

The preview enforces one write per approved job; it does **not** enforce a global paper budget across separate approvals or relaunches. Stop on no paper, an error, uncertainty, unexpected output, or an unexpected slip count. Do not retry or resubmit to make the initial check pass. A third slip requires a separately identified explicit action after checking paper and must keep the window total at three or fewer. The operator reconciliation policy and supported-model failure acceptance remain unresolved before milestone DONE.

The source supports a future explicitly compiled single literal private IPv4 endpoint. A physical action requires a fresh confirmation for one labeled job; permission expires after 60 seconds including rendering and is consumed before the write. That branch was checked using injected sockets only. The shipped Mac binary and default instructions leave the endpoint empty. Do not treat this guard or a TCP `sent` state as physical acceptance.

The [delivery runbook](POS02_PRINT_DELIVERY.md) and [sealed milestone checkpoint](proofs/POS02_CHECKPOINT_275688e1_2026-10-02/RESUME.md) retain the exact milestone criteria and historical evidence unchanged. Full Mac software verification remains 788 tests and 102 native SIGKILL checkpoints; the separate user-reported Windows smoke adds platform evidence for the existing 50 POS02 checks. This auxiliary preview does not complete or commit the milestone.
