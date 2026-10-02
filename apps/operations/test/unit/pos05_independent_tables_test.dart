import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/table_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/database_service.dart';
import '../support/menu01_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpOverrides? previous;

  setUp(() async {
    previous = HttpOverrides.current;
    HttpOverrides.global = Menu01NoHttp();
    root = await Directory.systemTemp.createTemp('vynic-pos05-tables-');
    await openMenu01(root.path);
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-10-02T00:00:00.000',
    );
    await DatabaseCore.tableBox!.put(
      'first-7',
      TableModel(tableNumber: '7', floor: 'first'),
    );
    Order.serviceFeeRateResolver = () => 0.0;
    AuditRepository.registerAuditChangedCallback(() {});
  });

  tearDown(() async {
    AuditRepository.registerAuditChangedCallback(() {});
    await closeMenu01();
    HttpOverrides.global = previous;
    await root.delete(recursive: true);
  });

  Future<Order> create() => OrderRepository.createOrder(
    tableNumbers: ['7'],
    floor: 'first',
    createdBy: 'synthetic',
    items: [
      OrderItem(
        itemKey: 'item',
        itemName: 'Synthetic',
        unitPrice: 12.51,
        quantity: 1,
        total: 12.51,
      ),
    ],
    includeServiceFee: false,
  );

  String persistentTableSnapshot() => jsonEncode(
    DatabaseCore.tableBox!.toMap().map(
      (key, value) => MapEntry('$key', value.toJson()..remove('currentBill')),
    ),
  );

  test(
    'stale free-table image cannot erase a subsequently committed owner',
    () async {
      final stale = TableRepository.getTable('7', 'first')!;
      final order = await create();
      final beforeAudit = jsonEncode(DatabaseCore.auditLogBox!.toMap());
      stale.free();
      var refused = false;
      try {
        await stale.save();
      } catch (_) {
        refused = true;
      }
      await closeMenu01();
      await openMenu01(root.path);
      final row = DatabaseCore.tableBox!.get('first-7')!;
      final observation = {'refused': refused, 'owner': row.activeOrderId};
      // ignore: avoid_print
      print('POS05_STALE_TABLE_OBSERVATION ${jsonEncode(observation)}');
      expect(refused, true, reason: jsonEncode(observation));
      expect(row.activeOrderId, order.orderId);
      expect(row.isReserved, true);
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), beforeAudit);
      expect(OrderRepository.getOrder(order.orderId)!.status, isNot('closed'));
    },
  );

  test('manual table release cannot detach a live persisted Order', () async {
    final order = await create();
    final beforeAudit = jsonEncode(DatabaseCore.auditLogBox!.toMap());
    var refused = false;
    try {
      await TableRepository.freeTable(tableNumber: '7', floor: 'first');
    } catch (_) {
      refused = true;
    }
    await closeMenu01();
    await openMenu01(root.path);
    final row = DatabaseCore.tableBox!.get('first-7')!;
    final observation = {'refused': refused, 'owner': row.activeOrderId};
    // ignore: avoid_print
    print('POS05_LIVE_TABLE_RELEASE_OBSERVATION ${jsonEncode(observation)}');
    expect(refused, true, reason: jsonEncode(observation));
    expect(row.activeOrderId, order.orderId);
    expect(row.isReserved, true);
    expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), beforeAudit);
  });

  test(
    'duplicate physical table rows refuse lookup and preserve both records',
    () async {
      await DatabaseCore.tableBox!.put(
        'duplicate-first-7',
        TableModel(tableNumber: '7', floor: 'first'),
      );
      final before = jsonEncode(
        DatabaseCore.tableBox!.toMap().map(
          (key, value) => MapEntry('$key', value.toJson()),
        ),
      );
      var refused = false;
      try {
        TableRepository.getTable('7', 'first');
      } catch (_) {
        refused = true;
      }
      // ignore: avoid_print
      print(
        'POS05_DUPLICATE_TABLE_OBSERVATION ${jsonEncode({'refused': refused, 'rows': DatabaseCore.tableBox!.length})}',
      );
      expect(
        refused,
        true,
        reason: 'A first-row winner would hide an inconsistent legacy store',
      );
      expect(DatabaseCore.tableBox!.length, 2);
      expect(
        jsonEncode(
          DatabaseCore.tableBox!.toMap().map(
            (key, value) => MapEntry('$key', value.toJson()),
          ),
        ),
        before,
      );
      expect(AuditRepository.getAuditReports(), isEmpty);
    },
  );
  test(
    'legacy ownership ambiguity remains readable after startup without choosing a winner',
    () async {
      final first = await create();
      await DatabaseCore.orderBox!.put(
        'legacy-second-owner',
        Order(
          orderId: 91,
          tableNumbers: ['7'],
          floor: 'first',
          items: first.items.map((item) => item.clone()).toList(),
          totalAmount: first.totalAmount,
          createdAt: DateTime(2026, 10, 2, 10),
          createdBy: 'legacy-synthetic',
          status: 'confirmed',
          includeServiceFee: false,
        ),
      );
      final beforeOrders = jsonEncode(
        DatabaseCore.orderBox!.toMap().map(
          (key, value) => MapEntry('$key', value.toJson()),
        ),
      );
      final beforeTables = persistentTableSnapshot();
      final beforeAudit = jsonEncode(DatabaseCore.auditLogBox!.toMap());
      await closeMenu01();
      Object? startupError;
      try {
        await DatabaseService.init(
          createBootstrapManager: false,
          managedDataDirectory: root.path,
        );
      } catch (error) {
        startupError = error;
      }
      final issues = OrderTableMutationRepository.integrityReport();
      final readable = OrderRepository.getAllOrders();
      final observation = {
        'startupFailed': startupError != null,
        'startupError': startupError?.toString(),
        'readableOrderIds': readable.map((order) => order.orderId).toList(),
        'issues': issues,
      };
      // ignore: avoid_print
      print('POS05_LEGACY_STARTUP_OBSERVATION ${jsonEncode(observation)}');
      expect(startupError, isNull, reason: jsonEncode(observation));
      expect(readable, hasLength(2));
      expect(issues, isNotEmpty);
      expect(
        jsonEncode(
          DatabaseCore.orderBox!.toMap().map(
            (key, value) => MapEntry('$key', value.toJson()),
          ),
        ),
        beforeOrders,
      );
      expect(persistentTableSnapshot(), beforeTables);
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), beforeAudit);
      await expectLater(create(), throwsA(isA<OrderMutationConflict>()));
      expect(DatabaseCore.orderBox!.length, 2);
    },
  );
}
