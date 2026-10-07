import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/order_edit_repository.dart';
import '../support/pos03_fixture.dart';
import '../unit/mgr05_order_edit_test.dart' show seedMgr05, mgr05Id;

void main() {
  final path = Platform.environment['MGR05_PROCESS_DIRECTORY'];
  final stage = Platform.environment['MGR05_PROCESS_STAGE'];
  if (path == null || stage == null) {
    test(
      'MGR05 owned native process orchestrator required',
      () {},
      skip:
          'python3 tool/prove_mgr05_recovery.py --flutter <SDK> --output <proof.json>',
    );
    return;
  }
  final parent = Directory(path).parent;
  if (!parent.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('vynic_mgr05_process_') ||
      !parent.absolute.path.startsWith(Directory.systemTemp.absolute.path)) {
    throw StateError('Only newly owned synthetic temporary data is accepted');
  }
  test('MGR05 native process $stage', () async {
    final fixture = Pos03Fixture();
    await fixture.open(path);
    if (stage == 'boundaries' || stage == 'writer') {
      await fixture.seed();
      final payload = await seedMgr05(fixture);
      await File(
        '$path/request.json',
      ).writeAsString(jsonEncode(payload), flush: true);
      fixture.trace.clear();
      if (stage == 'writer') {
        final target = int.parse(Platform.environment['MGR05_CHECKPOINT']!);
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
            OrderEditRepository.key(mgr05Id),
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
      await OrderEditRepository.apply(payload);
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
      await OrderEditRepository.recoverPending();
      expect((await OrderEditRepository.apply(payload)).ok, isTrue);
      final order = DatabaseCore.orderBox!.get('source')!;
      expect(order.items.single.quantity, 5);
      final auditBefore = DatabaseCore.auditLogBox!.toMap();
      final original = (await OrderEditRepository.apply(payload)).data;
      order.items.single.comment = 'later occupancy/edit';
      await DatabaseCore.orderBox!.put('source', order);
      expect((await OrderEditRepository.apply(payload)).data, original);
      expect(
        DatabaseCore.orderBox!.get('source')!.items.single.comment,
        'later occupancy/edit',
      );
      expect(DatabaseCore.auditLogBox!.toMap(), auditBefore);
      await File('$path/result.json').writeAsString(
        jsonEncode({
          'status': 'PASS',
          'writerPid': ready['pid'],
          'readerPid': pid,
          'oneOrderEffect': true,
          'oneDurableAudit': true,
          'retainedRetryPreservesLaterEdit': true,
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
