import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

/// The POS's shared surface vocabulary.
///
/// Every operational screen — the floor, the order detail, and the home
/// sections — is built from these five pieces, so they read as one product
/// instead of five that happen to ship together. Each screen used to carry its
/// own palette constants (teal here, slate there, a different blue in the
/// calculator), which is why the same concept could look like three things
/// depending on which tab you were standing in.

/// Uppercase, tracked-out heading. Names a block without competing with the
/// figures inside it.
class PosSectionLabel extends StatelessWidget {
  const PosSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: VynicFloorTokens.sectionLabel,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
      ),
    );
  }
}

/// A page heading: the screen's name, and one line saying what it is for.
class PosPageHeading extends StatelessWidget {
  const PosPageHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
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
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VynicFloorTokens.textMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ],
    );
  }
}

/// White card, hairline border, no shadow. The only container on these screens.
class PosPanel extends StatelessWidget {
  const PosPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Set when the panel holds a scrolling list that must not paint over the
  /// rounded corners.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: child,
    );
  }
}

/// One figure with its caption. The same card the order screen uses for
/// waiter/opened/elapsed/guests.
class PosMetricCard extends StatelessWidget {
  const PosMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.tone,
  });

  final String label;
  final String value;

  /// Colours the figure when it carries a warning (delayed orders, money
  /// owed). Left null the figure is plain — most of them are.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(VynicFloorTokens.metricRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VynicFloorTokens.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 26,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: tone ?? VynicFloorTokens.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How loudly a button argues for itself.
///
/// All-white buttons made every action look equally consequential. The tones
/// sort them by what they touch: money, the schedule, or something that cannot
/// be taken back.
enum PosActionTone {
  /// Harmless and repeatable — printing, refreshing, opening a detail.
  neutral(
    fill: VynicFloorTokens.panel,
    border: VynicFloorTokens.panelBorder,
    foreground: VynicFloorTokens.text,
  ),

  /// Changes what someone owes or pays.
  money(
    fill: VynicFloorTokens.accentSoft,
    border: Color(0xFFE2DCF2),
    foreground: VynicFloorTokens.accentText,
  ),

  /// Moves, defers or closes something without taking payment.
  caution(
    fill: VynicFloorTokens.occupiedTileFill,
    border: VynicFloorTokens.occupiedBorder,
    foreground: VynicFloorTokens.occupiedValue,
  ),

  /// Cancels or voids. The only tone that should give anyone pause.
  danger(
    fill: VynicFloorTokens.dangerFill,
    border: VynicFloorTokens.dangerBorder,
    foreground: VynicFloorTokens.dangerText,
  ),

  disabled(
    fill: VynicFloorTokens.metricFill,
    border: VynicFloorTokens.panelBorder,
    foreground: VynicFloorTokens.textFaint,
  );

  const PosActionTone({
    required this.fill,
    required this.border,
    required this.foreground,
  });

  final Color fill;
  final Color border;
  final Color foreground;
}

/// The standard button: a hairline border and a quiet label, tinted by tone.
///
/// Nothing here is filled — [PosPrimaryButton] is, and it only reads as the
/// loudest thing on a screen because everything around it stays soft.
class PosActionButton extends StatelessWidget {
  const PosActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.icon,
    this.tone = PosActionTone.neutral,
    this.expand = false,
    this.trailing,
  });

  final String label;
  final VoidCallback? onTap;

  /// Press-and-hold. Used where a control carries a secondary configuration
  /// sheet, so it must be threaded through rather than dropped.
  final VoidCallback? onLongPress;
  final IconData? icon;
  final PosActionTone tone;
  final bool expand;
  final Widget? trailing;

  Widget _label(PosActionTone palette) {
    return Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: palette.foreground,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final palette = disabled ? PosActionTone.disabled : tone;

    return Material(
      color: palette.fill,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        onLongPress: disabled ? null : onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: palette.foreground),
                const SizedBox(width: 8),
              ],
              // Flexible only where the row has a width to divide up. In an
              // unbounded row — a horizontal list, an intrinsic-width parent —
              // a non-zero flex has no size to take and the child never gets
              // laid out at all, which surfaces as `child.hasSize is not true`
              // and then a storm of failed hit tests.
              if (expand) Flexible(child: _label(palette)) else _label(palette),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// The one filled button on a screen.
class PosPrimaryButton extends StatelessWidget {
  const PosPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.onLongPress,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final VoidCallback? onLongPress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final foreground = disabled
        ? VynicFloorTokens.textFaint
        : VynicFloorTokens.panel;
    return Material(
      color: disabled
          ? VynicFloorTokens.badgeFill
          : VynicFloorTokens.accentStrong,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        onLongPress: disabled ? null : onLongPress,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 9),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dotted status pill. [tone] carries the dot and the text; the fill is
/// derived so every pill on the POS has the same weight.
class PosStatusPill extends StatelessWidget {
  const PosStatusPill({
    super.key,
    required this.label,
    required this.fill,
    required this.border,
    required this.foreground,
    required this.dot,
  });

  /// Amber — a live table, an order in progress.
  factory PosStatusPill.active(String label) => PosStatusPill(
    label: label,
    fill: VynicFloorTokens.statusPillFill,
    border: VynicFloorTokens.statusPillBorder,
    foreground: VynicFloorTokens.statusPillText,
    dot: VynicFloorTokens.occupiedDot,
  );

  /// Lavender — booked, scheduled, waiting on a time.
  factory PosStatusPill.booked(String label) => PosStatusPill(
    label: label,
    fill: VynicFloorTokens.accentSoft,
    border: const Color(0xFFE2DCF2),
    foreground: VynicFloorTokens.accentText,
    dot: VynicFloorTokens.reservedDot,
  );

  /// Grey — done, closed, nothing left to do.
  factory PosStatusPill.done(String label) => PosStatusPill(
    label: label,
    fill: VynicFloorTokens.badgeFill,
    border: VynicFloorTokens.panelBorder,
    foreground: VynicFloorTokens.textMuted,
    dot: VynicFloorTokens.freeDot,
  );

  /// Brick — cancelled, late, needs attention.
  factory PosStatusPill.alert(String label) => PosStatusPill(
    label: label,
    fill: VynicFloorTokens.dangerFill,
    border: VynicFloorTokens.dangerBorder,
    foreground: VynicFloorTokens.dangerText,
    dot: VynicFloorTokens.dangerText,
  );

  final String label;
  final Color fill;
  final Color border;
  final Color foreground;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Switches which of two panes fills a narrow window.
///
/// On a small screen the list and the detail cannot sit side by side, and
/// stacking them pushes the detail off the bottom of a scroll — you lose the
/// thing you just tapped. This keeps one pane on screen at full height and
/// lets you flip between them.
class PosPaneSwitch extends StatelessWidget {
  const PosPaneSwitch({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: VynicFloorTokens.metricFill,
        borderRadius: BorderRadius.circular(VynicFloorTokens.switchRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: _PaneTab(
                label: labels[i],
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaneTab extends StatelessWidget {
  const _PaneTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? VynicFloorTokens.panel : Colors.transparent,
      borderRadius: BorderRadius.circular(VynicFloorTokens.switchButtonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          VynicFloorTokens.switchButtonRadius,
        ),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              VynicFloorTokens.switchButtonRadius,
            ),
            border: Border.all(
              color: selected
                  ? VynicFloorTokens.panelBorder
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? VynicFloorTokens.text
                  : VynicFloorTokens.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
