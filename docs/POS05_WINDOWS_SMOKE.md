# POS-05: Windows synthetic acceptance

Status: **PENDING_NOT_RUN / HELD**. No Windows/Parallels operation is part of
the 2026-10-02 Mac proof. POS-05 is a source milestone; OPS-01 retains Windows
build, install/update/rollback and physical restaurant hardware qualification.

გამოიყენეთ მხოლოდ ახალი Windows-local სატესტო ასლი და გამოგონილი მონაცემები.
დაყენებული POS, მომხმარებლის Hive და არსებული რესტორნის backup არ გამოიყენოთ.

## Prerequisites and source identity

The existing Windows prerequisite checkpoint in `docs/POS03_WINDOWS_SMOKE.md`
is still pending. Resume only after its Flutter, native test engine, source and
architecture evidence has been supplied. Do not install tools or alter VM
settings implicitly. ARM64 Windows running the x64 test engine is emulation
evidence; physical x64 and printer qualification remain separate.

After the POS-03 prerequisite block has established `$pos03Flutter` and
`$pos03Repo`, copy the candidate into a fresh Windows-local directory:

```powershell
$ErrorActionPreference = 'Stop'
$pos05Flutter = $pos03Flutter
$pos05Repo = $pos03Repo
$pos05Root = Join-Path $env:LOCALAPPDATA ('VynicPos05Smoke\' + [guid]::NewGuid().ToString())
$pos05Ops = Join-Path $pos05Root 'apps\operations'
$pos05Contracts = Join-Path $pos05Root 'packages\contracts\generated\dart'
New-Item -ItemType Directory -Path $pos05Ops, $pos05Contracts | Out-Null
& robocopy "$pos05Repo\apps\operations" $pos05Ops /E /R:0 /W:0 /XD build .dart_tool .git .idea .gradle Pods ephemeral .symlinks /XF .env* *.hive *.hivec local.properties key.properties *.jks *.keystore *.p12 *.mobileprovision .flutter-plugins-dependencies | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'Operations source copy failed' }
& robocopy "$pos05Repo\packages\contracts\generated\dart" $pos05Contracts /E /R:0 /W:0 /XD .dart_tool build | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'Contracts source copy failed' }
$pos05Proof = Join-Path $pos05Root 'POS05-frozen-source.json'
Copy-Item -LiteralPath "$pos05Repo\docs\proofs\POS05_2026-10-02.json" -Destination $pos05Proof
Set-Location -LiteralPath $pos05Ops
```

The normal POS application and its workers remain closed for this smoke.

Verify the copied runtime and selected test/support/config sources against
`docs/proofs/POS05_2026-10-02.json` before testing. The manifest covers the
tested working profile, including three explicitly listed existing runtime WIP
files. A bare commit archive is a different profile unless separately tested.
If any source hash differs, stop and obtain the frozen validated profile or a
new validated milestone manifest. Do not disable checks or substitute the old
POS-03 proof, whose runtime hashes precede the shared POS-05 writer changes.

From the new copy's `apps\operations` directory, run:

```powershell
$ErrorActionPreference = 'Stop'
$pos05Evidence = Get-Content -LiteralPath $pos05Proof -Raw | ConvertFrom-Json
if ($pos05Evidence.status -ne 'DONE' -or -not $pos05Evidence.allRequiredMacChecksPassed) { throw 'POS-05 source acceptance is incomplete' }
if (@($pos05Evidence.sourceSha256.PSObject.Properties).Count -ne 382) { throw 'Incomplete frozen runtime manifest' }
foreach ($pos05Group in @('sourceSha256', 'testSha256', 'supportSha256')) {
  $pos05Entries = @($pos05Evidence.$pos05Group.PSObject.Properties)
  if ($pos05Entries.Count -eq 0) { throw "Missing frozen hash group: $pos05Group" }
  foreach ($pos05File in $pos05Entries) {
    $pos05Path = $pos05File.Name -replace '^apps/operations/', ''
    $pos05Actual = (Get-FileHash -LiteralPath $pos05Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($pos05Actual -ne $pos05File.Value) { throw "Frozen profile differs: $pos05Path" }
  }
}
'Frozen runtime, tests and support/config hashes verified'
& $pos05Flutter --suppress-analytics pub get --offline 2>&1 | Tee-Object -FilePath "$pos05Root\dependencies.log"
if ($LASTEXITCODE -ne 0) { throw "Cached dependencies unavailable; report $pos05Root\dependencies.log" }
```

## Native Flutter/Hive smoke

Run these from the Windows-local Operations copy with the verified existing
Flutter command. Retain the prerequisite output, source verification, complete
log and exit code:

```powershell
$pos05Suites = @(
  'test/unit/pos05_order_table_mutation_test.dart',
  'test/unit/pos05_ownership_recovery_test.dart',
  'test/unit/pos05_backup_legacy_test.dart',
  'test/unit/pos05_independent_ownership_test.dart',
  'test/unit/pos05_independent_settlement_guard_test.dart',
  'test/unit/pos05_independent_tables_test.dart',
  'test/unit/pos05_independent_command_refusal_test.dart',
  'test/widget/pos05_mutation_conflict_test.dart',
  'test/unit/pos03_item_transfer_recovery_test.dart',
  'test/unit/pos03_backup_legacy_test.dart',
  'test/widget/pos03_transfer_admission_test.dart'
)
& $pos05Flutter --suppress-analytics test --no-pub --reporter expanded --concurrency 1 @pos05Suites 2>&1 | Tee-Object -FilePath "$pos05Root\smoke.log"
$pos05Exit = $LASTEXITCODE
"POS05_WINDOWS_SMOKE_EXIT=$pos05Exit"
"POS05_WINDOWS_LOG=$pos05Root\smoke.log"
```

Expected: all tests passed and exit zero. The widgets must keep simultaneous
views usable, allow another writer while a dialog is open, visibly refuse
stale/occupied actions, preserve current data, and display recovery or a
readable legacy ownership report without false success. Storage tests cover
single ownership, stable request retry, cancel/payment, exact pending restore,
legacy identities and interrupted writes using synthetic directories only.

Send the actual final test lines and exit code on success. On failure, retain
the full log and first error. A missing dependency/native tool is a setup
blocker, not a passed test. This checklist stays pending until observed evidence.

## Remaining gates

The Mac SIGKILL scripts use Unix process ownership checks and are not Windows
termination qualification. OPS-01 must prove native Windows interruption,
restart, restore, signed install/update/binary rollback, exact compatible
artifacts and target hardware. POS-02 owns physical printing and uncertain
spooler outcomes. PROD-01 retains operator acceptance and rollout decisions.
No installation, release publication or customer-data replacement is authorized
by this checklist alone.
