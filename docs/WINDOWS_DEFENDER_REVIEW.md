# Windows Defender review and release qualification

## Status and evidence

User-reported detection: **Trojan:Win32/Bearfoos.A!ml**, Severe, against
`%LOCALAPPDATA%\Vynic\bin\VynicSetup.exe`. This is an Antivirus detection, not
SmartScreen publisher reputation. Classification is **unresolved**. Neither a
native rewrite nor a successful build proves a false positive or a clean scan.

The affected Windows file's SHA-256, Defender platform/engine/signature versions,
detection event and Microsoft submission verdict have not been supplied. The Mac
cannot run Microsoft Defender or validate native Windows GUI/COM behavior.

Before replacement the Mac-served Setup was preserved outside the repository:
`/Users/vaanskii/VynicLocalReleases/security-review/previous-artifact.json` and its
associated executable. Its SHA-256 was
`acdf5a61e8fca25be133a933ac130817cceb31431b8bca9f556c1d8e819e6866`.
This is **not yet proven to be the affected Windows file**. The build identifies
Go 1.27.1, module `vynic.local/edge/cmd/setup`, Windows amd64, and a modified source
checkout. Module-cache verification passed; that checks module hashes, not malware
absence or compiler provenance. No dependency was added for the native rewrite.

## Inspection findings

- Downloads are HTTPS-only; signed bootstrap and POS manifests have distinct
  signature domains, pinned Ed25519 keys, product/channel/version/schema checks,
  expiry, size and SHA-256 checks. ZIPs are verified before extraction/activation.
  No signature bypass, plaintext release fallback or downloaded-script execution
  was found in the inspected implementation. This is scoped source/PE inspection,
  not an independent forensic clearance of the affected Windows installation.
- **Fixed validation gap:** Go's ZIP extractor omitted Windows reserved device
  names with superscript digits (`COM¹`, `LPT²`, etc.) and explicit control-character
  rejection. The strengthened policy has tests containing an otherwise valid POS
  executable, so a missing executable cannot mask an accepted unsafe path.
  This requires an authenticated but malformed bundle to reach extraction; no
  evidence connects this defect with Bearfoos. Microsoft documents the reserved
  names: https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
- **Initial trust limitation:** the previous Setup had no Authenticode signature.
  Embedded Ed25519 public keys authenticate the subsequent release chain, but
  do not independently authenticate the initial Setup download/publisher. Actual
  external Authenticode signing and verification remain production prerequisites.
- **Local-account boundary:** ACLs restrict the per-user tree, and setup refuses
  elevation/reparse points. The design does not defend against compromise of that
  same Windows account, which can alter its own binaries/receipt. It is not an
  elevated service or a new security boundary against the installing user.
- POS termination uses a process handle whose full image path was validated;
  it does not kill all processes by image name. Starts now also explicitly reject
  relative POS paths. Setup/Edge use fixed owned absolute executable paths and
  inherit the unelevated user's token. No runas, shell command construction,
  process injection, exclusion setting or Defender configuration change is added.
- Repair pins the Edge baseline. Bounded POS current/staging/rollback, durable
  update admission, binary-only rollback and restaurant data retention remain.
  This review did not change Manager, Cloud/payment domains or Edge authority.

## Heuristic candidates, not causal findings

The old executable combined a Go GUI-subsystem PE, unsigned publisher identity,
encoded PowerShell/WinForms execution with a suppressed console, script-based
WScript.Shell shortcut creation, HTTPS executable downloads, self-copying into
LocalAppData, current-user logon registration, child supervision and binary swaps.
These are observable capabilities that can resemble downloader/persistence
behavior. No access to Defender's model or evidence establishes which triggered
this detection. Legitimate installers also need several of these capabilities.
No obfuscation, packing, renaming for detection avoidance, security exclusions or
policy bypass is part of this change. Unstripped Go test builds retain debugging
information to support inspection; their larger size is expected.

## Native replacement

`cmd/setup/ui_windows.go` owns a Win32 window, labels/buttons, message loop and
progress reporting inside Setup on a locked OS thread. Workers cannot outlive
the operation wait, and Close cannot abandon an in-flight install/repair. There
is no UI subprocess, PowerShell, temporary script or action-output parser.

