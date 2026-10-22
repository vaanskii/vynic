"""Summarize retained printer-only evidence; never executes a printer or VM."""
from pathlib import Path
import collections
import hashlib
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def summarize(names):
    outcomes = {}
    packages = {}
    for name in names:
        rows = [json.loads(line) for line in (HERE / name).read_text().splitlines()]
        for row in rows:
            action = row['Action']
            if action not in ('pass', 'fail', 'skip'):
                continue
            if 'Test' in row:
                outcomes[(row['Package'], row['Test'])] = action
            else:
                packages[row['Package']] = action
    if not packages or any(v != 'pass' for v in packages.values()):
        raise RuntimeError(f'incomplete or failed packages: {packages}')
    if 'fail' in outcomes.values():
        raise RuntimeError('failed test record')
    return {
        'logs': names,
        'records': dict(collections.Counter(outcomes.values())),
        'topLevel': dict(collections.Counter(v for (_, t), v in outcomes.items() if '/' not in t)),
        'skips': [{'package': p, 'test': t} for (p, t), v in outcomes.items() if v == 'skip'],
        'packages': packages,
    }


normal = summarize(['all-printer-regressions.jsonl', 'final-affected-tests.jsonl', 'final-local-tests.jsonl'])
race = summarize(['final-race-tests.jsonl', 'final-local-race.jsonl'])
windows = json.loads((HERE / 'windows-final/windows-result.json').read_text('utf-8-sig'))
windows['records'] = {}
for path in (HERE / 'windows-final').glob('*.stdout.log'):
    contents = path.read_text('utf-16')
    counts = dict(collections.Counter(re.findall(r'--- (PASS|FAIL|SKIP):', contents)))
    if counts.get('FAIL') or not re.search(r'^PASS\s*$', contents, re.M):
        raise RuntimeError(f'Windows test failure/incomplete: {path}')
    windows['records'][path.name] = counts
if any(r['exitCode'] != 0 for r in windows['results']):
    raise RuntimeError('Windows process failed')

performance = []
for line in (HERE / 'performance.jsonl').read_text().splitlines():
    row = json.loads(line)
    text = row.get('Output', '')
    if 'STATION_PERF ' in text:
        performance.append(json.loads(text.split('STATION_PERF ', 1)[1]))
    if row['Action'] == 'fail':
        raise RuntimeError('performance run failed')
if len(performance) != 6:
    raise RuntimeError('missing performance cases')

manifest = json.loads((HERE / 'final-source-manifest.json').read_text())
drift = [p for p, digest in manifest.items() if hashlib.sha256((ROOT / p).read_bytes()).hexdigest() != digest]
if drift:
    raise RuntimeError(f'source changed after verification: {drift}')

