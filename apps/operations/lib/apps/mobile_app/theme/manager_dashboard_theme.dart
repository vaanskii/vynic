import 'package:flutter/material.dart';
import 'package:vynic/core/services/manager_app/manager_dashboard_appearance.dart';

export 'package:vynic/core/services/manager_app/manager_dashboard_appearance.dart';

/// Bottom navigation bar styling (paired with [DashboardThemeData]).
class ManagerNavBarTheme {
  const ManagerNavBarTheme({
    required this.useGlass,
    required this.barGradientTop,
    required this.barGradientBottom,
    required this.borderColor,
    required this.outerShadow,
    required this.inactiveIconColor,
    required this.activeIconColor,
    required this.pillGradientStart,
    required this.pillGradientEnd,
    required this.pillBorderColor,
    required this.pillGlowColor,
    required this.inactiveIconOpacity,
    required this.pillBorderWidth,
    required this.pillGlowBlur,
  });

  final bool useGlass;
  final Color barGradientTop;
  final Color barGradientBottom;
  final Color borderColor;
  final Color outerShadow;
  final Color inactiveIconColor;
  final Color activeIconColor;
  final Color pillGradientStart;
  final Color pillGradientEnd;
  final Color pillBorderColor;
  final Color pillGlowColor;
  final double inactiveIconOpacity;
  final double pillBorderWidth;
  final double pillGlowBlur;
}

/// Semantic colors for the manager dashboard and shell (light + dark).
class DashboardThemeData {
  const DashboardThemeData({
    required this.appearance,
    required this.nav,
    required this.scaffoldBackground,
    required this.primary,
    required this.primarySoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.good,
    required this.bad,
    required this.warn,
    required this.info,
    required this.useGlassCards,
    required this.notificationTileLight,
    required this.refreshIndicatorBackground,
    required this.surfaceMuted,
    required this.headerButtonBackground,
    required this.headerShadow,
    required this.cardBorder,
    required this.cardShadow,
    required this.heroCardBackground,
    required this.heroCardBorder,
    required this.heroCardShadow,
    required this.glowTopRight,
    required this.glowBottomLeft,
    required this.glowTopRightOpacity,
    required this.glowBottomLeftOpacity,
    required this.chartLine,
    required this.chartFillTop,
    required this.chartFillBottom,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.avatarGradientEnd,
    required this.surfaceCard,
    required this.surfaceElevated,
    required this.borderSubtle,
    required this.accentText,
    required this.adminBg,
    required this.adminSurface,
    required this.adminSurfaceElevated,
    required this.adminBorder,
    required this.adminText,
    required this.adminTextMuted,
    required this.adminTextDim,
  });

  final ManagerDashboardAppearance appearance;
  final ManagerNavBarTheme nav;
  final Color scaffoldBackground;
  final Color primary;
  final Color primarySoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color good;
  final Color bad;
  final Color warn;
  final Color info;
  final bool useGlassCards;
  final bool notificationTileLight;
  final Color refreshIndicatorBackground;
  final Color surfaceMuted;
  final Color headerButtonBackground;
  final Color headerShadow;
  final Color cardBorder;
  final Color cardShadow;
  final Color heroCardBackground;
  final Color heroCardBorder;
  final Color heroCardShadow;
  final Color glowTopRight;
  final Color glowBottomLeft;
  final double glowTopRightOpacity;
  final double glowBottomLeftOpacity;
  final Color chartLine;
  final Color chartFillTop;
  final Color chartFillBottom;
  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color avatarGradientEnd;
  final Color surfaceCard;
  final Color surfaceElevated;
  final Color borderSubtle;
  final Color accentText;
  final Color adminBg;
  final Color adminSurface;
  final Color adminSurfaceElevated;
  final Color adminBorder;
  final Color adminText;
  final Color adminTextMuted;
  final Color adminTextDim;

  bool get isDark => appearance == ManagerDashboardAppearance.dark;

  static DashboardThemeData forAppearance(
    ManagerDashboardAppearance appearance,
  ) {
    return appearance == ManagerDashboardAppearance.dark ? dark() : light();
  }