`internal/setup/shortcuts_windows.go` uses native IShellLinkW/IPersistFile COM to
read ownership and save links. It does not call Resolve or execute a link. It
refuses foreign targets/reparse points and writes explicit `--launch` and normal
window visibility. Native API reference:
https://learn.microsoft.com/en-us/windows/win32/shell/links

No-argument mode remains installer/maintenance GUI. `--launch` requests the
installed POS through Edge; `--host` is the explicit background supervisor only.
Child paths are Setup, pinned Edge and managed POS; no runtime command shell is
launched. Errors continue to reach `logs/setup.log` and interactive native error
dialogs. Logon-host errors remain log-only.

## PE identity and Authenticode release pipeline

- `tool/build-setup.py`: native GUI, `asInvoker`, CompanyName `Vynic`, product and
  description `Vynic Setup`, original filename `VynicSetup.exe`, numeric/string
  file/product version (current test `1.0.2.0`).
- `tool/build-edge-windows.py`: `Vynic Edge` / `VynicEdge.exe`, same company,
  versioned PE/manifest and unelevated execution. This build does not replace an
  existing installed/pinned Edge.
- POS-only `apps/operations/tool/product.py prepare`: `Vynic POS` / `vynic_pos.exe`,
  CompanyName `Vynic`; Flutter version macros remain. Manager metadata is unchanged.
- `tool/windows_pe.py`: explicit version/manifest resources, inspected after build.
- `tool/sign-windows-release.py`: requires all three exact product filenames,
  absolute Windows SDK SignTool/binary paths, valid PE product fields, a selected
  current-user certificate thumbprint and an HTTPS RFC3161 timestamp URL. It signs
  with SHA-256, verifies every resulting signature with `/pa /all /v`, and writes
  the final binary hashes. A partial failure is not reported as a completed release.

On the controlled Windows release host, build all three outputs and then run:

```powershell
python C:\src\vynic\apps\edge\tool\sign-windows-release.py `
  --signtool 'C:\Program Files (x86)\Windows Kits\10\bin\<SDK-version>\x64\signtool.exe' `
  --thumbprint '<code-signing-certificate-thumbprint>' `
  --timestamp-url 'https://<your-certificate-provider-RFC3161-endpoint>' `
  --report C:\release\authenticode-report.json `
  C:\release\VynicSetup.exe C:\release\VynicEdge.exe C:\release\pos\vynic_pos.exe
```

The certificate/private key stays in the external current-user certificate
store/HSM/provider. The thumbprint selects it; it is not the signing digest.
Use a stable, legally verified publisher certificate identity. `Vynic` PE brand
metadata is not a certificate or proof of publisher ownership. No PFX, passwords,
private keys or production signing material are put in source or application
binaries. Microsoft SignTool reference:
https://learn.microsoft.com/en-us/dotnet/framework/tools/signtool-exe

Order is important: **build -> Authenticode sign/verify -> ZIP -> SHA-256 and
Ed25519 manifest signing -> publish**. Signing a binary after ZIP/manifest
creation changes bytes and requires recreating the ZIP and signed metadata.
SignTool is an explicitly invoked release-engineering tool, never run by Setup.
The separate local build-pos packaging command still uses PowerShell on the
Windows developer's machine; no such script ships/executes in installed Setup.

## Current test artifacts

The native rewrite review artifact (1.0.2.0) was built and served as
`https://10.10.10.3:8443/VynicSetup.exe` (the same fixed name).
Local file:
`/Users/vaanskii/VynicLocalReleases/security-review/native/VynicSetup.exe`

SHA-256:
`ab00cb1d548b919ba636bd90633d24f8ab396487096fc4f0d422bac5b6cef6f5`

This recorded 1.0.2.0 artifact is Windows amd64, GUI subsystem, `asInvoker`, 25,947,648 bytes, version 1.0.2.0,
and **unsigned**. No external certificate is configured. It has not been scanned
by Defender or executed on Windows in this review.

Separate Edge test artifact (not activated/published as a replacement baseline):
`/Users/vaanskii/VynicLocalReleases/security-review/native/VynicEdge.exe`
SHA-256: `f48fe52fbc02514990a1018dac3456af0eeb4a7a2feee72249d4be8e2b3a4206`.
The full artifact inventory is `security-review/native-artifacts.json`.
The POS metadata/signing workflow still requires a real Windows Flutter build.

