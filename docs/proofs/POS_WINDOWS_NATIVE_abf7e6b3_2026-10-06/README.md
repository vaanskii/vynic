# Verified Windows software checkpoint

UNCOMMITTED; POS-02 and EDGE-01 remain NOT_DONE.

Input is the previous sealed 932-file source (`abf7e6b3`), reconstructed from
HEAD `275688e1` plus its explicitly sealed candidate sources. The existing
`product.py` prepares 815 files without using unrelated checkout overlays.
`preparation.json` identifies every product-helper change. `preparation-v2.json`
and the retained v2 archive identify the one test-only link-target correction.

The existing Windows 11 ARM guest, cached Flutter 3.44.2/Dart 3.12.2,
MSVC 19.44, SDK 10.0.26100.0 and Firebase 13.5.0 build an amd64 POS Release.
All 815 build-source hashes stay unchanged. The 23 built artifacts are verified
byte-for-byte, including the PE target. The retained raw .NET ZIP uses backslash
names and is not qualified for release publication. This build is not signed,
installed, started or published.

The corrected Windows selection passes 483 tests/32 selected suites and clean
48-item analysis. Original raw receipts are retained. `windows-tests-normalized.json`
explains the raw PowerShell array Count metadata error; the retained selections
and successful log establish the corrected counts.

The fresh corrected native harness compiles/links against actual cached
StandardMethodCodec/ReplyManager and existing engine library/DLL. It initializes
no engine/product and uses a fake BinaryMessenger with a real message-only HWND.
CTest passes 208 channel assertions and 110 fake-core assertions. It reads the
one Print to PDF queue and submits zero documents. Queued old completion across
destruction/recreation is deterministic; blocked/in-flight Winspool, valid RAW
jobs, the live Flutter-engine messenger and hardware acceptance remain untested.
The seven harness sources and 43 cached SDK hashes remain unchanged. Initial
harness results are kept separately from the corrected final run. Independent
source review has no remaining blocker in this bounded read-only scope.

No new tools, packages, drivers, credentials or trust are installed. Existing
product/feed/data are untouched. Physical model/driver/paper/power/sound tests,
owner Receipt/paper/reconciliation policy, authenticated production command
admission, complete shared writers, Go/generated RPC runtime, three-terminal
LAN/handover and reader/rollback qualification remain pending. Existing
nonphysical VM verification was already authorized and is completed here.

`workspace-preservation.json` verifies HEAD/branch/stash, empty index, all 451
unrelated file hashes and the previous 69-artifact seal. `ARTIFACT_SHA256.json`
seals this separate packet; it excludes itself.
