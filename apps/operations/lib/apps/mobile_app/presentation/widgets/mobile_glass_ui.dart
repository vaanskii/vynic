import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';

/// Shared glass / light palette for manager mobile screens.
abstract final class MobileGlassTheme {
  static DashboardThemeData get data => DashboardThemeData.forAppearance(
    ManagerAppPreferences.dashboardAppearance.value,
  );

  static Color get bg => data.scaffoldBackground;
  static Color get primary => data.primary;
  static Color get accent => data.info;
  static Color get good => data.good;
  static Color get bad => data.bad;
  static Color get warn => data.warn;
  static Color get highlightFill => data.warn.withValues(alpha: 0.2);
  static Color get highlightBorder => data.warn;
  static Color get textPrimary => data.textPrimary;
  static Color get textSecondary => data.textSecondary;
  static Color get accentText => data.accentText;
  static Color get surfaceCard => data.surfaceCard;
  static Color get surfaceElevated => data.surfaceElevated;
  static Color get borderSubtle => data.borderSubtle;

  static Color muted([double opacity = 0.55]) {
    if (data.isDark) {
      return Colors.white.withValues(alpha: opacity);
    }
    return data.textSecondary.withValues(alpha: opacity.clamp(0.0, 1.0));
  }

  static Color border([double opacity = 0.1]) {
    if (data.isDark) {
      return Colors.white.withValues(alpha: opacity);
    }
    return data.textPrimary.withValues(
      alpha: (opacity * 0.35).clamp(0.06, 0.22),
    );
  }

  static Color surface([double opacity = 0.06]) {
    if (data.isDark) {
      return Colors.white.withValues(alpha: opacity);
    }
    if (opacity <= 0.12) return data.heroCardBackground;
    return data.primarySoft.withValues(alpha: opacity.clamp(0.08, 1.0));
  }

  static DashboardThemeData of(BuildContext context) => managerThemeOf(context);
}

class MobileGlowOrb extends StatelessWidget {
  const MobileGlowOrb({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class MobileGlassCard extends StatelessWidget {
  const MobileGlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 20,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.useGlassCards
            ? MobileGlassTheme.surface()
            : theme.heroCardBackground,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? theme.cardBorder),
        boxShadow: theme.isDark
            ? null
            : [
                BoxShadow(
                  color: theme.cardShadow,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );

    if (!theme.useGlassCards) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: content,
      ),
    );
  }
}

class MobileGlassScreen extends StatelessWidget {
  const MobileGlassScreen({
    super.key,
    required this.body,
    this.orbs = const [],
  });

  final Widget body;
  final List<Widget> orbs;

  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackground,
      body: Stack(
        children: [
          ...orbs,
          SafeArea(child: body),
        ],
      ),
    );
  }
}

class MobileGlassHeader extends StatelessWidget {
  const MobileGlassHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: Icon(Icons.arrow_back_rounded, color: theme.textPrimary),
            )
          else
            SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class MobileGlassPrimaryButton extends StatelessWidget {
  const MobileGlassPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? MobileGlassTheme.of(context).primary;
    final btn = Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 20),
                SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class MobileGlassIconButton extends StatelessWidget {
  const MobileGlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? MobileGlassTheme.bad;
    return Material(
      color: c.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(width: 52, height: 52, child: Icon(icon, color: c)),
      ),
    );
  }
}
