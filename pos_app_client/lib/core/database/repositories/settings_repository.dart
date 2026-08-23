import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import 'business_day_repository.dart';
import '../database_core.dart';

/// POS settings stored in the `settings` box: printers, service fee,
/// destructive-action password, language, monthly-report inputs, and the
/// POS↔server connection settings.
class SettingsRepository {
  SettingsRepository._();

  static const String _posIngestConnectionKeySetting = 'posIngestConnectionKey';
  static const String _lastManagerSyncAtSetting = 'lastManagerSyncAt';
  static const String _backendUrlOverrideSetting = 'backendUrlOverride';
  static const String _restrictTableCloseToOwnerSetting =
      'restrictTableCloseToOwner';
  static const String _receiptShowServiceFeeLineSetting =
      'receiptShowServiceFeeLine';

  static const String _closeReceiptShowServiceFeeLineSetting =
      'closeReceiptShowServiceFeeLine';

  /// Superseded by [_receiptShowServiceFeeLineSetting] (inverted). Read only,
  /// so a terminal that already toggled the old key keeps its choice.
  static const String _legacyReceiptHideServiceFeeLineSetting =
      'receiptHideServiceFeeLine';
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
  static const String _activeTableLayoutSetting = 'activeTableLayoutJson';
  static const String _posDisplayModeSetting = 'posDisplayMode';
  static const String _posUiDensitySetting = 'posUiDensity';
  static const String _posUiScalePercentSetting = 'posUiScalePercent';
  static const String _posSidebarDefaultSetting = 'posSidebarDefault';
  static const String _posTableTileSizeSetting = 'posTableTileSize';
  static const String _posFullscreenModeSetting = 'posFullscreenMode';
  static const String _posFloorPlanGridSetting = 'posFloorPlanGrid';

  static const Uuid _uuid = Uuid();

  static Box? get _settingsBox => DatabaseCore.settingsBox;

  /// Seeds first-run defaults into the settings box. Called from
  /// `DatabaseService.init()` (the façade) after schema migrations, before anything reads
  /// settings.
  static Future<void> seedDefaults() async {
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
      await _settingsBox!.put(
        _monthlyReportManualSalesByMonthSetting,
        <String, double>{},
      );
    }
    if (!_settingsBox!.containsKey(_monthlyReportLeaseCostByMonthSetting)) {
      await _settingsBox!.put(
        _monthlyReportLeaseCostByMonthSetting,
        <String, double>{},
      );
    }
    if (!_settingsBox!.containsKey(
      _monthlyReportStaffDailyCostByMonthSetting,
    )) {
      await _settingsBox!.put(
        _monthlyReportStaffDailyCostByMonthSetting,
        <String, double>{},
      );
    }

    // Printer configuration starts empty, not from `.env`.
    //
    // `.env` is bundled as an asset, so it is baked into whatever build ships.
    // Seeding from it meant a terminal installed at a customer site came up
    // pre-configured with whichever printer IPs were in the developer's file —
    // addresses on a network it has never been on. Silently wrong beats
    // obviously blank only if nobody has to debug it: an empty field says „set
    // me", `10.10.10.4` says „already done".
    if (!_settingsBox!.containsKey('printerKitchenIp')) {
      await _settingsBox!.put('printerKitchenIp', '');
    }
    if (!_settingsBox!.containsKey('printerReceiptIp')) {
      await _settingsBox!.put('printerReceiptIp', '');
    }
    if (!_settingsBox!.containsKey('printerPort')) {
      await _settingsBox!.put('printerPort', 9100);
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
      // Georgian, not whatever the build's `.env` happened to say.
      await _settingsBox!.put('defaultLanguage', 'ka');
    }

