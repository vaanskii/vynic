import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/package.dart';

import 'package:vynic/core/database/hive_migration_service.dart';

/// Owns the Hive storage bootstrap and the opened boxes for the POS database.
///
/// Feature repositories under `lib/core/services/db/` read their boxes from
/// here. The `DatabaseService` façade keeps the app-facing API and delegates;
/// screens never import this file directly.
class DatabaseCore {
  DatabaseCore._();

  static const String metaBoxName = 'meta';
  static const String userBoxName = 'users';
  static const String tableBoxName = 'tables';
  static const String orderBoxName = 'orders';
  static const String packageBoxName = 'packages';
  static const String menuBoxName = 'menu';
  static const String settingsBoxName = 'settings';
  static const String salesBoxName = 'sales';
  static const String expenseBoxName = 'expenses';
  static const String auditLogBoxName = 'auditLog';
  static const String errorLogBoxName = 'errorLog';
  static const String reservationBoxName = 'reservations';
  static const String quickOrderBoxName = 'quickOrders';

  static Box<User>? userBox;
  static Box<TableModel>? tableBox;
  static Box<Order>? orderBox;
  static Box<MenuCategoryDB>? menuBox;
  static Box? settingsBox;
  static Box? salesBox;
  static Box? expenseBox;
  static Box? errorLogBox;
  static Box? auditLogBox;
  static Box<Reservation>? reservationBox;
  static Box<QuickOrderDraft>? quickOrderBox;
  static Box<Package>? packageBox;
  static Box? metaBox;

  static late String dataDirectoryPath;
  static int dbVersion = HiveMigrationService.initialVersion;

  /// Resolves the per-machine data directory, initializes Hive, registers
  /// adapters, opens every box, and runs pending schema migrations.
  ///
  /// Seeding of defaults (admin user, tables, menu, settings) stays with the
  /// owning repositories / the façade's `init()`.
  static Future<void> open() async {
    // Resolve an application-owned storage directory. On Windows we avoid the
    // OneDrive-synced Documents folder to prevent lock conflicts.
    final baseDirectory = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();

    final supportRoot = Directory('${baseDirectory.path}/Vpos_Data');

    if (Platform.isWindows) {
      final legacyDocumentsDir = await getApplicationDocumentsDirectory();
      final legacyDirectory = Directory('${legacyDocumentsDir.path}/Vpos_Data');
      if (await legacyDirectory.exists() && !await supportRoot.exists()) {
        try {
          await legacyDirectory.rename(supportRoot.path);
        } catch (_) {
          await supportRoot.create(recursive: true);
          try {
            await _copyDirectory(legacyDirectory, supportRoot);
          } catch (_) {
            // If we cannot copy (e.g., file locks), fall back to an empty dir.
          }
        }
      }
    }

    final hostIdentifier = _sanitizeHostname(Platform.localHostname);
    final dataDirName = hostIdentifier.isEmpty
        ? 'Vpos_Data'
        : 'Vpos_Data_$hostIdentifier';
    final dataDirectory = Directory('${baseDirectory.path}/$dataDirName');

    if (!await dataDirectory.exists()) {
      if (await supportRoot.exists()) {
        try {
          await supportRoot.rename(dataDirectory.path);
        } catch (_) {
          await dataDirectory.create(recursive: true);
          try {
            await _copyDirectory(supportRoot, dataDirectory);
          } catch (_) {
            // If the legacy directory cannot be copied, continue with empty dir.
          }
        }
      } else {
        await dataDirectory.create(recursive: true);
      }
    }

    dataDirectoryPath = dataDirectory.path;

    // Initialize Hive with custom path unique per machine to avoid shared locks
    await Hive.initFlutter(dataDirectoryPath);

    // Register adapters
    Hive.registerAdapter(UserAdapter());
    Hive.registerAdapter(TableModelAdapter());
    Hive.registerAdapter(OrderAdapter());
    Hive.registerAdapter(OrderItemAdapter());
    Hive.registerAdapter(MenuCategoryDBAdapter());
    Hive.registerAdapter(MenuSubcategoryDBAdapter());
    Hive.registerAdapter(MenuItemDBAdapter());
    Hive.registerAdapter(MenuVariantDBAdapter());
    Hive.registerAdapter(ReservationAdapter());
    Hive.registerAdapter(QuickOrderDraftAdapter());
    Hive.registerAdapter(PackageAdapter());
    Hive.registerAdapter(PackageItemAdapter());

    metaBox = await Hive.openBox(metaBoxName);

    // Open boxes
    userBox = await Hive.openBox<User>(userBoxName);
    tableBox = await Hive.openBox<TableModel>(tableBoxName);
    orderBox = await Hive.openBox<Order>(orderBoxName);
    packageBox = await Hive.openBox<Package>(packageBoxName);
    menuBox = await Hive.openBox<MenuCategoryDB>(menuBoxName);
    settingsBox = await Hive.openBox(settingsBoxName);
    salesBox = await Hive.openBox(salesBoxName);
    expenseBox = await Hive.openBox(expenseBoxName);
    auditLogBox = await Hive.openBox(auditLogBoxName);
    errorLogBox = await Hive.openBox(errorLogBoxName);
    reservationBox = await Hive.openBox<Reservation>(reservationBoxName);
    quickOrderBox = await Hive.openBox<QuickOrderDraft>(quickOrderBoxName);

    // Run schema migrations before seeding defaults.
    final migrationContext = HiveMigrationContext(
      metaBox: metaBox!,
      userBox: userBox!,
      tableBox: tableBox!,
      orderBox: orderBox!,
      menuBox: menuBox!,
      settingsBox: settingsBox!,
      salesBox: salesBox!,
      auditLogBox: auditLogBox!,
      reservationBox: reservationBox!,
    );
    dbVersion = await HiveMigrationService.runPendingMigrations(
      migrationContext,
    );
  }

  static String _sanitizeHostname(String rawHostname) {
    final normalized = rawHostname.trim().toLowerCase();
    final replaced = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final collapsed = replaced.replaceAll(RegExp(r'_+'), '_');
    final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'default' : trimmed;
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    await for (final entity in source.list(recursive: false)) {
      final newPath = '${target.path}/${entity.uri.pathSegments.last}';
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }
}
