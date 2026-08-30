import 'package:flutter/widgets.dart';
import 'package:vynic/core/ui/vynic_breakpoints.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';

/// Responsive helpers built on [VynicBreakpoints]. Pure functions + a couple
/// of context conveniences — no widget tree, no side effects.
///
/// The panel/dialog width rules here are the safety net that lets UI Phase 3+
/// fix shell/tables at 1366×768 and 125–150% scaling without each screen
/// re-deriving its own magic numbers. See docs/UI_RESPONSIVE.md.
abstract final class VynicResponsive {
  // --- Panel width rules --------------------------------------------------
  /// A side panel (order cart, detail rail) must never get narrower than this,
  /// or its controls fall below the touch-target floor / text wraps to noise.
  static const double minPanelWidth = 300;

  /// …and never wider than this, or long lists become an awkward void on
  /// expanded displays.
  static const double maxPanelWidth = 460;

  /// The narrower panel width to use in [VynicLayoutMode.compact].
  static const double compactPanelWidth = 300;

  // --- Content width rules ------------------------------------------------
  /// Reading/content columns cap here so text lines stay scannable on wide
  /// monitors (forms, reports, settings).
  static const double maxContentWidth = 1200;

  // --- Dialog width rules -------------------------------------------------
  /// A dialog never exceeds this logical width regardless of screen size.
  static const double maxDialogWidth = 560;

  /// Horizontal breathing room reserved on each side of a dialog so it never
  /// touches the screen edge on a small terminal.
  static const double dialogViewportMargin = 32;

  static VynicLayoutMode modeOf(BuildContext context) =>
      VynicBreakpoints.modeForWidth(MediaQuery.sizeOf(context).width);

  static bool isCompact(BuildContext context) =>
      modeOf(context) == VynicLayoutMode.compact;

  /// Outer page gutter, scaled by layout mode.
  static double gutter(VynicLayoutMode mode) {
    switch (mode) {
      case VynicLayoutMode.compact:
        return VynicSpacing.md; // 16
      case VynicLayoutMode.regular:
        return VynicSpacing.lg; // 24
      case VynicLayoutMode.expanded:
        return VynicSpacing.xl; // 32
    }
  }

  /// Gap between sibling cards/tiles, scaled by layout mode.
  static double sectionGap(VynicLayoutMode mode) {
    switch (mode) {
      case VynicLayoutMode.compact:
        return VynicSpacing.sm; // 12
      case VynicLayoutMode.regular:
      case VynicLayoutMode.expanded:
        return VynicSpacing.md; // 16
    }
  }

  /// Resolve a side-panel width for the given available width, clamped to the
  /// [minPanelWidth]/[maxPanelWidth] rules and never starving the primary pane
  /// (caps at 42% of available width).
  static double panelWidth(double availableWidth, {double preferred = 380}) {
    final mode = VynicBreakpoints.modeForWidth(availableWidth);
    final target = mode == VynicLayoutMode.compact
        ? compactPanelWidth
        : preferred;
    final ceiling = availableWidth * 0.42;
    final upper = maxPanelWidth < ceiling ? maxPanelWidth : ceiling;
    if (upper < minPanelWidth) return upper; // extremely narrow screen
    return target.clamp(minPanelWidth, upper).toDouble();
  }

  /// Overflow-safe dialog width: capped by [maxDialogWidth] but always leaving
  /// [dialogViewportMargin] on each side so it can't overflow a 1280×720 (or
  /// smaller after scaling) viewport.
  static double dialogWidth(BuildContext context, {double? preferred}) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final available = screenWidth - (dialogViewportMargin * 2);
    final want = preferred ?? maxDialogWidth;
    final cap = want < maxDialogWidth ? want : maxDialogWidth;
    return available < cap ? available : cap;
  }

  /// Whether two panes fit side by side at [availableWidth] (primary keeps at
  /// least [minPrimaryWidth] after the panel takes its share).
  static bool canShowTwoPanes(
    double availableWidth, {
    double minPrimaryWidth = 480,
  }) {
    if (availableWidth < VynicBreakpoints.compactMax) return false;
    return availableWidth - panelWidth(availableWidth) >= minPrimaryWidth;
  }
}
