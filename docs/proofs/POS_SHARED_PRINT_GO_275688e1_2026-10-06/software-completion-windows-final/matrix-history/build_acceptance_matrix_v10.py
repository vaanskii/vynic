"""New Windows completion matrix; all earlier matrix files remain unchanged."""

import copy
import datetime
import hashlib
import json
from pathlib import Path


ROOT = Path('/tmp/vynic-readiness-resume-20261006-uv9ayewl')
MATRIX = ROOT / 'printer-validation'
VERIFY = ROOT / 'software-completion/verification'
WINDOWS = VERIFY / 'windows-software-v2'
BASE = MATRIX / 'acceptance-matrix-v9-software-completion.json'
BASE_SHA = '19f3cc4431982ad2f1304a0ba485b3e3588234096d019c3dbf3c58c9448f5f70'
SOURCE_SHA = 'faaaec2f1ece4f8259353666000eb4c0d3aee6143e73ae7fdf90772a937b581b'
PROOF = Path('/Users/vaanskii/Developer/vynic/docs/proofs/POS_SHARED_PRINT_GO_275688e1_2026-10-06')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def ref(path, expected=None):
    digest = sha(path)
    if expected:
        assert digest == expected, (str(path), digest, expected)
    return {'path': str(path), 'sha256': digest, 'bytes': path.stat().st_size}


assert sha(BASE) == sha(MATRIX / 'acceptance-matrix-final.json') == BASE_SHA
matrix = copy.deepcopy(load(BASE))
registry = matrix['evidence_registry']
registry['V9_BASELINE'] = ref(BASE, BASE_SHA)
registry['W2_SOURCE'] = ref(VERIFY / 'final-cohort-v2-source.json', SOURCE_SHA)
registry['W2_LINEAGE'] = ref(WINDOWS / 'final-cohort-v2-lineage.json', 'bab023485c929364a2a4432586615e07de6af9d99911c0030070b516694e4ee3')
registry['W2_FIXTURE_SOURCE_REVIEW'] = ref(WINDOWS / 'fixture-native-paths-v2-independent-review.json', '91b62022b8c73aa1641706ba0dfef155aafbdc90b7df20510b6e26767161fbb5')
registry['W2_PREFLIGHT_RETRY'] = ref(WINDOWS / 'preflight-retry-receipt.json')
registry['W2_GO_RECEIPT'] = ref(WINDOWS / 'go-packages-final-receipt.json', '60a07b83aa83d4e60cda75c6035715b8d1eb7dae4ef6225dfe1c242b182f06ae')
registry['W2_GO_REVIEW'] = ref(WINDOWS / 'go-runtime-independent-review.json', 'e711f5cb0f03a4b53c7581a92243d8814d77dc83b30b85c2048be2820e327dd0')
registry['W2_GO_STAGE'] = ref(PROOF / 'windows-software-go-packages-stage-v2/stage-receipt.json', '6004c62c195e96b4ba9f54e065b9c1e887924054c0168ca7e2c49b854ba2b4f4')
registry['W2_GO_ARTIFACTS'] = ref(PROOF / 'windows-software-go-packages-result-v2/artifact-sha256.json', '96c9404f3f5af428e23d7a49e9e9dd81221a619a90a13b66b87b68a29d2aea3a')
registry['W2_FLUTTER_RECEIPT'] = ref(WINDOWS / 'flutter-v3-final-receipt.json', 'f25fdd77b405b7b445e39ce1dd0cf15f153630542c140ab396a2b87721f21d60')
registry['W2_FLUTTER_REVIEW'] = ref(WINDOWS / 'flutter-combined-independent-review-final.json', '92c7dcb4ffcd69795145ba0959a5a63117407d2fc819fb7a2f0662dd41408cb2')

source_receipt = load(VERIFY / 'final-cohort-v2-source.json')
source = Path(source_receipt['snapshot'])
assert len(source_receipt['files']) == source_receipt['fileCount'] == 1109
for name, identity in source_receipt['files'].items():
    assert sha(source / name) == identity['sha256']
old_source = load(VERIFY / 'final-cohort-source.json')
assert set(old_source['files']) == set(source_receipt['files'])
delta = [name for name in source_receipt['files']
         if source_receipt['files'][name]['sha256'] != old_source['files'][name]['sha256']]
assert len(delta) == 2 and all(name.startswith('apps/operations/test/') for name in delta)
assert not any(name.startswith(('apps/edge/', 'packages/contracts/generated/go/', 'packages/contracts/proto/')) for name in delta)

