"""Port the two reviewed and Mac/Windows-qualified native-path fixture fixes."""
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile

task = pathlib.Path(__file__).resolve().parent
repo = pathlib.Path('/Users/vaanskii/Developer/vynic')
old = json.loads((task / 'verification/reviewed-printer-port-manifest.json').read_text())
new = json.loads((task / 'verification/final-cohort-v2-source.json').read_text())['files']
before = json.loads((task.parent / 'workspace-before-hashes.json').read_text())
names = ['apps/operations/test/unit/printer_agent_runtime_profile_test.dart',
         'apps/operations/test/widget/printer_agent_status_card_test.dart']
output = task / 'verification/windows-software-v2/fixture-port-v2-receipt.json'
if output.exists():
    raise SystemExit('Preserve earlier port receipt')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()

expected = ('275688e1e5c5dc0e26e62705ab0c7670cf16d99a',
            'codex/docker-deployment-foundation',
            '9df454225caec647f67ad4f70ef6038dbbbe41d6', '')
def identity():
    return (git('rev-parse', 'HEAD'), git('branch', '--show-current'),
            git('rev-parse', 'refs/stash'), git('diff', '--cached', '--name-only'))

if identity() != expected:
    raise SystemExit('Repository identity/index changed')
for name, value in old.items():
    if sha(repo / name) != value:
        raise SystemExit('Reviewed original changed: ' + name)
for name, value in before.items():
    if name not in old and sha(repo / name) != value:
        raise SystemExit('Unrelated original changed: ' + name)
records = []
for name in names:
    origin, target = task / 'source-v2' / name, repo / name
    if origin.is_symlink() or target.is_symlink() or sha(origin) != new[name]['sha256']:
        raise SystemExit('Reviewed fixture source changed')
    raw = origin.read_bytes()
    fd, temporary = tempfile.mkstemp(prefix='.vynic-fixture-v2-', dir=target.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, origin.stat().st_mode & 0o777)
        if sha(target) != old[name]:
            raise SystemExit('Original fixture changed at replacement')
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    if sha(target) != new[name]['sha256']:
        raise SystemExit('Ported fixture mismatch')
    records.append({'path': name, 'preimageSHA256': old[name],
                    'currentSHA256': new[name]['sha256']})
for name, value in old.items():
    if name not in names and sha(repo / name) != value:
        raise SystemExit('Other reviewed original changed')
for name, value in before.items():
    if name not in old and sha(repo / name) != value:
        raise SystemExit('Unrelated original changed after port')
if identity() != expected:
    raise SystemExit('Repository identity/index changed after port')
output.write_text(json.dumps({'recordedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                             'paths': records, 'unrelatedPreimagesUnchanged': True,
                             'other154ReviewedPathsUnchanged': True,
                             'HEADBranchStashIndexUnchanged': True,
                             'committed': False}, indent=2) + '\n')
print(json.dumps({'portedFixtures': len(records), 'receipt': str(output)}))
