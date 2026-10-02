import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import '../support/pos05_fixture.dart';

void main() {
  final path = Platform.environment['POS05_PROCESS_DIRECTORY'];
  final stage = Platform.environment['POS05_PROCESS_STAGE'];
  final scenario = Platform.environment['POS05_SCENARIO'];
  if (path == null || stage == null || scenario == null) {
    test(
      'POS05 native proof needs its owned synthetic orchestrator',
      () {},
      skip:
          'python3 tool/prove_pos05_recovery.py --flutter <SDK> --output <proof.json>',
    );
    return;
  }
  final parent = Directory(path).parent;
  if (!parent.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('vynic_pos05_process_') ||
      !parent.absolute.path.startsWith(Directory.systemTemp.absolute.path)) {
    throw StateError(
      'POS05 proof accepts only newly owned disposable temp directories',
    );
  }
  test('POS05 $scenario native process $stage', () async {
    final fixture = Pos05Fixture()..scenario = scenario;
    HttpOverrides.global = Menu01NoHttp();
    if (stage == 'boundaries') {
      await fixture.open(path);
      await fixture.prepare(scenario);
      await fixture.action();
      fixture.check();
      await File('$path/boundaries.json').writeAsString(
        jsonEncode({'pid': pid, 'trace': fixture.trace}),
        flush: true,
      );
      await fixture.close();
    } else if (stage == 'writer') {
      await fixture.open(path);
      await fixture.prepare(scenario);
      await File(
        '$path/original.json',
      ).writeAsString(jsonEncode(fixture.original), flush: true);
      final target = int.parse(Platform.environment['POS05_CHECKPOINT']!);
      fixture.fault = (point, position) async {
        if (position != target) return;
        // Flush the durable prefix without closing boxes or invoking cleanup.
        for (final box in [
          DatabaseCore.metaBox!,
          DatabaseCore.settingsBox!,
          DatabaseCore.orderBox!,
          DatabaseCore.tableBox!,
          DatabaseCore.reservationBox!,
          DatabaseCore.salesBox!,
          DatabaseCore.auditLogBox!,
        ]) {
          await (box as Pos05Box).inner.flush();
        }
        final intent = OrderTableMutationRepository.read(fixture.id);
        await File('$path/ready.tmp').writeAsString(
          jsonEncode({
            'pid': pid,
            'scenario': scenario,
            'checkpoint': target,
            'point': point,
            'requestId': intent?.id,
            'requestedId': fixture.id,
            'phase': intent?.body['phase'],
            'nextEffect': intent?.next,
            'orderUuid': intent?.outcome['orderUuid'],
            'httpBlocked': true,
            'boxesClosed': false,
          }),
          flush: true,
        );
        await File('$path/ready.tmp').rename('$path/ready.json');
        await Completer<void>().future;
      };
      await fixture.action();
      fail(
        'Writer must be terminated by its orchestrator at this actual I/O boundary',
      );
    } else if (stage == 'reader') {
      final ready =
          jsonDecode(await File('$path/ready.json').readAsString()) as Map;
      await fixture.open(path, instrument: false);
      fixture.original =
          (jsonDecode(await File('$path/original.json').readAsString()) as Map?)
              ?.cast<String, dynamic>();
      if (ready['requestId'] == null) await fixture.action();
      final result = fixture.check();
      if (ready['orderUuid'] != null)
        expect(result['orderUuid'], ready['orderUuid']);
      final before = fixture.persisted();
      await OrderTableMutationRepository.recoverPending();
      await fixture.action();
      fixture.check();
      expect(fixture.persisted(), before);
      expect(pid, isNot(ready['pid']));
      await File('$path/result.json').writeAsString(
        jsonEncode({
          ...result,
          'writerPid': ready['pid'],
          'readerPid': pid,
          'startupReplayBeforeMenuMigrations': true,
          'secondReplayChangedNothing': true,
          'exactCallerRetryChangedNothing': true,
          'httpBlocked': true,
        }),
        flush: true,
      );
      await fixture.close();
    } else {
      throw StateError('Unknown POS05 proof stage');
    }
  });
}
