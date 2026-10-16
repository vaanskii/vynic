param(
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [Parameter(Mandatory=$true)][string]$PrintTransportTestExe,
  [Parameter(Mandatory=$true)][string]$SourceManifest,
  [Parameter(Mandatory=$true)][string]$FlutterWrapper,
  [Parameter(Mandatory=$true)][string]$FlutterEngine,
  [Parameter(Mandatory=$true)][string]$SdkManifest
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Source-only qualification. Caller supplies a NEW task source/output tree and
# existing cached tools. No product process, SCM, install, driver or print job.
if (Test-Path $OutputRoot) { throw 'OutputRoot must be a fresh task directory' }
if ($env:VYNIC_PRINT_TEST_CHILD) { throw 'Unexpected test-child environment' }
New-Item -ItemType Directory -Path $OutputRoot | Out-Null

function Verify-Source {
  $manifest = Get-Content -Raw $SourceManifest | ConvertFrom-Json
  foreach ($entry in $manifest.files.PSObject.Properties) {
    $path = Join-Path $SourceRoot ($entry.Name.Replace('/', '\'))
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $entry.Value.sha256 -or $item.Length -ne $entry.Value.bytes) {
      throw "Source hash/length changed: $($entry.Name)"
    }
  }
  $testHash = (Get-FileHash -LiteralPath $PrintTransportTestExe -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($testHash -ne $manifest.testExecutable.sha256 -or
      (Get-Item -LiteralPath $PrintTransportTestExe).Length -ne $manifest.testExecutable.bytes) {
    throw 'Go test executable differs from its source-build receipt'
  }
}

function Verify-CachedSdk {
  $manifest = Get-Content -Raw $SdkManifest | ConvertFrom-Json
  foreach ($entry in $manifest.PSObject.Properties) {
    $base = $FlutterWrapper
    $relative = $entry.Name
    if ($relative.StartsWith('engine/')) { $base=$FlutterEngine; $relative=$relative.Substring(7) }
    $path = Join-Path $base ($relative.Replace('/', '\'))
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) {
      throw "Existing cached SDK hash differs: $($entry.Name)"
    }
  }
}

function Run-Checked([string]$Label, [string]$Program, [string[]]$Arguments) {
  $log=Join-Path $OutputRoot ($Label+'.log')
  & $Program @Arguments *> $log
  $code=$LASTEXITCODE
  Get-Content -LiteralPath $log
  if ($code -ne 0) { throw "$Label failed with exit $code" }
}

Verify-Source
Verify-CachedSdk
$helperBuild=Join-Path $OutputRoot 'helper'
$channelBuild=Join-Path $OutputRoot 'channel'
Run-Checked 'helper-configure' 'cmake' @('-S',(Join-Path $SourceRoot 'apps/edge/native/print_helper'),'-B',$helperBuild,'-G','Visual Studio 17 2022','-A','x64')
Run-Checked 'helper-build' 'cmake' @('--build',$helperBuild,'--config','Release')
Run-Checked 'helper-fake-tests' 'ctest' @('--test-dir',$helperBuild,'-C','Release','--output-on-failure','-V')
Run-Checked 'channel-configure' 'cmake' @('-S',(Join-Path $SourceRoot 'apps/operations/windows/tests'),'-B',$channelBuild,'-G','Visual Studio 17 2022','-A','x64','-DVYNIC_BUILD_READ_ONLY_CHANNEL_TEST=ON',('-DVYNIC_FLUTTER_CPP_WRAPPER='+$FlutterWrapper),('-DVYNIC_FLUTTER_ENGINE_DIR='+$FlutterEngine))
Run-Checked 'channel-build' 'cmake' @('--build',$channelBuild,'--config','Release')
Run-Checked 'channel-tests' 'ctest' @('--test-dir',$channelBuild,'-C','Release','--output-on-failure','-V')

$helper=Join-Path $helperBuild 'Release/vynic_print_helper.exe'
$helperHash=(Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant()
$oldHelperPath=$env:VYNIC_PRINT_HELPER_TEST_PATH
$oldHelperHash=$env:VYNIC_PRINT_HELPER_TEST_SHA256
try {
  $env:VYNIC_PRINT_HELPER_TEST_PATH=$helper
  $env:VYNIC_PRINT_HELPER_TEST_SHA256=$helperHash
  Run-Checked 'go-transport-tests' $PrintTransportTestExe @('-test.v','-test.timeout=60s')
} finally {
  $env:VYNIC_PRINT_HELPER_TEST_PATH=$oldHelperPath
  $env:VYNIC_PRINT_HELPER_TEST_SHA256=$oldHelperHash
}
Verify-Source
Verify-CachedSdk
$receipt=[ordered]@{
  scope='nonphysical source-only helper/guard/channel qualification'
  helperSha256=$helperHash
  helperBytes=(Get-Item -LiteralPath $helper).Length
  helperProtocol=1
  flutterEngineStarted=$false
  productStarted=$false
  serviceOperations=$false
  driverOperations=$false
  documentsSubmitted=0
  positiveWrites='fake APIs/processes only'
  sourceHashesUnchanged=$true
  cachedSdkHashesUnchanged=$true
}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'receipt.json')
$receipt | ConvertTo-Json -Depth 6
