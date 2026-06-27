param(
  [string]$PackagePath,
  [string]$StagingDir = "C:\Vynic\App\staging\incoming",
  [string]$AppRoot = "C:\Vynic\App",
  [string]$DeploymentRoot = "C:\ProgramData\Vynic\Deployment",
  [string]$ProcessName = "vynic",
  [string]$ExecutableName = "vynic.exe",
  [string]$HealthUrl = "http://127.0.0.1:8081/health",
  [int]$HealthTimeoutSeconds = 60,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$CurrentPath = Join-Path $AppRoot "current"
$ReleasesDir = Join-Path $AppRoot "releases"
$ExtractRoot = Join-Path $AppRoot "staging\extracted"
$ActiveVersionPath = Join-Path $DeploymentRoot "active_version.json"
$PendingUpdatePath = Join-Path $DeploymentRoot "pending_update.json"
$HistoryPath = Join-Path $DeploymentRoot "deployment_history.jsonl"
$LogPath = Join-Path $DeploymentRoot "deployment.log"

$PreservedFiles = @(
  "data/flutter_assets/.env"
)

function Write-DeployLog {
  param([string]$Message)

  $line = "[$((Get-Date).ToUniversalTime().ToString("o"))] $Message"
  Write-Host $line
  Add-Content -Encoding UTF8 -Path $LogPath -Value $line
}

function Write-History {
  param([hashtable]$Entry)

  $Entry.timestampUtc = (Get-Date).ToUniversalTime().ToString("o")
  $Entry | ConvertTo-Json -Depth 8 -Compress | Add-Content -Encoding UTF8 -Path $HistoryPath
}

function Get-LatestPackage {
  if ($PackagePath) {
    return (Resolve-Path $PackagePath).Path
  }

  $latest = Get-ChildItem $StagingDir -Filter "vynic-pos-*.zip" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
  if (!$latest) {
    throw "No staged package found in $StagingDir"
  }
  return $latest.FullName
}

function Assert-PackageChecksum {
  param([string]$ZipPath)

  $shaPath = "$ZipPath.sha256"
  if (!(Test-Path $shaPath -PathType Leaf)) {
    Write-DeployLog "No package .sha256 file found; continuing with manifest file checks only."
    return
  }

  $expected = ((Get-Content $shaPath -Raw).Trim() -split "\s+")[0].ToLowerInvariant()
  $actual = (Get-FileHash -Algorithm SHA256 -Path $ZipPath).Hash.ToLowerInvariant()
  if ($actual -ne $expected) {
    throw "Package checksum mismatch. Expected $expected but found $actual"
  }
}

function Resolve-SafeChildPath {
  param([string]$Root, [string]$RelativePath)

  $candidate = Join-Path $Root ($RelativePath.Replace("/", "\"))
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
  $candidateFull = [System.IO.Path]::GetFullPath($candidate)
  if (!$candidateFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Manifest path escapes package root: $RelativePath"
  }
  return $candidateFull
}

function Test-RequiredFiles {
  param([string]$PayloadDir, [object]$Manifest)

  foreach ($relativePath in $Manifest.requiredFiles) {
    $fullPath = Resolve-SafeChildPath -Root $PayloadDir -RelativePath $relativePath
    if (!(Test-Path $fullPath -PathType Leaf)) {
      throw "Required release file is missing: $relativePath"
    }
  }

  $assetDir = Join-Path $PayloadDir "data\flutter_assets"
  $assetManifest = Get-ChildItem $assetDir -Filter "AssetManifest.*" -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if (!$assetManifest) {
    throw "Required Flutter asset manifest is missing: data/flutter_assets/AssetManifest.*"
  }
}

function Test-ManifestFiles {
  param([string]$PayloadDir, [object]$Manifest)

  $preserved = @{}
  foreach ($relativePath in $PreservedFiles) {
    $preserved[$relativePath.ToLowerInvariant()] = $true
  }

  foreach ($file in $Manifest.files) {
    $relative = [string]$file.path
    if ($preserved.ContainsKey($relative.ToLowerInvariant())) {
      throw "Package attempts to replace preserved POS-local file: $relative"
    }

    $fullPath = Resolve-SafeChildPath -Root $PayloadDir -RelativePath $relative
    if (!(Test-Path $fullPath -PathType Leaf)) {
      throw "Manifest file is missing: $relative"
    }

    $actualHash = (Get-FileHash -Algorithm SHA256 -Path $fullPath).Hash.ToLowerInvariant()
    $expectedHash = ([string]$file.sha256).ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
      throw "Checksum mismatch for $relative"
    }
  }
}

function Get-ActiveReleasePath {
  if (Test-Path $ActiveVersionPath -PathType Leaf) {
    try {
      $active = Get-Content $ActiveVersionPath -Raw | ConvertFrom-Json
      if ($active.path -and (Test-Path $active.path -PathType Container)) {
        return $active.path
      }
    } catch {
    }
  }

  if (Test-Path $CurrentPath -PathType Container) {
    $item = Get-Item $CurrentPath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $item.Target) {
      if ($item.Target -is [array]) {
        return [string]$item.Target[0]
      }
      return [string]$item.Target
    }
    return $CurrentPath
  }

  return $null
}

function Stop-PosProcess {
  $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
  if (!$processes) {
    return
  }

  Write-DeployLog "Stopping POS process: $ProcessName"
  foreach ($process in $processes) {
    try {
      if ($process.MainWindowHandle -ne 0) {
        [void]$process.CloseMainWindow()
      }
    } catch {
    }
  }

  $deadline = (Get-Date).AddSeconds(12)
  while ((Get-Date) -lt $deadline) {
    $remaining = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if (!$remaining) {
      return
    }
    Start-Sleep -Milliseconds 500
  }

  Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force
}

function Set-CurrentRelease {
  param([string]$ReleasePath)

  if (Test-Path $CurrentPath) {
    $item = Get-Item $CurrentPath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or !$item.PSIsContainer) {
      Remove-Item $CurrentPath -Force
    } else {
      throw "$CurrentPath exists and is not a junction. Move the current app into releases first, then rerun."
    }
  }

  $parent = Split-Path $CurrentPath -Parent
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  & cmd.exe /c mklink /J "$CurrentPath" "$ReleasePath" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to create current junction."
  }
}

