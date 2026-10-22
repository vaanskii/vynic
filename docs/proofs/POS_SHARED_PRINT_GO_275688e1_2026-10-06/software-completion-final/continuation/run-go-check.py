import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import sys

task = pathlib.Path(__file__).resolve().parent
metadata = task / 'verification'
base = task / 'final-cohort'
checks = {
    'edge-tests': ('apps/edge', ['go', 'test', '-mod=readonly', '-count=1', '-json', './...'], {'GOPROXY': 'off'}),
    'edge-race': ('apps/edge', ['go', 'test', '-mod=readonly', '-race', '-count=1', '-json', './...'], {'GOPROXY': 'off'}),
    'edge-vet': ('apps/edge', ['go', 'vet', '-mod=readonly', './...'], {'GOPROXY': 'off'}),
    'windows-amd64-build': ('apps/edge', ['go', 'build', '-mod=readonly', './...'], {'GOOS': 'windows', 'GOARCH': 'amd64', 'CGO_ENABLED': '0', 'GOPROXY': 'off'}),
    'windows-arm64-build': ('apps/edge', ['go', 'build', '-mod=readonly', './...'], {'GOOS': 'windows', 'GOARCH': 'arm64', 'CGO_ENABLED': '0', 'GOPROXY': 'off'}),
    'contracts-test': ('packages/contracts/generated/go', ['go', 'test', '-mod=readonly', '-count=1', '-json', './...'], {'GOPROXY': 'off'}),
    'edge-govuln': ('apps/edge', ['govulncheck', '-json', '-scan=symbol', './...'], {}),
    'windows-govuln': ('apps/edge', ['govulncheck', '-json', '-scan=symbol', './...'], {'GOOS': 'windows', 'GOARCH': 'amd64', 'CGO_ENABLED': '0'}),
    'contracts-govuln': ('packages/contracts/generated/go/vynic/edge/v1', ['govulncheck', '-json', '-scan=module'], {}),
}
if len(sys.argv) != 2 or sys.argv[1] not in checks:
    raise SystemExit('Select one declared check')
name = sys.argv[1]
manifest = metadata / 'final-cohort-source.json'
if not manifest.is_file():
    raise SystemExit('Frozen final source required')
part, command, overrides = checks[name]
output = metadata / ('final-' + name + '.jsonl')
errors = metadata / ('final-' + name + '.stderr')
status_file = metadata / ('final-' + name + '-status.json')
if any(p.exists() for p in (output, errors, status_file)):
    raise SystemExit('Existing check evidence must be preserved')
environment = os.environ.copy()
environment.update(overrides)
executable = None
if name in ('edge-tests', 'edge-race'):
    executable = metadata / ('final-printer-agent-race' if name == 'edge-race' else 'final-printer-agent')
    if not executable.is_file():
        raise SystemExit('Actual same-cohort foreground executable is required')
    executable_sha = hashlib.sha256(executable.read_bytes()).hexdigest()
    environment['VYNIC_PRINTER_AGENT_BINARY'] = str(executable)
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
with output.open('w') as out, errors.open('w') as err:
    result = subprocess.run(command, cwd=base / part, env=environment, stdout=out, stderr=err)
status = {'exitCode': result.returncode, 'command': command, 'environmentOverrides': overrides,
          'workingDirectory': str(base / part), 'startedAtUTC': started,
          'finishedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'sourceManifestSHA256': hashlib.sha256(manifest.read_bytes()).hexdigest(),
          'output': str(output), 'stderr': str(errors), 'physicalPrints': 0}
if executable is not None:
    status['actualForegroundExecutable'] = {'path': str(executable), 'sha256': executable_sha,
        'sourceManifestSHA256': status['sourceManifestSHA256'],
        'beforeAfterUnchanged': hashlib.sha256(executable.read_bytes()).hexdigest() == executable_sha}
status_file.write_text(json.dumps(status, indent=2) + '\n')
print(json.dumps({'check': name, 'exitCode': result.returncode, 'output': str(output)}))
raise SystemExit(result.returncode)
