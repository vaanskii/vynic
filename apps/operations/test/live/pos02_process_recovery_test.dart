import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import '../support/pos02_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['POS02_PROCESS_DIRECTORY'];
  final stage = Platform.environment['POS02_PROCESS_STAGE'];
  final scenario = Platform.environment['POS02_SCENARIO'];
  if (path == null || stage == null || scenario == null) {
    test(
      'POS02 native proof needs its owned synthetic orchestrator',
      () {},
      skip:
          'python3 tool/prove_pos02_recovery.py --flutter <SDK> --output <proof.json>',
    );
    return;
  }
  final parent = Directory(path).parent;
  if (!parent.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('vynic_pos02_process_') ||
      !parent.absolute.path.startsWith(Directory.systemTemp.absolute.path)) {
    throw StateError(
      'POS02 proof accepts only newly owned disposable temp directories',
    );
  }
  test('POS02 $scenario native process $stage', () async {
    final f = Pos02Fixture();
    await f.open(path, instrument: stage != 'reader');
    if (stage == 'boundaries') {
      await f.prepare(scenario);
      await f.action(scenario);
      await File(
        '$path/boundaries.json',
      ).writeAsString(jsonEncode({'pid': pid, 'trace': f.trace}), flush: true);
    } else if (stage == 'writer') {
      await f.prepare(scenario);
      final target = int.parse(Platform.environment['POS02_CHECKPOINT']!);
      f.fault = (point, position) async {
        if (position != target) return;
        // Make this completed prefix durable without closing/cleaning Hive.
        // Process death is proved; arbitrary storage-controller power loss is not.
        await (DatabaseCore.metaBox! as Pos02Box).inner.flush();
        await (DatabaseCore.orderBox! as Pos02OrderBox).inner.flush();
        await DatabaseCore.settingsBox!.flush();
        await DatabaseCore.auditLogBox!.flush();
        final jobs = PrintJobRepository.all();
        await File('$path/ready.tmp').writeAsString(
          jsonEncode({
            'pid': pid,
            'scenario': scenario,
            'checkpoint': target,
            'point': point,
            'acknowledged': f.acknowledged,
            'jobs': jobs.map((j) => j.toMap()).toList(),
            'writes': f.persistedWriteCount,
            'httpBlocked': true,
            'boxesClosed': false,
          }),
          flush: true,
        );
        await File('$path/ready.tmp').rename('$path/ready.json');
        await Completer<void>().future;
      };
      await f.action(scenario);
      fail(
        'Writer must be killed by its owned orchestrator at the actual boundary',
      );
    } else if (stage == 'reader') {
      final ready =
          jsonDecode(await File('$path/ready.json').readAsString()) as Map;
      PosSession.start(
        DatabaseCore.userBox!.values.singleWhere(
          (u) => u.username == 'synthetic-operator',
        ),
      );
      PrintReconciliation.policy = PrintReconciliationPolicy.administrators;
      f.mode = scenario == 'uncertain' ? 'flush-error' : 'sent';
      final before = PrintJobRepository.all();
      // sending rows must already have become uncertain at DatabaseCore.open.
      expect(before.any((j) => j.state == PrintJobState.sending), false);
      final interrupted = (ready['jobs'] as List).where(
        (j) => j['attempts'].last['state'] == 'sending',
      );
      for (final raw in interrupted) {
        expect(
          PrintJobRepository.read(raw['id'])!.state,
          PrintJobState.uncertain,
        );
      }
      await f.dispatch();
      await f.action(scenario);
      final jobs = PrintJobRepository.all();
      expect(jobs, hasLength(1));
      final job = jobs.single;
      expect(
        job.state,
        isIn([
          PrintJobState.sent,
          PrintJobState.uncertain,
          PrintJobState.confirmed,
        ]),
      );
      final upper = scenario == 'reprint' ? 2 : 1;
      expect(f.persistedWriteCount, lessThanOrEqualTo(upper));
      if (interrupted.isNotEmpty)
        expect(f.persistedWriteCount, ready['writes']);
      final stable = job.toMap();
      final count = f.persistedWriteCount;
      await PrintJobRepository.recover();
      await f.action(scenario);
      await f.dispatch();
      expect(PrintJobRepository.all().single.toMap(), stable);
      expect(f.persistedWriteCount, count);
      expect(pid, isNot(ready['pid']));
      await File('$path/result.json').writeAsString(
        jsonEncode({
          'status': 'PASS',
          'writerPid': ready['pid'],
          'readerPid': pid,
          'state': job.state.name,
          'jobId': job.id,
          'attemptIds': job.attempts.map((a) => a['id']).toList(),
          'writes': count,
          'sendingRecoveredBeforeReplay': true,
          'exactRetryAddedNoWrite': true,
          'noUncertainAutomaticRetry': true,
          'httpBlocked': true,
          'syntheticTransportOnly': true,
        }),
        flush: true,
      );
    } else {
      throw StateError('Unknown native proof stage');
    }
    await f.close();
  });
}
