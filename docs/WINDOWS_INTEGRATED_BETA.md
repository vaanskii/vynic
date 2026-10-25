# Integrated beta qualification

This source adds an explicit **Upgrade POS + Edge** action in the downloaded
Setup (also `--upgrade`). It does not silently schedule a background upgrade.
Repair remains pinned; the existing POS-only Update Now flow remains separate.
The downloaded Setup must be outside the install tree; POS must be closed
normally, previous startup health must pass, and pending POS updates must finish.
No process is killed merely to make an upgrade succeed.

Both candidate ZIPs are verified under the installed distribution's pinned trust
and current compatibility policy before binary selection. Bootstrap/Edge/POS
versions must advance and the existing release high-water must be exceeded.
Endpoint/trust changes are rejected. No Hive, Edge identity, updater SQLite,
consent rows or counters are restored from backups. A private journal retains
previous POS bytes and the old Edge receipt through candidate startup probation.
On interrupted/failed startup, recovery restores only a licensing-capable
previous POS+Edge decision while keeping monotonic counters. The exact previous
POS must carry `licenseProtocol: 1` in its publisher-signed POS manifest. After
a POS-only update, Setup retrieves the signed per-version proof for the actual
installed version, checks its high-water bound, and downloads its signed ZIP.
Every installed file must match the verified extracted ZIP. The journal retains
that proof and the ZIP; recovery rechecks its signature/hash and re-extracts it
instead of trusting a mutable backup tree. The installed bootstrap still anchors
the old Edge identity and endpoints, without forcing POS back to its initial
baseline. Setup revalidates installed trust, capability and exact identities
before upgrade and again before recovery. Missing, expired,
forged, unknown or mismatched proof fails closed. This is an explicit migration
restriction: upgrading a pre-licensing installation is refused before binary
mutation; that installation needs a separately qualified migration, not an
automatic fallback to unrestricted sales. A previously created unsafe recovery
journal is retained with all data/binaries for inspection, not restored or erased.
No version-number heuristic grants the capability. Old strict manifest parsers
will reject the new field, so the old POS-only updater cannot install this new
format; use a qualified fresh install or separately qualified migration. Private
R2 publishing also requires this signed capability for the integrated beta.
The new Setup coordinator is retained because
older Setup versions cannot parse its additive bootstrap high-water field.
It does not roll itself back to an incompatible coordinator.

Authenticated POS startup and stability checks determine completion. A launched
or already-running candidate does not count as healthy until that check passes.
If failed POS remains running, close it normally before recovery; Setup refuses
to overwrite running business software. Committed cleanup is retried without
reverting a qualified candidate. Uninstall first resolves pending upgrade state,
then removes application binaries while retaining business data and identities.

The active printer path remains Flutter PrintQueue -> Dart TCP transport or the
bundled native Windows RAW spooler channel. The same operations Windows runner
is copied by `apps/operations/tool/product.py` into the isolated POS product.
There is no separate Go/toolchain install. `VynicEdge.exe` owns local host/update
and authorized sync duties; `cmd/printer-agent` remains an explicitly held
prototype and is not started by Setup. A second print daemon would duplicate
ownership rather than complete this path. Real paper/driver/cutter acceptance
must be performed on the intended printers with explicit permission.

Printer tests now seed one consistent Venue and separately test refusal of a
foreign-Venue enrollment; production tenant checks are unchanged. Runtime
feature revocation is independent of printer configuration publication, so test
faults/barriers target only printer writes. The real mTLS child-process fixture
uses generated disposable identities, not a physical printer agent. All 448
printer/update-readiness tests across 27 files pass locally with that fixture.
This is not Windows hardware qualification.

The new combined Windows beta is intended to use version 1.1.0/build19 or a later
reviewed monotonic release, exceeding old beta1.0.1 and lab1.0.14 by version.
No installed antirollback counters or trust roots may be reset to accept it.
Existing laboratory trust/distribution may require a separate approved migration.
The earlier build18 ZIP is historical evidence only. Final native build,
licenses/public pin, signatures, clean install/repair/uninstall and physical
printer evidence must be recorded against the new exact source/archive hashes.

Mail source is integrated with disabled defaults and `.invalid` example values;
SMTP credentials remain backend-only. Do not embed them in the installer. R2
live publishing, Worker deployment and hostname migration are independent of
local installer assembly. No release, artifact upload or operational install
is performed by these source changes.
