# POS-03: Windows / Parallels smoke check

Status: **PENDING — user-run Windows acceptance.** The 2026-10-02 Mac proofs do
not qualify Windows production. POS targets Windows; Manager targets all its
supported platforms. This checklist does not expand Manager scope.

მოკლე შემოწმება POS-03-ის დასრულების შემდეგ გავუშვათ. გამოიყენეთ მხოლოდ ქვემოთ
შექმნილი სატესტო ასლი; რესტორნის დაყენებული POS და არსებული backup არ არის ამ
შემოწმების წყარო. ტესტები თვითონ ქმნიან გამოგონილ Hive მონაცემებს და HTTP-ს კრძალავენ.

## 1. Prerequisites, without installation

Start the existing Windows 11 VM and open **Windows PowerShell** as the normal
Windows user. Paste this block:

```powershell
$pos03FlutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
$pos03Flutter = if ($pos03FlutterCommand) { $pos03FlutterCommand.Source } else {
  Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat'
}
$pos03Repo = '\\Mac\Home\Developer\vynic'
$pos03Tester = Join-Path (Split-Path -Parent $pos03Flutter) 'cache\artifacts\engine\windows-x64\flutter_tester.exe'
[pscustomobject]@{
  WindowsArchitecture = $env:PROCESSOR_ARCHITECTURE
  FlutterPath = $pos03Flutter
  FlutterPresent = Test-Path -LiteralPath $pos03Flutter -PathType Leaf
  WindowsTestEnginePresent = Test-Path -LiteralPath $pos03Tester -PathType Leaf
  ProjectPresent = Test-Path -LiteralPath "$pos03Repo\apps\operations\test\unit\pos03_item_transfer_recovery_test.dart"
  PythonCommand = (Get-Command python -ErrorAction SilentlyContinue).Source
  VisualStudioLocator = Test-Path -LiteralPath "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
} | Format-List
```

Send the output. If Flutter, its Windows test engine or the project is absent,
stop here and report the missing prerequisite. No installation, VM setting
change, network change or use of the installed POS is needed for this step.
The inspected VM is **Windows 11 ARM64**; running an x64 engine there is
compatibility evidence under emulation, not physical x64 qualification.

## 2. Copy the candidate to a new Windows-local directory

After the three prerequisites above are present, continue in the same window:

```powershell
$ErrorActionPreference = 'Stop'
$pos03Root = Join-Path $env:LOCALAPPDATA ('VynicPos03Smoke\' + [guid]::NewGuid().ToString())
$pos03Ops = Join-Path $pos03Root 'apps\operations'
$pos03Contracts = Join-Path $pos03Root 'packages\contracts\generated\dart'
New-Item -ItemType Directory -Path $pos03Ops, $pos03Contracts | Out-Null
& robocopy "$pos03Repo\apps\operations" $pos03Ops /E /R:0 /W:0 /XD build .dart_tool .git .idea .gradle Pods ephemeral .symlinks /XF .env* *.hive *.hivec local.properties key.properties *.jks *.keystore *.p12 *.mobileprovision .flutter-plugins-dependencies | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'Operations source copy failed' }
& robocopy "$pos03Repo\packages\contracts\generated\dart" $pos03Contracts /E /R:0 /W:0 /XD .dart_tool build | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'Contracts source copy failed' }
Set-Location -LiteralPath $pos03Ops
$pos03Expected = (Get-Content -LiteralPath "$pos03Repo\docs\proofs\POS03_NATIVE_2026-10-02.json" -Raw | ConvertFrom-Json).sourceSha256.PSObject.Properties | Where-Object { $_.Name -like 'lib/*' }
foreach ($pos03File in $pos03Expected) {
  $pos03Actual = (Get-FileHash -LiteralPath (Join-Path $pos03Ops $pos03File.Name) -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($pos03Actual -ne $pos03File.Value) { throw "Candidate source changed: $($pos03File.Name); request the current milestone checklist" }
}
"Verified $($pos03Expected.Count) candidate runtime hashes"
& $pos03Flutter --suppress-analytics pub get --offline 2>&1 | Tee-Object -FilePath "$pos03Root\dependencies.log"
if ($LASTEXITCODE -ne 0) { throw "Cached dependencies unavailable; report $pos03Root\dependencies.log" }
```

Expected: a fresh path under Windows `%LOCALAPPDATA%\VynicPos03Smoke`, and
successful offline dependency resolution. Tests use this Windows-local copy;
the Mac shared folder is only a source. An offline cache miss is a setup
blocker, not a POS-03 test result. Report it before adding dependencies.

## 3. Run the short synthetic transfer check

```powershell
& $pos03Flutter --suppress-analytics test --no-pub --reporter expanded --concurrency 1 test/unit/pos03_item_transfer_recovery_test.dart test/unit/pos03_backup_legacy_test.dart test/widget/pos03_transfer_admission_test.dart 2>&1 | Tee-Object -FilePath "$pos03Root\smoke.log"
$pos03Exit = $LASTEXITCODE
"POS03_WINDOWS_SMOKE_EXIT=$pos03Exit"
"POS03_WINDOWS_LOG=$pos03Root\smoke.log"
```

Expected: `All tests passed!` and `POS03_WINDOWS_SMOKE_EXIT=0`. The actual Order
screen tests select all four source items and Table 12, submit **გადატანა**, and
verify the success message, source route dismissal and completed cleanup.
They also change the source while the picker is open and inject interrupted
storage: the screen must refuse stale selection or report recovery, never
claim a released source before durable completion.

The storage tests verify total quantity **5**, frozen value **12.51 GEL**,
one MOVE audit on each Order, one nonfiscal TRANSFER_CLOSE, preserved historical
Sale and no new Sale, repeated recovery/retry, and complete portable restore.
These are native Windows Flutter/Hive tests; the normal POS application and
its workers are not launched.

On failure, send `smoke.log`, the printed exit code, the prerequisite output
and a screenshot of the first `Expected` / `Actual` or compiler error. On
success, send the final `All tests passed!` lines and the exit code. Parent
records the actual Windows result; it stays pending until that evidence arrives.

## Remaining release acceptance

This smoke is an early checkpoint, not release approval. The following remain
explicit plan gates:

- **OPS-01:** compile the exact POS product for Windows with existing Visual
  Studio C++/Windows SDK and correct POS native identity; qualify signed
  install/update/rollback, native process termination/restart, complete
  backup/restore on Windows-local storage, and target restaurant hardware.
  Python/Visual Studio presence and a usable new POS binary were not verified
  in the paused VM inspection. The installed desktop shortcut is an older
  artifact and does not prove this candidate.
- **OPS-01 / PROD-01:** operator acceptance on the qualified candidate with a
  separate synthetic data directory: partial/full transfer, stale selection,
  restart/recovery and resulting receipt/history; 1024×768, DPI, touch/keyboard,
  offline operation and on-site install/recovery procedures.
- **POS-02:** actual supported printers, spooler restart/uncertain print result
  and physical receipts. Windows ARM virtualization does not qualify printer
  drivers, physical power/storage failures or physical x64 POS hardware.
- Actual acquiring/provider sandbox and physical bank-terminal evidence remain
  their later payment milestones. This transfer does not create a payment.

After these checkpoints the owner decides production rollout. No deployment,
feed publication, installation or customer-data replacement is authorized by
this checklist alone.
