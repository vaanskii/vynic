# Revised POS-02 candidate — d194367f

This candidate contains the requested developer-only extra-printer registration,
Home journal-entry removal and simple Georgian kitchen-reprint dialog.
It is **NOT_DONE / UNCOMMITTED** pending supported-model physical acceptance.

`proof.json` is the verification result; `source.zip` is the complete isolated
876-file source plus verification metadata and Windows synthetic-test scripts.
Source manifest SHA-256:
`d194367f8fd0e2f6d9dcfea86f52d09cb605b32779b7904613b00466bd084de8`.
ZIP SHA-256:
`11b1da1ac84fc9930397fb867ab8f5067cd21c2bbd97ae4a723e5f1609c99dc4`.

From the repository, verify saved evidence and the 44 owned checkout paths:

```sh
python3 docs/proofs/POS02_ADMIN_d194367f_2026-10-02/verify_revision.py --check-owned-checkout
```

This command reads archives/source/logs; it launches no application, printer,
network connection or VM. Previous Windows/preview archives remain immutable.
`owned-runtime.patch` contains only the 44 task paths, against base HEAD;
`preservation.json` records branch, stash, empty index and unrelated-WIP checks.
Concurrent Claude changes in platform-web are recorded without modification.

## Later Windows synthetic verification

Do not perform VM operations while they are held. In an approved window, copy
this **new** ZIP to an owned local directory, hash it, extract it, then run the
source verifier with the existing Windows PowerShell/Flutter SDK:

```powershell
(Get-FileHash .\source.zip -Algorithm SHA256).Hash.ToLowerInvariant()
.\Verify-Source.ps1
.\Run-Synthetic-Tests.ps1
```

The last command defaults to a source-verification dry run. The first line must
match the ZIP hash above. To run the listed synthetic tests after verification:

```powershell
.\Run-Synthetic-Tests.ps1 -RunSyntheticTests -FlutterSdk 'C:\path\to\existing\flutter'
```

The script preflights the complete existing Flutter 3.44.1 SDK/tool/native-engine
cache, invokes the cached Dart/tool snapshot directly, disables version checks
and rejects unexpected artifact downloads. It restores its process environment
on exit and makes no persistent security/configuration changes. Use the existing
offline dependency cache. If dependencies are unavailable,
stop and retain the error; do not install, fetch or change credentials/security.
These eleven suites use fresh synthetic Hive stores, blocked HTTP and fake
printer transport. Their macOS run passed 126 checks; this candidate has no
Windows execution result yet. Keep the UTF-8 JSON/stdout and stderr logs for
review. This is a Flutter native test-engine check, not Windows GUI/C++/driver
or physical printer acceptance. The script never starts `main_pos.dart`.

The one-shot physical acceptance runner remains a separate, deferred next step.
Do not use the older optional preview approvals as a cumulative paper budget:
that preview has no global limit across approvals/relaunches. No additional
paper, device interruption or physical operation is authorized by this kit.
