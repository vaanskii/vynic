#!/usr/bin/env python3
"""Collect this packet only; never modifies historical printer proofs."""
import collections
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

def records(name):
    return [json.loads(line) for line in (HERE / name).read_text().splitlines()]

def test_summary(name):
    data = records(name)
    counts = collections.Counter(row['Action'] for row in data if row.get('Test') and row['Action'] in ('pass', 'fail', 'skip'))
    packages = {row['Package']: row['Action'] for row in data if not row.get('Test') and row['Action'] in ('pass', 'fail')}
    if not packages or any(v != 'pass' for v in packages.values()) or counts['fail']:
        raise RuntimeError(f'Incomplete or failed final selection: {name}')
    return {'log': name, 'records': dict(counts), 'packages': packages,
            'skips': [r['Test'] for r in data if r.get('Test') and r['Action'] == 'skip']}

def performance(name):
    data = records(name)
    if not any(r['Action'] == 'pass' and not r.get('Test') for r in data):
        raise RuntimeError(f'Incomplete performance selection: {name}')
    return [json.loads(r['Output'].split('STATION_PERF ', 1)[1]) for r in data if 'STATION_PERF ' in r.get('Output', '')]

source = json.loads((HERE / 'storage-source-manifest.json').read_text())
drift = [name for name, digest in source.items() if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
if drift:
    raise RuntimeError(f'Final source changed: {drift}')
windows = json.loads((HERE / 'windows/windows-result.json').read_text(encoding='utf-8-sig'))
windows['records'] = {}
for log in (HERE / 'windows').glob('*.stdout.log'):
    raw = log.read_text(encoding='utf-16')
    windows['records'][log.name] = dict(collections.Counter(re.findall(r'^\s*--- (PASS|FAIL|SKIP):', raw, re.M)))
if any(r['exitCode'] for r in windows['results']):
    raise RuntimeError('Windows selection failed')
baseline = json.loads((ROOT / 'docs/proofs/PRINT_ARCHITECTURE_3463ee40_2026-10-09/evidence.json').read_text())['performance']
matrix = [{'case': c, 'status': 'NOT_PROVEN_INTEGRATED'} for c in [
    'A: 1 POS LOCAL', 'B: 1 POS shared', 'C: 2 POS fixed host', 'D: 3 voters',
    'E: 4 POS', 'F: 10 POS', 'G: Kitchen and Bar', 'H: source exits after acceptance',
    'I: Flutter closes', 'J: local Go restart', 'K: leader dies', 'L: replica dies',
    'M: replica rejoins', 'N: lost admission ACK', 'O: duplicate ID', 'P: changed bytes same ID',
    'Q: controller lost before reservation', 'R: controller dies after reservation',
    'S: definitive backup', 'T: uncertain no backup', 'U: manual reprint',
    'V: independent station', 'W: config update queued jobs', 'X: Hive cutover',
    'Y: rollback', 'Z: backup/restore']]
evidence = {
    'version': 1, 'date': '2026-10-09', 'status': 'NOT_DONE',
    'branch': subprocess.check_output(['git','branch','--show-current'], cwd=ROOT, text=True).strip(),
    'startHead': '3463ee406184fec7f53818416e11d0e5f5602c87',
    'finalHead': subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip(),
    'productionAdmission': 'HELD', 'physicalActivation': 'HELD',
    'scopeImplemented': 'Normalized printer storage, payload retention, snapshots and reader/proof protocol gates',
    'sourceManifest': 'storage-source-manifest.json', 'sourceFiles': len(source), 'sourceDrift': drift,
    'normal': test_summary('final-printer-regressions.jsonl'),
    'finalAffected': test_summary('final-affected.jsonl'),
    'race': test_summary('final-race.jsonl'),
    'raceSource': 'source-before-timing-fix.json',
    'raceSourceDifference': 'Only payload measurement accounting moved after successful SQL commit; final affected and native Windows runs use the final source.',
    'windows': windows, 'before': baseline,
    'after': performance('storage-performance-final.jsonl'),
    'uniquePayloadStress': performance('storage-performance-unique.jsonl'),
    'performanceLimits': 'One Mac, in-process replicas; synthetic dispatch; allocation is cumulative, not peak. Payload persistence measures successful FULL/WAL transactions that write payload references/bytes. Admission and result timings include majority and leader FSM durability. No deployed LAN or printer throughput claim.',
    'retention': {'terminalDays': 30, 'unresolvedExpiry': None, 'pinsReprintOriginals': True,
                  'retiredExactRetries': 'REFUSED', 'productionScheduler': 'NOT_IMPLEMENTED'},
    'reader': {'storageSchema': 2, 'commandVersion': 2, 'snapshotVersion': 2,
               'legacyStore': 'REFUSED_BEFORE_SCHEMA_MUTATION', 'automaticMigration': 'NOT_IMPLEMENTED'},
    'integratedSoftwareMatrix': matrix,
    'productionSecurityMatrix': 'NOT_PROVEN: production authenticated runtime and issuer/config publication are not integrated',
    'physicalTests': 'NOT_RUN', 'servicePrincipal': 'NOT_QUALIFIED',
    'serviceRegistration': 'NOT_RUN', 'commits': [], 'push': False,
    'remainingSoftware': ['server-owned signed printer-purpose enrollment and config publication',
        'protected revocation/high-water state', 'authenticated Venue LAN RPC/Raft and stable production membership',
        'Admin station/physical-printer management', 'normal Flutter planner/admission and business-routing attachment',
        'retained controller-side receipts and recovery/drain', 'production operator reconciliation',
        'Hive migration/exclusion/cutover and rollback', 'automatic service lifecycle and principal qualification',
        'production upgrade/retention scheduling', 'integrated A-Z and Flutter/Windows proof'],
}
(HERE / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps({'status': evidence['status'], 'normal': evidence['normal']['records'], 'windows': windows['records'], 'sourceDrift': drift}))
