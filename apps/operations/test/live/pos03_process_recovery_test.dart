import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/services/pos/order_item_transfer.dart';
import '../support/pos03_fixture.dart';

void main() {
  final path = Platform.environment['POS03_PROCESS_DIRECTORY'];
  final stage = Platform.environment['POS03_PROCESS_STAGE'];
  if (path == null || stage == null) {
    test(
      'POS03 native proof requires its isolated orchestrator',
      () {},
      skip:
          'python3 tool/prove_pos03_recovery.py --flutter <SDK> --output <proof.json>',
    );
    return;
  }
  if (!path.startsWith('/private/tmp/vynic_pos03_process_')) {
    throw StateError(
      'POS03 proof accepts only owned disposable synthetic data',
    );
  }
  test('POS03 native process $stage', () async {
    final fixture = Pos03Fixture();
    HttpOverrides.global = Menu01NoHttp();
    if (stage == 'boundaries') {
      await fixture.open(path);
      await fixture.seed();
      expect((await fixture.apply()).ok, true);
      fixture.verify();
      await File('$path/boundaries.json').writeAsString(
        jsonEncode({'pid': pid, 'trace': fixture.trace}),
        flush: true,
      );
      await fixture.close();
    } else if (stage == 'writer') {
      await fixture.open(path);
      await fixture.seed();
      await File('$path/original.json').writeAsString(
        jsonEncode({
          'source': OrderTransferIntent.snapshot(fixture.originalSource!),
          'destination': OrderTransferIntent.snapshot(
            fixture.originalDestination!,
          ),
        }),
        flush: true,
      );
      final target = int.parse(Platform.environment['POS03_CHECKPOINT']!);
      fixture.fault = (point, position) async {
        if (position != target) return;
        // Flush the native stores, without closing any box or running cleanup.
        for (final box in [
          DatabaseCore.metaBox!,
          DatabaseCore.orderBox!,
          DatabaseCore.tableBox!,
          DatabaseCore.reservationBox!,
          DatabaseCore.auditLogBox!,
        ]) {
          await (box as Pos03Box).inner.flush();
        }
        final intent = OrderTransferJournalRepository.read(pos03Id);
        await File('$path/ready.tmp').writeAsString(
          jsonEncode({
            'pid': pid,
            'checkpoint': target,
            'point': point,
            'transferId': intent?.id,
            'requestedTransferId': pos03Id,
            'phase': intent?.data['phase'],
            'nextEffect': intent?.nextEffect,
            'httpBlocked': true,
            'boxesClosed': false,
            'sourceQuantity': DatabaseCore.orderBox!
                .get('source')!
                .items
                .fold(0, (int n, item) => n + item.quantity),
            'destinationQuantity': DatabaseCore.orderBox!
                .get('destination')!
                .items
                .fold(0, (int n, item) => n + item.quantity),
          }),
          flush: true,
        );
        await File('$path/ready.tmp').rename('$path/ready.json');
        await Completer<void>().future;
      };
      await fixture.apply();
      fail(
        'Writer must be SIGKILLed by its orchestrator at the selected boundary',
      );
    } else if (stage == 'reader') {
      final ready =
          jsonDecode(await File('$path/ready.json').readAsString()) as Map;
      await fixture.open(path, instrument: false);
      final original =
          jsonDecode(await File('$path/original.json').readAsString()) as Map;
      fixture.originalSource = OrderTransferIntent.orderImage(
        original['source'],
      );
      fixture.originalDestination = OrderTransferIntent.orderImage(
        original['destination'],
      );
      if (ready['transferId'] == null) expect((await fixture.apply()).ok, true);
      final result = fixture.verify();
      final before = jsonEncode(DatabaseCore.auditLogBox!.toMap());
      await OrderItemTransfer.recoverPending();
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), before);
      expect((await fixture.apply()).ok, true);
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), before);
      fixture.verify();
      expect(pid, isNot(ready['pid']));
      await File('$path/result.json').writeAsString(
        jsonEncode({
          ...result,
          'writerPid': ready['pid'],
          'readerPid': pid,
          'startupReplayBeforeMenuMigrations': true,
          'secondReplayChangedNothing': true,
          'exactCallerRetryChangedNothing': true,
        }),
        flush: true,
      );
      await fixture.close();
    } else {
      throw StateError('Unknown POS03 proof stage');
    }
  });
}