  static DashboardThemeData light() {
    const primary = Color(0xFF2563EB);
    const textGrey = Color(0xFF64748B);
    return DashboardThemeData(
      appearance: ManagerDashboardAppearance.light,
      nav: const ManagerNavBarTheme(
        useGlass: false,
        barGradientTop: Color(0xFFFFFFFF),
        barGradientBottom: Color(0xFFF7FAFF),
        borderColor: Color(0xFFC7D9F5),
        outerShadow: Color(0x1A2563EB),
        inactiveIconColor: textGrey,
        activeIconColor: Colors.white,
        pillGradientStart: Color(0xFF2563EB),
        pillGradientEnd: Color(0xFF3B82F6),
        pillBorderColor: Color(0xFF1D4ED8),
        pillGlowColor: Color(0x992563EB),
        inactiveIconOpacity: 0.62,
        pillBorderWidth: 0,
        pillGlowBlur: 18,
      ),
      scaffoldBackground: const Color(0xFFE3EDFC),
      primary: primary,
      primarySoft: Color(0xFFEFF6FF),
      textPrimary: Color(0xFF0F172A),
      textSecondary: textGrey,
      good: Color(0xFF10B981),
      bad: Color(0xFFEF4444),
      warn: Color(0xFFF59E0B),
      info: Color(0xFF3B82F6),
      useGlassCards: false,
      notificationTileLight: true,
      refreshIndicatorBackground: Color(0xFFFFFFFF),
      surfaceMuted: Color(0xFFE3EDFC),
      headerButtonBackground: Color(0xFFFFFFFF),
      headerShadow: Color(0x0A0F172A),
      cardBorder: Color(0x142563EB),
      cardShadow: Color(0x0F2563EB),
      heroCardBackground: Color(0xFFFFFFFF),
      heroCardBorder: Color(0x142563EB),
      heroCardShadow: Color(0x0F2563EB),
      glowTopRight: primary,
      glowBottomLeft: Color(0xFF38BDF8),
      glowTopRightOpacity: 0.1,
      glowBottomLeftOpacity: 0.08,
      chartLine: primary,
      chartFillTop: Color(0x332563EB),
      chartFillBottom: Color(0x002563EB),
      skeletonBase: Color(0x0A64748B),
      skeletonHighlight: Color(0x1464748B),
      avatarGradientEnd: Color(0xFF60A5FA),
      surfaceCard: Color(0xFFFFFFFF),
      surfaceElevated: Color(0xFFFFFFFF),
      borderSubtle: Color(0xFFC7D9F5),
      accentText: Color(0xFF1D4ED8),
      adminBg: Color(0xFFDCE8FB),
      adminSurface: Color(0xFFFFFFFF),
      adminSurfaceElevated: Color(0xFFEEF4FE),
      adminBorder: Color(0xFFC7D9F5),
      adminText: Color(0xFF0F172A),
      adminTextMuted: Color(0xFF64748B),
      adminTextDim: Color(0xFF94A3B8),
    );
  }

  static DashboardThemeData dark() {
    const primary = Color(0xFF3B82F6);
    const textDim = Color(0x99FFFFFF);
    return DashboardThemeData(
      appearance: ManagerDashboardAppearance.dark,
      nav: const ManagerNavBarTheme(
        useGlass: false,
        barGradientTop: Color(0xFF10203A),
        barGradientBottom: Color(0xFF10203A),
        borderColor: Color(0xFF24395C),
        outerShadow: Color(0x66000000),
        inactiveIconColor: Colors.white,
        activeIconColor: Colors.white,
        pillGradientStart: Color(0x6B3B82F6),
        pillGradientEnd: Color(0x472563EB),
        pillBorderColor: Color(0xA63B82F6),
        pillGlowColor: Color(0x593B82F6),
        inactiveIconOpacity: 0.42,
        pillBorderWidth: 1.2,
        pillGlowBlur: 14,
      ),
      scaffoldBackground: const Color(0xFF08152B),
      primary: primary,
      primarySoft: Color(0x1A3B82F6),
      textPrimary: Color(0xFFF8FAFC),
      textSecondary: textDim,
      good: Color(0xFF10B981),
      bad: Color(0xFFEF4444),
      warn: Color(0xFFF59E0B),
      info: Color(0xFF60A5FA),
      useGlassCards: true,
      notificationTileLight: false,
      refreshIndicatorBackground: Color(0xFF10203A),
      surfaceMuted: Color(0x0AFFFFFF),
      headerButtonBackground: Color(0x0AFFFFFF),
      headerShadow: Color(0x00000000),
      cardBorder: Color(0x14FFFFFF),
      cardShadow: Color(0x00000000),
      heroCardBackground: Color(0x0AFFFFFF),
      heroCardBorder: Color(0x14FFFFFF),
      heroCardShadow: Color(0x00000000),
      glowTopRight: Color(0xFF3B82F6),
      glowBottomLeft: Color(0xFF0EA5E9),
      glowTopRightOpacity: 0.14,
      glowBottomLeftOpacity: 0.12,
      chartLine: primary,
      chartFillTop: Color(0x333B82F6),
      chartFillBottom: Color(0x003B82F6),
      skeletonBase: Color(0x0AFFFFFF),
      skeletonHighlight: Color(0x14FFFFFF),
      avatarGradientEnd: Color(0xFF60A5FA),
      surfaceCard: Color(0xFF10203A),
      surfaceElevated: Color(0xFF17294A),
      borderSubtle: Color(0x14FFFFFF),
      accentText: Color(0xFFBFDBFE),
      adminBg: Color(0xFF0B1930),
      adminSurface: Color(0xFF12233E),
      adminSurfaceElevated: Color(0xFF182B4A),
      adminBorder: Color(0xFF24395C),
      adminText: Color(0xFFF3F6FC),
      adminTextMuted: Color(0xFF9AA8C0),
      adminTextDim: Color(0xFF6B7A94),
    );
  }
}
