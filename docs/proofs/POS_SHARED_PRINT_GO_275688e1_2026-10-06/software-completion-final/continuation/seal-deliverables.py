"""Archive printer-only evidence without modifying any earlier proof packet."""
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess

task = pathlib.Path(__file__).resolve().parent
root = task.parent
repo = pathlib.Path('/Users/vaanskii/Developer/vynic')
destination = repo / 'docs/proofs/POS_SHARED_PRINT_GO_275688e1_2026-10-06/software-completion-final'
if destination.exists():
    raise SystemExit('Preserve existing packet; this one-time archive cannot overwrite it')
destination.mkdir()
copied = {}
omitted = []

def sha(path):
    with path.open('rb') as stream:
        result = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()

def copy(origin, relative):
    if origin.is_symlink() or not origin.is_file():
        raise SystemExit('Nonregular proof input: ' + str(origin))
    target = destination / relative
    if target.exists():
        raise SystemExit('Duplicate proof path: ' + str(relative))
    target.parent.mkdir(parents=True, exist_ok=True)
    expected = sha(origin)
    shutil.copy2(origin, target)
    if sha(origin) != expected or sha(target) != expected:
        raise SystemExit('Copy changed proof bytes: ' + str(origin))
    copied[str(relative)] = {'origin': str(origin), 'sha256': expected,
                             'bytes': target.stat().st_size}

for directory in ('verification', 'metadata'):
    for origin in sorted((task / directory).rglob('*')):
        if not origin.is_file():
            continue
        relative = origin.relative_to(task)
        # The sealed ZIPs retain Windows executables once. Mac test executables
        # and duplicate independent builds retain their pins/build logs instead.
        if origin.stat().st_size > 8_000_000 and origin.suffix != '.zip':
            omitted.append({'origin': str(origin), 'sha256': sha(origin),
                            'bytes': origin.stat().st_size,
                            'reason': 'Temporary test executable or duplicate artifact; source, build command and actual executable pins retained.'})
            continue
        copy(origin, relative)

for origin in sorted((task / 'artifacts/bundles').rglob('*')):
    if origin.is_file():
        copy(origin, origin.relative_to(task))

for directory, archive_name in (('printer-validation', 'historical/printer-validation'),
                                 ('tools/metadata', 'historical/tool-metadata'),
                                 ('printhost-verification', 'historical/printhost-verification'),
                                 ('printtransport-failed-v1', 'historical/printtransport-failed-v1')):
    for origin in sorted((root / directory).rglob('*')):
        if origin.is_file() and origin.stat().st_size <= 8_000_000:
            copy(origin, pathlib.Path(archive_name) / origin.relative_to(root / directory))

for origin in sorted(root.iterdir()):
    if origin.is_file() and origin.suffix in ('.json', '.jsonl', '.stderr', '.stdout', '.log', '.txt', '.py'):
        # Exclude security/backend work and the obsolete old-source port script.
        if origin.name.startswith(('operational-', 'print', 'shared-print', 'windows-')) and origin.stat().st_size <= 8_000_000:
            copy(origin, pathlib.Path('historical/root-evidence') / origin.name)

for origin in sorted(task.iterdir()):
    if origin.is_file() and origin.suffix in ('.py', '.json', '.jsonl', '.log', '.txt'):
        copy(origin, pathlib.Path('continuation') / origin.name)

report = repo / 'docs/POS_PRINTER_IMPLEMENTATION_REPORT_2026-10-06.md'
if sha(report) != '0a70e7aa396839d7778636060c213c63cfd28ae61d1272d0df2a2ebc4a9f7a38':
    raise SystemExit('Reviewed report changed')
copy(report, pathlib.Path('reviewed-implementation-report.md'))

# All unrelated preimages and all explicitly reviewed port bytes must still match.
reviewed = json.loads((task / 'verification/reviewed-printer-port-manifest.json').read_text())
before = json.loads((root / 'workspace-before-hashes.json').read_text())
for name, expected in reviewed.items():
    if sha(repo / name) != expected:
        raise SystemExit('Ported source changed: ' + name)
