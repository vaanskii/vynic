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

  static DashboardThemeData light() => DashboardThemeData(
    appearance: ManagerDashboardAppearance.light,
    nav: ManagerNavBarTheme(
      useGlass: false,
      barGradientTop: const Color(0xFFFFFFFF),
      barGradientBottom: const Color(0xFFFFFFFF),
      borderColor: const Color(0xFFE9E6ED),
      outerShadow: Colors.transparent,
      inactiveIconColor: const Color(0xFF6E6A78),
      activeIconColor: const Color(0xFF7052AD),
      pillGradientStart: const Color(0xFFF0EBF8),
      pillGradientEnd: const Color(0xFFF0EBF8),
      pillBorderColor: const Color(0xFFF0EBF8),
      pillGlowColor: Colors.transparent,
      inactiveIconOpacity: 1,
      pillBorderWidth: 0,
      pillGlowBlur: 0,
    ),
    scaffoldBackground: const Color(0xFFF6F5F8),
    primary: const Color(0xFF7052AD),
    primarySoft: const Color(0xFFF0EBF8),
    textPrimary: const Color(0xFF282532),
    textSecondary: const Color(0xFF6E6A78),
    good: const Color(0xFF287653),
    bad: const Color(0xFFBA3F4A),
    warn: const Color(0xFF956018),
    info: const Color(0xFF526C9A),
    notificationTileLight: true,
    refreshIndicatorBackground: const Color(0xFFFFFFFF),
    surfaceMuted: const Color(0xFFF0EEF3),
    headerButtonBackground: const Color(0xFFFFFFFF),
    cardBorder: const Color(0xFFE9E6ED),
    heroCardBackground: const Color(0xFFFFFFFF),
    heroCardBorder: const Color(0xFFE9E6ED),
    glowTopRight: const Color(0xFF7052AD),
    glowBottomLeft: const Color(0xFF7052AD),
    chartLine: const Color(0xFF7052AD),
    chartFillTop: const Color(0x267052AD),
    chartFillBottom: const Color(0x007052AD),
    skeletonBase: const Color(0xFFE9E6ED),
    skeletonHighlight: const Color(0xFFF0EEF3),
    avatarGradientEnd: const Color(0xFF7052AD),
    surfaceCard: const Color(0xFFFFFFFF),
    surfaceElevated: const Color(0xFFF6F5F8),
    borderSubtle: const Color(0xFFE9E6ED),
    accentText: const Color(0xFF7052AD),
    adminBg: const Color(0xFFF6F5F8),
    adminSurface: const Color(0xFFFFFFFF),
    adminSurfaceElevated: const Color(0xFFF0EEF3),
    adminBorder: const Color(0xFFE9E6ED),
    adminText: const Color(0xFF282532),
    adminTextMuted: const Color(0xFF6E6A78),
    adminTextDim: const Color(0xFF6E6A78),
    useGlassCards: false,
    headerShadow: Colors.transparent,
    cardShadow: Colors.transparent,
    heroCardShadow: Colors.transparent,
    glowTopRightOpacity: 0,
    glowBottomLeftOpacity: 0,
  );

  static DashboardThemeData dark() => DashboardThemeData(
    appearance: ManagerDashboardAppearance.dark,
    nav: ManagerNavBarTheme(
      useGlass: false,
      barGradientTop: const Color(0xFF23202B),
      barGradientBottom: const Color(0xFF23202B),
      borderColor: const Color(0xFF3D3748),
      outerShadow: Colors.transparent,
      inactiveIconColor: const Color(0xFFBBB4C6),
      activeIconColor: const Color(0xFFBBA1EA),
      pillGradientStart: const Color(0xFF332A43),
      pillGradientEnd: const Color(0xFF332A43),
      pillBorderColor: const Color(0xFF332A43),
      pillGlowColor: Colors.transparent,
      inactiveIconOpacity: 1,
      pillBorderWidth: 0,
      pillGlowBlur: 0,
    ),
    scaffoldBackground: const Color(0xFF19171F),
    primary: const Color(0xFFBBA1EA),
    primarySoft: const Color(0xFF332A43),
    textPrimary: const Color(0xFFF4F0F8),
    textSecondary: const Color(0xFFBBB4C6),
    good: const Color(0xFF8BD6B2),
    bad: const Color(0xFFFFA9B3),
    warn: const Color(0xFFEBC38A),
    info: const Color(0xFFABC3EA),
    notificationTileLight: false,
    refreshIndicatorBackground: const Color(0xFF23202B),
    surfaceMuted: const Color(0xFF2D2936),
    headerButtonBackground: const Color(0xFF23202B),
    cardBorder: const Color(0xFF3D3748),
    heroCardBackground: const Color(0xFF23202B),
    heroCardBorder: const Color(0xFF3D3748),
    glowTopRight: const Color(0xFFBBA1EA),
    glowBottomLeft: const Color(0xFFBBA1EA),
    chartLine: const Color(0xFFBBA1EA),
    chartFillTop: const Color(0x26BBA1EA),
    chartFillBottom: const Color(0x00BBA1EA),
    skeletonBase: const Color(0xFF332D3E),
    skeletonHighlight: const Color(0xFF40384C),
    avatarGradientEnd: const Color(0xFFBBA1EA),
    surfaceCard: const Color(0xFF23202B),
    surfaceElevated: const Color(0xFF2D2936),
    borderSubtle: const Color(0xFF3D3748),
    accentText: const Color(0xFFD4BFF6),
    adminBg: const Color(0xFF19171F),
    adminSurface: const Color(0xFF23202B),
    adminSurfaceElevated: const Color(0xFF2D2936),
    adminBorder: const Color(0xFF3D3748),
    adminText: const Color(0xFFF4F0F8),
    adminTextMuted: const Color(0xFFBBB4C6),
    adminTextDim: const Color(0xFFBBB4C6),
    useGlassCards: false,
    headerShadow: Colors.transparent,
    cardShadow: Colors.transparent,
    heroCardShadow: Colors.transparent,
    glowTopRightOpacity: 0,
    glowBottomLeftOpacity: 0,
  );
}
