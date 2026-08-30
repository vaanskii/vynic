/// Layout density mode derived from the available width.
///
/// - [compact]  — small laptops / low-res terminals (e.g. 1024×768, 1280×720
///   when a nav rail eats width). Two-pane layouts collapse or narrow.
/// - [regular]  — the common restaurant terminal band (1280–1599 logical px:
///   1280×800, 1366×768, 1440×900, 1536×864, 1600×900 minus chrome).
/// - [expanded] — large/high-density displays and 24–32" externals
///   (1920×1080, 2560×1440).
enum VynicLayoutMode { compact, regular, expanded }

/// Vynic responsive breakpoints (docs/UI_RESPONSIVE.md).
///
/// Thresholds are on **logical** width (Flutter already folds the Windows
/// display-scale factor into logical pixels, so a physical 1920px screen at
/// 150% scaling reports ~1280 logical px and is treated as [regular], not
/// [expanded] — which is exactly what we want, because at 150% there is less
/// usable room). Always measure with `MediaQuery.sizeOf(context).width` or a
/// `LayoutBuilder`'s `constraints.maxWidth`, never a hardcoded resolution.
abstract final class VynicBreakpoints {
  /// Below this logical width, use [VynicLayoutMode.compact].
  /// Chosen to match the existing `compactDesktop` check in `menu_screen.dart`.
  static const double compactMax = 1100;

  /// At/above this logical width, use [VynicLayoutMode.expanded].
  static const double expandedMin = 1600;

  static VynicLayoutMode modeForWidth(double width) {
    if (width < compactMax) return VynicLayoutMode.compact;
    if (width >= expandedMin) return VynicLayoutMode.expanded;
    return VynicLayoutMode.regular;
  }
}
