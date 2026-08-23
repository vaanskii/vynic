import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/transactions/activate_reservation_transaction.dart';
import 'package:vynic/core/database/transactions/close_day_transaction.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/reservation_repository.dart';
import 'package:vynic/core/database/repositories/package_repository.dart';
import 'package:vynic/core/database/repositories/quick_order_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/repositories/error_log_repository.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/database/repositories/table_repository.dart';
import 'package:vynic/core/database/repositories/user_repository.dart';
import 'package:vynic/core/services/audit/audit_event_service.dart';

export 'package:vynic/core/database/repositories/reservation_repository.dart'
    show ReservationActivationResult;

class DatabaseService {
  // Boxes live in DatabaseCore; these private getters keep the (not yet
  // extracted) domain code below compiling unchanged during the Phase 2 split.
  static Box<User>? get _userBox => DatabaseCore.userBox;
  static Box<TableModel>? get _tableBox => DatabaseCore.tableBox;
  static Box<Order>? get _orderBox => DatabaseCore.orderBox;
  static Box<MenuCategoryDB>? get _menuBox => DatabaseCore.menuBox;
  static Box? get _auditLogBox => DatabaseCore.auditLogBox;
  static String get _dataDirectoryPath => DatabaseCore.dataDirectoryPath;

  static Box getAuditLogBox() {
    if (_auditLogBox == null) {
      throw StateError('AuditLog box is not initialized');
    }
    return _auditLogBox!;
  }

  /// Injected by ManagerSyncService so audit changes trigger a server push.
  static void registerAuditChangedCallback(void Function() cb) =>
      AuditRepository.registerAuditChangedCallback(cb);

  /// Injected by ManagerSyncService so user/PIN changes sync to the backend.
  static void registerUsersChangedCallback(void Function() cb) =>
      UserRepository.registerUsersChangedCallback(cb);

  static int get dbVersion => DatabaseCore.dbVersion;

  static List<String> get kitchenExcludedCategoryKeywords =>
      MenuRepository.kitchenExcludedCategoryKeywords;

  static Map<String, List<String>> getTableLayout() =>
      TableRepository.getTableLayout();

  static RestaurantTableLayout getRestaurantTableLayout() =>
      TableRepository.getRestaurantTableLayout();

  static Future<void> saveActiveRestaurantTableLayout(
    RestaurantTableLayout layout,
  ) => TableRepository.saveActiveRestaurantTableLayout(layout);

  static Future<void> clearActiveRestaurantTableLayout() =>
      TableRepository.clearActiveRestaurantTableLayout();

  static List<String> getAllTableNumbers() =>
      TableRepository.getAllTableNumbers();
  // ==================== QUICK ORDER DRAFTS ====================

  static List<QuickOrderDraft> getQuickOrderDrafts() =>
      QuickOrderRepository.getQuickOrderDrafts();

  static QuickOrderDraft? getQuickOrderDraft(String id) =>
      QuickOrderRepository.getQuickOrderDraft(id);

  static Future<QuickOrderDraft> saveQuickOrderDraft({
    required String createdBy,
    required List<OrderItem> items,
    required double subtotal,
    required bool includeServiceFee,
    required double serviceFeeRate,
    String? displayName,
  }) => QuickOrderRepository.saveQuickOrderDraft(
    createdBy: createdBy,
    items: items,
    subtotal: subtotal,
    includeServiceFee: includeServiceFee,
    serviceFeeRate: serviceFeeRate,
    displayName: displayName,
  );

  static Future<QuickOrderDraft> updateQuickOrderDraft({
    required String id,
    required String createdBy,
    required List<OrderItem> items,
    required double subtotal,
    required bool includeServiceFee,
    required double serviceFeeRate,
    String? displayName,
  }) => QuickOrderRepository.updateQuickOrderDraft(
    id: id,
    createdBy: createdBy,
    items: items,
    subtotal: subtotal,
    includeServiceFee: includeServiceFee,
    serviceFeeRate: serviceFeeRate,
    displayName: displayName,
  );

  static Future<void> deleteQuickOrderDraft(String id) =>
      QuickOrderRepository.deleteQuickOrderDraft(id);

  static Future<void> setQuickOrderDraftDisplayName({
    required String id,
    String? displayName,
  }) => QuickOrderRepository.setQuickOrderDraftDisplayName(
    id: id,
    displayName: displayName,
  );

  static Future<void> clearQuickOrderDrafts() =>
      QuickOrderRepository.clearQuickOrderDrafts();

  // ==================== PACKAGES ====================

  static List<Package> getAllPackages({bool includeInactive = true}) =>
      PackageRepository.getAllPackages(includeInactive: includeInactive);

  static Package? getPackageById(String packageId) =>
      PackageRepository.getPackageById(packageId);

  static Future<Package> createPackage({
    required String name,
    String? description,
    required List<PackageItem> items,
    required double pricePerPerson,
    required int servingSize,
    required String createdBy,
    List<String>? allowedTables,
  }) => PackageRepository.createPackage(
    name: name,
    description: description,
    items: items,
    pricePerPerson: pricePerPerson,
    servingSize: servingSize,
    createdBy: createdBy,
    allowedTables: allowedTables,
  );

