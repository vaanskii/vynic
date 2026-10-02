import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/close_day_journal_repository.dart';
import 'package:vynic/core/database/transactions/close_day_transaction.dart';
import '../support/pos01_fixture.dart';

void main() {
  final path = Platform.environment['POS01_PROCESS_DIRECTORY'];
  final stage = Platform.environment['POS01_PROCESS_STAGE'];
  if (path == null || stage == null) {
    test(
      'POS01 process proof requires its isolated orchestrator',
      () {},
      skip:
          'run python3 tool/prove_pos01_recovery.py --flutter <SDK> --output <proof.json>',
    );
    return;
  }
  if (!path.startsWith('/private/tmp/vynic_pos01_process_')) {
    throw StateError('POS01 proof only accepts owned disposable data');
  }
  test('POS01 native process $stage', () async {
    final fixture = Pos01Fixture();
    HttpOverrides.global = Menu01NoHttp();
    if (stage == 'boundaries') {
      await fixture.open(path);
      await fixture.seed();
      expect(
        await CloseDayTransaction.run(actorId: 'synthetic-operator'),
        true,
      );
      fixture.verify();
      await File('$path/boundaries.json').writeAsString(
        jsonEncode({'pid': pid, 'trace': fixture.trace}),
        flush: true,
      );
      await fixture.close();
    } else if (stage == 'writer') {
      await fixture.open(path);
      await fixture.seed();
      final target = int.parse(Platform.environment['POS01_CHECKPOINT']!);
      fixture.fault = (point, position) async {
        if (position != target) return;
        // Force every completed Hive write to disk before signaling the
        // external killer. This is an actual live process, no box close runs.
        for (final box in [
          DatabaseCore.metaBox!,
          DatabaseCore.settingsBox!,
          DatabaseCore.orderBox!,
          DatabaseCore.tableBox!,
          DatabaseCore.reservationBox!,
          DatabaseCore.auditLogBox!,
        ]) {
          await (box as Pos01Box).inner.flush();
        }
        final intent = CloseDayJournalRepository.read();
        await File('$path/ready.tmp').writeAsString(
          jsonEncode({
            'pid': pid,
            'checkpoint': target,
            'point': point,
            'transitionId': intent?.id,
            'phase': intent?.phase.name,
            'currentDate': DatabaseCore.settingsBox!.get('currentDate'),
            'httpBlocked': true,
            'boxesClosed': false,
          }),
          flush: true,
        );
        await File('$path/ready.tmp').rename('$path/ready.json');
        await Completer<void>().future;
      };
      await CloseDayTransaction.run(actorId: 'synthetic-operator');
      fail(
        'Writer must be SIGKILLed by its orchestrator at the selected boundary',
      );
    } else if (stage == 'reader') {
      final ready =
          jsonDecode(await File('$path/ready.json').readAsString()) as Map;
      // Real DatabaseCore.open owns recovery before migrations/Menu/defaults.
      await fixture.open(path, instrument: false);
      if (ready['transitionId'] == null) {
        expect(
          await CloseDayTransaction.run(actorId: 'synthetic-operator'),
          true,
        );
      }
      final result = fixture.verify(
        transitionId: ready['transitionId'] as String?,
      );
      final before = jsonEncode(DatabaseCore.auditLogBox!.toMap());
      await CloseDayTransaction.recoverPending();
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), before);
      expect(
        await CloseDayTransaction.run(expectedBusinessDate: '2026-10-01'),
        false,
      );
      fixture.verify(transitionId: ready['transitionId'] as String?);
      expect(pid, isNot(ready['pid']));
      await File('$path/result.json').writeAsString(
        jsonEncode({
          ...result,
          'writerPid': ready['pid'],
          'readerPid': pid,
          'startupReplayBeforeMenuMigrations': true,
          'secondReplayChangedNothing': true,
          'staleCloseRejected': true,
        }),
        flush: true,
      );
      await fixture.close();
    } else {
      throw StateError('Unknown POS01 proof stage');
    }
  });
}
