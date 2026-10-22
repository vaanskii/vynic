#!/usr/bin/env python3
"""Read existing receipts only; preserve the draft and build an 18-case matrix."""
import argparse
import copy
import datetime
import hashlib
import json
from pathlib import Path
import re
import zipfile


ROOT = Path('/tmp/vynic-readiness-resume-20261006-uv9ayewl')
SOURCE = ROOT / 'source'
OUT = ROOT / 'printer-validation'
WINDOWS = Path('/Users/vaanskii/Developer/vynic/docs/proofs/POS_SHARED_PRINT_GO_275688e1_2026-10-06/windows-result-v2')
PRIOR_SHA = '4f1362f96eb4040bf36ac6d0639e0c73f0729c3f22ce0a3dbbf3c51c7bfda66a'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_text(path):
    raw = path.read_bytes()
    return raw.decode('utf-16') if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else raw.decode('utf-8-sig')


def load(path):
    return json.loads(read_text(path))


def path_for(entry):
    p = Path(entry['path'])
    return p if p.is_absolute() else ROOT / p


def register(d, key, path, expected=None):
    path = Path(path)
    digest = sha(path)
    if expected is not None:
        assert digest == expected, (key, digest, expected)
    try:
        name = str(path.relative_to(ROOT))
    except ValueError:
        name = str(path)
    d['evidence_registry'][key] = {'path': name, 'sha256': digest, 'bytes': path.stat().st_size}
    return digest


def json_events(path):
    events = []
    for line, text in enumerate(read_text(path).splitlines(), 1):
        if text.strip():
            events.append((line, json.loads(text)))
    return events


def declaration(name, paths):
    top = name.split('/')[0]
    pattern = re.compile(r'^func\s+' + re.escape(top) + r'\s*\(', re.MULTILINE)
    for path in paths:
        text = path.read_text()
        found = pattern.search(text)
        if found:
            return path, text[:found.start()].count('\n') + 1
    raise AssertionError(('missing test declaration', name))


CLUSTER_TESTS = {
    'C_BEEP_ELECTION_TWO_PRINTERS': 'TestStartedBeepAcrossElectionStaysHeldOtherPrinterProgresses',
    'C_LOCAL_DURING_QUORUM_LOSS': 'TestIndependentLOCALDurableQueueWorksDuringActualSharedQuorumLoss',
    'C_TWO_POS_FULL_REPLICA': 'TestTwoPOSPlusThirdFullReplicaMajority',
    'C_THREE_FULL_VOTERS': 'TestThreeFullVotersMajorityDedupConfigFreezeAndRestart',
    'C_CONFIG_FROZEN': 'TestThreeFullVotersMajorityDedupConfigFreezeAndRestart/committed_configuration_does_not_follow_later_endpoint_edit',
    'C_ALL_STORES_COLD_REOPEN': 'TestThreeFullVotersMajorityDedupConfigFreezeAndRestart/cold_restart_all_stores_exact_retained_receipt',
    'C_POST_ELECTION_UNCERTAIN': 'TestLeaderLossInterruptionsAndOptionalBeepBarriers/new_leader_marks_started_uncertain_and_never_resends',
    'C_BEEP_NO_REPLAY': 'TestLeaderLossInterruptionsAndOptionalBeepBarriers/optional_beep_holds_FIFO_until_settled_then_never_repeats',
    'C_MANUAL_REPRINT_AUDIT': 'TestLeaderLossInterruptionsAndOptionalBeepBarriers/manual_reprint_fresh_IDs_committed_actor_and_reason',
    'C_MINORITY_PEER_LOSS': 'TestMinorityCannotAcceptOrUsePausedOldClaim',
    'C_NONVOTER_CLIENT': 'TestNonvoterAndClientDoNotCountTowardQuorum',
    'C_NONVOTER_NOT_QUORUM': 'TestNonvoterAndClientDoNotCountTowardQuorum/one_voter_plus_nonvoter_is_not_majority',
    'C_RASTER_8M_SNAPSHOT': 'TestFullRasterChunkingSnapshotRestoreAndBounds',
    'C_NO_INCOMPLETE_STAGING_ACCEPT': 'TestFullRasterChunkingSnapshotRestoreAndBounds/no_admission_from_incomplete_majority_durable_staging',
    'C_FIVE_FULL_VOTERS': 'TestFiveFullVotersRequireThree',
    'C_PROCESS_KILL_REJOIN': 'TestThreeProcessSIGKILLLeaderAndFourPOSRelayRecovery',
    'C_PROCESS_FANIN_2': 'TestThreeProcessSIGKILLLeaderAndFourPOSRelayRecovery/identical_job_actual_2_process_POS_relays',
    'C_PROCESS_FANIN_3': 'TestThreeProcessSIGKILLLeaderAndFourPOSRelayRecovery/identical_job_actual_3_process_POS_relays',
    'C_PROCESS_FANIN_4': 'TestThreeProcessSIGKILLLeaderAndFourPOSRelayRecovery/identical_job_actual_4_process_POS_relays',
}

WINDOWS_TESTS = {
    'W_CHILD_CONTAINMENT_EOF': 'TestWindowsJobContainsChildAndStdinHasNoInheritedWriter',
    'W_UNSUPPORTED_JOB_LIST': 'TestWindowsUnsupportedJobListFailsBeforeProcessCreation',
    'W_PARENT_DEATH_GUARD': 'TestWindowsParentDeathTerminatesChildAndFreshGuardAcquires',
    'W_ACTUAL_READONLY_HELPER': 'TestWindowsActualHelperReadOnlyAndInvalidRequests',
    'W_PRIMARY_OUTCOMES': 'TestHelperOutcomeAndNoCommitRetry',
    'W_ORIGINAL_HELPER_LIFETIME': 'TestHelperTimeoutRetainsOriginalLifetimeAndGuard',
    'W_PARTIAL_ACK_LOSS': 'TestHelperOutcomeAndNoCommitRetry/ACK_lost',
    'W_TCP_INJECTED_BOUNDARIES': 'TestTCPFailureBoundariesAndOneWrite',
}


