import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vynic/apps/mobile_app/core/theme/manager_dashboard_theme.dart';

/// Local preferences for the mobile manager app (Hive-backed).
class ManagerAppPreferences {
  ManagerAppPreferences._();

  static const _boxName = 'manager_preferences';
  static const _dashboardAppearanceKey = 'dashboard_appearance';
  static const _backendUrlKey = 'backend_url_override';

  static Box? _box;

  static final ValueNotifier<ManagerDashboardAppearance> dashboardAppearance =
      ValueNotifier(ManagerDashboardAppearance.light);

  /// User-set backend URL for the mobile manager app (e.g. the Windows POS LAN
  /// address http://10.10.10.4:3000). Null = use the bundled .env default.
  static final ValueNotifier<String?> backendUrlOverride =
      ValueNotifier<String?>(null);

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    final stored = _box!.get(_dashboardAppearanceKey) as String?;
    dashboardAppearance.value = _parseAppearance(stored);
    final url = (_box!.get(_backendUrlKey) as String?)?.trim();
    backendUrlOverride.value = (url == null || url.isEmpty) ? null : url;
  }

  /// Set (or clear, with null/empty) the backend URL override.
  static Future<void> setBackendUrlOverride(String? url) async {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      backendUrlOverride.value = null;
      await _box?.delete(_backendUrlKey);
    } else {
      backendUrlOverride.value = value;
      await _box?.put(_backendUrlKey, value);
    }
  }

  static ManagerDashboardAppearance _parseAppearance(String? raw) {
    if (raw == ManagerDashboardAppearance.dark.name) {
      return ManagerDashboardAppearance.dark;
    }
    return ManagerDashboardAppearance.light;
  }

  static Future<void> setDashboardAppearance(
    ManagerDashboardAppearance appearance,
  ) async {
    dashboardAppearance.value = appearance;
    await _box?.put(_dashboardAppearanceKey, appearance.name);
  }
}
