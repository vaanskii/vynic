import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/hive_migration_service.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/user.dart';

// Writes real pre-Phase-2 Hive records, omitting new identity fields.
class LegacyOrderWriter extends TypeAdapter<Order> {
  @override
  int get typeId => 4;
  @override
  Order read(BinaryReader reader) => throw UnimplementedError();
  @override
  void write(BinaryWriter w, Order o) {
    final fields = <int, dynamic>{
      0: o.orderId,
      1: o.tableNumbers,
      2: o.floor,
      3: o.items,
      4: o.totalAmount,
      5: o.createdAt,
      6: o.createdBy,
      7: o.status,
      9: o.includeServiceFee,
    };
    w.writeByte(fields.length);
    fields.forEach((k, v) {
      w.writeByte(k);
      w.write(v);
    });
  }
}

class LegacyLineWriter extends TypeAdapter<OrderItem> {
  @override
  int get typeId => 3;
  @override
  OrderItem read(BinaryReader reader) => throw UnimplementedError();
  @override
  void write(BinaryWriter w, OrderItem o) {
    final fields = <int, dynamic>{
      0: o.itemKey,
      1: o.itemName,
      2: o.unitPrice,
      3: o.quantity,
      4: o.total,
    };
    w.writeByte(fields.length);
    fields.forEach((k, v) {
      w.writeByte(k);
      w.write(v);
    });
  }
}

void main() {
  test(
    'legacy Hive v8 gets restart-stable UUIDs; clones and backups preserve them',
    () async {
      final dir = await Directory.systemTemp.createTemp('vynic-edge-v9-');
      Hive.init(dir.path);
      try {
        Hive.registerAdapter(LegacyOrderWriter());
        Hive.registerAdapter(LegacyLineWriter());
        var orders = await Hive.openBox<Order>('orders');
        await orders.put(
          7,
          Order(
            orderId: 42,
            tableNumbers: ['1'],
            floor: 'first',
            items: [
              OrderItem(
                itemKey: 'Tea',
                itemName: 'Tea',
                unitPrice: 4,
                quantity: 1,
                total: 4,
              ),
            ],
            totalAmount: 4,
            createdAt: DateTime(2026),
            createdBy: 'test',
          ),
        );
        await orders.close();
        Hive.registerAdapter(OrderAdapter(), override: true);
        Hive.registerAdapter(OrderItemAdapter(), override: true);
        Hive.registerAdapter(TableModelAdapter());
        Hive.registerAdapter(MenuCategoryDBAdapter());
        Hive.registerAdapter(ReservationAdapter());
        Hive.registerAdapter(UserAdapter());
        orders = await Hive.openBox<Order>('orders');
        final context = HiveMigrationContext(
          metaBox: await Hive.openBox('meta'),
          userBox: await Hive.openBox<User>('users'),
          tableBox: await Hive.openBox<TableModel>('tables'),
          orderBox: orders,
          menuBox: await Hive.openBox<MenuCategoryDB>('menu'),
          settingsBox: await Hive.openBox('settings'),
          salesBox: await Hive.openBox('sales'),
          auditLogBox: await Hive.openBox('audit'),
          reservationBox: await Hive.openBox<Reservation>('reservations'),
        );
        await context.metaBox.put(HiveMigrationService.dbVersionKey, 8);
        await HiveMigrationService.runPendingMigrations(context);
        final first = orders.get(7)!;
        final id = first.orderUuid;
        final line = first.items.single.lineUuid;
        expect(id, isNotNull);
        expect(line, isNotNull);
        expect(first.orderId, 42);
        expect(first.edgeRevision, 0);
        expect(first.clone().orderUuid, id);
        expect(first.clone().items.single.lineUuid, line);
        final encoded = BackupRepository.serializeOrder(first);
        expect(encoded['orderUuid'], id);
        expect((encoded['items'] as List).single['lineUuid'], line);
        expect(Order.fromJson(first.toJson()).orderUuid, id);
        await HiveMigrationService.runPendingMigrations(context);
        await orders.close();
        orders = await Hive.openBox<Order>('orders');
        expect(orders.get(7)!.orderUuid, id);
        expect(orders.get(7)!.items.single.lineUuid, line);
        expect(context.metaBox.get(HiveMigrationService.dbVersionKey), 9);
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