  static Future<Package> updatePackage({
    required String packageId,
    required String name,
    String? description,
    required List<PackageItem> items,
    required double pricePerPerson,
    required int servingSize,
    bool? isActive,
    List<String>? allowedTables,
  }) => PackageRepository.updatePackage(
    packageId: packageId,
    name: name,
    description: description,
    items: items,
    pricePerPerson: pricePerPerson,
    servingSize: servingSize,
    isActive: isActive,
    allowedTables: allowedTables,
  );

  static Future<void> deletePackage(String packageId) =>
      PackageRepository.deletePackage(packageId);

  static Future<void> setPackageActive({
    required String packageId,
    required bool isActive,
  }) => PackageRepository.setPackageActive(
    packageId: packageId,
    isActive: isActive,
  );

  static bool shouldCategorySendToKitchenByDefault(
    String? slug, {
    String? nameEn,
    String? nameKa,
  }) => MenuRepository.shouldCategorySendToKitchenByDefault(
    slug,
    nameEn: nameEn,
    nameKa: nameKa,
  );

  // Initialize Hive and create default admin user
  static Future<void> init() async {
    // Storage bootstrap: data directory, Hive init, adapters, boxes,
    // schema migrations.
    await DatabaseCore.open();

    await _migrateLegacyStaffRoles();

    // First-run defaults (current date, sales total, printers, service fee,
    // language, monthly-report inputs).
    await SettingsRepository.seedDefaults();

    // Create default admin user if no users exist
    if (_userBox!.isEmpty) {
      await createDefaultAdmin();
    }

    // Initialize tables if empty
    if (_tableBox!.isEmpty) {
      await TableRepository.initializeTables();
    }
    await TableRepository.ensureTableLayoutConsistency();

    // Initialize menu from JSON if empty
    if (_menuBox!.isEmpty) {
      await MenuRepository.initializeMenuFromJson();
    }

    await MenuRepository.ensureKitchenRoutingDefaults();

    Order.serviceFeeRateResolver = () => getServiceFeeRate();
    Order.timestampResolver = () => getCurrentDateTime();

    // Initialize Event-based Audit system
    AuditEventService.initialize();

    // One-time cleanup: older data may contain multiple OPEN reports
    // for the same floor + table set. Keep newest open, close the rest.
    await AuditRepository.runAuditDuplicateOpenCleanupOnce();
  }

  /// Shared secret for server → POS HTTP callbacks (`x-connection-key`).
  static String ensurePosIngestConnectionKey() =>
      SettingsRepository.ensurePosIngestConnectionKey();

  static String? getPosIngestConnectionKey() =>
      SettingsRepository.getPosIngestConnectionKey();

  static DateTime? getLastManagerSyncAt() =>
      SettingsRepository.getLastManagerSyncAt();

  static Future<void> saveLastManagerSyncAt(DateTime value) =>
      SettingsRepository.saveLastManagerSyncAt(value);

  static String? getBackendUrlOverride() =>
      SettingsRepository.getBackendUrlOverride();

  static Future<void> saveBackendUrlOverride(String value) =>
      SettingsRepository.saveBackendUrlOverride(value);

  static Future<void> clearBackendUrlOverride() =>
      SettingsRepository.clearBackendUrlOverride();

  static Map<String, dynamic> serializeReservationForSync(
    Reservation reservation,
  ) => BackupRepository.serializeReservationForSync(reservation);

  /// Maps legacy Hive `admin` role to `manager`.
  static Future<void> _migrateLegacyStaffRoles() =>
      UserRepository.migrateLegacyStaffRoles();

  // Create default manager user
  static Future<void> createDefaultAdmin() =>
      UserRepository.createDefaultAdmin();

  // Add a new user
  static Future<bool> addUser({
    required String username,
    required String pinCode,
    required String role,
  }) =>
      UserRepository.addUser(username: username, pinCode: pinCode, role: role);

  // Check if a PIN code already exists
  static bool isPinCodeExists(String pinCode) =>
      UserRepository.isPinCodeExists(pinCode);

  // Authenticate user by PIN code
  static User? authenticateByPin(String pinCode) =>
      UserRepository.authenticateByPin(pinCode);

  // Get all users
  static List<User> getAllUsers() => UserRepository.getAllUsers();

  // Get user by username
  static User? getUserByUsername(String username) =>
      UserRepository.getUserByUsername(username);

  static String getDisplayOperatorName(
    String? username, {
    bool isEnglish = false,
  }) => UserRepository.getDisplayOperatorName(username, isEnglish: isEnglish);

  // Update user
  static Future<void> updateUser(User user) => UserRepository.updateUser(user);

  static Future<bool> renameUserByUsername({
    required String oldUsername,
    required String newUsername,
  }) => UserRepository.renameUserByUsername(
    oldUsername: oldUsername,
    newUsername: newUsername,
  );

  static Future<bool> updateUserPinByUsername({
    required String username,
    required String pinCode,
  }) => UserRepository.updateUserPinByUsername(
    username: username,
    pinCode: pinCode,
  );

