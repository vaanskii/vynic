"""Add independently verified software-completion evidence without altering V8."""

import collections
import copy
import datetime
import hashlib
import json
from pathlib import Path


ROOT = Path('/tmp/vynic-readiness-resume-20261006-uv9ayewl')
SOFTWARE = ROOT / 'software-completion'
VERIFY = SOFTWARE / 'verification'
MATRIX = ROOT / 'printer-validation'
BASE = MATRIX / 'acceptance-matrix-v8-baseline.json'
BASE_SHA = '42e98fcead35c11171c9389dd31b7614b4788a7c8c096e4fe3a8841a876842d5'
SOURCE_SHA = '193e4800e5d0733a30bc6c8d4ac993590219363941e69a787bba5ac3681c8f68'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text())


def ref(path, expected=None):
    digest = sha(path)
    if expected:
        assert digest == expected, (str(path), digest, expected)
    return {'path': str(path), 'sha256': digest, 'bytes': path.stat().st_size}


assert sha(BASE) == BASE_SHA
matrix = copy.deepcopy(load(BASE))
source = load(VERIFY / 'final-cohort-source.json')
assert sha(VERIFY / 'final-cohort-source.json') == SOURCE_SHA
frozen = Path(source['snapshot'])
assert source['fileCount'] == len(source['files']) == 1109
for path, identity in source['files'].items():
    assert sha(frozen / path) == identity['sha256'], path

registry = matrix['evidence_registry']
registry['V8_BASELINE'] = ref(BASE, BASE_SHA)
new_evidence = {
    'S_FINAL_SOURCE': ('final-cohort-source.json', SOURCE_SHA),
    'S_TCP_RECEIPT': ('actual-tcp-crash-qualification.json', 'e502df1d058e3b39f548e37f024f13915c500c24b44882126fef0948ba5d6148'),
    'S_TCP_REVIEW': ('actual-tcp-crash-independent-review.json', '0280a5387bc8c47d1d126de97a5e3298a92f423f7d1ed9d2380d3921fe04eaf2'),
    'S_DAEMON_RECEIPT': ('printer-daemon-v1/checkpoint.json', 'ee91b017c63c04150955b8139bb8902e3bf1bee63776bafcea4465b1309885a2'),
    'S_DAEMON_REVIEW': ('printer-daemon-independent-review.json', 'c1f1afd089659144d60f753637110d8f968cfe52163a2767750bfc0941f634a6'),
    'S_PROVISIONING_RECEIPT': ('printerprovisioning-qualification.json', 'c08bb37d8ca192cd7982d571d6c360142c5dd143e6242d2006b453a4e6c55e51'),
    'S_PROVISIONING_REVIEW': ('printerprovisioning-independent-review.json', 'efee605a225833838925b4b9901bb02209fc336565f212f8774af80a99073aff'),
    'S_WINDOWS_STAGE': ('windows-software-go-stage/stage-receipt.json', 'deb1832d9d580f807e74ce1ecac57813c17c981d27151a9692aff154f02f3d01'),
}
for key, (path, expected) in new_evidence.items():
    registry[key] = ref(VERIFY / path, expected)

daemon_receipt = load(VERIFY / 'printer-daemon-v1/checkpoint.json')
for artifact in daemon_receipt['logs']:
    assert sha(Path(artifact['path'])) == artifact['sha256']
manifest_path = SOFTWARE / 'metadata/printer-daemon-owned-source-manifest.json'
registry['S_DAEMON_MANIFEST'] = ref(manifest_path, daemon_receipt['ownedManifestSha256'])
for identity in load(manifest_path)['files']:
    assert sha(frozen / identity['path']) == identity['sha256']

logs = {}
for key, relative in {
    'S_TCP_NORMAL_LOG': 'actual-tcp-crash-v1.jsonl',
    'S_TCP_RACE_LOG': 'actual-tcp-crash-v1-race.jsonl',
    'S_DAEMON_NORMAL_LOG': 'printer-daemon-v1/unit.jsonl',
    'S_DAEMON_RACE_LOG': 'printer-daemon-v1/race.jsonl',
    'S_FINAL_NORMAL_LOG': 'final-edge-tests.jsonl',
    'S_FINAL_RACE_LOG': 'final-edge-race.jsonl',
}.items():
    path = VERIFY / relative
    registry[key] = ref(path)
    events = [(line, json.loads(text)) for line, text in enumerate(path.read_text().splitlines(), 1) if text.strip()]
    assert not any(event['Action'] == 'fail' for _, event in events)
    assert 'WARNING: DATA RACE' not in path.read_text()
    logs[key] = events