go = load(WINDOWS / 'go-packages-final-receipt.json')
assert go['summary'] == {'topLevelPass': 104, 'subtestPass': 410, 'passRecords': 514, 'fixtureEntrySkips': 2, 'capabilitySkips': 0, 'failRecords': 0}
assert go['sourceBinaryBundleBeforeAfterMatched'] and all(v['before'] == v['after'] == 0 for v in go['zeroSpoolerJobInventories'].values())
registry['W2_GO_RAW'] = ref(Path(go['rawResult']['path']), go['rawResult']['sha256'])
registry['W2_GO_LAUNCH'] = ref(Path(go['launchReceipt']['path']), go['launchReceipt']['sha256'])
records = matrix['verified_test_records']
process_source = 'apps/edge/internal/printerdaemon/process_test.go'
process_lines = (source / process_source).read_text().splitlines()
new_test_refs = []
for architecture in ['arm64', 'amd64']:
    package = go['packages'][architecture + '/printerdaemon']
    log_key = 'W2_GO_' + architecture.upper() + '_DAEMON_LOG'
    registry[log_key] = ref(Path(package['stdout']['path']), package['stdout']['sha256'])
    for suffix, name in [
        ('RESTART', 'TestActualForegroundExecutableHealthExclusiveStopRestartAndRetention'),
        ('REFUSAL', 'TestActualForegroundExecutableRejectsWrongPinsRootRoleWithoutReset'),
        ('DRAIN', 'TestActualForegroundExecutableTrustedStorageAndArtifactFailuresDrain'),
    ]:
        matches = [r for r in package['records'] if r['status'] == 'PASS' and r['test'] == name]
        assert len(matches) == 1
        event = matches[0]
        declaration = [number for number, line in enumerate(process_lines, 1) if line.startswith('func ' + name + '(')]
        assert len(declaration) == 1
        key = 'W2_CLI_' + suffix + '_' + architecture.upper()
        records[key] = {
            'observed_status': 'passed', 'test_name': name, 'package': 'vynic.local/edge/internal/printerdaemon',
            'log_ref': log_key, 'record_line': event['logLine'], 'event_elapsed_seconds': event['elapsedSeconds'],
            'source_root': str(source), 'source_file': process_source, 'source_manifest_ref': 'W2_SOURCE',
            'source_declaration_line_current': declaration[0], 'source_sha256_at_verified_receipt': sha(source / process_source),
            'source_sha256_current_inspection': sha(source / process_source), 'current_source_matches_verified_receipt': True,
            'frozen_source_review_accepted': True, 'actual_packaged_CLI_sha256': go['shippedCLI'][architecture],
            'execution': 'Actual supplied packaged foreground CLI on Windows; ' + ('nativeARM64' if architecture == 'arm64' else 'amd64 under Windows-on-ARM emulation') + '; temporary synthetic mTLS/SQLite, held physical admission.',
        }
        new_test_refs.append(key)
for package in go['packages'].values():
    for identity in [package['stdout'], package['stderr']]:
        assert sha(Path(identity['path'])) == identity['sha256']

flutter = load(WINDOWS / 'flutter-v3-final-receipt.json')
assert flutter['status'] == 'PASS_EXACT_FROZEN_V2_WINDOWS_39_68' and flutter['sourceReceiptSHA256'] == SOURCE_SHA
assert flutter['visiblePassed'] == 623 and flutter['hiddenPassed'] == 51 and flutter['skipped'] == flutter['errorEvents'] == 0
assert flutter['suiteCount'] == 39 and flutter['analysisFiles'] == 68 and flutter['analysisNoIssues']
assert flutter['runnerResult']['sourceBefore'] and flutter['runnerResult']['sourceAfter']
assert flutter['runnerResult']['printJobsBefore'] == flutter['runnerResult']['printJobsAfter'] == 0
flutter_directory = Path(flutter['rawResultDirectory'])
for name, identity in flutter['rawFiles'].items():
    registry['W2_FLUTTER_RAW_' + name.upper().replace('.', '_').replace('-', '_')] = ref(flutter_directory / name, identity['sha256'])
failed_fixture = WINDOWS / 'flutter-first-failed-receipt.json'
registry['W2_RETAINED_FIXTURE_FAILURE'] = ref(failed_fixture, flutter['supersededInitialFailureReceiptSHA256'])