## Windows retest and exact-artifact submission

Do not run a quarantined/detected executable by overriding Defender. Keep normal
protection/remediation enabled. Use a disposable Windows test machine/account for
installation qualification. Download the new Setup under its unchanged filename.
In PowerShell, before executing it:

```powershell
$p = "$env:USERPROFILE\Downloads\VynicSetup.exe"
Get-FileHash -Algorithm SHA256 -LiteralPath $p
(Get-Item -LiteralPath $p).VersionInfo | Format-List CompanyName,ProductName,FileDescription,FileVersion,ProductVersion,OriginalFilename
Get-AuthenticodeSignature -LiteralPath $p | Format-List Status,StatusMessage,SignerCertificate
Update-MpSignature
Get-MpComputerStatus | Format-List AMProductVersion,AMEngineVersion,AntivirusSignatureVersion,AntivirusSignatureLastUpdated,RealTimeProtectionEnabled
Start-MpScan -ScanType CustomScan -ScanPath $p
Get-MpThreatDetection | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10 | Format-List *
```

Updating/scanning may require an elevated diagnostic PowerShell session; Setup
itself must still run as the normal POS user. An alternative documented custom
scan is `MpCmdRun.exe -Scan -ScanType 3 -File <absolute-file-path>` using the
installed, absolute Defender tool path. Do not use disable-remediation options.
Reference:
https://learn.microsoft.com/en-us/defender-endpoint/command-line-arguments-microsoft-defender-antivirus

Record hash, signature state, Defender engine/intelligence version, detection
name, event/time and affected path. If Defender has already quarantined the file,
record that limitation instead of restoring/bypassing protection for testing.
Only after a clean scan, test installer/Cancel, install, `--launch`, explicit
`--host`, repair and uninstall in the disposable account. Scan the installed
`%LOCALAPPDATA%\Vynic\bin\VynicSetup.exe` as well and compare its hash to the
download. Check that no powershell.exe/cmd.exe child is created. Native UI/DPI,
COM shortcuts, startup integration, AV interactions and filesystem behavior
remain Windows qualification work.

If detection remains, use **Software developer** at:
https://www.microsoft.com/en-us/wdsi/filesubmission
Select Microsoft Defender Antivirus and the option reporting a suspected
incorrect detection. Submit the **exact detected bytes**, SHA-256, detection name,
scan/version records, reproduction steps, product/publisher information and a
brief account of the native implementation/signing state. Use the preserved prior
sample only if its hash matches the affected original. Do not include restaurant
data, credentials or private signing material. Nothing was submitted automatically
by this task; retain Microsoft's submission ID and determination.

A fresh binary scanning clean is a useful result, but does not establish why the
old one was detected. A confirmed false positive requires an explicit Microsoft
analysis of the matching artifact (or concrete root-cause evidence), followed by
retesting the unchanged bytes with the relevant updated security intelligence.
Unexpected/mismatched hashes, unexplained code/network behavior or a substantive
Microsoft malware finding requires a code/supply-chain investigation. Do not label
that a reputation problem or try alternate encodings/builds to evade detection.

## Validation performed and limits

Passed on macOS: installer/updater `go test -race`, module checksum verification,
mode parsing, ZIP rejection/recovery tests, PE resource/signing preflight tests,
POS-versus-Manager metadata preparation tests, local-lab regression tests,
Windows cross-builds/vet and HTTPS artifact/manifest verification.

Windows-only tests are included and cross-compiled, not executed here:
`TestNativeProgressLifecycle`, `TestWin32ABISizes`, and
`TestNativeShortcutRoundtripAndForeignOwnership` (temporary shortcut directories).
Native behavior, Authenticode issuance/signing and Defender retest/Microsoft verdict
are pending. No Windows Defender result or false-positive clearance is claimed.


The local endpoint subsequently received Setup 1.0.3.0 (destination/update wizard).
Its build record is `~/VynicLocalReleases/work/setup-wizard-build.json`; do not use
this report's earlier 1.0.2.0 hash to identify that later binary. Defender and native
Windows qualification remain separate for each exact artifact.