tcp_receipt = load(VERIFY / 'actual-tcp-crash-qualification.json')
for name, identity in tcp_receipt['artifacts'].items():
    assert sha(VERIFY / name) == identity['sha256']

records = matrix['verified_test_records']


def test_record(key, log_key, name, source_path, declaration, execution):
    matches = [(line, e) for line, e in logs[log_key] if e['Action'] == 'pass' and e.get('Test') == name]
    assert len(matches) == 1, (key, matches)
    line, event = matches[0]
    content = (frozen / source_path).read_text().splitlines()
    declaration_lines = [n for n, text in enumerate(content, 1) if text.startswith('func ' + declaration + '(')]
    assert len(declaration_lines) == 1
    digest = sha(frozen / source_path)
    records[key] = {
        'observed_status': 'passed', 'test_name': name, 'package': event['Package'],
        'log_ref': log_key, 'record_line': line, 'event_elapsed_seconds': event.get('Elapsed'),
        'event_time': event.get('Time'), 'source_file': source_path,
        'source_root': str(frozen), 'source_declaration_line_current': declaration_lines[0],
        'source_sha256_at_verified_receipt': digest, 'source_sha256_current_inspection': digest,
        'current_source_matches_verified_receipt': True, 'frozen_source_review_accepted': True,
        'source_manifest_ref': 'S_FINAL_SOURCE', 'execution': execution,
    }


for mode in ['NORMAL', 'RACE']:
    for suffix, test in [('MIDWRITE', 'duringWrite'), ('POSTWRITE', 'afterWriteBeforeDisposition')]:
        test_record('S_TCP_' + suffix + '_' + mode, 'S_TCP_' + mode + '_LOG',
                    'TestActualTCPWriteSIGKILLNoReplay/' + test,
                    'apps/edge/internal/printqueue/crash_tcp_test.go', 'TestActualTCPWriteSIGKILLNoReplay',
                    'Actual macOS child process SIGKILL and literal127.0.0.1 TCP receiver; durable SQLite restart; no physical printer.')
    for suffix, name in [
        ('RESTART', 'TestActualForegroundExecutableHealthExclusiveStopRestartAndRetention'),
        ('REFUSAL', 'TestActualForegroundExecutableRejectsWrongPinsRootRoleWithoutReset'),
        ('DRAIN', 'TestActualForegroundExecutableTrustedStorageAndArtifactFailuresDrain'),
    ]:
        test_record('S_DAEMON_' + suffix + '_' + mode, 'S_DAEMON_' + mode + '_LOG', name,
                    'apps/edge/internal/printerdaemon/process_test.go', name,
                    'Real separately built foreground Go executable on macOS; synthetic mTLS and dedicated temporary SQLite; physical execution held.')

combined = {}
for mode, name in [('normal', 'final-edge-tests'), ('race', 'final-edge-race')]:
    status_path = VERIFY / (name + '-status.json')
    status = load(status_path)
    assert status['exitCode'] == 0 and status['sourceManifestSHA256'] == SOURCE_SHA
    assert Path(status['output']).resolve() == (VERIFY / (name + '.jsonl')).resolve()
    registry['S_FINAL_' + mode.upper() + '_STATUS'] = ref(status_path)
    events = logs['S_FINAL_' + mode.upper() + '_LOG']
    passes = [e for _, e in events if e['Action'] == 'pass' and e.get('Test')]
    skips = [{'test': e['Test'], 'package': e['Package'], 'record_line': line}
             for line, e in events if e['Action'] == 'skip' and e.get('Test')]
    assert len(passes) == 764 and len(skips) == 9
    actual = status['actualForegroundExecutable']
    assert actual['sourceManifestSHA256'] == SOURCE_SHA and actual['beforeAfterUnchanged']
    assert sha(Path(actual['path'])) == actual['sha256']
    combined[mode] = {
        'observed_status': 'passed', 'status_ref': 'S_FINAL_' + mode.upper() + '_STATUS',
        'log_ref': 'S_FINAL_' + mode.upper() + '_LOG', 'all_test_pass_records': len(passes),
        'top_level_test_pass_records': sum('/' not in e['Test'] for e in passes),
        'test_fail_records': 0, 'skip_records': skips, 'data_race_warning': False,
        'actual_foreground_executable': actual,
    }

