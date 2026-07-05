import 'package:flutter/widgets.dart';

/// Vynic elevation tokens (docs/UI_PLAN.md §6.2).
///
/// One shadow for floating surfaces (panels, dialogs, side sheets) only;
/// everything else is flat with a 1px border. Do not stack multiple shadows
/// or add colored glows on operational screens.
abstract final class VynicShadows {
  /// Subtle lift for a floating panel/card. Matches the shadow already used
  /// by `admin_design.dart`'s `panelDecoration`.
  static const List<BoxShadow> panel = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  /// Slightly stronger lift for modal dialogs / side sheets.
  static const List<BoxShadow> overlay = [
    BoxShadow(color: Color(0x1F0F172A), blurRadius: 28, offset: Offset(0, 12)),
  ];

  /// Explicitly no shadow — for flat, bordered cards.
  static const List<BoxShadow> none = [];
}
