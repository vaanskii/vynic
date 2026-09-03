/// Vynic touch-target tokens (docs/UI_PLAN.md §6.1).
///
/// The POS is used standing up, at speed, sometimes on a touch terminal — the
/// waiter/cashier surfaces have a hard 44px floor. Admin/mouse-only surfaces
/// may drop to 36px. These floors must hold *after* Windows display scaling
/// (125%/150%): because Flutter logical pixels already account for the OS
/// scale factor, a widget sized at [minPos] logical px stays >= 44 physical px
/// at 100% and grows with scaling — so sizing to these constants is
/// scale-safe. Never hardcode a tap target smaller than these.
abstract final class VynicTouchTargets {
  /// Minimum interactive size on POS / waiter / cashier surfaces.
  static const double minPos = 44;

  /// Minimum interactive size on admin / mouse-only surfaces.
  static const double minAdmin = 36;

  /// Minimum height for a tappable row in a data table/list.
  static const double minRow = 44;
}
