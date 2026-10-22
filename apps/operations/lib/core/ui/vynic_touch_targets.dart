/// Vynic touch-target tokens (docs/UI_PLAN.md §6.1).
///
/// The POS is used standing up, at speed, sometimes on a touch terminal — the
/// waiter/cashier surfaces have a hard 44px floor. Admin/mouse-only surfaces
/// may drop to 36px. These floors must hold *after* Windows display scaling
/// (125%/150%): because Flutter logical pixels already account for the OS
/// scale factor, a widget sized at [minPos] logical px stays >= 44 physical px
/// at 100% and grows with OS scaling. The POS application also has its own
/// transform; use [posDesktop] there to preserve the target after shrinking.
abstract final class VynicTouchTargets {
  /// POS desktop controls inside PosScaledSurface. At the supported 1024px
  /// window its 1200px design floor paints 56 logical px as about 48px.
  /// [minPos] alone does not account for that application-level transform.
  static const double posDesktop = 56;

  /// Minimum interactive size on POS / waiter / cashier surfaces.
  static const double minPos = 44;

  /// Minimum interactive size on admin / mouse-only surfaces.
  static const double minAdmin = 36;

  /// Minimum height for a tappable row in a data table/list.
  static const double minRow = 44;
}