  static Future<bool> updateUserRoleByUsername({
    required String username,
    required String role,
  }) => UserRepository.updateUserRoleByUsername(username: username, role: role);

  // Delete user
  static Future<void> deleteUser(User user) => UserRepository.deleteUser(user);

  static Future<bool> deleteUserByUsername(String username) =>
      UserRepository.deleteUserByUsername(username);

  // Get users box
  static Box<User>? get userBox => _userBox;

  // ========== TABLE MANAGEMENT ==========

  static List<TableModel> getAllTables() => TableRepository.getAllTables();

  static List<TableModel> getTablesByFloor(String floor) =>
      TableRepository.getTablesByFloor(floor);

  static TableModel? getTable(String tableNumber, String floor) =>
      TableRepository.getTable(tableNumber, floor);

  static bool isTableConfigured({
    required String tableNumber,
    required String floor,
  }) =>
      TableRepository.isTableConfigured(tableNumber: tableNumber, floor: floor);

  static Future<void> reserveTable({
    required String tableNumber,
    required String floor,
    required String username,
    required int orderId,
    String? reservationId,
  }) => TableRepository.reserveTable(
    tableNumber: tableNumber,
    floor: floor,
    username: username,
    orderId: orderId,
    reservationId: reservationId,
  );

  static Future<void> reserveTableForReservation({
    required String tableNumber,
    required String floor,
    required String username,
    required String reservationId,
  }) => TableRepository.reserveTableForReservation(
    tableNumber: tableNumber,
    floor: floor,
    username: username,
    reservationId: reservationId,
  );

  static Future<bool> completeReservationForOrder(int orderId) =>
      ReservationRepository.completeReservationByOrderId(orderId);

  static Future<void> freeTable({
    required String tableNumber,
    required String floor,
  }) => TableRepository.freeTable(tableNumber: tableNumber, floor: floor);

  // Public helper to fetch reservation by ID (used by UI overlays)
  static Reservation? findReservationById(String reservationId) =>
      ReservationRepository.findReservationById(reservationId);

  static List<Map<String, dynamic>> getReservedTableDiagnostics() =>
      TableRepository.getReservedTableDiagnostics();

  static Future<List<Map<String, dynamic>>> releaseStaleReservedTables() =>
      TableRepository.releaseStaleReservedTables();

  static Future<void> syncTableReservationsForCurrentDate() =>
      TableRepository.syncTableReservationsForCurrentDate();

  // ========== ORDER MANAGEMENT ==========

  static Future<Order> createOrder({
    required List<String> tableNumbers,
    required String floor,
    required String createdBy,
    required List<OrderItem> items,
    bool? includeServiceFee,
    bool createReservationRecord = true,
  }) => OrderRepository.createOrder(
    tableNumbers: tableNumbers,
    floor: floor,
    createdBy: createdBy,
    items: items,
    includeServiceFee: includeServiceFee,
    createReservationRecord: createReservationRecord,
  );

  static Future<Order> createTakeAwayOrder({
    required String customerName,
    required String customerPhone,
    required String pickupTime,
    String? notes,
    required List<OrderItem> items,
    required String createdBy,
  }) => OrderRepository.createTakeAwayOrder(
    customerName: customerName,
    customerPhone: customerPhone,
    pickupTime: pickupTime,
    notes: notes,
    items: items,
    createdBy: createdBy,
  );

  static Future<Order?> upsertMobileTakeawayOrder({
    required int posOrderId,
    required String customerName,
    required String pickupTime,
    required String waiterName,
    required List<OrderItem> items,
    double? totalAmount,
  }) => OrderRepository.upsertMobileTakeawayOrder(
    posOrderId: posOrderId,
    customerName: customerName,
    pickupTime: pickupTime,
    waiterName: waiterName,
    items: items,
    totalAmount: totalAmount,
  );

  static Future<Order?> upsertMobileDineInOrder({
    required int posOrderId,
    required List<String> tableNumbers,
    required String floor,
    required String waiterName,
    required List<OrderItem> items,
    int guestCount = 0,
    double? totalAmount,
  }) => OrderRepository.upsertMobileDineInOrder(
    posOrderId: posOrderId,
    tableNumbers: tableNumbers,
    floor: floor,
    waiterName: waiterName,
    items: items,
    guestCount: guestCount,
    totalAmount: totalAmount,
  );

  static Future<Order> createOrderForPackage({
    required Package package,
    required List<String> tableNumbers,
    required String floor,
    required int guestCount,
    required String createdBy,
  }) => OrderRepository.createOrderForPackage(
    package: package,
    tableNumbers: tableNumbers,
    floor: floor,
    guestCount: guestCount,
    createdBy: createdBy,
  );

  static Order? getOrder(int orderId) => OrderRepository.getOrder(orderId);

  static List<Order> getAllOrders() => OrderRepository.getAllOrders();

  static List<Order> getActiveOrders() => OrderRepository.getActiveOrders();

