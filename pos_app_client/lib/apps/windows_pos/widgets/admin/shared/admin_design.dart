import 'package:flutter/material.dart';

abstract final class AdminDesign {
  static const Color accent = Color(0xFF14B8A6);
  static const Color accentDark = Color(0xFF0F766E);
  static const Color surface = Color(0xFFF6F7F9);
  static const Color panel = Colors.white;
  static const Color panelSoft = Color(0xFFF9FAFB);
  static const Color border = Color(0xFFE5E7EB);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF6B7280);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const double radius = 8;

  static BoxDecoration panelDecoration({
    Color color = panel,
    Color borderColor = border,
    bool shadow = true,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor),
      boxShadow: shadow
          ? const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ]
          : null,
    );
  }

  static ButtonStyle primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: accentDark,
      foregroundColor: Colors.white,
      disabledBackgroundColor: border,
      disabledForegroundColor: muted,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle outlineButtonStyle({Color foreground = text}) {
    return OutlinedButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: foreground == danger ? const Color(0xFFFECACA) : border,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: AdminDesign.panelDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 620;
          final titleContent = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AdminDesign.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AdminDesign.radius),
                ),
                child: Icon(icon, color: AdminDesign.accentDark),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AdminDesign.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AdminDesign.muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isCompact && badge != null) ...[
                const SizedBox(width: 12),
                badge!,
              ],
            ],
          );

          if (!isCompact || action == null) {
            return Row(
              children: [
                Expanded(child: titleContent),
                if (action != null) ...[const SizedBox(width: 16), action!],
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleContent,
              if (badge != null) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: badge!),
              ],
              const SizedBox(height: 14),
              action!,
            ],
          );
        },
      ),
    );
  }
}

class AdminPanel extends StatelessWidget {
  const AdminPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = AdminDesign.panel,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: AdminDesign.panelDecoration(color: color, shadow: shadow),
      child: child,
    );
  }
}

class AdminStatusBadge extends StatelessWidget {
  const AdminStatusBadge({
    super.key,
    required this.icon,
    required this.label,
    this.color = AdminDesign.accentDark,
    this.background = const Color(0xFFECFDF5),
    this.border = const Color(0xFFA7F3D0),
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AdminDesign.panelSoft,
                borderRadius: BorderRadius.circular(AdminDesign.radius),
                border: Border.all(color: AdminDesign.border),
              ),
              child: Icon(icon, color: AdminDesign.muted),
            ),
            const SizedBox(height: 13),
            Text(
              title,
              style: const TextStyle(
                color: AdminDesign.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminDesign.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
