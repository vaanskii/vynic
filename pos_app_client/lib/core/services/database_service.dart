import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';
import 'hive_migration_service.dart';
import 'sync_events.dart';
import 'package:uuid/uuid.dart';
import 'dart:developer' as developer;
import 'audit_event_service.dart';

class DatabaseService {
  static const String _operatedBusinessDatesKey = 'operatedBusinessDates';
  static const String _metaBoxName = 'meta';
  static const String _userBoxName = 'users';
  static const String _tableBoxName = 'tables';
  static const String _orderBoxName = 'orders';
  static const String _packageBoxName = 'packages';
  static const String _menuBoxName = 'menu';
  static const String _settingsBoxName = 'settings';
  static const String _posIngestConnectionKeySetting = 'posIngestConnectionKey';
  static const String _salesBoxName = 'sales';
  static const String _expenseBoxName = 'expenses';
  static const String _auditLogBoxName = 'auditLog';
  static const String _errorLogBoxName = 'errorLog';
  static const String _reservationBoxName = 'reservations';
  static const String _quickOrderBoxName = 'quickOrders';
  static const String _auditReportKeyPrefix = 'audit_report_order_';
  static const String _auditLegacyPrefix = 'legacy_event_';
  static const String _restrictTableCloseToOwnerSetting =
      'restrictTableCloseToOwner';
  static const String _destructivePasswordSetting =
      'destructiveActionPasswordHash';
  static const String _destructivePasswordSaltSetting =
      'destructiveActionPasswordSalt';
  static const String _destructivePasswordUpdatedAtSetting =
      'destructiveActionPasswordUpdatedAt';
  static const String _destructivePasswordHintSetting =
      'destructiveActionPasswordHint';
  static const String _monthlyReportLeaseCostSetting = 'monthlyReportLeaseCost';
  static const String _monthlyReportStaffDailyCostSetting =
      'monthlyReportStaffDailyCost';
  static const String _monthlyReportFoodProfitRatioSetting =
      'monthlyReportFoodProfitRatio';
  static const String _monthlyReportManualSalesByMonthSetting =
      'monthlyReportManualSalesByMonth';
  static const String _monthlyReportLeaseCostByMonthSetting =
      'monthlyReportLeaseCostByMonth';
  static const String _monthlyReportStaffDailyCostByMonthSetting =
      'monthlyReportStaffDailyCostByMonth';

  static Box<User>? _userBox;
  static Box<TableModel>? _tableBox;
  static Box<Order>? _orderBox;
  static Box<MenuCategoryDB>? _menuBox;
  static Box? _settingsBox;
  static Box? _salesBox;
  static Box? _expenseBox;
  static Box? _errorLogBox;
  static Box? _auditLogBox;

  static Box getAuditLogBox() {
    if (_auditLogBox == null) {
      throw StateError('AuditLog box is not initialized');
    }
    return _auditLogBox!;
  }

  static Box<Reservation>? _reservationBox;
  static Box<QuickOrderDraft>? _quickOrderBox;
  static Box<Package>? _packageBox;
  static Box? _metaBox;
  static late String _dataDirectoryPath;
  static int _dbVersion = HiveMigrationService.initialVersion;
  static const Uuid _uuid = Uuid();

  /// Injected by ManagerSyncService so audit changes trigger a server push.
  static void Function()? _onAuditChanged;
  static void registerAuditChangedCallback(void Function() cb) {
    _onAuditChanged = cb;
  }

  /// Injected by ManagerSyncService so user/PIN changes sync to the backend.
  static void Function()? _onUsersChanged;
  static void registerUsersChangedCallback(void Function() cb) {
    _onUsersChanged = cb;
  }

  static void _notifyUsersChanged() {
    _onUsersChanged?.call();
  }

  static const int _kitchenRoutingDefaultsVersion = 2;
  static int get dbVersion => _dbVersion;

  static const List<String> _kitchenExcludedCategoryKeywords = [
    'drink',
    'drinks',
    'soft drink',
    'soft drinks',
    'alcohol',
    'alcoholic',
    'bar',
    'vodka',
    'house vodka',
    'chacha',
    'house chacha',
    'wine',
    'house wine',
    'dry wine',
    'red wine',
    'white wine',
    'sparkling wine',
    'sparkling',
    'champagne',
    'prosecco',
    'cava',
    'cognac',
    'brandy',
    'whiskey',
    'whisky',
    'bourbon',
    'scotch',
    'beer',
    'draft beer',
    'bottled beer',
    'craft beer',
    'lager',
    'ale',
    'cider',
    'gin',
    'rum',
    'tequila',
    'martini',
    'cocktail',
    'cocktails',
    'spritz',
    'aperol',
    'sangria',
    'shots',
    'shot',
    'liqueur',
    'liquor',
    'digestif',
    'aperitif',
    'energy drink',
    'energy drinks',
    'juice',
    'juices',
    'lemonade',
    'soda',
    'tonic',
    'water',
    'sparkling water',
    'still water',
    'mineral water',
    'coffee',
    'coffee and tea',
    'espresso',
    'americano',
    'cappuccino',
    'latte',
    'macchiato',
    'flat white',
    'iced coffee',
    'tea',
    'iced tea',
    'herbal tea',
    'milkshake',
    'milkshakes',
    'smoothie',
    'smoothies',
    'mocktail',
    'mocktails',
    'non-alcoholic',
    'bar menu',
  ];

