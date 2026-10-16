#!/usr/bin/env python3
"""Read-only verification of POS-02.B final evidence and the sealed source."""
from pathlib import Path
import hashlib
import json

packet = Path(__file__).resolve().parent
repo = packet.parents[2]
def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
for name, root in [('source-manifest.json', repo), ('ARTIFACTS.json', packet)]:
    manifest = json.loads((packet / name).read_text())
    for path, expected in manifest.items():
        assert digest(root / path) == expected, f'{name}: changed {path}'
proof = json.loads((packet / 'proof.json').read_text())
assert proof['status'] == 'DONE' and proof['overallPOS02'] == 'NOT_DONE'
for section in ['process', 'race', 'regression', 'performanceRun']:
    summary = proof[section]
    rows = [json.loads(line) for line in (packet / summary['log']).read_text().splitlines()]
    assert rows[-1]['Action'] == 'pass'
    assert not any(row['Action'] == 'fail' for row in rows)
    assert sum(row['Action'] == 'pass' and 'Test' in row for row in rows) == summary['passedRecords']
    assert [row['Test'] for row in rows if row['Action'] == 'skip' and 'Test' in row] == summary['skippedTests']
win = json.loads((packet / 'windows-result.json').read_text(encoding='utf-8-sig'))
assert win['exitCode'] == 0
assert (packet / 'windows-native.log').read_text(encoding='utf-8-sig').count('--- PASS:') == proof['windows']['passedRecords']
binaries = json.loads((packet / 'binary-manifest.json').read_text())
assert next(b['sha256'] for b in binaries if b['path'].endswith('/peer.test.exe')) == win['sha256'].lower()
for item in json.loads((packet / 'changed-existing-files.json').read_text()):
    assert digest(repo / item['path']) == item['afterSha256']
for item in json.loads((packet / 'new-stage-files.json').read_text()):
    assert digest(repo / item['path']) == item['sha256']
assert all(item['status'] == 'PASS' for item in proof['requirements'].values())
assert not proof['nextSubstageStarted']
assert proof['safety']['physicalWriter'] == 'HELD'
print('POS-02.B: source/artifact hashes and final test outcomes verified.')