case18 = next(case for case in matrix['cases'] if case['number'] == 18)
case18['software_counterpart']['observed'] = case18['software_counterpart']['observed'].replace(
    ' The new Windows CLI/tests are crosscompiled and staged only.', '')
case18['software_counterpart']['observed'] += (
    ' The replacement1109-source Windows cohort now executes BOTHactual shipped CLI architectures: '
    'authenticated held health, concurrent-instance exclusion, normal dedicated stop-marker exit, '
    'foreground restart with exact retained primary/spent-beep UNCERTAIN, and trusted failure drain all pass. '
    'ARM64 is native and amd64 is emulated. No registered SCM service or Windows OS restart occurred.'
)
case18['software_counterpart']['verified_test_refs'] += new_test_refs
case18['software_counterpart']['review_refs'] += ['W2_GO_REVIEW', 'W2_FLUTTER_REVIEW']
case18['software_counterpart']['software_completion_source_manifest_ref'] = 'W2_SOURCE'
case18['additional_evidence_refs'] += ['W2_GO_RECEIPT', 'W2_FLUTTER_RECEIPT', 'W2_GO_ARTIFACTS']
case18['boundary_limits'] = [
    'Actual packaged Windows foreground CLI stop/restart is software process qualification; SCM registration/service-account lifecycle, registered-service restart and OS reboot/power loss remain not-run.',
    'NativeARM64 and emulatedamd64 use exact separately pinned shipped CLI artifacts, with all1109 source/binary/bundle bytes and currentSID verified before/after.',
    'Bundled native helper/profile hashes are checked before/after; daemon fixtures use synthetic unexecuted held-helper.bin. Actual native helper execution remains a separate earlier proof cohort.',
    'Foreground config/status/Submit remain HELD_PROVISIONING; restart success never grants production print admission or physical dispatch.',
    'TestPrinterAgentProcess skips as a standalone cross-language fixture entry once perarchitecture; the Windows Flutter packet invokes that actual Go fixture separately. There are no capability skips.',
    'TestForegroundHeldChild passes as a standalone no-op entry; retained-process behavior runs through three actual parent-invoked child cases perarchitecture.',
]

