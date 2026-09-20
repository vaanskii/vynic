import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/closure_journal_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/edge/orders_tables/coordinator.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';
import 'package:vynic_edge_contracts/vynic_edge_contracts.dart';
import 'edge_order_table_coordinator_test.dart' show ScriptedTransport;

void main() {
  late Directory dir;
  setUp(() async {
    UpdateReadiness.enabled = true;
    UpdateReadiness.startupReady = true;
    UpdateReadiness.frozen = false;
    UpdateReadiness.failure = null;
    UpdateReadiness.recoveryChecks.clear();
    dir = await Directory.systemTemp.createTemp('vynic-update-hive-');
    Hive.init(dir.path);
    DatabaseCore.dataDirectoryPath = dir.path;
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
    DatabaseCore.settingsBox = UpdateTrackedBox(await Hive.openBox('settings'));
  });
  tearDown(() async {
    UpdateReadiness.enabled = false;
    UpdateReadiness.frozen = false;
    UpdateReadiness.failure = null;
    UpdateReadiness.recoveryChecks.clear();
    await Hive.close();
    DatabaseCore.settingsBox = null;
    DatabaseCore.closureJournalBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.tableBox = null;
    await dir.delete(recursive: true);
  });
  test(
    'persisted open Order/Table and pending Cloud sync are READY and survive binary restart',
    () async {
      var orders = UpdateTrackedBox(await Hive.openBox<Order>('orders'));
      var tables = UpdateTrackedBox(await Hive.openBox<TableModel>('tables'));
      final order = Order(
        orderId: 31,
        tableNumbers: ['1'],
        floor: 'first',
        items: [
          OrderItem(
            itemKey: 'tea',
            itemName: 'Tea',
            unitPrice: 4,
            quantity: 2,
            total: 8,
          ),
        ],
        totalAmount: 8,
        createdAt: DateTime(2026),
        createdBy: 'staff',
      );
      final table = TableModel(
        tableNumber: '1',
        floor: 'first',
        isReserved: true,
        activeOrderId: 31,
      );
      await orders.put(31, order);
      await tables.put('a5bb22d3-af9d-4e1a-aebb-8d5f7185be56', table);
      await DatabaseCore.settingsBox!.put('pendingCloudSync', true);
      final before = jsonEncode(order.toJson());
      final uuid = order.orderUuid;
      expect(UpdateReadiness.evaluate().status, 'READY');
      expect(
        await UpdateReadiness.freeze(() async {
          await orders.flush();
          await tables.flush();
          await DatabaseCore.settingsBox!.flush();
        }),
        isNull,
      );
      await expectLater(order.save(), throwsStateError);
      await Hive.close();
      UpdateReadiness.frozen = false;
      // Same data path, reopened adapters: both new and rollback binaries use it.
      for (var restart = 0; restart < 2; restart++) {
        orders = UpdateTrackedBox(await Hive.openBox<Order>('orders'));
        tables = UpdateTrackedBox(await Hive.openBox<TableModel>('tables'));
        expect(jsonEncode(orders.get(31)!.toJson()), before);
        expect(orders.get(31)!.orderUuid, uuid);
        expect(
          tables.get('a5bb22d3-af9d-4e1a-aebb-8d5f7185be56')!.activeOrderId,
          31,
        );
        expect(
          tables.get('a5bb22d3-af9d-4e1a-aebb-8d5f7185be56')!.isReserved,
          isTrue,
        );
        expect(UpdateReadiness.evaluate().status, 'READY');
        await orders.close();
        await tables.close();
      }
      final settings = await Hive.openBox('settings');
      expect(settings.get('pendingCloudSync'), isTrue);
    },
  );
  test(
    'active payment/close and local writes block; release restores READY',
    () async {
      for (final operation in [
        'payment',
        'close',
        'cancel',
        'restore',
        'local transaction',
      ]) {
        final c = Completer<void>();
        final task = UpdateReadiness.track(operation, () => c.future);
        expect(UpdateReadiness.evaluate().status, 'BLOCKED');
        var flushed = false;
        expect(
          await UpdateReadiness.freeze(() async {
            flushed = true;
          }),
          isNotNull,
        );
        expect(flushed, isFalse);
        c.complete();
        await task;
        expect(UpdateReadiness.evaluate().status, 'READY');
      }
    },
  );
  test(
    'unresolved existing Edge intent and unready projection block',
    () async {
      final box = await Hive.openBox('projection');
      final client = OrderTableCoordinator(
        box: box,
        transport: ScriptedTransport(),
        auth: AuthenticatedRequest(),
      );
      UpdateReadiness.recoveryChecks.add(OrderTableCoordinator.updateBlocker);
      expect(UpdateReadiness.evaluate().status, 'BLOCKED');
      await client.open();
      expect(UpdateReadiness.evaluate().status, 'READY');
      await client.prepare([]);
      expect(UpdateReadiness.evaluate().status, 'BLOCKED');
      client.ready = false;
      expect(UpdateReadiness.evaluate().status, 'BLOCKED');
      client.ready = true;
      await box.close();
      expect(UpdateReadiness.evaluate().status, 'BLOCKED');
    },
  );
  test(
    'pending closure recovery blocks without counting open entities',
    () async {
      DatabaseCore.closureJournalBox = await Hive.openBox('closures');
      UpdateReadiness.recoveryChecks.add(
        () => ClosureJournalRepository.pending().isNotEmpty ? 'recovery' : null,
      );
      expect(UpdateReadiness.evaluate().status, 'READY');
      await DatabaseCore.closureJournalBox!.put('x', {
        'closureId': 'x',
        'orderId': 31,
        'phase': 'started',
        'startedAt': DateTime(2026).toIso8601String(),
      });
      expect(UpdateReadiness.evaluate().status, 'BLOCKED');
    },
  );
  test('failed flush retains blocked admission; never sends install', () async {
    var sent = 0;
    final u = PosUpdater(
      requestOverride: (route, body) async {
        sent++;
        return {};
      },
      flushOverride: () async {
        throw const FileSystemException('disk full');
      },
    )..configured = true;
    await u.installNow();
    expect(sent, 0);
    expect(UpdateReadiness.frozen, isTrue);
    expect(UpdateReadiness.evaluate().status, 'BLOCKED');
    u.dispose();
  });
  test(
    'Later remains persisted; explicit install retries same request after lost ACK',
    () async {
      final requests = <String>[];
      var flushes = 0;
      final u =
          PosUpdater(
              requestOverride: (route, body) async {
                requests.add(body!['requestId'] as String);
                if (requests.length == 1)
                  throw const SocketException('lost ACK');
                return {'status': 'INSTALLING'};
              },
              flushOverride: () async {
                flushes++;
              },
            )
            ..configured = true
            ..state = {'status': 'READY_TO_INSTALL', 'version': '1.9.0'};
      await u.later();
      expect(DatabaseCore.settingsBox!.get('posUpdateLater'), '1.9.0');
      expect(requests, isEmpty);
      expect(u.status, 'READY_TO_INSTALL');
      await u.installNow();
      expect(UpdateReadiness.frozen, isTrue);
      await u.installNow();
      expect(requests.length, 2);
      expect(requests.toSet().length, 1);
      expect(flushes, 1);
      u.dispose();
    },
  );
  test(
    'restart with an install marker waits for a definitive Go outcome',
    () async {
      await DatabaseCore.settingsBox!.put('posUpdateAttempt', {
        'id': 'pending',
        'version': '1.9.0',
      });
      var remote = 'INSTALLING';
      final updater = PosUpdater(
        requestOverride: (route, body) async => {'status': remote},
        flushOverride: () async {},
      )..awaitingDecision = true;
      await updater.refresh();
      expect(updater.inputHeld, isTrue);
      expect(UpdateReadiness.frozen, isTrue);
      remote = 'ROLLED_BACK';
      await updater.refresh();
      expect(updater.inputHeld, isFalse);
      expect(UpdateReadiness.frozen, isFalse);
      expect(DatabaseCore.settingsBox!.get('posUpdateAttempt'), isNull);
      updater.dispose();
    },
  );
  test(
    'Manager-disabled tracking does not freeze Manager operations',
    () async {
      UpdateReadiness.enabled = false;
      UpdateReadiness.frozen = true;
      var ran = false;
      await UpdateReadiness.track('manager', () async {
        ran = true;
      });
      expect(ran, isTrue);
    },
  );
}