  static Future<void> updateOrder(
    Order order, {
    bool? previousIncludeServiceFee,
  }) => OrderRepository.updateOrder(
    order,
    previousIncludeServiceFee: previousIncludeServiceFee,
  );

  static Future<void> updateOrderStatus({
    required int orderId,
    required String status,
  }) => OrderRepository.updateOrderStatus(orderId: orderId, status: status);

  static Future<bool> deleteOrderAndCleanup({
    required int orderId,
    required String deletedBy,
    bool cancelLinkedReservation = true,
  }) => OrderRepository.deleteOrderAndCleanup(
    orderId: orderId,
    deletedBy: deletedBy,
    cancelLinkedReservation: cancelLinkedReservation,
  );

  static Future<int> deleteOpenOrdersForDate({
    required DateTime date,
    required String deletedBy,
    bool includeTakeAway = true,
  }) => OrderRepository.deleteOpenOrdersForDate(
    date: date,
    deletedBy: deletedBy,
    includeTakeAway: includeTakeAway,
  );

  static Future<void> addItemToOrder({
    required int orderId,
    required OrderItem item,
  }) => OrderRepository.addItemToOrder(orderId: orderId, item: item);

  static Future<void> removeItemFromOrder({
    required int orderId,
    required String itemKey,
  }) => OrderRepository.removeItemFromOrder(orderId: orderId, itemKey: itemKey);

  static Future<void> updateOrderItemQuantity({
    required int orderId,
    required String itemKey,
    required int quantity,
  }) => OrderRepository.updateOrderItemQuantity(
    orderId: orderId,
    itemKey: itemKey,
    quantity: quantity,
  );

  // Get tables box
  static Box<TableModel>? get tableBox => _tableBox;

  // Get orders box
  static Box<Order>? get orderBox => _orderBox;

  // ==================== MENU METHODS ====================

  static List<MenuCategoryDB> getAllMenuCategories() =>
      MenuRepository.getAllMenuCategories();

  static Future<void> clearMenuCache() => MenuRepository.clearMenuCache();

  // ==================== MENU CRUD METHODS ====================

  static Future<bool> addCategory({
    required String slug,
    required String nameEn,
    required String nameKa,
    bool? sendToKitchen,
  }) => MenuRepository.addCategory(
    slug: slug,
    nameEn: nameEn,
    nameKa: nameKa,
    sendToKitchen: sendToKitchen,
  );

  static Future<bool> updateCategory({
    required int index,
    required String slug,
    required String nameEn,
    required String nameKa,
    bool? sendToKitchen,
  }) => MenuRepository.updateCategory(
    index: index,
    slug: slug,
    nameEn: nameEn,
    nameKa: nameKa,
    sendToKitchen: sendToKitchen,
  );

  static Future<bool> deleteCategory(int index) =>
      MenuRepository.deleteCategory(index);

  static Future<bool> addItemToCategory({
    required int categoryIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
  }) => MenuRepository.addItemToCategory(
    categoryIndex: categoryIndex,
    nameEn: nameEn,
    nameKa: nameKa,
    price: price,
    variants: variants,
    sendToKitchen: sendToKitchen,
  );

  static Future<bool> updateItemInCategory({
    required int categoryIndex,
    required int itemIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
  }) => MenuRepository.updateItemInCategory(
    categoryIndex: categoryIndex,
    itemIndex: itemIndex,
    nameEn: nameEn,
    nameKa: nameKa,
    price: price,
    variants: variants,
    sendToKitchen: sendToKitchen,
  );

  static Future<bool> deleteItemFromCategory({
    required int categoryIndex,
    required int itemIndex,
  }) => MenuRepository.deleteItemFromCategory(
    categoryIndex: categoryIndex,
    itemIndex: itemIndex,
  );

  static Future<bool> addSubcategory({
    required int categoryIndex,
    required String slug,
    required String nameEn,
    required String nameKa,
  }) => MenuRepository.addSubcategory(
    categoryIndex: categoryIndex,
    slug: slug,
    nameEn: nameEn,
    nameKa: nameKa,
  );