matrix['matrix_revision'] = 10
matrix['recorded_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
matrix['previous_version'] = ref(BASE, BASE_SHA)
matrix['previous_version']['immutable_baseline_preserved'] = True
matrix['source_root'] = str(source)
matrix['cohort_scope'] = (
    'Current replacement1109-file faaaec source; exactly two reviewed Dart test-path fixture changes, '
    'with1107 files and all201 Edge/generatedGo/proto repository inputs unchanged from193e source. '
    'Historical V8/V9 receipts remain separately pinned. Actual Windows four-package tests perARM64/amd64 '
    'and supplied packaged foreground CLIs plus39Flutter/68analysis are qualified; physical/SCM/OS acceptance is unchanged.'
)
matrix['source_hashes_v8_v9_scope'] = 'Existing source_hashes map and historical records retain their original source_root and receipt scope; current full source is explicitly pinned by W2_SOURCE/W2_LINEAGE.'
completion = matrix['software_completion']
completion['previous_source_root'] = completion['source_root']
completion['source_root'] = str(source)
completion['source_manifest_ref'] = 'W2_SOURCE'
completion['source_lineage_ref'] = 'W2_LINEAGE'
completion['source_changes'] = delta
completion['Go_normal_race_receipts_scope'] = 'Recorded V1 normal/race764pass each remain bound to their original193e source; all Go/generatedGo/proto inputs are byte-identical in currentfaaaec source. No duplicate broadGo rerun claimed.'
completion['new_windows_runtime_observed_status'] = 'passed'
completion['previous_windows_blocker'] = completion.pop('windows_blocker')
completion['preflight_resolution'] = 'Exactly one identical rejected-preflight retry accepted; current-user SID1000/ARM64/zerojobs confirmed. Parent then explicitly authorized the bounded Windows package/foreground checks; no alternate executor, settings or elevation.'
completion['Windows_Go'] = {
    'receipt_ref': 'W2_GO_RECEIPT', 'review_ref': 'W2_GO_REVIEW', 'stage_ref': 'W2_GO_STAGE',
    'source_files': 1109, 'architectures': ['nativeARM64', 'emulatedamd64'],
    'pass_records': 514, 'top_level_pass_records': 104, 'subtest_pass_records': 410,
    'fixture_entry_skips': 2, 'capability_skips': 0, 'fail_records': 0,
    'actual_packaged_foreground_CLI_executed': True, 'POS_product_started': False,
    'native_helper_execution_in_this_packet': False, 'helper_profile_bundle_hashes_before_after_verified': True,
    'physical_docs': 0, 'registered_service_restarts': 0, 'Windows_OS_restarts': 0,
}
completion['Windows_Flutter'] = {
    'receipt_ref': 'W2_FLUTTER_RECEIPT', 'review_ref': 'W2_FLUTTER_REVIEW', 'suites': 39,
    'visible_pass_records': 623, 'hidden_pass_records': 51, 'skips': 0, 'error_events': 0,
    'analysis_selectors': 68, 'analysis_no_issues': True, 'source_and_Go_fixture_hashes_before_after_verified': True,
    'currentSID': go['currentSID'], 'point_in_time_spooler_counts': [0, 0], 'POS_product_started': False,
}
matrix['execution_history'].append({
    'id': 'W2_RETAINED_MIXED_PATH_TEST_FIXTURE_FAILURE', 'receipt_ref': 'W2_RETAINED_FIXTURE_FAILURE',
    'observed_status': 'failed', 'source_manifest_ref': 'S_FINAL_SOURCE',
    'observed': 'Initial Windows39 continuation run rejected mixed-separator fixture paths through the unchanged strict production path validator. Raw failed run is retained.',
    'final_disposition': 'Exactly two reviewed Dart test fixture changes use platform-correct path.join; newfaaaec full39/68 Windows run passes. No production-path relaxation or Go source change.',
})
matrix['superseded_qualification_states'].append({
    'earlier_state': 'V9 new Windows package/foreground execution approval-blocked/not-run',
    'scope': 'Only current-user synthetic Windows4packages perarchitecture, actual shipped foreground CLI and full39Flutter/68analysis; not SCM/OS/physical.',
    'superseded_by_review_refs': ['W2_GO_REVIEW', 'W2_FLUTTER_REVIEW'],
})
matrix['pending_evidence'] = [entry for entry in matrix['pending_evidence']
                              if entry['area'] != 'new1109-cohort native Windows daemon/RPC/CLI execution']
matrix['global_boundaries'].append('Current shipped printer-agent foreground CLI is executed in dedicated synthetic held state. Legacy raw result productStarts=0 refers to normal POS product execution; no absence of foreground CLI execution is implied.')
summary = matrix['summary']
summary['new_windows_runtime_tests'] = 514
summary['new_windows_top_level_pass_records'] = 104
summary['new_windows_subtest_pass_records'] = 410
summary['new_windows_fixture_entry_skips'] = 2
summary['new_windows_capability_skips'] = 0
summary['new_windows_fail_records'] = 0
summary['actual_Windows_foreground_CLI_restart_counterpart'] = 'passed-nativeARM64-and-emulatedamd64'
summary['new_Windows_Flutter_visible_pass'] = 623
summary['new_Windows_Flutter_hidden_pass'] = 51
summary['new_Windows_Flutter_suites'] = 39
summary['new_Windows_analysis_selectors'] = 68
assert summary['bounded_software_counterpart_passed'] == 17 and summary['bounded_software_counterpart_not_run'] == 1
assert all(case['acceptance_observed_status'] == case['physical_acceptance']['observed_status'] == 'not-run' for case in matrix['cases'])
assert summary['actual_Windows_OS_restart_tests'] == summary['actual_Windows_SCM_service_restart_tests'] == summary['physical_documents'] == 0
for key, identity in registry.items():
    if key.startswith('W2_') or key == 'V9_BASELINE':
        assert sha(Path(identity['path'])) == identity['sha256']
for case in matrix['cases']:
    assert all(key in records for key in case['software_counterpart']['verified_test_refs'])
destination = MATRIX / 'acceptance-matrix-v10-windows-completion.json'
assert not destination.exists()
destination.write_text(json.dumps(matrix, indent=2, sort_keys=True) + '\n')
assert sha(BASE) == sha(MATRIX / 'acceptance-matrix-final.json') == BASE_SHA
assert sha(MATRIX / 'acceptance-matrix-v8-baseline.json') == '42e98fcead35c11171c9389dd31b7614b4788a7c8c096e4fe3a8841a876842d5'
print(json.dumps({'path': str(destination), 'sha256': sha(destination), 'V9AndFinalAliasUnchanged': True,
                  'softwarePass': 17, 'softwareNotRun': 1, 'fullPhysicalNotRun': 18, 'actualWindowsGoPass': 514}))
