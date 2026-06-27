# LAN deployment for Windows POS

This is the first-stage local deployment system for development builds. It uses
only the LAN, Windows release folders, SMB/Robocopy, and a POS-local apply
script with rollback.

## Roles

- Mac: edit source.
- Parallels Windows: build and package Windows release.
- Windows POS: receive a staged package and apply it locally.

The POS remains the only operational POS, the only print host, and the Hive
source of truth.

## Protected files and data

The deployment scripts never reference the Hive data directory. The package
script also excludes:

```text
data/flutter_assets/.env
```

When applying an update, the POS script copies the existing local `.env` from
the active release into the new release if it exists. Printer settings, logs,
licenses, callback configuration, and Hive boxes remain outside the release
payload.

## POS folder layout

Recommended POS layout:

```text
C:\Vynic\App\current
C:\Vynic\App\releases
C:\Vynic\App\staging\incoming
C:\Vynic\App\staging\extracted
C:\ProgramData\Vynic\Deployment
```

`current` is a junction that points to the active release. The updater switches
that junction during deployment and switches it back during rollback.

If the current POS app is already installed somewhere else, bootstrap once by
copying the known-good release bundle into a folder under:

```text
C:\Vynic\App\releases\bootstrap
```

Then create the first `current` junction:

```powershell
cmd.exe /c mklink /J C:\Vynic\App\current C:\Vynic\App\releases\bootstrap
```

## One-time POS setup

Run the POS setup script from an elevated PowerShell window on the real POS:

```powershell
.\scripts\windows\setup-pos-deployment.ps1
```

This creates the deployment folders, installs `apply-staged-update.ps1` under
`C:\ProgramData\Vynic\Deployment`, creates the SMB drop, and registers an
on-demand scheduled task.

The SMB share points at:

```text
C:\Vynic\App\staging\incoming
```

Example share name:

```text
\\10.10.10.4\VynicDeployDrop
```

By default, the share grants modify access to the Windows user running the setup
script. If the Parallels builder should authenticate as a dedicated POS user,
pass it explicitly:

```powershell
.\scripts\windows\setup-pos-deployment.ps1 -ShareChangeAccess "POS-PC\vynic_deploy"
```

The scheduled task runs manually/on demand:

```powershell
Start-ScheduledTask -TaskName VynicApplyStagedUpdate
```

For production safety, do not add a trigger that runs automatically during
restaurant operation.

If there is already a known-good POS release folder, bootstrap `current` during
setup:

```powershell
.\scripts\windows\setup-pos-deployment.ps1 -BootstrapReleaseDir "C:\Existing\VynicRelease"
```

## Build and package on Parallels Windows

From `pos_app_client`:

```powershell
.\scripts\windows\package-release.ps1
```

This runs:

```powershell
flutter build windows --release
```

Then it packages:

```text
build\windows\x64\runner\Release
```

into:

```text
deployment\packages\vynic-pos-<build>-<commit>.zip
deployment\packages\vynic-pos-<build>-<commit>.zip.sha256
```

To package an already-built release without rebuilding:

```powershell
.\scripts\windows\package-release.ps1 -SkipFlutterBuild
```

## Copy package to POS

```powershell
.\scripts\windows\copy-package-to-pos.ps1
```

Default destination:

```text
\\10.10.10.4\VynicDeployDrop
```

Override it if the share name differs:

```powershell
.\scripts\windows\copy-package-to-pos.ps1 -PosDrop "\\10.10.10.4\YourShare"
```

## Apply on the POS

Run the scheduled task, or run directly on the POS:

```powershell
.\apply-staged-update.ps1
```

The script will:

1. Select the newest staged package.
2. Verify package checksum if `.sha256` is present.
3. Extract the package.
4. Verify manifest checksums.
5. Reject packages that try to replace preserved local files.
6. Copy the payload into a new versioned release folder.
7. Copy preserved local `.env` into the new release.
8. Stop `vynic.exe`.
9. Point `current` at the new release.
10. Start the POS.
11. Check `http://127.0.0.1:8081/health`.
12. Roll back to the previous release if startup or health check fails.

## Logs

Deployment state and history are written to:

```text
C:\ProgramData\Vynic\Deployment\active_version.json
C:\ProgramData\Vynic\Deployment\pending_update.json
C:\ProgramData\Vynic\Deployment\deployment_history.jsonl
C:\ProgramData\Vynic\Deployment\deployment.log
```
