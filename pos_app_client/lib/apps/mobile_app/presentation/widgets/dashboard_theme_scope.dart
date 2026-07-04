import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';

/// Provides [DashboardThemeData] to the manager dashboard widget tree.
class DashboardThemeScope extends InheritedWidget {
  const DashboardThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final DashboardThemeData theme;

  static DashboardThemeData of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DashboardThemeScope>();
    assert(scope != null, 'DashboardThemeScope not found');
    return scope!.theme;
  }

  @override
  bool updateShouldNotify(DashboardThemeScope oldWidget) =>
      theme != oldWidget.theme;
}

extension DashboardThemeContext on BuildContext {
  DashboardThemeData get dash => DashboardThemeScope.of(this);
}