CASE_UPDATES = {
    1: ('passed', ['C_PROCESS_KILL_REJOIN', 'C_POST_ELECTION_UNCERTAIN'],
        'The actual Raft leader OS process was SIGKILLed after a logical STARTED; two surviving FULL voters elected a replacement. The new leader retained exact payload/config/receipt, classified the interrupted primary UNCERTAIN, and the killed process cold-rejoined without replay.',
        ['Three FULL voter processes and one client process run on one macOS host over loopback; this is not computer power loss.', 'The cluster performs logical state transitions only; no physical Send or downstream takeover is enabled.']),
    2: ('not-run', ['C_PROCESS_KILL_REJOIN'],
        'Leader-process SIGKILL is verified separately. No computer disappearance, power-off, disk loss or multi-host network-loss experiment was performed.',
        ['Separate OS processes on one computer do not reproduce loss of a physical machine.']),
    3: ('passed', ['C_MINORITY_PEER_LOSS', 'E_LOGICAL_MINORITY_DENIAL', 'E_RAW_PAUSE_RESUME', 'E_BUFFER_AFTER_CLOSE'],
        'Two-way loopback Raft peer filtering isolates the old leader: it cannot ACCEPT a new job, the majority rejects its stale logical assignment, and a new majority accepts fresh work. A separate real-loopback unsafe bypass proves a paused old RAW sender can still reach the receiver.',
        ['The Raft peer filter is synthetic; the old leader was not simultaneously connected to a physical printer.', 'The expected RAW counterexample bypasses CheckPhysical intentionally. Majority/election cannot establish physical writer exclusion.']),
    4: ('passed', ['T_REFUSED_BEFORE_WRITE', 'T_PARTIAL_WRITE_UNCERTAIN', 'Q_STALLED_P1_P2_PROGRESS', 'W_TCP_INJECTED_BOUNDARIES'],
        'Injected TCP dial/prewrite failure returns NotSent; an attempted partial write returns Uncertain and is never retried. The standalone executor keeps P1 held while P2 continues. This is a bounded transport/executor analogue; the Raft tests do not disconnect a physical printer while preserving leader peer connectivity.',
        ['TCP connection failures are injected fakes, not a physical printer disappearance on a venue LAN.', 'Raft logical state and transport failure checks are separate fixtures.']),
    5: ('passed', ['C_PROCESS_KILL_REJOIN', 'C_MINORITY_PEER_LOSS'],
        'Actual leader-process SIGKILL leaves 2/3 FULL voters; they elect a different leader. A separate loopback peer-partition test also elects a replacement while the old minority cannot accept work.',
        ['Election and durable logical acceptance are qualified on one host over loopback.', 'No elected leader is granted physical RAW dispatch by the proof capability.']),
    6: ('passed', ['C_MINORITY_PEER_LOSS', 'C_NONVOTER_NOT_QUORUM', 'E_LOGICAL_MINORITY_DENIAL', 'H_SHARED_PHYSICAL_DENIAL'],
        'The isolated old leader cannot ACCEPT work or use its stale claim. One voter plus a FULL nonvoter also cannot form a majority. The shared physical gate remains held even when logical majority evidence exists.',
        ['Observed refusal is a logical queue/gate result; no attempted physical document was sent.', 'A stale raw socket outside this gate remains an unresolved fencing problem demonstrated by the unsafe counterexample.']),
    7: ('passed', ['Q_CRASH_BEFORE_SEND', 'C_POST_ELECTION_UNCERTAIN', 'W_UNSUPPORTED_JOB_LIST'],
        'Actual standalone SIGKILL immediately after durable STARTED and before fake Send records zero send calls; restart retains UNCERTAIN with no automatic replay. Logical Raft STARTED recovery and Windows pre-process refusal provide separate corroborating boundaries.',
        ['The crash boundary is before a fake Sender call, not an instrumented live TCP printer connection.', 'Windows unsupported JOB_LIST refusal is injected before CreateProcess; it is not a crash experiment.']),
    8: ('not-run', ['Q_CRASH_IN_FAKE_SEND', 'T_PARTIAL_WRITE_UNCERTAIN', 'T_CANCEL_INFLIGHT', 'W_PARTIAL_ACK_LOSS', 'C_POST_ELECTION_UNCERTAIN'],
        'Related passing tests kill a process inside fake Send, inject partial/canceled TCP writes, and hold interrupted logical STARTED. No test kills a real process during a real TCP Write to a physical printer.',
        ['Fake write interruption and logical STARTED recovery do not establish the exact live TCP-write crash window.', 'The conservative UNCERTAIN hold is verified; physical recovery requires separate qualification.']),
    9: ('not-run', ['Q_CRASH_IN_FAKE_SEND', 'Q_CRASH_POST_PRIMARY_RECORD', 'T_COMPLETE_WRITE_SUBMITTED', 'H_RECONSTRUCTION_UNCERTAIN', 'W_PARTIAL_ACK_LOSS'],
        'Fake full-write submission, lost helper ACK and durable restart boundaries pass. No recorded test crashes after a real physical TCP write and before a paper-delivery acknowledgement or durable delivery record.',
        ['Submitted is transport acceptance evidence and never paper DELIVERED.', 'Logical MarkPrimarySubmitted does not transmit bytes and cannot prove paper delivery.']),
    10: ('passed', ['C_PROCESS_FANIN_2', 'C_PROCESS_FANIN_3', 'C_PROCESS_FANIN_4', 'C_THREE_FULL_VOTERS', 'Q_RECEIPT_RETRY'],
        'The same immutable job and original caller tuple arrive concurrently through 2, 3 and 4 separate loopback POS relay OS processes. All responses have one exact ACCEPTED receipt, and all three FULL voter stores retain the same complete payload/receipt. Changed payload or origin is refused.',
        ['These are separate OS processes on one computer with synthetic relay authentication; they are not four installed POS computers.', 'No logical ACCEPTED receipt denotes paper output.']),
    11: ('passed', ['C_BEEP_ELECTION_TWO_PRINTERS', 'C_POST_ELECTION_UNCERTAIN', 'Q_STALLED_P1_P2_PROGRESS', 'H_P1_P2_BUSINESS_DRAIN'],
        'A logical P1 job interrupted after primary submission and beep STARTED becomes beep UNCERTAIN across election; P1 FIFO remains held. The standalone SQLite executor also preserves stalled/UNCERTAIN P1 admission and ownership without replay.',
        ['The shared case injects an interrupted logical delivery state, not a physical printer powered off.', 'No timer clears the held printer or grants physical RAW failover.']),
    12: ('passed', ['C_BEEP_ELECTION_TWO_PRINTERS', 'Q_STALLED_P1_P2_PROGRESS', 'H_P1_P2_BUSINESS_DRAIN'],
        'With P1 held by interrupted optional sound, the shared majority accepts and logically claims P2. Separate real-SQLite executor/business tests send P2 once through a fake Sender while P1 remains stalled.',
        ['Shared P2 progress is logical admission/claim; byte submission through a fake Sender is qualified in the standalone executor only.', 'No physical second printer or paper output was exercised.']),
    13: ('passed', ['C_TWO_POS_FULL_REPLICA', 'C_MINORITY_PEER_LOSS', 'C_PROCESS_KILL_REJOIN'],
        'After one FULL voter stops, the surviving 2/3 majority accepts a new immutable job. After loopback peer isolation, the replacement majority also accepts fresh work. The actual process-kill fixture preserves exact retry receipts and the interrupted job through election/rejoin.',
        ['Fresh admission on surviving nodes is observed in the real loopback Raft-node fixture, not separate venue computers.', 'An UNCERTAIN physical head remains held; new admission does not imply safe dispatch on that printer.']),
    14: ('passed', ['C_TWO_POS_FULL_REPLICA', 'C_NO_INCOMPLETE_STAGING_ACCEPT', 'C_RASTER_8M_SNAPSHOT'],
        'The two-POS-plus-third-FULL fixture retains exact full payload on three voter stores, admits with 2/3 remaining, and refuses with one. Separate chunk/snapshot tests retain an 8 MiB synthetic primary payload and refuse incomplete staging; a metadata witness does not count.',
        ['The three roles are real loopback Raft runtimes with separate files on one host; independent physical machine failure is untested.', 'The 8 MiB chunk/snapshot bound is exercised in a one-voter proof fixture; the three-voter/process fixtures retain smaller complete 600/700 KiB payloads.', 'No real-printer dispatch capability is enabled.']),
    15: ('passed', ['C_PROCESS_KILL_REJOIN', 'C_PROCESS_FANIN_3', 'C_THREE_FULL_VOTERS'],
        'Three independent FULL voter OS processes retain the same immutable job bytes and stable receipt; leader-process death leaves an electing majority and cold rejoin preserves the interrupted job. Three process relays concurrently submit an identical job.',
        ['All processes run on one macOS host, not three POS computers with independent power/network faults.', 'The fixture contains an additional client process; only three FULL voters count toward quorum.']),
    16: ('passed', ['C_PROCESS_KILL_REJOIN', 'C_PROCESS_FANIN_4', 'C_NONVOTER_CLIENT', 'C_NONVOTER_NOT_QUORUM'],
        'The actual four-process fixture has three FULL voters and one client relay. Identical four-way fan-in receives one stable majority-accepted receipt. Membership tests separately prove clients/nonvoters cannot replace a voter or create majority.',
        ['The client is an inert relay fixture; no production authentication/listener or installed four-computer topology is activated.', 'Physical RAW writer exclusion is still pending regardless of quorum.']),
    17: ('passed', ['C_LOCAL_DURING_QUORUM_LOSS', 'H_LOCAL_PINS'],
        'After stopping two real loopback FULL voters, the shared minority cannot ACCEPT work. An independent LOCAL durable SQLite queue then admits and submits the frozen primary bytes exactly once through a fake Sender; the original retry receipt remains unchanged.',
        ['LOCAL submission uses a fake Sender and is not a physical printer test.', 'The outage is loss of real loopback Raft nodes on one host, not a venue-wide cluster/network outage.']),
    18: ('not-run', ['C_PROCESS_KILL_REJOIN', 'C_ALL_STORES_COLD_REOPEN', 'W_PARENT_DEATH_GUARD', 'W_CHILD_CONTAINMENT_EOF', 'H_RECONSTRUCTION_UNCERTAIN', 'H_SERVICE_STOP_MODEL', 'H_RUNTIME_STOP_WITHOUT_SCM', 'H_CALLER_CANCEL_STAYS_RUNNING'],
        'Actual Raft-process cold restart retains receipt/payload/UNCERTAIN; Windows parent death terminates its contained child and a fresh guard can acquire. The host service-control model drains trusted runtime stop, and SQLite Store/Scheduler reconstruction prevents replay. No Windows SCM service restart or OS reboot was executed.',
        ['Go process restart, Windows helper containment and modeled service control are separate from a registered service restart.', 'Windows v2 run-result explicitly records machineRestarted=false, serviceRegistration=false, productStarted=false and zero documents.', 'amd64 test/helper binaries ran in an ARM64 Windows guest; native ARM64 runtime is unqualified.']),
}


