import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

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
}
