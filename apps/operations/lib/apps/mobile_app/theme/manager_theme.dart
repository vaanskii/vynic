import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/dashboard_theme_scope.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';

/// Resolves the active manager theme (scoped context or saved preference).
DashboardThemeData managerThemeOf(BuildContext context) {
  final scope = context
      .dependOnInheritedWidgetOfExactType<DashboardThemeScope>();
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
          child: Theme(data: managerMaterialTheme(appearance), child: child),
        );
      },
    );
  }
}

/// Material defaults for Manager routes, overlays and native inputs. Kept
/// separate from the POS theme so product styling does not change POS behavior.
ThemeData managerMaterialTheme(ManagerDashboardAppearance appearance) {
  final t = DashboardThemeData.forAppearance(appearance);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: t.primary,
        brightness: t.isDark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: t.primary,
        onPrimary: t.isDark ? const Color(0xFF21182E) : Colors.white,
        primaryContainer: t.primarySoft,
        onPrimaryContainer: t.accentText,
        secondary: t.primary,
        secondaryContainer: t.primarySoft,
        onSecondaryContainer: t.accentText,
        surface: t.surfaceCard,
        onSurface: t.textPrimary,
        onSurfaceVariant: t.textSecondary,
        surfaceContainerHighest: t.surfaceMuted,
        outline: t.textSecondary,
        outlineVariant: t.cardBorder,
        error: t.bad,
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'NotoSansGeorgian',
    scaffoldBackgroundColor: t.scaffoldBackground,
    canvasColor: t.surfaceCard,
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: t.textPrimary,
      displayColor: t.textPrimary,
    ),
    dividerColor: t.cardBorder,
    focusColor: t.primary.withValues(alpha: .18),
    hoverColor: t.primary.withValues(alpha: .06),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.primary,
      selectionColor: t.primary.withValues(alpha: .22),
      selectionHandleColor: t.primary,
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: t.scaffoldBackground,
      foregroundColor: t.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSansGeorgian',
        color: t.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: t.surfaceCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textSecondary),
      helperMaxLines: 3,
      errorMaxLines: 3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: 'NotoSansGeorgian',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(48, 48),
        shape: shape,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        side: BorderSide(color: t.cardBorder),
        foregroundColor: t.textPrimary,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
      ),
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
    ),
    cardTheme: CardThemeData(
      color: t.surfaceCard,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: t.cardBorder),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surfaceCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      alignment: Alignment.center,
      constraints: const BoxConstraints(maxWidth: 680),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: t.cardBorder),
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSansGeorgian',
        color: t.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'NotoSansGeorgian',
        color: t.textSecondary,
        fontSize: 14,
        height: 1.5,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surfaceCard,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: t.surfaceCard,
      selectedColor: t.primarySoft,
      side: BorderSide(color: t.cardBorder),
      labelStyle: TextStyle(
        fontFamily: 'NotoSansGeorgian',
        color: t.textPrimary,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.primary,
      unselectedLabelColor: t.textSecondary,
      dividerColor: t.cardBorder,
      indicatorColor: t.primary,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(t.textSecondary.withValues(alpha: .4)),
      radius: const Radius.circular(8),
    ),
  );
}
