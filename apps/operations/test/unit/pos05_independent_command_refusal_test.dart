import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';
import '../support/menu01_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpOverrides? previous;

  setUp(() async {
    previous = HttpOverrides.current;
    HttpOverrides.global = Menu01NoHttp();
    root = await Directory.systemTemp.createTemp(
      'vynic-pos05-command-refusal-',
    );
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

  String ordersImage() => jsonEncode(
    DatabaseCore.orderBox!.toMap().map(
      (key, value) => MapEntry('$key', value.toJson()),
    ),
  );

  String tablesImage() => jsonEncode(
    DatabaseCore.tableBox!.toMap().map(
      (key, value) => MapEntry('$key', value.toJson()..remove('currentBill')),
    ),
  );

  test(
    'remote edit refusal leaves ambiguous Orders and their audits intact',
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
      await closeMenu01();
      await openMenu01(root.path);
      final beforeOrders = ordersImage();
      final beforeTables = tablesImage();
      final beforeAudits = jsonEncode(DatabaseCore.auditLogBox!.toMap());
      Object? outcome;
      try {
        outcome = await PosCommandApplier.updateOrder({
          'posOrderId': first.orderId,
          'updatedBy': 'remote-synthetic',
          'includeServiceFee': false,
          'items': [
            {
              'itemKey': 'item',
              'itemName': 'Synthetic',
              'unitPrice': 12.51,
              'quantity': 2,
              'total': 25.02,
            },
          ],
          'totalAmount': 25.02,
        });
      } catch (error) {
        outcome = error;
      }
      final refused = outcome is! PosCommandOutcome || !outcome.ok;
      await closeMenu01();
      await openMenu01(root.path);
      // ignore: avoid_print
      print(
        'POS05_COMMAND_REFUSAL_OBSERVATION ${jsonEncode({'refused': refused, 'auditUnchanged': jsonEncode(DatabaseCore.auditLogBox!.toMap()) == beforeAudits})}',
      );
      expect(refused, true);
      expect(ordersImage(), beforeOrders);
      expect(tablesImage(), beforeTables);
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), beforeAudits);
      expect(DatabaseCore.salesBox!.isEmpty, true);
    },
  );

  test(
    'direct model terminal status cannot strand the physical Table owner',
    () async {
      final first = await create();
      await closeMenu01();
      await openMenu01(root.path);
      final beforeOrders = ordersImage();
      final beforeTables = tablesImage();
      final beforeAudits = jsonEncode(DatabaseCore.auditLogBox!.toMap());
      final order = OrderRepository.getOrder(first.orderId)!;
      var refused = false;
      try {
        await order.updateStatus('cancelled');
      } catch (_) {
        refused = true;
      }
      await closeMenu01();
      await openMenu01(root.path);
      // ignore: avoid_print
      print(
        'POS05_MODEL_TERMINAL_OBSERVATION ${jsonEncode({'refused': refused, 'status': OrderRepository.getOrder(first.orderId)!.status, 'owner': DatabaseCore.tableBox!.get('first-7')!.activeOrderId})}',
      );
      expect(refused, true);
      expect(ordersImage(), beforeOrders);
      expect(tablesImage(), beforeTables);
      expect(jsonEncode(DatabaseCore.auditLogBox!.toMap()), beforeAudits);
      expect(DatabaseCore.salesBox!.isEmpty, true);
    },
  );
}
