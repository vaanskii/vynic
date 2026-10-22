import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/table_repair_repository.dart';
import 'package:vynic/core/models/table.dart';
import '../support/pos03_fixture.dart';
import '../unit/mgr02_table_repair_test.dart' show seedMgr02, mgr02RequestId;

void main() {
  final path = Platform.environment['MGR02_PROCESS_DIRECTORY'];
  final stage = Platform.environment['MGR02_PROCESS_STAGE'];
  if (path == null || stage == null) {
    test(
      'MGR02 owned native process orchestrator required',
      () {},
      skip:
          'python3 tool/prove_mgr02_recovery.py --flutter <SDK> --output <proof.json>',
    );
    return;
  }
  final parent = Directory(path).parent;
  if (!parent.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('vynic_mgr02_process_') ||
      !parent.absolute.path.startsWith(Directory.systemTemp.absolute.path)) {
    throw StateError('Only newly owned synthetic temporary data is accepted');
  }
  test('MGR02 native process $stage', () async {
    final fixture = Pos03Fixture();
    await fixture.open(path);
    if (stage == 'boundaries' || stage == 'writer') {
      await fixture.seed();
      final payload = await seedMgr02();
      await File(
        '$path/request.json',
      ).writeAsString(jsonEncode(payload), flush: true);
      fixture.trace.clear();
      if (stage == 'writer') {
        final target = int.parse(Platform.environment['MGR02_CHECKPOINT']!);
        fixture.fault = (point, position) async {
          if (position != target) return;
          for (final box in [
            DatabaseCore.metaBox!,
            DatabaseCore.tableBox!,
            DatabaseCore.orderBox!,
            DatabaseCore.reservationBox!,
            DatabaseCore.auditLogBox!,
          ]) {
            await (box as Pos03Box).inner.flush();
          }
          final raw = DatabaseCore.metaBox!.get(
            TableRepairRepository.key(mgr02RequestId),
          );
          await File('$path/ready.tmp').writeAsString(
            jsonEncode({
              'pid': pid,
              'checkpoint': target,
              'point': point,
              'phase': raw is Map ? raw['phase'] : null,
              'httpBlocked': true,
              'boxesClosed': false,
            }),
            flush: true,
          );
          await File('$path/ready.tmp').rename('$path/ready.json');
          await Completer<void>().future;
        };
      }
      await TableRepairRepository.repair(payload);
      if (stage == 'writer')
        fail('Owned orchestrator must SIGKILL this writer');
      await File('$path/boundaries.json').writeAsString(
        jsonEncode({'pid': pid, 'trace': fixture.trace}),
        flush: true,
      );
    } else if (stage == 'reader') {
      final ready =
          jsonDecode(await File('$path/ready.json').readAsString()) as Map;
      final payload = Map<String, dynamic>.from(
        jsonDecode(await File('$path/request.json').readAsString()),
      );
      await TableRepairRepository.recoverPending();
      expect((await TableRepairRepository.repair(payload)).ok, isTrue);
      final key = DatabaseCore.tableBox!
          .toMap()
          .entries
          .singleWhere(
            (e) => e.value.floor == 'first' && e.value.tableNumber == '7',
          )
          .key;
      expect(DatabaseCore.tableBox!.get(key)!.isReserved, isFalse);
      expect(DatabaseCore.tableBox!.get(key)!.activeOrderId, isNull);
      expect(DatabaseCore.auditLogBox!.length, 1);
      await TableRepairRepository.recoverPending();
      await DatabaseCore.tableBox!.put(
        key,
        TableModel(
          floor: 'first',
          tableNumber: '7',
          isReserved: true,
          activeOrderId: 222,
        ),
      );
      expect((await TableRepairRepository.repair(payload)).ok, isTrue);
      expect(DatabaseCore.tableBox!.get(key)!.activeOrderId, 222);
      expect(DatabaseCore.auditLogBox!.length, 1);
      expect(pid, isNot(ready['pid']));
      await File('$path/result.json').writeAsString(
        jsonEncode({
          'status': 'PASS',
          'writerPid': ready['pid'],
          'readerPid': pid,
          'oneTableEffect': true,
          'oneDurableAudit': true,
          'retainedRetryPreservesLaterOccupancy': true,
          'httpBlocked': true,
        }),
        flush: true,
      );
    } else {
      throw StateError('Unknown stage');
    }
    await fixture.close();
  });
}
