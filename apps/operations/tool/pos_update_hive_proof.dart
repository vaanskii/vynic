// macOS-safe process proof using the production Hive adapters/readiness barrier.
// No Windows artifact is executed, no production data directory is consulted.
import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';

Future<void> main(List<String> args) async {
  final dir = args[0];
  final action = args[1];
  Hive.init(dir);
  Hive.registerAdapter(OrderAdapter());
  Hive.registerAdapter(OrderItemAdapter());
  Hive.registerAdapter(TableModelAdapter());
  final orders = UpdateTrackedBox(await Hive.openBox<Order>('orders'));
  final tables = UpdateTrackedBox(await Hive.openBox<TableModel>('tables'));
  final outbox = UpdateTrackedBox(await Hive.openBox('outbox'));
  UpdateReadiness.enabled = true;
  UpdateReadiness.startupReady = true;
  if (action == 'seed') {
    await orders.put(
      7,
      Order(
        orderId: 7,
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
        createdAt: DateTime.utc(2026, 9, 20),
        createdBy: 'proof',
        status: 'confirmed',
      ),
    );
    await tables.put(
      'd5f31198-e38f-4194-ae2e-c82fcd2868cb',
      TableModel(
        tableNumber: '1',
        floor: 'first',
        isReserved: true,
        activeOrderId: 7,
      ),
    );
    await outbox.put('cloud-pending', {
      'id': 'stable-outbox-id',
      'status': 'pending',
    });
  }
  final readiness = UpdateReadiness.evaluate();
  if (readiness.status != 'READY') throw StateError(readiness.reason!);
  final before = orders.get(7)!;
  final result = {
    'pid': pid,
    'readiness': readiness.status,
    'order': before.toJson(),
    'table': tables.values.single.toJson(),
    'pendingCloud': outbox.get('cloud-pending'),
  };
  final blocked = await UpdateReadiness.freeze(() async {
    await orders.flush();
    await tables.flush();
    await outbox.flush();
  });
  if (blocked != null) throw StateError(blocked);
  stdout.writeln(jsonEncode(result));
  // Intentional abrupt process exit after the same flush barrier used by POS.
  exit(0);
}
