# Windows protected beta test installation

Current package: **POS 1.0.1 build 18**, **Edge / Setup 1.0.1.18**, Windows 10/11
amd64, beta. Runtime source is `1dea429408683d746304e1ed77ed2db693113acf`,
integrated into main. The package contains the reviewed nonfiscal entitlement and
advance-closing fixes, current main backend compatibility, build 16 printer fixes,
and the three previously verified Microsoft-signed x64 CRT DLLs.

The complete offline ZIP is held in GitHub **draft** release `422983256`
(`v1.0.1-beta.18`), asset `673319647`. Obtain it through the existing authenticated
Admin/Owner download action and its temporary protected link. There is no public
catalog or direct anonymous installer download at `releases.vynic.ge`.
The authorized ZIP contains Setup, POS, Edge, signed metadata, checksums and
qualification evidence. Issue a new protected link for this package; previous
links pin their original asset. Extract **all files together** before running Setup.

Archive: `Vynic-Windows-1.0.1-build18-beta-offline.zip` — **47,038,575 bytes**.

SHA-256:
`3065c95c77012bbb5f421f83bb3118fe250f4c9f8ba4099e89a67c4e7ddcd4f7`

Protected delivery uses the download filename `Vynic-Windows-beta-offline.zip`
for the same bytes. Use
`Get-FileHash -Algorithm SHA256 .\Vynic-Windows-beta-offline.zip`
to compare the downloaded archive before extraction (adjust to its actual name).

## Confirm compatibility before user installation

- Export the supported password-protected complete restaurant backup first;
  keep the backup, password and original installer independently available.
  Setup does not perform a restaurant backup or migrate/merge restaurant data.
- Record the running POS version/build/channel and existing installation baseline.
  This is a **fresh-install baseline**, not a qualified in-place upgrade of an
  existing Setup receipt. Installed receipts pin their original bootstrap/Edge
  and repair metadata; this package contains only baseline 18. Repair of a prior
  baseline needs its original complete package. Do not run new Setup over a
  working installation, uninstall it, delete retained state, change its receipt,
  or reset updater high-water values to force this package.
- **Lab POS 1.0.14 is newer than 1.0.1 in SemVer.** Build 18 does not authorize a
  downgrade. An existing-terminal upgrade/reprovisioning path needs separate
  qualification; it was not performed or enabled by this publication.
- For the first-install test, use a clean intended POS PC with no retained Vynic
  installation/data. No new Windows user was created by this task. A separate
  user on the same VM does not isolate all-machine process/port checks.
- Run Setup as the ordinary designated Windows user. Setup/POS/Edge have no
  Authenticode publisher signature. Ed25519 metadata signatures verify package
  identity; they do not provide Windows/SmartScreen publisher trust. Do not
  disable Windows protection or add developer trust roots for this test.
- The package points to **https://api.vynic.ge** with `VYNIC_ENV=staging`,
  `VYNIC_APP_VERSION=1.0.1`, `VYNIC_APP_BUILD=18`. The staging label does not create
  a separate cloud database. Select the correct existing Venue; do not provision
  a duplicate restaurant, import history, or alter historical transactions to test.

## Owner beta test checklist

1. Confirm package hash and versions, then verify clean install, shortcuts,
   normal POS startup and restart. Record Windows version and any visible error.
2. Confirm enrollment identifies the intended Venue and the supported existing
   Manager flow. Protect credentials and device codes in any shared evidence.
3. With nonfiscal entitlement **off**, check POS, Sales, X report, Manager and
   open dialogs: no nonfiscal controls, options or labels should appear. Ordinary
   paid closure must remain usable offline. Missing/unverified permission denies
   nonfiscal closing; an old unbound feature cache needs one successful refresh.
