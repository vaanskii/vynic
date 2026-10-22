param([Parameter(Mandatory=$true)][string]$ExpectedStageReceiptSHA256)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest
$stage = '\\Mac\Home\Developer\vynic\docs\proofs\POS_SHARED_PRINT_GO_275688e1_2026-10-06\windows-software-go-packages-stage-v2'
$resultShare = '\\Mac\Home\Developer\vynic\docs\proofs\POS_SHARED_PRINT_GO_275688e1_2026-10-06\windows-software-go-packages-result-v2'
$expectedSid = 'S-1-5-21-611125631-3759947118-1641436196-1000'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -ne $expectedSid -or $identity.Name -ne 'VANSKI\vaanskii' -or $env:PROCESSOR_ARCHITECTURE -ne 'ARM64') { throw 'Pinned current-user ARM64 context required' }
$base = Join-Path $env:LOCALAPPDATA 'VynicReadinessPrinterAgent\software-v2-d6f8ecef582b'
if ((Test-Path -LiteralPath $base) -or (Test-Path -LiteralPath $resultShare)) { throw 'Fresh qualification directory is occupied' }
if ((Get-FileHash -LiteralPath (Join-Path $stage 'stage-receipt.json') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedStageReceiptSHA256) { throw 'Stage receipt pin mismatch' }
New-Item -ItemType Directory -Path $base | Out-Null
$output = Join-Path $base 'output'
$temporary = Join-Path $base 'temporary'
New-Item -ItemType Directory -Path $output,$temporary | Out-Null
$source = Join-Path $base 'source'
$packages = [ordered]@{}
$jobs = [ordered]@{}
$status = 'FAILED'
$failure = $null
$sourceBefore = $false
$sourceAfter = $false
$binaryBefore = $false
$binaryAfter = $false
$bundleBefore = $false
$bundleAfter = $false
$jobsBefore = $null
$jobsAfter = $null
$started = [DateTime]::UtcNow.ToString('o')
function Hash([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function VerifySource($manifest) {
  $entries = @($manifest.files.PSObject.Properties)
  if ($entries.Count -ne 1109 -or $manifest.count -ne 1109 -or @(Get-ChildItem -LiteralPath $source -Recurse -File -Force).Count -ne 1109) { throw 'Exact1109 source manifest required' }
  foreach ($entry in $entries) {
    $path = Join-Path $source ($entry.Name.Replace('/', '\'))
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -ne $entry.Value.bytes -or (Hash $path) -ne $entry.Value.sha256) { throw ('Source mismatch: ' + $entry.Name) }
  }
}
function VerifyBinaries($manifest) {
  foreach ($arch in @('arm64','amd64')) {
    $root = Join-Path $base ('binaries-' + $arch)
    $entries = @($manifest.artifacts.PSObject.Properties | Where-Object { $_.Value.architecture -eq $arch })
    if ($entries.Count -ne 5 -or @(Get-ChildItem -LiteralPath $root -File -Force).Count -ne 5) { throw 'Exact5 per-architecture compiler artifacts required' }
    foreach ($entry in $entries) {
      $path = Join-Path $root $entry.Value.filename
      if ((Get-Item -LiteralPath $path).Length -ne $entry.Value.bytes -or (Hash $path) -ne $entry.Value.sha256) { throw ('Compiler binary mismatch: ' + $entry.Name) }
    }
  }
}
function VerifyBundles($manifest) {
  foreach ($arch in @('arm64','amd64')) {
    $root = Join-Path $base ('bundle-' + $arch)
    $bundle = $manifest.bundles.PSObject.Properties[$arch].Value
    $entries = @($bundle.files.PSObject.Properties)
    if ($entries.Count -ne 4 -or @(Get-ChildItem -LiteralPath $root -File -Force).Count -ne 4) { throw 'Exact4 shipped bundle artifacts required' }
    foreach ($entry in $entries) {
      $path = Join-Path $root $entry.Name
      if ((Get-Item -LiteralPath $path).Length -ne $entry.Value.bytes -or (Hash $path) -ne $entry.Value.sha256) { throw ('Packaged bundle mismatch: ' + $arch + '/' + $entry.Name) }
    }
    $document = Get-Content -Raw (Join-Path $root 'manifest.json') | ConvertFrom-Json
    if ($document.physicalEligible -ne $false -or $document.provisionStatus -ne 'HELD_PROVISIONING' -or $document.agentArchitecture -ne $arch -or $document.helperArchitecture -ne $arch) { throw 'Packaged bundle must remain held and architecture-matched' }
  }
}
try {
  $receipt = Get-Content -Raw (Join-Path $stage 'stage-receipt.json') | ConvertFrom-Json
  foreach ($entry in $receipt.artifacts.PSObject.Properties) {
    $path = Join-Path $stage $entry.Name
    if ((Hash $path) -ne $entry.Value.sha256 -or (Get-Item -LiteralPath $path).Length -ne $entry.Value.bytes) { throw ('Stage artifact mismatch: ' + $entry.Name) }
    Copy-Item -LiteralPath $path -Destination (Join-Path $base $entry.Name)
  }
  Expand-Archive -LiteralPath (Join-Path $base 'source1109.zip') -DestinationPath $source
  foreach ($arch in @('arm64','amd64')) {
    Expand-Archive -LiteralPath (Join-Path $base ($arch + '-packages-cli.zip')) -DestinationPath (Join-Path $base ('binaries-' + $arch))
    Expand-Archive -LiteralPath (Join-Path $base ($arch + '-packaged-bundle.zip')) -DestinationPath (Join-Path $base ('bundle-' + $arch))
  }
  $sourceManifest = Get-Content -Raw (Join-Path $base 'source-manifest.json') | ConvertFrom-Json
  $binaryManifest = Get-Content -Raw (Join-Path $base 'binary-manifest.json') | ConvertFrom-Json
  $bundleManifest = Get-Content -Raw (Join-Path $base 'packaged-bundle-manifest.json') | ConvertFrom-Json
  VerifySource $sourceManifest
  $sourceBefore = $true
  VerifyBinaries $binaryManifest
  $binaryBefore = $true
  VerifyBundles $bundleManifest
  $bundleBefore = $true
  Get-ChildItem -LiteralPath $source -Recurse -File -Force | ForEach-Object { $_.IsReadOnly = $true }
  $env:TEMP = $temporary
  $env:TMP = $temporary
  $env:GOPROXY = 'off'
  $env:GOTOOLCHAIN = 'local'
  $env:HTTP_PROXY = 'http://127.0.0.1:9'
  $env:HTTPS_PROXY = 'http://127.0.0.1:9'
  $env:NO_PROXY = 'localhost,127.0.0.1,::1'
  $jobsBefore = @(Get-CimInstance -ClassName Win32_PrintJob).Count
  if ($jobsBefore -ne 0) { throw 'Existing spooler jobs prevent zero-job qualification' }
  foreach ($arch in @('arm64','amd64')) {
    $env:VYNIC_PRINTER_AGENT_BINARY = Join-Path $base ('bundle-' + $arch + '\vynic-printer-agent.exe')
    $cliSHA = Hash $env:VYNIC_PRINTER_AGENT_BINARY
    foreach ($name in @('printerprovisioning','printeragent','printerdaemon','printer-agent-command')) {
      $key = $arch + '/' + $name
      $cwd = if ($name -eq 'printer-agent-command') { Join-Path $source 'apps\edge\cmd\printer-agent' } else { Join-Path $source ('apps\edge\internal\' + $name) }
      $exe = Join-Path $base ('binaries-' + $arch + '\' + $name + '.test.exe')
      $stdout = Join-Path $output ($arch + '-' + $name + '.stdout.log')
      $stderr = Join-Path $output ($arch + '-' + $name + '.stderr.log')
      $before = @(Get-CimInstance -ClassName Win32_PrintJob).Count
      if ($before -ne 0) { throw ('Existing spooler jobs before ' + $key) }
      $watch = [Diagnostics.Stopwatch]::StartNew()
      Write-Output ('START ' + $key + ' ' + [DateTime]::UtcNow.ToString('o'))
      try {
        $process = Start-Process -FilePath $exe -ArgumentList @('-test.v','-test.timeout=10m') -WorkingDirectory $cwd -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
        $watch.Stop()
        $packages[$key] = [ordered]@{ status=$(if ($process.ExitCode -eq 0) { 'PASS' } else { 'FAILED' }); exitCode=$process.ExitCode; elapsedMs=$watch.ElapsedMilliseconds; workingDirectory=$cwd; binarySHA256=(Hash $exe); packagedCLISHA256=$cliSHA; arguments=@('-test.v','-test.timeout=10m'); stdoutSHA256=(Hash $stdout); stderrSHA256=(Hash $stderr) }
        Write-Output ('END ' + $key + ' exit=' + $process.ExitCode + ' elapsedMs=' + $watch.ElapsedMilliseconds)
      } catch {
        $watch.Stop()
        $packages[$key] = [ordered]@{ status='FAILED'; exitCode=$null; elapsedMs=$watch.ElapsedMilliseconds; failure=$_.ToString() }
        Write-Output ('ERROR ' + $key + ' ' + $_.ToString())
      }
      $after = @(Get-CimInstance -ClassName Win32_PrintJob).Count
      $jobs[$key] = [ordered]@{before=$before; after=$after}
      if ($after -ne 0) { throw ('Unexpected spooler jobs after ' + $key) }
    }
  }
  VerifySource $sourceManifest
  $sourceAfter = $true
  VerifyBinaries $binaryManifest
  $binaryAfter = $true
  VerifyBundles $bundleManifest
  $bundleAfter = $true
  if ($packages.Count -ne 8 -or @($packages.Values | Where-Object { $_.status -ne 'PASS' }).Count -ne 0) { throw 'One or more Windows package tests failed; logs retained without source changes' }
  $status = 'PASS'
} catch {
  $failure = $_.ToString()
} finally {
  try { $jobsAfter = @(Get-CimInstance -ClassName Win32_PrintJob).Count } catch { $failure = 'Final spooler inventory unavailable: ' + $_.ToString(); $status = 'FAILED' }
  if ($jobsAfter -ne 0) { $failure = 'Final spooler jobs were not zero: ' + $failure; $status = 'FAILED' }
  New-Item -ItemType Directory -Path $resultShare | Out-Null
  Get-ChildItem -LiteralPath $output -File | Copy-Item -Destination $resultShare
  $result = [ordered]@{schema=2;status=$status;failure=$failure;startedUtc=$started;completedUtc=[DateTime]::UtcNow.ToString('o');guestBase=$base;currentUser=$identity.Name;currentSID=$identity.User.Value;guestArchitecture=$env:PROCESSOR_ARCHITECTURE;binaryArchitectures=@('arm64','amd64');sourceReceiptSHA256='faaaec2f1ece4f8259353666000eb4c0d3aee6143e73ae7fdf90772a937b581b';executionStageSHA256=$ExpectedStageReceiptSHA256;sourceFiles=1109;packages=$packages;spoolerInventories=$jobs;sourceBefore=$sourceBefore;sourceAfter=$sourceAfter;binaryBefore=$binaryBefore;binaryAfter=$binaryAfter;bundleBefore=$bundleBefore;bundleAfter=$bundleAfter;printJobsBefore=$jobsBefore;printJobsAfter=$jobsAfter;physicalDocumentsSubmitted=0;validRAWCalls=0;SCMRegistrations=0;machineRestarts=0;VMSettingsChanges=0;persistentCredentialChanges=0;productStarts=0;limitations=@('Actual packaged foreground CLI, synthetic temporary SQLite/mTLS; HELD_PROVISIONING always remains.','ARM64 packages run natively; amd64 packages run under Windows-on-ARM emulation.','SCM registration, actual service-account lifecycle, registered-service restart, OS reboot/power loss and physical printer/model/cut/beep acceptance remain not-run.','Installer backend tests inject fakes; no actual service/account/ACL/trust/driver/security changes.','Spooler inventory records are point-in-time observations; no continuous Winspool syscall tracing claimed.','Temporary test certificates are synthetic and do not alter persistent Windows trust or product credentials.')}
  [IO.File]::WriteAllText((Join-Path $resultShare 'windows-software-go-packages.json'),($result | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
  Write-Output ($result | ConvertTo-Json -Depth 12)
}
if ($status -ne 'PASS') { throw $failure }
