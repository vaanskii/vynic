import 'package:vynic/core/database/repositories/order_edit_repository.dart';
import 'table_repair_repository.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/pos/closure_recovery_service.dart';
import 'package:vynic/core/services/sync/sale_ledger_sync_state.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/orders_tables/shadow.dart';
import 'package:vynic/core/services/sync/audit_sync_state.dart';
import 'package:vynic/core/services/sync/staff_credential_sync_state.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';

import 'package:vynic/core/database/hive_migration_service.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/menu/pos_menu_sync_service.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import 'business_day_repository.dart';
import 'closure_journal_repository.dart';
import 'close_day_journal_repository.dart';
import 'order_transfer_journal_repository.dart';
import 'order_table_mutation_repository.dart';
import 'package:vynic/core/services/pos/order_item_transfer.dart';
import '../transactions/close_day_transaction.dart';
import '../database_core.dart';
import 'menu_repository.dart';
import 'order_repository.dart';
import 'reservation_repository.dart';
import 'table_repository.dart';
import 'settings_repository.dart';
import 'user_repository.dart';

/// Versioned restaurant backup/restore, plus the serialize/deserialize
/// helpers shared with the POS↔server sync payloads.
class BackupRepository {
  BackupRepository._();

  /// Serializes a reservation in the shape the sync layer sends to the server.
  static Map<String, dynamic> serializeReservationForSync(
    Reservation reservation,
  ) {
    return _serializeReservation(reservation);
  }

  static const restoreMarkerName = 'pos_restore_pending.json';
  static Map<String, num> lastBackupMetrics = {};
  static Map<String, num> lastRestoreMetrics = {};

  static Future<File> createDataBackup({
    String? targetFilePath,
    String? password,
  }) async {
    final total = Stopwatch()..start();
    if (OrderTableShadow.observer != null)
      throw StateError('Detach the development shadow before backup');
    final payload = await LocalDataAdmission.exclusive(_captureSnapshot);
    final file = await _writeSnapshot(
      payload,
      targetFilePath: targetFilePath,
      password: password,
    );
    lastBackupMetrics = {
      ...lastBackupMetrics,
      'durationMs': total.elapsedMicroseconds / 1000,
      'bytes': await file.length(),
    };
    return file;
  }

  static Future<Map<String, dynamic>> _captureSnapshot() async {
    final pause = Stopwatch()..start();
    await _ensureRecoveryBoxes();
    if (_storeBoxes().length != PosBackupFormat.stores.length - 1)
      throw StateError(
        'Required restaurant stores are not open; refusing incomplete backup',
      );
    await MenuLocalStore.forBox(DatabaseCore.menuBox!).run(() async {});
    await SaleLedgerSyncState.ensureSaleIdentities();
    for (final box in _storeBoxes().values) {
      await box.flush();
    }
    await EdgeCommandJournal.flushForUpdate();
    final data = _snapshotPayload();
    lastBackupMetrics = {'barrierMs': pause.elapsedMicroseconds / 1000};
    return data;
  }

  static Future<File> _writeSnapshot(
    Map<String, dynamic> payload, {
    String? targetFilePath,
    String? password,
  }) async {
    PosBackupFormat.seal(payload);
    PosBackupFormat.validate(payload);
    _decodeStores(payload);
    final text = await PosBackupFormat.encode(payload, password: password);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final file = File(
      targetFilePath ??
          '${DatabaseCore.dataDirectoryPath}/backups/pos_backup_$timestamp.json',
    );
    await _atomicWrite(file, text);
    return file;
  }

  static Map<String, dynamic> _snapshotPayload() {
    final timestamp = DateTime.now().toUtc();
    // Read once so the keys and the values cannot disagree about their order.
    final auditLogEntries = DatabaseCore.auditLogBox!.toMap().entries.toList(
      growable: false,
    );

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
      if (DatabaseCore.userBox?.isOpen ?? false)
        'users': DatabaseCore.userBox!.values.map(_serializeUser).toList(),
      if (DatabaseCore.tableBox?.isOpen ?? false)
        'tables': DatabaseCore.tableBox!.values.map(_serializeTable).toList(),
      if (DatabaseCore.orderBox?.isOpen ?? false)
        'orders': DatabaseCore.orderBox!.values.map(_serializeOrder).toList(),
      if (DatabaseCore.packageBox?.isOpen ?? false)
        'packages': DatabaseCore.packageBox!.values
            .map(_serializePackage)
            .toList(),
      if (DatabaseCore.reservationBox?.isOpen ?? false)
        'reservations': DatabaseCore.reservationBox!.values
            .map(_serializeReservation)
            .toList(),
      if (DatabaseCore.quickOrderBox?.isOpen ?? false)
        'quickOrders': DatabaseCore.quickOrderBox!.values
            .map(_serializeQuickOrderDraft)
            .toList(),
      if (DatabaseCore.menuBox?.isOpen ?? false)
        'menu': DatabaseCore.menuBox!.values
            .map(_serializeMenuCategory)
            .toList(),
      'inventoryCatalog': InventoryRepository.exportCatalog(),
      if (DatabaseCore.salesBox?.isOpen ?? false)
        'sales': DatabaseCore.salesBox!.values
            .map(_serializeDynamicMap)
            .toList(),
      if (DatabaseCore.expenseBox?.isOpen ?? false)
        'expenses': DatabaseCore.expenseBox!.values
            .map(_serializeDynamicMap)
            .toList(),
      'auditLog': auditLogEntries
          .map((entry) => _serializeDynamicMap(entry.value))
          .toList(),
      // The keys the audit box actually used, index-aligned with `auditLog`.
      //
      // A restore has to put each row back where it belongs: an audit report
      // lives under `audit_report_order_<id>` and a legacy action log under
      // `legacy_event_<micros>`, and code reads both by that key rather than by
      // scanning contents. The old backup carried values only, so a restore had
      // nowhere to put them and appended — which stored a report under a fresh
      // integer key, hid legacy logs from the audit screen, and duplicated
      // everything again on the next restore. `auditLog` keeps its old shape so
      // a backup taken now still restores on a build that ignores this field.
      'auditLogKeys': auditLogEntries.map((entry) => entry.key).toList(),
      'errorLog': <dynamic>[],
    };

