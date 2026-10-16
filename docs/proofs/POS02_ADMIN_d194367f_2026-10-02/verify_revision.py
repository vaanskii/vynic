#!/usr/bin/env python3
"""Verify archived source/evidence; optional task-path check. No runtime/device actions."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def events(data):
    return [json.loads(line) for line in data.decode('utf-8-sig').splitlines() if line.startswith('{')]


def passing(events_, expected):
    checks = [v for v in events_ if v.get('type') == 'testDone' and not v.get('hidden')]
    require(len(checks) == expected, 'Saved test count mismatch')
    require(all(v['result'] == 'success' and not v['skipped'] for v in checks), 'Saved failed/skipped test')
    require(not any(v.get('type') == 'error' for v in events_), 'Saved test error')
    require(any(v.get('type') == 'done' and v.get('success') is True for v in events_), 'Missing successful completion')
    return len(checks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-owned-checkout', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    repo = root.parents[2]
    checks = json.loads((root / 'CHECKSUMS.json').read_text())
    for name, digest in checks['filesSha256'].items():
        require(sha((root / name).read_bytes()) == digest, f'Artifact mismatch: {name}')
    require(sha((repo / 'docs/POS02_ADMIN_REVISION.md').read_bytes()) == checks['guideSha256'], 'Guide mismatch')
    proof = json.loads((root / 'proof.json').read_text())
    require(proof['milestoneDone'] is False and proof['WindowsCurrentRevision'] == 'PENDING_NOT_RUN', 'Pending-gate status mismatch')
    sources = json.loads((root / 'source-sha256.json').read_text())
    require(len(sources) == 876, 'Source count mismatch')
    require(sha((root / 'source-sha256.json').read_bytes()) == proof['sourceManifestSha256'], 'Source manifest mismatch')
    require(sha((root / 'source.zip').read_bytes()) == proof['sourceZipSha256'], 'Source ZIP mismatch')
    with zipfile.ZipFile(root / 'source.zip') as archive:
        require(archive.testzip() is None, 'Source ZIP CRC failure')
        metadata = {'POS02_SOURCE_SHA256.json', 'POS02_PROFILE.json', 'Verify-Source.ps1', 'Run-Synthetic-Tests.ps1'}
        require(set(archive.namelist()) == set(sources) | metadata, 'Unexpected archive paths')
        for name, digest in sources.items():
            require(not Path(name).is_absolute() and '..' not in Path(name).parts, 'Unsafe source path')
            require(sha(archive.read(name)) == digest, f'Source mismatch: {name}')
        require(json.loads(archive.read('POS02_SOURCE_SHA256.json')) == sources, 'Embedded manifest mismatch')
        require(archive.read('POS02_PROFILE.json') == (root / 'profile.json').read_bytes(), 'Embedded profile mismatch')
        for name in ['Verify-Source.ps1', 'Run-Synthetic-Tests.ps1']:
            require(archive.read(name) == (root / name).read_bytes(), f'Windows script mismatch: {name}')
    native = json.loads((root / 'native-recovery.json').read_text())
    require(native['status'] == 'PASS' and native['checkpointCount'] == native['availableCheckpointCount'] == 102, 'Native proof incomplete')
    require(len(native['checkpoints']) == 102, 'Native checkpoint record count mismatch')
    expected_matrix = {'send': 15, 'uncertain': 14, 'reprint': 15, 'confirm': 4, 'remotecreate': 37, 'localconfirm': 17}
    expected_ids = {(scenario, n) for scenario, count in expected_matrix.items() for n in range(1, count + 1)}
    actual_ids = [(v['scenario'], v['checkpoint']) for v in native['checkpoints']]
    require(len(set(actual_ids)) == len(actual_ids) and set(actual_ids) == expected_ids, 'Native checkpoint identities/matrix mismatch')
    require(native['allRealHttpBlocked'] and native['syntheticOnly'] and native['temporaryDirectoryRemoved'], 'Native isolation evidence missing')
    for name, digest in native['sourceSha256'].items():
        require(sources.get('apps/operations/' + name) == digest, f'Native source binding mismatch: {name}')
    for checkpoint in native['checkpoints']:
        require(checkpoint['signal'] == 'SIGKILL' and checkpoint['writerExit'] != 0, 'Native kill evidence missing')
        require(checkpoint['restart']['status'] == 'PASS', 'Native restart failed')
        require(checkpoint['beforeKill']['pid'] != checkpoint['restart']['readerPid'], 'Native process identity reused')
    with zipfile.ZipFile(root / 'logs.zip') as archive:
        require(archive.testzip() is None, 'Log ZIP CRC failure')
        logs = json.loads((root / 'log-sha256.json').read_text())
        require(set(logs) == set(archive.namelist()), 'Log set mismatch')
        for name, digest in logs.items():
            require(sha(archive.read(name)) == digest, f'Log mismatch: {name}')
        saved = events(archive.read('admin-acceptance-tests.jsonl'))
        count = passing(saved, 855)
        require(sum(v.get('type') == 'suite' for v in saved) == 72, 'Suite count mismatch')
        passing(events(archive.read('admin-focused-tests.jsonl')), 124)
        passing(events(archive.read('admin-entry-tests.jsonl')), 2)
        require('No issues found!' in archive.read('admin-analyze-final.log').decode(), 'Analyzer success missing')
        require('43 files (0 changed)' in archive.read('admin-format.log').decode(), 'Format verification missing')
        require('Built build/macos/Build/Products/Debug/Vynic Manager.app' in archive.read('admin-build.log').decode(), 'Mac compile success missing')
        for checkpoint in native['checkpoints']:
            prefix = f"admin-native-proof.{checkpoint['scenario']}-{checkpoint['checkpoint']:03d}"
            for stage in ['writer', 'reader']:
                require(sha(archive.read(f'{prefix}-{stage}.log')) == checkpoint[f'{stage}LogSha256'], 'Native log binding mismatch')
        for scenario, digest in native['captureLogSha256'].items():
            require(sha(archive.read(f'admin-native-proof.{scenario}-boundaries-boundaries.log')) == digest, 'Native capture log mismatch')
    review = json.loads((root / 'review.json').read_text())
    require(review['independent'] and review['readOnly'] and review['remainingP1'] == review['remainingP2'] == 0, 'Review incomplete')
    require(sources['apps/operations/test/widget/pos02_kitchen_entry_points_test.dart'] == review['finalScreenTestSha256'], 'Review test binding mismatch')
    preserve = json.loads((root / 'preservation.json').read_text())
    require(not preserve['missingOriginalFiles'] and not preserve['index'], 'Preservation/index evidence mismatch')
    for name, digest in preserve['oldArchivesSha256'].items():
        require(sha((repo / name).read_bytes()) == digest, f'Historical archive changed: {name}')
    owned = json.loads((root / 'owned-paths.json').read_text())
    require(len(owned) == 44, 'Owned path count mismatch')
    if args.check_owned_checkout:
        for name in owned:
            require(sha((repo / name).read_bytes()) == sources[name], f'Tested owned checkout mismatch: {name}')
    print(json.dumps({'status': 'PASS', 'sourceFiles': len(sources), 'ownedPathsChecked': len(owned) if args.check_owned_checkout else 0, 'savedPassingChecks': count, 'acceptanceSuites': 72, 'nativeSigkillRestartCheckpoints': 102, 'nativeSourceBindings': len(native['sourceSha256']), 'windowsCurrentRevision': 'PENDING_NOT_RUN', 'physicalAcceptance': 'PENDING', 'milestoneDone': False}, indent=2))


if __name__ == '__main__':
    main()