    final displayDefaults = PosDisplaySettings.defaults;
    if (!_settingsBox!.containsKey(_posDisplayModeSetting)) {
      await _settingsBox!.put(
        _posDisplayModeSetting,
        displayDefaults.displayMode.storageValue,
      );
    }
    if (!_settingsBox!.containsKey(_posUiDensitySetting)) {
      await _settingsBox!.put(
        _posUiDensitySetting,
        displayDefaults.density.storageValue,
      );
    }
    if (!_settingsBox!.containsKey(_posUiScalePercentSetting)) {
      await _settingsBox!.put(
        _posUiScalePercentSetting,
        displayDefaults.scalePercent,
      );
    }
    if (!_settingsBox!.containsKey(_posSidebarDefaultSetting)) {
      await _settingsBox!.put(
        _posSidebarDefaultSetting,
        displayDefaults.sidebarDefault.storageValue,
      );
    }
    if (!_settingsBox!.containsKey(_posTableTileSizeSetting)) {
      await _settingsBox!.put(
        _posTableTileSizeSetting,
        displayDefaults.tableTileSize.storageValue,
      );
    }
    if (!_settingsBox!.containsKey(_posFullscreenModeSetting)) {
      await _settingsBox!.put(
        _posFullscreenModeSetting,
        displayDefaults.fullscreenPosMode,
      );
    }
    if (!_settingsBox!.containsKey(_posFloorPlanGridSetting)) {
      await _settingsBox!.put(
        _posFloorPlanGridSetting,
        displayDefaults.floorPlanGrid,
      );
    }
  }

  // ==================== MONTHLY REPORT INPUTS ====================

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

  static double? getMonthlyReportLeaseCostOverrideForMonth(
    int year,
    int month,
  ) {
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

  // ==================== PRINTERS ====================

  /// The kitchen printer's address, as configured in the admin panel.
  ///
  /// This used to fall through to `PRINTER_KITCHEN_IP` from the bundled `.env`
  /// whenever the stored value was blank — so clearing the field in Settings
  /// did not clear the printer, it reverted it to a build-time address. What
  /// the admin panel shows is now what the POS uses.
  static String getKitchenPrinterIp() {
    final stored = _settingsBox!.get('printerKitchenIp');
    return stored is String ? stored.trim() : '';
  }

  static String getReceiptPrinterIp() {
    final stored = _settingsBox!.get('printerReceiptIp');
    return stored is String ? stored.trim() : '';
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

  // ==================== SERVICE FEE ====================

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

  static Future<void> _applyServiceFeePreferenceToOpenOrders() async {
    if (DatabaseCore.orderBox == null) {
      return;
    }

    final now = BusinessDayRepository.getCurrentDateTime();
    final pendingSaves = <Future<void>>[];

    for (final order in DatabaseCore.orderBox!.values) {
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
    if (DatabaseCore.quickOrderBox == null) return;
    final pending = <Future<void>>[];
    for (final draft in DatabaseCore.quickOrderBox!.values) {
      if (!draft.includeServiceFee && draft.serviceFeeAmount <= 0) continue;
      draft.includeServiceFee = false;
      draft.serviceFeeAmount = 0;
      draft.total = draft.subtotal;
      pending.add(DatabaseCore.quickOrderBox!.put(draft.id, draft));
    }
    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
  }

  /// Honors an explicit request only when the service fee is available.
  static bool resolveIncludeServiceFee(bool requested) {
    if (!isServiceFeeAvailable()) return false;
    return requested;
  }

  static bool _isOrderFinalized(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'paid' ||
        normalized == 'cancelled' ||
        normalized == 'closed';
  }

  // ==================== DESTRUCTIVE ACTION PASSWORD ====================

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

  // ==================== LANGUAGE ====================

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

  // ==================== DISPLAY & INTERFACE ====================

  static PosDisplaySettings getPosDisplaySettings() {
    if (_settingsBox == null) return PosDisplaySettings.defaults;
    final scale = _settingsBox!.get(_posUiScalePercentSetting);
    final scalePercent = scale is num
        ? scale.toInt()
        : int.tryParse(scale?.toString() ?? '') ?? 100;
    final fullscreen = _settingsBox!.get(_posFullscreenModeSetting);
    final floorPlanGrid = _settingsBox!.get(_posFloorPlanGridSetting);

    return PosDisplaySettings(
      displayMode: PosDisplayMode.fromStorage(
        _settingsBox!.get(_posDisplayModeSetting),
      ),
      density: PosUiDensity.fromStorage(
        _settingsBox!.get(_posUiDensitySetting),
      ),
      scalePercent: scalePercent.clamp(90, 110),
      sidebarDefault: PosSidebarDefault.fromStorage(
        _settingsBox!.get(_posSidebarDefaultSetting),
      ),
      tableTileSize: PosTableTileSize.fromStorage(
        _settingsBox!.get(_posTableTileSizeSetting),
      ),
      fullscreenPosMode: fullscreen is bool ? fullscreen : false,
      // Defaults to on, so a terminal that predates this setting keeps the
      // floor plan it already had.
      floorPlanGrid: floorPlanGrid is bool ? floorPlanGrid : true,
    );
  }

  static Future<void> setPosDisplaySettings(PosDisplaySettings settings) async {
    await _settingsBox!.put(
      _posDisplayModeSetting,
      settings.displayMode.storageValue,
    );
    await _settingsBox!.put(
      _posUiDensitySetting,
      settings.density.storageValue,
    );
    await _settingsBox!.put(
      _posUiScalePercentSetting,
      settings.scalePercent.clamp(90, 110),
    );
    await _settingsBox!.put(
      _posSidebarDefaultSetting,
      settings.sidebarDefault.storageValue,
    );
    await _settingsBox!.put(
      _posTableTileSizeSetting,
      settings.tableTileSize.storageValue,
    );
    await _settingsBox!.put(
      _posFullscreenModeSetting,
      settings.fullscreenPosMode,
    );
    await _settingsBox!.put(_posFloorPlanGridSetting, settings.floorPlanGrid);
  }

  // ==================== TABLE CLOSING OWNERSHIP ====================

  /// Get whether table closing is restricted to the user who opened/activated
  /// it. Default: false (any waiter can close any table)
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

  /// Whether printed customer receipts show the separate service-fee line.
  ///
  /// Display only: the fee is inside the receipt total either way, this just
  /// controls the "სერვისის საფასური დამატებულია" row. Defaults to `true` —
  /// the row prints, which is how the POS has always behaved.
  static bool isReceiptServiceFeeLineVisible() {
    if (_settingsBox == null) return true; // not initialized on mobile
    final stored = _settingsBox!.get(_receiptShowServiceFeeLineSetting);
    if (stored is bool) return stored;
    // Fall back to the superseded inverted key so a terminal that already
    // chose "hide" before the rename keeps that choice.
    final legacyHidden = _settingsBox!.get(
      _legacyReceiptHideServiceFeeLineSetting,
    );
    if (legacyHidden is bool) return !legacyHidden;
    return true;
  }

  /// Set whether printed receipts show the separate service-fee line.
  static Future<void> setReceiptServiceFeeLineVisible(bool visible) async {
    await _settingsBox!.put(_receiptShowServiceFeeLineSetting, visible);
    // Keep the superseded key from overriding a newer choice on re-read.
    await _settingsBox!.delete(_legacyReceiptHideServiceFeeLineSetting);
  }

  /// Whether the *closing* receipt shows the separate service-fee line.
  ///
  /// A separate switch from [isReceiptServiceFeeLineVisible] because the two
  /// receipts are different documents: the customer receipt printed during
  /// service, and the fiscal check produced when the table is closed and paid
  /// (cash, card, or split).
  ///
  /// Defaults to `false`, which is how the POS has always behaved — the
  /// closing check never carried the row, because the total already includes
  /// the fee. Turning it on is display only; no total changes either way.
  static bool isCloseReceiptServiceFeeLineVisible() {
    if (_settingsBox == null) return false; // not initialized on mobile
    final stored = _settingsBox!.get(_closeReceiptShowServiceFeeLineSetting);
    return stored is bool ? stored : false;
  }

  static Future<void> setCloseReceiptServiceFeeLineVisible(
    bool visible,
  ) async {
    await _settingsBox!.put(_closeReceiptShowServiceFeeLineSetting, visible);
  }

  // ==================== POS ↔ SERVER CONNECTION ====================

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

  static DateTime? getLastManagerSyncAt() {
    final raw = _settingsBox?.get(_lastManagerSyncAtSetting) as String?;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> saveLastManagerSyncAt(DateTime value) async {
    await _settingsBox?.put(_lastManagerSyncAtSetting, value.toIso8601String());
  }

  static String? getBackendUrlOverride() {
    final raw = _settingsBox?.get(_backendUrlOverrideSetting) as String?;
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static Future<void> saveBackendUrlOverride(String value) async {
    await _settingsBox?.put(_backendUrlOverrideSetting, value.trim());
  }

  static Future<void> clearBackendUrlOverride() async {
    await _settingsBox?.delete(_backendUrlOverrideSetting);
  }

  static RestaurantTableLayout? getActiveTableLayout() {
    final raw = _settingsBox?.get(_activeTableLayoutSetting);
    if (raw == null) {
      return null;
    }

    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) {
      throw StateError('Saved table layout setting is not a JSON object');
    }

    return RestaurantTableLayout.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  static Future<void> saveActiveTableLayout(
    RestaurantTableLayout layout,
  ) async {
    await _settingsBox?.put(_activeTableLayoutSetting, jsonEncode(layout));
  }

  static Future<void> clearActiveTableLayout() async {
    await _settingsBox?.delete(_activeTableLayoutSetting);
  }
}
