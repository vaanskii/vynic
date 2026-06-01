import 'package:hive/hive.dart';

import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';

class HiveMigrationContext {
  HiveMigrationContext({
    required this.metaBox,
    required this.userBox,
    required this.tableBox,
    required this.orderBox,
    required this.menuBox,
    required this.settingsBox,
    required this.salesBox,
    required this.auditLogBox,
    required this.reservationBox,
  });

  final Box metaBox;
  final Box<User> userBox;
  final Box<TableModel> tableBox;
  final Box<Order> orderBox;
  final Box<MenuCategoryDB> menuBox;
  final Box settingsBox;
  final Box salesBox;
  final Box auditLogBox;
  final Box<Reservation> reservationBox;
}

class HiveMigrationService {
  static const String dbVersionKey = 'db_version';
  static const String lastMigrationKey = 'last_migration_timestamp';
  static const int initialVersion = 1;
  static const int targetVersion = 2;

  static Future<int> readCurrentVersion(Box metaBox) async {
    final stored = metaBox.get(dbVersionKey);
    if (stored is int && stored >= initialVersion) {
      return stored;
    }
    await metaBox.put(dbVersionKey, initialVersion);
    return initialVersion;
  }

  static Future<int> runPendingMigrations(HiveMigrationContext context) async {
    var currentVersion = await readCurrentVersion(context.metaBox);

    if (currentVersion < 2) {
      await migrateV1toV2(context);
      currentVersion = 2;
      await context.metaBox.put(dbVersionKey, currentVersion);
      await context.metaBox.put(
        lastMigrationKey,
        DateTime.now().toIso8601String(),
      );
    }

    return currentVersion;
  }

  static Future<void> migrateV1toV2(HiveMigrationContext context) async {
    // Ensure critical settings keys exist for older installs.
    if (!context.settingsBox.containsKey('serviceFeePercent')) {
      await context.settingsBox.put('serviceFeePercent', 10.0);
    }
    if (!context.settingsBox.containsKey('serviceFeeEnabled')) {
      await context.settingsBox.put('serviceFeeEnabled', true);
    }

    // Normalize existing orders so new calculations behave predictably.
    for (final order in context.orderBox.values) {
      if (order.discountAmount.isNaN || order.discountAmount < 0) {
        order.discountAmount = 0.0;
        await order.save();
      }
      if (order.totalAmount <= 0) {
        order.recalculateTotal();
        await order.save();
      }
    }

    // Guarantee reservations have a valid status string.
    for (final reservation in context.reservationBox.values) {
      if (reservation.status.trim().isEmpty) {
        reservation.status = 'pending';
        await reservation.save();
      }
    }

    // Add additional box transformation logic here when evolving V1 data.
  }
}
