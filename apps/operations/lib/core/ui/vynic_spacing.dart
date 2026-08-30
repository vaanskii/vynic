/// Vynic spacing scale (docs/UI_PLAN.md §6.2): 4 / 8 / 12 / 16 / 24 / 32.
///
/// Use these instead of ad-hoc literals so gaps stay on a consistent rhythm.
/// Adaptive gutter/margin helpers that vary by layout mode live in
/// `vynic_responsive.dart`.
abstract final class VynicSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}