for name, expected in before.items():
    if name not in reviewed and sha(repo / name) != expected:
        raise SystemExit('Unrelated original changed: ' + name)

manifest = json.loads((task / 'verification/final-cohort-source.json').read_text())
differences = {}
for name, record in manifest['files'].items():
    for base in (task / 'source', task / 'final-cohort'):
        if sha(base / name) != record['sha256']:
            raise SystemExit('Frozen source changed: ' + name)
    original = repo / name
    value = sha(original) if original.is_file() else None
    if value != record['sha256']:
        differences[name] = {'workspaceSHA256': value, 'qualifiedCandidateSHA256': record['sha256']}
known = json.loads((root / 'printer-validation/workspace-overlay-boundary.json').read_text())['unownedDifferences']
for name, record in known.items():
    original = repo / name
    actual = sha(original) if original.is_file() else None
    if actual != record['workspaceSHA256']:
        raise SystemExit('Known unowned workspace input changed: ' + name)
if differences != {name: {k: v[k] for k in ('workspaceSHA256', 'qualifiedCandidateSHA256')}
                    for name, v in known.items() if name in manifest['files']}:
    raise SystemExit('Unexpected original/candidate differences')

older = []
for entry in json.loads((root / 'printer-validation/earlier-proof-seal-check.json').read_text()):
    folder = repo / 'docs/proofs' / entry['directory']
    seal = folder / 'ARTIFACT_SHA256.json'
    if sha(seal) != entry['sealSHA256']:
        raise SystemExit('Earlier proof seal changed')
    values = json.loads(seal.read_text())
    for name, expected in values.items():
        if sha(folder / name) != expected:
            raise SystemExit('Earlier proof artifact changed: ' + name)
    older.append({**entry, 'artifactsRehashed': len(values), 'unchanged': True})

