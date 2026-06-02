import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vynic/apps/mobile_app/core/theme/manager_dashboard_theme.dart';

/// Local preferences for the mobile manager app (Hive-backed).
class ManagerAppPreferences {
  ManagerAppPreferences._();

  static const _boxName = 'manager_preferences';
  static const _dashboardAppearanceKey = 'dashboard_appearance';

  static Box? _box;

  static final ValueNotifier<ManagerDashboardAppearance> dashboardAppearance =
      ValueNotifier(ManagerDashboardAppearance.light);

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    final stored = _box!.get(_dashboardAppearanceKey) as String?;
    dashboardAppearance.value = _parseAppearance(stored);
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
