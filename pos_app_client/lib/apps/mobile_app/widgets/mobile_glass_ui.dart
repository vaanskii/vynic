import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared dark glass palette for manager mobile screens.
abstract final class MobileGlassTheme {
  static const bg = Color(0xFF050508);
  static const primary = Color(0xFF6366F1);
  static const accent = Color(0xFF3B82F6);
  static const good = Color(0xFF10B981);
  static const bad = Color(0xFFEF4444);
  static const warn = Color(0xFFF59E0B);
  static const highlightFill = Color(0x33F97316);
  static const highlightBorder = Color(0xFFF97316);

  static Color muted([double opacity = 0.55]) =>
      Colors.white.withValues(alpha: opacity);

  static Color border([double opacity = 0.1]) =>
      Colors.white.withValues(alpha: opacity);

  static Color surface([double opacity = 0.06]) =>
      Colors.white.withValues(alpha: opacity);
}

class MobileGlowOrb extends StatelessWidget {
  const MobileGlowOrb({
    super.key,
    required this.color,
    required this.size,
  });

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
          colors: [
            color.withValues(alpha: 0.35),
            color.withValues(alpha: 0),
          ],
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: MobileGlassTheme.surface(),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? MobileGlassTheme.border()),
          ),
          child: child,
        ),
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
    return Scaffold(
      backgroundColor: MobileGlassTheme.bg,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: MobileGlassTheme.muted(0.5),
                      fontSize: 12,
                    ),
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
    this.color = MobileGlassTheme.primary,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: color,
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
                const SizedBox(width: 8),
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
    this.color = MobileGlassTheme.bad,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}
