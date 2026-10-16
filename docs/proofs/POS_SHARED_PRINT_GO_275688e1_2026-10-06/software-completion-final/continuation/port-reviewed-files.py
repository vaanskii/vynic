"""One guarded printer-only port from exact reviewed candidate bytes."""
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile

task = pathlib.Path(__file__).resolve().parent
repo = pathlib.Path('/Users/vaanskii/Developer/vynic')
source = task / 'source'
output = task / 'verification/printer-port-receipt.json'
if output.exists():
    raise SystemExit('Earlier port receipt must be preserved; do not repeat')
if len(sys.argv) != 2:
    raise SystemExit('Explicit reviewed path/digest manifest required')
reviewed = json.loads(pathlib.Path(sys.argv[1]).read_text())
if not isinstance(reviewed, dict) or not reviewed:
    raise SystemExit('Explicit reviewed path/digest object required')

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()

head, branch, stash = git('rev-parse', 'HEAD'), git('branch', '--show-current'), git('rev-parse', 'refs/stash')
if (head != '275688e1e5c5dc0e26e62705ab0c7670cf16d99a'
        or branch != 'codex/docker-deployment-foundation'
        or stash != '9df454225caec647f67ad4f70ef6038dbbbe41d6'):
    raise SystemExit('HEAD, branch or user stash changed; re-review preimages')
if git('diff', '--cached', '--name-only'):
    raise SystemExit('Index is no longer empty')
before = json.loads((task.parent / 'workspace-before-hashes.json').read_text())
for name, expected in before.items():
    target = repo / name
    if not target.is_file() or target.is_symlink() or digest(target.read_bytes()) != expected:
        raise SystemExit('User-owned original preimage changed: ' + name)
records, values = [], {}
for name, reviewed_sha in sorted(reviewed.items()):
    relative = pathlib.PurePosixPath(name)
    if (relative.is_absolute() or '..' in relative.parts
            or name.startswith(('.git/', '.env', 'apps/backend/', 'apps/platform-web/'))
            or not isinstance(reviewed_sha, str) or len(reviewed_sha) != 64):
        raise SystemExit('Out-of-scope/invalid reviewed input: ' + name)
    origin, target = source / name, repo / name
    if not origin.is_file() or origin.is_symlink() or target.is_symlink():
        raise SystemExit('Nonregular candidate/original input: ' + name)
    data = origin.read_bytes()
    if digest(data) != reviewed_sha:
        raise SystemExit('Reviewed candidate digest changed: ' + name)
    expected = before.get(name)
    if expected is None:
        blob = subprocess.run(['git', 'show', f'{head}:{name}'], cwd=repo,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if blob.returncode == 0:
            expected = digest(blob.stdout)
    actual = digest(target.read_bytes()) if target.is_file() else None
    if actual != expected:
        raise SystemExit('Original preimage changed: ' + name)
    values[name] = data
    records.append({'path': name, 'preimageSHA256': expected,
                    'candidateSHA256': reviewed_sha, 'bytes': len(data),
                    'changed': actual != reviewed_sha})
for entry in records:
    name = entry['path']
    if (source / name).read_bytes() != values[name]:
        raise SystemExit('Candidate changed before port: ' + name)
    if not entry['changed']:
        continue
    target = repo / name
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.vynic-printer-port-', dir=target.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(values[name])
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, (source / name).stat().st_mode & 0o777)
        actual = digest(target.read_bytes()) if target.is_file() else None
        if actual != entry['preimageSHA256']:
            raise SystemExit('Original changed at replacement: ' + name)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
for entry in records:
    if digest((repo / entry['path']).read_bytes()) != entry['candidateSHA256']:
        raise SystemExit('Port digest mismatch: ' + entry['path'])
unowned = {name: sha for name, sha in before.items() if name not in reviewed}
for name, sha in unowned.items():
    if digest((repo / name).read_bytes()) != sha:
        raise SystemExit('Unowned WIP preservation failed: ' + name)
if git('rev-parse', 'HEAD') != head or git('branch', '--show-current') != branch or git('rev-parse', 'refs/stash') != stash or git('diff', '--cached', '--name-only'):
    raise SystemExit('Repository identity/index changed across port')
receipt = {'recordedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
           'baseCommit': head, 'branch': branch, 'stash': stash,
           'reviewedManifestSHA256': digest(pathlib.Path(sys.argv[1]).read_bytes()),
           'paths': records, 'unownedWIPCount': len(unowned),
           'unownedWIPUnchanged': True, 'portVerified': True,
           'committed': False, 'pushed': False,
           'originalWorkspaceRuntimeQualified': False,
           'exactCommittedRuntimeQualified': False}
output.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'changed': sum(x['changed'] for x in records), 'reviewed': len(records),
                  'unownedWIPPreserved': len(unowned), 'receipt': str(output)}))
