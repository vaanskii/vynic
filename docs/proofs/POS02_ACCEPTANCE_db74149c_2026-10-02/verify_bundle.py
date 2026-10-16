#!/usr/bin/env python3
"""Read-only sealed source/evidence checks; never launch Flutter/VM/devices."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

PIN = 'db74149c4680d05e16a3a1f53906b269bf76be3d1d71e78796119633d15ff51a'
BASE = 'd194367f8fd0e2f6d9dcfea86f52d09cb605b32779b7904613b00466bd084de8'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def events(data):
    return [json.loads(line) for line in data.decode('utf-8-sig').splitlines()
            if line.startswith('{')]


def passing(saved, expected):
    require([e['success'] for e in saved if e.get('type') == 'done'] == [True],
            'Test run did not complete successfully')
    require(not any(e.get('type') == 'error' for e in saved), 'Test errors present')
    passed = [e for e in saved if e.get('type') == 'testDone' and not e.get('hidden')
              and not e.get('skipped') and e['result'] == 'success']
    require(len(passed) == len({e['testID'] for e in passed}) == expected,
            'Distinct passing check count mismatch')
    return passed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--check-owned-checkout', action='store_true')
    args = parser.parse_args()
    root = args.root
    checksums = json.loads((root / 'CHECKSUMS.json').read_text())
    require(set(checksums) == {p.name for p in root.iterdir() if p.is_file()
                             and p.name != 'CHECKSUMS.json'}, 'Proof file set changed')
    for name, digest in checksums.items():
        require(Path(name).name == name and sha((root / name).read_bytes()) == digest,
                f'Proof checksum mismatch: {name}')
    require(sha((root / 'source-sha256.json').read_bytes()) == PIN, 'Candidate manifest changed')
    require(sha((root / 'base-source-sha256.json').read_bytes()) == BASE, 'Admin base manifest changed')
    sources = json.loads((root / 'source-sha256.json').read_text())
    base = json.loads((root / 'base-source-sha256.json').read_text())
    profile = json.loads((root / 'profile.json').read_text())
    proof = json.loads((root / 'proof.json').read_text())
    require(len(sources) == 883 and len(base) == 876 and
            all(sources.get(p) == h for p, h in base.items()), 'Base source or count changed')
    require(profile['sourceManifestSha256'] == proof['sourceManifestSha256'] == PIN
            and not proof['milestoneDone'] and proof['physicalAllowance'] == 0,
            'Candidate identity/status/budget mismatch')
    extras = {
        'POS02_SOURCE_SHA256.json': 'source-sha256.json', 'POS02_PROFILE.json': 'profile.json',
        'Run-Pos02-Acceptance.ps1': 'Run-Pos02-Acceptance.ps1',
        'Verify-Source.ps1': 'Verify-Source.ps1', 'acceptance-suites.json': 'acceptance-suites.json',
        'window-zero.json': 'window-zero.json', 'README.md': 'README.md',
        'INSTALLER_GUIDE.md': 'INSTALLER_GUIDE.md',
    }
    require(sha((root / 'source.zip').read_bytes()) == proof['sourceZipSha256'], 'Source ZIP changed')
    with zipfile.ZipFile(root / 'source.zip') as archive:
        require(archive.testzip() is None and len(archive.namelist()) == len(set(archive.namelist()))
                and set(archive.namelist()) == set(sources) | set(extras), 'Source ZIP set/CRC mismatch')
        for path, digest in sources.items():
            require(sha(archive.read(path)) == digest, f'Source mismatch: {path}')
        for name, local in extras.items():
            require(archive.read(name) == (root / local).read_bytes(), f'Handoff mismatch: {name}')
    suites = json.loads((root / 'acceptance-suites.json').read_text())
    require(len(suites) == len(set(suites)) == 74, 'Acceptance suite set changed')
    for script in ['Run-Pos02-Acceptance.ps1', 'Verify-Source.ps1']:
        require(PIN in (root / script).read_text(), 'Launcher source binding missing')
    require(sha((root / 'acceptance-suites.json').read_bytes()) in
            (root / 'Run-Pos02-Acceptance.ps1').read_text(), 'Launcher suite binding missing')
    require(json.loads((root / 'window-zero.json').read_text())['window']['allowance'] == 0,
            'Template grants paper allowance')
    with zipfile.ZipFile(root / 'logs.zip') as archive:
        logs = json.loads((root / 'log-sha256.json').read_text())
        require(set(logs) == set(archive.namelist()) and archive.testzip() is None, 'Log ZIP changed')
        for name, digest in logs.items():
            require(sha(archive.read(name)) == digest, f'Log hash mismatch: {name}')
        saved = events(archive.read('runner-acceptance-final.jsonl'))
        checks = passing(saved, 895)
        meta = {e['test']['id']: e['test'] for e in saved if e.get('type') == 'testStart'}
        require(len({meta[e['testID']]['suiteID'] for e in checks}) == 73, 'Passing suite count changed')
        require(sum(e.get('type') == 'suite' for e in saved) == 74, 'Discovered suite count changed')
        passing(events(archive.read('native-smoke.jsonl')), 1)
        require('No issues found!' in archive.read('runner-analysis-final.txt').decode(), 'Analysis failed')
        require('Built build/macos/Build/Products/Debug/Vynic Manager.app' in
                archive.read('runner-build-final2.txt').decode(), 'Development build failed')
        require([e['success'] for e in events(archive.read('runner-all.jsonl'))
                 if e.get('type') == 'done'] == [False], 'Exploratory failed run was hidden')
    native = json.loads((root / 'native-ledger.json').read_text())
    require(native['status'] == 'PASS' and native['syntheticOnly'] and not native['deviceContact'],
            'Native ledger proof is not isolated')
    require([c['phase'] for c in native['checkpoints']] == ['reserved', 'admitted', 'connect', 'write'],
            'Native checkpoint matrix changed')
    for path, digest in native['sourceBindings'].items():
        require(sources['apps/operations/' + path] == digest, 'Native ledger source changed')
    for index, record in enumerate(native['checkpoints']):
        require(all(record[k] for k in ['lockRejected', 'ownedChildKilled', 'consumedOnRestart',
                                       'journalUnchanged']) and len(record['events']) == index + 1,
                'Native ledger restart/lock proof incomplete')
        for seq, event in enumerate(record['events']):
            body = {k: v for k, v in event.items() if k != 'sha256'}
            require(event['seq'] == seq and event['sha256'] == sha(json.dumps(
                body, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()),
                'Native event hash changed')
            if seq:
                require(event['previous'] == record['events'][seq - 1]['sha256'], 'Native chain changed')
    old = json.loads((root / 'inherited-product-recovery.json').read_text())
    matrix = {'send': 15, 'uncertain': 14, 'reprint': 15, 'confirm': 4, 'remotecreate': 37, 'localconfirm': 17}
    expected = {(scenario, n) for scenario, count in matrix.items() for n in range(1, count + 1)}
    actual = [(v['scenario'], v['checkpoint']) for v in old['checkpoints']]
    require(old['status'] == 'PASS' and old['checkpointCount'] == old['availableCheckpointCount'] == 102
            and len(actual) == len(set(actual)) == 102 and set(actual) == expected,
            'Inherited product checkpoint matrix incomplete')
    for path, digest in old['sourceSha256'].items():
        require(sources['apps/operations/' + path] == digest, 'Inherited runtime changed')
    with zipfile.ZipFile(root / 'inherited-product-logs.zip') as archive:
        for c in old['checkpoints']:
            require(c['signal'] == 'SIGKILL' and c['writerExit'] != 0 and c['restart']['status'] == 'PASS',
                    'Inherited kill/restart did not pass')
            prefix = f"admin-native-proof.{c['scenario']}-{c['checkpoint']:03d}"
            for stage in ['writer', 'reader']:
                require(sha(archive.read(f'{prefix}-{stage}.log')) == c[f'{stage}LogSha256'],
                        'Inherited native log changed')
    smoke = json.loads((root / 'native-smoke-result.json').read_text())
    require(smoke['simulated'] and smoke['window']['allowance'] == 0 and
            smoke['candidateSha256'] == PIN and not smoke['paperConfirmed'] and not smoke['milestoneDone'],
            'Smoke could be mistaken for physical proof')
    review = json.loads((root / 'review.json').read_text())
    require(not review['remainingP1P2'], 'Independent review is not resolved')
    for p, h in review['sourceBindings'].items():
        require(sources[p] == h, 'Reviewed source changed')
    for p, h in review['handoffBindings'].items():
        require(sha((root / p).read_bytes()) == h, 'Reviewed launcher changed')
    checked = 0
    if args.check_owned_checkout:
        checkout = Path(__file__).resolve().parents[3]
        owned = json.loads((root / 'owned-paths.json').read_text()) + profile['newPaths']
        for path in owned:
            require(sha((checkout / path).read_bytes()) == sources[path], f'Owned checkout changed: {path}')
        checked = len(owned)
    print(json.dumps({'status': 'PASS', 'sourceFiles': 883, 'ownedPathsChecked': checked,
        'passingChecks': 895, 'newBudgetKillCheckpoints': 4, 'inheritedProductCheckpoints': 102,
        'physicalAllowance': 0, 'Windows': 'PENDING_NOT_RUN', 'physicalAcceptance': 'PENDING',
        'milestoneDone': False}, indent=2))


if __name__ == '__main__':
    main()
