# LAN deployment quickstart

Use this checklist after the deployment scripts are committed and pushed.

## What this gives you

After the first setup, your normal workflow becomes:

```text
Mac: code
Parallels Windows: build + package + copy to POS
Real Windows POS: apply staged update + restart POS
```

No installer is needed for later development updates.

## Before you start

Do this only when the restaurant is not operating.

Make sure the real POS is still the only machine used for:

```text
Hive data
printing
callback ingest
local settings
licenses
logs
```

The updater replaces only the Flutter Windows app release files.

## One-time setup

### 1. Get the latest repo on Parallels Windows

On Parallels Windows:

```powershell
git pull
cd apps/operations
flutter pub get
```

### 2. Build a known-good Windows release

On Parallels Windows:

```powershell
flutter build windows --release
```

The release folder will be:

```text
apps\operations\build\windows\x64\runner\Release
```

### 3. Copy tools and first release to the real POS

Copy this folder to the real POS:

```text
apps\operations\scripts\windows
```

Suggested POS location:

```text
C:\Vynic\Tools\windows
```

Also copy the known-good release folder from Parallels:

```text
apps\operations\build\windows\x64\runner\Release
```

Suggested temporary POS location:

```text
C:\Vynic\BootstrapRelease
```

### 4. Run POS setup

On the real POS, open PowerShell as Administrator:

```powershell
cd C:\Vynic\Tools\windows
powershell.exe -ExecutionPolicy Bypass -File .\setup-pos-deployment.ps1 -BootstrapReleaseDir "C:\Vynic\BootstrapRelease"
```

This creates:

```text
C:\Vynic\App\current
C:\Vynic\App\releases
C:\Vynic\App\staging\incoming
C:\Vynic\App\staging\extracted
C:\ProgramData\Vynic\Deployment
\\10.10.10.4\VynicDeployDrop
Scheduled Task: VynicApplyStagedUpdate
```

### 5. Start the POS from the new app path

Start:

```text
C:\Vynic\App\current\vynic.exe
```

If you use a desktop shortcut, point it to that file.

Confirm the POS opens correctly and still sees the existing Hive data, printer
settings, `.env`, and local configuration.

## Normal update flow after setup

### 1. Build and package on Parallels Windows

On Parallels Windows:

```powershell
cd apps/operations
.\scripts\windows\package-release.ps1
```

This creates a zip package under:

```text
apps\operations\deployment\packages
```

### 2. Copy the package to the POS

On Parallels Windows:

```powershell
.\scripts\windows\copy-package-to-pos.ps1
```

It copies to:

```text
\\10.10.10.4\VynicDeployDrop
```

### 3. Apply the update on the POS

On the real POS:

```powershell
Start-ScheduledTask -TaskName VynicApplyStagedUpdate
```

Or open Task Scheduler and run:

```text
VynicApplyStagedUpdate
```

The updater will stop the POS, switch to the new release, restart it, check
health, and roll back if startup fails.

## Check result

On the real POS, check:

```text
C:\ProgramData\Vynic\Deployment\deployment.log
C:\ProgramData\Vynic\Deployment\deployment_history.jsonl
C:\ProgramData\Vynic\Deployment\active_version.json
```

Success means:

```text
Deployment succeeded
```

Rollback means:

```text
rolled_back
```

## Important safety rules

- Do not apply updates while orders are active.
- Do not point the POS shortcut at old installer paths after setup.
- Do not manually edit files under `C:\Vynic\App\releases` during an update.
- Keep at least one known-good old release folder.
- If anything fails, start the previous release from `C:\Vynic\App\releases`.

## First real test

Before trusting this during development, test once while closed:

1. Start current POS from `C:\Vynic\App\current\vynic.exe`.
2. Package a fresh build on Parallels.
3. Copy it to the POS drop.
4. Run `VynicApplyStagedUpdate`.
5. Confirm POS starts.
6. Confirm printer settings are still present.
7. Confirm Hive data is still present.
8. Confirm `deployment.log` says success.