4. If the owner separately requests a controlled entitlement test, only the
   authorized **PlatformUser SUPER_ADMIN** may explicitly enable it for the
   intended Venue. Venue owners, Managers, Staff and read-only support cannot
   grant it. This release did not change any real tenant's entitlement.
   Confirm it appears only after the verified grant; revoke, refresh/reconnect
   and check that even open views remove it. A disconnected POS retains its last
   verified identity-bound grant until it receives a new decision; clock changes
   cannot create or extend permission. No arbitrary 15-minute offline cutoff exists.
5. On a deliberate new test order, record **GEL 1000 gross**, receive **GEL 100
   advance**, then close with **GEL 900 newly collected**. History/ledger/report
   should retain gross 1000, advance 100 and remaining due 900 at closure, with
   exactly one settlement and no deposit-created nonfiscal classification.
   An ordinary recorded sale is not proof of an issued fiscal receipt.
6. Repeat with zero advance, full 1000 advance (zero collected at closure), and
   split cash/card for the remaining 900. Restart/reconnect and allow repeated
   sync; no duplicate payment, revenue or close should appear. Keep synthetic
   records separate from genuine customer transactions; do not rewrite history.
7. Print deliberate receipt/kitchen test output on the intended Windows RAW/TCP
   targets. Verify item/header text, explicit copy labels, routing and error
   feedback. Confirm the matched Edge/Setup versions. Physical output remains
   an owner qualification step; this publication sent no print job.
8. Record results before wider use. Existing-terminal update/repair/uninstall,
   power-loss recovery and physical devices remain separate qualification gates.

## Publication evidence and remaining qualification

- New native Windows build succeeded; 335 native Windows Flutter regressions
  and the same 335 on macOS passed, including the complete repaired build 16
  printing/update selection with no exclusions. Analysis and backend build pass.
- 29 backend unit/HTTP tests, 14 protected-download HTTP/DB tests and five macOS
  Go Setup/updater/signature suites passed. Disposable accounting PostgreSQL:
  107 passed; two hostname-resolution failures reproduce on the unchanged base.
  The separate stale cloud-printer fixture aggregate retains its documented 20
  baseline failures and is not the passing build 16 printing selection.
- Two optional Windows Go signer tests passed. The additional Windows Go run
  was not completed: its Parallels transport hung without an observable guest
  test process, then a bounded direct invocation returned 255 without output.
  That transport was closed; this is no native Setup/runtime qualification.
- All 23 files from the native POS release match the packaged bytes; the three
  included CRT DLLs match previously verified hashes. POS executable and AOT payload
  differ from build 16. Hive 9, Edge schema 2, POS layout 2 and updater protocol 1 match.
- Go production policy and independent OpenSSL verified both Ed25519 envelopes.
  Metadata expires **2026-11-23T21:06:43Z**; pinned beta trust expires 2027-10-24.
  Renew retained metadata before expiry without replacing immutable artifacts.
- Authenticated upstream HEAD 200, resumed Range 206 and full 47,038,575-byte SHA-256
  readback match. New/old anonymous asset URLs, new release tag, technical root,
  generic index, bootstrap/repair paths and automatic update feed return 404.
- The three nonsecret backend installer-selection keys reference asset 673319647,
  size 47038575 and the archive hash above. The existing repository-limited read
  Render credential was preserved; no credential was generated or rotated.
- A real end-user complete/resumed transfer through the current browser grant
  handshake is **not verified**: owner login/browser archive-download permission
  remains pending from the separate task. Upstream readback does not substitute
  for this browser handoff. No permission prompt was bypassed.
- Clean-PC installer/runtime, real enrollment/offline recovery, existing-terminal
  handoff and physical printers remain unqualified. No installer, POS/Edge runtime,
  stable release, automatic update feed, real tenant setting or historical
  transaction was changed by publication. The original dirty checkout is preserved.

See `PROTECTED_WINDOWS_DOWNLOADS.md`, `NONFISCAL_ADVANCE_BETA.md` and
`proofs/WINDOWS_BETA_1.0.1_BUILD18_2026-10-24/publication.json`.