  static Future<bool> updateSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required String slug,
    required String nameEn,
    required String nameKa,
  }) => MenuRepository.updateSubcategory(
    categoryIndex: categoryIndex,
    subcategoryIndex: subcategoryIndex,
    slug: slug,
    nameEn: nameEn,
    nameKa: nameKa,
  );

  static Future<bool> deleteSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
  }) => MenuRepository.deleteSubcategory(
    categoryIndex: categoryIndex,
    subcategoryIndex: subcategoryIndex,
  );

  static Future<bool> addItemToSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
  }) => MenuRepository.addItemToSubcategory(
    categoryIndex: categoryIndex,
    subcategoryIndex: subcategoryIndex,
    nameEn: nameEn,
    nameKa: nameKa,
    price: price,
    variants: variants,
    sendToKitchen: sendToKitchen,
  );

  static Future<bool> updateItemInSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required int itemIndex,
    required String nameEn,
    required String nameKa,
    double? price,
    List<MenuVariantDB>? variants,
    bool? sendToKitchen,
  }) => MenuRepository.updateItemInSubcategory(
    categoryIndex: categoryIndex,
    subcategoryIndex: subcategoryIndex,
    itemIndex: itemIndex,
    nameEn: nameEn,
    nameKa: nameKa,
    price: price,
    variants: variants,
    sendToKitchen: sendToKitchen,
  );

  static Future<bool> deleteItemFromSubcategory({
    required int categoryIndex,
    required int subcategoryIndex,
    required int itemIndex,
  }) => MenuRepository.deleteItemFromSubcategory(
    categoryIndex: categoryIndex,
    subcategoryIndex: subcategoryIndex,
    itemIndex: itemIndex,
  );

  // ==================== DATE MANAGEMENT METHODS ====================

  // Get current business date
  static DateTime getCurrentDate() => BusinessDayRepository.getCurrentDate();

  static DateTime getCurrentDateTime() =>
      BusinessDayRepository.getCurrentDateTime();

  static double getMonthlyReportLeaseCost() =>
      SettingsRepository.getMonthlyReportLeaseCost();

  static Future<void> setMonthlyReportLeaseCost(double value) =>
      SettingsRepository.setMonthlyReportLeaseCost(value);

  static double getMonthlyReportStaffDailyCost() =>
      SettingsRepository.getMonthlyReportStaffDailyCost();

  static Future<void> setMonthlyReportStaffDailyCost(double value) =>
      SettingsRepository.setMonthlyReportStaffDailyCost(value);

  static double getMonthlyReportFoodProfitRatio() =>
      SettingsRepository.getMonthlyReportFoodProfitRatio();

  static Future<void> setMonthlyReportFoodProfitRatio(double ratio) =>
      SettingsRepository.setMonthlyReportFoodProfitRatio(ratio);

  static double getMonthlyReportManualSalesForMonth(int year, int month) =>
      SettingsRepository.getMonthlyReportManualSalesForMonth(year, month);

  static Future<void> setMonthlyReportManualSalesForMonth(
    int year,
    int month,
    double value,
  ) => SettingsRepository.setMonthlyReportManualSalesForMonth(
    year,
    month,
    value,
  );

  static double? getMonthlyReportLeaseCostOverrideForMonth(
    int year,
    int month,
  ) =>
      SettingsRepository.getMonthlyReportLeaseCostOverrideForMonth(year, month);

  static Future<void> setMonthlyReportLeaseCostOverrideForMonth(
    int year,
    int month,
    double? value,
  ) => SettingsRepository.setMonthlyReportLeaseCostOverrideForMonth(
    year,
    month,
    value,
  );

  static double? getMonthlyReportStaffDailyCostOverrideForMonth(
    int year,
    int month,
  ) => SettingsRepository.getMonthlyReportStaffDailyCostOverrideForMonth(
    year,
    month,
  );

  static Future<void> setMonthlyReportStaffDailyCostOverrideForMonth(
    int year,
    int month,
    double? value,
  ) => SettingsRepository.setMonthlyReportStaffDailyCostOverrideForMonth(
    year,
    month,
    value,
  );

  static String getDataDirectoryPath() => _dataDirectoryPath;

  static Future<void> setCurrentDate(DateTime newDate) =>
      BusinessDayRepository.setCurrentDate(newDate);

  static Future<void> refreshDailySalesTotalForDate(DateTime date) =>
      BusinessDayRepository.refreshDailySalesTotalForDate(date);

  // ==================== SETTINGS MANAGEMENT ====================

  static String getKitchenPrinterIp() =>
      SettingsRepository.getKitchenPrinterIp();

  static String getReceiptPrinterIp() =>
      SettingsRepository.getReceiptPrinterIp();

  static int getPrinterPort() => SettingsRepository.getPrinterPort();

  static int getKitchenPrinterPort() =>
      SettingsRepository.getKitchenPrinterPort();

  static int getReceiptPrinterPort() =>
      SettingsRepository.getReceiptPrinterPort();

  static List<Map<String, dynamic>> getPrintersList() =>
      SettingsRepository.getPrintersList();

  static Future<void> savePrintersList(List<Map<String, dynamic>> printers) =>
      SettingsRepository.savePrintersList(printers);

  static Future<void> savePrinterConfiguration({
    required String kitchenIp,
    required String receiptIp,
    required int port,
  }) => SettingsRepository.savePrinterConfiguration(
    kitchenIp: kitchenIp,
    receiptIp: receiptIp,
    port: port,
  );

  static double getServiceFeePercentage() =>
      SettingsRepository.getServiceFeePercentage();

  static double getServiceFeeRate() => SettingsRepository.getServiceFeeRate();

  static String getFormattedServiceFeePercentage({int maxFractionDigits = 1}) =>
      SettingsRepository.getFormattedServiceFeePercentage(
        maxFractionDigits: maxFractionDigits,
      );

  static bool isServiceFeeEnabledByDefault() =>
      SettingsRepository.isServiceFeeEnabledByDefault();

  /// True when admin enabled service fee AND percent is greater than zero.
  static bool isServiceFeeAvailable() =>
      SettingsRepository.isServiceFeeAvailable();

  static bool defaultIncludeServiceFee() =>
      SettingsRepository.defaultIncludeServiceFee();

  static Future<void> updateServiceFeeSettings({
    required double percentage,
    required bool enabledByDefault,
  }) => SettingsRepository.updateServiceFeeSettings(
    percentage: percentage,
    enabledByDefault: enabledByDefault,
  );

  static bool hasDestructiveActionPassword() =>
      SettingsRepository.hasDestructiveActionPassword();

  static bool verifyDestructiveActionPassword(String input) =>
      SettingsRepository.verifyDestructiveActionPassword(input);

  static Future<void> setDestructiveActionPassword(
    String newPassword, {
    String hint = '',
  }) =>
      SettingsRepository.setDestructiveActionPassword(newPassword, hint: hint);

  static DateTime? getDestructiveActionPasswordUpdatedAt() =>
      SettingsRepository.getDestructiveActionPasswordUpdatedAt();

  static String getDestructiveActionPasswordHint() =>
      SettingsRepository.getDestructiveActionPasswordHint();

  static Future<void> setDestructiveActionPasswordHint(String hint) =>
      SettingsRepository.setDestructiveActionPasswordHint(hint);

  static String getDefaultLanguage() => SettingsRepository.getDefaultLanguage();

  static Future<void> setDefaultLanguage(String language) =>
      SettingsRepository.setDefaultLanguage(language);

  static PosDisplaySettings getPosDisplaySettings() =>
      SettingsRepository.getPosDisplaySettings();

  static Future<void> setPosDisplaySettings(PosDisplaySettings settings) =>
      SettingsRepository.setPosDisplaySettings(settings);

  // ========== TABLE CLOSING OWNERSHIP SETTINGS ==========

  /// Get whether table closing is restricted to the user who opened/activated it
  /// Default: false (any waiter can close any table)
  static bool isTableCloseRestrictedToOwner() =>
      SettingsRepository.isTableCloseRestrictedToOwner();

  /// Set whether table closing is restricted to the owner
  static Future<void> setTableCloseRestrictedToOwner(bool restricted) =>
      SettingsRepository.setTableCloseRestrictedToOwner(restricted);

  // ========== RECEIPT DISPLAY SETTINGS ==========

  /// Whether printed receipts show the separate service-fee line. Display
  /// only — the fee is inside the receipt total either way. Default: true.
  static bool isReceiptServiceFeeLineVisible() =>
      SettingsRepository.isReceiptServiceFeeLineVisible();

  /// Set whether printed receipts show the separate service-fee line.
  static Future<void> setReceiptServiceFeeLineVisible(bool visible) =>
      SettingsRepository.setReceiptServiceFeeLineVisible(visible);

  static bool isCloseReceiptServiceFeeLineVisible() =>
      SettingsRepository.isCloseReceiptServiceFeeLineVisible();

  static Future<void> setCloseReceiptServiceFeeLineVisible(bool visible) =>
      SettingsRepository.setCloseReceiptServiceFeeLineVisible(visible);

  static Future<File> createDataBackup({String? targetFilePath}) =>
      BackupRepository.createDataBackup(targetFilePath: targetFilePath);

  static List<Map<String, dynamic>> exportMenu() =>
      BackupRepository.exportMenu();

  static Future<void> importMenuFromJson(
    List<dynamic> payload, {
    bool clearExisting = false,
    bool silent = false,
  }) => BackupRepository.importMenuFromJson(
    payload,
    clearExisting: clearExisting,
    silent: silent,
  );

  static List<Map<String, dynamic>> exportOrders() =>
      BackupRepository.exportOrders();

  static Future<void> replaceOrdersFromJson(List<dynamic> payload) =>
      BackupRepository.replaceOrdersFromJson(payload);

  static Map<String, dynamic> serializeOrder(Order order) =>
      BackupRepository.serializeOrder(order);

  static Future<Order?> createTakeawayOrderFromRemote({
    required int orderId,
    required String customerName,
    required String pickupTime,
    required String waiterName,
    required List<Map<String, dynamic>> items,
  }) => BackupRepository.createTakeawayOrderFromRemote(
    orderId: orderId,
    customerName: customerName,
    pickupTime: pickupTime,
    waiterName: waiterName,
    items: items,
  );

  static Future<Order> createOrderFromJson(Map<String, dynamic> json) =>
      BackupRepository.createOrderFromJson(json);

  static List<Map<String, dynamic>> exportReservations() =>
      BackupRepository.exportReservations();

  static Future<void> replaceReservationsFromJson(List<dynamic> payload) =>
      BackupRepository.replaceReservationsFromJson(payload);

  static Future<String> createReservationFromJson(Map<String, dynamic> json) =>
      BackupRepository.createReservationFromJson(json);

  static Map<String, dynamic>? getReservationById(String reservationId) =>
      BackupRepository.getReservationById(reservationId);

  static List<Map<String, dynamic>> exportTables() =>
      BackupRepository.exportTables();

  static Future<void> replaceTablesFromJson(List<dynamic> payload) =>
      BackupRepository.replaceTablesFromJson(payload);

  static Future<void> updateTableFromJson(Map<String, dynamic> json) =>
      BackupRepository.updateTableFromJson(json);

  static Future<void> restoreDataBackupFromFile(
    File backupFile, {
    bool clearExisting = true,
    bool backupBeforeRestore = true,
  }) => BackupRepository.restoreDataBackupFromFile(
    backupFile,
    clearExisting: clearExisting,
    backupBeforeRestore: backupBeforeRestore,
  );

  static Future<void> restoreDataBackupFromJson(
    String jsonString, {
    bool clearExisting = true,
    bool backupBeforeRestore = true,
  }) => BackupRepository.restoreDataBackupFromJson(
    jsonString,
    clearExisting: clearExisting,
    backupBeforeRestore: backupBeforeRestore,
  );

  // Close current day and move to next date
  /// Closes the business day. See [CloseDayTransaction].
  static Future<bool> closeDay() => CloseDayTransaction.run();

  // Get date in Georgian format
  static String getGeorgianFormattedDate(DateTime date) =>
      BusinessDayRepository.getGeorgianFormattedDate(date);

  // ==================== SALES TRACKING METHODS ====================

  static Future<bool> closeOrderWithPayment({
    required int orderId,
    required String paymentMethod,
    required String closedById,
    String? closedByName,
    Map<String, double>? paymentBreakdown,
    String? customPaymentLabel,
  }) => CloseTableTransaction.withPayment(
    orderId: orderId,
    paymentMethod: paymentMethod,
    closedById: closedById,
    closedByName: closedByName,
    paymentBreakdown: paymentBreakdown,
    customPaymentLabel: customPaymentLabel,
  );

  static Future<bool> closeOrderNonFiscal({
    required int orderId,
    required String closedById,
    String? closedByName,
  }) => CloseTableTransaction.nonFiscal(
    orderId: orderId,
    closedById: closedById,
    closedByName: closedByName,
  );

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
  }) => SalesRepository.saveSaleRecord(
    orderId: orderId,
    tableNumbers: tableNumbers,
    floor: floor,
    items: items,
    totalAmount: totalAmount,
    paymentMethod: paymentMethod,
    paymentBreakdown: paymentBreakdown,
    customPaymentLabel: customPaymentLabel,
    createdBy: createdBy,
    createdAt: createdAt,
    closedAt: closedAt,
    includeServiceFee: includeServiceFee,
    discountAmount: discountAmount,
    advanceAmount: advanceAmount,
    subtotalAmount: subtotalAmount,
    manualAdjustmentAmount: manualAdjustmentAmount,
    finalTransaction: finalTransaction,
    isFiscal: isFiscal,
    isCancelled: isCancelled,
    cancelledAt: cancelledAt,
  );

  static double getDailySalesTotal() => SalesRepository.getDailySalesTotal();

  static Future<Map<String, dynamic>> saveExpenseRecord({
    required String description,
    required double amount,
    required String category,
    String paymentType = 'cash',
    DateTime? createdAt,
    String? businessDate,
    String? sourceId,
  }) => SalesRepository.saveExpenseRecord(
    description: description,
    amount: amount,
    category: category,
    paymentType: paymentType,
    createdAt: createdAt,
    businessDate: businessDate,
    sourceId: sourceId,
  );

  static List<Map<String, dynamic>> getExpensesForDate(String date) =>
      SalesRepository.getExpensesForDate(date);

  static double getExpenseTotalForDate(String date) =>
      SalesRepository.getExpenseTotalForDate(date);

  static List<Map<String, dynamic>> getAllExpenseRecords() =>
      SalesRepository.getAllExpenseRecords();

  static List<Map<String, dynamic>> getSalesForDate(String date) =>
      SalesRepository.getSalesForDate(date);

  static List<Map<String, dynamic>> getAllSales() =>
      SalesRepository.getAllSales();

  static Future<bool> cancelSaleRecord(dynamic recordKey) =>
      SalesRepository.cancelSaleRecord(recordKey);

  static Future<bool> restoreClosedOrderFromSale({
    required dynamic recordKey,
    required String restoredBy,
  }) => SalesRepository.restoreClosedOrderFromSale(
    recordKey: recordKey,
    restoredBy: restoredBy,
  );

  static Future<void> resetDailySalesTotal() =>
      SalesRepository.resetDailySalesTotal();

  // ==================== AUDIT LOG METHODS ====================

  static Future<void> saveAuditReport(AuditReport report) =>
      AuditRepository.saveAuditReport(report);

  static AuditReport? getAuditReport(int orderId) =>
      AuditRepository.getAuditReport(orderId);

  static List<AuditReport> getAuditReports({AuditReportStatus? status}) =>
      AuditRepository.getAuditReports(status: status);

  static Future<void> appendOrderAuditEvents({
    required int orderId,
    required List<AuditEvent> events,
    AuditReportStatus? statusOverride,
    bool lockReport = false,
    String? closedById,
    String? closedByName,
  }) => AuditRepository.appendOrderAuditEvents(
    orderId: orderId,
    events: events,
    statusOverride: statusOverride,
    lockReport: lockReport,
    closedById: closedById,
    closedByName: closedByName,
  );

  static Future<void> logAdminAction({
    required String actionType,
    required String performedBy,
    Map<String, dynamic>? details,
    String? comment,
    String? approvedBy,
  }) => AuditRepository.logAdminAction(
    actionType: actionType,
    performedBy: performedBy,
    details: details,
    comment: comment,
    approvedBy: approvedBy,
  );

  static List<Map<String, dynamic>> getAuditLogs({
    String? date,
    String? actionType,
  }) => AuditRepository.getAuditLogs(date: date, actionType: actionType);

  // ==================== ERROR LOG METHODS ====================

  static Future<void> logError({
    required String title,
    required Object error,
    required StackTrace stackTrace,
    String? context,
    String? performedBy,
    Map<String, dynamic>? metadata,
  }) => ErrorLogRepository.logError(
    title: title,
    error: error,
    stackTrace: stackTrace,
    context: context,
    performedBy: performedBy,
    metadata: metadata,
  );

  static List<Map<String, dynamic>> getErrorLogs({String? date}) =>
      ErrorLogRepository.getErrorLogs(date: date);

  static Future<void> clearErrorLogs() => ErrorLogRepository.clearErrorLogs();

  // ==================== RESERVATION METHODS ====================

  static Future<String> createReservation({
    required String customerName,
    required String customerPhone,
    List<int> tableNumbers = const [],
    List<TableRef>? tableRefs,
    required DateTime reservationDate,
    required String reservationTime,
    required int numberOfGuests,
    String? notes,
    required String createdBy,
    List<OrderItem>? preOrderItems,
    bool isTakeAway = false,
    int? linkedOrderId,
    String status = 'pending',
  }) => ReservationRepository.createReservation(
    customerName: customerName,
    customerPhone: customerPhone,
    tableNumbers: tableNumbers,
    tableRefs: tableRefs,
    reservationDate: reservationDate,
    reservationTime: reservationTime,
    numberOfGuests: numberOfGuests,
    notes: notes,
    createdBy: createdBy,
    preOrderItems: preOrderItems,
    isTakeAway: isTakeAway,
    linkedOrderId: linkedOrderId,
    status: status,
  );

  static List<Reservation> getAllReservations() =>
      ReservationRepository.getAllReservations();

  static Reservation? getReservation(String reservationId) =>
      ReservationRepository.getReservation(reservationId);

  static List<Reservation> getReservationsForDate(DateTime date) =>
      ReservationRepository.getReservationsForDate(date);

  /// Real bookings on [date] that already hold table numbers (excludes walk-ins).
  static List<Reservation> getTableBlockingReservationsForDate(DateTime date) =>
      ReservationRepository.getTableBlockingReservationsForDate(date);

  static Future<bool> cancelReservationByOrderId(int orderId) =>
      ReservationRepository.cancelReservationByOrderId(orderId);

  static Reservation? findReservationForOrder(Order order) =>
      ReservationRepository.findReservationForOrder(order);

  static List<Reservation> getTakeAwayReservationsForDate(DateTime date) =>
      ReservationRepository.getTakeAwayReservationsForDate(date);

  static List<Reservation> getReservationsByStatus(String status) =>
      ReservationRepository.getReservationsByStatus(status);

  static List<DateTime> getOperatedBusinessDates() =>
      BusinessDayRepository.getOperatedBusinessDates();

  static List<DateTime> getKnownBusinessDates() =>
      BusinessDayRepository.getKnownBusinessDates();

  static Future<void> updateReservationStatus(
    String reservationId,
    String newStatus,
  ) => ReservationRepository.updateReservationStatus(reservationId, newStatus);

  static Future<void> updateReservationPreOrderItems(
    String reservationId,
    List<OrderItem> updatedItems,
  ) => ReservationRepository.updateReservationPreOrderItems(
    reservationId,
    updatedItems,
  );

  static Future<void> updateReservationTables(
    String reservationId,
    List<int> tableNumbers, {
    List<TableRef>? tableRefs,
  }) => ReservationRepository.updateReservationTables(
    reservationId,
    tableNumbers,
    tableRefs: tableRefs,
  );

  /// Activates a reservation by creating (or re-linking) its order and
  /// reserving its tables. See [ActivateReservationTransaction].
  static Future<ReservationActivationResult> activateReservation({
    required String reservationId,
    required String activatedBy,
  }) => ActivateReservationTransaction.activate(
    reservationId: reservationId,
    activatedBy: activatedBy,
  );

  static Future<void> deleteReservation(String reservationId) =>
      ReservationRepository.deleteReservation(reservationId);

  static bool areTablesAvailableForReservation({
    required List<int> tableNumbers,
    required DateTime reservationDate,
    required String reservationTime,
    String? excludeReservationId,
  }) => ReservationRepository.areTablesAvailableForReservation(
    tableNumbers: tableNumbers,
    reservationDate: reservationDate,
    reservationTime: reservationTime,
    excludeReservationId: excludeReservationId,
  );

  static Future<void> activateTodaysReservations() =>
      ActivateReservationTransaction.activateTodaysReservations();
}
