param([string]$FlutterSdk, [switch]$RunSyntheticTests)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Verify-Source.ps1') -SourceRoot $PSScriptRoot
if (!$RunSyntheticTests) {
  Write-Output 'Dry run complete. Use -RunSyntheticTests only in the approved Windows verification window with the existing SDK/cache.'
  exit 0
}
# Every listed fixture uses fresh synthetic Hive data, blocked HTTP and fake printer transport.
# This never runs main_pos.dart, connects a real printer or modifies VM configuration.
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
# Bypass flutter.bat SDK bootstrap. Version checks are disabled. Any unexpected
# artifact fetch is redirected to an unsupported file URI and fails before network I/O.
# Only process-scoped environment values change; restore them in finally.
$priorFlutterRoot = $env:FLUTTER_ROOT
$priorStorageUrl = $env:FLUTTER_STORAGE_BASE_URL
$priorAnalytics = $env:FLUTTER_SUPPRESS_ANALYTICS
$tests = @(
  'test/unit/pos02_print_delivery_test.dart',
  'test/unit/pos02_backup_restore_test.dart',
  'test/widget/pos02_print_jobs_test.dart',
  'test/unit/pos02_local_printers_test.dart',
  'test/widget/pos02_admin_printers_test.dart',
  'test/widget/pos02_kitchen_entry_points_test.dart',
  'test/widget/admin_navigation_test.dart',
  'test/unit/developer_access_test.dart',
  'test/unit/runtime_config_test.dart',
  'test/unit/pos02_preview_safety_test.dart',
  'test/unit/backup_completeness_test.dart'
)
Push-Location (Join-Path $PSScriptRoot 'apps/operations')
try {
  $env:FLUTTER_ROOT = $FlutterSdk
  $env:FLUTTER_STORAGE_BASE_URL = 'file:///POS02_NO_DOWNLOADS_ALLOWED'
  $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
  & $dart --disable-dart-dev $tool --no-version-check --suppress-analytics pub get --offline --enforce-lockfile
  if ($LASTEXITCODE -ne 0) { throw 'Offline dependencies unavailable. Stop; do not install or fetch dependencies.' }
  & (Join-Path $PSScriptRoot 'Verify-Source.ps1') -SourceRoot $PSScriptRoot
  $log = Join-Path $PSScriptRoot 'POS02_WINDOWS_SYNTHETIC_TESTS.jsonl'
  $err = Join-Path $PSScriptRoot 'POS02_WINDOWS_SYNTHETIC_TESTS.stderr'
  & $dart --disable-dart-dev $tool --no-version-check --suppress-analytics test --no-pub --reporter=json @tests 2> $err | Out-File -LiteralPath $log -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw "Synthetic tests failed. Keep $log and $err." }
  Write-Output "Tests exited 0. Preserve logs; this is not native GUI/driver/physical-printer acceptance. Log: $log"
} finally {
  $env:FLUTTER_ROOT = $priorFlutterRoot
  $env:FLUTTER_STORAGE_BASE_URL = $priorStorageUrl
  $env:FLUTTER_SUPPRESS_ANALYTICS = $priorAnalytics
  Pop-Location
}
