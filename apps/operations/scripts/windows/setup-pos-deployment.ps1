param(
  [string]$AppRoot = "C:\Vynic\App",
  [string]$DeploymentRoot = "C:\ProgramData\Vynic\Deployment",
  [string]$ShareName = "VynicDeployDrop",
  [string]$ShareChangeAccess,
  [string]$ScheduledTaskName = "VynicApplyStagedUpdate",
  [string]$BootstrapReleaseDir,
  [switch]$SkipShare,
  [switch]$SkipScheduledTask,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an elevated PowerShell window on the POS."
  }
}

function Write-SetupLog {
  param([string]$Message)
  Write-Host "[$((Get-Date).ToUniversalTime().ToString("o"))] $Message"
}

function Copy-UpdaterScript {
  param([string]$TargetRoot)

  $source = Join-Path $PSScriptRoot "apply-staged-update.ps1"
  if (!(Test-Path $source -PathType Leaf)) {
    throw "Missing updater script beside setup script: $source"
  }

  $target = Join-Path $TargetRoot "apply-staged-update.ps1"
  Copy-Item $source $target -Force
  Write-SetupLog "Installed updater script: $target"
  return $target
}

function Ensure-Share {
  param(
    [string]$Name,
    [string]$Path,
    [string]$ChangeAccess
  )

  $existing = Get-SmbShare -Name $Name -ErrorAction SilentlyContinue
  if ($existing) {
    if ($existing.Path -ne $Path) {
      if (!$Force) {
        throw "SMB share '$Name' already exists at '$($existing.Path)'. Use -Force to recreate it for '$Path'."
      }
      Remove-SmbShare -Name $Name -Force
    } else {
      Write-SetupLog "SMB share already exists: \\$env:COMPUTERNAME\$Name"
      return
    }
  }

  if ([string]::IsNullOrWhiteSpace($ChangeAccess)) {
    $ChangeAccess = "$env:COMPUTERNAME\$env:USERNAME"
  }

  New-SmbShare -Name $Name -Path $Path -ChangeAccess $ChangeAccess | Out-Null
  & icacls $Path /grant "${ChangeAccess}:(OI)(CI)M" | Out-Null
  Write-SetupLog "Created SMB share: \\$env:COMPUTERNAME\$Name"
  Write-SetupLog "Granted modify access to: $ChangeAccess"
}

function Ensure-ScheduledTask {
  param(
    [string]$TaskName,
    [string]$UpdaterPath
  )

  $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($existing) {
    if (!$Force) {
      Write-SetupLog "Scheduled task already exists: $TaskName"
      return
    }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  }

  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$UpdaterPath`""
  $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments
  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew

  Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings | Out-Null
  Write-SetupLog "Registered on-demand scheduled task: $TaskName"
}

function Bootstrap-CurrentRelease {
  param(
    [string]$SourceReleaseDir,
    [string]$AppRootPath
  )

  if ([string]::IsNullOrWhiteSpace($SourceReleaseDir)) {
    return
  }
  if (!(Test-Path $SourceReleaseDir -PathType Container)) {
    throw "Bootstrap release directory does not exist: $SourceReleaseDir"
  }

  $bootstrapPath = Join-Path $AppRootPath "releases\bootstrap"
  if (Test-Path $bootstrapPath) {
    if (!$Force) {
      Write-SetupLog "Bootstrap release already exists: $bootstrapPath"
    } else {
      Remove-Item $bootstrapPath -Recurse -Force
      Copy-Item $SourceReleaseDir $bootstrapPath -Recurse -Force
      Write-SetupLog "Replaced bootstrap release: $bootstrapPath"
    }
  } else {
    Copy-Item $SourceReleaseDir $bootstrapPath -Recurse -Force
    Write-SetupLog "Copied bootstrap release: $bootstrapPath"
  }

  $currentPath = Join-Path $AppRootPath "current"
  if (Test-Path $currentPath) {
    $item = Get-Item $currentPath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or !$item.PSIsContainer) {
      if ($Force) {
        Remove-Item $currentPath -Force
      } else {
        Write-SetupLog "Current release pointer already exists: $currentPath"
        return
      }
    } else {
      throw "$currentPath exists and is not a junction. Move it manually before bootstrapping."
    }
  }

  if (!(Test-Path $currentPath)) {
    & cmd.exe /c mklink /J "$currentPath" "$bootstrapPath" | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to create current junction."
    }
    Write-SetupLog "Created current junction: $currentPath -> $bootstrapPath"
  }
}

Assert-Admin

$stagingIncoming = Join-Path $AppRoot "staging\incoming"
$stagingExtracted = Join-Path $AppRoot "staging\extracted"
$releases = Join-Path $AppRoot "releases"

New-Item -ItemType Directory -Force -Path $stagingIncoming, $stagingExtracted, $releases, $DeploymentRoot | Out-Null
Write-SetupLog "Created deployment directories."

$updaterPath = Copy-UpdaterScript -TargetRoot $DeploymentRoot

if (!$SkipShare) {
  Ensure-Share -Name $ShareName -Path $stagingIncoming -ChangeAccess $ShareChangeAccess
}

if (!$SkipScheduledTask) {
  Ensure-ScheduledTask -TaskName $ScheduledTaskName -UpdaterPath $updaterPath
}

Bootstrap-CurrentRelease -SourceReleaseDir $BootstrapReleaseDir -AppRootPath $AppRoot

Write-SetupLog "POS deployment setup complete."
Write-Host ""
Write-Host "Builder copy target:"
Write-Host "  \\10.10.10.4\$ShareName"
Write-Host ""
Write-Host "Manual apply command:"
Write-Host "  Start-ScheduledTask -TaskName $ScheduledTaskName"