def git(*args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()

identity = {'head': git('rev-parse', 'HEAD'), 'branch': git('branch', '--show-current'),
            'stash': git('rev-parse', 'refs/stash'), 'stagedFiles': git('diff', '--cached', '--name-only')}
if identity != {'head': '275688e1e5c5dc0e26e62705ab0c7670cf16d99a',
                'branch': 'codex/docker-deployment-foundation',
                'stash': '9df454225caec647f67ad4f70ef6038dbbbe41d6', 'stagedFiles': ''}:
    raise SystemExit('Repository identity/index changed')
check = subprocess.run(['git', 'diff', '--check'], cwd=repo, capture_output=True, text=True)
(destination / 'workspace-diff-check.txt').write_text(check.stdout + check.stderr)
if check.returncode:
    raise SystemExit('Diff check failed; packet intentionally unsealed')
(destination / 'git-status-short.txt').write_text(subprocess.check_output(['git', 'status', '--short'], cwd=repo, text=True))
preservation = {'recordedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'repository': identity, 'reviewedPortPathsVerified': len(reviewed),
                'unrelatedPreimagesVerified': sum(name not in reviewed for name in before),
                'qualifiedSourceAndCopyFilesVerified': len(manifest['files']),
                'workspaceDiffCheckExit': check.returncode,
                'preservedUnownedWorkspaceDifferencesWithinCohort': differences,
                'preservedHistoricalWorkspaceDifferences': known,
                'excludedHistoricalLogInputs': sorted(set(known) - set(manifest['files'])),
                'earlierProofSeals': older, 'committed': False,
                'dirtyWorkspaceRuntimeQualified': False,
                'exactCommittedRuntimeQualified': False}
(destination / 'workspace-final-preservation.json').write_text(json.dumps(preservation, indent=2) + '\n')
(destination / 'copy-provenance.json').write_text(json.dumps({'files': copied, 'omittedDuplicateTemporaryExecutables': omitted}, indent=2) + '\n')
(destination / 'README.md').write_text('''# Printer software continuation proof

Status: **POS-02 NOT_DONE**. Production submission remains HELD_PROVISIONING;
shared physical dispatch remains held. No service registration or physical job
was performed. No commit, push, deployment or roadmap continuation occurred.

The exact isolated source has 1,109 pinned files. Normal and race Go each pass
225 top-level tests / 764 records with nine child-fixture entrypoint skips;
parent tests exercise those children. Flutter passes 623 visible tests plus 51
hidden setup records across 39 suites, with no skips/errors. Analysis of 68
targets, vet, generated-contract compilation, Windows amd64/ARM64 static builds
and the three recorded Go vulnerability scans pass. These checks qualify the
frozen source, not the dirty workspace or a committed runtime.

- `verification/final-integrated-qualification.json`: authoritative outcomes.
- `verification/final-integrated-independent-review.json`: independent review,
  no open P1/P2; final report hash and complete evidence checks.
- `verification/final-cohort-source.json`: exact source manifest.
- `verification/windows-software-go-stage/source1109.zip`: exact source archive.
- `verification/final-flutter-tests-v3-normalized-receipt.json`: authoritative
  visible/hidden counts from the successful actual v2 machine log.
- `historical/printer-validation/acceptance-matrix-v9-software-completion.json`:
  17 bounded software counterparts pass; machine disappearance is not run.
  All 18 full physical acceptance cases remain not run.
- `artifacts/bundles/{amd64,arm64}`: four-file unprovisioned Windows bundles;
  independent byte-for-byte reproductions are recorded in packaging receipts.
- `verification/windows-software-go-stage`: source and ten cross-compiled PE
  executables in two ZIPs, prepared for subsequent authorized Windows checks.
  Source-only Flutter/POS stage packets reside in the parent proof directory.
- `verification/printer-port-receipt.json` and
  `workspace-final-preservation.json`: guarded 156-file port, unrelated
  preimages and earlier proof packets unchanged, branch/stash/index preserved.

New Windows execution is NOT_RUN_BLOCKED_AUTOMATIC_APPROVAL. Automatic approval
review rejected the harmless current-user preflight for VM
9830bac8-34c6-46f7-9062-cd8f62f7a127 because the original task held VM operations;
retained evidence of later clearance was not accepted. No alternate executor
was attempted. The exact denied argv/script and source-only preparation receipts
are retained. Scoped current clearance is required for one identical retry.
Earlier separately pinned Windows/native-helper proofs remain historical and do
not qualify this new daemon/RPC/UI cohort, SCM lifecycle or service principal.

Remaining implementation includes the production issuer/enrollment and durable
current-authority/route bridge, authenticated shared LAN runtime, business/Hive
writer cutover, reconciliation and reader/rollback qualification. Actual printer
models/firmware, downstream fence or independently powered gateway, offline
grant policy and service principal require explicit selection. Physical printer,
driver, account/SCM and Windows restart acceptance remain unperformed.

Failed tests/builds/wrappers and earlier matrix/source versions are preserved as
history. In particular, the first final Flutter wrapper failed while parsing a
batch array; v2 incorrectly counted hidden loader records as visible. Neither
superseded receipt is used as final evidence. The actual successful v2 process
status plus v3 normalized receipt establish the final counts. The first combined
Go summarizer error also remains history.

`ARTIFACTS.json` seals every file in this packet except itself. `copy-provenance`
records original task paths and hashes, so absolute paths in immutable receipts
remain resolvable within this archived packet. Duplicate temporary executable
pins/build commands are retained without duplicating their bytes. The Windows
stage ZIPs and production bundle artifacts retain the actual PE files.
''')
seal = {str(f.relative_to(destination)): sha(f) for f in sorted(destination.rglob('*')) if f.is_file()}
(destination / 'ARTIFACTS.json').write_text(json.dumps(seal, indent=2) + '\n')
for name, expected in seal.items():
    if sha(destination / name) != expected:
        raise SystemExit('Final artifact seal mismatch: ' + name)
print(json.dumps({'destination': str(destination), 'sealedFiles': len(seal),
                  'sealSHA256': sha(destination / 'ARTIFACTS.json'),
                  'bytes': sum((destination / name).stat().st_size for name in seal),
                  'unownedPreimagesVerified': preservation['unrelatedPreimagesVerified'],
                  'earlierProofArtifactsVerified': sum(x['artifactsRehashed'] for x in older)}))
