param(
  [string]$PackagePath,
  [string]$PackageDir,
  [string]$PosDrop = "\\10.10.10.4\VynicDeployDrop"
)

$ErrorActionPreference = "Stop"

function Resolve-ClientRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Invoke-RobocopyFile {
  param(
    [string]$SourceDir,
    [string]$DestinationDir,
    [string]$FileName
  )

  Write-Host "Copying $FileName to $DestinationDir"
  & robocopy $SourceDir $DestinationDir $FileName /Z /R:3 /W:2 /NFL /NDL /NP
  $code = $LASTEXITCODE
  if ($code -ge 8) {
    throw "Robocopy failed for $FileName with exit code $code"
  }
}

$clientRoot = Resolve-ClientRoot
if (!$PackageDir) {
  $PackageDir = Join-Path $clientRoot "deployment\packages"
}

if (!$PackagePath) {
  $latest = Get-ChildItem $PackageDir -Filter "vynic-pos-*.zip" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
  if (!$latest) {
    throw "No package found in $PackageDir"
  }
  $PackagePath = $latest.FullName
}

$PackagePath = (Resolve-Path $PackagePath).Path
$sourceDir = Split-Path $PackagePath -Parent
$packageFile = Split-Path $PackagePath -Leaf
$shaPath = "$PackagePath.sha256"
$shaFile = Split-Path $shaPath -Leaf

if (!(Test-Path $PosDrop -PathType Container)) {
  throw "POS drop folder is not available: $PosDrop"
}

Invoke-RobocopyFile -SourceDir $sourceDir -DestinationDir $PosDrop -FileName $packageFile

if (Test-Path $shaPath -PathType Leaf) {
  Invoke-RobocopyFile -SourceDir $sourceDir -DestinationDir $PosDrop -FileName $shaFile
} else {
  Write-Warning "No checksum file found beside package: $shaPath"
}

Write-Host "Package copied to POS drop:"
Write-Host "  $PosDrop\$packageFile"
