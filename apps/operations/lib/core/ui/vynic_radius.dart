import 'package:flutter/widgets.dart';

/// Vynic corner-radius scale (docs/UI_PLAN.md §6.2): 8 / 12 / pill.
///
/// 8 is the default card/panel/button radius (matches `admin_design.dart`).
/// 12 is for larger floating surfaces (dialogs, side sheets). `pill` is for
/// status chips and toggle segments.
abstract final class VynicRadius {
  static const double sm = 8;
  static const double lg = 12;

  /// Effectively a pill for any control shorter than 999px tall.
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}
