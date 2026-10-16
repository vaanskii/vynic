param([string]$FlutterSdk, [switch]$RunSyntheticTests, [switch]$RunDryJob,
      [switch]$ExecuteApprovedPhysical, [string]$ConfigPath)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Verify-Source.ps1') -SourceRoot $PSScriptRoot
$actions = @($RunSyntheticTests.IsPresent, $RunDryJob.IsPresent, $ExecuteApprovedPhysical.IsPresent) | Where-Object { $_ }
if ($actions.Count -gt 1) { throw 'Choose exactly one execution mode.' }
if ($actions.Count -eq 0) {
  Write-Output 'DRY PREPARATION ONLY: source verified; no Flutter, VM, device, socket or printing. Physical allowance remains ZERO.'
  exit 0
}
if ($env:OS -ne 'Windows_NT') { throw 'Synthetic execution requires the existing approved Windows environment.' }
if ([string]::IsNullOrWhiteSpace($FlutterSdk)) { throw 'Supply the path to the existing complete Flutter SDK; do not install or bootstrap one.' }
$FlutterSdk = (Resolve-Path -LiteralPath $FlutterSdk).Path
function Require-CachedFile([string]$RelativePath) {
  $file = Join-Path $FlutterSdk $RelativePath
  if (!(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) { throw "Existing SDK/cache is incomplete: $RelativePath. Stop; no downloads are authorized." }
  return $file
}
function Require-CachedDirectory([string]$RelativePath) {
  if (!(Test-Path -LiteralPath (Join-Path $FlutterSdk $RelativePath) -PathType Container)) { throw "Existing SDK/cache is incomplete: $RelativePath. Stop; no downloads are authorized." }
}
$dart = Require-CachedFile 'bin/cache/dart-sdk/bin/dart.exe'
$tool = Require-CachedFile 'bin/cache/flutter_tools.snapshot'
$version = Get-Content -LiteralPath (Require-CachedFile 'bin/cache/flutter.version.json') -Raw | ConvertFrom-Json
if ($version.frameworkVersion -ne '3.44.1') { throw 'This handoff expects the existing Flutter 3.44.1 SDK. Stop on a version mismatch; do not upgrade.' }
$engineInfo = Require-CachedFile 'bin/cache/engine_stamp.json'
$engine = (Get-Content -LiteralPath (Require-CachedFile 'bin/cache/engine.stamp') -Raw).Trim()
foreach ($name in @('engine-dart-sdk', 'engine_stamp', 'flutter_sdk', 'font-subset')) {
  $cached = (Get-Content -LiteralPath (Require-CachedFile "bin/cache/$name.stamp") -Raw).Trim()
  if ($cached -ne $engine) { throw "Stale existing SDK artifact: $name. Stop; do not update it." }
}
foreach ($name in @('material_fonts', 'gradle_wrapper')) {
  $required = (Get-Content -LiteralPath (Require-CachedFile "bin/internal/$name.version") -Raw).Trim()
  $cached = (Get-Content -LiteralPath (Require-CachedFile "bin/cache/$name.stamp") -Raw).Trim()
  if ($cached -ne $required) { throw "Stale existing SDK artifact: $name. Stop; do not update it." }
  Require-CachedDirectory "bin/cache/artifacts/$name"
}
foreach ($directory in @('bin/cache/artifacts/engine/common', 'bin/cache/pkg/sky_engine', 'bin/cache/pkg/flutter_gpu')) { Require-CachedDirectory $directory }
$engines = @('windows-x64', 'windows-arm64') | Where-Object { Test-Path -LiteralPath (Join-Path $FlutterSdk "bin/cache/artifacts/engine/$_/flutter_tester.exe") -PathType Leaf }
if ($engines.Count -eq 0) { throw 'Existing native Windows Flutter test engine is missing. Stop; no downloads are authorized.' }
$toolConfig = Require-CachedFile 'packages/flutter_tools/.dart_tool/package_config.json'
$config = Get-Content -LiteralPath $toolConfig -Raw | ConvertFrom-Json
if (!$config.packages -or $config.packages.Count -eq 0) { throw 'Existing Flutter tool dependencies are missing.' }
$baseUri = [Uri]::new([IO.Path]::GetFullPath($toolConfig))
foreach ($package in $config.packages) {
  $uri = [Uri]::new($baseUri, [string]$package.rootUri)
  if ($uri.Scheme -ne 'file' -or !(Test-Path -LiteralPath (Join-Path $uri.LocalPath 'pubspec.yaml') -PathType Leaf)) { throw "Existing Flutter tool dependency is missing: $($package.name). Stop; no bootstrap is authorized." }
}

$profile = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'POS02_PROFILE.json') -Raw | ConvertFrom-Json
$sourceSha = 'db74149c4680d05e16a3a1f53906b269bf76be3d1d71e78796119633d15ff51a'
if ($profile.sourceManifestSha256 -ne $sourceSha) { throw 'Profile differs from the tested runner candidate.' }
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA) -or !(Test-Path -LiteralPath $env:LOCALAPPDATA -PathType Container)) { throw 'Existing LOCALAPPDATA is required.' }
function Reject-ReparseAncestors([string]$Path) {
  $current = [IO.Path]::GetFullPath($Path)
  while ($current) {
    if (Test-Path -LiteralPath $current) {
      if (((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked acceptance path refused: $current" }
    }
    $parent = [IO.Directory]::GetParent($current)
    if (!$parent) { break }
    $current = $parent.FullName
  }
}
$resultParent = Join-Path $env:LOCALAPPDATA 'VynicPos02Acceptance/results'
Reject-ReparseAncestors $resultParent
$runId = 'pos02-result-' + [Guid]::NewGuid().ToString()
$resultRoot = Join-Path $resultParent $runId
$utf8 = [Text.UTF8Encoding]::new($false)
if ($RunSyntheticTests) {
  $windowId = 'pos02-synthetic-suite'
} elseif ($ConfigPath) {
  $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
  $request = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
  $windowId = [string]$request.window.windowId
  if ($request.window.candidateSha256 -ne $sourceSha) { throw 'Config must bind this exact source manifest.' }
} elseif ($RunDryJob) {
  $windowId = 'pos02-dry-' + [Guid]::NewGuid().ToString()
  $now = [DateTime]::UtcNow
  $request = [ordered]@{window=[ordered]@{
    protocol=1; baseCandidate='d194367f8fd0e2f6d9dcfea86f52d09cb605b32779b7904613b00466bd084de8'; candidateSha256=$sourceSha;
    windowId=$windowId; approval='UNAPPROVED; dry simulation only'; startsAt=$now.AddSeconds(-5).ToString('o'); expiresAt=$now.AddMinutes(2).ToString('o');
    allowance=0; host='10.10.10.5'; port=9100; target='kitchen'; model='UNDECIDED'; firmware='UNDECIDED'; paperMm=80;
    action='original'; actionId=$windowId; jobId=$windowId
  }; go=$true}
} else { throw 'Physical mode requires an explicitly approved immutable ConfigPath. Current allowance is zero.' }
if ($RunDryJob -and $request.go -and $request.window.action -eq 'copy') { throw 'Fresh dry job supports ORIGINAL or Cancel. Copy/restart are exercised by RunSyntheticTests; no physical ledger is opened by a dry job.' }
if ($ExecuteApprovedPhysical) {
  if (!$ConfigPath -or $request.window.allowance -ne 1) { throw 'Supply an approved one-job allowance config. No implicit budget increase.' }
  foreach ($field in @('approval','model','firmware')) {
    if ([string]::IsNullOrWhiteSpace($request.window.$field) -or $request.window.$field -match 'UNAPPROVED|UNDECIDED|SYNTHETIC') { throw "Exact approved physical provenance required: $field" }
  }
}
[IO.Directory]::CreateDirectory($resultRoot) | Out-Null
$marker = [ordered]@{owner='VYNIC_POS02_RESULT_V1'; candidateSha256=$sourceSha; windowId=$windowId} | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $resultRoot 'OWNER.json'), $marker, $utf8)
$vars = @('FLUTTER_ROOT','FLUTTER_STORAGE_BASE_URL','FLUTTER_SUPPRESS_ANALYTICS','POS02_ACCEPTANCE_CONFIG','POS02_ACCEPTANCE_SOURCE_SHA','POS02_ACCEPTANCE_EXECUTE','POS02_ACCEPTANCE_OUTPUT_ROOT')
$previous = @{}
foreach ($name in $vars) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
Push-Location (Join-Path $PSScriptRoot 'apps/operations')
try {
  $env:FLUTTER_ROOT = $FlutterSdk
  $env:FLUTTER_STORAGE_BASE_URL = 'file:///POS02_NO_DOWNLOADS_ALLOWED'
  $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
  $env:POS02_ACCEPTANCE_CONFIG = $null
  $env:POS02_ACCEPTANCE_EXECUTE = $null
  & $dart --disable-dart-dev $tool --no-version-check --suppress-analytics pub get --offline --enforce-lockfile
  if ($LASTEXITCODE -ne 0) { throw 'Offline locked dependencies unavailable. Stop; no installs or downloads.' }
  & (Join-Path $PSScriptRoot 'Verify-Source.ps1') -SourceRoot $PSScriptRoot
  if ($RunSyntheticTests) {
    if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'acceptance-suites.json') -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'b07b50b3787fa8dc5e24ebd1a0ba65c9f36163082b56cae2855e0801519f69d3') { throw 'Acceptance suite list changed.' }
    $tests = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'acceptance-suites.json') -Raw | ConvertFrom-Json)
  } else {
    # Freeze a copy in the fresh owned result folder; a config edited later cannot affect this run.
    $frozenConfig = Join-Path $resultRoot 'request.json'
    [IO.File]::WriteAllText($frozenConfig, ($request | ConvertTo-Json -Depth 20 -Compress), $utf8)
    # request.json is outside the strictly empty output subdirectory.
    $outputRoot = Join-Path $resultParent ('pos02-result-' + [Guid]::NewGuid().ToString())
    [IO.Directory]::CreateDirectory($outputRoot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $outputRoot 'OWNER.json'), $marker, $utf8)
    $env:POS02_ACCEPTANCE_CONFIG = $frozenConfig
    $env:POS02_ACCEPTANCE_SOURCE_SHA = $sourceSha
    $env:POS02_ACCEPTANCE_OUTPUT_ROOT = $outputRoot
    if ($ExecuteApprovedPhysical) { $env:POS02_ACCEPTANCE_EXECUTE = 'EXPLICIT_APPROVED_ONE_SHOT' }
    $tests = @('test/live/pos02_one_shot_acceptance_test.dart')
  }
  $log = Join-Path $resultRoot 'tests.jsonl'
  $err = Join-Path $resultRoot 'tests.stderr'
  & $dart --disable-dart-dev $tool --no-version-check --suppress-analytics test --no-pub --reporter=json @tests 2> $err | Out-File -LiteralPath $log -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw "Run failed. Preserve $resultRoot and its ledger; never retry/refund an uncertain physical action." }
  & (Join-Path $PSScriptRoot 'Verify-Source.ps1') -SourceRoot $PSScriptRoot
  if (!$RunSyntheticTests -and !(Test-Path -LiteralPath (Join-Path $outputRoot 'result.json') -PathType Leaf)) { throw 'Missing native result. Preserve the consumed ledger; do not print again.' }
  Write-Output "Execution exited zero. Logs: $resultRoot"
  if (!$RunSyntheticTests) { Write-Output "Result: $outputRoot/result.json" }
  Write-Output 'TCP sent is not paper confirmed. Windows GUI/driver/hardware acceptance and milestone DONE remain pending.'
} finally {
  foreach ($name in $vars) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
  Pop-Location
}