  static const List<String> _firstFloorTableNumbers = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
  ];

  static const List<String> _secondFloorTableNumbers = ['1', '2', '3'];

  static const Map<String, List<String>> _tableLayout = {
    'first': _firstFloorTableNumbers,
    'second': _secondFloorTableNumbers,
  };

  static List<String> get kitchenExcludedCategoryKeywords =>
      List.unmodifiable(_kitchenExcludedCategoryKeywords);

  static Map<String, List<String>> getTableLayout() {
    return {
      for (final entry in _tableLayout.entries)
        entry.key: List<String>.from(entry.value),
    };
  }

  static List<String> getAllTableNumbers() {
    return _tableLayout.values.expand((tables) => tables).toList();
  }

  static List<OrderItem> cloneOrderItems(List<OrderItem> items) {
    return items
        .map(
          (item) => OrderItem(
            itemKey: item.itemKey,
            itemName: item.itemName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            total: item.total,
            comment: item.comment,
          ),
        )
        .toList();
  }

  // ==================== QUICK ORDER DRAFTS ====================

  static QuickOrderDraft _cloneQuickOrderDraft(QuickOrderDraft draft) {
    return QuickOrderDraft(
      id: draft.id,
      items: cloneOrderItems(draft.items),
      subtotal: draft.subtotal,
      serviceFeeAmount: draft.serviceFeeAmount,
      total: draft.total,
      includeServiceFee: draft.includeServiceFee,
      serviceFeeRate: draft.serviceFeeRate,
      createdAt: draft.createdAt,
      createdBy: draft.createdBy,
      displayName: draft.displayName,
    );
  }

  static List<QuickOrderDraft> getQuickOrderDrafts() {
    if (_quickOrderBox == null) {
      return [];
    }

    final drafts = _quickOrderBox!.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return drafts.map(_cloneQuickOrderDraft).toList();
  }

  static QuickOrderDraft? getQuickOrderDraft(String id) {
    if (_quickOrderBox == null) {
      return null;
    }

    final draft = _quickOrderBox!.get(id);
    if (draft == null) {
      return null;
    }

    return _cloneQuickOrderDraft(draft);
  }

  static Future<QuickOrderDraft> saveQuickOrderDraft({
    required String createdBy,
    required List<OrderItem> items,
    required double subtotal,
    required bool includeServiceFee,
    required double serviceFeeRate,
    String? displayName,
  }) async {
    if (_quickOrderBox == null) {
      throw StateError('Quick order storage is not initialized');
    }

    final normalizedSubtotal = double.parse(subtotal.toStringAsFixed(2));
    final includeFee = _resolveIncludeServiceFee(includeServiceFee);
    final rate = includeFee ? serviceFeeRate : 0.0;
    final serviceFeeAmount = includeFee
        ? double.parse((normalizedSubtotal * rate).toStringAsFixed(2))
        : 0.0;
    final total = double.parse(
      (normalizedSubtotal + serviceFeeAmount).toStringAsFixed(2),
    );

    final draft = QuickOrderDraft(
      id: _uuid.v4(),
      items: cloneOrderItems(items),
      subtotal: normalizedSubtotal,
      serviceFeeAmount: serviceFeeAmount,
      total: total,
      includeServiceFee: includeFee,
      serviceFeeRate: rate,
      createdAt: getCurrentDateTime(),
      createdBy: createdBy,
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : null,
    );

    await _quickOrderBox!.put(draft.id, draft);
    return _cloneQuickOrderDraft(draft);
  }

  static Future<QuickOrderDraft> updateQuickOrderDraft({
    required String id,
    required String createdBy,
    required List<OrderItem> items,
    required double subtotal,
    required bool includeServiceFee,
    required double serviceFeeRate,
    String? displayName,
  }) async {
    if (_quickOrderBox == null) {
      throw StateError('Quick order storage is not initialized');
    }

    final normalizedSubtotal = double.parse(subtotal.toStringAsFixed(2));
    final includeFee = _resolveIncludeServiceFee(includeServiceFee);
    final rate = includeFee ? serviceFeeRate : 0.0;
    final serviceFeeAmount = includeFee
        ? double.parse((normalizedSubtotal * rate).toStringAsFixed(2))
        : 0.0;
    final total = double.parse(
      (normalizedSubtotal + serviceFeeAmount).toStringAsFixed(2),
    );

    final existing = _quickOrderBox!.get(id);

    final draft = QuickOrderDraft(
      id: id,
      items: cloneOrderItems(items),
      subtotal: normalizedSubtotal,
      serviceFeeAmount: serviceFeeAmount,
      total: total,
      includeServiceFee: includeFee,
      serviceFeeRate: rate,
      createdAt: getCurrentDateTime(),
      createdBy: createdBy,
      displayName: displayName ?? existing?.displayName,
    );

    await _quickOrderBox!.put(draft.id, draft);
    return _cloneQuickOrderDraft(draft);
  }

  static Future<void> deleteQuickOrderDraft(String id) async {
    if (_quickOrderBox == null) {
      return;
    }

    await _quickOrderBox!.delete(id);
  }

  static Future<void> setQuickOrderDraftDisplayName({
    required String id,
    String? displayName,
  }) async {
    if (_quickOrderBox == null) {
      return;
    }

    final draft = _quickOrderBox!.get(id);
    if (draft == null) {
      return;
    }

    final normalized = displayName?.trim();
    draft.displayName = (normalized == null || normalized.isEmpty)
        ? null
        : normalized;
    await draft.save();
  }

  static Future<void> clearQuickOrderDrafts() async {
    if (_quickOrderBox == null) {
      return;
    }

    await _quickOrderBox!.clear();
  }

  static PackageItem _clonePackageItem(PackageItem item) {
    return PackageItem(
      itemKey: item.itemKey,
      itemName: item.itemName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );
  }

  static Package _clonePackage(Package package) {
    return Package(
      packageId: package.packageId,
      name: package.name,
      description: package.description,
      items: package.items.map(_clonePackageItem).toList(),
      pricePerPerson: package.pricePerPerson,
      isActive: package.isActive,
      createdAt: package.createdAt,
      createdBy: package.createdBy,
      servingSize: package.servingSize,
      allowedTables: List<String>.from(package.allowedTables),
    );
  }

  static List<Package> getAllPackages({bool includeInactive = true}) {
    if (_packageBox == null) {
      return [];
    }
    final packages = _packageBox!.values.where(
      (pkg) => includeInactive || pkg.isActive,
    );
    final cloned = packages.map(_clonePackage).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return cloned;
  }

  static Package? getPackageById(String packageId) {
    if (_packageBox == null) {
      return null;
    }
    final package = _packageBox!.get(packageId);
    if (package == null) {
      return null;
    }
    return _clonePackage(package);
  }

  static Future<Package> createPackage({
    required String name,
    String? description,
    required List<PackageItem> items,
    required double pricePerPerson,
    required int servingSize,
    required String createdBy,
    List<String>? allowedTables,
  }) async {
    if (_packageBox == null) {
      throw StateError('Package storage is not initialized');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Package name cannot be empty');
    }
    if (items.isEmpty) {
      throw ArgumentError('Package must include at least one item');
    }
    final normalizedPrice = double.parse(pricePerPerson.toStringAsFixed(2));
    if (normalizedPrice <= 0) {
      throw ArgumentError('Package price must be greater than zero');
    }
    final normalizedServingSize = servingSize;
    if (normalizedServingSize <= 0) {
      throw ArgumentError('Serving size must be greater than zero');
    }
    final normalizedDescription = description?.trim();
    final normalizedAllowedTables = allowedTables == null
        ? <String>[]
        : (allowedTables
              .map((table) => table.trim())
              .where((table) => table.isNotEmpty)
              .toSet()
              .toList()
            ..sort());

    final package = Package.create(
      name: trimmedName,
      description: normalizedDescription?.isEmpty == true
          ? null
          : normalizedDescription,
      items: items.map(_clonePackageItem).toList(),
      pricePerPerson: normalizedPrice,
      servingSize: normalizedServingSize,
      createdBy: createdBy,
      allowedTables: normalizedAllowedTables,
    );
    await _packageBox!.put(package.packageId, package);
    return _clonePackage(package);
  }

  static Future<Package> updatePackage({
    required String packageId,
    required String name,
    String? description,
    required List<PackageItem> items,
    required double pricePerPerson,
    required int servingSize,
    bool? isActive,
    List<String>? allowedTables,
  }) async {
    if (_packageBox == null) {
      throw StateError('Package storage is not initialized');
    }
    final existing = _packageBox!.get(packageId);
    if (existing == null) {
      throw ArgumentError('Package not found');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Package name cannot be empty');
    }
    if (items.isEmpty) {
      throw ArgumentError('Package must include at least one item');
    }
    final normalizedPrice = double.parse(pricePerPerson.toStringAsFixed(2));
    if (normalizedPrice <= 0) {
      throw ArgumentError('Package price must be greater than zero');
    }
    final normalizedServingSize = servingSize;
    if (normalizedServingSize <= 0) {
      throw ArgumentError('Serving size must be greater than zero');
    }
    final normalizedDescription = description?.trim();

    final normalizedAllowedTables = allowedTables == null
        ? List<String>.from(existing.allowedTables)
        : (allowedTables
              .map((table) => table.trim())
              .where((table) => table.isNotEmpty)
              .toSet()
              .toList()
            ..sort());

    existing
      ..name = trimmedName
      ..description = normalizedDescription?.isEmpty == true
          ? null
          : normalizedDescription
      ..items = items.map(_clonePackageItem).toList()
      ..pricePerPerson = normalizedPrice
      ..servingSize = normalizedServingSize
      ..isActive = isActive ?? existing.isActive
      ..allowedTables = normalizedAllowedTables;
    await existing.save();
    return _clonePackage(existing);
  }

  static Future<void> deletePackage(String packageId) async {
    if (_packageBox == null) {
      return;
    }
    await _packageBox!.delete(packageId);
  }

  static Future<void> setPackageActive({
    required String packageId,
    required bool isActive,
  }) async {
    if (_packageBox == null) {
      return;
    }
    final existing = _packageBox!.get(packageId);
    if (existing == null) {
      return;
    }
    existing.isActive = isActive;
    await existing.save();
  }

  static bool shouldCategorySendToKitchenByDefault(
    String? slug, {
    String? nameEn,
    String? nameKa,
  }) {
    return _shouldCategorySendToKitchen(slug, nameEn: nameEn, nameKa: nameKa);
  }

  static bool _shouldCategorySendToKitchen(
    String? slug, {
    String? nameEn,
    String? nameKa,
  }) {
    if (_matchesKitchenExclusion(slug)) {
      return false;
    }
    if (_matchesKitchenExclusion(nameEn)) {
      return false;
    }
    if (_matchesKitchenExclusion(nameKa)) {
      return false;
    }
    return true;
  }

  static bool _matchesKitchenExclusion(String? value) {
    final normalized =
        value?.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ').trim() ??
        '';
    if (normalized.isEmpty) {
      return false;
    }
    for (final keyword in _kitchenExcludedCategoryKeywords) {
      final keywordNormalized = keyword
          .toLowerCase()
          .replaceAll('-', ' ')
          .trim();
      if (keywordNormalized.isNotEmpty &&
          normalized.contains(keywordNormalized)) {
        return true;
      }
    }
    return false;
  }

  static String _sanitizeHostname(String rawHostname) {
    final normalized = rawHostname.trim().toLowerCase();
    final replaced = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final collapsed = replaced.replaceAll(RegExp(r'_+'), '_');
    final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'default' : trimmed;
  }

  // Initialize Hive and create default admin user
  static Future<void> init() async {
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

    _dataDirectoryPath = dataDirectory.path;

    // Initialize Hive with custom path unique per machine to avoid shared locks
    await Hive.initFlutter(_dataDirectoryPath);

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

    _metaBox = await Hive.openBox(_metaBoxName);

    // Open boxes
    _userBox = await Hive.openBox<User>(_userBoxName);
    _tableBox = await Hive.openBox<TableModel>(_tableBoxName);
    _orderBox = await Hive.openBox<Order>(_orderBoxName);
    _packageBox = await Hive.openBox<Package>(_packageBoxName);
    _menuBox = await Hive.openBox<MenuCategoryDB>(_menuBoxName);
    _settingsBox = await Hive.openBox(_settingsBoxName);
    _salesBox = await Hive.openBox(_salesBoxName);
    _expenseBox = await Hive.openBox(_expenseBoxName);
    _auditLogBox = await Hive.openBox(_auditLogBoxName);
    _errorLogBox = await Hive.openBox(_errorLogBoxName);
    _reservationBox = await Hive.openBox<Reservation>(_reservationBoxName);
    _quickOrderBox = await Hive.openBox<QuickOrderDraft>(_quickOrderBoxName);

    // Run schema migrations before seeding defaults.
    final migrationContext = HiveMigrationContext(
      metaBox: _metaBox!,
      userBox: _userBox!,
      tableBox: _tableBox!,
      orderBox: _orderBox!,
      menuBox: _menuBox!,
      settingsBox: _settingsBox!,
      salesBox: _salesBox!,
      auditLogBox: _auditLogBox!,
      reservationBox: _reservationBox!,
    );
    _dbVersion = await HiveMigrationService.runPendingMigrations(
      migrationContext,
    );
    await _migrateLegacyStaffRoles();

    // Initialize current date if not set
    if (!_settingsBox!.containsKey('currentDate')) {
      await _settingsBox!.put('currentDate', DateTime.now().toIso8601String());
    }

    // Initialize daily sales total if not set
    if (!_settingsBox!.containsKey('dailySalesTotal')) {
      await _settingsBox!.put('dailySalesTotal', 0.0);
    }

    if (!_settingsBox!.containsKey(_monthlyReportLeaseCostSetting)) {
      await _settingsBox!.put(_monthlyReportLeaseCostSetting, 13000.0);
    }
    if (!_settingsBox!.containsKey(_monthlyReportStaffDailyCostSetting)) {
      await _settingsBox!.put(_monthlyReportStaffDailyCostSetting, 650.0);
    }
    if (!_settingsBox!.containsKey(_monthlyReportFoodProfitRatioSetting)) {
      await _settingsBox!.put(_monthlyReportFoodProfitRatioSetting, 0.5);
    }
    if (!_settingsBox!.containsKey(_monthlyReportManualSalesByMonthSetting)) {
      await _settingsBox!.put(_monthlyReportManualSalesByMonthSetting, <String, double>{});
    }
    if (!_settingsBox!.containsKey(_monthlyReportLeaseCostByMonthSetting)) {
      await _settingsBox!.put(_monthlyReportLeaseCostByMonthSetting, <String, double>{});
    }
    if (!_settingsBox!.containsKey(_monthlyReportStaffDailyCostByMonthSetting)) {
      await _settingsBox!.put(_monthlyReportStaffDailyCostByMonthSetting, <String, double>{});
    }

    // Initialize printer configuration defaults
    if (!_settingsBox!.containsKey('printerKitchenIp')) {
      final envValue = dotenv.env['PRINTER_KITCHEN_IP'] ?? '';
      await _settingsBox!.put('printerKitchenIp', envValue.trim());
    }
    if (!_settingsBox!.containsKey('printerReceiptIp')) {
      final envValue = dotenv.env['PRINTER_RECEIPT_IP'] ?? '';
      await _settingsBox!.put('printerReceiptIp', envValue.trim());
    }
    if (!_settingsBox!.containsKey('printerPort')) {
      final defaultPort =
          int.tryParse(dotenv.env['PRINTER_PORT'] ?? '9100') ?? 9100;
      await _settingsBox!.put('printerPort', defaultPort);
    }

    // Initialize service fee configuration
    if (!_settingsBox!.containsKey('serviceFeePercent')) {
      await _settingsBox!.put('serviceFeePercent', 10.0);
    }
    if (!_settingsBox!.containsKey('serviceFeeEnabled')) {
      await _settingsBox!.put('serviceFeeEnabled', true);
    }

    // Initialize localization defaults
    if (!_settingsBox!.containsKey('defaultLanguage')) {
      final language = (dotenv.env['DEFAULT_LANGUAGE'] ?? 'ka').toLowerCase();
      await _settingsBox!.put(
        'defaultLanguage',
        (language == 'en' || language == 'ka') ? language : 'ka',
      );
    }

    // Create default admin user if no users exist
    if (_userBox!.isEmpty) {
      await createDefaultAdmin();
    }

    // Initialize tables if empty
    if (_tableBox!.isEmpty) {
      await _initializeTables();
    }
    await _ensureTableLayoutConsistency();

    // Initialize menu from JSON if empty
    if (_menuBox!.isEmpty) {
      await _initializeMenuFromJson();
    }

    final appliedVersion =
        (_settingsBox!.get('kitchenRoutingDefaultsVersion') as int?) ?? 0;
    if (appliedVersion < _kitchenRoutingDefaultsVersion) {
      await _applyKitchenRoutingDefaults();
      await _settingsBox!.put(
        'kitchenRoutingDefaultsVersion',
        _kitchenRoutingDefaultsVersion,
      );
    }

    Order.serviceFeeRateResolver = () => getServiceFeeRate();
    Order.timestampResolver = () => getCurrentDateTime();

    // Initialize Event-based Audit system
    AuditEventService.initialize();

    // One-time cleanup: older data may contain multiple OPEN reports
    // for the same floor + table set. Keep newest open, close the rest.
    await _runAuditDuplicateOpenCleanupOnce();
  }

  /// Shared secret for server → POS HTTP callbacks (`x-connection-key`).
  static String ensurePosIngestConnectionKey() {
    final fromEnv = dotenv.env['POS_CONNECTION_KEY']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      _settingsBox?.put(_posIngestConnectionKeySetting, fromEnv);
      return fromEnv;
    }
    final existing =
        _settingsBox?.get(_posIngestConnectionKeySetting) as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _uuid.v4().replaceAll('-', '');
    _settingsBox?.put(_posIngestConnectionKeySetting, generated);
    return generated;
  }

  static String? getPosIngestConnectionKey() {
    final fromEnv = dotenv.env['POS_CONNECTION_KEY']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return _settingsBox?.get(_posIngestConnectionKeySetting) as String?;
  }

  static Map<String, dynamic> serializeReservationForSync(Reservation reservation) {
    return _serializeReservation(reservation);
  }

  /// Maps legacy Hive `admin` role to `manager`.
  static Future<void> _migrateLegacyStaffRoles() async {
    if (_userBox == null) return;
    for (final user in _userBox!.values) {
      if (user.role.trim().toLowerCase() == 'admin') {
        user.role = 'manager';
        await user.save();
      }
    }
  }

  // Create default manager user
  static Future<void> createDefaultAdmin() async {
    final manager = User(
      username: 'vaanskii',
      pinCode: '000000',
      role: 'manager',
    );
    await _userBox!.add(manager);
  }

  // Add a new user
  static Future<bool> addUser({
    required String username,
    required String pinCode,
    required String role,
  }) async {
    // Check if PIN code already exists
    if (isPinCodeExists(pinCode)) {
      return false; // PIN code must be unique
    }

    final user = User(username: username, pinCode: pinCode, role: role);

    await _userBox!.add(user);
    _notifyUsersChanged();
    return true;
  }

  // Check if a PIN code already exists
  static bool isPinCodeExists(String pinCode) {
    return _userBox!.values.any((user) => user.pinCode == pinCode);
  }

  // Authenticate user by PIN code
  static User? authenticateByPin(String pinCode) {
    try {
      return _userBox!.values.firstWhere((user) => user.pinCode == pinCode);
    } catch (e) {
      return null; // User not found
    }
  }

  // Get all users
  static List<User> getAllUsers() {
    return _userBox!.values.toList();
  }

  // Get user by username
  static User? getUserByUsername(String username) {
    try {
      return _userBox!.values.firstWhere((user) => user.username == username);
    } catch (e) {
      return null;
    }
  }

  static String getDisplayOperatorName(
    String? username, {
    bool isEnglish = false,
  }) {
    final trimmed = (username ?? '').trim();
    if (trimmed.isEmpty) {
      return '-';
    }

    final user = getUserByUsername(trimmed);
    if (user != null && user.isManager) {
      return isEnglish ? 'System' : 'სისტემა';
    }

    final normalized = trimmed.toLowerCase();
    if (normalized == 'admin' ||
        normalized == 'administrator' ||
        normalized == 'superadmin' ||
        normalized == 'manager' ||
        normalized == 'მენეჯერი' ||
        normalized == 'ადმინი' ||
        normalized == 'ადმინისტრატორი') {
      return isEnglish ? 'System' : 'სისტემა';
    }

    return trimmed;
  }

  // Update user
  static Future<void> updateUser(User user) async {
    await user.save();
  }

  static Future<bool> renameUserByUsername({
    required String oldUsername,
    required String newUsername,
  }) async {
    final trimmed = newUsername.trim();
    if (trimmed.isEmpty) return false;

    final user = getUserByUsername(oldUsername);
    if (user == null) return false;

    if (trimmed != oldUsername && getUserByUsername(trimmed) != null) {
      return false;
    }

    user.username = trimmed;
    await user.save();
    _notifyUsersChanged();
    return true;
  }

  static Future<bool> updateUserPinByUsername({
    required String username,
    required String pinCode,
  }) async {
    final user = getUserByUsername(username);
    if (user == null) return false;
    final pinUsedByAnother = _userBox!.values.any(
      (u) => u.username != username && u.pinCode == pinCode,
    );
    if (pinUsedByAnother) return false;
    user.pinCode = pinCode;
    await user.save();
    _notifyUsersChanged();
    return true;
  }

  // Delete user
  static Future<void> deleteUser(User user) async {
    await user.delete();
    _notifyUsersChanged();
  }

  static Future<bool> deleteUserByUsername(String username) async {
    final user = getUserByUsername(username);
    if (user == null) return false;
    if (user.isManager) {
      final activeManagers = _userBox!.values.where((u) => u.isManager).length;
      if (activeManagers <= 1) {
        return false;
      }
    }
    await user.delete();
    _notifyUsersChanged();
    return true;
  }

  // Get users box
  static Box<User>? get userBox => _userBox;

  // ========== TABLE MANAGEMENT ==========

  // Initialize default tables
  static Future<void> _initializeTables() async {
    for (final tableNumber in _firstFloorTableNumbers) {
      final table = TableModel(
        tableNumber: tableNumber,
        floor: 'first',
        isReserved: false,
      );
      await _tableBox!.add(table);
    }

    for (final tableNumber in _secondFloorTableNumbers) {
      final table = TableModel(
        tableNumber: tableNumber,
        floor: 'second',
        isReserved: false,
      );
      await _tableBox!.add(table);
    }
  }

  static Future<void> _ensureTableLayoutConsistency() async {
    if (_tableBox == null) {
      return;
    }

    final allowedByFloor = <String, Set<String>>{};
    for (final entry in _tableLayout.entries) {
      allowedByFloor[entry.key] = entry.value.toSet();
    }

    final invalidKeys = <dynamic>[];
    for (final key in _tableBox!.keys) {
      final TableModel? table = _tableBox!.get(key);
      if (table == null) {
        invalidKeys.add(key);
        continue;
      }

      final allowedSet = allowedByFloor[table.floor];
      final isAllowed =
          allowedSet != null && allowedSet.contains(table.tableNumber);
      if (!isAllowed) {
        invalidKeys.add(key);
      }
    }

    if (invalidKeys.isNotEmpty) {
      await _tableBox!.deleteAll(invalidKeys);
    }

    for (final entry in _tableLayout.entries) {
      for (final tableNumber in entry.value) {
        if (getTable(tableNumber, entry.key) == null) {
          final table = TableModel(
            tableNumber: tableNumber,
            floor: entry.key,
            isReserved: false,
          );
          await _tableBox!.add(table);
        }
      }
    }
  }

  // Get all tables
  static List<TableModel> getAllTables() {
    return _tableBox!.values.toList();
  }

  // Get tables by floor
  static List<TableModel> getTablesByFloor(String floor) {
    return _tableBox!.values.where((table) => table.floor == floor).toList();
  }

  // Get table by number and floor
  static TableModel? getTable(String tableNumber, String floor) {
    try {
      return _tableBox!.values.firstWhere(
        (table) => table.tableNumber == tableNumber && table.floor == floor,
      );
    } catch (e) {
      return null;
    }
  }

  static bool isTableConfigured({
    required String tableNumber,
    required String floor,
  }) {
    final layout = _tableLayout[floor];
    if (layout == null) {
      return false;
    }
    return layout.contains(tableNumber);
  }

  // Reserve a table
  static Future<void> reserveTable({
    required String tableNumber,
    required String floor,
    required String username,
    required int orderId,
    String? reservationId,
  }) async {
    final table = getTable(tableNumber, floor);
    if (table != null) {
      table.reserve(username, orderId, reservationId: reservationId);
      await table.save();
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.tables,
          action: 'reserved',
          payload: {
            'tableNumber': tableNumber,
            'floor': floor,
            'orderId': orderId,
            if (reservationId != null) 'reservationId': reservationId,
          },
        ),
      );
    }
  }

  // Reserve a table for a reservation (without an order)
  static Future<void> reserveTableForReservation({
    required String tableNumber,
    required String floor,
    required String username,
    required String reservationId,
  }) async {
    final table = getTable(tableNumber, floor);
    if (table != null) {
      table.reserveForReservation(username, reservationId);
      await table.save();
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.tables,
          action: 'reserved',
          payload: {
            'tableNumber': tableNumber,
            'floor': floor,
            'reservationId': reservationId,
          },
        ),
      );
    }
  }

  // Free a table
  static Future<void> freeTable({
    required String tableNumber,
    required String floor,
  }) async {
    final table = getTable(tableNumber, floor);
    if (table != null) {
      table.free();
      await table.save();
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.tables,
          action: 'freed',
          payload: {'tableNumber': tableNumber, 'floor': floor},
        ),
      );
    }
  }

  static Reservation? _findReservationById(String reservationId) {
    if (_reservationBox == null) {
      return null;
    }
    try {
      return _reservationBox!.values.firstWhere(
        (reservation) => reservation.id == reservationId,
      );
    } catch (_) {
      return null;
    }
  }

  // Public helper to fetch reservation by ID (used by UI overlays)
  static Reservation? findReservationById(String reservationId) {
    return _findReservationById(reservationId);
  }

  static int? _resolveReservationTableNumber(TableModel table) {
    final parsed = int.tryParse(table.tableNumber.trim());
    if (parsed == null) {
      return null;
    }
    if (table.floor == 'second') {
      return parsed + 10;
    }
    return parsed;
  }

  static bool _orderContainsTable(Order order, TableModel table) {
    final identifiers = <String>{};
    final base = table.tableNumber.trim();
    if (base.isEmpty) {
      return false;
    }
    identifiers.add(base);
    identifiers.add('Table $base');
    if (table.floor == 'second') {
      identifiers.add('VIP Zone $base');
      final numeric = int.tryParse(base);
      if (numeric != null) {
        identifiers.add((numeric + 10).toString());
      }
    }
    for (final value in order.tableNumbers) {
      final normalized = value.trim();
      if (identifiers.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  static String? _normalizeTableIdentifier(String rawValue, String floor) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('table ')) {
      final extracted = trimmed.substring(6).trim();
      return extracted.isEmpty ? null : extracted;
    }

    if (lower.startsWith('vip zone ')) {
      final extracted = trimmed.substring(9).trim();
      return extracted.isEmpty ? null : extracted;
    }

    final parsed = int.tryParse(trimmed);
    if (parsed != null && floor == 'second' && parsed > 10) {
      return (parsed - 10).toString();
    }

    return trimmed;
  }

  static Map<String, dynamic> _analyzeReservedTable(
    TableModel table,
    String todayKey,
  ) {
    final result = <String, dynamic>{
      'tableNumber': table.tableNumber,
      'floor': table.floor,
      'reservedBy': table.reservedBy,
      'reservedAt': table.reservedAt?.toIso8601String(),
      'activeOrderId': table.activeOrderId,
      'reservationId': table.reservationId,
      'shouldRelease': false,
      'reason': null,
    };

    final orderId = table.activeOrderId;
    bool hasActiveOrder = false;
    if (orderId != null) {
      final order = getOrder(orderId);
      result['orderStatus'] = order?.status;
      result['orderCreatedAt'] = order?.createdAt.toIso8601String();
      if (order == null) {
        result['shouldRelease'] = true;
        result['reason'] = 'Order #$orderId missing';
        return result;
      }

      final status = order.status.toLowerCase();
      final orderDateKey = order.createdAt.toIso8601String().split('T')[0];
      final isActiveStatus =
          status != 'closed' && status != 'cancelled' && status != 'paid';
      final includesTable = _orderContainsTable(order, table);

      if (!isActiveStatus) {
        result['shouldRelease'] = true;
        result['reason'] = 'Order #$orderId is $status';
        return result;
      }

      if (orderDateKey != todayKey) {
        result['shouldRelease'] = true;
        result['reason'] = 'Order #$orderId is from $orderDateKey';
        return result;
      }

      if (!includesTable) {
        result['shouldRelease'] = true;
        result['reason'] = 'Order #$orderId no longer uses table';
        return result;
      }

      hasActiveOrder = true;
    }

    final reservationId = table.reservationId;
    if (reservationId != null) {
      final reservation = _findReservationById(reservationId);
      result['reservationStatus'] = reservation?.status;
      result['reservationDate'] = reservation?.reservationDate
          .toIso8601String();
      if (reservation == null) {
        if (!hasActiveOrder) {
          result['shouldRelease'] = true;
          result['reason'] = 'Reservation $reservationId missing';
        }
        return result;
      }

      if (hasActiveOrder) {
        return result;
      }

      final status = reservation.status.toLowerCase();
      final allowedStatuses = {'in-progress', 'confirmed', 'preparing'};
      if (!allowedStatuses.contains(status)) {
        result['shouldRelease'] = true;
        result['reason'] = 'Reservation $reservationId is $status';
        return result;
      }

      final resDateKey = reservation.reservationDate.toIso8601String().split(
        'T',
      )[0];
      if (resDateKey != todayKey) {
        result['shouldRelease'] = true;
        result['reason'] = 'Reservation $reservationId date $resDateKey';
        return result;
      }

      final normalizedTable = _resolveReservationTableNumber(table);
      if (normalizedTable == null ||
          !reservation.tableNumbers.contains(normalizedTable)) {
        result['shouldRelease'] = true;
        result['reason'] = 'Reservation $reservationId lost table link';
        return result;
      }

      return result;
    }

    if (!hasActiveOrder) {
      result['shouldRelease'] = true;
      result['reason'] = 'No active order or reservation';
    }

    return result;
  }

  static List<Map<String, dynamic>> getReservedTableDiagnostics() {
    if (_tableBox == null) {
      return const [];
    }
    final todayKey = getCurrentDate().toIso8601String().split('T')[0];
    return _tableBox!.values
        .where((table) => table.isReserved)
        .map((table) => _analyzeReservedTable(table, todayKey))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> releaseStaleReservedTables() async {
    if (_tableBox == null) {
      return const [];
    }
    final todayKey = getCurrentDate().toIso8601String().split('T')[0];
    final reservedTables = _tableBox!.values
        .where((table) => table.isReserved)
        .toList();
    final released = <Map<String, dynamic>>[];

    for (final table in reservedTables) {
      final analysis = _analyzeReservedTable(table, todayKey);
      if (analysis['shouldRelease'] == true) {
        released.add(analysis);
        await freeTable(tableNumber: table.tableNumber, floor: table.floor);
      }
    }

    return released;
  }

  static Future<void> syncTableReservationsForCurrentDate() async {
    if (_tableBox == null || _orderBox == null) {
      return;
    }

    final currentDateKey = getCurrentDate().toIso8601String().split('T')[0];

    // Step 1: clear table locks that do not belong to the selected business date.
    await releaseStaleReservedTables();

    // Step 2: ensure active orders of selected date are reflected on table map.
    final activeOrdersForDate = _orderBox!.values.where((order) {
      if (!_isOrderStatusActive(order.status)) {
        return false;
      }
      final orderDateKey = order.createdAt.toIso8601String().split('T')[0];
      return orderDateKey == currentDateKey;
    });

    for (final order in activeOrdersForDate) {
      for (final rawTableNumber in order.tableNumbers) {
        final normalizedTableNumber = _normalizeTableIdentifier(
          rawTableNumber,
          order.floor,
        );
        if (normalizedTableNumber == null || normalizedTableNumber.isEmpty) {
          continue;
        }

        if (!isTableConfigured(
          tableNumber: normalizedTableNumber,
          floor: order.floor,
        )) {
          continue;
        }

        final table = getTable(normalizedTableNumber, order.floor);
        if (table == null) {
          continue;
        }

        final occupiedByAnotherOrder =
            table.isReserved &&
            table.activeOrderId != null &&
            table.activeOrderId != order.orderId;
        if (occupiedByAnotherOrder) {
          continue;
        }

        final alreadyBoundToOrder =
            table.isReserved && table.activeOrderId == order.orderId;
        if (alreadyBoundToOrder) {
          continue;
        }

        await reserveTable(
          tableNumber: normalizedTableNumber,
          floor: order.floor,
          username: order.createdBy,
          orderId: order.orderId,
        );
      }
    }
  }

  // ========== ORDER MANAGEMENT ==========

  // Get next order ID
  static int _getNextOrderId() {
    final stored = _settingsBox?.get('lastOrderId') as int?;
    var maxExisting = 0;
    if (_orderBox != null && _orderBox!.isNotEmpty) {
      maxExisting = _orderBox!.values
          .map((o) => o.orderId)
          .reduce((a, b) => a > b ? a : b);
    }
    final base = [stored ?? 0, maxExisting].reduce((a, b) => a > b ? a : b);
    return base + 1;
  }

  // Create a new order
  static Future<Order> createOrder({
    required List<String> tableNumbers,
    required String floor,
    required String createdBy,
    required List<OrderItem> items,
    bool? includeServiceFee,
    bool createReservationRecord = true,
  }) async {
    final normalizedTables = <String>[];
    final seenTables = <String>{};
    for (final raw in tableNumbers) {
      final normalized = _normalizeTableIdentifier(raw, floor);
      if (normalized == null) {
        continue;
      }
      if (seenTables.add(normalized)) {
        normalizedTables.add(normalized);
      }
    }

    if (normalizedTables.isEmpty) {
      throw ArgumentError('Select at least one table');
    }

    for (final tableNumber in normalizedTables) {
      final table = getTable(tableNumber, floor);
      if (table != null && table.isReserved) {
        final details = StringBuffer(
          'Table $tableNumber on $floor floor is busy',
        );
        if (table.activeOrderId != null) {
          details.write(' (order #${table.activeOrderId})');
        } else if (table.reservationId != null) {
          details.write(' (reservation ${table.reservationId})');
        }
        throw StateError(details.toString());
      }
    }

    final orderTableNumbers = List<String>.from(normalizedTables);
    final orderId = _getNextOrderId();
    final shouldIncludeServiceFee =
        includeServiceFee ?? defaultIncludeServiceFee();
    final order = Order(
      orderId: orderId,
      tableNumbers: orderTableNumbers,
      floor: floor,
      items: items,
      totalAmount: 0,
      createdAt: getCurrentDateTime(),
      createdBy: createdBy,
      status: 'pending',
      includeServiceFee: shouldIncludeServiceFee,
      openedByUserId: createdBy, // Set owner when table is created
    );
    order.recalculateTotal();

    await _orderBox!.add(order);
    await _settingsBox?.put('lastOrderId', orderId);

    // Reserve tables
    for (final tableNumber in orderTableNumbers) {
      await reserveTable(
        tableNumber: tableNumber,
        floor: floor,
        username: createdBy,
        orderId: orderId,
        reservationId: null,
      );
    }

    if (createReservationRecord) {
      final tableNumList = <int>[];
      for (final tableName in orderTableNumbers) {
        if (tableName.startsWith('Table ')) {
          final parsed = int.tryParse(tableName.replaceAll('Table ', ''));
          if (parsed != null) {
            tableNumList.add(parsed);
          }
        } else if (tableName.startsWith('VIP Zone ')) {
          final parsed = int.tryParse(tableName.replaceAll('VIP Zone ', ''));
          if (parsed != null) {
            tableNumList.add(10 + parsed);
          }
        } else {
          final parsed = int.tryParse(tableName);
          if (parsed != null) {
            tableNumList.add(floor == 'second' ? parsed + 10 : parsed);
          }
        }
      }

      final currentDate = getCurrentDate();
      final currentTime = getCurrentDateTime();
      final timeString =
          '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}';

      await createReservation(
        customerName: 'Walk-in',
        customerPhone: '-',
        tableNumbers: tableNumList,
        reservationDate: currentDate,
        reservationTime: timeString,
        numberOfGuests: 0,
        notes: 'Order #$orderId',
        createdBy: createdBy,
        linkedOrderId: orderId,
      );
    }

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': orderId},
      ),
    );

    debugPrint('[Audit] Logging ORDER_CREATED for order $orderId');
    unawaited(
      AuditEventService.logEvent(
        action: 'ORDER_CREATED',
        userId: createdBy,
        data: {
          'orderId': orderId,
          'tableNumbers': tableNumbers,
          'total': order.totalAmount,
          'floor': floor,
        },
      ),
    );

    final creationTimestamp = order.createdAt;
    final initialEvents = order.items
        .map(
          (item) => AuditEvent(
            type: AuditEventType.addItem,
            itemName: item.itemName,
            previousQty: 0,
            newQty: item.quantity,
            waiterId: order.createdBy,
            waiterName: order.createdBy,
            timestamp: creationTimestamp,
          ),
        )
        .toList();

    if (initialEvents.isNotEmpty) {
      await appendOrderAuditEvents(orderId: orderId, events: initialEvents);
    } else {
      await _ensureAuditReport(orderId: orderId, orderSnapshot: order);
    }

    await _finalizeConflictingOpenAuditReports(
      currentOrderId: orderId,
      floor: floor,
      tableNumbers: orderTableNumbers,
      closedBy: createdBy,
    );

    return order;
  }

  static Future<Order> createTakeAwayOrder({
    required String customerName,
    required String customerPhone,
    required String pickupTime,
    String? notes,
    required List<OrderItem> items,
    required String createdBy,
  }) async {
    final orderId = _getNextOrderId();
    final order = Order(
      orderId: orderId,
      tableNumbers: ['TA-$orderId'],
      floor: 'takeaway',
      items: items,
      totalAmount: 0,
      createdAt: getCurrentDateTime(),
      createdBy: createdBy,
      status: 'pending',
      includeServiceFee: false,
    );
    order.recalculateTotal();

    await _orderBox!.add(order);

    final today = getCurrentDate();
    final totalGuests = items.fold<int>(0, (sum, item) => sum + item.quantity);

    await createReservation(
      customerName: customerName,
      customerPhone: customerPhone,
      tableNumbers: const [],
      reservationDate: today,
      reservationTime: pickupTime,
      numberOfGuests: totalGuests,
      notes: notes?.isNotEmpty == true
          ? '${notes!.trim()} (Order #$orderId)'
          : 'Take-away Order #$orderId',
      createdBy: createdBy,
      preOrderItems: items,
      isTakeAway: true,
      linkedOrderId: orderId,
      status: 'confirmed',
    );

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': orderId, 'takeAway': true},
      ),
    );

    unawaited(
      AuditEventService.logEvent(
        action: 'TAKEAWAY_ORDER_CREATED',
        userId: createdBy,
        data: {
          'orderId': orderId,
          'customerName': customerName,
          'total': order.totalAmount,
        },
      ),
    );

    return order;
  }

  /// Mobile/cloud takeaway with a fixed `posOrderId` from the backend counter.
  static Future<Order?> upsertMobileTakeawayOrder({
    required int posOrderId,
    required String customerName,
    required String pickupTime,
    required String waiterName,
    required List<OrderItem> items,
    double? totalAmount,
  }) async {
    final existing = getOrder(posOrderId);
    if (existing != null) {
      existing.items = items;
      if (totalAmount != null) {
        existing.totalAmount = totalAmount;
      } else {
        existing.recalculateTotal();
      }
      existing.updatedAt = getCurrentDateTime();
      await existing.save();
      return existing;
    }

    final order = Order(
      orderId: posOrderId,
      tableNumbers: ['TA-$posOrderId'],
      floor: 'takeaway',
      items: items,
      totalAmount: totalAmount ?? 0,
      createdAt: getCurrentDateTime(),
      createdBy: waiterName,
      // Mobile-originated takeaway orders are auto-confirmed (skip manual
      // "შეკვეთის დადასტურება" step on POS) so the kitchen check fires immediately.
      status: 'confirmed',
      includeServiceFee: false,
    );
    if (totalAmount == null) {
      order.recalculateTotal();
    }

    await _orderBox!.add(order);
    final lastId = (_settingsBox?.get('lastOrderId') as int?) ?? 0;
    if (posOrderId > lastId) {
      await _settingsBox?.put('lastOrderId', posOrderId);
    }

    final guestCount = items.fold<int>(0, (sum, item) => sum + item.quantity);
    await createReservation(
      customerName: customerName.isNotEmpty ? customerName : 'Takeaway',
      customerPhone: '-',
      tableNumbers: const [],
      reservationDate: getCurrentDate(),
      reservationTime: pickupTime,
      numberOfGuests: guestCount > 0 ? guestCount : 1,
      notes: 'Take-away Order #$posOrderId (mobile)',
      createdBy: waiterName,
      preOrderItems: items,
      isTakeAway: true,
      linkedOrderId: posOrderId,
      status: 'confirmed',
    );

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': posOrderId, 'takeAway': true, 'source': 'mobile'},
      ),
    );

    return order;
  }

  /// Mobile/cloud dine-in (walk-in) order with a fixed `posOrderId`. Reserves
  /// the chosen tables and records a walk-in reservation, mirroring a POS
  /// walk-in created locally.
  static Future<Order?> upsertMobileDineInOrder({
    required int posOrderId,
    required List<String> tableNumbers,
    required String floor,
    required String waiterName,
    required List<OrderItem> items,
    int guestCount = 0,
    double? totalAmount,
  }) async {
    final existing = getOrder(posOrderId);
    if (existing != null) {
      existing.items = items;
      if (totalAmount != null) {
        existing.totalAmount = totalAmount;
      } else {
        existing.recalculateTotal();
      }
      existing.updatedAt = getCurrentDateTime();
      await existing.save();
      return existing;
    }

    final normalizedTables = <String>[];
    final seenTables = <String>{};
    for (final raw in tableNumbers) {
      final normalized = _normalizeTableIdentifier(raw, floor);
      if (normalized == null) continue;
      if (seenTables.add(normalized)) {
        normalizedTables.add(normalized);
      }
    }
    if (normalizedTables.isEmpty) {
      return null;
    }

    final order = Order(
      orderId: posOrderId,
      tableNumbers: normalizedTables,
      floor: floor,
      items: items,
      totalAmount: totalAmount ?? 0,
      createdAt: getCurrentDateTime(),
      createdBy: waiterName,
      // Mobile-originated walk-in orders are auto-confirmed (skip manual
      // "შეკვეთის დადასტურება" step on POS) so the kitchen check fires immediately.
      status: 'confirmed',
      includeServiceFee: false,
      openedByUserId: waiterName,
    );
    if (totalAmount == null) {
      order.recalculateTotal();
    }

    await _orderBox!.add(order);
    final lastId = (_settingsBox?.get('lastOrderId') as int?) ?? 0;
    if (posOrderId > lastId) {
      await _settingsBox?.put('lastOrderId', posOrderId);
    }

    for (final tableNumber in normalizedTables) {
      await reserveTable(
        tableNumber: tableNumber,
        floor: floor,
        username: waiterName,
        orderId: posOrderId,
        reservationId: null,
      );
    }

    final tableNumList = <int>[];
    for (final tableName in normalizedTables) {
      if (tableName.startsWith('Table ')) {
        final parsed = int.tryParse(tableName.replaceAll('Table ', ''));
        if (parsed != null) tableNumList.add(parsed);
      } else if (tableName.startsWith('VIP Zone ')) {
        final parsed = int.tryParse(tableName.replaceAll('VIP Zone ', ''));
        if (parsed != null) tableNumList.add(10 + parsed);
      } else {
        final parsed = int.tryParse(tableName);
        if (parsed != null) {
          tableNumList.add(floor == 'second' ? parsed + 10 : parsed);
        }
      }
    }
    final currentTime = getCurrentDateTime();
    final timeString =
        '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}';
    await createReservation(
      customerName: 'Walk-in',
      customerPhone: '-',
      tableNumbers: tableNumList,
      reservationDate: getCurrentDate(),
      reservationTime: timeString,
      numberOfGuests: guestCount,
      notes: 'Order #$posOrderId',
      createdBy: waiterName,
      preOrderItems: items,
      linkedOrderId: posOrderId,
      status: 'confirmed',
    );

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': posOrderId, 'source': 'mobile'},
      ),
    );

    return order;
  }

  static Future<Order> createOrderForPackage({
    required Package package,
    required List<String> tableNumbers,
    required String floor,
    required int guestCount,
    required String createdBy,
  }) async {
    if (guestCount <= 0) {
      throw ArgumentError('Guest count must be greater than zero');
    }

    final uniqueTables = <String>[];
    for (final raw in tableNumbers) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (!uniqueTables.contains(trimmed)) {
        uniqueTables.add(trimmed);
      }
    }

    if (uniqueTables.isEmpty) {
      throw ArgumentError('Select at least one table');
    }

    if (!package.isActive) {
      throw StateError('Activate the package before assigning it to tables');
    }

    if (package.allowedTables.isNotEmpty) {
      final disallowed = uniqueTables
          .where((table) => !package.allowedTables.contains(table))
          .toList();
      if (disallowed.isNotEmpty) {
        throw StateError(
          'Package is not available for tables ${disallowed.join(", ")}',
        );
      }
    }

    final conflictedTables = <String>{};
    for (final order in _orderBox!.values) {
      if (!_isOrderStatusActive(order.status)) {
        continue;
      }
      if (order.floor != floor) {
        continue;
      }
      if (order.tableNumbers.any(uniqueTables.contains)) {
        conflictedTables.addAll(
          order.tableNumbers.where(uniqueTables.contains),
        );
      }
    }

    if (conflictedTables.isNotEmpty) {
      final sorted = conflictedTables.toList()..sort();
      final suffix = sorted.length > 1 ? 's' : '';
      final verb = sorted.length > 1 ? 'have' : 'has';
      throw StateError(
        'Table$suffix ${sorted.join(", ")} already $verb an active order',
      );
    }

    final includeServiceForPackage = defaultIncludeServiceFee();

    final order = await createOrder(
      tableNumbers: uniqueTables,
      floor: floor,
      createdBy: createdBy,
      items: <OrderItem>[],
      includeServiceFee: includeServiceForPackage,
    );

    final packageItems = package.items
        .map(
          (item) => OrderItem(
            itemKey: item.itemKey,
            itemName: item.itemName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            total: double.parse(
              (item.unitPrice * item.quantity).toStringAsFixed(2),
            ),
          ),
        )
        .toList();

    order.packageId = package.packageId;
    order.packageName = package.name;
    order.packageUnitPrice = package.pricePerPerson;
    order.packageGuestCount = guestCount;
    order.packageItems = packageItems;
    order.packagePrice = double.parse(
      (package.pricePerPerson * guestCount).toStringAsFixed(2),
    );
    order.includeServiceFee = includeServiceForPackage;
    order.updatedAt = getCurrentDateTime();

    await updateOrder(order);
    await updateOrderStatus(orderId: order.orderId, status: 'confirmed');

    return order;
  }

  // Get order by ID
  static Order? getOrder(int orderId) {
    try {
      return _orderBox!.values.firstWhere((order) => order.orderId == orderId);
    } catch (e) {
      return null;
    }
  }

  // Get all orders
  static List<Order> getAllOrders() {
    return _orderBox!.values.toList();
  }

  static bool _isOrderStatusActive(String status) {
    final normalized = status.toLowerCase();
    return normalized != 'paid' &&
        normalized != 'cancelled' &&
        normalized != 'closed';
  }

  // Get active orders (not paid or cancelled)
  static List<Order> getActiveOrders() {
    return _orderBox!.values.where((order) {
      return _isOrderStatusActive(order.status);
    }).toList();
  }

  // Update order
  static Future<void> updateOrder(
    Order order, {
    bool? previousIncludeServiceFee,
  }) async {
    order.recalculateTotal();

    Order? original;
    if (order.isInBox) {
      original = order;
    } else {
      try {
        original = _orderBox!.values.firstWhere(
          (o) => o.orderId == order.orderId,
        );
      } catch (e) {
        // If not found, we can't update
        return;
      }
    }

    final prevIncludeServiceFee =
        previousIncludeServiceFee ?? original.includeServiceFee;

    if (original != order) {
      original.items = order.items;
      original.totalAmount = order.totalAmount;
      original.includeServiceFee = order.includeServiceFee;
      original.discountAmount = order.discountAmount;
      original.manualAdjustmentAmount = order.manualAdjustmentAmount;
      original.updatedAt = order.updatedAt;
      original.status = order.status;
      original.paymentMethod = order.paymentMethod;
      original.closedAt = order.closedAt;
      original.packageId = order.packageId;
      original.packageName = order.packageName;
      original.packagePrice = order.packagePrice;
      original.packageItems = order.packageItems;
      original.packageUnitPrice = order.packageUnitPrice;
      original.packageGuestCount = order.packageGuestCount;
    }

    await original.save();
    final serviceFeeChanged =
        original.includeServiceFee != prevIncludeServiceFee;
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'updated',
        payload: {
          'orderId': order.orderId,
          if (serviceFeeChanged) 'serviceFeeChanged': true,
        },
      ),
    );
  }

  // Update order status
  static Future<void> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      order.updateStatus(status);
      await order.save();

      // If order is paid or cancelled, free the tables
      if (status == 'paid' || status == 'cancelled') {
        for (final tableNumber in order.tableNumbers) {
          await freeTable(tableNumber: tableNumber, floor: order.floor);
        }
      }
    }
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'status_changed',
        payload: {'orderId': orderId, 'status': status},
      ),
    );
  }

  // Hard delete an order (admin only) and release all related resources
  static Future<bool> deleteOrderAndCleanup({
    required int orderId,
    required String deletedBy,
    bool cancelLinkedReservation = true,
  }) async {
    try {
      final order = getOrder(orderId);
      if (order == null) {
        return false;
      }

      // Free all tables associated with this order
      for (final tableNumber in order.tableNumbers) {
        await freeTable(tableNumber: tableNumber, floor: order.floor);
      }

      // Cancel any linked reservation so it does not block day-close
      if (cancelLinkedReservation) {
        await cancelReservationByOrderId(orderId);
      }

      // Remove audit report snapshot if it exists
      final auditKey = _buildAuditReportKey(orderId);
      if (_auditLogBox != null && _auditLogBox!.containsKey(auditKey)) {
        await _auditLogBox!.delete(auditKey);
      }

      // Delete the order record itself
      await order.delete();

      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.orders,
          action: 'deleted',
          payload: {'orderId': orderId, 'deletedBy': deletedBy},
        ),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  // Bulk delete all open orders for a specific date. Used by admin to fix stuck day-close.
  static Future<int> deleteOpenOrdersForDate({
    required DateTime date,
    required String deletedBy,
    bool includeTakeAway = true,
  }) async {
    final targetKey = date.toIso8601String().split('T')[0];
    final allOrders = getAllOrders();

    int deletedCount = 0;

    for (final order in allOrders) {
      final status = order.status.toLowerCase();
      if (status == 'closed' || status == 'cancelled') {
        continue;
      }

      final orderKey = order.createdAt.toIso8601String().split('T')[0];
      if (orderKey != targetKey) {
        continue;
      }

      if (!includeTakeAway) {
        final floor = order.floor.toLowerCase();
        final isTakeAway =
            floor == 'takeaway' ||
            floor == 'take-away' ||
            floor.contains('take away');
        if (isTakeAway) {
          continue;
        }
      }

      final success = await deleteOrderAndCleanup(
        orderId: order.orderId,
        deletedBy: deletedBy,
      );
      if (success) {
        deletedCount++;
      }
    }

    return deletedCount;
  }

  // Add item to order
  static Future<void> addItemToOrder({
    required int orderId,
    required OrderItem item,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      order.addItem(item);
      await updateOrder(order);
    }
  }

  // Remove item from order
  static Future<void> removeItemFromOrder({
    required int orderId,
    required String itemKey,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      order.removeItem(itemKey);
      await updateOrder(order);
    }
  }

  // Update item quantity in order
  static Future<void> updateOrderItemQuantity({
    required int orderId,
    required String itemKey,
    required int quantity,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      order.updateItemQuantity(itemKey, quantity);
      await updateOrder(order);
    }
  }

  // Get tables box
  static Box<TableModel>? get tableBox => _tableBox;

  // Get orders box
  static Box<Order>? get orderBox => _orderBox;

  // ==================== MENU METHODS ====================

  // Initialize menu from JSON file
  static Future<void> _initializeMenuFromJson() async {
    try {
      final String jsonString = await rootBundle.loadString('data/menu.json');
      final List<dynamic> jsonList = json.decode(jsonString);

      for (final categoryJson in jsonList) {
        final category = _convertJsonToMenuCategory(categoryJson);
        await _menuBox!.add(category);
      }
    } catch (e) {
      developer.log(e.toString(), name: 'DatabaseService', error: e);
    }
  }

  // Convert JSON to MenuCategoryDB
  static MenuCategoryDB _convertJsonToMenuCategory(Map<String, dynamic> json) {
    final nameEn = json['translations']['en']['name'] as String;
    final nameKa = json['translations']['ka']['name'] as String;
    return MenuCategoryDB(
      slug: json['slug'] as String,
      translationsEn: {'name': nameEn},
      translationsKa: {'name': nameKa},
      sendToKitchen:
          json['sendToKitchen'] as bool? ??
          _shouldCategorySendToKitchen(
            json['slug'] as String?,
            nameEn: nameEn,
            nameKa: nameKa,
          ),
      items: json['items'] != null
          ? (json['items'] as List)
                .map((item) => _convertJsonToMenuItem(item))
                .toList()
          : null,
      subcategories: json['subcategories'] != null
          ? (json['subcategories'] as List)
                .map((sub) => _convertJsonToMenuSubcategory(sub))
                .toList()
          : null,
    );
  }

  // Convert JSON to MenuSubcategoryDB
  static MenuSubcategoryDB _convertJsonToMenuSubcategory(
    Map<String, dynamic> json,
  ) {
    return MenuSubcategoryDB(
      slug: json['slug'] as String,
      translationsEn: {'name': json['translations']['en']['name'] as String},
      translationsKa: {'name': json['translations']['ka']['name'] as String},
      items: (json['items'] as List)
          .map((item) => _convertJsonToMenuItem(item))
          .toList(),
    );
  }

  // Convert JSON to MenuItemDB
  static MenuItemDB _convertJsonToMenuItem(Map<String, dynamic> json) {
    return MenuItemDB(
      translationsEn: {'name': json['translations']['en']['name'] as String},
      translationsKa: {'name': json['translations']['ka']['name'] as String},
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      sendToKitchen: json['sendToKitchen'] as bool? ?? true,
      variants: json['variants'] != null
          ? (json['variants'] as List)
                .map((variant) => _convertJsonToMenuVariant(variant))
                .toList()
          : null,
    );
  }

  // Convert JSON to MenuVariantDB
  static MenuVariantDB _convertJsonToMenuVariant(Map<String, dynamic> json) {
    return MenuVariantDB(
      size: (json['size'] as num).toDouble(),
      price: (json['price'] as num).toDouble(),
    );
  }

  // Get all menu categories from database
  static List<MenuCategoryDB> getAllMenuCategories() {
    return _menuBox!.values.toList();
  }

  // Clear menu cache (if needed for refresh)
  static Future<void> clearMenuCache() async {
    // This is handled by Hive automatically
    // No need for explicit cache clearing
  }

  static Future<void> _applyKitchenRoutingDefaults() async {
    if (_menuBox == null || _menuBox!.isEmpty) {
      return;
    }

    bool updated = false;
    for (final category in _menuBox!.values) {
      final shouldSend = _shouldCategorySendToKitchen(
        category.slug,
        nameEn: category.translationsEn['name'],
        nameKa: category.translationsKa['name'],
      );
      if (!shouldSend && category.sendToKitchen) {
        category.sendToKitchen = false;
        await category.save();
        updated = true;
      }
    }

    if (updated) {
      developer.log(
        'Updated kitchen routing defaults for bar/drink categories',
        name: 'DatabaseService',
      );
    }
  }

  // ==================== MENU CRUD METHODS ====================

  // Add new category
  static Future<bool> addCategory({
    required String slug,
    required String nameEn,
    required String nameKa,
    bool? sendToKitchen,
  }) async {
    try {
      final category = MenuCategoryDB(
        slug: slug,
        translationsEn: {'name': nameEn},
        translationsKa: {'name': nameKa},
        items: [],
        subcategories: null,
        sendToKitchen:
            sendToKitchen ??
            _shouldCategorySendToKitchen(slug, nameEn: nameEn, nameKa: nameKa),
      );
      await _menuBox!.add(category);
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.menu,
          action: 'created',
          payload: {'slug': slug},
        ),
      );
      return true;
    } catch (e) {
      developer.log(
        'Error adding category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Update category
  static Future<bool> updateCategory({
    required int index,
    required String slug,
    required String nameEn,
    required String nameKa,
    bool? sendToKitchen,
  }) async {
    try {
      final category = _menuBox!.getAt(index);
      if (category != null) {
        category.slug = slug;
        category.translationsEn = {'name': nameEn};
        category.translationsKa = {'name': nameKa};
        category.sendToKitchen = sendToKitchen ?? category.sendToKitchen;
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'updated',
            payload: {'slug': slug},
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error updating category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Delete category
  static Future<bool> deleteCategory(int index) async {
    try {
      await _menuBox!.deleteAt(index);
      SyncHub.notify(SyncEvent(type: SyncEventType.menu, action: 'deleted'));
      return true;
    } catch (e) {
      developer.log(
        'Error deleting category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Add item to category
  static Future<bool> addItemToCategory({
    required int categoryIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
  }) async {
    try {
      final category = _menuBox!.getAt(categoryIndex);
      if (category != null) {
        final item = MenuItemDB(
          translationsEn: {'name': nameEn},
          translationsKa: {'name': nameKa},
          price: price,
          variants: variants,
          sendToKitchen: sendToKitchen ?? true,
        );
        category.items ??= [];
        category.items!.add(item);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'item_created',
            payload: {'slug': category.slug},
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error adding item to category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Update item in category
  static Future<bool> updateItemInCategory({
    required int categoryIndex,
    required int itemIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
  }) async {
    try {
      final category = _menuBox!.getAt(categoryIndex);
      if (category != null &&
          category.items != null &&
          itemIndex < category.items!.length) {
        category.items![itemIndex].translationsEn = {'name': nameEn};
        category.items![itemIndex].translationsKa = {'name': nameKa};
        category.items![itemIndex].price = price;
        category.items![itemIndex].variants = variants;
        if (sendToKitchen != null) {
          category.items![itemIndex].sendToKitchen = sendToKitchen;
        }
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'item_updated',
            payload: {'slug': category.slug},
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error updating item in category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Delete item from category
  static Future<bool> deleteItemFromCategory({
    required int categoryIndex,
    required int itemIndex,
  }) async {
    try {
      final category = _menuBox!.getAt(categoryIndex);
      if (category != null &&
          category.items != null &&
          itemIndex < category.items!.length) {
        category.items!.removeAt(itemIndex);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'item_deleted',
            payload: {'slug': category.slug},
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error deleting item from category: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Add subcategory
  static Future<bool> addSubcategory({
    required int categoryIndex,
    required String slug,
    required String nameEn,
    required String nameKa,
  }) async {
    try {
      final category = _menuBox!.getAt(categoryIndex);
      if (category != null) {
        final subcategory = MenuSubcategoryDB(
          slug: slug,
          translationsEn: {'name': nameEn},
          translationsKa: {'name': nameKa},
          items: <MenuItemDB>[],
        );
        category.subcategories ??= <MenuSubcategoryDB>[];
        category.subcategories!.add(subcategory);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'subcategory_created',
            payload: {'slug': category.slug},
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error adding subcategory: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Update subcategory
  static Future<bool> updateSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required String slug,
    required String nameEn,
    required String nameKa,
  }) async {
    try {
      final category = _menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        final subcategory = subcategories[subcategoryIndex];
        subcategory.slug = slug;
        subcategory.translationsEn = {'name': nameEn};
        subcategory.translationsKa = {'name': nameKa};
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'subcategory_updated',
            payload: {'slug': category.slug},
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error updating subcategory: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Delete subcategory
  static Future<bool> deleteSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
  }) async {
    try {
      final category = _menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        subcategories.removeAt(subcategoryIndex);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'subcategory_deleted',
            payload: {'slug': category.slug},
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error deleting subcategory: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Add item to subcategory
  static Future<bool> addItemToSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
  }) async {
    try {
      final category = _menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        final item = MenuItemDB(
          translationsEn: {'name': nameEn},
          translationsKa: {'name': nameKa},
          price: price,
          variants: variants,
          sendToKitchen: sendToKitchen ?? true,
        );
        subcategories[subcategoryIndex].items.add(item);
        await category.save();
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.menu,
            action: 'subcategory_item_created',
            payload: {'slug': category.slug},
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      developer.log(
        'Error adding item to subcategory: $e',
        name: 'DatabaseService',
        error: e,
      );
      return false;
    }
  }

  // Update item in subcategory
  static Future<bool> updateItemInSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required int itemIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
  }) async {
    try {
      final category = _menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        final items = subcategories[subcategoryIndex].items;
        if (itemIndex < items.length) {
          final item = items[itemIndex];
          item.translationsEn = {'name': nameEn};
          item.translationsKa = {'name': nameKa};
          item.price = price;
          item.variants = variants;
          if (sendToKitchen != null) {
            item.sendToKitchen = sendToKitchen;
          }
          await category.save();
          SyncHub.notify(
            SyncEvent(
              type: SyncEventType.menu,
              action: 'subcategory_item_updated',
              payload: {'slug': category.slug},
            ),
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      developer.log('Error updating subcategory item: $e');
      return false;
    }
  }

  // Delete item from subcategory
  static Future<bool> deleteItemFromSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required int itemIndex,
  }) async {
    try {
      final category = _menuBox!.getAt(categoryIndex);
      final subcategories = category?.subcategories;
      if (category != null &&
          subcategories != null &&
          subcategoryIndex < subcategories.length) {
        final items = subcategories[subcategoryIndex].items;
        if (itemIndex < items.length) {
          items.removeAt(itemIndex);
          await category.save();
          SyncHub.notify(
            SyncEvent(
              type: SyncEventType.menu,
              action: 'subcategory_item_deleted',
              payload: {'slug': category.slug},
            ),
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      developer.log('Error deleting subcategory item: $e');
      return false;
    }
  }

  // ==================== DATE MANAGEMENT METHODS ====================

  // Get current business date
  static DateTime getCurrentDate() {
    final dateString = _settingsBox!.get(
      'currentDate',
      defaultValue: DateTime.now().toIso8601String(),
    );
    return DateTime.parse(dateString as String);
  }

  static DateTime getCurrentDateTime() {
    final businessDate = getCurrentDate();
    final now = DateTime.now();
    return DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
  }

  static double getMonthlyReportLeaseCost() {
    final stored = _settingsBox!.get(_monthlyReportLeaseCostSetting);
    if (stored is num) {
      return stored.toDouble();
    }
    return 13000.0;
  }

  static Future<void> setMonthlyReportLeaseCost(double value) async {
    await _settingsBox!.put(_monthlyReportLeaseCostSetting, value);
  }

  static double getMonthlyReportStaffDailyCost() {
    final stored = _settingsBox!.get(_monthlyReportStaffDailyCostSetting);
    if (stored is num) {
      return stored.toDouble();
    }
    return 650.0;
  }

  static Future<void> setMonthlyReportStaffDailyCost(double value) async {
    await _settingsBox!.put(_monthlyReportStaffDailyCostSetting, value);
  }

  static double getMonthlyReportFoodProfitRatio() {
    final stored = _settingsBox!.get(_monthlyReportFoodProfitRatioSetting);
    if (stored is num) {
      final ratio = stored.toDouble();
      if (ratio >= 0 && ratio <= 1) {
        return ratio;
      }
    }
    return 0.5;
  }

  static Future<void> setMonthlyReportFoodProfitRatio(double ratio) async {
    final normalized = ratio.clamp(0.0, 1.0);
    await _settingsBox!.put(_monthlyReportFoodProfitRatioSetting, normalized);
  }

  static double getMonthlyReportManualSalesForMonth(int year, int month) {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    final raw = _settingsBox!.get(_monthlyReportManualSalesByMonthSetting);
    if (raw is Map) {
      final value = raw[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  static Future<void> setMonthlyReportManualSalesForMonth(
    int year,
    int month,
    double value,
  ) async {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    final raw = _settingsBox!.get(_monthlyReportManualSalesByMonthSetting);
    final map = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final parsed = v is num ? v.toDouble() : double.tryParse(v.toString());
        if (parsed != null && parsed > 0) {
          map[k.toString()] = parsed;
        }
      });
    }
    final normalized = value.isNaN || value.isInfinite ? 0.0 : value;
    if (normalized <= 0) {
      map.remove(key);
    } else {
      map[key] = normalized;
    }
    await _settingsBox!.put(_monthlyReportManualSalesByMonthSetting, map);
  }

  static double? getMonthlyReportLeaseCostOverrideForMonth(int year, int month) {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    final raw = _settingsBox!.get(_monthlyReportLeaseCostByMonthSetting);
    if (raw is Map) {
      final value = raw[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
    }
    return null;
  }

  static Future<void> setMonthlyReportLeaseCostOverrideForMonth(
    int year,
    int month,
    double? value,
  ) async {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    final raw = _settingsBox!.get(_monthlyReportLeaseCostByMonthSetting);
    final map = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final parsed = v is num ? v.toDouble() : double.tryParse(v.toString());
        if (parsed != null && parsed > 0) {
          map[k.toString()] = parsed;
        }
      });
    }
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    await _settingsBox!.put(_monthlyReportLeaseCostByMonthSetting, map);
  }

  static double? getMonthlyReportStaffDailyCostOverrideForMonth(
    int year,
    int month,
  ) {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    final raw = _settingsBox!.get(_monthlyReportStaffDailyCostByMonthSetting);
    if (raw is Map) {
      final value = raw[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
    }
    return null;
  }

  static Future<void> setMonthlyReportStaffDailyCostOverrideForMonth(
    int year,
    int month,
    double? value,
  ) async {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    final raw = _settingsBox!.get(_monthlyReportStaffDailyCostByMonthSetting);
    final map = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final parsed = v is num ? v.toDouble() : double.tryParse(v.toString());
        if (parsed != null && parsed > 0) {
          map[k.toString()] = parsed;
        }
      });
    }
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    await _settingsBox!.put(_monthlyReportStaffDailyCostByMonthSetting, map);
  }

  static String getDataDirectoryPath() => _dataDirectoryPath;

  static Future<void> setCurrentDate(DateTime newDate) async {
    final previousDate = getCurrentDate();
    await _rememberOperatedBusinessDate(previousDate);
    await _rememberOperatedBusinessDate(newDate);
    await _settingsBox!.put('currentDate', newDate.toIso8601String());
    await syncTableReservationsForCurrentDate();
    await refreshDailySalesTotalForDate(newDate);
  }

  static List<String> _getOperatedBusinessDateKeys() {
    final stored = _settingsBox!.get(_operatedBusinessDatesKey);
    if (stored is List) {
      return stored
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  static Future<void> _rememberOperatedBusinessDate(DateTime date) async {
    final dateKey = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String().split('T')[0];
    final keys = _getOperatedBusinessDateKeys();
    if (!keys.contains(dateKey)) {
      keys.add(dateKey);
      keys.sort();
      await _settingsBox!.put(_operatedBusinessDatesKey, keys);
    }
  }

  static Future<void> refreshDailySalesTotalForDate(DateTime date) async {
    final dateString = date.toIso8601String().split('T')[0];
    final sales = getSalesForDate(dateString);
    final total = sales
        .where(
          (sale) =>
              sale['isCancelled'] != true &&
              sale['restoredToOrder'] != true &&
              sale['isFiscal'] != false,
        )
        .fold<double>(
          0,
          (sum, sale) =>
              sum + ((sale['totalAmount'] as num?)?.toDouble() ?? 0.0),
        );
    final currentDateString = getCurrentDate().toIso8601String().split('T')[0];
    if (currentDateString == dateString) {
      await _settingsBox!.put('dailySalesTotal', total);
    }
  }

  // ==================== SETTINGS MANAGEMENT ====================

  static String getKitchenPrinterIp() {
    final stored = _settingsBox!.get('printerKitchenIp');
    if (stored is String && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    return (dotenv.env['PRINTER_KITCHEN_IP'] ?? '').trim();
  }

  static String getReceiptPrinterIp() {
    final stored = _settingsBox!.get('printerReceiptIp');
    if (stored is String && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    return (dotenv.env['PRINTER_RECEIPT_IP'] ?? '').trim();
  }

  static int getPrinterPort() {
    return 9100;
  }

  static int getKitchenPrinterPort() {
    return 9100;
  }

  static int getReceiptPrinterPort() {
    return 9100;
  }

  static List<Map<String, dynamic>> getPrintersList() {
    final stored = _settingsBox!.get('printersList');
    if (stored is List) {
      return List<Map<String, dynamic>>.from(
        stored.map((item) => Map<String, dynamic>.from(item as Map)),
      );
    }
    return [];
  }

  static Future<void> savePrintersList(
    List<Map<String, dynamic>> printers,
  ) async {
    await _settingsBox!.put('printersList', printers);
    await _settingsBox!.put(
      'printerConfigUpdatedAt',
      DateTime.now().toIso8601String(),
    );
  }

  static Future<void> savePrinterConfiguration({
    required String kitchenIp,
    required String receiptIp,
    required int port,
  }) async {
    await _settingsBox!.put('printerKitchenIp', kitchenIp.trim());
    await _settingsBox!.put('printerReceiptIp', receiptIp.trim());
    await _settingsBox!.put('printerPort', port);
    await _settingsBox!.put(
      'printerConfigUpdatedAt',
      DateTime.now().toIso8601String(),
    );
  }

  static double getServiceFeePercentage() {
    if (_settingsBox == null) return 10.0; // not initialized on mobile
    final stored = _settingsBox!.get('serviceFeePercent');
    if (stored is num) {
      return stored.toDouble();
    }
    if (stored is String) {
      final parsed = double.tryParse(stored);
      if (parsed != null) {
        return parsed;
      }
    }
    return 10.0;
  }

  static double getServiceFeeRate() {
    final percent = getServiceFeePercentage();
    return percent <= 0 ? 0.0 : percent / 100.0;
  }

  static String getFormattedServiceFeePercentage({int maxFractionDigits = 1}) {
    final percent = getServiceFeePercentage();
    final precision = percent == percent.roundToDouble()
        ? 0
        : percent < 1
        ? (maxFractionDigits + 1)
        : maxFractionDigits;
    return percent.toStringAsFixed(precision);
  }

  static bool isServiceFeeEnabledByDefault() {
    if (_settingsBox == null) return false;
    final stored = _settingsBox!.get('serviceFeeEnabled');
    if (stored is bool) {
      return stored;
    }
    if (stored is String) {
      return stored.toLowerCase() == 'true';
    }
    return false;
  }

  /// True when admin enabled service fee AND percent is greater than zero.
  static bool isServiceFeeAvailable() {
    if (_settingsBox == null) return false;
    if (!isServiceFeeEnabledByDefault()) return false;
    return getServiceFeePercentage() > 0;
  }

  static bool defaultIncludeServiceFee() => isServiceFeeAvailable();

  static Future<void> updateServiceFeeSettings({
    required double percentage,
    required bool enabledByDefault,
  }) async {
    final previousPercent = getServiceFeePercentage();
    final previouslyEnabled = isServiceFeeEnabledByDefault();
    final clamped = percentage.clamp(0, 100).toDouble();
    final normalizedPercent = double.parse(clamped.toStringAsFixed(2));
    await _settingsBox!.put('serviceFeePercent', normalizedPercent);
    await _settingsBox!.put('serviceFeeEnabled', enabledByDefault);
    await _settingsBox!.put(
      'serviceFeeUpdatedAt',
      DateTime.now().toIso8601String(),
    );
    if (!enabledByDefault && previouslyEnabled != enabledByDefault) {
      await _applyServiceFeePreferenceToOpenOrders();
      await _clearServiceFeeFromQuickOrderDrafts();
    }
    final hasChanged =
        previouslyEnabled != enabledByDefault ||
        (previousPercent - normalizedPercent).abs() > 0.0001;
    if (hasChanged) {
      SyncHub.notify(
        SyncEvent(type: SyncEventType.orders, action: 'service_fee_updated'),
      );
    }
  }

  static bool hasDestructiveActionPassword() {
    final stored = _settingsBox!.get(_destructivePasswordSetting);
    return stored is String && stored.isNotEmpty;
  }

  static bool verifyDestructiveActionPassword(String input) {
    final sanitized = input.trim();
    if (sanitized.isEmpty) {
      return false;
    }
    final salt = _settingsBox!.get(_destructivePasswordSaltSetting);
    final storedHash = _settingsBox!.get(_destructivePasswordSetting);
    if (storedHash is! String || storedHash.isEmpty) {
      return false;
    }
    if (salt is! String || salt.isEmpty) {
      return false;
    }
    final candidateHash = _hashDestructivePassword(sanitized, salt);
    return _constantTimeEquals(storedHash, candidateHash);
  }

  static Future<void> setDestructiveActionPassword(
    String newPassword, {
    String hint = '',
  }) async {
    final sanitized = newPassword.trim();
    if (sanitized.isEmpty) {
      throw ArgumentError('Cancellation password cannot be empty.');
    }
    if (!RegExp(r'^[0-9]{6}$').hasMatch(sanitized)) {
      throw ArgumentError('Cancellation password must be exactly 6 digits.');
    }
    final salt = _uuid.v4().replaceAll('-', '');
    final hash = _hashDestructivePassword(sanitized, salt);
    await _settingsBox!.put(_destructivePasswordSetting, hash);
    await _settingsBox!.put(_destructivePasswordSaltSetting, salt);
    await _settingsBox!.put(_destructivePasswordHintSetting, hint.trim());
    await _settingsBox!.put(
      _destructivePasswordUpdatedAtSetting,
      DateTime.now().toIso8601String(),
    );
  }

  static DateTime? getDestructiveActionPasswordUpdatedAt() {
    final stored =
        _settingsBox!.get(_destructivePasswordUpdatedAtSetting) as String?;
    if (stored == null || stored.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(stored);
    } catch (_) {
      return null;
    }
  }

  static String getDestructiveActionPasswordHint() {
    final stored = _settingsBox!.get(_destructivePasswordHintSetting);
    if (stored is String) {
      return stored;
    }
    return '';
  }

  static Future<void> setDestructiveActionPasswordHint(String hint) async {
    await _settingsBox!.put(_destructivePasswordHintSetting, hint.trim());
    await _settingsBox!.put(
      _destructivePasswordUpdatedAtSetting,
      DateTime.now().toIso8601String(),
    );
  }

  static String _hashDestructivePassword(String value, String salt) {
    final bytes = utf8.encode('$salt::$value');
    return sha256.convert(bytes).toString();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Future<void> _applyServiceFeePreferenceToOpenOrders() async {
    if (_orderBox == null) {
      return;
    }

    final now = getCurrentDateTime();
    final pendingSaves = <Future<void>>[];

    for (final order in _orderBox!.values) {
      if (_isOrderFinalized(order.status)) {
        continue;
      }
      if (!order.includeServiceFee) {
        continue;
      }
      order.includeServiceFee = false;
      order.recalculateTotal();
      order.updatedAt = now;
      pendingSaves.add(order.save());
    }

    if (pendingSaves.isNotEmpty) {
      await Future.wait(pendingSaves);
    }
  }

  static Future<void> _clearServiceFeeFromQuickOrderDrafts() async {
    if (_quickOrderBox == null) return;
    final pending = <Future<void>>[];
    for (final draft in _quickOrderBox!.values) {
      if (!draft.includeServiceFee && draft.serviceFeeAmount <= 0) continue;
      draft.includeServiceFee = false;
      draft.serviceFeeAmount = 0;
      draft.total = draft.subtotal;
      pending.add(_quickOrderBox!.put(draft.id, draft));
    }
    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
  }

  static bool _resolveIncludeServiceFee(bool requested) {
    if (!isServiceFeeAvailable()) return false;
    return requested;
  }

  static bool _isOrderFinalized(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'paid' ||
        normalized == 'cancelled' ||
        normalized == 'closed';
  }

  static String getDefaultLanguage() {
    if (_settingsBox == null) return 'ka'; // not initialized on mobile
    final stored = (_settingsBox!.get('defaultLanguage') as String?) ?? 'ka';
    final normalized = stored.toLowerCase();
    return (normalized == 'en' || normalized == 'ka') ? normalized : 'ka';
  }

  static Future<void> setDefaultLanguage(String language) async {
    final normalized = language.toLowerCase();
    await _settingsBox!.put(
      'defaultLanguage',
      (normalized == 'en' || normalized == 'ka') ? normalized : 'ka',
    );
    await _settingsBox!.put(
      'defaultLanguageUpdatedAt',
      DateTime.now().toIso8601String(),
    );
  }

  // ========== TABLE CLOSING OWNERSHIP SETTINGS ==========

  /// Get whether table closing is restricted to the user who opened/activated it
  /// Default: false (any waiter can close any table)
  static bool isTableCloseRestrictedToOwner() {
    return _settingsBox!.get(
          _restrictTableCloseToOwnerSetting,
          defaultValue: false,
        )
        as bool;
  }

  /// Set whether table closing is restricted to the owner
  static Future<void> setTableCloseRestrictedToOwner(bool restricted) async {
    await _settingsBox!.put(_restrictTableCloseToOwnerSetting, restricted);
  }

  static Future<File> createDataBackup({String? targetFilePath}) async {
    final timestamp = DateTime.now();
    final backupFile = targetFilePath != null
        ? File(targetFilePath)
        : () {
            final backupDirectory = Directory('$_dataDirectoryPath/backups');
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
      'currentDate': getCurrentDate().toIso8601String(),
      'meta': {
        'db_version':
            _metaBox?.get(HiveMigrationService.dbVersionKey) ??
            HiveMigrationService.initialVersion,
        'last_migration_timestamp': _metaBox?.get(
          HiveMigrationService.lastMigrationKey,
        ),
      },
      'settings': {
        'serviceFeePercent': getServiceFeePercentage(),
        'serviceFeeEnabled': isServiceFeeEnabledByDefault(),
        'defaultLanguage': getDefaultLanguage(),
        'printerKitchenIp': getKitchenPrinterIp(),
        'printerReceiptIp': getReceiptPrinterIp(),
        'printerPort': getPrinterPort(),
        'knownBusinessDates': getKnownBusinessDates()
            .map((date) => date.toIso8601String())
            .toList(),
      },
      'users': _userBox!.values.map(_serializeUser).toList(),
      'tables': _tableBox!.values.map(_serializeTable).toList(),
      'orders': _orderBox!.values.map(_serializeOrder).toList(),
      'packages': _packageBox!.values.map(_serializePackage).toList(),
      'reservations': _reservationBox!.values
          .map(_serializeReservation)
          .toList(),
      'quickOrders': _quickOrderBox!.values
          .map(_serializeQuickOrderDraft)
          .toList(),
      'menu': _menuBox!.values.map(_serializeMenuCategory).toList(),
      'sales': _salesBox!.values.map(_serializeDynamicMap).toList(),
      'expenses': _expenseBox!.values.map(_serializeDynamicMap).toList(),
      'auditLog': _auditLogBox!.values.map(_serializeDynamicMap).toList(),
      'errorLog': _errorLogBox!.values.map(_serializeDynamicMap).toList(),
    };

    await backupFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(backupPayload),
    );
    return backupFile;
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
    if (_menuBox == null) {
      return [];
    }
    return _menuBox!.values.map(_serializeMenuCategory).toList();
  }

  static Future<void> importMenuFromJson(
    List<dynamic> payload, {
    bool clearExisting = false,
    bool silent = false,
  }) async {
    if (_menuBox == null) {
      return;
    }
    if (clearExisting) {
      await _menuBox!.clear();
    }
    for (final entry in payload) {
      if (entry is Map<String, dynamic>) {
        final category = _deserializeMenuCategory(entry);
        await _menuBox!.add(category);
      } else if (entry is Map) {
        final category = _deserializeMenuCategory(
          Map<String, dynamic>.from(entry),
        );
        await _menuBox!.add(category);
      }
    }
    if (!silent) {
      SyncHub.notify(SyncEvent(type: SyncEventType.menu, action: 'updated'));
    }
  }

  static List<Map<String, dynamic>> exportOrders() {
    if (_orderBox == null) {
      return [];
    }
    return _orderBox!.values.map(_serializeOrder).toList();
  }

  static Future<void> replaceOrdersFromJson(List<dynamic> payload) async {
    if (_orderBox == null) {
      return;
    }
    await _orderBox!.clear();
    for (final entry in payload) {
      if (entry is Map<String, dynamic>) {
        final order = _deserializeOrder(entry);
        await _orderBox!.add(order);
      } else if (entry is Map) {
        final order = _deserializeOrder(Map<String, dynamic>.from(entry));
        await _orderBox!.add(order);
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
    if (_orderBox == null || _reservationBox == null) return null;
    // Idempotent — skip if already exists
    final existing = getOrder(orderId);
    if (existing != null) return existing;

    final now = getCurrentDateTime();
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
      status: 'confirmed',
      includeServiceFee: false,
    );
    order.recalculateTotal();
    await _orderBox!.add(order);

    // Keep lastOrderId counter in sync so future POS orders don't reuse this ID
    final stored = _settingsBox?.get('lastOrderId') as int? ?? 0;
    if (orderId > stored) {
      await _settingsBox?.put('lastOrderId', orderId);
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
      status: 'confirmed',
      isTakeAway: true,
      linkedOrderId: orderId,
    );
    await _reservationBox!.add(reservation);

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
    final order = await createOrder(
      tableNumbers: tableNumbers,
      floor: floor,
      createdBy: createdBy,
      items: items,
      includeServiceFee: includeServiceFee,
    );
    return order;
  }

  static List<Map<String, dynamic>> exportReservations() {
    if (_reservationBox == null) {
      return [];
    }
    return _reservationBox!.values.map(_serializeReservation).toList();
  }

  static Future<void> replaceReservationsFromJson(List<dynamic> payload) async {
    if (_reservationBox == null) {
      return;
    }
    await _reservationBox!.clear();
    for (final entry in payload) {
      if (entry is Map<String, dynamic>) {
        final reservation = _deserializeReservation(entry);
        await _reservationBox!.add(reservation);
      } else if (entry is Map) {
        final reservation = _deserializeReservation(
          Map<String, dynamic>.from(entry),
        );
        await _reservationBox!.add(reservation);
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

    return createReservation(
      customerName: json['customerName'] as String? ?? 'Remote Guest',
      customerPhone: json['customerPhone'] as String? ?? '-',
      tableNumbers: tableNumbers,
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
      final reservation = _reservationBox!.values.firstWhere(
        (r) => r.id == reservationId,
      );
      return _serializeReservation(reservation);
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> exportTables() {
    if (_tableBox == null) {
      return [];
    }
    return _tableBox!.values.map(_serializeTable).toList();
  }

  static Future<void> replaceTablesFromJson(List<dynamic> payload) async {
    if (_tableBox == null) {
      return;
    }
    await _tableBox!.clear();
    for (final entry in payload) {
      if (entry is Map<String, dynamic>) {
        final table = _deserializeTable(entry);
        await _tableBox!.add(table);
      } else if (entry is Map) {
        final table = _deserializeTable(Map<String, dynamic>.from(entry));
        await _tableBox!.add(table);
      }
    }
    SyncHub.notify(SyncEvent(type: SyncEventType.tables, action: 'reloaded'));
  }

  static Future<void> updateTableFromJson(Map<String, dynamic> json) async {
    final tableNumber = json['tableNumber']?.toString();
    final floor = json['floor'] as String? ?? 'first';
    final table = getTable(tableNumber ?? '', floor);
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
        _userBox!.clear(),
        _tableBox!.clear(),
        _orderBox!.clear(),
        _packageBox!.clear(),
        _reservationBox!.clear(),
        _quickOrderBox!.clear(),
        _menuBox!.clear(),
        _salesBox!.clear(),
        _expenseBox!.clear(),
        _auditLogBox!.clear(),
        _errorLogBox!.clear(),
      ]);
    }

    for (final userEntry in usersJson) {
      if (userEntry is Map) {
        final user = _deserializeUser(Map<String, dynamic>.from(userEntry));
        await _userBox!.add(user);
      }
    }

    for (final tableEntry in tablesJson) {
      if (tableEntry is Map) {
        final table = _deserializeTable(Map<String, dynamic>.from(tableEntry));
        await _tableBox!.add(table);
      }
    }

    for (final orderEntry in ordersJson) {
      if (orderEntry is Map) {
        final order = _deserializeOrder(Map<String, dynamic>.from(orderEntry));
        await _orderBox!.add(order);
      }
    }

    for (final packageEntry in packagesJson) {
      if (packageEntry is Map) {
        final package = _deserializePackage(
          Map<String, dynamic>.from(packageEntry),
        );
        await _packageBox!.put(package.packageId, package);
      }
    }

    for (final reservationEntry in reservationsJson) {
      if (reservationEntry is Map) {
        final reservation = _deserializeReservation(
          Map<String, dynamic>.from(reservationEntry),
        );
        await _reservationBox!.add(reservation);
      }
    }

    for (final quickOrderEntry in quickOrdersJson) {
      if (quickOrderEntry is Map) {
        final draft = _deserializeQuickOrderDraft(
          Map<String, dynamic>.from(quickOrderEntry),
        );
        await _quickOrderBox!.put(draft.id, draft);
      }
    }

    for (final categoryEntry in menuJson) {
      if (categoryEntry is Map) {
        final category = _deserializeMenuCategory(
          Map<String, dynamic>.from(categoryEntry),
        );
        await _menuBox!.add(category);
      }
    }

    for (final saleEntry in salesJson) {
      if (saleEntry is Map) {
        _salesBox!.add(Map<String, dynamic>.from(saleEntry));
      }
    }

    for (final expenseEntry in expensesJson) {
      if (expenseEntry is Map) {
        _expenseBox!.add(Map<String, dynamic>.from(expenseEntry));
      }
    }

    for (final auditEntry in auditLogJson) {
      if (auditEntry is Map) {
        _auditLogBox!.add(Map<String, dynamic>.from(auditEntry));
      }
    }

    for (final errorEntry in errorLogJson) {
      if (errorEntry is Map) {
        _errorLogBox!.add(Map<String, dynamic>.from(errorEntry));
      }
    }

    final meta = payload['meta'] as Map?;
    final restoredVersion =
        (meta?['db_version'] as int?) ?? HiveMigrationService.targetVersion;
    await _metaBox!.put(HiveMigrationService.dbVersionKey, restoredVersion);
    await _metaBox!.put(
      HiveMigrationService.lastMigrationKey,
      meta?['last_migration_timestamp'] as String? ??
          DateTime.now().toIso8601String(),
    );
    _dbVersion = restoredVersion;

    final currentDateIso = payload['currentDate'] as String?;
    if (currentDateIso != null && currentDateIso.isNotEmpty) {
      await _settingsBox!.put('currentDate', currentDateIso);
    }

    final settings = payload['settings'] as Map?;
    if (settings != null) {
      if (settings.containsKey('serviceFeePercent')) {
        final percent = settings['serviceFeePercent'];
        if (percent is num) {
          await _settingsBox!.put('serviceFeePercent', percent.toDouble());
        }
      }
      if (settings.containsKey('serviceFeeEnabled')) {
        final value = settings['serviceFeeEnabled'];
        if (value is bool) {
          await _settingsBox!.put('serviceFeeEnabled', value);
        }
      }
      if (settings.containsKey('defaultLanguage')) {
        final value = settings['defaultLanguage'] as String?;
        if (value != null && value.isNotEmpty) {
          await _settingsBox!.put('defaultLanguage', value);
        }
      }
      if (settings.containsKey('printerKitchenIp')) {
        final value = settings['printerKitchenIp'] as String?;
        if (value != null) {
          await _settingsBox!.put('printerKitchenIp', value);
        }
      }
      if (settings.containsKey('printerReceiptIp')) {
        final value = settings['printerReceiptIp'] as String?;
        if (value != null) {
          await _settingsBox!.put('printerReceiptIp', value);
        }
      }
      if (settings.containsKey('printerPort')) {
        final value = settings['printerPort'];
        if (value is num) {
          await _settingsBox!.put('printerPort', value.toInt());
        }
      }
    }

    if (currentDateIso != null && currentDateIso.isNotEmpty) {
      await refreshDailySalesTotalForDate(DateTime.parse(currentDateIso));
    }

    await _ensureTableLayoutConsistency();

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
    );

    order.recalculateTotal();
    return order;
  }

  static Reservation _deserializeReservation(Map<String, dynamic> json) {
    final preOrders = ((json['preOrderItems'] as List?) ?? const [])
        .whereType<Map>()
        .map((it) => _deserializeOrderItem(Map<String, dynamic>.from(it)))
        .toList();

    return Reservation(
      id:
          json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      customerName: json['customerName'] as String? ?? 'Unknown',
      customerPhone: json['customerPhone'] as String? ?? '-',
      tableNumbers: ((json['tableNumbers'] as List?) ?? const [])
          .map(_coerceToInt)
          .whereType<int>()
          .toList(),
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

  // Close current day and move to next date
  static Future<bool> closeDay() async {
    try {
      developer.log('========================================');
      developer.log('CLOSE DAY - Starting checks');
      final currentDate = getCurrentDate();
      final currentDateString = currentDate.toIso8601String().split('T')[0];
      developer.log(
        'Current business date: ${getGeorgianFormattedDate(currentDate)}',
      );
      developer.log('========================================');

      // Check if any tables have active (non-closed) orders
      final activeOrders = _orderBox!.values.where((order) {
        if (order.status == 'closed' || order.status == 'cancelled') {
          return false;
        }
        final orderDateString = order.createdAt.toIso8601String().split('T')[0];
        return orderDateString == currentDateString;
      }).toList();

      developer.log('Total active orders: ${activeOrders.length}');

      if (activeOrders.isNotEmpty) {
        developer.log('❌ CANNOT CLOSE DAY - Active orders found:');
        for (var order in activeOrders) {
          developer.log('  - Order #${order.orderId}:');
          developer.log('    Tables: ${order.tableNumbers.join(", ")}');
          developer.log('    Floor: ${order.floor}');
          developer.log('    Status: ${order.status}');
          developer.log('    Created by: ${order.createdBy}');
          developer.log('    Created at: ${order.createdAt}');
        }

        // Also check which tables are still reserved
        developer.log('\nReserved tables in database:');
        for (final table in _tableBox!.values) {
          if (table.isReserved) {
            developer.log('  - Table ${table.tableNumber} (${table.floor}):');
            developer.log('    Reserved by: ${table.reservedBy}');
            developer.log('    Order ID: ${table.activeOrderId}');
            developer.log('    Reserved at: ${table.reservedAt}');
          }
        }

        // Check reservations
        developer.log('\nAll reservations in database:');
        for (var reservation in _reservationBox!.values) {
          final resDate = reservation.reservationDate.toIso8601String().split(
            'T',
          )[0];
          developer.log(
            '  - ${reservation.customerName} (${reservation.status}):',
          );
          developer.log(
            '    Date: $resDate (${getGeorgianFormattedDate(reservation.reservationDate)})',
          );
          developer.log('    Tables: ${reservation.tableNumbers.join(", ")}');
          developer.log('    Time: ${reservation.reservationTime}');
          developer.log('    Notes: ${reservation.notes ?? "none"}');
        }

        return false;
      }

      final pendingTakeAwayReservations = _reservationBox!.values.where((
        reservation,
      ) {
        if (!reservation.isTakeAway) {
          return false;
        }
        final reservationDateString = reservation.reservationDate
            .toIso8601String()
            .split('T')[0];
        if (reservationDateString != currentDateString) {
          return false;
        }
        final status = reservation.status.toLowerCase();
        return status != 'completed' && status != 'cancelled';
      }).toList();

      if (pendingTakeAwayReservations.isNotEmpty) {
        developer.log(
          '❌ CANNOT CLOSE DAY - Pending takeaway reservations found:',
        );
        for (final reservation in pendingTakeAwayReservations) {
          developer.log(
            '  - ${reservation.customerName} (${reservation.status})',
          );
          developer.log('    Time: ${reservation.reservationTime}');
          developer.log('    Created by: ${reservation.createdBy}');
        }
        return false;
      }

      final cleanupResults = await releaseStaleReservedTables();
      if (cleanupResults.isNotEmpty) {
        developer.log(
          '🧹 Cleaned ${cleanupResults.length} stale reserved tables before final check:',
        );
        for (final entry in cleanupResults) {
          final reason = entry['reason'] as String? ?? 'unknown reason';
          developer.log(
            '  - Table ${entry['tableNumber']} (${entry['floor']}) • $reason',
          );
        }
      }

      final reservedTables = _tableBox!.values
          .where((table) => table.isReserved)
          .toList();
      if (reservedTables.isNotEmpty) {
        developer.log('❌ CANNOT CLOSE DAY - Reserved tables still active:');
        for (final table in reservedTables) {
          developer.log('  - Table ${table.tableNumber} (${table.floor})');
          if (table.reservedBy != null) {
            developer.log('    Reserved by: ${table.reservedBy}');
          }
          if (table.activeOrderId != null) {
            developer.log('    Active order: #${table.activeOrderId}');
          }
          if (table.reservationId != null) {
            developer.log('    Reservation ID: ${table.reservationId}');
          }
        }
        return false;
      }

      developer.log('✅ No active orders found - proceeding with day closure');

      // Persist the day being closed so empty days (without sales) are still
      // part of operated business history.
      await _rememberOperatedBusinessDate(currentDate);

      final nextDate = currentDate.add(const Duration(days: 1));
      developer.log(
        'Moving from ${getGeorgianFormattedDate(currentDate)} to ${getGeorgianFormattedDate(nextDate)}',
      );

      await _settingsBox!.put('currentDate', nextDate.toIso8601String());

      // Reset daily sales total for new day
      await resetDailySalesTotal();

      // Clear all closed orders from active orders
      final orderKeys = _orderBox!.keys.toList();
      for (final key in orderKeys) {
        final order = _orderBox!.get(key);
        if (order?.status == 'closed') {
          await _orderBox!.delete(key);
        }
      }

      // Free all reserved tables for new day
      int freedTables = 0;
      for (final table in _tableBox!.values) {
        if (table.isReserved || table.reservationId != null) {
          table.isReserved = false;
          table.activeOrderId = null;
          table.reservedAt = null;
          table.reservedBy = null;
          table.reservationId = null;
          await table.save();
          freedTables++;
        }
      }

      developer.log('Freed $freedTables tables');

      developer.log('✅ Day closed successfully');
      developer.log('========================================');

      return true;
    } catch (e) {
      developer.log('❌ Error closing day: $e');
      return false;
    }
  }

  // Get date in Georgian format
  static String getGeorgianFormattedDate(DateTime date) {
    final months = [
      'იანვარი',
      'თებერვალი',
      'მარტი',
      'აპრილი',
      'მაისი',
      'ივნისი',
      'ივლისი',
      'აგვისტო',
      'სექტემბერი',
      'ოქტომბერი',
      'ნოემბერი',
      'დეკემბერი',
    ];
    final weekDays = [
      'ორშაბათი',
      'სამშაბათი',
      'ოთხშაბათი',
      'ხუთშაბათი',
      'პარასკევი',
      'შაბათი',
      'კვირა',
    ];

    final day = date.day;
    final month = months[date.month - 1];
    final year = date.year;
    final weekDay = weekDays[date.weekday - 1];

    return '$weekDay, $day $month $year';
  }

  // ==================== SALES TRACKING METHODS ====================

  // Close order with payment method
  static Future<bool> closeOrderWithPayment({
    required int orderId,
    required String paymentMethod,
    required String closedById,
    String? closedByName,
    Map<String, double>? paymentBreakdown,
    String? customPaymentLabel,
  }) async {
    try {
      final order = _orderBox!.values.firstWhere((o) => o.orderId == orderId);
      order.status = 'closed';
      order.paymentMethod = paymentMethod;
      final closureTimestamp = getCurrentDateTime();
      order.closedAt = closureTimestamp;
      order.updatedAt = closureTimestamp;
      await order.save();

      // Free all tables associated with this order
      for (final tableNumber in order.tableNumbers) {
        await freeTable(tableNumber: tableNumber, floor: order.floor);
      }

      // Mark associated reservation as completed
      final currentDate = getCurrentDate();
      final dateString = currentDate.toIso8601String().split('T')[0];

      // Find reservation with matching tables and date
      for (var reservation in _reservationBox!.values) {
        final resDateString = reservation.reservationDate
            .toIso8601String()
            .split('T')[0];
        if (resDateString == dateString &&
            reservation.notes != null &&
            reservation.notes!.contains('Order #$orderId')) {
          reservation.status = 'completed';
          await reservation.save();
          break;
        }
      }

      final closingEvent = AuditEvent(
        type: AuditEventType.cancelTable,
        itemName: 'ORDER',
        previousQty: 0,
        newQty: 0,
        waiterId: closedById,
        waiterName: closedByName ?? closedById,
        timestamp: order.closedAt!,
        note: customPaymentLabel != null && customPaymentLabel.isNotEmpty
            ? 'Order closed with $customPaymentLabel'
            : 'Order closed with $paymentMethod',
      );

      try {
        await appendOrderAuditEvents(
          orderId: orderId,
          events: [closingEvent],
          statusOverride: AuditReportStatus.closed,
          lockReport: true,
          closedById: closedById,
          closedByName: closedByName ?? closedById,
        );
      } catch (e) {
        developer.log('Audit report append failed for order $orderId: $e');
      }

      return true;
    } catch (e) {
      developer.log('Error closing order with payment: $e');
      return false;
    }
  }

  static Future<bool> closeOrderNonFiscal({
    required int orderId,
    required String closedById,
    String? closedByName,
  }) async {
    try {
      final order = _orderBox!.values.firstWhere((o) => o.orderId == orderId);
      order.status = 'closed';
      order.paymentMethod = 'non-fiscal';
      final closureTimestamp = getCurrentDateTime();
      order.closedAt = closureTimestamp;
      order.updatedAt = closureTimestamp;
      await order.save();

      for (final tableNumber in order.tableNumbers) {
        await freeTable(tableNumber: tableNumber, floor: order.floor);
      }

      final currentDate = getCurrentDate();
      final dateString = currentDate.toIso8601String().split('T')[0];

      for (var reservation in _reservationBox!.values) {
        final resDateString = reservation.reservationDate
            .toIso8601String()
            .split('T')[0];
        if (resDateString == dateString &&
            reservation.notes != null &&
            reservation.notes!.contains('Order #$orderId')) {
          reservation.status = 'completed';
          await reservation.save();
          break;
        }
      }

      final closingEvent = AuditEvent(
        type: AuditEventType.cancelTable,
        itemName: 'ORDER',
        previousQty: 0,
        newQty: 0,
        waiterId: closedById,
        waiterName: closedByName ?? closedById,
        timestamp: order.closedAt!,
        note: 'Order closed (non-fiscal)',
      );

      try {
        await appendOrderAuditEvents(
          orderId: orderId,
          events: [closingEvent],
          statusOverride: AuditReportStatus.closed,
          lockReport: true,
          closedById: closedById,
          closedByName: closedByName ?? closedById,
        );
      } catch (e) {
        developer.log(
          'Audit report append failed for non-fiscal closure $orderId: $e',
        );
      }

      return true;
    } catch (e) {
      developer.log('Error closing order non-fiscally: $e');
      return false;
    }
  }

  // Save sale record
  static Future<bool> saveSaleRecord({
    required int orderId,
    required List<String> tableNumbers,
    required String floor,
    required List<OrderItem> items,
    required double totalAmount,
    required String paymentMethod,
    Map<String, double>? paymentBreakdown,
    String? customPaymentLabel,
    required String createdBy,
    required DateTime createdAt,
    required DateTime closedAt,
    required bool includeServiceFee,
    double discountAmount = 0.0,
    double advanceAmount = 0.0,
    double? subtotalAmount,
    double? manualAdjustmentAmount,
    Map<String, dynamic>? finalTransaction,
    bool isFiscal = true,
    bool isCancelled = false,
    DateTime? cancelledAt,
  }) async {
    try {
      final saleRecord = {
        'orderId': orderId,
        'tableNumbers': tableNumbers,
        'floor': floor,
        'items': items
            .map(
              (item) => {
                'itemName': item.itemName,
                'quantity': item.quantity,
                'unitPrice': item.unitPrice,
                'total': item.total,
              },
            )
            .toList(),
        'totalAmount': totalAmount,
        'total': totalAmount, // Add this field for reports compatibility
        'paymentMethod': paymentMethod,
        'paymentBreakdown': paymentBreakdown,
        'customPaymentLabel': customPaymentLabel,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'closedAt': closedAt.toIso8601String(),
        'includeServiceFee': includeServiceFee,
        'discountAmount': discountAmount,
        'advanceAmount': advanceAmount,
        'subtotalAmount': subtotalAmount ?? totalAmount,
        'manualAdjustmentAmount': manualAdjustmentAmount ?? 0.0,
        'finalTransaction': finalTransaction,
        'date': getCurrentDate().toIso8601String().split('T')[0],
        'isCancelled': isCancelled,
        if (isCancelled)
          'cancelledAt': (cancelledAt ?? getCurrentDateTime())
              .toIso8601String(),
        'isFiscal': isFiscal,
      };

      await _salesBox!.add(saleRecord);

      // Update daily sales total
      if (isFiscal) {
        final currentTotal =
            _settingsBox!.get('dailySalesTotal', defaultValue: 0.0) as double;
        await _settingsBox!.put('dailySalesTotal', currentTotal + totalAmount);
      }

      return true;
    } catch (e) {
      developer.log('Error saving sale record: $e');
      return false;
    }
  }

  // Get daily sales total
  static double getDailySalesTotal() {
    return _settingsBox!.get('dailySalesTotal', defaultValue: 0.0) as double;
  }

  static Future<Map<String, dynamic>> saveExpenseRecord({
    required String description,
    required double amount,
    required String category,
    String paymentType = 'cash',
    DateTime? createdAt,
    String? businessDate,
    String? sourceId,
  }) async {
    final now = createdAt ?? getCurrentDateTime();
    final date = businessDate ?? getCurrentDate().toIso8601String().split('T')[0];
    final record = <String, dynamic>{
      'id': sourceId ?? _uuid.v4(),
      'description': description.trim(),
      'amount': double.parse(amount.toStringAsFixed(2)),
      'category': category.trim().isEmpty ? 'სხვა' : category.trim(),
      'paymentType': paymentType.trim().isEmpty ? 'cash' : paymentType.trim(),
      'createdAt': now.toIso8601String(),
      'date': date,
    };
    await _expenseBox!.add(record);
    return record;
  }

  static List<Map<String, dynamic>> getExpensesForDate(String date) {
    final entries = <Map<String, dynamic>>[];
    for (final key in _expenseBox!.keys) {
      final raw = _expenseBox!.get(key);
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      if ((data['date'] as String?) != date) continue;
      data['recordKey'] = key;
      entries.add(data);
    }
    entries.sort((a, b) {
      final aTs = (a['createdAt'] as String?) ?? '';
      final bTs = (b['createdAt'] as String?) ?? '';
      return bTs.compareTo(aTs);
    });
    return entries;
  }

  static double getExpenseTotalForDate(String date) {
    return getExpensesForDate(date).fold<double>(
      0.0,
      (sum, expense) => sum + ((expense['amount'] as num?)?.toDouble() ?? 0.0),
    );
  }

  static List<Map<String, dynamic>> getAllExpenseRecords() {
    final entries = <Map<String, dynamic>>[];
    for (final key in _expenseBox!.keys) {
      final raw = _expenseBox!.get(key);
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      data['recordKey'] = key;
      entries.add(data);
    }
    entries.sort((a, b) {
      final aTs = (a['createdAt'] as String?) ?? '';
      final bTs = (b['createdAt'] as String?) ?? '';
      return bTs.compareTo(aTs);
    });
    return entries;
  }

  // Get sales for a specific date
  static List<Map<String, dynamic>> getSalesForDate(String date) {
    return _mapSalesRecords(filterDate: date);
  }

  // Get all sales records
  static List<Map<String, dynamic>> getAllSales() {
    return _mapSalesRecords();
  }

  static List<Map<String, dynamic>> _mapSalesRecords({String? filterDate}) {
    final records = <Map<String, dynamic>>[];

    for (final key in _salesBox!.keys) {
      final raw = Map<String, dynamic>.from(_salesBox!.get(key) as Map);
      if (filterDate != null && raw['date'] != filterDate) {
        continue;
      }
      raw['recordKey'] = key;
      raw['isCancelled'] = raw['isCancelled'] ?? false;
      raw['restoredToOrder'] = raw['restoredToOrder'] ?? false;
      raw['isFiscal'] = raw['isFiscal'] ?? true;
      records.add(raw);
    }

    records.sort(
      (a, b) => (b['closedAt'] as String).compareTo(a['closedAt'] as String),
    );

    return records;
  }

  static Future<bool> cancelSaleRecord(dynamic recordKey) async {
    try {
      final sale = _salesBox!.get(recordKey);
      if (sale == null) return false;

      final updated = Map<String, dynamic>.from(sale as Map);
      if (updated['isCancelled'] == true) {
        return true;
      }

      updated['isCancelled'] = true;
      updated['cancelledAt'] = getCurrentDateTime().toIso8601String();
      await _salesBox!.put(recordKey, updated);

      final dateString = updated['date'] as String?;
      if (dateString != null && dateString.isNotEmpty) {
        await refreshDailySalesTotalForDate(DateTime.parse(dateString));
      }

      return true;
    } catch (e) {
      developer.log('Error cancelling sale record: $e');
      return false;
    }
  }

  static Future<bool> restoreClosedOrderFromSale({
    required dynamic recordKey,
    required String restoredBy,
  }) async {
    try {
      final rawSale = _salesBox!.get(recordKey);
      if (rawSale == null) {
        return false;
      }

      final sale = Map<String, dynamic>.from(rawSale as Map);
      if (sale['restoredToOrder'] == true) {
        return false;
      }

      final saleDate = (sale['date'] as String?) ?? '';
      final todayDate = getCurrentDate().toIso8601String().split('T')[0];
      if (saleDate != todayDate) {
        return false;
      }

      final paymentMethod = (sale['paymentMethod'] as String? ?? '')
          .trim()
          .toLowerCase();
      if (paymentMethod == 'advance') {
        return false;
      }

      final orderIdRaw = sale['orderId'];
      final int? orderId = orderIdRaw is int
          ? orderIdRaw
          : int.tryParse(orderIdRaw?.toString() ?? '');
      if (orderId == null) {
        return false;
      }

      final saleFloor = (sale['floor'] as String?)?.trim().isNotEmpty == true
          ? (sale['floor'] as String).trim()
          : 'first';

      final saleTableNumbers = <String>[];
      final seenSaleTables = <String>{};
      final rawTables = (sale['tableNumbers'] as List?) ?? const [];
      for (final raw in rawTables) {
        final normalized = _normalizeTableIdentifier(raw.toString(), saleFloor);
        if (normalized == null || normalized.isEmpty) {
          continue;
        }
        if (!isTableConfigured(tableNumber: normalized, floor: saleFloor)) {
          continue;
        }
        if (seenSaleTables.add(normalized)) {
          saleTableNumbers.add(normalized);
        }
      }
      if (saleTableNumbers.isEmpty) {
        return false;
      }

      Order? order = getOrder(orderId);
      final targetFloor = order?.floor ?? saleFloor;
      final targetTables = order?.tableNumbers.isNotEmpty == true
          ? List<String>.from(order!.tableNumbers)
          : saleTableNumbers;

      if (order != null) {
        final normalizedOrderStatus = order.status.toLowerCase();
        if (normalizedOrderStatus != 'closed' &&
            normalizedOrderStatus != 'cancelled') {
          return false;
        }
      }

      for (final tableNumber in targetTables) {
        final table = getTable(tableNumber, targetFloor);
        if (table == null) {
          continue;
        }

        final occupiedByAnotherOrder =
            table.isReserved &&
            table.activeOrderId != null &&
            table.activeOrderId != orderId;
        if (occupiedByAnotherOrder) {
          return false;
        }
      }

      final restoreTimestamp = getCurrentDateTime();

      if (order == null) {
        final parsedCreatedAt = _tryParseDate(sale['createdAt'] as String?);
        final includeServiceFee = sale['includeServiceFee'] == true;
        final discountAmount =
            (sale['discountAmount'] as num?)?.toDouble() ??
            (sale['advanceAmount'] as num?)?.toDouble() ??
            0.0;
        final manualAdjustment =
            (sale['manualAdjustmentAmount'] as num?)?.toDouble() ?? 0.0;

        final reconstructedItems = <OrderItem>[];
        final rawItems = (sale['items'] as List?) ?? const [];
        for (final raw in rawItems.whereType<Map>()) {
          final quantity = (raw['quantity'] as num?)?.toInt() ?? 0;
          final total = (raw['total'] as num?)?.toDouble() ?? 0.0;
          final unitPrice =
              (raw['unitPrice'] as num?)?.toDouble() ??
              (quantity > 0 ? total / quantity : total);
          final itemName = (raw['itemName'] ?? raw['name'] ?? 'უცნობი პოზიცია')
              .toString();

          reconstructedItems.add(
            OrderItem(
              itemKey: itemName,
              itemName: itemName,
              unitPrice: double.parse(unitPrice.toStringAsFixed(2)),
              quantity: quantity,
              total: double.parse(total.toStringAsFixed(2)),
              comment: raw['comment']?.toString(),
            ),
          );
        }

        order = Order(
          orderId: orderId,
          tableNumbers: targetTables,
          floor: targetFloor,
          items: reconstructedItems,
          totalAmount: (sale['totalAmount'] as num?)?.toDouble() ?? 0.0,
          createdAt: parsedCreatedAt ?? restoreTimestamp,
          createdBy: (sale['createdBy'] as String?) ?? restoredBy,
          status: 'confirmed',
          includeServiceFee: includeServiceFee,
          discountAmount: discountAmount,
          manualAdjustmentAmount: manualAdjustment,
          openedByUserId: restoredBy,
          paymentMethod: null,
          closedAt: null,
          updatedAt: restoreTimestamp,
        );
        order.recalculateTotal(serviceFeeRate: getServiceFeeRate());
        await _orderBox!.add(order);

        final storedLastOrderId =
            (_settingsBox?.get('lastOrderId') as int?) ?? 0;
        if (orderId > storedLastOrderId) {
          await _settingsBox?.put('lastOrderId', orderId);
        }
      }

      for (final tableNumber in targetTables) {
        final table = getTable(tableNumber, targetFloor);
        if (table == null) {
          continue;
        }

        await reserveTable(
          tableNumber: tableNumber,
          floor: targetFloor,
          username: restoredBy,
          orderId: orderId,
        );
      }

      order.status = 'confirmed';
      order.paymentMethod = null;
      order.closedAt = null;
      order.updatedAt = restoreTimestamp;
      await order.save();

      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.orders,
          action: 'restored',
          payload: {'orderId': orderId, 'restoredBy': restoredBy},
        ),
      );

      final updatedSale = Map<String, dynamic>.from(sale)
        ..['isCancelled'] = false
        ..remove('cancelledAt')
        ..['restoredToOrder'] = true
        ..['restoredAt'] = restoreTimestamp.toIso8601String()
        ..['restoredBy'] = restoredBy;
      await _salesBox!.put(recordKey, updatedSale);

      await refreshDailySalesTotalForDate(getCurrentDate());
      return true;
    } catch (e) {
      developer.log('Error restoring sale record to order: $e');
      return false;
    }
  }

  // Reset daily sales total (called when closing day)
  static Future<void> resetDailySalesTotal() async {
    await _settingsBox!.put('dailySalesTotal', 0.0);
  }

  // ==================== AUDIT LOG METHODS ====================

  static String _buildAuditReportKey(int orderId) =>
      '$_auditReportKeyPrefix$orderId';

  static AuditReport? _parseAuditReport(dynamic raw) {
    if (raw is AuditReport) {
      return raw;
    }
    if (raw is Map) {
      final map = Map<dynamic, dynamic>.from(raw);
      final reportId = (map['reportId'] as String?)?.trim();
      if (reportId != null && reportId.isNotEmpty) {
        return AuditReport.fromMap(map);
      }
    }
    return null;
  }

  static Future<AuditReport> _ensureAuditReport({
    required int orderId,
    Order? orderSnapshot,
  }) async {
    final existing = getAuditReport(orderId);
    if (existing != null) {
      return existing;
    }

    orderSnapshot ??= getOrder(orderId);
    final now = DateTime.now();
    final tableNumbers = orderSnapshot?.tableNumbers ?? const <String>[];
    final floor = orderSnapshot?.floor ?? 'first';
    final openedBy = orderSnapshot?.createdBy ?? 'unknown';
    final openedAt = orderSnapshot?.createdAt ?? now;

    final report = AuditReport(
      reportId: _buildAuditReportKey(orderId),
      orderId: orderId,
      tableNumbers: List<String>.from(tableNumbers),
      floor: floor,
      openedById: openedBy,
      openedByName: openedBy,
      openedAt: openedAt,
      status: AuditReportStatus.open,
      events: const [],
      updatedAt: now,
      locked: false,
    );

    await saveAuditReport(report);
    return report;
  }

  static Future<void> saveAuditReport(AuditReport report) async {
    if (_auditLogBox == null) return;
    await _auditLogBox!.put(report.reportId, report.toMap());
    _onAuditChanged?.call();
  }

  static AuditReport? getAuditReport(int orderId) {
    if (_auditLogBox == null) {
      return null;
    }
    final raw = _auditLogBox!.get(_buildAuditReportKey(orderId));
    if (raw == null) {
      return null;
    }
    try {
      return _parseAuditReport(raw);
    } catch (e) {
      developer.log('Failed to parse audit report for order $orderId: $e');
      return null;
    }
  }

  static List<AuditReport> getAuditReports({AuditReportStatus? status}) {
    if (_auditLogBox == null) {
      return const [];
    }

    final actualReports = <AuditReport>[];
    for (final key in _auditLogBox!.keys) {
      final value = _auditLogBox!.get(key);
      final report = _parseAuditReport(value);
      if (report == null) {
        continue;
      }
      actualReports.add(report);
    }

    final legacyReports = _buildLegacyAuditReports(
      actualReports.map((report) => report.orderId).toSet(),
    );

    final combined = <AuditReport>[...actualReports, ...legacyReports];
    if (status != null) {
      combined.removeWhere((report) => report.status != status);
    }

    combined.sort((a, b) => _reportLastActivity(b).compareTo(_reportLastActivity(a)));
    return combined;
  }

  static String _auditTableSetKey(List<String> tables) {
    final normalized = tables
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList()
      ..sort();
    return normalized.join('|');
  }

  static Future<void> _finalizeConflictingOpenAuditReports({
    required int currentOrderId,
    required String floor,
    required List<String> tableNumbers,
    required String closedBy,
  }) async {
    if (_auditLogBox == null) {
      return;
    }

    final targetKey = _auditTableSetKey(tableNumbers);
    if (targetKey.isEmpty) {
      return;
    }

    final now = getCurrentDateTime();
    var changed = false;
    final openReports = getAuditReports(status: AuditReportStatus.open);

    for (final report in openReports) {
      if (report.orderId == currentOrderId) {
        continue;
      }
      if (report.floor != floor) {
        continue;
      }
      if (_auditTableSetKey(report.tableNumbers) != targetKey) {
        continue;
      }
      if (report.reportId.startsWith('legacy_report_order_')) {
        continue;
      }

      final updated = report.copyWith(
        status: AuditReportStatus.closed,
        locked: true,
        closedAt: now,
        closedById: closedBy,
        closedByName: closedBy,
        updatedAt: now,
      );
      await _auditLogBox!.put(updated.reportId, updated.toMap());
      changed = true;
    }

    if (changed) {
      _onAuditChanged?.call();
    }
  }

  static Future<void> _runAuditDuplicateOpenCleanupOnce() async {
    if (_settingsBox == null || _auditLogBox == null) {
      return;
    }

    const cleanupKey = 'auditOpenDuplicateCleanupV1';
    final alreadyDone = _settingsBox!.get(cleanupKey) == true;
    if (alreadyDone) {
      return;
    }

    final openReports = getAuditReports(status: AuditReportStatus.open)
        .where((r) => !r.reportId.startsWith('legacy_report_order_'))
        .toList();

    if (openReports.isEmpty) {
      await _settingsBox!.put(cleanupKey, true);
      return;
    }

    final grouped = <String, List<AuditReport>>{};
    for (final report in openReports) {
      final tableKey = _auditTableSetKey(report.tableNumbers);
      if (tableKey.isEmpty) {
        continue;
      }
      final key = '${report.floor}|$tableKey';
      grouped.putIfAbsent(key, () => <AuditReport>[]).add(report);
    }

    var changed = false;
    final now = getCurrentDateTime();

    for (final entry in grouped.entries) {
      final reports = entry.value;
      if (reports.length <= 1) {
        continue;
      }

      reports.sort((a, b) => _reportLastActivity(b).compareTo(_reportLastActivity(a)));
      final keeper = reports.first;
      final stale = reports.skip(1);

      for (final report in stale) {
        final closedBy = report.closedByName ?? report.openedByName;
        final closedId = report.closedById ?? report.openedById;
        final fixed = report.copyWith(
          status: AuditReportStatus.closed,
          locked: true,
          closedAt: now,
          closedById: closedId,
          closedByName: closedBy,
          updatedAt: now,
        );
        await _auditLogBox!.put(fixed.reportId, fixed.toMap());
        changed = true;
      }

      debugPrint(
        '[AuditCleanup] ${reports.length - 1} stale OPEN reports closed for ${entry.key}, kept order #${keeper.orderId}.',
      );
    }

    await _settingsBox!.put(cleanupKey, true);
    if (changed) {
      _onAuditChanged?.call();
    }
  }

  static DateTime _reportLastActivity(AuditReport report) {
    DateTime latestEventTs = report.openedAt;
    for (final event in report.events) {
      if (event.timestamp.isAfter(latestEventTs)) {
        latestEventTs = event.timestamp;
      }
    }
    return report.updatedAt.isAfter(latestEventTs) ? report.updatedAt : latestEventTs;
  }

  static List<AuditReport> _buildLegacyAuditReports(Set<int> existingOrderIds) {
    if (_auditLogBox == null) {
      return const [];
    }

    final groupedLogs = <int, List<Map<String, dynamic>>>{};

    for (final key in _auditLogBox!.keys) {
      if (key is! String || !key.startsWith(_auditLegacyPrefix)) {
        continue;
      }

      final raw = _auditLogBox!.get(key);
      if (raw is! Map) {
        continue;
      }

      final log = Map<String, dynamic>.from(raw);
      final detailsRaw = log['details'];
      if (detailsRaw is! Map) {
        continue;
      }

      final orderId = (detailsRaw['orderId'] as num?)?.toInt();
      if (orderId == null || existingOrderIds.contains(orderId)) {
        continue;
      }

      groupedLogs
          .putIfAbsent(orderId, () => <Map<String, dynamic>>[])
          .add(Map<String, dynamic>.from(log));
    }

    if (groupedLogs.isEmpty) {
      return const [];
    }

    final legacyReports = <AuditReport>[];

    for (final entry in groupedLogs.entries) {
      final orderId = entry.key;
      final logs = entry.value;
      final events = <AuditEvent>[];

      for (final log in logs) {
        final actionType = log['actionType'] as String?;
        final eventType = _eventTypeFromLegacyAction(actionType);
        if (eventType == null) {
          continue;
        }

        final details = (log['details'] as Map?) ?? const {};
        final timestamp = _resolveLegacyTimestamp(
          log['timestamp'] as String?,
          log['date'] as String?,
        );

        final waiterName = (log['performedBy'] as String?)?.trim();
        final comment = (log['comment'] as String?)?.trim();

        events.add(
          AuditEvent(
            type: eventType,
            itemName: (details['itemName'] as String?)?.trim() ?? 'Item',
            previousQty: (details['previousQty'] as num?)?.toInt() ?? 0,
            newQty: (details['newQty'] as num?)?.toInt() ?? 0,
            waiterId: waiterName?.isNotEmpty == true ? waiterName! : 'unknown',
            waiterName: waiterName?.isNotEmpty == true
                ? waiterName!
                : 'Unknown',
            timestamp: timestamp,
            note: comment?.isNotEmpty == true ? comment : null,
          ),
        );
      }

      if (events.isEmpty) {
        continue;
      }

      events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final firstEvent = events.first;
      final lastEvent = events.last;

      final referenceDetails = logs.lastWhere(
        (log) => log['details'] is Map,
        orElse: () => const {},
      );
      final referenceMap = (referenceDetails['details'] as Map?) ?? const {};

      final tableNumbers = _stringifyTableNumbers(referenceMap['tableNumbers']);
      final floorRaw = (referenceMap['floor']?.toString() ?? '').trim();
      final floor = floorRaw.isNotEmpty ? floorRaw : 'first';

      final isCancelled = events.last.type == AuditEventType.cancelTable;
      final status = isCancelled
          ? AuditReportStatus.cancelled
          : AuditReportStatus.open;

      legacyReports.add(
        AuditReport(
          reportId: 'legacy_report_order_$orderId',
          orderId: orderId,
          tableNumbers: tableNumbers,
          floor: floor,
          openedById: firstEvent.waiterId,
          openedByName: firstEvent.waiterName,
          openedAt: firstEvent.timestamp,
          status: status,
          events: List<AuditEvent>.unmodifiable(events),
          updatedAt: lastEvent.timestamp,
          closedAt: isCancelled ? lastEvent.timestamp : null,
          closedById: isCancelled ? lastEvent.waiterId : null,
          closedByName: isCancelled ? lastEvent.waiterName : null,
          locked: isCancelled,
        ),
      );
    }

    return legacyReports;
  }

  static AuditEventType? _eventTypeFromLegacyAction(String? action) {
    switch (action) {
      case 'add_item':
        return AuditEventType.addItem;
      case 'reduce_quantity':
        return AuditEventType.reduceQty;
      case 'remove_item':
        return AuditEventType.deleteItem;
      case 'cancel_table':
        return AuditEventType.cancelTable;
      case 'custom':
        return AuditEventType.custom;
    }
    return null;
  }

  static DateTime _resolveLegacyTimestamp(
    String? timestampIso,
    String? dateIso,
  ) {
    final parsedTimestamp = timestampIso != null
        ? DateTime.tryParse(timestampIso)
        : null;
    if (parsedTimestamp != null) {
      return parsedTimestamp;
    }

    if (dateIso != null && dateIso.isNotEmpty) {
      final parsedDate = DateTime.tryParse(dateIso);
      if (parsedDate != null) {
        return DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      }
    }

    return getCurrentDateTime();
  }

  static List<String> _stringifyTableNumbers(dynamic raw) {
    if (raw is List) {
      return raw
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return const [];
      }
      return trimmed
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static Future<void> appendOrderAuditEvents({
    required int orderId,
    required List<AuditEvent> events,
    AuditReportStatus? statusOverride,
    bool lockReport = false,
    String? closedById,
    String? closedByName,
  }) async {
    if (events.isEmpty && !lockReport) {
      return;
    }

    final orderSnapshot = getOrder(orderId);
    var report = await _ensureAuditReport(
      orderId: orderId,
      orderSnapshot: orderSnapshot,
    );

    if (report.locked) {
      throw StateError('Audit report for order $orderId is locked');
    }

    final mergedEvents = <AuditEvent>[...report.events, ...events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final updatedEvents = List<AuditEvent>.unmodifiable(mergedEvents);
    final updatedAt = getCurrentDateTime();

    final updatedReport = report.copyWith(
      events: updatedEvents,
      updatedAt: updatedAt,
      status: statusOverride ?? report.status,
      locked: lockReport ? true : report.locked,
      closedAt: lockReport ? updatedAt : report.closedAt,
      closedById: lockReport
          ? (closedById ??
                report.closedById ??
                (updatedEvents.isNotEmpty ? updatedEvents.last.waiterId : null))
          : (closedById ?? report.closedById),
      closedByName: lockReport
          ? (closedByName ??
                report.closedByName ??
                (updatedEvents.isNotEmpty
                    ? updatedEvents.last.waiterName
                    : null))
          : (closedByName ?? report.closedByName),
    );

    await _auditLogBox!.put(updatedReport.reportId, updatedReport.toMap());
    _onAuditChanged?.call();
  }

  static String _legacyActionForEvent(AuditEventType type) {
    switch (type) {
      case AuditEventType.addItem:
        return 'add_item';
      case AuditEventType.reduceQty:
        return 'reduce_quantity';
      case AuditEventType.deleteItem:
        return 'remove_item';
      case AuditEventType.cancelTable:
        return 'cancel_table';
      case AuditEventType.custom:
        return 'custom';
    }
  }

  static Future<void> logAdminAction({
    required String actionType,
    required String performedBy,
    Map<String, dynamic>? details,
    String? comment,
    String? approvedBy,
  }) async {
    final normalizedType = actionType.toLowerCase();
    final orderId = (details?['orderId'] as num?)?.toInt();

    if (orderId != null &&
        (normalizedType == 'cancel_table' ||
            normalizedType == 'remove_item' ||
            normalizedType == 'reduce_quantity' ||
            normalizedType == 'add_item')) {
      final waiterName = performedBy.trim().isEmpty ? 'Unknown' : performedBy;
      final waiterId = waiterName;
      final timestamp = getCurrentDateTime();
      final events = <AuditEvent>[];

      final changes = (details?['changes'] as List?) ?? const [];

      if (normalizedType == 'cancel_table') {
        events.add(
          AuditEvent(
            type: AuditEventType.cancelTable,
            itemName: 'ORDER',
            previousQty: 0,
            newQty: 0,
            waiterId: waiterId,
            waiterName: waiterName,
            timestamp: timestamp,
            note: comment ?? details?['requestComment'] as String?,
          ),
        );

        await appendOrderAuditEvents(
          orderId: orderId,
          events: events,
          statusOverride: AuditReportStatus.cancelled,
          lockReport: true,
          closedById: waiterId,
          closedByName: waiterName,
        );
        return;
      }

      if (changes.isNotEmpty) {
        for (final entry in changes.whereType<Map>()) {
          final change = Map<String, dynamic>.from(entry);
          final itemName = (change['itemName'] as String?) ?? 'Item';
          final previousQty =
              (change['previousQuantity'] as num?)?.toInt() ?? 0;
          final newQty = (change['newQuantity'] as num?)?.toInt() ?? 0;

          AuditEventType type;
          if (newQty <= 0) {
            type = AuditEventType.deleteItem;
          } else if (newQty < previousQty) {
            type = AuditEventType.reduceQty;
          } else {
            type = AuditEventType.addItem;
          }

          events.add(
            AuditEvent(
              type: type,
              itemName: itemName,
              previousQty: previousQty,
              newQty: newQty,
              waiterId: waiterId,
              waiterName: waiterName,
              timestamp: timestamp,
              note: comment,
            ),
          );
        }
      } else if (details?['itemName'] is String) {
        final itemName = details?['itemName'] as String? ?? 'Item';
        final previousQty =
            (details?['previousQuantity'] as num?)?.toInt() ?? 0;
        final newQty = (details?['newQuantity'] as num?)?.toInt() ?? 0;

        AuditEventType type;
        if (normalizedType == 'remove_item' || newQty <= 0) {
          type = AuditEventType.deleteItem;
        } else if (newQty < previousQty) {
          type = AuditEventType.reduceQty;
        } else {
          type = AuditEventType.addItem;
        }

        events.add(
          AuditEvent(
            type: type,
            itemName: itemName,
            previousQty: previousQty,
            newQty: newQty,
            waiterId: waiterId,
            waiterName: waiterName,
            timestamp: timestamp,
            note: comment,
          ),
        );
      }

      if (events.isNotEmpty) {
        await appendOrderAuditEvents(orderId: orderId, events: events);
        return;
      }
    }

    final logKey =
        '$_auditLegacyPrefix${DateTime.now().microsecondsSinceEpoch}';
    final log = {
      'actionType': actionType,
      'performedBy': performedBy,
      if (approvedBy != null) 'approvedBy': approvedBy,
      'comment': comment ?? '',
      'details': details ?? <String, dynamic>{},
      'timestamp': getCurrentDateTime().toIso8601String(),
      'date': getCurrentDate().toIso8601String().split('T')[0],
    };

    await _auditLogBox!.put(logKey, log);

    unawaited(
      AuditEventService.logEvent(
        action: actionType,
        userId: performedBy,
        data: {
          if (details != null) ...details,
          if (comment != null) 'comment': comment,
          if (approvedBy != null) 'approvedBy': approvedBy,
        },
      ),
    );
    _onAuditChanged?.call();
  }

  static List<Map<String, dynamic>> getAuditLogs({
    String? date,
    String? actionType,
  }) {
    final logs = <Map<String, dynamic>>[];

    for (final report in getAuditReports()) {
      for (final event in report.sortedEvents) {
        final action = _legacyActionForEvent(event.type);
        final timestampIso = event.timestamp.toIso8601String();
        final entryDate = timestampIso.split('T')[0];

        logs.add({
          'actionType': action,
          'performedBy': event.waiterName,
          'comment': event.note ?? '',
          'details': {
            'orderId': report.orderId,
            'tableNumbers': report.tableNumbers,
            'floor': report.floor,
            'previousQty': event.previousQty,
            'newQty': event.newQty,
            'itemName': event.itemName,
          },
          'timestamp': timestampIso,
          'date': entryDate,
        });
      }
    }

    if (_auditLogBox != null) {
      for (final key in _auditLogBox!.keys) {
        final value = _auditLogBox!.get(key);
        if (value is! Map) continue;

        final map = Map<String, dynamic>.from(value);

        if (key is String && key.startsWith(_auditLegacyPrefix)) {
          logs.add(map);
        } else if (map.containsKey('action') && map.containsKey('userId')) {
          // New AuditEventLog format - map to legacy-compatible structure for UI
          final createdAt =
              map['createdAt'] as String? ?? DateTime.now().toIso8601String();
          final rawData = map['data'] is String
              ? jsonDecode(map['data'])
              : (map['data'] ?? {});

          final Map<String, dynamic> dataMap = rawData is Map
              ? Map<String, dynamic>.from(rawData)
              : {};

          // Extract details: handle both flat and nested (for transition period)
          final Map<String, dynamic> finalDetails =
              dataMap.containsKey('details') && dataMap['details'] is Map
              ? Map<String, dynamic>.from(dataMap['details'])
              : dataMap;

          logs.add({
            'actionType': map['action'],
            'performedBy': map['userId'],
            'comment': dataMap['comment'] ?? '',
            'details': finalDetails,
            'timestamp': createdAt,
            'date': createdAt.split('T')[0],
          });
        }
      }
    }

    var filtered = logs;
    if (date != null) {
      filtered = filtered
          .where((log) => (log['date'] as String?) == date)
          .toList();
    }
    if (actionType != null) {
      filtered = filtered
          .where((log) => (log['actionType'] as String?) == actionType)
          .toList();
    }

    filtered.sort(
      (a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String),
    );

    return filtered;
  }

  // ==================== ERROR LOG METHODS ====================

  static Future<void> logError({
    required String title,
    required Object error,
    required StackTrace stackTrace,
    String? context,
    String? performedBy,
    Map<String, dynamic>? metadata,
  }) async {
    if (_errorLogBox == null) {
      return;
    }

    final timestamp = getCurrentDateTime();
    final logKey = 'error_${timestamp.microsecondsSinceEpoch}';
    final log = <String, dynamic>{
      'title': title,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
      'context': context ?? '',
      'performedBy': performedBy ?? '',
      'metadata': metadata ?? <String, dynamic>{},
      'timestamp': timestamp.toIso8601String(),
      'date': timestamp.toIso8601String().split('T')[0],
    };

    await _errorLogBox!.put(logKey, log);
    developer.log(
      'Error logged: $title',
      name: 'ErrorLog',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static List<Map<String, dynamic>> getErrorLogs({String? date}) {
    if (_errorLogBox == null) {
      return [];
    }

    final logs = <Map<String, dynamic>>[];
    for (final key in _errorLogBox!.keys) {
      final raw = _errorLogBox!.get(key);
      if (raw is Map) {
        logs.add(Map<String, dynamic>.from(raw));
      }
    }

    var filtered = logs;
    if (date != null) {
      filtered = filtered
          .where((log) => (log['date'] as String?) == date)
          .toList();
    }

    filtered.sort(
      (a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String),
    );

    return filtered;
  }

  static Future<void> clearErrorLogs() async {
    await _errorLogBox?.clear();
  }

  // ==================== RESERVATION METHODS ====================

  // Create a new reservation
  static Future<String> createReservation({
    required String customerName,
    required String customerPhone,
    required List<int> tableNumbers,
    required DateTime reservationDate,
    required String reservationTime,
    required int numberOfGuests,
    String? notes,
    required String createdBy,
    List<OrderItem>? preOrderItems,
    bool isTakeAway = false,
    int? linkedOrderId,
    String status = 'pending',
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // All new reservations start as pending (will be confirmed manually when date arrives)
    final reservation = Reservation(
      id: id,
      customerName: customerName,
      customerPhone: customerPhone,
      tableNumbers: tableNumbers,
      reservationDate: reservationDate,
      reservationTime: reservationTime,
      numberOfGuests: numberOfGuests,
      notes: notes,
      createdAt: getCurrentDateTime(),
      createdBy: createdBy,
      status: status,
      preOrderItems: preOrderItems,
      isTakeAway: isTakeAway,
      linkedOrderId: linkedOrderId,
    );

    await _reservationBox!.add(reservation);
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'created',
        payload: {'reservationId': id},
      ),
    );
    return id;
  }

  // Get all reservations
  static List<Reservation> getAllReservations() {
    return _reservationBox!.values.toList();
  }

  // Get a reservation by its key (ID)
  static Reservation? getReservation(String reservationId) {
    try {
      final key = int.parse(reservationId);
      return _reservationBox!.get(key);
    } catch (e) {
      return null;
    }
  }

  // Get reservations for a specific date
  static List<Reservation> getReservationsForDate(DateTime date) {
    return _reservationBox!.values
        .where(
          (r) => ReservationTableAvailability.isSameCalendarDate(
            r.reservationDate,
            date,
          ),
        )
        .toList();
  }

  /// Real bookings on [date] that already hold table numbers (excludes walk-ins).
  static List<Reservation> getTableBlockingReservationsForDate(DateTime date) {
    return getReservationsForDate(date).where((reservation) {
      if (!ReservationTableAvailability.isRealTableBooking(reservation)) {
        return false;
      }
      if (!ReservationTableAvailability.isReservationBlocking(
        reservation.status,
      )) {
        return false;
      }
      return reservation.tableNumbers.isNotEmpty;
    }).toList();
  }

  static Future<bool> cancelReservationByOrderId(int orderId) async {
    try {
      for (final reservation in _reservationBox!.values) {
        final matchesLinked = reservation.linkedOrderId == orderId;
        final matchesNote =
            reservation.notes != null &&
            reservation.notes!.contains('Order #$orderId');
        if (matchesLinked || matchesNote) {
          reservation.status = 'cancelled';
          await reservation.save();
          return true;
        }
      }
      return false;
    } catch (e) {
      developer.log('Error cancelling reservation by order id: $e');
      return false;
    }
  }

  static Reservation? findReservationForOrder(Order order) {
    try {
      final orderDateKey = order.createdAt.toIso8601String().split('T')[0];
      bool matchesOrderDate(Reservation reservation) {
        final reservationDateKey = reservation.reservationDate
            .toIso8601String()
            .split('T')[0];
        return reservationDateKey == orderDateKey;
      }

      if (_tableBox != null) {
        for (final table in _tableBox!.values) {
          if (table.activeOrderId == order.orderId &&
              table.reservationId != null) {
            final linked = _findReservationById(table.reservationId!);
            if (linked != null && matchesOrderDate(linked)) {
              return linked;
            }
          }
        }
      }

      final isTakeAway = _isOrderTakeAway(order);

      for (final reservation in _reservationBox!.values) {
        if (reservation.linkedOrderId == order.orderId &&
            reservation.isTakeAway == isTakeAway &&
            matchesOrderDate(reservation)) {
          final name = reservation.customerName.trim().toLowerCase();
          if (name.isNotEmpty && name != 'walk-in') {
            return reservation;
          }
        }
      }

      for (final reservation in _reservationBox!.values) {
        if (reservation.linkedOrderId == order.orderId &&
            reservation.isTakeAway == isTakeAway &&
            matchesOrderDate(reservation)) {
          return reservation;
        }
      }

      for (final reservation in _reservationBox!.values) {
        if (reservation.linkedOrderId == order.orderId &&
            matchesOrderDate(reservation)) {
          return reservation;
        }
      }

      final targetNote = 'Order #${order.orderId}';
      for (final reservation in _reservationBox!.values) {
        final note = reservation.notes;
        if (note != null &&
            note.contains(targetNote) &&
            reservation.isTakeAway == isTakeAway &&
            matchesOrderDate(reservation)) {
          return reservation;
        }
      }

      for (final reservation in _reservationBox!.values) {
        final note = reservation.notes;
        if (note != null &&
            note.contains(targetNote) &&
            matchesOrderDate(reservation)) {
          return reservation;
        }
      }
    } catch (e) {
      developer.log('Error finding reservation for order ${order.orderId}: $e');
    }
    return null;
  }

  static bool _isOrderTakeAway(Order order) {
    final floorLabel = order.floor.toLowerCase();
    if (floorLabel == 'takeaway' ||
        floorLabel == 'take-away' ||
        floorLabel.contains('take away')) {
      return true;
    }

    for (final table in order.tableNumbers) {
      final normalized = table.toLowerCase();
      if (normalized.startsWith('ta-') || normalized.contains('take away')) {
        return true;
      }
    }

    return false;
  }

  static List<Reservation> getTakeAwayReservationsForDate(DateTime date) {
    final dateString = date.toIso8601String().split('T')[0];
    final reservationsForDate = _reservationBox!.values.where((r) {
      if (!r.isTakeAway) return false;
      final reservationDateString = r.reservationDate.toIso8601String().split(
        'T',
      )[0];
      return reservationDateString == dateString;
    }).toList();

    reservationsForDate.sort((a, b) {
      final orderIdComparison = (b.linkedOrderId ?? 0).compareTo(
        a.linkedOrderId ?? 0,
      );
      if (orderIdComparison != 0) {
        return orderIdComparison;
      }

      final createdAtComparison = b.createdAt.compareTo(a.createdAt);
      if (createdAtComparison != 0) {
        return createdAtComparison;
      }
      return b.id.compareTo(a.id);
    });

    return reservationsForDate;
  }

  // Get reservations by status
  static List<Reservation> getReservationsByStatus(String status) {
    return _reservationBox!.values.where((r) => r.status == status).toList();
  }

  /// Returns only dates that were real operated business days (have sales records)
  /// plus the current business date. Excludes reservation-only future dates.
  static List<DateTime> getOperatedBusinessDates() {
    final dates = <String>{
      ..._getOperatedBusinessDateKeys(),
      getCurrentDate().toIso8601String().split('T')[0],
    };

    for (final sale in _salesBox!.values) {
      final date = (sale as Map)['date'] as String?;
      if (date != null && date.isNotEmpty) {
        dates.add(date);
      }
    }

    final parsedDates = dates
        .where((date) => date.isNotEmpty)
        .map((date) => DateTime.parse(date))
        .toList();

    parsedDates.sort();
    return parsedDates;
  }

  static List<DateTime> getKnownBusinessDates() {
    final dates = <String>{getCurrentDate().toIso8601String().split('T')[0]};

    for (final sale in _salesBox!.values) {
      final date = (sale as Map)['date'] as String?;
      if (date != null && date.isNotEmpty) {
        dates.add(date);
      }
    }

    for (final reservation in _reservationBox!.values) {
      dates.add(reservation.reservationDate.toIso8601String().split('T')[0]);
    }

    final parsedDates = dates
        .where((date) => date.isNotEmpty)
        .map((date) => DateTime.parse(date))
        .toList();

    parsedDates.sort();
    return parsedDates;
  }

  // Update reservation status
  static Future<void> updateReservationStatus(
    String reservationId,
    String newStatus,
  ) async {
    final reservation = _reservationBox!.values.firstWhere(
      (r) => r.id == reservationId,
    );
    reservation.status = newStatus;
    await reservation.save();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'updated',
        payload: {'reservationId': reservationId},
      ),
    );
  }

  static Future<void> updateReservationPreOrderItems(
    String reservationId,
    List<OrderItem> updatedItems,
  ) async {
    final reservation = _reservationBox!.values.firstWhere(
      (r) => r.id == reservationId,
    );

    final clonedItems = updatedItems
        .map(
          (item) => OrderItem(
            itemKey: item.itemKey,
            itemName: item.itemName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            total: item.unitPrice * item.quantity,
            comment: item.comment,
          ),
        )
        .toList();

    if (clonedItems.isEmpty) {
      reservation.preOrderItems = null;
      if (reservation.status == 'preparing') {
        reservation.status = 'pending';
      }
    } else {
      reservation.preOrderItems = clonedItems;
      if (reservation.status == 'pending') {
        reservation.status = 'preparing';
      }
    }

    await reservation.save();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'updated',
        payload: {'reservationId': reservationId},
      ),
    );
  }

  static Future<void> updateReservationTables(
    String reservationId,
    List<int> tableNumbers,
  ) async {
    final reservations = _reservationBox!.values.where(
      (r) => r.id == reservationId,
    );
    if (reservations.isEmpty) {
      developer.log(
        'Warning: Tried to update tables for missing reservation $reservationId',
      );
      return;
    }
    final reservation = reservations.first;

    reservation.tableNumbers = List<int>.from(tableNumbers);
    if (reservation.status == 'pending') {
      reservation.status = 'confirmed';
    }
    await reservation.save();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.reservations,
        action: 'updated',
        payload: {'reservationId': reservationId},
      ),
    );
  }

  static Future<int?> activateReservation({
    required String reservationId,
    required String activatedBy,
  }) async {
    try {
      final reservations = _reservationBox!.values.where(
        (r) => r.id == reservationId,
      );
      if (reservations.isEmpty) {
        developer.log(
          'Warning: Tried to activate missing reservation $reservationId',
        );
        return null;
      }
      final reservation = reservations.first;

      if (reservation.isTakeAway) {
        return reservation.linkedOrderId;
      }

      if (reservation.tableNumbers.isEmpty) {
        return null;
      }

      final hasVipTables = reservation.tableNumbers.any(
        (number) => number > 10,
      );
      final hasFirstFloorTables = reservation.tableNumbers.any(
        (number) => number <= 10,
      );

      if (hasVipTables && hasFirstFloorTables) {
        developer.log(
          'Failed to activate reservation $reservationId: mixed-floor tables are not supported',
        );
        return null;
      }

      final floor = hasVipTables ? 'second' : 'first';

      Future<void> ensureTablesReserved(int orderId) async {
        for (final tableNumber in reservation.tableNumbers) {
          final targetFloor = tableNumber > 10 ? 'second' : 'first';
          final normalized = tableNumber > 10
              ? (tableNumber - 10).toString()
              : '$tableNumber';
          await reserveTable(
            tableNumber: normalized,
            floor: targetFloor,
            username: activatedBy,
            orderId: orderId,
            reservationId: reservation.id,
          );
        }
      }

      final existingOrderId = reservation.linkedOrderId;
      if (existingOrderId != null) {
        final existingOrder = getOrder(existingOrderId);
        if (existingOrder != null) {
          await ensureTablesReserved(existingOrderId);
          if (existingOrder.status.toLowerCase() != 'confirmed') {
            existingOrder.status = 'confirmed';
            await existingOrder.save();
          }
          reservation.status = 'in-progress';
          reservation.notes ??=
              'Order #$existingOrderId - ${reservation.customerName}';
          await reservation.save();
          return existingOrderId;
        }
        reservation.linkedOrderId = null;
      }

      final order = await createOrder(
        tableNumbers: reservation.tableNumbers
            .map(
              (number) =>
                  number > 10 ? (number - 10).toString() : number.toString(),
            )
            .toList(),
        floor: floor,
        createdBy: activatedBy,
        items: reservation.preOrderItems ?? const <OrderItem>[],
        createReservationRecord: false,
      );

      // Set openedByUserId to track who activated this reservation
      order.openedByUserId = activatedBy;

      // Restore reservation link on tables (createOrder clears reservationId)
      await ensureTablesReserved(order.orderId);

      order.status = 'confirmed';
      await order.save();

      reservation.status = 'in-progress';
      if (reservation.notes == null || reservation.notes!.trim().isEmpty) {
        reservation.notes =
            'Order #${order.orderId} - ${reservation.customerName}';
      }
      reservation.linkedOrderId = order.orderId;
      await reservation.save();

      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.reservations,
          action: 'activated',
          payload: {'reservationId': reservationId, 'orderId': order.orderId},
        ),
      );

      return order.orderId;
    } catch (error) {
      developer.log('Failed to activate reservation $reservationId: $error');
      return null;
    }
  }

  // Delete reservation
  static Future<void> deleteReservation(String reservationId) async {
    try {
      final reservation = _reservationBox!.values.firstWhere(
        (r) => r.id == reservationId,
      );
      await reservation.delete();
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.reservations,
          action: 'deleted',
          payload: {'reservationId': reservationId},
        ),
      );
    } catch (e) {
      developer.log('Error deleting reservation: $e');
    }
  }

  // Check if tables are available for a specific date
  static bool areTablesAvailableForReservation({
    required List<int> tableNumbers,
    required DateTime reservationDate,
    required String reservationTime,
    String? excludeReservationId,
  }) {
    if (tableNumbers.isEmpty) {
      return true;
    }
    return ReservationTableAvailability.areTableCodesAvailable(
      tableCodes: tableNumbers,
      reservations: getTableBlockingReservationsForDate(reservationDate),
      excludeReservationId: excludeReservationId,
    );
  }

  // Activate today's confirmed reservations (called when app starts or day opens)
  static Future<void> activateTodaysReservations() async {
    developer.log('========================================');
    developer.log('ACTIVATE TODAY\'S RESERVATIONS - CALLED');

    final currentDate = getCurrentDate();
    final currentDateString = currentDate.toIso8601String().split('T')[0];

    developer.log(
      'Current business date: ${getGeorgianFormattedDate(currentDate)} ($currentDateString)',
    );
    developer.log('\nALL RESERVATIONS IN DATABASE:');

    for (var r in _reservationBox!.values) {
      final resDateString = r.reservationDate.toIso8601String().split('T')[0];
      developer.log('  - ${r.customerName}:');
      developer.log(
        '    Date: $resDateString (${getGeorgianFormattedDate(r.reservationDate)})',
      );
      developer.log('    Status: ${r.status}');
      developer.log('    Tables: ${r.tableNumbers.join(", ")}');
      developer.log('    Notes: ${r.notes ?? "null"}');
    }

    developer.log('\nFILTERING FOR TODAY\'S CONFIRMED RESERVATIONS:');

    // Get all confirmed reservations for today that haven't been activated yet
    final todaysReservations = _reservationBox!.values.where((r) {
      if (r.isTakeAway) {
        return false;
      }
      final resDateString = r.reservationDate.toIso8601String().split('T')[0];
      final isToday = resDateString == currentDateString;
      final isConfirmed = r.status == 'confirmed';
      final notActivated =
          r.notes == null ||
          (!r.notes!.startsWith('Order #') &&
              !r.notes!.startsWith('Reservation activated'));

      developer.log(
        '  ${r.customerName}: IsToday=$isToday, IsConfirmed=$isConfirmed, NotActivated=$notActivated',
      );

      return isToday && isConfirmed && notActivated;
    }).toList();

    developer.log(
      '\n✅ Found ${todaysReservations.length} reservations to activate',
    );

    // Show current reserved tables BEFORE activation
    developer.log('\nCURRENT RESERVED TABLES (before activation):');
    final reservedTablesBefore = _tableBox!.values
        .where((t) => t.isReserved)
        .toList();
    if (reservedTablesBefore.isEmpty) {
      developer.log('  None');
    } else {
      for (var table in reservedTablesBefore) {
        developer.log(
          '  - Table ${table.tableNumber} (${table.floor}): Reserved by ${table.reservedBy}',
        );
      }
    }

    if (todaysReservations.isEmpty) {
      developer.log(
        '\n❌ No reservations to activate - exiting without changes',
      );
      developer.log('========================================');
      return;
    }

    // Reserve tables for each confirmed reservation
    for (var reservation in todaysReservations) {
      developer.log(
        '\n🔄 Activating reservation for ${reservation.customerName}:',
      );
      developer.log('  Tables: ${reservation.tableNumbers.join(", ")}');
      developer.log('  Time: ${reservation.reservationTime}');

      // Convert table numbers to table names
      final tableNames = <String>[];
      for (var num in reservation.tableNumbers) {
        if (num <= 10) {
          tableNames.add('Table $num');
        } else {
          tableNames.add('VIP Zone ${num - 10}');
        }
      }

      // Determine floor based on table numbers
      String floor = 'first';
      if (reservation.tableNumbers.any((n) => n > 10)) {
        floor = 'second';
      }

      developer.log(
        '  Reserving tables: ${tableNames.join(", ")} on $floor floor',
      );
      developer.log(
        '  Pre-order items: ${reservation.preOrderItems?.length ?? 0}',
      );

      // Create order with pre-order items (or empty if no pre-order)
      final order = await createOrder(
        tableNumbers: reservation.tableNumbers
            .map((n) => n.toString())
            .toList(),
        floor: floor,
        createdBy: 'System (Reservation)',
        items:
            reservation.preOrderItems ??
            [], // Use pre-order items or empty list
        createReservationRecord: false,
      );

      // If there are pre-order items, mark order as confirmed (already sent to kitchen)
      if (reservation.preOrderItems != null &&
          reservation.preOrderItems!.isNotEmpty) {
        order.status = 'confirmed';
        await order.save();
        developer.log(
          '  ✅ Order #${order.orderId} status set to "confirmed" (pre-ordered items)',
        );
      }

      developer.log(
        '  ✅ Order #${order.orderId} created with ${reservation.preOrderItems?.length ?? 0} items',
      );

      // Update reservation status to 'in-progress' and link to order
      reservation.status = 'in-progress';
      reservation.notes =
          'Order #${order.orderId} - ${reservation.customerName}';
      reservation.linkedOrderId = order.orderId;
      await reservation.save();

      developer.log(
        '  ✅ Activated successfully - Reservation ID: ${reservation.key}, Order ID: ${order.orderId}',
      );
    }

    // Show reserved tables AFTER activation
    developer.log('\nCURRENT RESERVED TABLES (after activation):');
    final reservedTablesAfter = _tableBox!.values
        .where((t) => t.isReserved)
        .toList();
    if (reservedTablesAfter.isEmpty) {
      developer.log('  None');
    } else {
      for (var table in reservedTablesAfter) {
        developer.log(
          '  - Table ${table.tableNumber} (${table.floor}): Reserved=${table.isReserved}, ReservationId=${table.reservationId}, OrderId=${table.activeOrderId}',
        );
      }
    }

    developer.log('\n✅ All today\'s reservations activated');
    developer.log('========================================');
  }
}
