"""Port only the independently approved final printer report/state bytes."""
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile

task = pathlib.Path(__file__).resolve().parent
repo = pathlib.Path('/Users/vaanskii/Developer/vynic')
source = task / 'source-v2'
old = json.loads((task / 'verification/reviewed-printer-port-manifest.json').read_text())
frozen = json.loads((task / 'verification/final-cohort-v2-source.json').read_text())['files']
fixtures = ['apps/operations/test/unit/printer_agent_runtime_profile_test.dart',
            'apps/operations/test/widget/printer_agent_status_card_test.dart']
expected = dict(old)
for name in fixtures:
    expected[name] = frozen[name]['sha256']
before = json.loads((task.parent / 'workspace-before-hashes.json').read_text())
review = task / 'verification/windows-software-v2/final-report-state-matrix-independent-review.json'
if hashlib.sha256(review.read_bytes()).hexdigest() != 'f8b22e1b5c71339808a1df305b9c07f826fdd389eccf7bdc508e69883ea228e6':
    raise SystemExit('Final documentation review changed')
approved = {str(pathlib.Path(path).resolve().relative_to(source)): sha
            for path, sha in json.loads(review.read_text())['approvedDocumentation'].items()}
if set(approved) != {'docs/POS_PRINTER_IMPLEMENTATION_REPORT_2026-10-06.md',
                     'docs/agent-state/VYNIC_PROJECT_STATE.md'}:
    raise SystemExit('Unexpected documentation scope')
output = task / 'verification/windows-software-v2/documentation-port-v2-receipt.json'
manifest_output = task / 'verification/windows-software-v2/reviewed-printer-port-v2-manifest.json'
if output.exists() or manifest_output.exists():
    raise SystemExit('Preserve earlier documentation port')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()

def identity():
    return (git('rev-parse', 'HEAD'), git('branch', '--show-current'),
            git('rev-parse', 'refs/stash'), git('diff', '--cached', '--name-only'))

identity_expected = ('275688e1e5c5dc0e26e62705ab0c7670cf16d99a',
                     'codex/docker-deployment-foundation',
                     '9df454225caec647f67ad4f70ef6038dbbbe41d6', '')
if identity() != identity_expected:
    raise SystemExit('Repository identity/index changed')
for name, value in expected.items():
    if sha(repo / name) != value:
        raise SystemExit('Reviewed workspace preimage changed: ' + name)
for name, value in before.items():
    if name not in expected and sha(repo / name) != value:
        raise SystemExit('Unrelated workspace input changed: ' + name)
records = []
for name, value in sorted(approved.items()):
    origin, target = source / name, repo / name
    if origin.is_symlink() or target.is_symlink() or sha(origin) != value:
        raise SystemExit('Approved document changed: ' + name)
    raw = origin.read_bytes()
    fd, temporary = tempfile.mkstemp(prefix='.vynic-printer-doc-v2-', dir=target.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, origin.stat().st_mode & 0o777)
        if sha(target) != expected[name]:
            raise SystemExit('Document preimage changed at replacement')
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    records.append({'path': name, 'preimageSHA256': expected[name], 'currentSHA256': value})
    expected[name] = value
for name, value in expected.items():
    if sha(repo / name) != value or sha(source / name) != value:
        raise SystemExit('Final reviewed candidate/workspace mismatch: ' + name)
for name, value in before.items():
    if name not in expected and sha(repo / name) != value:
        raise SystemExit('Unrelated workspace input changed after port')
if identity() != identity_expected:
    raise SystemExit('Repository identity/index changed after port')
manifest_output.write_text(json.dumps(expected, indent=2) + '\n')
output.write_text(json.dumps({'recordedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                             'paths': records, 'finalReviewedPaths': len(expected),
                             'reviewSHA256': sha(review), 'finalManifestSHA256': sha(manifest_output),
                             'unrelatedPreimagesUnchanged': True, 'HEADBranchStashIndexUnchanged': True,
                             'committed': False, 'exactCommittedRuntimeQualified': False}, indent=2) + '\n')
print(json.dumps({'portedDocs': len(records), 'finalReviewedPaths': len(expected), 'receipt': str(output)}))
