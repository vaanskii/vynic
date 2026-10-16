#!/usr/bin/env python3
"""Kill only owned synthetic Dart ledger children; no VM, Hive or network."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dart', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    app = Path(__file__).resolve().parent.parent
    base = 'd194367f8fd0e2f6d9dcfea86f52d09cb605b32779b7904613b00466bd084de8'
    records = []
    files = [app / 'tool/pos02_acceptance_ledger.dart', app / 'tool/pos02_acceptance_ledger_probe.dart', Path(__file__).resolve()]
    bindings = {str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    command = [args.dart, '--disable-dart-dev', f'--packages={app}/.dart_tool/package_config.json', str(app / 'tool/pos02_acceptance_ledger_probe.dart')]
    with tempfile.TemporaryDirectory(prefix='vynic_pos02_ledger_kill_') as owned:
        temp = Path(owned)
        for phase in ['reserved', 'admitted', 'connect', 'write']:
            now = dt.datetime.now(dt.timezone.utc)
            identity = f'pos02-kill-{phase}'
            spec = {
                'protocol': 1, 'baseCandidate': base, 'candidateSha256': 'a' * 64,
                'windowId': identity, 'approval': 'SYNTHETIC process proof; no printer',
                'startsAt': (now - dt.timedelta(seconds=5)).isoformat().replace('+00:00', 'Z'),
                'expiresAt': (now + dt.timedelta(minutes=2)).isoformat().replace('+00:00', 'Z'),
                'allowance': 1, 'host': '10.10.10.5', 'port': 9100, 'target': 'kitchen',
                'model': 'SYNTHETIC', 'firmware': 'SYNTHETIC', 'paperMm': 80,
                'action': 'original', 'actionId': identity, 'jobId': identity,
            }
            config = temp / f'{phase}.json'
            config.write_text(json.dumps(spec))
            root, ready = temp / f'owned-{phase}', temp / f'{phase}-ready.json'
            child = subprocess.Popen(command + [str(root), str(config), phase, str(ready)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 15
                while not ready.exists() and child.poll() is None and time.monotonic() < deadline:
                    time.sleep(.02)
                if not ready.exists():
                    raise RuntimeError(f'Child did not reach {phase}: {child.poll()}')
                signal = json.loads(ready.read_text())
                if signal['pid'] != child.pid:
                    raise RuntimeError('Wrong child identity')
                locked = subprocess.run(command + [str(root), str(config), 'lock-check'], capture_output=True, text=True, timeout=15)
                if locked.returncode != 3 or json.loads(locked.stdout) != {'status': 'LOCK_REJECTED'}:
                    raise RuntimeError(f'Lock refusal was not proved: {locked.returncode} {locked.stderr}')
                child.kill()
                child.wait(timeout=10)
                journal = root / 'windows' / identity / 'journal.jsonl'
                before = hashlib.sha256(journal.read_bytes()).hexdigest()
                recovery = subprocess.run(command + [str(root), str(config), 'inspect'], capture_output=True, text=True, timeout=15)
                if recovery.returncode != 0:
                    raise RuntimeError(recovery.stderr)
                result = json.loads(recovery.stdout)
                if not result['consumed'] or result['events'] != signal['events'] or hashlib.sha256(journal.read_bytes()).hexdigest() != before:
                    raise RuntimeError('Restart lost or refunded a durable reservation')
                records.append({'phase': phase, 'lockRejected': True, 'ownedChildKilled': True,
                                'consumedOnRestart': True, 'journalUnchanged': True,
                                'journalSha256': before, 'events': result['events']})
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=10)
    if bindings != {str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}:
        raise RuntimeError('Source changed while the proof ran')
    Path(args.output).write_text(json.dumps({'status': 'PASS', 'syntheticOnly': True,
        'deviceContact': False, 'sourceBindings': bindings, 'checkpoints': records}, indent=2) + '\n')
    print(f'PASS: {len(records)} native kills/restarts and cross-process lock refusals; no device contact')


if __name__ == '__main__':
    main()
