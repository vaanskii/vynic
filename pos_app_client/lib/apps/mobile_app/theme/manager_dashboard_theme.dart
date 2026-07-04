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
    const primary = Color(0xFF7C3AED);
    const textGrey = Color(0xFF64748B);
    return DashboardThemeData(
      appearance: ManagerDashboardAppearance.light,
      nav: const ManagerNavBarTheme(
        useGlass: false,
        barGradientTop: Color(0xFFFFFFFF),
        barGradientBottom: Color(0xFFFFFFFF),
        borderColor: Color(0xFFE2E8F0),
        outerShadow: Color(0x1A7C3AED),
        inactiveIconColor: textGrey,
        activeIconColor: Colors.white,
        pillGradientStart: Color(0xFF7C3AED),
        pillGradientEnd: Color(0xFF8B5CF6),
        pillBorderColor: Color(0xFF6D28D9),
        pillGlowColor: Color(0x997C3AED),
        inactiveIconOpacity: 0.62,
        pillBorderWidth: 0,
        pillGlowBlur: 18,
      ),
      scaffoldBackground: const Color(0xFFF8F9FA),
      primary: primary,
      primarySoft: Color(0xFFF5F3FF),
      textPrimary: Color(0xFF0F172A),
      textSecondary: textGrey,
      good: Color(0xFF10B981),
      bad: Color(0xFFEF4444),
      warn: Color(0xFFF59E0B),
      info: Color(0xFF3B82F6),
      useGlassCards: false,
      notificationTileLight: true,
      refreshIndicatorBackground: Color(0xFFFFFFFF),
      surfaceMuted: Color(0xFFF8F9FA),
      headerButtonBackground: Color(0xFFFFFFFF),
      headerShadow: Color(0x0A0F172A),
      cardBorder: Color(0x0D7C3AED),
      cardShadow: Color(0x0A7C3AED),
      heroCardBackground: Color(0xFFFFFFFF),
      heroCardBorder: Color(0x0D7C3AED),
      heroCardShadow: Color(0x0A7C3AED),
      glowTopRight: primary,
      glowBottomLeft: Color(0xFFFF7E67),
      glowTopRightOpacity: 0.08,
      glowBottomLeftOpacity: 0.05,
      chartLine: primary,
      chartFillTop: Color(0x337C3AED),
      chartFillBottom: Color(0x007C3AED),
      skeletonBase: Color(0x0A64748B),
      skeletonHighlight: Color(0x1464748B),
      avatarGradientEnd: Color(0xFF8B5CF6),
      surfaceCard: Color(0xFFFFFFFF),
      surfaceElevated: Color(0xFFFFFFFF),
      borderSubtle: Color(0xFFE2E8F0),
      accentText: Color(0xFF7C3AED),
      adminBg: Color(0xFFF1F5F9),
      adminSurface: Color(0xFFFFFFFF),
      adminSurfaceElevated: Color(0xFFF8FAFC),
      adminBorder: Color(0xFFE2E8F0),
      adminText: Color(0xFF0F172A),
      adminTextMuted: Color(0xFF64748B),
      adminTextDim: Color(0xFF94A3B8),
    );
  }

  static DashboardThemeData dark() {
    const primary = Color(0xFF6366F1);
    const textDim = Color(0x99FFFFFF);
    return DashboardThemeData(
      appearance: ManagerDashboardAppearance.dark,
      nav: const ManagerNavBarTheme(
        useGlass: false,
        barGradientTop: Color(0xFF15151C),
        barGradientBottom: Color(0xFF15151C),
        borderColor: Color(0xFF2E3440),
        outerShadow: Color(0x66000000),
        inactiveIconColor: Colors.white,
        activeIconColor: Colors.white,
        pillGradientStart: Color(0x6B10B981),
        pillGradientEnd: Color(0x47059669),
        pillBorderColor: Color(0xA610B981),
        pillGlowColor: Color(0x5910B981),
        inactiveIconOpacity: 0.42,
        pillBorderWidth: 1.2,
        pillGlowBlur: 14,
      ),
      scaffoldBackground: const Color(0xFF050508),
      primary: primary,
      primarySoft: Color(0x1A6366F1),
      textPrimary: Color(0xFFF8FAFC),
      textSecondary: textDim,
      good: Color(0xFF10B981),
      bad: Color(0xFFEF4444),
      warn: Color(0xFFF59E0B),
      info: Color(0xFF3B82F6),
      useGlassCards: true,
      notificationTileLight: false,
      refreshIndicatorBackground: Color(0xFF15151C),
      surfaceMuted: Color(0x0AFFFFFF),
      headerButtonBackground: Color(0x0AFFFFFF),
      headerShadow: Color(0x00000000),
      cardBorder: Color(0x14FFFFFF),
      cardShadow: Color(0x00000000),
      heroCardBackground: Color(0x0AFFFFFF),
      heroCardBorder: Color(0x14FFFFFF),
      heroCardShadow: Color(0x00000000),
      glowTopRight: Color(0xFF3B82F6),
      glowBottomLeft: Color(0xFF8B5CF6),
      glowTopRightOpacity: 0.12,
      glowBottomLeftOpacity: 0.1,
      chartLine: primary,
      chartFillTop: Color(0x336366F1),
      chartFillBottom: Color(0x006366F1),
      skeletonBase: Color(0x0AFFFFFF),
      skeletonHighlight: Color(0x14FFFFFF),
      avatarGradientEnd: Color(0xFF8B5CF6),
      surfaceCard: Color(0xFF15151C),
      surfaceElevated: Color(0xFF1C2029),
      borderSubtle: Color(0x14FFFFFF),
      accentText: Color(0xFFC7D2FE),
      adminBg: Color(0xFF0E1014),
      adminSurface: Color(0xFF161920),
      adminSurfaceElevated: Color(0xFF1C2029),
      adminBorder: Color(0xFF2E3440),
      adminText: Color(0xFFF3F4F6),
      adminTextMuted: Color(0xFF9CA3AF),
      adminTextDim: Color(0xFF6B7280),
    );
  }
}