    backupPayload['errorLog'] = <dynamic>[];
    final stateRaw = DatabaseCore.menuCanonicalBox?.get(
      MenuLocalStore.stateKey,
    );
    final canonicalVenue = stateRaw == null
        ? null
        : (jsonDecode(stateRaw) as Map)['venueId'];
    final binding = DatabaseCore.settingsBox?.get('restoreVenueBinding');
    final venue =
        EdgeDeviceCredentialStore.venueId ?? binding ?? canonicalVenue;
    if (canonicalVenue != null && venue != canonicalVenue)
      throw StateError('Stored Menu belongs to another Venue');
    final stores = <String, dynamic>{};
    for (final entry in _storeBoxes().entries) {
      stores[entry.key] = [
        for (final row in entry.value.toMap().entries)
          if (!(entry.key == 'settings' &&
                  PosBackupFormat.deviceSettings.contains(row.key)) &&
              !(entry.key == 'meta' && row.key == 'backupRestoreReceipt'))
            {
              'key': row.key,
              'value': PosBackupFormat.encodeValue(
                _serializeStoreValue(entry.key, row.value),
              ),
            },
      ];
    }
    stores[EdgeCommandJournal.boxName] = [
      for (final row in EdgeCommandJournal.snapshot().entries)
        {'key': row.key, 'value': PosBackupFormat.encodeValue(row.value)},
    ];
    // Detach every nested value before admission resumes.
    return Map<String, dynamic>.from(
      jsonDecode(
        jsonEncode({
          ...backupPayload,
          'formatVersion': PosBackupFormat.version,
          'product': PosBackupFormat.product,
          'createdAt': timestamp.toIso8601String(),
          'appVersion': const String.fromEnvironment(
            'VYNIC_APP_VERSION',
            defaultValue: '1.0.0+1',
          ),
          'hiveSchemaVersion': HiveMigrationService.targetVersion,
          'menuLocalProtocolVersion': MenuLocalStore.protocolVersion,
          'venue': {
            'id': venue,
            'sourceDeviceId': EdgeDeviceCredentialStore.deviceId,
            'name': SettingsRepository.getVenueName(),
          },
          'recoveryCompleteness':
              DatabaseCore.settingsBox?.get('restoreLegacyIncomplete') == true
              ? 'legacy-history-incomplete'
              : 'complete-current-state',
          'confidentiality': {
            'containsStaffPins': true,
            'containsGuestData': true,
            'deviceCredentialsIncluded': false,
            'plaintextRequiresProtectedStorage': true,
          },
          'compatibility': {
            'minimumReaderFormat': PosBackupFormat.version,
            'hiveSchema': 9,
            'menuProtocol': 1,
          },
          'stores': stores,
        }),
      ),
    );
  }

  static Map<String, Box> _storeBoxes() => {
    if (DatabaseCore.metaBox?.isOpen ?? false) 'meta': DatabaseCore.metaBox!,
    if (DatabaseCore.userBox?.isOpen ?? false) 'users': DatabaseCore.userBox!,
    if (DatabaseCore.tableBox?.isOpen ?? false)
      'tables': DatabaseCore.tableBox!,
    if (DatabaseCore.orderBox?.isOpen ?? false)
      'orders': DatabaseCore.orderBox!,
    if (DatabaseCore.packageBox?.isOpen ?? false)
      'packages': DatabaseCore.packageBox!,
    if (DatabaseCore.menuBox?.isOpen ?? false) 'menu': DatabaseCore.menuBox!,
    if (DatabaseCore.settingsBox?.isOpen ?? false)
      'settings': DatabaseCore.settingsBox!,
    if (DatabaseCore.salesBox?.isOpen ?? false) 'sales': DatabaseCore.salesBox!,
    if (DatabaseCore.expenseBox?.isOpen ?? false)
      'expenses': DatabaseCore.expenseBox!,
    if (DatabaseCore.auditLogBox?.isOpen ?? false)
      'auditLog': DatabaseCore.auditLogBox!,
    if (DatabaseCore.reservationBox?.isOpen ?? false)
      'reservations': DatabaseCore.reservationBox!,
    if (DatabaseCore.quickOrderBox?.isOpen ?? false)
      'quickOrders': DatabaseCore.quickOrderBox!,
    if (DatabaseCore.closureJournalBox?.isOpen ?? false)
      'closureJournal': DatabaseCore.closureJournalBox!,
    if (DatabaseCore.inventoryBox?.isOpen ?? false)
      'inventoryCatalog': DatabaseCore.inventoryBox!,
    if (DatabaseCore.menuCanonicalBox?.isOpen ?? false)
      'menuCanonical': DatabaseCore.menuCanonicalBox!,
    if (DatabaseCore.menuJournalBox?.isOpen ?? false)
      'menuMutationJournal': DatabaseCore.menuJournalBox!,
  };

  static Future<void> _ensureRecoveryBoxes() async {
    if (!(DatabaseCore.closureJournalBox?.isOpen ?? false))
      DatabaseCore.closureJournalBox = UpdateTrackedBox(
        await Hive.openBox(DatabaseCore.closureJournalBoxName),
      );
    if (!(DatabaseCore.menuCanonicalBox?.isOpen ?? false))
      DatabaseCore.menuCanonicalBox = UpdateTrackedBox(
        await Hive.openBox<String>(DatabaseCore.menuCanonicalBoxName),
      );
    if (!(DatabaseCore.menuJournalBox?.isOpen ?? false))
      DatabaseCore.menuJournalBox = UpdateTrackedBox(
        await Hive.openBox<String>(DatabaseCore.menuJournalBoxName),
      );
    await EdgeCommandJournal.open(pruneExpired: false);
    if (DatabaseCore.menuBox != null) {
      MenuLocalStore.attach(
        menuBox: DatabaseCore.menuBox!,
        stateBox: DatabaseCore.menuCanonicalBox!,
        journalBox: DatabaseCore.menuJournalBox!,
        venueId: () => EdgeDeviceCredentialStore.venueId,
      );
    }
  }

  static dynamic _serializeStoreValue(String store, dynamic value) =>
      switch (store) {
        'users' => _serializeUser(value as User),
        'tables' => _serializeTable(value as TableModel),
        'orders' => _serializeOrder(value as Order),
        'packages' => _serializePackage(value as Package),
        'menu' => _serializeMenuCategory(value as MenuCategoryDB),
        'reservations' => _serializeReservation(value as Reservation),
        'quickOrders' => _serializeQuickOrderDraft(value as QuickOrderDraft),
        'sales' =>
          value is SaleRecord
              ? {'backupModel': 'SaleRecord', 'fields': value.toMap()}
              : value,
        _ => value,
      };

  static dynamic _deserializeStoreValue(String store, dynamic value) {
    Map<String, dynamic> model() => Map<String, dynamic>.from(value as Map);
    switch (store) {
      case 'users':
        return _deserializeUser(model());
      case 'tables':
        return _deserializeTable(model());
      case 'orders':
        return deserializeOrderSnapshot(model());
      case 'packages':
        return _deserializePackage(model());
      case 'menu':
        return _deserializeMenuCategory(model());
      case 'reservations':
        return _deserializeReservation(model(), preserveStoredValues: true);
      case 'quickOrders':
        return _deserializeQuickOrderDraft(model());
      case 'sales':
        return value is Map && value['backupModel'] == 'SaleRecord'
            ? SaleRecord.fromMap(
                Map<String, dynamic>.from(value['fields'] as Map),
              )
            : value;
      case 'menuCanonical':
      case 'menuMutationJournal':
        if (value is! String)
          throw const FormatException('Invalid Menu store value');
        return value;
      case 'edge_command_journal':
        if (value is! Map ||
            ![
              'running',
              'interrupted',
              'succeeded',
              'failed',
            ].contains(value['status']) ||
            value['commandId'] is! String)
          throw const FormatException('Invalid command result journal');
        return value;
      default:
        return value;
    }
  }

  static void _validateTypedSnapshot(String name, dynamic value) {
    const required = {
      'users': ['username', 'pinCode', 'role'],
      'tables': ['tableNumber', 'floor', 'edgeRevision', 'activeOrderId'],
      'orders': [
        'orderId',
        'orderUuid',
        'items',
        'packageItems',
        'totalAmount',
        'createdAt',
        'createdBy',
        'status',
        'floor',
      ],
      'packages': [
        'packageId',
        'name',
        'items',
        'pricePerPerson',
        'createdAt',
        'createdBy',
      ],
      'menu': [
        'id',
        'slug',
        'translationsEn',
        'translationsKa',
        'sendToKitchen',
      ],
      'reservations': [
        'id',
        'customerName',
        'customerPhone',
        'reservationDate',
        'createdAt',
        'status',
      ],
      'quickOrders': [
        'id',
        'items',
        'subtotal',
        'total',
        'createdAt',
        'createdBy',
      ],
      'closureJournal': [
        'closureId',
        'orderId',
        'phase',
        'businessDate',
        'grossSaleAmount',
        'advanceApplied',
        'collectedNow',
        'startedAt',
      ],
    };
    final fields = required[name];
    if (fields == null) return;
    if (value is! Map || fields.any((key) => !value.containsKey(key)))
      throw FormatException('Incomplete $name model');
    for (final key in ['createdAt', 'reservationDate', 'startedAt']) {
      if (value.containsKey(key)) DateTime.parse(value[key] as String);
    }
    if (['orders', 'quickOrders'].contains(name)) {
      for (final key in ['items', if (name == 'orders') 'packageItems']) {
        for (final line in value[key] as List) {
          if (line is! Map ||
              [
                'itemKey',
                'itemName',
                'unitPrice',
                'quantity',
                'total',
              ].any((key) => !line.containsKey(key)))
            throw const FormatException('Incomplete captured order line');
          if (line['unitPrice'] is! num ||
              line['quantity'] is! int ||
              line['total'] is! num)
            throw const FormatException('Invalid captured money/quantity');
        }
      }
    }
    if (name == 'closureJournal' &&
        ![
          'started',
          'saleWritten',
          'postSaleEffectsCompleted',
          'completed',
        ].contains(value['phase']))
      throw const FormatException('Unsupported closure phase');
  }

  static Map<String, Map<dynamic, dynamic>> _decodeStores(
    Map<String, dynamic> payload,
  ) {
    final out = <String, Map<dynamic, dynamic>>{};
    for (final name in PosBackupFormat.stores) {
      final rows = <dynamic, dynamic>{};
      for (final row in payload['stores'][name] as List) {
        final value = PosBackupFormat.decodeValue(row['value']);
        _validateTypedSnapshot(name, value);
        if (name == 'edge_command_journal') {
          if (value is! Map ||
              row['key'] != value['commandId'] ||
              value['idempotencyKey'] is! String ||
              value['type'] is! String)
            throw const FormatException('Invalid command identity');
          DateTime.parse(value['firstSeenAt'] as String);
          if (value['completedAt'] != null)
            DateTime.parse(value['completedAt'] as String);
        }
        if (name == 'closureJournal') {
          if (row['key'] != value['closureId'])
            throw const FormatException('Invalid closure identity');
          ClosureJournalEntry.fromMap(value as Map);
        }
        rows[row['key']] = _deserializeStoreValue(name, value);
      }
      out[name] = rows;
    }
    final menu = out['menuCanonical']!;
    final dayClose = out['meta']![CloseDayJournalRepository.key];
    if (dayClose != null) {
      final intent = CloseDayIntent.fromMap(dayClose);
      if (intent.pending &&
          out['settings']!['currentDate'] != intent.fromDate &&
          out['settings']!['currentDate'] != intent.toDate) {
        throw const FormatException('Close Day date disagrees with backup');
      }
    }
    var pendingTransfers = 0;
    for (final entry in out['meta']!.entries) {
      if (entry.key is! String ||
          !(entry.key as String).startsWith(
            OrderTransferJournalRepository.prefix,
          ))
        continue;
      final intent = OrderTransferJournalRepository.decode(
        entry.key as String,
        entry.value,
      );
      if (intent.pending) {
        if (++pendingTransfers > 1) {
          throw const FormatException(
            'Multiple pending Order transfers in backup',
          );
        }
        if (dayClose != null && CloseDayIntent.fromMap(dayClose).pending ||
            BusinessDayRepository.dateKey(
                  DateTime.parse(out['settings']!['currentDate'] as String),
                ) !=
                intent.request['businessDate']) {
          throw const FormatException(
            'Order transfer backup date/recovery disagrees',
          );
        }
        OrderTransferJournalRepository.validateCurrent(
          intent,
          (store, key) =>
              OrderItemTransfer.persistedImage(store, key, stores: out),
        );
      }
    }
    final pendingEdits = OrderEditRepository.validateBackup(out);
    final pendingRepairs = TableRepairRepository.validateBackup(out);
    if (pendingEdits > 0 &&
        (pendingRepairs > 0 ||
            pendingTransfers > 0 ||
            dayClose != null && CloseDayIntent.fromMap(dayClose).pending))
      throw const FormatException(
        'Order edit overlaps another recovery in backup',
      );
    if (pendingRepairs > 0 &&
        (pendingTransfers > 0 ||
            dayClose != null && CloseDayIntent.fromMap(dayClose).pending))
      throw const FormatException(
        'Table repair overlaps another recovery in backup',
      );
    var pendingOwnership = 0;
    for (final entry in out['meta']!.entries) {
      if (entry.key is! String ||
          !(entry.key as String).startsWith(
            OrderTableMutationRepository.prefix,
          ))
        continue;
      if (TableRepairRepository.isRecord(entry.key, entry.value) ||
          OrderEditRepository.isRecord(entry.key, entry.value))
        continue;
      final intent = OrderTableMutationRepository.decode(
        entry.key as String,
        entry.value,
      );
      if (!intent.pending) continue;
      if (++pendingOwnership > 1 ||
          pendingEdits > 0 ||
          pendingRepairs > 0 ||
          pendingTransfers > 0 ||
          dayClose != null && CloseDayIntent.fromMap(dayClose).pending ||
          BusinessDayRepository.dateKey(
                DateTime.parse(out['settings']!['currentDate'] as String),
              ) !=
              intent.businessDate)
        throw const FormatException('Ownership backup recovery/date disagrees');
      OrderTableMutationRepository.validateCurrent(
        intent,
        (store, key) => OrderTableMutationRepository.persistedImage(
          store,
          key,
          stores: out,
        ),
      );
      OrderTableMutationRepository.validateFinalOwnership(
        intent,
        orders: out['orders']!.cast<dynamic, Order>(),
        tables: out['tables']!.cast<dynamic, TableModel>(),
      );
    }
    if (menu[MenuLocalStore.versionKey] != null &&
        menu[MenuLocalStore.versionKey] != '1')
      throw const FormatException('Unknown local Menu protocol');
    if (menu.containsKey(MenuLocalStore.commitKey) ||
        menu.containsKey(MenuLocalStore.rebuildingKey))
      throw const FormatException(
        'Backup does not contain a stable Menu boundary',
      );
    final state = menu[MenuLocalStore.stateKey];
    final venue = payload['venue']['id'];
    if (state != null) CanonicalMenu.fromJsonString(state as String).toHive();
    if (menu[MenuLocalStore.generationKey] != null &&
        int.parse(menu[MenuLocalStore.generationKey] as String) < 0) {
      throw const FormatException('Invalid Menu generation');
    }
    if (state != null &&
        (jsonDecode(state as String) as Map)['venueId'] != venue)
      throw const FormatException('Menu Venue does not match backup');
    final baseline = menu[MenuLocalStore.baselineKey];
    if (baseline != null &&
        CanonicalMenu.fromJsonString(baseline as String).venueId != venue)
      throw const FormatException('Menu baseline belongs to another Venue');
    final journal = out['menuMutationJournal']!;
    if (journal.isNotEmpty && state == null)
      throw const FormatException(
        'Missing canonical recovery state for Menu journal',
      );
    for (final entry in journal.entries) {
      final raw = jsonDecode(entry.value as String) as Map;
      if (entry.key is! String || int.parse(entry.key as String) != raw['seq'])
        throw const FormatException('Invalid Menu journal sequence key');
      MenuMutationEntry.fromJson(Map<String, dynamic>.from(raw));
      if (!MenuMutationStatus.values.map((s) => s.name).contains(raw['status']))
        throw const FormatException('Unknown menu mutation status');
      if (raw['venueId'] != venue || raw['mutationId'] is! String)
        throw const FormatException(
          'Mutation Venue/identity does not match backup',
        );
    }
    final pendingProfile = out['settings']!['pendingVenueProfile'];
    if (pendingProfile is Map && pendingProfile['venueId'] != venue)
      throw const FormatException('Profile intent belongs to another Venue');
    if (out['settings']!.keys.any(PosBackupFormat.deviceSettings.contains))
      throw const FormatException(
        'Portable backup contains installation identity',
      );
    return out;
  }

  static void _validateVenue(Map<String, dynamic> payload) {
    final source = payload['venue']['id'];
    final destination = EdgeDeviceCredentialStore.venueId;
    final binding = DatabaseCore.settingsBox?.get('restoreVenueBinding');
    if ((destination != null && source != destination) ||
        (binding != null && source != binding) ||
        (EdgeDeviceCredentialStore.hasCredential && destination == null))
      throw StateError(
        'Backup does not match the destination enrollment/Venue',
      );
    final current = DatabaseCore.menuCanonicalBox?.get(MenuLocalStore.stateKey);
    if (current != null && (jsonDecode(current) as Map)['venueId'] != source)
      throw StateError('Backup belongs to another local Venue');
  }

  static void _validateLegacy(Map<String, dynamic> payload) {
    if (!payload.keys.any(
      [
        'users',
        'tables',
        'orders',
        'menu',
        'sales',
        'auditLog',
        'settingsAll',
      ].contains,
    ))
      throw const FormatException('Unrecognized legacy backup');
    final schema = (payload['meta'] as Map?)?['db_version'];
    if (schema != null && (schema is! int || schema > 9))
      throw const FormatException('Unsupported legacy Hive schema');
    _normalizeLegacyIdentities(payload);
    for (final section in [
      'users',
      'tables',
      'orders',
      'packages',
      'menu',
      'reservations',
      'quickOrders',
      'sales',
      'expenses',
      'auditLog',
      'errorLog',
    ]) {
      if (payload[section] == null) continue;
      if (payload[section] is! List ||
          (payload[section] as List).any((row) => row is! Map))
        throw FormatException('Invalid legacy $section');
      for (final row in payload[section] as List) {
        if ([
          'users',
          'tables',
          'orders',
          'packages',
          'menu',
          'reservations',
          'quickOrders',
        ].contains(section))
          _deserializeStoreValue(section, row);
      }
    }
    if (payload['currentDate'] != null)
      DateTime.parse(payload['currentDate'] as String);
    if (payload['auditLogKeys'] != null && payload['auditLogKeys'] is! List)
      throw const FormatException('Invalid legacy audit keys');
    if (payload['settings'] != null && payload['settings'] is! Map)
      throw const FormatException('Invalid legacy settings');
    final oldSettings = payload['settings'] as Map?;
    for (final key in [
      'defaultLanguage',
      'printerKitchenIp',
      'printerReceiptIp',
    ]) {
      if (oldSettings?[key] != null && oldSettings![key] is! String)
        throw const FormatException('Invalid legacy setting');
    }
    if (payload['inventoryCatalog'] != null &&
        payload['inventoryCatalog'] is! Map)
      throw const FormatException('Invalid legacy inventory');
    final all = payload['settingsAll'];
    if (all != null && all is! Map)
      throw const FormatException('Invalid legacy settings');
    if (all is Map)
      for (final key in PosBackupFormat.deviceSettings) {
        all.remove(key);
      }
  }

  /// Missing identities in pre-identity exports get deterministic upgrade IDs.
  /// They are fixed in the descriptor before the first destructive write.
  static void _normalizeLegacyIdentities(Map<String, dynamic> payload) {
    if (!payload.containsKey('reservations') &&
        payload.containsKey('reservation'))
      payload['reservations'] = payload.remove('reservation');
    if (!payload.containsKey('quickOrders') &&
        payload.containsKey('quickOrderDrafts'))
      payload['quickOrders'] = payload.remove('quickOrderDrafts');
    final seed = PosBackupFormat.digest(payload);
    void identity(Map row, String key, String path) {
      if (row[key] == null || row[key] == '')
        row[key] = const Uuid().v5(
          Uuid.NAMESPACE_URL,
          'vynic-legacy:$seed:$path:$key',
        );
    }

    void walk(dynamic rows, String path, void Function(Map, String) visit) {
      if (rows == null) return;
      if (rows is! List) throw const FormatException('Invalid legacy rows');
      for (var i = 0; i < rows.length; i++) {
        if (rows[i] is! Map) throw const FormatException('Invalid legacy row');
        visit(rows[i] as Map, '$path/$i');
      }
    }

    void menu(Map row, String path) {
      identity(row, 'id', path);
      walk(row['items'], '$path/items', (row, path) {
        identity(row, 'id', path);
        walk(
          row['variants'],
          '$path/variants',
          (row, path) => identity(row, 'id', path),
        );
      });
      walk(row['subcategories'], '$path/subcategories', menu);
    }

    walk(payload['menu'], 'menu', menu);
    for (final name in ['orders', 'reservations', 'quickOrders', 'packages']) {
      walk(payload[name], name, (row, path) {
        identity(
          row,
          name == 'orders'
              ? 'orderUuid'
              : name == 'packages'
              ? 'packageId'
              : 'id',
          path,
        );
        for (final key in [
          'createdAt',
          if (name == 'reservations') 'reservationDate',
        ]) {
          row[key] ??= payload['generatedAt'] ?? '1970-01-01T00:00:00.000Z';
        }
        if (name != 'packages') {
          for (final key in ['items', 'packageItems', 'preOrderItems']) {
            walk(
              row[key],
              '$path/$key',
              (row, path) => identity(row, 'lineUuid', path),
            );
          }
        }
      });
    }
  }

  static Future<void> _atomicWrite(File file, String text) async {
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.staging');
    if (await staging.exists())
      throw StateError('Unfinished backup staging file; choose a new path');
    try {
      await staging.create();
      if (!Platform.isWindows) {
        final mode = await Process.run('chmod', ['600', staging.path]);
        if (mode.exitCode != 0)
          throw FileSystemException(
            'Cannot protect backup staging file',
            staging.path,
          );
      }
      await staging.writeAsString(text, flush: true);
      await staging.rename(file.path);
    } catch (_) {
      if (await staging.exists()) await staging.delete();
      rethrow;
    }
  }

  /// Replays a fully validated descriptor before Menu recovery/defaults/UI.
  static Future<void> recoverInterruptedRestore() async {
    final marker = File('${DatabaseCore.dataDirectoryPath}/$restoreMarkerName');
    if (!await marker.exists()) return;
    LocalDataAdmission.failure =
        'Interrupted backup restore requires startup recovery';
    final descriptor = Map<String, dynamic>.from(
      jsonDecode(await marker.readAsString()) as Map,
    );
    await LocalDataAdmission.exclusive(() async {
      await _ensureRecoveryBoxes();
      await _finishRestore(descriptor, marker);
      LocalDataAdmission.failure = null;
    }, recovery: true);
  }

  static Future<void> _finishRestore(
    Map<String, dynamic> descriptor,
    File marker,
  ) async {
    if (descriptor['restoreProtocolVersion'] != 1)
      throw const FormatException('Unsupported restore recovery protocol');
    final unsigned = Map<String, dynamic>.of(descriptor)
      ..remove('descriptorSha256');
    if (descriptor['descriptorSha256'] != PosBackupFormat.digest(unsigned))
      throw const FormatException('Damaged restore marker');
    if (descriptor['actorId'] is! String ||
        descriptor['actorName'] != null && descriptor['actorName'] is! String)
      throw const FormatException('Invalid restore actor');
    AuditSource.values.byName(descriptor['source'] as String);
    for (final entry in (descriptor['destinationSettings'] as Map).entries) {
      if (!PosBackupFormat.deviceSettings.contains(entry.key))
        throw const FormatException('Invalid destination identity marker');
      PosBackupFormat.decodeValue(entry.value);
    }
    final payload = Map<String, dynamic>.from(descriptor['payload'] as Map);
    if (descriptor['receipt'] != PosBackupFormat.digest(payload))
      throw const FormatException('Restore recovery descriptor is damaged');
    final modern = descriptor['modern'] == true;
    if (modern) {
      PosBackupFormat.validate(payload);
      _validateVenue(payload);
      final stores = _decodeStores(payload);
      for (final entry in _storeBoxes().entries) {
        await entry.value.clear();
        for (final row in stores[entry.key]!.entries) {
          await entry.value.put(row.key, row.value);
        }
        await entry.value.flush();
      }
      await EdgeCommandJournal.restoreSnapshot(
        stores[EdgeCommandJournal.boxName]!.map(
          (key, value) => MapEntry(key, value as Map),
        ),
      );
    } else {
      _validateLegacy(payload);
      await PosMenuSyncService.instance.externalMenuWrite(
        () => _applyBackupPayload(
          payload,
          clearExisting: descriptor['clearExisting'] == true,
        ),
      );
    }
    final settings = DatabaseCore.settingsBox!;
    for (final key in PosBackupFormat.deviceSettings) {
      await settings.delete(key);
    }
    for (final entry in (descriptor['destinationSettings'] as Map).entries) {
      await settings.put(entry.key, PosBackupFormat.decodeValue(entry.value));
    }
    final venue = modern ? payload['venue']['id'] : null;
    if (venue != null) await settings.put('restoreVenueBinding', venue);
    await settings.put(
      'restoreSourceDeviceId',
      modern ? payload['venue']['sourceDeviceId'] : null,
    );
    await settings.put(
      'restoreLegacyIncomplete',
      !modern ||
          venue == null ||
          payload['recoveryCompleteness'] != 'complete-current-state',
    );
    // Restore already owns admission; finish the restored transition before
    // Menu recovery, rebuilt ACKs or any UI/worker can admit business writes.
    await OrderEditRepository.recoverPending(underExclusive: true);
    await TableRepairRepository.recoverPending(underExclusive: true);
    await OrderTableMutationRepository.recoverPending(underExclusive: true);
    await CloseDayTransaction.recoverUnderAdmission();
    await OrderItemTransfer.recoverUnderAdmission();
    if (DatabaseCore.reservationBox?.isOpen == true)
      await HiveMigrationService.persistReservationLineIdentities(
        DatabaseCore.metaBox!,
        DatabaseCore.reservationBox!,
      );
    // Rebuildable ACKs must not hide unsent data on this destination.
    await AuditSyncState.resetAfterRestore();
    await StaffCredentialSyncState.resetAfterRestore();
    if (DatabaseCore.menuBox != null)
      await MenuLocalStore.forBox(DatabaseCore.menuBox!).initialize();
    await GlobalAudit.backupRestored(
      actorId: descriptor['actorId'] as String,
      actorName: descriptor['actorName'] as String?,
      source: AuditSource.values.byName(descriptor['source'] as String),
      backupCreatedAt: payload['generatedAt'] as String?,
      backupVersion: modern
          ? '2'
          : ((payload['meta'] as Map?)?['db_version']?.toString() ??
                'legacy-incomplete'),
      safetyBackupPath: descriptor['safetyBackupPath'] as String?,
      clearedExisting: descriptor['clearExisting'] == true,
      restoredCounts: {'stores': modern ? 17 : 0, 'legacyIncomplete': !modern},
    );
    if (DatabaseCore.orderBox != null && DatabaseCore.salesBox != null) {
      await ClosureRecoveryService.recoverPending();
    }
    await DatabaseCore.metaBox!.put(
      'backupRestoreReceipt',
      descriptor['receipt'],
    );
    for (final box in _storeBoxes().values) {
      await box.flush();
    }
    DatabaseCore.dbVersion =
        (DatabaseCore.metaBox!.get(HiveMigrationService.dbVersionKey)
            as int?) ??
        HiveMigrationService.targetVersion;
    await marker.delete();
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
      if (!PosBackupFormat.deviceSettings.contains(key))
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
    if (value is SaleRecord) return value.toMap();
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
      'edgeRevision': table.edgeRevision,
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
      'orderUuid': order.orderUuid,
      'edgeRevision': order.edgeRevision,
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
      'packageId': order.packageId,
      'packageName': order.packageName,
      'packagePrice': order.packagePrice,
      'packageItems': order.packageItems.map(_serializeOrderItem).toList(),
      'packageUnitPrice': order.packageUnitPrice,
      'packageGuestCount': order.packageGuestCount,
      'manualAdjustmentAmount': order.manualAdjustmentAmount,
      'openedByUserId': order.openedByUserId,
      'customServiceFeePercentage': order.customServiceFeePercentage,
      'closureId': order.closureId,
      'advanceAmount': order.advanceAmount,
      'advanceCollectedOn': order.advanceCollectedOn,
      'advanceReceiptId': order.advanceReceiptId,
      'customerName': order.customerName,
      'customerPhone': order.customerPhone,
      'pickupTime': order.pickupTime,
    };
  }

  static Map<String, dynamic> _serializeOrderItem(OrderItem item) {
    return {
      'lineUuid': item.lineUuid,
      'itemKey': item.itemKey,
      'itemName': item.itemName,
      'unitPrice': item.unitPrice,
      'quantity': item.quantity,
      'total': item.total,
      'comment': item.comment,
      if (item.menuItemId != null) 'menuItemId': item.menuItemId,
      if (item.variantId != null) 'variantId': item.variantId,
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
      if (item.menuItemId != null) 'menuItemId': item.menuItemId,
      if (item.variantId != null) 'variantId': item.variantId,
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
      'displayName': draft.displayName,
    };
  }

  static Map<String, dynamic> _serializeMenuCategory(MenuCategoryDB category) {
    return {
      if (category.id != null) 'id': category.id,
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
      if (subcategory.id != null) 'id': subcategory.id,
      'slug': subcategory.slug,
      'translationsEn': subcategory.translationsEn,
      'translationsKa': subcategory.translationsKa,
      'items': subcategory.items.map(_serializeMenuItem).toList(),
    };
  }

  static Map<String, dynamic> _serializeMenuItem(MenuItemDB item) {
    return {
      // The item's stable identity travels with the backup, so a restore puts
      // the same products back rather than fresh ones. Absent in backups taken
      // before the field existed; `ensureStableMenuIds` fills those in on the
      // way back.
      if (item.id != null) 'id': item.id,
      'translationsEn': item.translationsEn,
      'translationsKa': item.translationsKa,
      'price': item.price,
      'sendToKitchen': item.sendToKitchen,
      'variants': item.variants?.map(_serializeMenuVariant).toList(),
    };
  }

  static Map<String, dynamic> _serializeMenuVariant(MenuVariantDB variant) {
    return {
      if (variant.id != null) 'id': variant.id,
      'size': variant.size,
      'price': variant.price,
    };
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
  }) => UpdateReadiness.track(
    'importMenuFromJson',
    // Restored rows are not operator edits of a canonical Cloud Menu.
    () => PosMenuSyncService.instance.externalMenuWrite(
      () => _updateTrackedImportMenuFromJson(
        payload,
        clearExisting: clearExisting,
        silent: silent,
      ),
    ),
  );

  static Future<void> _updateTrackedImportMenuFromJson(
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
    // An older backup carries items with no stable id. Give them one now,
    // once, so the restored menu is identified like every other menu.
    await MenuRepository.ensureStableMenuIds();
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

  static Future<void> replaceOrdersFromJson(List<dynamic> payload) =>
      UpdateReadiness.mutate(
        'replaceOrdersFromJson',
        () => _updateTrackedReplaceOrdersFromJson(payload),
      );

  static Future<void> _updateTrackedReplaceOrdersFromJson(
    List<dynamic> payload,
  ) async {
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

  /// Lossless local/format-2 image, including hand-priced line totals.
  /// Legacy imports keep their existing recalculating decoder.
  static Order deserializeOrderSnapshot(Map<String, dynamic> value) =>
      _deserializeOrder(
        value,
        recalculate: false,
        preserveStoredLineTotals: true,
      );

  /// Creates a takeaway order received from the mobile app, with a server-assigned ID.
  /// This bypasses the standard createOrder flow (which auto-assigns IDs and reserves tables)
  /// to allow mobile-originated orders to appear on the POS with a known posOrderId.
  static Future<Order?> createTakeawayOrderFromRemote({
    required int orderId,
    required String customerName,
    required String pickupTime,
    required String waiterName,
    required List<Map<String, dynamic>> items,
  }) => OrderRepository.upsertMobileTakeawayOrder(
    posOrderId: orderId,
    customerName: customerName,
    pickupTime: pickupTime,
    waiterName: waiterName,
    items: items
        .map((raw) => OrderItem.fromJson(Map<String, dynamic>.of(raw)))
        .toList(),
    requestId: 'remote-takeaway:$orderId',
  );

  static Future<Order> createOrderFromJson(Map<String, dynamic> json) =>
      UpdateReadiness.mutate(
        'createOrderFromJson',
        () => _updateTrackedCreateOrderFromJson(json),
      );

  static Future<Order> _updateTrackedCreateOrderFromJson(
    Map<String, dynamic> json,
  ) async {
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
      requestId: json['requestId'] as String?,
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

  static Future<void> replaceReservationsFromJson(List<dynamic> payload) =>
      UpdateReadiness.mutate(
        'replaceReservationsFromJson',
        () => _updateTrackedReplaceReservationsFromJson(payload),
      );

  static Future<void> _updateTrackedReplaceReservationsFromJson(
    List<dynamic> payload,
  ) async {
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
    Map<String, dynamic> json, {
    AuditSource source = AuditSource.manager,
    bool requireDurability = false,
  }) => UpdateReadiness.mutate(
    'createReservationFromJson',
    () => _updateTrackedCreateReservationFromJson(
      json,
      source: source,
      requireDurability: requireDurability,
    ),
  );

  static Future<String> _updateTrackedCreateReservationFromJson(
    Map<String, dynamic> json, {
    AuditSource source = AuditSource.manager,
    bool requireDurability = false,
  }) async {
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
      // Present when Cloud originated the booking and allocated its identity,
      // which is what makes a redelivered create converge instead of duplicate.
      id: json['id'] as String?,
      source: source,
      requireDurability: requireDurability,
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

  static Future<void> replaceTablesFromJson(List<dynamic> payload) =>
      UpdateReadiness.mutate(
        'replaceTablesFromJson',
        () => _updateTrackedReplaceTablesFromJson(payload),
      );

  static Future<void> _updateTrackedReplaceTablesFromJson(
    List<dynamic> payload,
  ) async {
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

  static Future<void> updateTableFromJson(Map<String, dynamic> json) =>
      UpdateReadiness.mutate(
        'updateTableFromJson',
        () => _updateTrackedUpdateTableFromJson(json),
      );

  static Future<void> _updateTrackedUpdateTableFromJson(
    Map<String, dynamic> json,
  ) async {
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
    String actorId = 'unknown',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? password,
    bool allowLegacyIncomplete = false,
  }) async {
    if (!await backupFile.exists())
      throw ArgumentError('Backup file not found');
    await restoreDataBackupFromJson(
      await backupFile.readAsString(),
      clearExisting: clearExisting,
      backupBeforeRestore: backupBeforeRestore,
      actorId: actorId,
      actorName: actorName,
      source: source,
      password: password,
      allowLegacyIncomplete: allowLegacyIncomplete,
    );
  }

  static Future<void> restoreDataBackupFromJson(
    String jsonString, {
    bool clearExisting = true,
    bool backupBeforeRestore = true,
    String actorId = 'unknown',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? password,
    bool allowLegacyIncomplete = false,
  }) async {
    final total = Stopwatch()..start();
    final payload = await PosBackupFormat.decode(
      jsonString,
      password: password,
    );
    final modern = payload.containsKey('formatVersion');
    if (modern) {
      PosBackupFormat.validate(payload);
      _decodeStores(payload); // Parse every model before any write.
      _validateVenue(payload);
      if (!clearExisting)
        throw const FormatException(
          'Complete recovery backups replace data; merging is unsupported',
        );
    } else {
      if (!allowLegacyIncomplete)
        throw const FormatException(
          'Legacy backup is incomplete: no Menu/closure/command recovery guarantee. Explicit legacy import is required.',
        );
      _validateLegacy(payload);
    }
    final receipt = PosBackupFormat.digest(payload);
    if (DatabaseCore.metaBox?.get('backupRestoreReceipt') == receipt) return;
    await LocalDataAdmission.exclusive(() async {
      await _ensureRecoveryBoxes();
      if (modern) {
        _validateVenue(payload);
        if (_storeBoxes().length != PosBackupFormat.stores.length - 1)
          throw StateError('Required restore stores are not open');
      }
      if (!modern &&
          ((DatabaseCore.metaBox?.keys.any(
                    (key) =>
                        key is String &&
                        (key.startsWith(
                              OrderTransferJournalRepository.prefix,
                            ) ||
                            key.startsWith(
                              OrderTableMutationRepository.prefix,
                            )),
                  ) ??
                  false) ||
              (DatabaseCore.metaBox?.containsKey(
                    CloseDayJournalRepository.key,
                  ) ??
                  false) ||
              (DatabaseCore.menuJournalBox?.isNotEmpty ?? false) ||
              (DatabaseCore.menuCanonicalBox?.containsKey(
                    MenuLocalStore.stateKey,
                  ) ??
                  false) ||
              (DatabaseCore.closureJournalBox?.isNotEmpty ?? false) ||
              EdgeCommandJournal.snapshot().isNotEmpty)) {
        throw StateError(
          'Legacy import requires a destination without Menu/closure/command recovery state',
        );
      }
      final pause = Stopwatch()..start();
      final safetyBackupPath = backupBeforeRestore
          ? (await _writeSnapshot(await _captureSnapshot())).path
          : null;
      final descriptor = {
        'restoreProtocolVersion': 1,
        'payload': payload,
        'modern': modern,
        'clearExisting': clearExisting,
        'receipt': receipt,
        'destinationSettings': {
          for (final key in PosBackupFormat.deviceSettings)
            if (DatabaseCore.settingsBox?.containsKey(key) ?? false)
              key: PosBackupFormat.encodeValue(
                DatabaseCore.settingsBox!.get(key),
              ),
        },
        'actorId': actorId,
        'actorName': actorName,
        'source': source.name,
        'safetyBackupPath': safetyBackupPath,
      };
      final marker = File(
        '${DatabaseCore.dataDirectoryPath}/$restoreMarkerName',
      );
      descriptor['descriptorSha256'] = PosBackupFormat.digest(descriptor);
      await _atomicWrite(marker, jsonEncode(descriptor));
      try {
        await _finishRestore(descriptor, marker);
      } catch (_) {
        LocalDataAdmission.failure =
            'Interrupted backup restore; restart to finish recovery';
        rethrow;
      }
      lastRestoreMetrics = {'barrierMs': pause.elapsedMicroseconds / 1000};
    });
    lastRestoreMetrics = {
      ...lastRestoreMetrics,
      'durationMs': total.elapsedMicroseconds / 1000,
    };
    for (final type in [
      SyncEventType.menu,
      SyncEventType.orders,
      SyncEventType.reservations,
      SyncEventType.tables,
    ]) {
      SyncHub.notify(SyncEvent(type: type, action: 'reloaded'));
    }
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
  static Future<String?> wipeAllData({bool backupFirst = true}) =>
      LocalDataAdmission.exclusive(() async {
        final safety = backupFirst
            ? (await _writeSnapshot(await _captureSnapshot())).path
            : null;
        await PosMenuSyncService.instance.externalMenuWrite(
          () => _updateTrackedWipeAllData(backupFirst: false),
        );
        return safety;
      });

  static Future<String?> _updateTrackedWipeAllData({
    bool backupFirst = true,
  }) async {
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
      if (DatabaseCore.inventoryBox != null) DatabaseCore.inventoryBox!.clear(),
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

  /// Restores the audit box, each row under the key it belongs at.
  ///
  /// The key is not decoration: `AuditRepository` reads a report by
  /// `audit_report_order_<orderId>`, derives its legacy reports only from keys
  /// prefixed `legacy_event_`, and `AuditEventService` writes its own rows
  /// under the event's uuid. Appending instead — which is what this used to do
  /// — put a report somewhere nothing looks for it, so the next write created a
  /// second copy under the canonical key and the report was then offered to
  /// Cloud as two conflicting versions of itself, only one of which could ever
  /// be acknowledged. It also dropped legacy action logs out of the audit
  /// screen entirely, since a row under an integer key has no prefix to match.
  ///
  /// Every key below is derived from the row's own content, so restoring the
  /// same backup twice writes the same rows twice rather than doubling them.
  static Future<void> _restoreAuditLog(
    List<dynamic> auditLogJson,
    List<dynamic>? recordedKeys,
  ) async {
    final box = DatabaseCore.auditLogBox;
    if (box == null) return;

    for (var index = 0; index < auditLogJson.length; index++) {
      final raw = auditLogJson[index];
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final recorded = recordedKeys != null && index < recordedKeys.length
          ? recordedKeys[index]
          : null;
      await box.put(_auditLogKeyFor(entry, recorded, box), entry);
    }
  }

  /// Where one audit row goes.
  ///
  /// Identity carried by the row wins over the key the backup recorded: a
  /// report's canonical home is its own `reportId`, so a backup taken from a
  /// store that had already been damaged by the old append restore is repaired
  /// rather than reproduced.
  static Object _auditLogKeyFor(
    Map<String, dynamic> entry,
    Object? recordedKey,
    Box<dynamic> box,
  ) {
    // An audit report. `reportId` is exactly what AuditRepository writes under.
    final reportId = (entry['reportId'] as String?)?.trim();
    if (reportId != null && reportId.isNotEmpty) return reportId;

    // An AuditEventLog row, keyed by its own uuid by AuditEventService.
    final eventId = (entry['id'] as String?)?.trim();
    if (eventId != null && eventId.isNotEmpty) return eventId;

    // A legacy action log from a backup that recorded its key.
    if (recordedKey is String && recordedKey.isNotEmpty) return recordedKey;
    if (recordedKey is int) return recordedKey;

    // A legacy action log from an older backup, which carried no keys. The key
    // the POS minted was the moment of the action, so rebuild that from the
    // log's own timestamp and keep the prefix the audit screen looks for.
    final timestamp = parseAuditTimestamp(entry['timestamp']);
    if (timestamp == null) {
      // Nothing in the row says when it happened, and inventing a number here
      // would read back as a fabricated time. A content address instead: not
      // parseable as micros, so it resolves as an unknown time.
      return 'legacy_event_undated_${_contentDigest(entry)}';
    }

    // Two distinct logs can share a microsecond. Step past an occupied slot
    // rather than overwrite it, and stop as soon as the row already there is
    // this same row — which is what makes a repeated restore a no-op.
    final base = timestamp.microsecondsSinceEpoch;
    for (var offset = 0; offset < _auditLogKeyProbeLimit; offset++) {
      final candidate = 'legacy_event_${base + offset}';
      final occupant = box.get(candidate);
      if (occupant == null) return candidate;
      if (occupant is Map &&
          _contentDigest(occupant) == _contentDigest(entry)) {
        return candidate;
      }
    }
    return 'legacy_event_undated_${_contentDigest(entry)}';
  }

  /// How far [_auditLogKeyFor] will probe past a taken microsecond.
  static const int _auditLogKeyProbeLimit = 64;

  /// A short stable fingerprint of a row's content, order-independent.
  static String _contentDigest(Map<dynamic, dynamic> entry) {
    final keys = entry.keys.map((key) => key.toString()).toList()..sort();
    final buffer = StringBuffer();
    for (final key in keys) {
      buffer
        ..write(json.encode(key))
        ..write(':')
        ..write(json.encode(_canonicalForDigest(entry[key])))
        ..write(',');
    }
    return sha256
        .convert(utf8.encode(buffer.toString()))
        .toString()
        .substring(0, 16);
  }

  /// Nested content in a form whose encoding cannot depend on map ordering —
  /// a row read from Hive and the same row decoded from JSON must fingerprint
  /// alike, or a repeated restore would stop recognising its own work.
  static Object? _canonicalForDigest(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonicalForDigest(value[key])};
    }
    if (value is List) return value.map(_canonicalForDigest).toList();
    if (value is DateTime) return value.toIso8601String();
    return value;
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
    final inventoryCatalog = payload['inventoryCatalog'];
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
        if (DatabaseCore.inventoryBox != null)
          DatabaseCore.inventoryBox!.clear(),
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
    // Same rule as `importMenuFromJson`: a backup written before menu items
    // had identities restores id-less rows, and they get one here — once.
    await MenuRepository.ensureStableMenuIds();
    if (DatabaseCore.inventoryBox != null) {
      await InventoryRepository.restoreCatalog(inventoryCatalog);
    }

    for (final saleEntry in salesJson) {
      if (saleEntry is Map) {
        await DatabaseCore.salesBox!.add(Map<String, dynamic>.from(saleEntry));
      }
    }

    for (final expenseEntry in expensesJson) {
      if (expenseEntry is Map) {
        await DatabaseCore.expenseBox!.add(
          Map<String, dynamic>.from(expenseEntry),
        );
      }
    }

    await _restoreAuditLog(auditLogJson, payload['auditLogKeys'] as List?);

    for (final errorEntry in errorLogJson) {
      if (errorEntry is Map) {
        await DatabaseCore.errorLogBox!.add(
          Map<String, dynamic>.from(errorEntry),
        );
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
      edgeRevision: (json['edgeRevision'] as num?)?.toInt() ?? 0,
      tableNumber: json['tableNumber']?.toString() ?? '0',
      floor: json['floor'] as String? ?? 'first',
      isReserved: json['isReserved'] as bool? ?? false,
      reservedAt: _tryParseDate(json['reservedAt'] as String?),
      reservedBy: json['reservedBy'] as String?,
      activeOrderId: (json['activeOrderId'] as num?)?.toInt(),
      reservationId: json['reservationId'] as String?,
    );
  }

  static Order _deserializeOrder(
    Map<String, dynamic> json, {
    bool recalculate = true,
    bool preserveStoredLineTotals = false,
  }) {
    final items = ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (it) => _deserializeOrderItem(
            Map<String, dynamic>.from(it),
            preserveStoredTotal: preserveStoredLineTotals,
          ),
        )
        .toList();
    final packageItems = ((json['packageItems'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (it) => _deserializeOrderItem(
            Map<String, dynamic>.from(it),
            preserveStoredTotal: preserveStoredLineTotals,
          ),
        )
        .toList();

    final order = Order(
      orderUuid: json['orderUuid'] as String?,
      edgeRevision: (json['edgeRevision'] as num?)?.toInt() ?? 0,
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
      packageId: json['packageId'] as String?,
      packageName: json['packageName'] as String?,
      packagePrice: (json['packagePrice'] as num?)?.toDouble() ?? 0.0,
      packageItems: packageItems,
      packageUnitPrice: (json['packageUnitPrice'] as num?)?.toDouble() ?? 0.0,
      packageGuestCount: (json['packageGuestCount'] as num?)?.toInt() ?? 0,
      manualAdjustmentAmount:
          (json['manualAdjustmentAmount'] as num?)?.toDouble() ?? 0.0,
      openedByUserId: json['openedByUserId'] as String?,
      customServiceFeePercentage: (json['customServiceFeePercentage'] as num?)
          ?.toDouble(),
      closureId: json['closureId'] as String?,
      advanceAmount: (json['advanceAmount'] as num?)?.toDouble() ?? 0.0,
      advanceCollectedOn: json['advanceCollectedOn'] as String?,
      advanceReceiptId: json['advanceReceiptId'] as String?,
      customerName: json['customerName'] as String? ?? '',
      customerPhone: json['customerPhone'] as String? ?? '',
      pickupTime: json['pickupTime'] as String? ?? '',
    );

    if (recalculate) order.recalculateTotal();
    return order;
  }

  static Reservation _deserializeReservation(
    Map<String, dynamic> json, {
    bool preserveStoredValues = false,
  }) {
    final preOrders = ((json['preOrderItems'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (it) => _deserializeOrderItem(
            Map<String, dynamic>.from(it),
            preserveStoredTotal: preserveStoredValues,
          ),
        )
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
      tableRefs: preserveStoredValues
          ? (json['tableRefs'] == null ? null : tableRefs)
          : tableRefs.isNotEmpty
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
      preOrderItems: preserveStoredValues
          ? (json['preOrderItems'] == null ? null : preOrders)
          : preOrders.isEmpty
          ? null
          : preOrders,
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
      menuItemId: json['menuItemId'] as String?,
      variantId: json['variantId'] as String?,
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
      displayName: json['displayName'] as String?,
    );
  }

  static MenuCategoryDB _deserializeMenuCategory(Map<String, dynamic> json) {
    return MenuCategoryDB(
      id: json['id'] as String?,
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
      id: json['id'] as String?,
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
    // Never mints: a backup that carries no id restores id-less items, and
    // `ensureStableMenuIds` gives each of them exactly one afterwards. Minting
    // here would hand the same product a new identity on every restore.
    final id = (json['id'] as String?)?.trim();
    return MenuItemDB(
      id: id == null || id.isEmpty ? null : id,
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
      id: json['id'] as String?,
      size: (json['size'] as num?)?.toDouble() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
    );
  }

  static OrderItem _deserializeOrderItem(
    Map<String, dynamic> json, {
    bool preserveStoredTotal = false,
  }) {
    final unitPrice = (json['unitPrice'] as num?)?.toDouble() ?? 0.0;
    final quantity = (json['quantity'] as num?)?.toInt() ?? 0;
    final total = preserveStoredTotal && json['total'] is num
        ? (json['total'] as num).toDouble()
        : unitPrice * quantity;
    return OrderItem(
      lineUuid: json['lineUuid'] as String?,
      itemKey: json['itemKey'] as String? ?? '',
      itemName: json['itemName'] as String? ?? '',
      unitPrice: unitPrice,
      quantity: quantity,
      total: total,
      comment: json['comment'] as String?,
      menuItemId: json['menuItemId'] as String?,
      variantId: json['variantId'] as String?,
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