def build(args):
    prior = OUT / 'acceptance-matrix-draft.json'
    assert sha(prior) == PRIOR_SHA
    history = OUT / 'acceptance-matrix-draft.v3.json'
    assert history.read_bytes() == prior.read_bytes()
    d = copy.deepcopy(load(prior))
    for key, entry in d['evidence_registry'].items():
        assert sha(path_for(entry)) == entry['sha256'], ('historical evidence changed', key)
    d['format'] = 'vynic.printer-acceptance-evidence.v2'
    d['draft'] = not bool(args.cluster_review)
    d['matrix_revision'] = 4
    d.pop('draft_revision', None)
    d['recorded_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    d['previous_version'] = {'path': 'printer-validation/acceptance-matrix-draft.v3.json', 'sha256': PRIOR_SHA, 'bytes': prior.stat().st_size, 'original_draft_unchanged': True}
    d['superseded_qualification_states'] = [{'earlier_review_refs': ['T_REVIEW', 'T_FINAL_DELTA_REVIEW'], 'earlier_state': 'Actual Windows runtime qualification pending', 'superseded_by_review_ref': 'W_REVIEW', 'scope': 'Only the exact nonphysical 34-source Windows v2 packet; SCM and OS restart remain unexecuted.'}]
    d['method'] = 'Read-only receipt/log parsing, SHA-256 verification and targeted test-declaration/source inspection; no test rerun, VM action, physical print, SCM action, OS restart or source change in this matrix task.'
    windows_review = OUT / 'windows-transport-independent-review.json'
    register(d, 'W_REVIEW', windows_review, 'd9c919900d1af608262cf200fe67d4168d832e3f39eebd168307ab83538d4209')
    wr = load(windows_review)
    wm_path = ROOT / 'printtransport-source-manifest.v2.json'
    register(d, 'W_MANIFEST', wm_path, wr['source_manifest_sha256'])
    wm = load(wm_path)
    for name, digest in wr['reviewed_evidence_sha256'].items():
        register(d, 'W_' + name.upper().replace('.', '_').replace('-', '_'), WINDOWS / name, digest)
    windows_drift = []
    for rel, info in wm['files'].items():
        actual = sha(SOURCE / rel)
        d['source_hashes'][rel] = {'recorded_sha256': info['sha256'], 'current_sha256': actual, 'matches_current': actual == info['sha256'], 'historical_evidence_only': actual != info['sha256'], 'source_manifest_ref': 'W_MANIFEST', 'owned_by_packet': info['owned']}
        assert actual == info['sha256'] or not info['owned'], ('Windows-owned source drift', rel)
        if actual != info['sha256']:
            windows_drift.append({'file': rel, 'owned_by_packet': info['owned'], 'tested_packet_sha256': info['sha256'], 'current_sha256': actual, 'qualification': 'Historical exact packet remains verified; later unowned manifest change does not retest this native binary.'})
    win_text = read_text(WINDOWS / 'go-transport-tests.log')
    win_pass = {}
    for line, text in enumerate(win_text.splitlines(), 1):
        match = re.match(r'\s*--- PASS: (\S+) \(([0-9.]+)s\)', text)
        if match:
            win_pass[match[1]] = (line, float(match[2]))
    assert len([t for t in win_pass if '/' not in t]) == 12
    assert '--- FAIL:' not in win_text and '--- SKIP:' not in win_text
    for key, name in WINDOWS_TESTS.items():
        line, elapsed = win_pass[name]
        source, declaration_line = declaration(name, sorted((SOURCE / 'apps/edge/internal/printtransport').glob('*_test.go')))
        rel = str(source.relative_to(SOURCE))
        d['verified_test_records'][key] = {'test_name': name, 'observed_status': 'passed', 'log_ref': 'W_GO_TRANSPORT_TESTS_LOG', 'record_line': line, 'event_elapsed_seconds': elapsed, 'package': 'vynic.local/edge/internal/printtransport', 'source_file': rel, 'source_declaration_line_current': declaration_line, 'source_sha256_at_verified_receipt': wm['files'][rel]['sha256'], 'current_source_matches_verified_receipt': sha(source) == wm['files'][rel]['sha256'], 'execution': 'actual Windows guest; amd64 executable in ARM64 guest; nonphysical helper/process/guard or injected transport only'}
    run = load(WINDOWS / 'run-result.json')
    assert run['status'] == 'PASS' and run['documentsSubmitted'] == 0 and run['printJobsBefore'] == run['printJobsAfter'] == 0
    assert not run['serviceRegistration'] and not run['machineRestarted'] and not run['productStarted']
    d['windows_execution'] = {'review_ref': 'W_REVIEW', 'source_manifest_ref': 'W_MANIFEST', 'exact_source_inputs': 34, 'current_owned_sources_match_tested_packet': True, 'current_unowned_source_drift': windows_drift, 'guest_architecture': 'ARM64', 'binary_architecture': 'amd64 PE0x8664', 'go_top_level_passes': 12, 'go_skips': 0, 'helper_fake_assertions': 254, 'spooler_fake_assertions': 110, 'read_only_channel_assertions': 204, 'documents_submitted': 0, 'spooler_jobs_before_after': [0, 0], 'SCM_service_operations': 0, 'OS_restarts': 0, 'not_qualified': ['native ARM64 runtime', 'SCM service restart', 'OS reboot or power loss', 'service-account printer inventory', 'physical printer output/cut/beep', 'shared RAW fencing']}
    register(d, 'C_EARLIER_CANDIDATE_LOG', ROOT / 'tools/metadata/printcluster-tests-reviewed.jsonl', '503f62975a8b7249aaaf47f2bc5c261da489b5a776643b2c733ea8b3e0bab28f')
    failed_path = OUT / 'cluster-independent-boundaries-authorized.jsonl'
    register(d, 'C_HISTORICAL_PROCESS_RACE_LOG', failed_path, '927cf58d905a4337366ff5174ef969023c4501503db4ade1cc7e8cfb80892d41')
    historical_failed = [(line, r) for line, r in json_events(failed_path) if r.get('Action') == 'fail' and r.get('Test')]
    assert len(historical_failed) == 1
    failed_line, failed_record = historical_failed[0]
    assert failed_record['Test'] == 'TestThreeProcessSIGKILLLeaderAndFourPOSRelayRecovery'
    d['execution_history'] = [{'id': 'C_HISTORICAL_PROCESS_RACE_FAILURE', 'observed_status': 'failed', 'test_name': failed_record['Test'], 'log_ref': 'C_HISTORICAL_PROCESS_RACE_LOG', 'record_line': failed_line, 'elapsed_seconds': failed_record['Elapsed'], 'event_time': failed_record['Time'], 'observed': 'Instrumented process fixture failed: cold restarted leader did not rejoin with retained exact work before its deadline. Fan-in 2/3/4 subtests passed in the same run.', 'race_detector_data_race_reported': 'DATA RACE' in read_text(failed_path), 'source_scope': 'Retained pre-final-source execution; no claim that a later source/run erases this observation.', 'final_disposition': 'See accepted final cluster review/receipt' if args.cluster_review else 'Diagnosis and final source/receipt pending'}]
    register(d, 'C_HISTORICAL_FULL_RACE_LOG', OUT / 'acceptance-go-race-failure.c553f557d3cf.jsonl', 'c553f557d3cf0211e745ff945ee898c219f2ef143cd891bd0aeb74d21be08729')
    register(d, 'C_HISTORICAL_FULL_RACE_STATUS', OUT / 'acceptance-historical-go-final-edge-race-status.f3ae976cc171.json', 'f3ae976cc1715396762e5c4d65593dd7100a1efb516544d268c211290b8dce1e')
    register(d, 'C_HISTORICAL_FULL_RACE_SOURCE', OUT / 'acceptance-historical-go-final-source-snapshot.becbed114597.json', 'becbed114597ac2e6d153fe0c5bbc75bd720a497f43678dd5cb7954e64b76f5f')
    register(d, 'C_HISTORICAL_A43_MANIFEST', OUT / 'acceptance-cluster-manifest.a43c5b81ef7b.json', 'a43c5b81ef7b143123f9a377c0abcfd058f0096bf8bae0f05eca709530c2cd8d')
    for line, r in json_events(OUT / 'acceptance-go-race-failure.c553f557d3cf.jsonl'):
        if r.get('Action') == 'fail' and r.get('Test'):
            assert r['Test'] == 'TestFullRasterChunkingSnapshotRestoreAndBounds'
            d['execution_history'].append({'id': 'C_HISTORICAL_FULL_RACE_RASTER_RESTART_FAILURE', 'observed_status': 'failed', 'test_name': r['Test'], 'log_ref': 'C_HISTORICAL_FULL_RACE_LOG', 'record_line': line, 'event_time': r['Time'], 'elapsed_seconds': r['Elapsed'], 'observed': 'Single-voter 8 MiB snapshot/restart race fixture reported no majority leader elected before its bounded helper deadline.', 'source_manifest_ref': 'C_HISTORICAL_A43_MANIFEST', 'source_snapshot_ref': 'C_HISTORICAL_FULL_RACE_SOURCE', 'final_disposition': 'See superseding source/full-race receipt and independent review' if args.cluster_review else 'Superseding source/full-race/review pending.'})
    cluster_log = Path(args.cluster_log)
    register(d, 'C_LOG', cluster_log)
    events = [(line, r) for line, r in json_events(cluster_log) if r.get('Package') == 'vynic.local/edge/internal/printcluster']
    failures = [r for _, r in events if r.get('Action') == 'fail']
    assert not failures
    passes = {r['Test']: (line, r) for line, r in events if r.get('Action') == 'pass' and r.get('Test')}
    package = [r for _, r in events if r.get('Action') == 'pass' and not r.get('Test')]
    assert len(package) == 1
    accepted = bool(args.cluster_review)
    if accepted:
        review_path = Path(args.cluster_review)
        manifest_path = Path(args.cluster_manifest)
        receipt_path = Path(args.cluster_receipt)
        register(d, 'C_REVIEW', review_path)
        register(d, 'C_MANIFEST', manifest_path)
        register(d, 'C_RECEIPT', receipt_path)
        review = load(review_path)
        receipt = load(receipt_path)
        assert review['verdict'].startswith('PASS')
        assert review.get('sourceManifestSha256', review.get('ownedManifestSha256')) == sha(manifest_path)
        assert receipt['exitCode'] == 0 and Path(receipt['output']).resolve() == cluster_log.resolve()
        assert not receipt['hardwareExecution']
        snapshot_path = Path(receipt['sourceReceipt'])
        if not snapshot_path.is_absolute():
            snapshot_path = receipt_path.parent / snapshot_path
        register(d, 'C_FULL_TEST_SOURCE_SNAPSHOT', snapshot_path)
        snapshot = load(snapshot_path)
        assert snapshot['beforeCopyAfterEqual'] is True
        if 'snapshotManifestSha256' in review:
            assert review['snapshotManifestSha256'] == sha(snapshot_path)
        assert args.cluster_race_receipt, 'Final qualification requires completed full-race receipt'
        race_receipt_path = Path(args.cluster_race_receipt)
        register(d, 'C_FULL_RACE_RECEIPT', race_receipt_path)
        race_receipt = load(race_receipt_path)
        assert race_receipt['exitCode'] == 0 and '-race' in race_receipt['command'] and not race_receipt['hardwareExecution']
        race_snapshot_path = Path(race_receipt['sourceReceipt'])
        if not race_snapshot_path.is_absolute():
            race_snapshot_path = race_receipt_path.parent / race_snapshot_path
        assert sha(race_snapshot_path) == sha(snapshot_path)
        race_log_path = Path(race_receipt['output'])
        register(d, 'C_FULL_RACE_LOG', race_log_path)
        race_events = [(line, r) for line, r in json_events(race_log_path) if r.get('Package') == 'vynic.local/edge/internal/printcluster']
        assert not any(r.get('Action') == 'fail' for _, r in race_events)
        race_package = [r for _, r in race_events if not r.get('Test') and r.get('Action') == 'pass']
        assert len(race_package) == 1
        d['cluster_full_race_execution'] = {'receipt_ref': 'C_FULL_RACE_RECEIPT', 'log_ref': 'C_FULL_RACE_LOG', 'source_snapshot_ref': 'C_FULL_TEST_SOURCE_SNAPSHOT', 'observed_status': 'passed', 'top_level_passes': sum(r.get('Action') == 'pass' and bool(r.get('Test')) and '/' not in r['Test'] for _, r in race_events), 'all_pass_records': sum(r.get('Action') == 'pass' and bool(r.get('Test')) for _, r in race_events), 'package_elapsed_seconds': race_package[0]['Elapsed'], 'fail_records': 0, 'hardware_execution': False}
        manifest = load(manifest_path)
        entries = manifest['files']
        if isinstance(entries, list):
            entries = {e['path']: e for e in entries}
        for rel, info in entries.items():
            digest = info if isinstance(info, str) else info['sha256']
            actual = sha(SOURCE / rel)
            assert digest == actual, ('cluster frozen source drift', rel)
            assert snapshot['files'][rel]['sha256'] == digest
            assert sha(Path(snapshot['snapshot']) / rel) == digest
            d['source_hashes'][rel] = {'recorded_sha256': digest, 'current_sha256': actual, 'matches_current': True, 'historical_evidence_only': False, 'source_manifest_ref': 'C_MANIFEST'}
        independent = []
        for name, evidence in review.get('independentTests', review.get('validation', {})).items():
            key = 'C_INDEPENDENT_' + name.upper().replace('.', '_').replace('-', '_')
            log = ROOT / name if '/' in name else OUT / name
            register(d, key, log, evidence['sha256'])
            observed_events = json_events(log)
            failed_tests = [r['Test'] for _, r in observed_events if r.get('Action') == 'fail' and r.get('Test')]
            assert failed_tests == evidence.get('failTests', [])
            packages = [r for _, r in observed_events if not r.get('Test') and r.get('Action') in ('pass', 'fail')]
            assert packages[-1] == evidence.get('packageResult', evidence.get('lastPackageEvent'))
            independent.append({'log_ref': key, 'package_observed_status': 'passed' if packages[-1]['Action'] == 'pass' else 'failed', 'top_level_passes': evidence.get('topLevelPass', evidence.get('topLevelPassed')), 'failed_tests': failed_tests, 'elapsed_seconds': packages[-1]['Elapsed'], 'historical_pre_final_source': bool(failed_tests)})
        d['cluster_independent_execution_cohorts'] = independent
        if 'testFailureHistory' in review:
            d['execution_history'][0]['final_disposition'] = review['testFailureHistory']['status']
        else:
            d['execution_history'][0]['final_disposition'] = 'Prior failure remains preserved; superseding frozen V2 full normal/race and independent affected normal/race pass. Timing support does not prove a sole cause for every earlier failure.'
            for rel, digest in review.get('failedEvidencePreserved', {}).items():
                register(d, 'C_RETAINED_' + rel.upper().replace('/', '_').replace('.', '_').replace('-', '_'), ROOT / rel, digest)
            d['cluster_test_only_delta_review'] = review['deltaReview']
        integrated_path = ROOT / 'tools/metadata/go-final-integrated-validation.json'
        register(d, 'C_INTEGRATED_VALIDATION', integrated_path)
        integrated = load(integrated_path)
        assert integrated['status'] == 'PASS' and integrated['sourceSnapshotSha256'] == sha(snapshot_path)
        assert integrated['sourceUnchangedAcrossValidation'] is True
        assert integrated['checks']['edge-tests']['outputSha256'] == sha(cluster_log)
        assert integrated['checks']['edge-race']['outputSha256'] == sha(race_log_path)
        for name, check in integrated['checks'].items():
            assert check['status']['exitCode'] == 0
            register(d, 'C_INTEGRATED_' + name.upper().replace('-', '_'), Path(check['status']['output']), check['outputSha256'])
        for key, name in {
            'C_TEMP_ROOT_BOUNDARY': 'TestOnlyTemporaryProofDirectories',
            'C_TWO_VOTER_FAILSAFE': 'TestExplicitTwoVoterFailSafeNeverFallsBack',
            'C_MIXED_JOB_RESTORE_BOUNDARY': 'TestAssignedPlusUnreferencedNullJobRestoreRefused',
        }.items():
            CLUSTER_TESTS[key] = name
    else:
        entries = {}
    for key, name in CLUSTER_TESTS.items():
        line, record = passes[name]
        source, declaration_line = declaration(name, sorted((SOURCE / 'apps/edge/internal/printcluster').glob('*_test.go')))
        rel = str(source.relative_to(SOURCE))
        info = entries.get(rel)
        digest = info if isinstance(info, str) else info['sha256'] if info else None
        d['verified_test_records'][key] = {'test_name': name, 'observed_status': 'passed', 'log_ref': 'C_LOG', 'record_line': line, 'event_elapsed_seconds': record.get('Elapsed'), 'event_time': record.get('Time'), 'package': record.get('Package'), 'source_file': rel, 'source_declaration_line_current': declaration_line, 'source_sha256_at_verified_receipt': digest, 'source_sha256_current_inspection': sha(source), 'current_source_matches_verified_receipt': digest == sha(source) if digest else None, 'frozen_source_review_accepted': accepted, 'execution': 'real durable SQLite/Bolt/Raft over loopback on one macOS host; logical dispatch only; process_test uses separate OS processes; other cluster fixtures use separate node runtimes/stores in one process'}
    d['cluster_execution'] = {'frozen_source_review_accepted': accepted, 'suite_log_ref': 'C_LOG', 'review_ref': 'C_REVIEW' if accepted else None, 'manifest_ref': 'C_MANIFEST' if accepted else None, 'receipt_ref': 'C_RECEIPT' if accepted else None, 'top_level_passes': len([t for t in passes if '/' not in t]), 'all_pass_records': len(passes), 'fail_records': 0, 'package_elapsed_seconds': package[0]['Elapsed'], 'skips': [{'test': r.get('Test'), 'record_line': line, 'reason': 'helper subprocess entrypoint; actual parent scenario executes it in child mode' if r.get('Test') == 'TestRaftProcessFixture' else 'see execution log'} for line, r in events if r.get('Action') == 'skip'], 'transport': 'loopback Raft plus synthetic HTTP fixture relays; no printer transport', 'hosts': 1, 'actual_process_leader_SIGKILL': True, 'actual_process_cold_rejoin': True, 'physical_dispatch_enabled': False, 'production_startup_enabled': False, 'source_seal_note': 'Accepted frozen-source review and execution receipt' if accepted else 'Execution log PASS observed; source still provisional, no whole-cluster qualification'}
    if accepted:
        d['cluster_execution']['source_snapshot_ref'] = 'C_FULL_TEST_SOURCE_SNAPSHOT'
        d['cluster_execution']['exact_owned_files_verified'] = len(entries)
        d['cluster_execution']['full_race_log_ref'] = 'C_FULL_RACE_LOG'
        d['cluster_execution']['integrated_validation_ref'] = 'C_INTEGRATED_VALIDATION'
    if args.prepared_build:
        build_path = Path(args.prepared_build)
        base = build_path.parent
        proof = base.parent
        register(d, 'W_POS_PREPARED_BUILD_RECEIPT', build_path)
        build_receipt = load(build_path)
        assert build_receipt['status'] == 'PASS' and build_receipt['sourceUnchanged'] is True
        assert build_receipt['productStarted'] is False and build_receipt['serviceOperations'] is False
        assert build_receipt['physicalJobs'] == build_receipt['printJobsBefore'] == build_receipt['printJobsAfter'] == 0
        build_stage = proof / 'windows-pos-prepared-stage/stage-receipt.json'
        stage = load(build_stage)
        register(d, 'W_POS_PREPARED_STAGE', build_stage)
        register(d, 'W_POS_PREPARED_MANIFEST', proof / 'windows-pos-prepared-stage/source-manifest.json', stage['sourceManifestSHA256'])
        register(d, 'W_POS_PRODUCT_PREPARATION', proof / 'windows-pos-prepared-stage/product-preparation.json')
        assert stage['sourceZipSHA256'] == build_receipt['sourceZipSHA256']
        manifest = load(proof / 'windows-pos-prepared-stage/source-manifest.json')
        assert len(manifest) == build_receipt['sourceFiles'] == 898
        before_path = base / 'firebase-sdk-sha256-before.json'
        after_path = base / 'firebase-sdk-sha256-after.json'
        register(d, 'W_POS_FIREBASE_BEFORE', before_path)
        register(d, 'W_POS_FIREBASE_AFTER', after_path)
        assert load(before_path) == load(after_path) and len(load(before_path)) == 182
        hashes_path = base / 'built-artifact-sha256.json'
        register(d, 'W_POS_ARTIFACT_MANIFEST', hashes_path)
        hashes = load(hashes_path)
        archive = base / 'native-pos-build.zip'
        register(d, 'W_POS_NATIVE_ARCHIVE', archive, build_receipt['archiveSha256'])
        with zipfile.ZipFile(archive) as z:
            names = z.namelist()
            assert len(names) == len(set(names)) == len(hashes) == 23
            assert set(names) == set(hashes) and 'vynic_pos.exe' in names
            for name in names:
                assert '\\' not in name and not name.startswith('/') and '..' not in name.split('/')
                assert hashlib.sha256(z.read(name)).hexdigest() == hashes[name]
        failed_build = proof / 'windows-pos-result/windows-pos-build.json'
        register(d, 'W_POS_GENERIC_BUILD_FAILURE', failed_build)
        old_build = load(failed_build)
        assert old_build['status'] == 'FAILED'
        d['execution_history'].append({'id': 'W_GENERIC_PRODUCT_BUILD_LOOKUP_FAILURE', 'observed_status': 'failed', 'receipt_ref': 'W_POS_GENERIC_BUILD_FAILURE', 'observed': old_build['failure'], 'scope': 'Initial generic-product build receipt failed while locating the expected POS executable; retained separately from corrected official POS preparation.', 'final_disposition': 'Existing product.prepare(pos) applied in an isolated prepared directory; prepared POS release build/23 archive artifact hashes verify PASS. No product execution or physical print.'})
        d['windows_prepared_product_build'] = {'observed_status': 'passed', 'receipt_ref': 'W_POS_PREPARED_BUILD_RECEIPT', 'prepared_source_manifest_ref': 'W_POS_PREPARED_MANIFEST', 'prepared_source_files': 898, 'source_unchanged_reported': True, 'product_preparation_ref': 'W_POS_PRODUCT_PREPARATION', 'firebase_sdk_files_unchanged': 182, 'artifact_manifest_ref': 'W_POS_ARTIFACT_MANIFEST', 'archive_ref': 'W_POS_NATIVE_ARCHIVE', 'artifact_file_hashes_independently_verified': 23, 'executable': 'vynic_pos.exe', 'executable_sha256': hashes['vynic_pos.exe'], 'portable_forward_slash_zip_entries': True, 'target': build_receipt['target'], 'guest_architecture': build_receipt['guestArchitecture'], 'product_started': False, 'installed': False, 'SCM_operations': 0, 'physical_documents': 0, 'qualification': 'Prepared product release build only; it does not execute a registered service, restart Windows or qualify physical printing.'}
        d['matrix_revision'] = 5
    if args.flutter_review:
        flutter_review_path = Path(args.flutter_review)
        register(d, 'WF_REVIEW', flutter_review_path)
        flutter_review = load(flutter_review_path)
        assert flutter_review['verdict'].startswith('PASS')
        proof = Path(flutter_review['evidenceRoot'])
        for rel, digest in flutter_review['evidenceHashes'].items():
            key = 'WF_' + rel.upper().replace('/', '_').replace('.', '_').replace('-', '_')
            register(d, key, proof / rel, digest)
        tests_path = proof / 'windows-flutter-result/flutter-tests.jsonl'
        test_records = []
        for line, r in json_events(tests_path):
            if isinstance(r, list):
                test_records.extend((line, item) for item in r if isinstance(item, dict))
            else:
                test_records.append((line, r))
        starts = {r['test']['id']: (line, r['test']) for line, r in test_records if r.get('type') == 'testStart'}
        done = [(line, r) for line, r in test_records if r.get('type') == 'testDone' and not r.get('hidden')]
        suites = [r['suite'] for _, r in test_records if r.get('type') == 'suite']
        assert len(done) == 535 and all(r['result'] == 'success' and not r['skipped'] for _, r in done)
        assert len(suites) == 36 and test_records[-1][1]['type'] == 'done' and test_records[-1][1]['success'] is True
        assert not any(r.get('type') == 'error' for _, r in test_records)
        selection = load(proof / 'windows-flutter-tests/flutter-final-test-selection.json')
        assert set(s['path'].split('/apps/operations/')[1] for s in suites) == set(selection)
        analysis_selection = load(proof / 'windows-flutter-tests/flutter-final-analysis-selection.json')
        assert len(analysis_selection) == 59
        wrapper = load(proof / 'windows-flutter-result/windows-flutter-tests.json')
        analysis = load(proof / 'windows-flutter-analysis-result/windows-flutter-analysis.json')
        assert wrapper['status'] == 'FAILED' and wrapper['testExitCode'] == 0 and wrapper['analysisExitCode'] is None
        assert analysis['status'] == 'PASS' and analysis['analysisExitCode'] == 0 and analysis['sourceUnchanged'] is True
        generic_manifest = load(proof / 'windows-pos-stage/source-manifest.json')
        wire = [(line, r, starts[r['testID']][1]) for line, r in done if 'operational_proof_wire_test.dart' in starts[r['testID']][1].get('url', '')]
        assert len(wire) == 19
        actual = [(line, r, test) for line, r, test in wire if test['name'].startswith('actual Dart')]
        assert len(actual) == 1
        line, result, test = actual[0]
        rel = 'apps/operations/test/unit/operational_proof_wire_test.dart'
        digest = generic_manifest[rel]['sha256']
        assert sha(SOURCE / rel) == digest
        d['verified_test_records']['WF_ACTUAL_TLS_LOST_ACK_REOPEN'] = {'test_name': test['name'], 'record_format': 'dart-jsonl', 'test_id': result['testID'], 'observed_status': 'passed', 'log_ref': 'WF_WINDOWS_FLUTTER_RESULT_FLUTTER_TESTS_JSONL', 'record_line': line, 'event_time_ms': result['time'], 'source_file': rel, 'source_declaration_line_current': test['line'], 'source_sha256_at_verified_receipt': digest, 'current_source_matches_verified_receipt': True, 'review_ref': 'WF_REVIEW', 'execution': 'Actual Windows guest Dart/Go mutual-TLS/SQLite fixture test; retained test metadata, synthetic test identity and no physical Sender. Log name keeps its OS-encoded representation.'}
        d['source_hashes'][rel] = {'recorded_sha256': digest, 'current_sha256': sha(SOURCE / rel), 'matches_current': True, 'historical_evidence_only': False, 'source_manifest_ref': 'WF_WINDOWS_POS_STAGE_SOURCE_MANIFEST_JSON'}
        d['windows_flutter_execution'] = {'observed_status': 'passed', 'review_ref': 'WF_REVIEW', 'test_log_ref': 'WF_WINDOWS_FLUTTER_RESULT_FLUTTER_TESTS_JSONL', 'visible_successful_tests': 535, 'actual_suite_count': 36, 'skipped': 0, 'error_events': 0, 'done_success': True, 'machine_elapsed_ms': 115964, 'source_files': 898, 'test_source_manifest_ref': 'WF_WINDOWS_POS_STAGE_SOURCE_MANIFEST_JSON', 'wire_tests': 19, 'actual_TLS_fixture_test_ref': 'WF_ACTUAL_TLS_LOST_ACK_REOPEN', 'Go_fixture_sha256': wrapper['fixtureSHA256'], 'initial_wrapper_receipt_status': 'FAILED', 'initial_wrapper_test_exit_code': 0, 'initial_wrapper_analysis_executed': False, 'wrapper_count_metadata_valid': False, 'analysis_ref': 'WF_WINDOWS_FLUTTER_ANALYSIS_RESULT_WINDOWS_FLUTTER_ANALYSIS_JSON', 'analysis_files': 59, 'analysis_exit_code': 0, 'analysis_source_hashes_unchanged_reported': True, 'physical_documents': 0, 'SCM_operations': 0, 'OS_restarts': 0, 'boundaries': flutter_review['limits']}
        d['execution_history'].append({'id': 'WF_METADATA_GIT_LAUNCH_FAILURE', 'observed_status': 'failed', 'receipt_ref': 'WF_WINDOWS_FLUTTER_RESULT_WINDOWS_FLUTTER_TESTS_JSON', 'observed': wrapper['failure'], 'scope': '535 tests passed before dart.bat/git lookup failure prevented analysis; nested-array wrapper metadata reports1 instead of actual36/59 selections. This is a wrapper/analysis-launch failure, not a test failure.', 'final_disposition': 'Supplemental native dart.exe analysis passes59 explicit selectors; original FAILED wrapper retained.'})
        d['matrix_revision'] = 7
    if accepted:
        d['matrix_revision'] = 8
        d['cohort_scope'] = 'Frozen V2 163-file Go snapshot and 898-file generic/prepared Flutter source packets only. Later software-completion CLI/installer/local-RPC/UI source is outside this matrix.'
    d['global_boundaries'] = [
        'Logical ACCEPTED and transport SUBMITTED are distinct from paper DELIVERED; none of these receipts observes paper delivery.',
        'Actual Raft SIGKILL and cold rejoin use separate OS processes on one macOS host over loopback; they are not loss of a physical computer or a venue-LAN partition.',
        'Windows helper parent-death containment is a real OS-process test, not a registered-service restart or OS reboot.',
        'No physical document, physical printer disappearance/restoration, printer-model cut/beep, SCM installation or Windows OS restart was performed.',
        'VENUE_SHARED Raft has no physical Send capability. The LOCAL/qualified fixed-owner executor and shared logical consensus queue are separate components.',
        'Quorum and lease evidence alone cannot fence a paused old RAW writer, retract spooled/TCP-buffered bytes or authorize unsafe takeover.',
        'UNCERTAIN primary or spent/in-flight beep remains held without automatic replay; new logical admission is not permission to overlap an unresolved physical writer.',
        'No production auth/listener/host startup, durable membership transfer, multi-machine failure acceptance or physical activation is qualified by this matrix.',
    ]
    d['host_receipt_note'] = 'Printhost v2 is bounded unit/race/cross-build evidence. Windows v2 adds actual helper/guard/process and read-only channel runtime evidence, not SCM-service runtime.'
    d['pending_evidence'] = [] if accepted else [{'area': 'printcluster frozen source review', 'needed': 'Owner frozen-source manifest/execution receipt plus final independent source review; passing candidate log alone is insufficient.', 'observed_status': 'not-run'}]
    d['pending_evidence'] += [{'area': 'full physical/multi-host/Windows-service acceptance', 'needed': 'Separate physical printer/model/LAN-machine/power-loss/RAW-fencing and registered SCM service/OS reboot qualification.', 'observed_status': 'not-run'}]
    for case in d['cases']:
        status, refs, observed, limits = CASE_UPDATES[case['number']]
        cluster_refs = [r for r in refs if r.startswith('C_')]
        effective = status if accepted or not cluster_refs or case['number'] in (3, 6, 7, 11, 12) else 'not-run'
        cluster_exact = case['number'] in (1, 3, 5, 6, 10, 11, 12, 13, 14, 15, 16, 17)
        case['acceptance_observed_status'] = 'not-run'
        case['software_counterpart'] = {'observed_status': effective, 'qualification': 'bounded software analogue; full physical case remains unexecuted' if effective == 'passed' else 'exact requested scenario unexecuted or frozen-source qualification pending', 'observed': observed, 'verified_test_refs': refs, 'cluster_integration_observed_status': 'passed' if accepted and cluster_exact else 'not-run', 'cluster_note': 'Frozen-source loopback logical queue proof accepted; physical dispatch always held.' if accepted and cluster_exact else 'Related cluster/software evidence does not execute this exact physical/OS scenario.' if accepted else 'Passing candidate log is provisional until final frozen-source review.', 'review_refs': sorted(set(['C_REVIEW'] if accepted and cluster_refs else []) | set(['W_REVIEW'] if any(r.startswith('W_') for r in refs) else []))}
        case['boundary_limits'] = limits
        if args.prepared_build and case['number'] == 18:
            case['additional_evidence_refs'] = ['W_POS_PREPARED_BUILD_RECEIPT', 'W_POS_ARTIFACT_MANIFEST', 'W_POS_NATIVE_ARCHIVE']
            case['boundary_limits'].append('Prepared vynic_pos.exe release build passes with 23 verified archive artifacts; the executable was not started or installed.')
        if args.flutter_review and case['number'] == 18:
            case.setdefault('additional_evidence_refs', []).extend(['WF_REVIEW', 'WF_WINDOWS_FLUTTER_RESULT_FLUTTER_TESTS_JSONL', 'WF_WINDOWS_FLUTTER_ANALYSIS_RESULT_WINDOWS_FLUTTER_ANALYSIS_JSON'])
            case['software_counterpart']['verified_test_refs'].append('WF_ACTUAL_TLS_LOST_ACK_REOPEN')
            case['boundary_limits'].append('The actual Dart/Go TLS fixture tests retain immutable results on reopen; they do not start or restart an SCM service or the POS product.')
        if case['number'] in (1, 10, 15, 16, 18):
            case['retained_execution_history_refs'] = ['C_HISTORICAL_PROCESS_RACE_FAILURE']
        if case['number'] == 14:
            case['retained_execution_history_refs'] = ['C_HISTORICAL_FULL_RACE_RASTER_RESTART_FAILURE']
        case['physical_acceptance'] = {'observed_status': 'not-run', 'physical_documents': 0, 'paper_DELIVERED_observed': False, 'actual_Windows_OS_restart_observed': False}
    d['status_meanings'] = {'passed': 'Only the explicitly described bounded software evidence passed; this never means physical acceptance.', 'failed': 'An observed test or modeled safety property failed; expected unsafe counterexamples identify intentionally unsafe alternatives, not defects in the held implementation.', 'not-run': 'The stated full scenario or its required frozen-source/physical/service/OS qualification was not executed and accepted.'}
    d['summary'] = {'case_count': 18, 'bounded_software_counterpart_passed': sum(c['software_counterpart']['observed_status'] == 'passed' for c in d['cases']), 'bounded_software_counterpart_not_run': sum(c['software_counterpart']['observed_status'] == 'not-run' for c in d['cases']), 'full_acceptance_passed': 0, 'full_acceptance_failed': 0, 'full_acceptance_not_run': 18, 'expected_unsafe_modeled_property_failures': 2, 'retained_historical_go_test_failures': 2, 'retained_historical_build_or_wrapper_failures': int(bool(args.prepared_build)) + int(bool(args.flutter_review)), 'physical_documents': 0, 'actual_Windows_SCM_service_restart_tests': 0, 'actual_Windows_OS_restart_tests': 0, 'cluster_frozen_source_review_accepted': accepted, 'verified_current_cluster_go_test_fail_events': 0, 'verified_Windows_go_test_fail_events': 0}
    assert [c['number'] for c in d['cases']] == list(range(1, 19))
    for case in d['cases']:
        for key in case['software_counterpart']['verified_test_refs']:
            assert key in d['verified_test_records'], (case['number'], key)
    for key, entry in d['evidence_registry'].items():
        assert sha(path_for(entry)) == entry['sha256'], ('evidence changed while building', key)
    assert sha(prior) == PRIOR_SHA and history.read_bytes() == prior.read_bytes()
    path = OUT / ('acceptance-matrix-final.json' if accepted else 'acceptance-matrix-candidate.v' + str(d['matrix_revision']) + '.json')
    data = (json.dumps(d, indent=2, sort_keys=True) + '\n').encode()
    if path.exists() and path.read_bytes() != data:
        old_sha = sha(path)
        old_data = load(path)
        old = path.with_name(path.stem + '.v' + str(old_data.get('matrix_revision', 'unknown')) + '.' + old_sha[:12] + path.suffix)
        if not old.exists():
            old.write_bytes(path.read_bytes())
        d['previous_draft'] = {'path': 'printer-validation/acceptance-matrix-draft.v3.json', 'sha256': PRIOR_SHA, 'bytes': prior.stat().st_size}
        d['previous_version'] = {'path': str(old.relative_to(ROOT)), 'sha256': old_sha, 'bytes': len(path.read_bytes()), 'original_draft_unchanged': True}
        data = (json.dumps(d, indent=2, sort_keys=True) + '\n').encode()
    path.write_bytes(data)
    print(json.dumps({'path': str(path), 'sha256': sha(path), 'bytes': len(data), 'summary': d['summary'], 'draft_v3_unchanged_sha256': sha(prior)}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--cluster-log', default=str(ROOT / 'tools/metadata/printcluster-tests-reviewed.jsonl'))
    parser.add_argument('--cluster-review')
    parser.add_argument('--cluster-manifest')
    parser.add_argument('--cluster-receipt')
    parser.add_argument('--cluster-race-receipt')
    parser.add_argument('--prepared-build')
    parser.add_argument('--flutter-review')
    build(parser.parse_args())