cases = {case['number']: case for case in matrix['cases']}
for number in [8, 9, 18]:
    counterpart = cases[number]['software_counterpart']
    counterpart['previous_v8_observed_status'] = counterpart['observed_status']
    counterpart['observed_status'] = 'passed'
    counterpart['qualification'] = 'Verified bounded software analogue; exact physical, registered service and OS scenarios remain not-run.'
    counterpart['software_completion_source_manifest_ref'] = 'S_FINAL_SOURCE'
    # The shared logical Raft component is unchanged; these new tests qualify its separate executor/host analogue.
    counterpart['cluster_integration_observed_status'] = 'not-run'
    counterpart['cluster_note'] = 'This new evidence tests the separate LOCAL/held executor and foreground host; no shared physical dispatch is activated.'

cases[8]['software_counterpart']['observed'] = (
    'A real child process entered TCP Write and was SIGKILLed with no observed return marker. '
    'The loopback receiver drained an exact8192-byte prefix of the frozen2097152-byte payload after death. '
    'Reopened SQLite retained UNCERTAIN, one attempt, the exact acceptance receipt, integrity and zero automatic replay.'
)
cases[8]['software_counterpart']['verified_test_refs'] += ['S_TCP_MIDWRITE_NORMAL', 'S_TCP_MIDWRITE_RACE']
cases[8]['software_counterpart']['review_refs'] += ['S_TCP_REVIEW']
cases[8]['boundary_limits'] = [
    'Write entered with no observed return marker at SIGKILL; a wrapper-return/marker gap prevents instruction-exact kernel syscall placement.',
    'The receiver is synthetic literal loopback on one macOS host; no physical printer, venue LAN, computer power loss or Windows termination is tested by this fixture.',
    'Received bytes are transport evidence only; UNCERTAIN remains held without replay or unsafe takeover.',
]
cases[9]['software_counterpart']['observed'] = (
    'The actual loopback receiver retained16/16 frozen primary/cut bytes. The child process was SIGKILLed '
    'after Write returned Submitted and before durable primary disposition. Reopen retained UNCERTAIN, '
    'one attempt, the exact immutable receipt, SQLite integrity and zero automatic replay.'
)
cases[9]['software_counterpart']['verified_test_refs'] += ['S_TCP_POSTWRITE_NORMAL', 'S_TCP_POSTWRITE_RACE']
cases[9]['software_counterpart']['review_refs'] += ['S_TCP_REVIEW']
cases[9]['boundary_limits'] = [
    'Complete TCP bytes and Submitted never establish paper DELIVERED or a physical delivery acknowledgement.',
    'This test proves the transport-write/durable-settlement crash gap using a macOS process and loopback receiver, not a Windows OS or physical printer restart.',
]
cases[18]['software_counterpart']['observed'] = (
    'The actual separately built macOS foreground printer-agent executable serves authenticated synthetic mTLS health, '
    'refuses a concurrent instance, drains on its dedicated local stop marker, exits and restarts against the same temporary SQLite. '
    'Durable STARTED primary and spent beep remain UNCERTAIN with exact frozen bytes and zero replay. '
    'Actual wrong-pins/root/role/reader and trusted storage/helper/marker failures refuse or drain without resetting state. '
    'Historical Windows helper/queue-process proofs are separate cohorts. The new Windows CLI/tests are crosscompiled and staged only.'
)
cases[18]['software_counterpart']['verified_test_refs'] += [
    'S_DAEMON_RESTART_NORMAL', 'S_DAEMON_RESTART_RACE',
    'S_DAEMON_REFUSAL_NORMAL', 'S_DAEMON_REFUSAL_RACE',
    'S_DAEMON_DRAIN_NORMAL', 'S_DAEMON_DRAIN_RACE',
]
cases[18]['software_counterpart']['review_refs'] += ['S_DAEMON_REVIEW']
cases[18]['additional_evidence_refs'] += ['S_DAEMON_RECEIPT', 'S_WINDOWS_STAGE']
cases[18]['boundary_limits'] = [
    'Actual macOS foreground executable stop/restart is distinct from SCM service registration/restart and Windows OS power/reboot.',
    'Foreground host and synthetic mTLS status stay HELD_PROVISIONING; successful startup does not authorize print admission or physical dispatch.',
    'New ARM64/amd64 Windows CLI and four package test binaries were compiled from exact1109 source files; their new runtime execution is approval-blocked and unqualified.',
    'Earlier Windows helper/queue-process and prepared POS build proofs remain separately source-pinned historical cohorts; none implies execution of the new daemon.',
    'A standalone passing fixture entry TestForegroundHeldChild performs no work; real retained-process paths are exercised by actual child-process subtests.',
]

