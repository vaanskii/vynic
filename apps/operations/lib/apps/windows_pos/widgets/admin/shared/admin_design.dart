import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

/// The admin panel's design tokens.
///
/// These used to be their own palette — a teal accent, cool grey surfaces, a
/// drop shadow under every card — which is why the admin read as a different
/// product from the floor and the home sections sitting one screen away. They
/// are now derived from [VynicFloorTokens], the same tokens the rest of the POS
/// is built from, so the panel inherits the redesign instead of drifting from
/// it.
///
/// The names are kept as they were. Thirteen sections reference them, and
/// renaming would have meant touching every one of those files to change
/// nothing anybody can see.
abstract final class AdminDesign {
  /// Lavender, not teal. Selection, focus, and the one primary action.
  ///
  /// [accent] is a mid-tone, matching what the teal it replaced was: readable
  /// as a foreground, and the thing call sites tint with `withValues(alpha:)`
  /// when they want a wash. [accentSoft] is that wash pre-mixed, for the places
  /// that want a fill rather than a tint.
  static const Color accent = VynicFloorTokens.accentText;
  static const Color accentDark = VynicFloorTokens.accentStrong;
  static const Color accentSoft = VynicFloorTokens.accentSoft;
  static const Color accentSoftBorder = Color(0xFFE2DCF2);

  /// Warm page behind the panels.
  static const Color surface = VynicFloorTokens.page;
  static const Color panel = VynicFloorTokens.panel;
  static const Color panelSoft = VynicFloorTokens.metricFill;
  static const Color border = VynicFloorTokens.panelBorder;
  static const Color text = VynicFloorTokens.text;
  static const Color muted = VynicFloorTokens.textMuted;

  /// A muted brick. It has to read as serious without shouting at somebody
  /// mid-service.
  static const Color danger = VynicFloorTokens.dangerText;
  static const Color warning = VynicFloorTokens.statusPillText;

  /// Controls: buttons, fields, chips.
  static const double radius = 10;

  /// Cards. Panels sit a step softer than the controls inside them.
  static const double panelRadius = VynicFloorTokens.panelRadius;

  /// A card: white, hairline border, and — unlike before — no shadow.
  ///
  /// The [shadow] flag is kept because a dozen call sites pass it, but it no
  /// longer lifts anything off the page. Depth was the old design's way of
  /// separating a card from its background; this one separates them with a
  /// hairline and a warmer page colour, and stacking shadows on top of that
  /// made the panel look like it belonged to a different screen.
  static BoxDecoration panelDecoration({
    Color color = panel,
    Color borderColor = border,
    bool shadow = true,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(panelRadius),
      border: Border.all(color: borderColor),
    );
  }

  static ButtonStyle primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: accentDark,
      foregroundColor: VynicFloorTokens.panel,
      disabledBackgroundColor: VynicFloorTokens.badgeFill,
      disabledForegroundColor: VynicFloorTokens.textFaint,
      elevation: 0,
      shadowColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle outlineButtonStyle({Color foreground = text}) {
    return OutlinedButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: foreground == danger
          ? VynicFloorTokens.dangerFill
          : VynicFloorTokens.panel,
      side: BorderSide(
        color: foreground == danger ? VynicFloorTokens.dangerBorder : border,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// The heading at the top of an admin section.
///
/// Same API as before — icon, title, subtitle, optional action and badge — but
/// it now matches the page headings on the home sections: a 22px title over one
/// muted line, no oversized display type, and a soft lavender icon tile instead
/// of a teal one.
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: AdminDesign.panelDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 620;
          final titleContent = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: VynicFloorTokens.accentSoft,
                  borderRadius: BorderRadius.circular(AdminDesign.radius),
                  border: Border.all(color: const Color(0xFFE2DCF2)),
                ),
                child: Icon(icon, color: VynicFloorTokens.accentText, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VynicFloorTokens.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VynicFloorTokens.textMuted,
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

  /// Retained for the call sites that pass it; [AdminDesign.panelDecoration]
  /// no longer draws one either way.
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

/// A small status tag. Defaults to the accent rather than the old mint green,
/// so a badge nobody colour-coded still lands inside the palette.
class AdminStatusBadge extends StatelessWidget {
  const AdminStatusBadge({
    super.key,
    required this.icon,
    required this.label,
    this.color = VynicFloorTokens.accentText,
    this.background = VynicFloorTokens.accentSoft,
    this.border = const Color(0xFFE2DCF2),
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(VynicFloorTokens.badgeRadius),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
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
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: VynicFloorTokens.metricFill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: VynicFloorTokens.panelBorder),
              ),
              child: Icon(icon, color: VynicFloorTokens.textFaint, size: 24),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VynicFloorTokens.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VynicFloorTokens.textMuted,
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
