"""Compile only cached test fixtures from the exact frozen software cohort."""
import datetime
import hashlib
import json
import os
import pathlib
import subprocess

TASK = pathlib.Path(__file__).resolve().parent
MANIFEST = TASK / 'verification/final-cohort-source.json'
EXPECTED = '193e4800e5d0733a30bc6c8d4ac993590219363941e69a787bba5ac3681c8f68'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


assert digest(MANIFEST) == EXPECTED
snapshot = json.loads(MANIFEST.read_text())
source = pathlib.Path(snapshot['snapshot'])
assert source == TASK / 'final-cohort'


def verify():
    for name, item in snapshot['files'].items():
        path = source / name
        assert not path.is_symlink() and digest(path) == item['sha256'], name


verify()
out = TASK / 'tools/final-cohort-windows-fixtures'
assert not out.exists(), 'Preserve existing fixture proof'
out.mkdir()
env = os.environ.copy()
env.update(GOPROXY='off', GOTOOLCHAIN='local', GOOS='windows', GOARCH='amd64', CGO_ENABLED='0')
results = {}
for package, name in [('server', 'operational-proof-server-windows.test.exe'),
                      ('printeragent', 'printer-agent-server-windows.test.exe')]:
    binary = out / name
    command = ['go', 'test', '-mod=readonly', '-c', '-o', str(binary), './internal/' + package]
    before = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (out / (package + '.build.stdout')).open('w') as stdout, (out / (package + '.build.stderr')).open('w') as stderr:
        result = subprocess.run(command, cwd=source / 'apps/edge', env=env, stdout=stdout, stderr=stderr)
    assert result.returncode == 0, package
    raw = binary.read_bytes()
    offset = int.from_bytes(raw[60:64], 'little')
    assert raw[:2] == b'MZ' and raw[offset:offset + 6] == b'PE\x00\x00\x64\x86'
    info = subprocess.run(['go', 'version', '-m', str(binary)], env=os.environ,
                          capture_output=True, text=True, check=True)
    (out / (package + '.build-info.txt')).write_text(info.stdout)
    results[name] = {'package': 'apps/edge/internal/' + package, 'path': str(binary),
                     'sha256': digest(binary), 'bytes': binary.stat().st_size,
                     'startedAtUtc': before,
                     'finishedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                     'command': command, 'workingDirectory': str(source / 'apps/edge'), 'exitCode': 0,
                     'buildInfoSHA256': digest(out / (package + '.build-info.txt')),
                     'stdoutSHA256': digest(out / (package + '.build.stdout')),
                     'stderrSHA256': digest(out / (package + '.build.stderr'))}
verify()
receipt = {'schema': 1, 'sourceManifestSHA256': EXPECTED, 'sourceFiles': snapshot['fileCount'],
           'sourceBeforeAfterVerified': True, 'environment': {k: env[k] for k in
               ['GOROOT', 'GOTOOLCHAIN', 'GOOS', 'GOARCH', 'CGO_ENABLED', 'GOCACHE', 'GOMODCACHE', 'GOPROXY']},
           'artifacts': results, 'physicalPrints': 0, 'VMExecuted': False, 'generatedSourceEdits': False}
target = TASK / 'verification/windows-final-fixtures-compile.json'
assert not target.exists()
target.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'receipt': str(target), 'sha256': digest(target), 'artifacts': results}, indent=2))
