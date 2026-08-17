import 'package:flutter/widgets.dart';

/// Design tokens for the POS floor screen, taken 1:1 from the approved
/// `Vynic POS Floor` mock.
///
/// They live here rather than in `VynicColors` because the floor screen uses a
/// warmer, quieter set than the operational chrome: the plan surface is almost
/// white, tiles carry hairline borders instead of status fills, and the only
/// saturated colour on the screen is the amber occupied dot. Both the tables
/// dashboard and the floor-plan renderer read from here so they cannot drift
/// apart.
abstract final class VynicFloorTokens {
  // --- surfaces -----------------------------------------------------------

  /// Page behind the panels.
  static const Color page = Color(0xFFF7F6F4);

  /// Plan panel and side rail.
  static const Color panel = Color(0xFFFFFFFF);

  /// Hairline around panels, the floor switch and tiles.
  static const Color panelBorder = Color(0xFFECEAE6);

  /// The plan's own inner surface — a touch off-white against the panel.
  static const Color canvas = Color(0xFFFCFCFB);
  static const Color canvasBorder = Color(0xFFEEECE8);

  // --- text ---------------------------------------------------------------

  static const Color text = Color(0xFF1C1A19);
  static const Color textMuted = Color(0xFF6F6A65);
  static const Color textFaint = Color(0xFF8A8480);

  /// Section headings in the rail (uppercase, tracked out).
  static const Color sectionLabel = Color(0xFF9A948F);

  // --- accent -------------------------------------------------------------

  /// Selected-tab fill: pale lavender, not a saturated purple.
  static const Color accentSoft = Color(0xFFF2EFFA);
  static const Color accentText = Color(0xFF52447A);
  static const Color accentBadgeText = Color(0xFF6F5F92);

  // --- status -------------------------------------------------------------

  /// Free — a neutral dot, deliberately not green.
  static const Color freeDot = Color(0xFFE2E0DB);

  /// Occupied — the one saturated colour on the screen.
  static const Color occupiedDot = Color(0xFFD9A531);
  static const Color occupiedFill = Color(0xFFFFFDF7);
  static const Color occupiedBorder = Color(0xFFECDCB6);
  static const Color occupiedMeta = Color(0xFF8A7A52);
  static const Color occupiedValue = Color(0xFF8A6A20);
  static const Color occupiedTileFill = Color(0xFFFDF9EF);

  /// Reserved.
  static const Color reservedDot = Color(0xFFD1C0DD);

  // --- tiles --------------------------------------------------------------

  static const Color tileFill = Color(0xFFFFFFFF);
  static const Color tileBorder = Color(0xFFE9E6E2);
  static const Color tileBorderHover = Color(0xFFCFCAC3);

  /// Neutral metric tile in the rail — no border, just a soft fill.
  static const Color metricFill = Color(0xFFF9F8F6);

  /// Inactive floor-tab badge.
  static const Color badgeFill = Color(0xFFF4F3F0);

  /// Rail section dividers.
  static const Color divider = Color(0xFFF0EEEA);

  // --- radii --------------------------------------------------------------

  /// Panels (plan, rail).
  static const double panelRadius = 14;

  /// The plan's inner surface.
  static const double canvasRadius = 20;

  /// Table tiles and venue objects.
  static const double tileRadius = 14;

  /// The floor-switch container.
  static const double switchRadius = 11;

  /// Buttons inside the floor switch.
  static const double switchButtonRadius = 8;

  /// Rail metric tiles.
  static const double metricRadius = 11;

  /// Count badges.
  static const double badgeRadius = 9;

  // --- elevation ----------------------------------------------------------

  /// Free tile: `0 1px 2px rgba(28,26,25,0.03)`.
  static const List<BoxShadow> tileShadow = [
    BoxShadow(
      color: Color(0x081C1A19),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Occupied tile sits a hair higher: `rgba(28,26,25,0.04)`.
  static const List<BoxShadow> occupiedTileShadow = [
    BoxShadow(
      color: Color(0x0A1C1A19),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  // --- venue objects ------------------------------------------------------

  static const Color barFill = Color(0xFFF4F7FA);
  static const Color barBorder = Color(0xFFE3EAF1);
  static const Color barText = Color(0xFF4D6A85);

  static const Color stageFill = Color(0xFFFAF5F8);
  static const Color stageBorder = Color(0xFFECDDE6);
  static const Color stageText = Color(0xFF8D6B7E);
}