cases = [
    ('1 POS + local', 'PASS_COMPONENT', 'TestLocalStationSpoolReopensWithoutRaft'),
    ('1 POS + shared station', 'PASS_COMPONENT', 'TestStationReplicatedTopologyMatrix/1'),
    ('2 POS shared kitchen', 'PASS_COMPONENT_NO_HA_CLAIM', 'TestStationReplicatedTopologyMatrix/2'),
    ('3 POS shared kitchen', 'PASS_COMPONENT', 'TestStationReplicatedTopologyMatrix/3'),
    ('4 POS / 3 voters + client', 'PASS_COMPONENT', 'TestStationReplicatedTopologyMatrix/4'),
    ('10 POS / 3 voters + clients', 'PASS_COMPONENT', 'TestStationReplicatedTopologyMatrix/10'),
    ('all LOCAL only', 'PASS_DOMAIN_AND_LOCAL_COMPONENT', 'TestTopologyMatrix; TestLocalScopeAndAllLocal'),
    ('mixed shared production and local receipts', 'PASS_DOMAIN', 'TestMixedSharedProductionAndIndependentLocalReceipts'),
    ('Kitchen + Bar independent', 'PASS_SYNTHETIC_DISPATCH', 'TestStationBlockedKitchenControllerDoesNotBlockBar'),
    ('primary unavailable before send -> backup', 'PASS_DOMAIN_AND_SYNTHETIC_DISPATCH', 'TestUnavailableControllerSkipRequiresNoDispatchReservation; TestStationControllersDispatchFallbackInFIFOOrder'),
    ('Bar continues while Kitchen unavailable', 'PASS_SYNTHETIC_DISPATCH', 'TestStationBlockedKitchenControllerDoesNotBlockBar'),
    ('lost submit ACK', 'PASS_COMPONENT', 'TestStationReplicatedTopologyMatrix; TestStationReplicaLossLeaderLossRejoinAndMinority'),
    ('duplicate ID/retry', 'PASS_COMPONENT', 'TestRestartAndLostACKRetainImmutableIdentity'),
    ('Go process restart', 'PASS_PROCESS', 'TestStationSpoolProcessKillAndIndependentRestart'),
    ('Flutter closes while queue nonempty', 'NOT_RUN_END_TO_END_UNINTEGRATED', 'Go component is independent; normal Flutter admission is not attached'),
    ('controller restart', 'PASS_LOCAL_COMPONENT_ONLY', 'TestStationSpoolProcessKillAndIndependentRestart; no installed service tested'),
    ('queue restored', 'PASS_COMPONENT', 'TestLocalStationSpoolReopensWithoutRaft'),
    ('one replica dies', 'PASS_COMPONENT', 'TestStationReplicaLossLeaderLossRejoinAndMinority'),
    ('leader dies', 'PASS_COMPONENT_AND_RETAINED_PROCESS_TEST', 'TestStationReplicaLossLeaderLossRejoinAndMinority; TestThreeProcessSIGKILLLeaderAndFourPOSRelayRecovery'),
    ('replica rejoins', 'PASS_COMPONENT', 'TestStationReplicaLossLeaderLossRejoinAndMinority'),
    ('minority cannot commit', 'PASS_COMPONENT', 'TestStationReplicaLossLeaderLossRejoinAndMinority'),
    ('UNCERTAIN primary', 'PASS_DOMAIN', 'TestUncertainNeverFallsBackOrRetries'),
    ('manual reprint', 'PASS_DOMAIN_ONLY', 'TestManualReprintAuditAndOriginalUnchanged; production Staff/reconciliation bridge pending'),
    ('backup blocked after UNCERTAIN', 'PASS_SYNTHETIC_DISPATCH', 'TestStationBlockedKitchenControllerDoesNotBlockBar'),
    ('FIFO backup ordering', 'PASS_SYNTHETIC_DISPATCH', 'TestStationControllersDispatchFallbackInFIFOOrder'),
    ('different stations independent', 'PASS_SYNTHETIC_DISPATCH', 'TestStationBlockedKitchenControllerDoesNotBlockBar'),
    ('wrong Venue rejected', 'PASS_COMPONENT', 'TestStationMalformedOversizedAndWrongVenue'),
    ('unauthenticated client rejected', 'PASS_RETAINED_LOCAL_RPC_ONLY', 'TestFreshMutualTLSClientScopePinRevocationAndProtocol; no production shared LAN API exists'),
    ('oversized/malformed rejected', 'PASS_COMPONENT', 'TestStationMalformedOversizedAndWrongVenue'),
    ('config change with queued jobs', 'PASS_DOMAIN', 'TestConfigurationAndAuthorityFailClosed'),
    ('service version mismatch', 'PASS_RETAINED_LOCAL_RPC', 'TestFreshMutualTLSClientScopePinRevocationAndProtocol'),
    ('LOCAL root alias duplicate owner', 'PASS_COMPONENT', 'TestLocalStationRootAliasCannotDuplicateOwner'),
]
physical = [
    'controller machine power loss', 'Ethernet cable pull', 'printer power loss',
    'paper out', 'printer cable removal', 'switch/network partition',
    'service kill during physical write', 'failure before physical socket write',
    'failure during physical write', 'failure after bytes accepted by physical printer',
    'cutter', 'optional beep', 'Windows reboot', 'installed service restart',
    'primary physical printer failure', 'physical backup printer fallback',
]
check = subprocess.run(['git', 'diff', '--check'], cwd=ROOT, capture_output=True, text=True)
if check.returncode:
    raise RuntimeError(check.stdout + check.stderr)
(HERE / 'diff-check.txt').write_text(check.stdout + check.stderr)
(HERE / 'final-status.txt').write_bytes(subprocess.check_output(['git', 'status', '--short'], cwd=ROOT))
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
if head != (HERE / 'starting-head.txt').read_text().strip():
    raise RuntimeError('HEAD changed')
evidence = {
    'version': 1, 'date': '2026-10-09', 'timezone': 'Asia/Tbilisi',
    'branch': subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip(),
    'head': head, 'status': 'NOT_DONE', 'productionAdmission': 'HELD',
    'physicalActivation': 'HELD', 'unsafeSameRawTakeoverEnabled': False,
    'sourceManifest': 'final-source-manifest.json', 'sourceFiles': len(manifest),
    'sourceDrift': [], 'normal': normal, 'race': race, 'windows': windows,
    'performance': performance,
    'performanceSource': 'source-before-local-alias-fix.json',
    'performanceLimit': 'One Mac, all replicas in-process; software overhead, not printer or deployed LAN throughput. Final change only fixes LOCAL directory alias exclusion.',
    'softwareMatrix': [{'case': c, 'status': s, 'evidence': e} for c, s, e in cases],
    'physicalMatrix': [{'case': c, 'status': 'NOT_RUN'} for c in physical],
    'softwareGaps': ['production normalized storage and retention', 'signed station/scope publication and configuration UI', 'production issuer/protected authorization bridge', 'authenticated LAN and normal Flutter/local RPC station admission', 'retained controller receipts/drain and Staff reconciliation', 'Hive writer cutover/import/rollback adapter', 'automatic SCM startup/recovery and service-principal qualification'],
    'vet': 'PASS', 'diffCheck': 'PASS', 'commits': [], 'pushes': [],
}
(HERE / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps({'normal': normal['records'], 'race': race['records'], 'windows': windows['records'], 'sourceFiles': len(manifest), 'status': evidence['status']}, indent=2))
