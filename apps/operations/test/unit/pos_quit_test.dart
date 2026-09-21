import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/pos/pos_quit.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';

void main() {
  late PosUpdater updater;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vynic-quit-');
    Hive.init(directory.path);
    DatabaseCore.dbVersion = 9;
    PosQuit.enableWindowsTracking();
    UpdateReadiness.frozen = false;
    UpdateReadiness.failure = null;
    UpdateReadiness.recoveryChecks.clear();
    updater = PosUpdater();
  });
  tearDown(() async {
    updater.dispose();
    await EdgeCommandJournal.close();
    await Hive.close();
    DatabaseCore.orderBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.settingsBox = null;
    UpdateReadiness.enabled = false;
    UpdateReadiness.frozen = false;
    await directory.delete(recursive: true);
  });

  test(
    'clean quit stops clients before flush/close and is idempotent',
    () async {
      final steps = <String>[];
      final stopping = Completer<void>();
      final quit = PosQuit(
        updater: updater,
        stopServices: () async {
          steps.add('stop');
          await stopping.future;
        },
        flushAndClose: () async {
          steps.add('flush/close');
        },
      );
      final first = quit.prepare();
      final second = quit.prepare();
      expect(identical(first, second), isTrue);
      expect(UpdateReadiness.frozen, isTrue);
      await expectLater(
        UpdateReadiness.track('new payment', () async {}),
        throwsStateError,
      );
      stopping.complete();
      expect(await first, isNull);
      expect(await quit.prepare(), isNull);
      expect(steps, ['stop', 'flush/close']);
    },
  );

  test(
    'in-flight payment/close/write and updater transactions refuse quit',
    () async {
      var stopped = false;
      final quit = PosQuit(
        updater: updater,
        stopServices: () async {
          stopped = true;
        },
        flushAndClose: () async {},
      );
      for (final operation in [
        'payment',
        'close',
        'cancel',
        'restore',
        'Hive write',
      ]) {
        final gate = Completer<void>();
        final operationFuture = UpdateReadiness.track(
          operation,
          () => gate.future,
        );
        expect(await quit.prepare(), isNotNull);
        expect(stopped, isFalse);
        expect(UpdateReadiness.frozen, isFalse);
        gate.complete();
        await operationFuture;
      }
      updater.installing = true;
      expect(await quit.prepare(), isNotNull);
      updater.installing = false;
      updater.awaitingDecision = true;
      expect(await quit.prepare(), isNotNull);
      updater.awaitingDecision = false;
      updater.preparingInstall = true;
      expect(await quit.prepare(), isNotNull);
      updater.preparingInstall = false;
      updater.probation = true;
      expect(await quit.prepare(), contains('გაშვების'));
      expect(stopped, isFalse);
      updater.probation = false;
      expect(await quit.prepare(), isNull);
    },
  );

  test(
    'failure retains barrier and retry never returns false success',
    () async {
      var fail = true;
      final quit = PosQuit(
        updater: updater,
        stopServices: () async {},
        flushAndClose: () async {
          if (fail) throw const FileSystemException('flush failed');
        },
      );
      expect(await quit.prepare(), contains('flush failed'));
      expect(quit.completed, isFalse);
      expect(UpdateReadiness.frozen, isTrue);
      fail = false;
      expect(await quit.prepare(), isNull);
      expect(quit.completed, isTrue);
    },
  );

  test(
    'open persisted Orders/Tables and durable outbox survive clean quit',
    () async {
      if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
      if (!Hive.isAdapterRegistered(3))
        Hive.registerAdapter(OrderItemAdapter());
      if (!Hive.isAdapterRegistered(2))
        Hive.registerAdapter(TableModelAdapter());
      DatabaseCore.orderBox = UpdateTrackedBox(
        await Hive.openBox<Order>('orders'),
      );
      DatabaseCore.tableBox = UpdateTrackedBox(
        await Hive.openBox<TableModel>('tables'),
      );
      DatabaseCore.settingsBox = UpdateTrackedBox(
        await Hive.openBox('settings'),
      );
      await EdgeCommandJournal.open();
      final order = Order(
        orderId: 31,
        tableNumbers: ['1'],
        floor: 'first',
        items: [],
        totalAmount: 0,
        createdAt: DateTime(2026),
        createdBy: 'staff',
      );
      await DatabaseCore.orderBox!.put(31, order);
      await DatabaseCore.tableBox!.put(
        'table',
        TableModel(
          floor: 'first',
          tableNumber: '1',
          isReserved: true,
          activeOrderId: 31,
        ),
      );
      await DatabaseCore.settingsBox!.put('pendingCloudSync', true);
      final quit = PosQuit(
        updater: updater,
        stopServices: () async {},
        flushAndClose: () async {
          await PosUpdater.flushLocalState();
          await EdgeCommandJournal.close();
          await Hive.close();
        },
      );
      expect(quit.blockedReason, isNull);
      expect(await quit.prepare(), isNull);
      final orders = await Hive.openBox<Order>('orders');
      final tables = await Hive.openBox<TableModel>('tables');
      final settings = await Hive.openBox('settings');
      expect(orders.get(31)!.orderUuid, order.orderUuid);
      expect(orders.get(31)!.status, order.status);
      expect(tables.get('table')!.activeOrderId, 31);
      expect(tables.get('table')!.isReserved, isTrue);
      expect(settings.get('pendingCloudSync'), isTrue);
    },
  );
}
