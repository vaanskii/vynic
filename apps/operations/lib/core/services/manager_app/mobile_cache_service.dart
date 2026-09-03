import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/models/table.dart';

/// Keys used inside the Hive box.
class _Keys {
  static const dashboard = 'dashboard';
  static const tables = 'tables';
  static const staffPerformance = 'staff_performance';
  static const financials = 'financials';
  static const menu = 'menu';
  static const topItems = 'top_items';
  static const lastServerTime = 'last_server_time'; // ISO – for diff sync
  static const notificationsSyncAt = 'notifications_sync_at';
  static const countedMenus = 'counted_menus';

  // Per-key TTL timestamps
  static String ttl(String key) => '${key}_ttl';
}

/// Offline-first cache for the Mobile Manager App, backed by Hive.
///
/// Strategy:
///   • Network-first with timeout → on success update cache.
///   • On failure (timeout / no internet) → serve cached data.
///   • Cache entries have a soft TTL; stale data is shown with a warning.
class MobileCacheService {
  static const _boxName = 'mobile_manager_cache';
  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  static Future<void> _write(String key, Object value) async {
    final box = _box;
    if (box == null) return;
    await box.put(key, jsonEncode(value));
    await box.put(_Keys.ttl(key), DateTime.now().toIso8601String());
  }

  static T? _read<T>(String key, T Function(dynamic json) fromJson) {
    final box = _box;
    if (box == null) return null;
    final raw = box.get(key);
    if (raw == null) return null;
    try {
      return fromJson(jsonDecode(raw as String));
    } catch (e) {
      debugPrint('[Cache] Decode error for $key: $e');
      return null;
    }
  }

  /// Returns true if the cached value for [key] is older than [maxAge].
  static bool isStale(
    String key, {
    Duration maxAge = const Duration(minutes: 5),
  }) {
    final ttlStr = _box?.get(_Keys.ttl(key)) as String?;
    if (ttlStr == null) return true;
    final saved = DateTime.tryParse(ttlStr);
    if (saved == null) return true;
    return DateTime.now().difference(saved) > maxAge;
  }

  /// ISO timestamp of the last successful backend sync (used for diff endpoint).
  static String? get lastServerTime =>
      _box?.get(_Keys.lastServerTime) as String?;

  static Future<void> setLastServerTime(String iso) async =>
      _box?.put(_Keys.lastServerTime, iso);

  /// Last time we pulled persisted notifications from the server (ISO).
  static String? get lastNotificationsSyncAt =>
      _box?.get(_Keys.notificationsSyncAt) as String?;

  static Future<void> setLastNotificationsSyncAt(String iso) async =>
      _box?.put(_Keys.notificationsSyncAt, iso);

  // ── Dashboard ──────────────────────────────────────────────────────────────

  static Future<void> saveDashboard(ManagerDashboardMetrics metrics) =>
      _write(_Keys.dashboard, metrics.toJson());

  static ManagerDashboardMetrics? getCachedDashboard() => _read(
    _Keys.dashboard,
    (json) => ManagerDashboardMetrics.fromJson(json as Map<String, dynamic>),
  );

  // ── Tables ─────────────────────────────────────────────────────────────────

  static Future<void> saveTables(List<TableModel> tables) =>
      _write(_Keys.tables, tables.map((t) => t.toJson()).toList());

  static List<TableModel>? getCachedTables() => _read(
    _Keys.tables,
    (json) => (json as List)
        .map((e) => TableModel.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  // ── Staff performance ──────────────────────────────────────────────────────

  static Future<void> saveStaffPerformance(List<StaffMetric> staff) =>
      _write(_Keys.staffPerformance, staff.map((s) => s.toJson()).toList());

  static List<StaffMetric>? getCachedStaffPerformance() => _read(
    _Keys.staffPerformance,
    (json) => (json as List)
        .map((e) => StaffMetric.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  // ── Financials ─────────────────────────────────────────────────────────────

  static Future<void> saveFinancials(Map<String, dynamic> data) =>
      _write(_Keys.financials, data);

  static Map<String, dynamic>? getCachedFinancials() =>
      _read(_Keys.financials, (json) => json as Map<String, dynamic>);

  // ── Menu ───────────────────────────────────────────────────────────────────

  static Future<void> saveMenu(List<dynamic> menu) => _write(_Keys.menu, menu);

  static List<dynamic>? getCachedMenu() =>
      _read(_Keys.menu, (json) => json as List<dynamic>);

  // ── Top items ──────────────────────────────────────────────────────────────

  static Future<void> saveTopItems(List<dynamic> items) =>
      _write(_Keys.topItems, items);

  static List<dynamic>? getCachedTopItems() =>
      _read(_Keys.topItems, (json) => json as List<dynamic>);

  // ── Partial diff update for tables ────────────────────────────────────────

  /// Merges diff tables into the existing cache by tableNumber+floor key.
  static Future<void> applyTableDiff(
    List<Map<String, dynamic>> diffTables,
  ) async {
    final existing = getCachedTables() ?? [];
    final Map<String, TableModel> map = {
      for (final t in existing) '${t.tableNumber}_${t.floor}': t,
    };
    for (final dt in diffTables) {
      final key = '${dt['tableNumber']}_${dt['floor']}';
      map[key] = TableModel.fromJson(dt);
    }
    await saveTables(map.values.toList());
  }

  // ── Counted Menus ─────────────────────────────────────────────────────────

  static Future<void> saveCountedMenus(List<dynamic> menus) =>
      _write(_Keys.countedMenus, menus);

  static List<dynamic>? getCachedCountedMenus() =>
      _read(_Keys.countedMenus, (json) => json as List<dynamic>);

  // ── Clear ──────────────────────────────────────────────────────────────────

  static Future<void> clear() async => _box?.clear();
}