matrix['matrix_revision'] = 9
matrix['recorded_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
matrix['previous_version'] = ref(BASE, BASE_SHA)
matrix['previous_version']['immutable_baseline_preserved'] = True
matrix['cohort_scope'] = (
    'V8 frozen163-file Go/898-file Flutter historical evidence retained unchanged; '
    'software-completion exact1109-file final source adds verified macOS TCP crash and held foreground daemon/restart evidence. '
    'Final-cohort normal/race logs are source-identified. New Windows CLI/test binaries are compile/stage only; no new guest execution.'
)
matrix['software_completion'] = {
    'source_root': str(frozen), 'source_manifest_ref': 'S_FINAL_SOURCE', 'files_rehashed': 1109,
    'normal_and_race_execution': combined,
    'daemon_review_ref': 'S_DAEMON_REVIEW', 'provisioning_review_ref': 'S_PROVISIONING_REVIEW',
    'provisioning_scope': 'Signed printer-only candidate validation and frozen route binding only; candidate success remains HELD without a durable production receipt.',
    'windows_stage_ref': 'S_WINDOWS_STAGE', 'new_windows_runtime_observed_status': 'not-run',
    'windows_blocker': 'Parent-reported automatic approval review rejected the new current-user read-only VM preflight; no alternate guest command is authorized or attempted.',
    'production_gaps': [
        'Production issuer, current Device/Venue enrollment, persistent rollback-resistant generation/highwater/revocation and trusted lifetime policy.',
        'Activated signed routes, full business/Hive admission bridge, writer cutover and downstream physical fencing/model qualification.',
        'Authenticated shared LAN Raft runtime/relay/dispatch composition in the held daemon.',
    ],
}
matrix['global_boundaries'] += [
    'The signed candidate validator verifies externally pinned current authority and exact bytes only; it neither mints production authority nor enables Submit.',
    'New foreground software tests use temporary synthetic identities and LOCAL_HELD/SHARED_HELD status; no production credential, trust, account or machine configuration changes occur.',
]
matrix['pending_evidence'] += [
    {'area': 'new1109-cohort native Windows daemon/RPC/CLI execution', 'observed_status': 'not-run',
     'needed': 'Accepted current scoped VM authorization, then fresh source-matched current-user synthetic tests; no SCM/OS/physical mutation.'},
    {'area': 'production provisioning and physical cutover', 'observed_status': 'not-run',
     'needed': 'Production issuer/current persistent authorization policy, route activation, business writer bridge and qualified downstream fencing/model tests.'},
]
matrix['superseded_qualification_states'] += [
    {'earlier_state': 'V8 software cases8/9/18 not-run', 'scope': 'Bounded macOS TCP crash and actual held foreground executable analogue only.',
     'superseded_by_review_refs': ['S_TCP_REVIEW', 'S_DAEMON_REVIEW'], 'physical_SCM_OS_status_unchanged': 'not-run'},
]
summary = matrix['summary']
summary['bounded_software_counterpart_passed'] = sum(c['software_counterpart']['observed_status'] == 'passed' for c in matrix['cases'])
summary['bounded_software_counterpart_not_run'] = sum(c['software_counterpart']['observed_status'] == 'not-run' for c in matrix['cases'])
assert summary['bounded_software_counterpart_passed'] == 17
assert summary['bounded_software_counterpart_not_run'] == 1
assert all(c['acceptance_observed_status'] == 'not-run' and c['physical_acceptance']['observed_status'] == 'not-run' for c in matrix['cases'])
summary['new_windows_runtime_tests'] = 0
summary['actual_mac_foreground_executable_restart_counterpart'] = 'passed'
summary['full_1109_cohort_Go_normal_and_race_pass_records_each'] = 764
summary['full_1109_cohort_Go_normal_and_race_top_level_pass_records_each'] = 225
summary['full_1109_cohort_Go_normal_and_race_skip_records_each'] = 9

# Check every new test reference resolves to a logged pass and every new evidence hash still matches.
for case in matrix['cases']:
    for key in case['software_counterpart']['verified_test_refs']:
        assert key in records, (case['number'], key)
for key, identity in registry.items():
    if key.startswith('S_') or key == 'V8_BASELINE':
        assert sha(Path(identity['path'])) == identity['sha256'], key
assert sha(BASE) == BASE_SHA
payload = (json.dumps(matrix, indent=2, sort_keys=True) + '\n').encode()
version = MATRIX / 'acceptance-matrix-v9-software-completion.json'
assert not version.exists(), 'Version must be immutable once written.'
version.write_bytes(payload)
(MATRIX / 'acceptance-matrix-final.json').write_bytes(payload)
print(json.dumps({'version': str(version), 'latest': str(MATRIX / 'acceptance-matrix-final.json'),
                  'sha256': sha(version), 'software_passed': 17, 'software_not_run': 1,
                  'full_physical_not_run': 18, 'new_windows_execution': 'not-run-approval-blocked'}))
