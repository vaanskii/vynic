import 'package:flutter/widgets.dart';
import 'package:vynic/core/ui/vynic_colors.dart';

/// Vynic typography scale (docs/UI_PLAN.md §6.2): sizes 11 / 13 / 15 / 18 / 24,
/// weights 600 / 800 only.
///
/// Styles intentionally set NO `fontFamily`, so text inherits the ambient
/// font and Georgian rendering is unaffected. 11px is the absolute floor
/// (chips/labels); operational text read at table distance should use
/// [bodyStrong] (15) or larger. Height values keep Georgian ascenders/
/// descenders from clipping.
abstract final class VynicTextStyles {
  static const FontWeight _semibold = FontWeight.w600;
  static const FontWeight _bold = FontWeight.w800;

  /// 24 / 800 — screen or section title.
  static const TextStyle title = TextStyle(
    fontSize: 24,
    fontWeight: _bold,
    height: 1.25,
    color: VynicColors.textPrimary,
  );

  /// 18 / 800 — sub-section / card heading.
  static const TextStyle heading = TextStyle(
    fontSize: 18,
    fontWeight: _bold,
    height: 1.3,
    color: VynicColors.textPrimary,
  );

  /// 15 / 600 — emphasized body / primary list text.
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    fontWeight: _semibold,
    height: 1.35,
    color: VynicColors.textPrimary,
  );

  /// 15 / 600 muted — secondary body.
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: _semibold,
    height: 1.35,
    color: VynicColors.textMuted,
  );

  /// 13 / 600 — labels, secondary rows.
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: _semibold,
    height: 1.35,
    color: VynicColors.textMuted,
  );

  /// 11 / 800 — chip text, smallest allowed. Never below 11px.
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: _bold,
    height: 1.3,
    color: VynicColors.textMuted,
  );

  /// Absolute minimum font size any Vynic text may use.
  static const double minFontSize = 11;
}
