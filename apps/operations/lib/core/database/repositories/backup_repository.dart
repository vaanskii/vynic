import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

import 'package:vynic/core/database/hive_migration_service.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import 'business_day_repository.dart';
import '../database_core.dart';
import 'order_repository.dart';
import 'reservation_repository.dart';
import 'table_repository.dart';
import 'settings_repository.dart';
import 'user_repository.dart';

/// JSON backup/restore of every Hive box, plus the serialize/deserialize
/// helpers shared with the POS↔server sync payloads.
class BackupRepository {
  BackupRepository._();

  /// Serializes a reservation in the shape the sync layer sends to the server.
  static Map<String, dynamic> serializeReservationForSync(
    Reservation reservation,
  ) {
    return _serializeReservation(reservation);
  }

  static Future<File> createDataBackup({String? targetFilePath}) async {
    final timestamp = DateTime.now();
    final backupFile = targetFilePath != null
        ? File(targetFilePath)
        : () {
            final backupDirectory = Directory(
              '${DatabaseCore.dataDirectoryPath}/backups',
            );
            if (!backupDirectory.existsSync()) {
              backupDirectory.createSync(recursive: true);
            }
            final formattedTimestamp = timestamp
                .toIso8601String()
                .replaceAll(':', '-')
                .replaceAll('.', '-');
            return File(
              '${backupDirectory.path}/pos_backup_$formattedTimestamp.json',
            );
          }();

    final backupPayload = {
      'generatedAt': timestamp.toIso8601String(),
      'currentDate': BusinessDayRepository.getCurrentDate().toIso8601String(),
      'meta': {
        'db_version':
            DatabaseCore.metaBox?.get(HiveMigrationService.dbVersionKey) ??
            HiveMigrationService.initialVersion,
        'last_migration_timestamp': DatabaseCore.metaBox?.get(
          HiveMigrationService.lastMigrationKey,
        ),
      },
      // Every key in the settings box, not a hand-picked few.
      //
      // This used to list seven settings by name, which silently dropped
      // everything added since — the floor plan (`activeTableLayoutJson`), the
      // printer list, the monthly-report configuration, the destructive-action
      // password, the display settings. A restore looked successful and came
      // back without the table layout.
      'settingsAll': _serializeSettingsBox(),
      // Kept so a backup taken now still restores on a build that only knows
      // the old shape.
      'settings': {
        'serviceFeePercent': SettingsRepository.getServiceFeePercentage(),
        'serviceFeeEnabled': SettingsRepository.isServiceFeeEnabledByDefault(),
        'defaultLanguage': SettingsRepository.getDefaultLanguage(),
        'printerKitchenIp': SettingsRepository.getKitchenPrinterIp(),
        'printerReceiptIp': SettingsRepository.getReceiptPrinterIp(),
        'printerPort': SettingsRepository.getPrinterPort(),
        'knownBusinessDates': BusinessDayRepository.getKnownBusinessDates()
            .map((date) => date.toIso8601String())
            .toList(),
      },
      'users': DatabaseCore.userBox!.values.map(_serializeUser).toList(),
      'tables': DatabaseCore.tableBox!.values.map(_serializeTable).toList(),
      'orders': DatabaseCore.orderBox!.values.map(_serializeOrder).toList(),
      'packages': DatabaseCore.packageBox!.values
          .map(_serializePackage)
          .toList(),
      'reservations': DatabaseCore.reservationBox!.values
          .map(_serializeReservation)
          .toList(),
      'quickOrders': DatabaseCore.quickOrderBox!.values
          .map(_serializeQuickOrderDraft)
          .toList(),
      'menu': DatabaseCore.menuBox!.values.map(_serializeMenuCategory).toList(),
      'sales': DatabaseCore.salesBox!.values.map(_serializeDynamicMap).toList(),
      'expenses': DatabaseCore.expenseBox!.values
          .map(_serializeDynamicMap)
          .toList(),
      'auditLog': DatabaseCore.auditLogBox!.values
          .map(_serializeDynamicMap)
          .toList(),
      'errorLog': DatabaseCore.errorLogBox!.values
          .map(_serializeDynamicMap)
          .toList(),
    };

    await backupFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(backupPayload),
    );
    return backupFile;
  }

  /// The whole settings box as plain JSON.
  ///
  /// Values are Hive primitives (strings, numbers, bools, lists, maps), so
  /// they survive a JSON round trip as they are. Anything that does not is
  /// stringified rather than dropped, because a setting restored as text is
  /// recoverable and a missing one is not.
  static Map<String, dynamic> _serializeSettingsBox() {
    final box = DatabaseCore.settingsBox;
    if (box == null) return const {};
    final out = <String, dynamic>{};
    for (final key in box.keys) {
      final value = box.get(key);
      if (value == null) continue;
      out['$key'] = _jsonSafe(value);
    }
    return out;
  }

  static dynamic _jsonSafe(dynamic value) {
    if (value is String || value is num || value is bool) return value;
    if (value is DateTime) return value.toIso8601String();
    if (value is List) return value.map(_jsonSafe).toList();
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', _jsonSafe(item)));
    }
    return value.toString();
  }

  /// Writes every key from a `settingsAll` block back.
  ///
  /// Returns false when the backup predates the block, so the caller falls
  /// back to the old per-key restore.
  static Future<bool> _restoreSettingsBox(Map<String, dynamic> payload) async {
    final all = payload['settingsAll'];
    if (all is! Map || all.isEmpty) return false;
    final box = DatabaseCore.settingsBox!;
    for (final entry in all.entries) {
      await box.put('${entry.key}', entry.value);
    }
    return true;
  }

  static Map<String, dynamic> _serializeDynamicMap(dynamic value) {
    if (value is Map) {
      return value.map((key, dynamic val) => MapEntry(key.toString(), val));
    }
    return {'value': value};
  }

  static Map<String, dynamic> _serializeUser(User user) {
    return {
      'username': user.username,
      'role': user.role,
      'pinCode': user.pinCode,
    };
  }

  static Map<String, dynamic> _serializeTable(TableModel table) {
    return {
      'tableNumber': table.tableNumber,
      'floor': table.floor,
      'isReserved': table.isReserved,
      'reservedAt': table.reservedAt?.toIso8601String(),
      'reservedBy': table.reservedBy,
      'activeOrderId': table.activeOrderId,
      'reservationId': table.reservationId,
    };
  }

  static Map<String, dynamic> _serializeOrder(Order order) {
    return {
      'orderId': order.orderId,
      'tableNumbers': order.tableNumbers,
      'floor': order.floor,
      'items': order.items.map(_serializeOrderItem).toList(),
      'totalAmount': order.totalAmount,
      'createdAt': order.createdAt.toIso8601String(),
      'createdBy': order.createdBy,
      'status': order.status,
      'updatedAt': order.updatedAt?.toIso8601String(),
      'includeServiceFee': order.includeServiceFee,
      'paymentMethod': order.paymentMethod,
      'closedAt': order.closedAt?.toIso8601String(),
      'discountAmount': order.discountAmount,
      'openedByUserId': order.openedByUserId,
      'closureId': order.closureId,
    };
  }

  static Map<String, dynamic> _serializeOrderItem(OrderItem item) {
    return {
      'itemKey': item.itemKey,
      'itemName': item.itemName,
      'unitPrice': item.unitPrice,
      'quantity': item.quantity,
      'total': item.total,
      'comment': item.comment,
    };
  }

  static Map<String, dynamic> _serializeReservation(Reservation reservation) {
    return {
      'id': reservation.id,
      'customerName': reservation.customerName,
      'customerPhone': reservation.customerPhone,
      'tableNumbers': reservation.tableNumbers,
      if (reservation.tableRefs != null) 'tableRefs': reservation.tableRefs,
      'reservationDate': reservation.reservationDate.toIso8601String(),
      'reservationTime': reservation.reservationTime,
      'numberOfGuests': reservation.numberOfGuests,
      'notes': reservation.notes,
      'createdAt': reservation.createdAt.toIso8601String(),
      'createdBy': reservation.createdBy,
      'status': reservation.status,
      'preOrderItems': reservation.preOrderItems
          ?.map(_serializeOrderItem)
          .toList(),
      'isTakeAway': reservation.isTakeAway,
      'linkedOrderId': reservation.linkedOrderId,
    };
  }

  static Map<String, dynamic> _serializePackage(Package package) {
    return {
      'packageId': package.packageId,
      'name': package.name,
      'description': package.description,
      'items': package.items.map(_serializePackageItem).toList(),
      'pricePerPerson': package.pricePerPerson,
      'isActive': package.isActive,
      'createdAt': package.createdAt.toIso8601String(),
      'createdBy': package.createdBy,
      'servingSize': package.servingSize,
      'allowedTables': package.allowedTables,
    };
  }

  static Map<String, dynamic> _serializePackageItem(PackageItem item) {
    return {
      'itemKey': item.itemKey,
      'itemName': item.itemName,
      'quantity': item.quantity,
      'unitPrice': item.unitPrice,
    };
  }

  static Map<String, dynamic> _serializeQuickOrderDraft(QuickOrderDraft draft) {
    return {
      'id': draft.id,
      'items': draft.items.map(_serializeOrderItem).toList(),
      'subtotal': draft.subtotal,
      'serviceFeeAmount': draft.serviceFeeAmount,
      'total': draft.total,
      'includeServiceFee': draft.includeServiceFee,
      'serviceFeeRate': draft.serviceFeeRate,
      'createdAt': draft.createdAt.toIso8601String(),
      'createdBy': draft.createdBy,
    };
  }

  static Map<String, dynamic> _serializeMenuCategory(MenuCategoryDB category) {
    return {
      'slug': category.slug,
      'translationsEn': category.translationsEn,
      'translationsKa': category.translationsKa,
      'sendToKitchen': category.sendToKitchen,
      'items': category.items?.map(_serializeMenuItem).toList(),
      'subcategories': category.subcategories
          ?.map(_serializeMenuSubcategory)
          .toList(),
    };
  }

  static Map<String, dynamic> _serializeMenuSubcategory(
    MenuSubcategoryDB subcategory,
  ) {
    return {
      'slug': subcategory.slug,
      'translationsEn': subcategory.translationsEn,
      'translationsKa': subcategory.translationsKa,
      'items': subcategory.items.map(_serializeMenuItem).toList(),
    };
  }

  static Map<String, dynamic> _serializeMenuItem(MenuItemDB item) {
    return {
      'translationsEn': item.translationsEn,
      'translationsKa': item.translationsKa,
      'price': item.price,
      'sendToKitchen': item.sendToKitchen,
      'variants': item.variants?.map(_serializeMenuVariant).toList(),
    };
  }

  static Map<String, dynamic> _serializeMenuVariant(MenuVariantDB variant) {
    return {'size': variant.size, 'price': variant.price};
  }

  static List<Map<String, dynamic>> exportMenu() {
    if (DatabaseCore.menuBox == null) {
      return [];
    }
    return DatabaseCore.menuBox!.values.map(_serializeMenuCategory).toList();
  }

  static Future<void> importMenuFromJson(
    List<dynamic> payload, {
    bool clearExisting = false,
    bool silent = false,
  }) async {
    if (DatabaseCore.menuBox == null) {
      return;
    }
    if (clearExisting) {
      await DatabaseCore.menuBox!.clear();
    }
    for (final entry in payload) {
      if (entry is Map<String, dynamic>) {
        final category = _deserializeMenuCategory(entry);
        await DatabaseCore.menuBox!.add(category);
      } else if (entry is Map) {
        final category = _deserializeMenuCategory(
          Map<String, dynamic>.from(entry),
        );
        await DatabaseCore.menuBox!.add(category);
      }
    }
    if (!silent) {
      SyncHub.notify(SyncEvent(type: SyncEventType.menu, action: 'updated'));
    }
  }

  static List<Map<String, dynamic>> exportOrders() {
    if (DatabaseCore.orderBox == null) {
      return [];
    }
    return DatabaseCore.orderBox!.values.map(_serializeOrder).toList();
  }

  static Future<void> replaceOrdersFromJson(List<dynamic> payload) async {
    if (DatabaseCore.orderBox == null) {
      return;
    }
    await DatabaseCore.orderBox!.clear();
    for (final entry in payload) {
      if (entry is Map<String, dynamic>) {
        final order = _deserializeOrder(entry);
        await DatabaseCore.orderBox!.add(order);
      } else if (entry is Map) {
        final order = _deserializeOrder(Map<String, dynamic>.from(entry));
        await DatabaseCore.orderBox!.add(order);
      }
    }
    SyncHub.notify(SyncEvent(type: SyncEventType.orders, action: 'reloaded'));
  }

  static Map<String, dynamic> serializeOrder(Order order) =>
      _serializeOrder(order);

  /// Creates a takeaway order received from the mobile app, with a server-assigned ID.
  /// This bypasses the standard createOrder flow (which auto-assigns IDs and reserves tables)
  /// to allow mobile-originated orders to appear on the POS with a known posOrderId.
  static Future<Order?> createTakeawayOrderFromRemote({
    required int orderId,
    required String customerName,
    required String pickupTime,
    required String waiterName,
    required List<Map<String, dynamic>> items,
  }) async {
    if (DatabaseCore.orderBox == null || DatabaseCore.reservationBox == null) {
      return null;
    }
    // Idempotent — skip if already exists
    final existing = OrderRepository.getOrder(orderId);
    if (existing != null) return existing;

    final now = BusinessDayRepository.getCurrentDateTime();
    final orderItems = items
        .map(
          (it) => OrderItem(
            itemKey: it['itemName'] as String,
            itemName: it['itemName'] as String,
            unitPrice: (it['unitPrice'] as num).toDouble(),
            quantity: (it['quantity'] as num).toInt(),
            total:
                ((it['total'] as num?)?.toDouble()) ??
                (it['unitPrice'] as num).toDouble() *
                    (it['quantity'] as num).toInt(),
          ),
        )
        .toList();

    final order = Order(
      orderId: orderId,
      tableNumbers: ['TA-$orderId'],
      floor: 'takeaway',
      items: orderItems,
      totalAmount: 0,
      createdAt: now,
      createdBy: waiterName,
      status: OrderStatus.confirmed.storageValue,
      includeServiceFee: false,
    );
    order.recalculateTotal();
    await DatabaseCore.orderBox!.add(order);

    // Keep lastOrderId counter in sync so future POS orders don't reuse this ID
    final stored = DatabaseCore.settingsBox?.get('lastOrderId') as int? ?? 0;
    if (orderId > stored) {
      await DatabaseCore.settingsBox?.put('lastOrderId', orderId);
    }

    // Create linked takeaway reservation so POS home screen shows it
    final reservationId = const Uuid().v4();
    final reservation = Reservation(
      id: reservationId,
      customerName: customerName,
      customerPhone: '-',
      tableNumbers: [],
      reservationDate: now,
      reservationTime: pickupTime,
      numberOfGuests: 1,
      createdAt: now,
      createdBy: waiterName,
      status: ReservationStatus.confirmed.storageValue,
      isTakeAway: true,
      linkedOrderId: orderId,
    );
    await DatabaseCore.reservationBox!.add(reservation);

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': orderId},
      ),
    );

    return order;
  }

  static Future<Order> createOrderFromJson(Map<String, dynamic> json) async {
    final tableNumbers = ((json['tableNumbers'] as List?) ?? const [])
        .map((entry) => entry.toString())
        .toList();
    final items = ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => _deserializeOrderItem(item.cast<String, dynamic>()))
        .toList();
    final floor = json['floor'] as String? ?? 'first';
    final createdBy = json['createdBy'] as String? ?? 'Remote';
    final includeServiceFee = json['includeServiceFee'] as bool? ?? false;
    final order = await OrderRepository.createOrder(
      tableNumbers: tableNumbers,
      floor: floor,
      createdBy: createdBy,
      items: items,
      includeServiceFee: includeServiceFee,
    );
    return order;
  }

  static List<Map<String, dynamic>> exportReservations() {
    if (DatabaseCore.reservationBox == null) {
      return [];
    }
    return DatabaseCore.reservationBox!.values
        .map(_serializeReservation)
        .toList();
  }

  static Future<void> replaceReservationsFromJson(List<dynamic> payload) async {
    if (DatabaseCore.reservationBox == null) {
      return;
    }
    await DatabaseCore.reservationBox!.clear();
    for (final entry in payload) {
      if (entry is Map<String, dynamic>) {
        final reservation = _deserializeReservation(entry);
        await DatabaseCore.reservationBox!.add(reservation);
      } else if (entry is Map) {
        final reservation = _deserializeReservation(
          Map<String, dynamic>.from(entry),
        );
        await DatabaseCore.reservationBox!.add(reservation);
      }
    }
    SyncHub.notify(
      SyncEvent(type: SyncEventType.reservations, action: 'reloaded'),
    );
  }

  static Future<String> createReservationFromJson(
    Map<String, dynamic> json,
  ) async {
    final tableNumbers = ((json['tableNumbers'] as List?) ?? const [])
        .map((e) => _coerceToInt(e) ?? 0)
        .where((value) => value > 0)
        .toList();
    final tableRefs = ((json['tableRefs'] as List?) ?? const [])
        .map((e) => TableRef.tryDecode(e.toString()))
        .whereType<TableRef>()
        .toList();
    final reservationDate = _parseRequiredDate(
      json['reservationDate'] as String?,
    );
    final reservationTime = json['reservationTime'] as String? ?? '00:00';
    final numberOfGuests = (json['numberOfGuests'] as num?)?.toInt() ?? 0;
    final createdBy = json['createdBy'] as String? ?? 'Remote';
    final preOrderItems = ((json['preOrderItems'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => _deserializeOrderItem(item.cast<String, dynamic>()))
        .toList();

    return ReservationRepository.createReservation(
      customerName: json['customerName'] as String? ?? 'Remote Guest',
      customerPhone: json['customerPhone'] as String? ?? '-',
      tableNumbers: tableNumbers,
      tableRefs: tableRefs.isNotEmpty ? tableRefs : null,
      reservationDate: reservationDate,
      reservationTime: reservationTime,
      numberOfGuests: numberOfGuests,
      notes: json['notes'] as String?,
      createdBy: createdBy,
      preOrderItems: preOrderItems.isEmpty ? null : preOrderItems,
      isTakeAway: json['isTakeAway'] as bool? ?? false,
      linkedOrderId: (json['linkedOrderId'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'pending',
    );
  }

  static Map<String, dynamic>? getReservationById(String reservationId) {
    try {
      final reservation = DatabaseCore.reservationBox!.values.firstWhere(
        (r) => r.id == reservationId,
      );
      return _serializeReservation(reservation);
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> exportTables() {
    if (DatabaseCore.tableBox == null) {
      return [];
    }
    return DatabaseCore.tableBox!.values.map(_serializeTable).toList();
  }

  static Future<void> replaceTablesFromJson(List<dynamic> payload) async {
    if (DatabaseCore.tableBox == null) {
      return;
    }
    await DatabaseCore.tableBox!.clear();
    for (final entry in payload) {
      if (entry is Map<String, dynamic>) {
        final table = _deserializeTable(entry);
        await DatabaseCore.tableBox!.add(table);
      } else if (entry is Map) {
        final table = _deserializeTable(Map<String, dynamic>.from(entry));
        await DatabaseCore.tableBox!.add(table);
      }
    }
    SyncHub.notify(SyncEvent(type: SyncEventType.tables, action: 'reloaded'));
  }

  static Future<void> updateTableFromJson(Map<String, dynamic> json) async {
    final tableNumber = json['tableNumber']?.toString();
    final floor = json['floor'] as String? ?? 'first';
    final table = TableRepository.getTable(tableNumber ?? '', floor);
    if (table == null) {
      return;
    }
    table.isReserved = json['isReserved'] as bool? ?? table.isReserved;
    table.reservedBy = json['reservedBy'] as String? ?? table.reservedBy;
    table.activeOrderId = (json['activeOrderId'] as num?)?.toInt();
    table.reservedAt =
        _tryParseDate(json['reservedAt'] as String?) ?? table.reservedAt;
    table.reservationId =
        json['reservationId'] as String? ?? table.reservationId;
    await table.save();
    SyncHub.notify(SyncEvent(type: SyncEventType.tables, action: 'updated'));
  }

  static Future<void> restoreDataBackupFromFile(
    File backupFile, {
    bool clearExisting = true,
    bool backupBeforeRestore = true,
  }) async {
    if (!await backupFile.exists()) {
      throw ArgumentError('Backup file not found: ${backupFile.path}');
    }
    final jsonString = await backupFile.readAsString();
    await restoreDataBackupFromJson(
      jsonString,
      clearExisting: clearExisting,
      backupBeforeRestore: backupBeforeRestore,
    );
  }

  static Future<void> restoreDataBackupFromJson(
    String jsonString, {
    bool clearExisting = true,
    bool backupBeforeRestore = true,
  }) async {
    if (backupBeforeRestore) {
      await createDataBackup();
    }

    final dynamic decoded = json.decode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup payload must be a JSON object.');
    }

    final payload = Map<String, dynamic>.from(decoded);
    await _applyBackupPayload(payload, clearExisting: clearExisting);
  }

  /// Erases every box on this terminal and leaves it as if freshly installed.
  ///
  /// Developer-only, and deliberately not reachable from any manager screen.
  /// A safety backup is written first and its path returned, because the one
  /// certainty about a wipe is that somebody will want the data back.
  ///
  /// Settings are cleared too, but the terminal identity and the developer
  /// clock high-water mark survive: a wipe must not become a way to shed an
  /// unlock token's device binding or to rewind expiry checks.
  static Future<String?> wipeAllData({bool backupFirst = true}) async {
    String? safetyBackupPath;
    if (backupFirst) {
      final file = await createDataBackup();
      safetyBackupPath = file.path;
    }

    final settings = DatabaseCore.settingsBox;
    final preservedSettings = <String, dynamic>{
      for (final key in const [
        'developerTerminalId',
        'developerClockHighWater',
      ])
        if (settings?.containsKey(key) ?? false) key: settings!.get(key),
    };

    await Future.wait([
      DatabaseCore.userBox!.clear(),
      DatabaseCore.tableBox!.clear(),
      DatabaseCore.orderBox!.clear(),
      DatabaseCore.packageBox!.clear(),
      DatabaseCore.reservationBox!.clear(),
      DatabaseCore.quickOrderBox!.clear(),
      DatabaseCore.menuBox!.clear(),
      DatabaseCore.salesBox!.clear(),
      DatabaseCore.expenseBox!.clear(),
      DatabaseCore.auditLogBox!.clear(),
      DatabaseCore.errorLogBox!.clear(),
      if (settings != null) settings.clear(),
    ]);

    if (settings != null && preservedSettings.isNotEmpty) {
      await settings.putAll(preservedSettings);
    }

    // Re-seed the minimum a terminal needs to be usable again: first-run
    // defaults and one manager account, matching what `DatabaseService.init`
    // does on a fresh install.
    await SettingsRepository.seedDefaults();
    // Without this the terminal has no account to sign in with and the wipe is
    // indistinguishable from a brick.
    await UserRepository.createDefaultAdmin();

    SyncHub.notify(SyncEvent(type: SyncEventType.tables, action: 'updated'));
    SyncHub.notify(SyncEvent(type: SyncEventType.orders, action: 'updated'));

    return safetyBackupPath;
  }

  static Future<void> _applyBackupPayload(
    Map<String, dynamic> payload, {
    required bool clearExisting,
  }) async {
    final usersJson = (payload['users'] as List?) ?? const [];
    final tablesJson = (payload['tables'] as List?) ?? const [];
    final ordersJson = (payload['orders'] as List?) ?? const [];
    final packagesJson = (payload['packages'] as List?) ?? const [];
    final reservationsJson =
        (payload['reservations'] as List?) ??
        (payload['reservation'] as List?) ??
        const [];
    final quickOrdersJson =
        (payload['quickOrders'] as List?) ??
        (payload['quickOrderDrafts'] as List?) ??
        const [];
    final menuJson = (payload['menu'] as List?) ?? const [];
    final salesJson = (payload['sales'] as List?) ?? const [];
    final expensesJson = (payload['expenses'] as List?) ?? const [];
    final auditLogJson = (payload['auditLog'] as List?) ?? const [];
    final errorLogJson = (payload['errorLog'] as List?) ?? const [];

    if (clearExisting) {
      await Future.wait([
        DatabaseCore.userBox!.clear(),
        DatabaseCore.tableBox!.clear(),
        DatabaseCore.orderBox!.clear(),
        DatabaseCore.packageBox!.clear(),
        DatabaseCore.reservationBox!.clear(),
        DatabaseCore.quickOrderBox!.clear(),
        DatabaseCore.menuBox!.clear(),
        DatabaseCore.salesBox!.clear(),
        DatabaseCore.expenseBox!.clear(),
        DatabaseCore.auditLogBox!.clear(),
        DatabaseCore.errorLogBox!.clear(),
      ]);
    }

    for (final userEntry in usersJson) {
      if (userEntry is Map) {
        final user = _deserializeUser(Map<String, dynamic>.from(userEntry));
        await DatabaseCore.userBox!.add(user);
      }
    }

    for (final tableEntry in tablesJson) {
      if (tableEntry is Map) {
        final table = _deserializeTable(Map<String, dynamic>.from(tableEntry));
        await DatabaseCore.tableBox!.add(table);
      }
    }

    for (final orderEntry in ordersJson) {
      if (orderEntry is Map) {
        final order = _deserializeOrder(Map<String, dynamic>.from(orderEntry));
        await DatabaseCore.orderBox!.add(order);
      }
    }

    for (final packageEntry in packagesJson) {
      if (packageEntry is Map) {
        final package = _deserializePackage(
          Map<String, dynamic>.from(packageEntry),
        );
        await DatabaseCore.packageBox!.put(package.packageId, package);
      }
    }

    for (final reservationEntry in reservationsJson) {
      if (reservationEntry is Map) {
        final reservation = _deserializeReservation(
          Map<String, dynamic>.from(reservationEntry),
        );
        await DatabaseCore.reservationBox!.add(reservation);
      }
    }

    for (final quickOrderEntry in quickOrdersJson) {
      if (quickOrderEntry is Map) {
        final draft = _deserializeQuickOrderDraft(
          Map<String, dynamic>.from(quickOrderEntry),
        );
        await DatabaseCore.quickOrderBox!.put(draft.id, draft);
      }
    }

    for (final categoryEntry in menuJson) {
      if (categoryEntry is Map) {
        final category = _deserializeMenuCategory(
          Map<String, dynamic>.from(categoryEntry),
        );
        await DatabaseCore.menuBox!.add(category);
      }
    }

    for (final saleEntry in salesJson) {
      if (saleEntry is Map) {
        DatabaseCore.salesBox!.add(Map<String, dynamic>.from(saleEntry));
      }
    }

    for (final expenseEntry in expensesJson) {
      if (expenseEntry is Map) {
        DatabaseCore.expenseBox!.add(Map<String, dynamic>.from(expenseEntry));
      }
    }

    for (final auditEntry in auditLogJson) {
      if (auditEntry is Map) {
        DatabaseCore.auditLogBox!.add(Map<String, dynamic>.from(auditEntry));
      }
    }

    for (final errorEntry in errorLogJson) {
      if (errorEntry is Map) {
        DatabaseCore.errorLogBox!.add(Map<String, dynamic>.from(errorEntry));
      }
    }

    final meta = payload['meta'] as Map?;
    final restoredVersion =
        (meta?['db_version'] as int?) ?? HiveMigrationService.targetVersion;
    await DatabaseCore.metaBox!.put(
      HiveMigrationService.dbVersionKey,
      restoredVersion,
    );
    await DatabaseCore.metaBox!.put(
      HiveMigrationService.lastMigrationKey,
      meta?['last_migration_timestamp'] as String? ??
          DateTime.now().toIso8601String(),
    );
    DatabaseCore.dbVersion = restoredVersion;

    final currentDateIso = payload['currentDate'] as String?;
    if (currentDateIso != null && currentDateIso.isNotEmpty) {
      await DatabaseCore.settingsBox!.put('currentDate', currentDateIso);
    }

    // A full settings block supersedes the curated one; the per-key restore
    // below stays for backups taken before it existed.
    final restoredEverySetting = await _restoreSettingsBox(payload);

    final settings = restoredEverySetting ? null : payload['settings'] as Map?;
    if (settings != null) {
      if (settings.containsKey('serviceFeePercent')) {
        final percent = settings['serviceFeePercent'];
        if (percent is num) {
          await DatabaseCore.settingsBox!.put(
            'serviceFeePercent',
            percent.toDouble(),
          );
        }
      }
      if (settings.containsKey('serviceFeeEnabled')) {
        final value = settings['serviceFeeEnabled'];
        if (value is bool) {
          await DatabaseCore.settingsBox!.put('serviceFeeEnabled', value);
        }
      }
      if (settings.containsKey('defaultLanguage')) {
        final value = settings['defaultLanguage'] as String?;
        if (value != null && value.isNotEmpty) {
          await DatabaseCore.settingsBox!.put('defaultLanguage', value);
        }
      }
      if (settings.containsKey('printerKitchenIp')) {
        final value = settings['printerKitchenIp'] as String?;
        if (value != null) {
          await DatabaseCore.settingsBox!.put('printerKitchenIp', value);
        }
      }
      if (settings.containsKey('printerReceiptIp')) {
        final value = settings['printerReceiptIp'] as String?;
        if (value != null) {
          await DatabaseCore.settingsBox!.put('printerReceiptIp', value);
        }
      }
      if (settings.containsKey('printerPort')) {
        final value = settings['printerPort'];
        if (value is num) {
          await DatabaseCore.settingsBox!.put('printerPort', value.toInt());
        }
      }
    }

    if (currentDateIso != null && currentDateIso.isNotEmpty) {
      await BusinessDayRepository.refreshDailySalesTotalForDate(
        DateTime.parse(currentDateIso),
      );
    }

    await TableRepository.ensureCanonicalTableIdentity();
    await TableRepository.ensureTableLayoutConsistency();

    // Force in-app consumers to refresh immediately after restore.
    SyncHub.notify(SyncEvent(type: SyncEventType.menu, action: 'reloaded'));
    SyncHub.notify(SyncEvent(type: SyncEventType.orders, action: 'reloaded'));
    SyncHub.notify(
      SyncEvent(type: SyncEventType.reservations, action: 'reloaded'),
    );
    SyncHub.notify(SyncEvent(type: SyncEventType.tables, action: 'reloaded'));
  }

  static User _deserializeUser(Map<String, dynamic> json) {
    return User(
      username: json['username'] as String? ?? 'unknown',
      pinCode: json['pinCode'] as String? ?? '000000',
      role: json['role'] as String? ?? 'waiter',
    );
  }

  static TableModel _deserializeTable(Map<String, dynamic> json) {
    return TableModel(
      tableNumber: json['tableNumber']?.toString() ?? '0',
      floor: json['floor'] as String? ?? 'first',
      isReserved: json['isReserved'] as bool? ?? false,
      reservedAt: _tryParseDate(json['reservedAt'] as String?),
      reservedBy: json['reservedBy'] as String?,
      activeOrderId: (json['activeOrderId'] as num?)?.toInt(),
      reservationId: json['reservationId'] as String?,
    );
  }

  static Order _deserializeOrder(Map<String, dynamic> json) {
    final items = ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((it) => _deserializeOrderItem(Map<String, dynamic>.from(it)))
        .toList();

    final order = Order(
      orderId: (json['orderId'] as num?)?.toInt() ?? 0,
      tableNumbers: ((json['tableNumbers'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      floor: json['floor'] as String? ?? 'first',
      items: items,
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      createdAt: _parseRequiredDate(json['createdAt'] as String?),
      createdBy: json['createdBy'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'pending',
      updatedAt: _tryParseDate(json['updatedAt'] as String?),
      includeServiceFee: json['includeServiceFee'] as bool? ?? false,
      paymentMethod: json['paymentMethod'] as String?,
      closedAt: _tryParseDate(json['closedAt'] as String?),
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
      openedByUserId: json['openedByUserId'] as String?,
      closureId: json['closureId'] as String?,
    );

    order.recalculateTotal();
    return order;
  }

  static Reservation _deserializeReservation(Map<String, dynamic> json) {
    final preOrders = ((json['preOrderItems'] as List?) ?? const [])
        .whereType<Map>()
        .map((it) => _deserializeOrderItem(Map<String, dynamic>.from(it)))
        .toList();

    final tableNumbers = ((json['tableNumbers'] as List?) ?? const [])
        .map(_coerceToInt)
        .whereType<int>()
        .toList();
    final tableRefs = ((json['tableRefs'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((raw) => TableRef.tryDecode(raw) != null)
        .toList();

    return Reservation(
      id:
          json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      customerName: json['customerName'] as String? ?? 'Unknown',
      customerPhone: json['customerPhone'] as String? ?? '-',
      tableNumbers: tableNumbers,
      // Old backups carry no refs; derive them so restored records are
      // complete regardless of the migration state.
      tableRefs: tableRefs.isNotEmpty
          ? tableRefs
          : [
              for (final code in tableNumbers)
                ReservationTableAvailability.refFromLegacyCode(code).encode(),
            ],
      reservationDate: _parseRequiredDate(json['reservationDate'] as String?),
      reservationTime: json['reservationTime'] as String? ?? '00:00',
      numberOfGuests: (json['numberOfGuests'] as num?)?.toInt() ?? 0,
      notes: json['notes'] as String?,
      createdAt: _parseRequiredDate(json['createdAt'] as String?),
      createdBy: json['createdBy'] as String? ?? 'Unknown',
      status: json['status'] as String? ?? 'pending',
      preOrderItems: preOrders.isEmpty ? null : preOrders,
      isTakeAway: json['isTakeAway'] as bool? ?? false,
      linkedOrderId: (json['linkedOrderId'] as num?)?.toInt(),
    );
  }

  static Package _deserializePackage(Map<String, dynamic> json) {
    final items = ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((it) => _deserializePackageItem(Map<String, dynamic>.from(it)))
        .toList();

    return Package(
      packageId:
          json['packageId']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Package',
      description: json['description'] as String?,
      items: items,
      pricePerPerson: (json['pricePerPerson'] as num?)?.toDouble() ?? 0.0,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: _parseRequiredDate(json['createdAt'] as String?),
      createdBy: json['createdBy'] as String? ?? 'unknown',
      servingSize: (json['servingSize'] as num?)?.toInt() ?? 1,
      allowedTables: ((json['allowedTables'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((value) => value.trim().isNotEmpty)
          .toList(),
    );
  }

  static PackageItem _deserializePackageItem(Map<String, dynamic> json) {
    return PackageItem(
      itemKey: json['itemKey'] as String? ?? '',
      itemName: json['itemName'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static QuickOrderDraft _deserializeQuickOrderDraft(
    Map<String, dynamic> json,
  ) {
    final items = ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((it) => _deserializeOrderItem(Map<String, dynamic>.from(it)))
        .toList();

    return QuickOrderDraft(
      id:
          json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      items: items,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      serviceFeeAmount: (json['serviceFeeAmount'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      includeServiceFee: json['includeServiceFee'] as bool? ?? false,
      serviceFeeRate: (json['serviceFeeRate'] as num?)?.toDouble() ?? 0.0,
      createdAt: _parseRequiredDate(json['createdAt'] as String?),
      createdBy: json['createdBy'] as String? ?? 'unknown',
    );
  }

  static MenuCategoryDB _deserializeMenuCategory(Map<String, dynamic> json) {
    return MenuCategoryDB(
      slug: json['slug'] as String? ?? 'unknown-category',
      translationsEn: _mapToStringMap(json['translationsEn']),
      translationsKa: _mapToStringMap(json['translationsKa']),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((it) => _deserializeMenuItem(Map<String, dynamic>.from(it)))
          .toList(),
      subcategories: ((json['subcategories'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (it) => _deserializeMenuSubcategory(Map<String, dynamic>.from(it)),
          )
          .toList(),
      sendToKitchen: json['sendToKitchen'] as bool? ?? true,
    );
  }

  static MenuSubcategoryDB _deserializeMenuSubcategory(
    Map<String, dynamic> json,
  ) {
    return MenuSubcategoryDB(
      slug: json['slug'] as String? ?? 'unknown-subcategory',
      translationsEn: _mapToStringMap(json['translationsEn']),
      translationsKa: _mapToStringMap(json['translationsKa']),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((it) => _deserializeMenuItem(Map<String, dynamic>.from(it)))
          .toList(),
    );
  }

  static MenuItemDB _deserializeMenuItem(Map<String, dynamic> json) {
    return MenuItemDB(
      translationsEn: _mapToStringMap(json['translationsEn']),
      translationsKa: _mapToStringMap(json['translationsKa']),
      price: (json['price'] as num?)?.toDouble(),
      variants: ((json['variants'] as List?) ?? const [])
          .whereType<Map>()
          .map((it) => _deserializeMenuVariant(Map<String, dynamic>.from(it)))
          .toList(),
      sendToKitchen: json['sendToKitchen'] as bool? ?? true,
    );
  }

  static MenuVariantDB _deserializeMenuVariant(Map<String, dynamic> json) {
    return MenuVariantDB(
      size: (json['size'] as num?)?.toDouble() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
    );
  }

  static OrderItem _deserializeOrderItem(Map<String, dynamic> json) {
    final unitPrice = (json['unitPrice'] as num?)?.toDouble() ?? 0.0;
    final quantity = (json['quantity'] as num?)?.toInt() ?? 0;
    final total = unitPrice * quantity;
    return OrderItem(
      itemKey: json['itemKey'] as String? ?? '',
      itemName: json['itemName'] as String? ?? '',
      unitPrice: unitPrice,
      quantity: quantity,
      total: total,
      comment: json['comment'] as String?,
    );
  }

  static DateTime _parseRequiredDate(String? value) {
    final parsed = _tryParseDate(value);
    return parsed ?? DateTime.now();
  }

  static DateTime? _tryParseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _mapToStringMap(dynamic value) {
    if (value is Map) {
      final result = <String, String>{};
      value.forEach((key, dynamic val) {
        if (key != null) {
          result[key.toString()] = val?.toString() ?? '';
        }
      });
      return result;
    }
    return {};
  }

  static int? _coerceToInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
