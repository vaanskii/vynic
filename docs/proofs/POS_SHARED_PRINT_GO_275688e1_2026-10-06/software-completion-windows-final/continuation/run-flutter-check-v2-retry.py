import collections
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import sys

task = pathlib.Path(__file__).resolve().parent
proof = task / 'verification/software-v2-mac-retry'
proof.mkdir(exist_ok=True)
base = task / 'final-cohort-v2'
manifest_path = task / 'verification/final-cohort-v2-source.json'
manifest = json.loads(manifest_path.read_text())
tools = task.parent / 'tools'
sdk = tools / 'flutter-sdk'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify_source():
    for name, entry in manifest['files'].items():
        for root in (base, task / 'source-v2'):
            if sha(root / name) != entry['sha256']:
                raise SystemExit('Frozen source changed: ' + name)

if len(sys.argv) != 2 or sys.argv[1] not in ('tests', 'analysis'):
    raise SystemExit('Select tests or analysis')
name = sys.argv[1]
suffix = '-v2' if name == 'tests' else ''
out = proof / ('final-flutter-' + name + suffix + '.jsonl')
err = proof / ('final-flutter-' + name + suffix + '.stderr')
receipt = proof / ('final-flutter-' + name + suffix + '-receipt.json')
if any(path.exists() for path in (out, err, receipt)):
    raise SystemExit('Prior evidence must be retained')
verify_source()
environment = os.environ.copy()
environment.update(CI='true', DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true')
fixtures = {}
if name == 'tests':
    for variable, filename in (
            ('VYNIC_OPERATIONAL_PROOF_GO_FIXTURE', 'final-operational-proof-server.test'),
            ('VYNIC_PRINTER_AGENT_GO_FIXTURE', 'final-printer-agent-server.test')):
        path = task / 'verification' / filename
        if not path.is_file():
            raise SystemExit('Required exact-cohort real Go fixture missing: ' + str(path))
        environment[variable] = str(path)
        fixtures[variable] = {'path': str(path), 'sha256': sha(path), 'bytes': path.stat().st_size}
    command = [str(sdk / 'bin/flutter'), '--suppress-analytics', 'test', '--no-pub', '--machine', *manifest['testSelection']]
else:
    command = [str(sdk / 'bin/cache/dart-sdk/bin/dart.native'), '--suppress-analytics', 'analyze', *manifest['analysisSelection']]
start = datetime.datetime.now(datetime.timezone.utc).isoformat()
with out.open('w') as output, err.open('w') as errors:
    result = subprocess.run(command, cwd=base / 'apps/operations', env=environment, stdout=output, stderr=errors)
verify_source()
for fixture in fixtures.values():
    if sha(pathlib.Path(fixture['path'])) != fixture['sha256']:
        raise SystemExit('Fixture changed across test')
facts = {'exitCode': result.returncode, 'command': command, 'workingDirectory': str(base / 'apps/operations'),
         'startedAtUTC': start, 'finishedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'sourceManifestSHA256': sha(manifest_path), 'sourceBeforeAfterMatch': True,
         'fixtures': fixtures, 'physicalPrintJobs': 0, 'outputSHA256': sha(out), 'stderrSHA256': sha(err)}
(proof / ('final-flutter-' + name + suffix + '-raw-status.json')).write_text(json.dumps(facts, indent=2) + '\n')
if name == 'tests':
    def flattened(value):
        if isinstance(value, list):
            for child in value:
                yield from flattened(child)
        elif isinstance(value, dict):
            yield value
        else:
            raise ValueError('Unexpected Flutter machine event type')
    events = [event for line in out.read_text().splitlines() if line.strip()
              for event in flattened(json.loads(line))]
    starts = {event['test']['id']: event['test'] for event in events if event.get('type') == 'testStart'}
    outcomes = collections.Counter()
    for event in events:
        if event.get('type') == 'testDone':
            key = 'skipped' if event.get('skipped') else event['result']
            if not event.get('hidden', False):
                outcomes[key] += 1
    facts['visibleTestOutcomes'] = dict(outcomes)
    facts['hiddenTests'] = sum(event.get('type') == 'testDone' and event.get('hidden', False) for event in events)
    facts['suiteCount'] = sum(event.get('type') == 'suite' for event in events)
    facts['machineErrors'] = sum(event.get('type') == 'error' for event in events)
    facts['doneSuccess'] = next((event['success'] for event in reversed(events) if event.get('type') == 'done'), None)
    assert result.returncode == 0 and facts['doneSuccess'] is True and facts['machineErrors'] == 0
    assert outcomes.get('skipped', 0) == 0 and outcomes.get('error', 0) == 0 and outcomes.get('failure', 0) == 0
receipt.write_text(json.dumps(facts, indent=2) + '\n')
print(json.dumps({'check': name, 'exitCode': result.returncode, 'receipt': str(receipt), 'outcomes': facts.get('visibleTestOutcomes')}))
raise SystemExit(result.returncode)
