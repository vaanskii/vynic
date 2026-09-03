param(
  [string]$ReleaseDir,
  [string]$OutputDir,
  [string]$AppId = "vynic-pos-windows",
  [string]$BuildNumber,
  [string]$BuildName,
  [switch]$SkipFlutterBuild
)

$ErrorActionPreference = "Stop"

function Resolve-ClientRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Read-PubspecVersion {
  param([string]$ClientRoot)

  $pubspecPath = Join-Path $ClientRoot "pubspec.yaml"
  if (!(Test-Path $pubspecPath)) {
    return @{ Name = "0.0.0"; Number = "0" }
  }

  $line = Get-Content $pubspecPath | Where-Object { $_ -match "^\s*version:\s*(\S+)" } | Select-Object -First 1
  if ($line -and $line -match "^\s*version:\s*([^\+]+)\+?(\S*)") {
    $name = $Matches[1]
    $number = if ($Matches[2]) { $Matches[2] } else { "0" }
    return @{ Name = $name; Number = $number }
  }

  return @{ Name = "0.0.0"; Number = "0" }
}

function Get-GitValue {
  param([string[]]$Arguments, [string]$Fallback = "")

  try {
    $value = & git @Arguments 2>$null
    if ($LASTEXITCODE -eq 0) {
      return (($value | Out-String).Trim())
    }
  } catch {
  }
  return $Fallback
}

function Get-RelativePath {
  param([string]$BasePath, [string]$FullPath)

  $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
  $full = [System.IO.Path]::GetFullPath($FullPath)
  $uriBase = [Uri]$base
  $uriFull = [Uri]$full
  return [Uri]::UnescapeDataString($uriBase.MakeRelativeUri($uriFull).ToString()).Replace("/", "\")
}

function Test-RequiredReleaseFiles {
  param([string]$PayloadDir)

  $requiredFiles = @(
    "vynic.exe",
    "flutter_windows.dll",
    "data\icudtl.dat",
    "data\app.so"
  )

  foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $PayloadDir $relativePath
    if (!(Test-Path $fullPath -PathType Leaf)) {
      throw "Required release file is missing: $relativePath"
    }
  }

  $assetManifest = Get-ChildItem (Join-Path $PayloadDir "data\flutter_assets") -Filter "AssetManifest.*" -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if (!$assetManifest) {
    throw "Required Flutter asset manifest is missing: data\flutter_assets\AssetManifest.*"
  }
}

$clientRoot = Resolve-ClientRoot
if (!$ReleaseDir) {
  $ReleaseDir = Join-Path $clientRoot "build\windows\x64\runner\Release"
}
if (!$OutputDir) {
  $OutputDir = Join-Path $clientRoot "deployment\packages"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if (!$SkipFlutterBuild) {
  Push-Location $clientRoot
  try {
    Write-Host "Building Windows release..."
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
      throw "flutter build windows --release failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
}

if (!(Test-Path $ReleaseDir -PathType Container)) {
  throw "Release directory does not exist: $ReleaseDir"
}
$ReleaseDir = (Resolve-Path $ReleaseDir).Path

$pubspecVersion = Read-PubspecVersion -ClientRoot $clientRoot
if (!$BuildName) {
  $BuildName = $pubspecVersion.Name
}
if (!$BuildNumber) {
  $BuildNumber = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
}

$gitCommit = Get-GitValue -Arguments @("-C", $clientRoot, "rev-parse", "--short=12", "HEAD") -Fallback "unknown"
$gitStatus = Get-GitValue -Arguments @("-C", $clientRoot, "status", "--porcelain") -Fallback ""
$gitDirty = ![string]::IsNullOrWhiteSpace($gitStatus)
$builtAtUtc = (Get-Date).ToUniversalTime().ToString("o")
$releaseId = "$BuildNumber-$gitCommit"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "vynic-package-$releaseId"
if (Test-Path $tempRoot) {
  Remove-Item $tempRoot -Recurse -Force
}

$packageRoot = Join-Path $tempRoot "package"
$payloadDir = Join-Path $packageRoot "payload"
New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null

$preservedPaths = @(
  "data/flutter_assets/.env"
)

Write-Host "Copying release payload..."
$sourceFiles = Get-ChildItem $ReleaseDir -Recurse -File
foreach ($file in $sourceFiles) {
  $relative = (Get-RelativePath -BasePath $ReleaseDir -FullPath $file.FullName).Replace("\", "/")
  if ($preservedPaths -contains $relative) {
    Write-Host "Preserving POS-local file, not packaging: $relative"
    continue
  }

  $targetPath = Join-Path $payloadDir ($relative.Replace("/", "\"))
  $targetDir = Split-Path $targetPath -Parent
  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  Copy-Item $file.FullName $targetPath -Force
}

Test-RequiredReleaseFiles -PayloadDir $payloadDir

$files = @()
foreach ($file in Get-ChildItem $payloadDir -Recurse -File) {
  $relative = (Get-RelativePath -BasePath $payloadDir -FullPath $file.FullName).Replace("\", "/")
  $hash = Get-FileHash -Algorithm SHA256 -Path $file.FullName
  $files += [ordered]@{
    path = $relative
    size = $file.Length
    sha256 = $hash.Hash.ToLowerInvariant()
  }
}

$version = [ordered]@{
  appId = $AppId
  version = $BuildName
  buildNumber = $BuildNumber
  gitCommit = $gitCommit
  gitDirty = $gitDirty
  builtAtUtc = $builtAtUtc
  builtBy = $env:COMPUTERNAME
  flutterBuild = "windows-release"
  channel = "lan-dev"
}

$manifest = [ordered]@{
  packageVersion = 1
  appId = $AppId
  releaseId = $releaseId
  createdAtUtc = $builtAtUtc
  version = $version
  requiredFiles = @(
    "vynic.exe",
    "flutter_windows.dll",
    "data/icudtl.dat",
    "data/app.so"
  )
  preservedFiles = $preservedPaths
  files = $files
}

$versionPath = Join-Path $packageRoot "version.json"
$manifestPath = Join-Path $packageRoot "manifest.json"
$version | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $versionPath
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $manifestPath

$packageName = "vynic-pos-$releaseId.zip"
$packagePath = Join-Path $OutputDir $packageName
if (Test-Path $packagePath) {
  Remove-Item $packagePath -Force
}

Write-Host "Creating package: $packagePath"
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $packagePath -Force

$packageHash = Get-FileHash -Algorithm SHA256 -Path $packagePath
$shaPath = "$packagePath.sha256"
"$($packageHash.Hash.ToLowerInvariant())  $packageName" | Set-Content -Encoding ASCII -Path $shaPath

Write-Host "Package created:"
Write-Host "  $packagePath"
Write-Host "  $shaPath"