function Start-PosProcess {
  $exePath = Join-Path $CurrentPath $ExecutableName
  if (!(Test-Path $exePath -PathType Leaf)) {
    throw "POS executable is missing: $exePath"
  }

  Write-DeployLog "Starting POS: $exePath"
  Start-Process -FilePath $exePath -WorkingDirectory $CurrentPath | Out-Null
}

function Test-PosHealth {
  $deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$process) {
      Start-Sleep -Seconds 1
      continue
    }

    try {
      $response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 3
      if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
        return $true
      }
    } catch {
    }

    Start-Sleep -Seconds 1
  }

  return $false
}

function Copy-PreservedFiles {
  param([string]$PreviousPath, [string]$NewPath)

  if (!$PreviousPath) {
    return
  }

  foreach ($relativePath in $PreservedFiles) {
    $source = Resolve-SafeChildPath -Root $PreviousPath -RelativePath $relativePath
    if (!(Test-Path $source -PathType Leaf)) {
      continue
    }

    $target = Resolve-SafeChildPath -Root $NewPath -RelativePath $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item $source $target -Force
    Write-DeployLog "Preserved POS-local file: $relativePath"
  }
}

function Complete-ActiveVersion {
  param([object]$Manifest, [string]$ReleasePath)

  $active = [ordered]@{
    releaseId = $Manifest.releaseId
    path = $ReleasePath
    version = $Manifest.version.version
    buildNumber = $Manifest.version.buildNumber
    gitCommit = $Manifest.version.gitCommit
    activatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  }
  $active | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $ActiveVersionPath
}

function Rollback-ToPrevious {
  param([string]$PreviousPath, [string]$Reason)

  if (!$PreviousPath -or !(Test-Path $PreviousPath -PathType Container)) {
    throw "Cannot rollback because previous release is unavailable. Reason: $Reason"
  }

  Write-DeployLog "Rolling back to previous release: $PreviousPath"
  Stop-PosProcess
  Set-CurrentRelease -ReleasePath $PreviousPath
  Start-PosProcess
  Write-History @{ status = "rolled_back"; reason = $Reason; releasePath = $PreviousPath }
}

function Recover-PendingUpdate {
  if (!(Test-Path $PendingUpdatePath -PathType Leaf)) {
    return
  }

  try {
    $pending = Get-Content $PendingUpdatePath -Raw | ConvertFrom-Json
    $previousPath = [string]$pending.previousPath
    if (![string]::IsNullOrWhiteSpace($previousPath) -and (Test-Path $previousPath -PathType Container)) {
      Write-DeployLog "Found pending update from an interrupted deployment; rolling back first."
      Stop-PosProcess
      Set-CurrentRelease -ReleasePath $previousPath
      Start-PosProcess
      Remove-Item $PendingUpdatePath -Force -ErrorAction SilentlyContinue
      Write-History @{
        status = "recovered_pending_update"
        reason = "interrupted deployment"
        releasePath = $previousPath
      }
      return
    }

    Write-DeployLog "Found pending update but no previous release was available."
  } catch {
    Write-DeployLog "Unable to recover pending update metadata: $($_.Exception.Message)"
  }
}

