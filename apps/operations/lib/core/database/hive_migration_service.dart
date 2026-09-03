import 'package:hive/hive.dart';

import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

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
  static const int targetVersion = 6;

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

    if (currentVersion < 3) {
      await migrateV2toV3(context);
      currentVersion = 3;
      await context.metaBox.put(dbVersionKey, currentVersion);
      await context.metaBox.put(
        lastMigrationKey,
        DateTime.now().toIso8601String(),
      );
    }

    if (currentVersion < 4) {
      await migrateV3toV4(context);
      currentVersion = 4;
      await context.metaBox.put(dbVersionKey, currentVersion);
      await context.metaBox.put(
        lastMigrationKey,
        DateTime.now().toIso8601String(),
      );
    }

    if (currentVersion < 5) {
      await migrateV4toV5(context);
      currentVersion = 5;
      await context.metaBox.put(dbVersionKey, currentVersion);
      await context.metaBox.put(
        lastMigrationKey,
        DateTime.now().toIso8601String(),
      );
    }

    if (currentVersion < 6) {
      await migrateV5toV6(context);
      currentVersion = 6;
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
        reservation.statusEnum = ReservationStatus.pending;
        await reservation.save();
      }
    }

    // Add additional box transformation logic here when evolving V1 data.
  }

  /// V4 accompanies the typed `SaleRecord` schema and `Order.closureId`
  /// (docs/VYNIC_ROADMAP.md Task 1). Both new fields are nullable, so no
  /// order/sale data needs restructuring. This migration only materializes
  /// the sales-map default keys (`isCancelled`, `restoredToOrder`,
  /// `isFiscal`) that every read path already assumes
  /// (`SalesRepository._mapSalesRecords` defaults them on read), so the
  /// stored maps and the future typed conversion agree on shape.
  /// Idempotent: records that already carry the keys are left untouched.
  static Future<void> migrateV3toV4(HiveMigrationContext context) async {
    for (final key in context.salesBox.keys) {
      final raw = context.salesBox.get(key);
      if (raw is! Map) continue;
      final needsCancelled = !raw.containsKey('isCancelled');
      final needsRestored = !raw.containsKey('restoredToOrder');
      final needsFiscal = !raw.containsKey('isFiscal');
      if (!needsCancelled && !needsRestored && !needsFiscal) {
        continue;
      }
      final updated = Map<dynamic, dynamic>.from(raw);
      if (needsCancelled) updated['isCancelled'] = false;
      if (needsRestored) updated['restoredToOrder'] = false;
      if (needsFiscal) updated['isFiscal'] = true;
      await context.salesBox.put(key, updated);
    }
  }

  /// Backfills [Reservation.tableRefs] from the legacy encoded int codes in
  /// `tableNumbers`. Idempotent: records that already carry refs are left
  /// untouched.
  static Future<void> migrateV2toV3(HiveMigrationContext context) async {
    for (final reservation in context.reservationBox.values) {
      final existingRefs = reservation.tableRefs;
      if (existingRefs != null && existingRefs.isNotEmpty) {
        continue;
      }
      if (reservation.tableNumbers.isEmpty) {
        continue;
      }
      reservation.tableRefs = [
        for (final code in reservation.tableNumbers)
          ReservationTableAvailability.refFromLegacyCode(code).encode(),
      ];
      await reservation.save();
    }
  }

  /// V5 removes the manual monthly sales setting.
  ///
  /// `monthlyReportManualSalesByMonth` let an operator type an amount that was
  /// added to a month's reported revenue, and the report generator turned that
  /// amount into transaction rows that looked like sales the POS had recorded.
  /// Nothing in the operational data ever backed those rows. The capability is
  /// gone; this deletes what installs still hold so a future reader cannot
  /// resurrect the figure. Idempotent — deleting an absent key is a no-op.
  static Future<void> migrateV4toV5(HiveMigrationContext context) async {
    await context.settingsBox.delete(
      SettingsRepository.removedMonthlyReportManualSalesByMonthSetting,
    );
  }

  /// V6 separates the advance from the discount.
  ///
  /// The POS's advance dialog was the only thing that ever wrote
  /// `Order.discountAmount`, so every stored value is a deposit the guest had
  /// already paid — not a reduction in what the meal was worth. Keeping them
  /// in one field meant a closure could not tell the value of the sale from
  /// the balance left to collect, and every order settled with a deposit was
  /// booked at the balance.
  ///
  /// The amount moves to `advanceAmount`. Totals do not change:
  /// `recalculateTotal` subtracts both fields, so an order that had 50 in one
  /// and now has 50 in the other computes the same balance. Idempotent —
  /// orders already carrying an advance are left alone.
  ///
  /// Closed orders are migrated too. Their `totalAmount` is not recomputed
  /// (it is history), but the split has to be right for anything that reads
  /// them afterwards.
  static Future<void> migrateV5toV6(HiveMigrationContext context) async {
    for (final order in context.orderBox.values) {
      if (order.advanceAmount > 0) continue;
      if (order.discountAmount <= 0) continue;
      order.advanceAmount = order.discountAmount;
      order.discountAmount = 0.0;
      // The collection date was never recorded. The order's own creation
      // date is the closest honest answer, and stating it is better than
      // leaving the receipt undatable.
      order.advanceCollectedOn ??= order.createdAt.toIso8601String().split(
        'T',
      )[0];
      await order.save();
    }
  }
}
