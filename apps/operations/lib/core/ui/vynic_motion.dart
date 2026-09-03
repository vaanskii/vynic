/// Vynic motion tokens (docs/UI_PLAN.md §6.2): 120ms / 200ms only.
///
/// This is an operational POS, not a marketing site — keep animation minimal
/// and fast. [fast] is for small state changes (hover, chip toggle); [normal]
/// is for panel/sheet transitions. Do not introduce longer or bouncier
/// durations for operational surfaces.
abstract final class VynicMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);

  /// The only durations any Vynic primitive is allowed to use. Enforced by
  /// `test/unit/vynic_tokens_test.dart` so a longer duration can't slip in.
  static const List<Duration> allowed = [fast, normal];
}
