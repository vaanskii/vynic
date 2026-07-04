import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/dashboard_theme_scope.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';

/// Resolves the active manager theme (scoped context or saved preference).
DashboardThemeData managerThemeOf(BuildContext context) {
  final scope = context
      .getElementForInheritedWidgetOfExactType<DashboardThemeScope>()
      ?.widget;
  if (scope is DashboardThemeScope) {
    return scope.theme;
  }
  return DashboardThemeData.forAppearance(
    ManagerAppPreferences.dashboardAppearance.value,
  );
}

/// Listens for theme changes and rebuilds [child].
/// Wraps a screen pushed above the shell so theme preference changes rebuild it.
Widget managerThemedPage(Widget child) => ManagerThemeListener(child: child);

class ManagerThemeListener extends StatelessWidget {
  const ManagerThemeListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ManagerDashboardAppearance>(
      valueListenable: ManagerAppPreferences.dashboardAppearance,
      builder: (context, appearance, _) {
        return DashboardThemeScope(
          theme: DashboardThemeData.forAppearance(appearance),
          child: child,
        );
      },
    );
  }
}