function Assert-IncomingVersionAllowed {
  param([object]$Manifest)

  if ($Force) {
    return
  }
  if (!(Test-Path $ActiveVersionPath -PathType Leaf)) {
    return
  }

  try {
    $active = Get-Content $ActiveVersionPath -Raw | ConvertFrom-Json
    $activeBuild = [string]$active.buildNumber
    $incomingBuild = [string]$Manifest.version.buildNumber
    if ([string]::IsNullOrWhiteSpace($activeBuild) -or [string]::IsNullOrWhiteSpace($incomingBuild)) {
      return
    }

    $activeNumber = 0D
    $incomingNumber = 0D
    $activeIsNumber = [decimal]::TryParse($activeBuild, [ref]$activeNumber)
    $incomingIsNumber = [decimal]::TryParse($incomingBuild, [ref]$incomingNumber)

    if ($activeIsNumber -and $incomingIsNumber) {
      if ($incomingNumber -le $activeNumber) {
        throw "Incoming build $incomingBuild is not newer than active build $activeBuild. Use -Force to redeploy."
      }
      return
    }

    if ([string]::CompareOrdinal($incomingBuild, $activeBuild) -le 0) {
      throw "Incoming build $incomingBuild is not newer than active build $activeBuild. Use -Force to redeploy."
    }
  } catch {
    throw
  }
}

New-Item -ItemType Directory -Force -Path $StagingDir, $ReleasesDir, $ExtractRoot, $DeploymentRoot | Out-Null
Recover-PendingUpdate

$package = Get-LatestPackage
Write-DeployLog "Applying staged package: $package"
Assert-PackageChecksum -ZipPath $package

$extractDir = Join-Path $ExtractRoot ([System.IO.Path]::GetFileNameWithoutExtension($package))
if (Test-Path $extractDir) {
  Remove-Item $extractDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
Expand-Archive -Path $package -DestinationPath $extractDir -Force

$manifestPath = Join-Path $extractDir "manifest.json"
$payloadDir = Join-Path $extractDir "payload"
if (!(Test-Path $manifestPath -PathType Leaf)) {
  throw "Package is missing manifest.json"
}
if (!(Test-Path $payloadDir -PathType Container)) {
  throw "Package is missing payload directory"
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
Test-RequiredFiles -PayloadDir $payloadDir -Manifest $manifest
Test-ManifestFiles -PayloadDir $payloadDir -Manifest $manifest
Assert-IncomingVersionAllowed -Manifest $manifest

$releaseId = [string]$manifest.releaseId
if ([string]::IsNullOrWhiteSpace($releaseId)) {
  throw "Manifest releaseId is empty"
}

$newReleasePath = Join-Path $ReleasesDir $releaseId
if (Test-Path $newReleasePath) {
  if (!$Force) {
    throw "Release already exists: $newReleasePath. Use -Force to replace it."
  }
  Remove-Item $newReleasePath -Recurse -Force
}

$previousPath = Get-ActiveReleasePath
Copy-Item $payloadDir $newReleasePath -Recurse -Force
Copy-PreservedFiles -PreviousPath $previousPath -NewPath $newReleasePath

$pending = [ordered]@{
  releaseId = $releaseId
  previousPath = $previousPath
  newPath = $newReleasePath
  startedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
}
$pending | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $PendingUpdatePath

try {
  Stop-PosProcess
  Set-CurrentRelease -ReleasePath $newReleasePath
  Start-PosProcess

  if (!(Test-PosHealth)) {
    throw "POS health check failed: $HealthUrl"
  }

  Complete-ActiveVersion -Manifest $manifest -ReleasePath $newReleasePath
  Remove-Item $PendingUpdatePath -Force -ErrorAction SilentlyContinue
  Write-History @{ status = "success"; releaseId = $releaseId; releasePath = $newReleasePath }
  Write-DeployLog "Deployment succeeded: $releaseId"
} catch {
  $reason = $_.Exception.Message
  Write-DeployLog "Deployment failed: $reason"
  Write-History @{ status = "failed"; releaseId = $releaseId; releasePath = $newReleasePath; reason = $reason }
  Rollback-ToPrevious -PreviousPath $previousPath -Reason $reason
  throw
}
