"""Seal the final Windows qualification without rewriting earlier packets."""
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess

task = pathlib.Path(__file__).resolve().parent
repo = pathlib.Path('/Users/vaanskii/Developer/vynic')
parent = repo / 'docs/proofs/POS_SHARED_PRINT_GO_275688e1_2026-10-06'
target = parent / 'software-completion-windows-final'
if target.exists():
    raise SystemExit('Existing final packet must be preserved')
target.mkdir()
provenance = {}

def sha(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()

def copy(origin, relative):
    if origin.is_symlink() or not origin.is_file():
        raise SystemExit('Nonregular proof input: ' + str(origin))
    output = target / relative
    if output.exists():
        raise SystemExit('Duplicate archive path: ' + str(relative))
    expected = sha(origin)
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(origin, output)
    if sha(origin) != expected or sha(output) != expected:
        raise SystemExit('Proof input changed across copy')
    provenance[str(relative)] = {'origin': str(origin), 'sha256': expected, 'bytes': output.stat().st_size}

for directory in ('windows-software-v2', 'software-v2-mac', 'software-v2-mac-retry'):
    for origin in sorted((task / 'verification' / directory).rglob('*')):
        if origin.is_file():
            copy(origin, pathlib.Path('verification') / directory / origin.relative_to(task / 'verification' / directory))
for name in ('final-cohort-v2-source.json', 'final-flutter-v2-test-selection.json',
             'final-flutter-v2-analysis-selection.json'):
    copy(task / 'verification' / name, pathlib.Path('verification') / name)
copy(task / 'metadata/printer-agent-ui-owned-hashes-v2.json', pathlib.Path('metadata/printer-agent-ui-owned-hashes-v2.json'))
for origin in sorted(task.glob('*v2*.py')):
    copy(origin, pathlib.Path('continuation') / origin.name)
copy(pathlib.Path(__file__), pathlib.Path('continuation/seal-windows-final.py'))
copy(task.parent / 'printer-validation/acceptance-matrix-v10-windows-completion.json', pathlib.Path('acceptance-matrix-v10-windows-completion.json'))
for origin in sorted((task.parent / 'printer-validation').glob('*v10*')):
    if origin.is_file() and origin.name != 'acceptance-matrix-v10-windows-completion.json':
        copy(origin, pathlib.Path('matrix-history') / origin.name)

# Large executable/ZIP bytes already reside in immutable sibling stages/results.
# Archive all their metadata/logs here and pin every sibling artifact below.
for directory in sorted(parent.iterdir()):
    if not directory.is_dir() or not directory.name.startswith(('software-windows-', 'windows-software-go-packages-')):
        continue
    for origin in sorted(directory.rglob('*')):
        if origin.is_file() and origin.stat().st_size <= 8_000_000 and origin.suffix not in ('.exe', '.zip'):
            copy(origin, pathlib.Path('windows-stages-results') / directory.name / origin.relative_to(directory))

for name in ('docs/POS_PRINTER_IMPLEMENTATION_REPORT_2026-10-06.md', 'docs/agent-state/VYNIC_PROJECT_STATE.md'):
    copy(repo / name, pathlib.Path('reviewed-documentation') / pathlib.Path(name).name)

reviewed = json.loads((task / 'verification/windows-software-v2/reviewed-printer-port-v2-manifest.json').read_text())
before = json.loads((task.parent / 'workspace-before-hashes.json').read_text())
frozen = json.loads((task / 'verification/final-cohort-v2-source.json').read_text())
for name, value in reviewed.items():
    if sha(repo / name) != value or sha(task / 'source-v2' / name) != value:
        raise SystemExit('Final reviewed source differs: ' + name)
for name, value in before.items():
    if name not in reviewed and sha(repo / name) != value:
        raise SystemExit('Unrelated preimage changed: ' + name)
differences = {}
for name, entry in frozen['files'].items():
    for base in (task / 'source-v2', task / 'final-cohort-v2'):
        if sha(base / name) != entry['sha256']:
            raise SystemExit('Frozen v2 source changed: ' + name)
    actual = sha(repo / name) if (repo / name).is_file() else None
    if actual != entry['sha256']:
        differences[name] = {'workspaceSHA256': actual, 'qualifiedCandidateSHA256': entry['sha256']}
known = json.loads((task.parent / 'printer-validation/workspace-overlay-boundary.json').read_text())['unownedDifferences']
if differences != {name: {k: v[k] for k in ('workspaceSHA256', 'qualifiedCandidateSHA256')}
                    for name, v in known.items() if name in frozen['files']}:
    raise SystemExit('Unexpected dirty-workspace source difference')
for name, entry in known.items():
    actual = sha(repo / name) if (repo / name).is_file() else None
    if actual != entry['workspaceSHA256']:
        raise SystemExit('Historical unowned input changed')

old_packet = parent / 'software-completion-final'
old_seal = old_packet / 'ARTIFACTS.json'
if sha(old_seal) != 'f42021a776158e9d12ccf3a5cec7333f655a45e56a3d6050adc8a147a13faf65':
    raise SystemExit('Earlier621 seal changed')
for name, expected in json.loads(old_seal.read_text()).items():
    if sha(old_packet / name) != expected:
        raise SystemExit('Earlier621 artifact changed')
older_count = 0
for entry in json.loads((task.parent / 'printer-validation/earlier-proof-seal-check.json').read_text()):
    directory = repo / 'docs/proofs' / entry['directory']
    seal = directory / 'ARTIFACT_SHA256.json'
    if sha(seal) != entry['sealSHA256']:
        raise SystemExit('Earlier180 seal changed')
    values = json.loads(seal.read_text())
    for name, expected in values.items():
        if sha(directory / name) != expected:
            raise SystemExit('Earlier180 artifact changed')
    older_count += len(values)

def git(*args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()

identity = {'head': git('rev-parse', 'HEAD'), 'branch': git('branch', '--show-current'),
            'stash': git('rev-parse', 'refs/stash'), 'stagedFiles': git('diff', '--cached', '--name-only')}
if identity != {'head': '275688e1e5c5dc0e26e62705ab0c7670cf16d99a',
                'branch': 'codex/docker-deployment-foundation',
                'stash': '9df454225caec647f67ad4f70ef6038dbbbe41d6', 'stagedFiles': ''}:
    raise SystemExit('Repository identity/index changed')
check = subprocess.run(['git', 'diff', '--check'], cwd=repo, capture_output=True, text=True)
(target / 'git-diff-check.txt').write_text(check.stdout + check.stderr)
if check.returncode:
    raise SystemExit('Diff check failed; packet unsealed')
(target / 'git-status-short.txt').write_text(subprocess.check_output(['git', 'status', '--short'], cwd=repo, text=True))
record = {'recordedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'repository': identity, 'reviewedPaths': len(reviewed),
          'unrelatedPreimagesUnchanged': sum(n not in reviewed for n in before),
          'frozenSourceAndCopyFilesUnchanged': len(frozen['files']),
          'preservedFiveRuntimeDifferences': differences, 'preservedSevenHistoricalDifferences': known,
          'oldSoftware621ArtifactsUnchanged': True, 'earlierArtifactsUnchanged': older_count,
          'diffCheckExit': 0, 'committed': False, 'pushed': False,
          'exactCommittedRuntimeQualified': False, 'dirtyWorkspaceRuntimeQualified': False,
          'POS02Status': 'NOT_DONE'}
(target / 'workspace-final-preservation.json').write_text(json.dumps(record, indent=2) + '\n')
external = {str(f.relative_to(parent)): {'sha256': sha(f), 'bytes': f.stat().st_size}
            for f in sorted(parent.rglob('*')) if f.is_file() and target not in f.parents}
(target / 'EXTERNAL_ARTIFACTS.json').write_text(json.dumps(external, indent=2) + '\n')
(target / 'copy-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
(target / 'README.md').write_text('''# Final printer software qualification

**POS-02 remains NOT_DONE.** This packet completes the authorized software and
report scope. Production issuer/current authorization/route wiring, authenticated
shared LAN composition, full business/Hive writer cutover and rollback remain
implementation dependencies. Actual models/fence or gateway, offline grant policy
and service principal require decisions; SCM/account/OS and physical acceptance
remain pending. No commit, push, deployment or roadmap continuation occurred.

Final source: 1,109 files, manifest faaaec2f1ece4f8259353666000eb4c0d3aee6143e73ae7fdf90772a937b581b.
Exactly two Dart test fixtures gained native path joins; other1,107 inputs,
including201Go/contract/proto inputs, remain unchanged. Production validation was
not relaxed. Original unrelated WIP, branch, HEAD, stash and index are preserved.

- Mac and Windows each pass623visible+51hidden records/39suites with zero skips
  or errors; all68analysis targets clean. Real mutual TLS and manual card/profile/
  offline integration, symlink and directory-escape cases pass on Windows.
- Windows Go: eight runs, nativeARM64 and emulatedamd64,514PASS records=
  104top-level+410subtests,2child-fixture entrypoint skips,0capability skips/failures.
  Both actual packaged CLIs passed foreground health/exclusivity/stop/restart and
  retained-state tests. Their synthetic held-helper configuration does not run
  the bundled helper. Native-helper execution remains separately qualified;
  actual bundle/helper/profile hashes are checked before/after here.
- Retained unchanged-Go macOS normal/race proof:225top-level/764PASS records,
  9fixture-entry skips perrun. Vet/static Windows builds/contracts/scans remain
  retained component proof, not a new broad rerun after Dart-only fixture edits.
- Official preparedPOS main_pos amd64 Release passes with exactly8declared
  metadata/data deltas,23canonical artifacts and unchanged182cached SDK files.
  ZIPf5eb22bfe2ca70f9b9e0434336da548eeb0613ed7d10d1ae43ebe252f1b9b785.
  Local-lab invalid-loopback API origin, no explicitagent profile; product was
  not started/installed/signed/published. Every Windows job inventory is zero.
- MatrixV10:17boundedsoftware counterparts pass; machine-loss counterpart is
  not run. All18full physical/SCM/OS acceptance cases remain not run.

Authoritative outcomes and independent reviews are in verification/windows-software-v2:
windows-software-completion-final-receipt-v2.json,
flutter-combined-independent-review-final.json, go-runtime-independent-review.json,
pos-and-windows-aggregate-independent-review.json and
final-report-state-matrix-independent-review.json. Reviewed report/state are in
reviewed-documentation. acceptance-matrix-v10-windows-completion.json is current;
olderV8/V9/final aliases and the initialV10 candidate remain historical.

All failed history is retained: initial12Windows fixture failures,39visible Mac
loader errors/no test bodies from sandbox loopback denial, two long guest-session
launcher failures followed by the same reviewed script's short-launch success,
and approval-review preflight denial followed by the ONE identical same-tool
retry after the parent forwarded later user clearance. Earlier parser/count
annotations remain history; the normalized loader annotation distinguishes
visible failed loading records from successful hidden setup records.

ARTIFACTS.json seals this packet except itself. EXTERNAL_ARTIFACTS.json pins all
immutable sibling stage/result/bundle bytes relative to the parent proof folder,
including actualPE/ZIP artifacts and the earlier621-file packet. Large binaries
are retained once in those siblings. No earlier packet/seal was rewritten.
copy-provenance maps immutable original receipt paths to archived copies.
''')
seal = {str(f.relative_to(target)): sha(f) for f in sorted(target.rglob('*')) if f.is_file()}
(target / 'ARTIFACTS.json').write_text(json.dumps(seal, indent=2) + '\n')
for name, value in seal.items():
    if sha(target / name) != value:
        raise SystemExit('Final packet seal mismatch')
for name, value in external.items():
    if sha(parent / name) != value['sha256']:
        raise SystemExit('External artifact changed during sealing')
print(json.dumps({'packet': str(target), 'files': len(seal), 'externalArtifacts': len(external),
                  'sealSHA256': sha(target / 'ARTIFACTS.json'), 'unrelatedPreimagesPreserved': record['unrelatedPreimagesUnchanged']}))
