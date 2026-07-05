import 'package:flutter/widgets.dart';

/// Vynic color tokens — the single source of truth for the modern light POS
/// design direction (docs/UI_PLAN.md §6.2).
///
/// Additive only in UI Phase 2: no screen imports these yet. Values are
/// intentionally the same family as the existing `admin_design.dart` (teal
/// accent, neutral greys) so migrating a screen onto tokens is a lateral move,
/// not a repaint. Do NOT introduce purple/violet or glass-gradient surfaces
/// for operational screens.
abstract final class VynicColors {
  // --- Surfaces -----------------------------------------------------------
  /// App/background behind cards and panels.
  static const Color background = Color(0xFFF7F8FA);

  /// Primary raised surface (cards, panels, dialogs).
  static const Color card = Color(0xFFFFFFFF);

  /// Secondary/inset surface (nested rows, subtle fills).
  static const Color cardSoft = Color(0xFFF9FAFB);

  // --- Lines --------------------------------------------------------------
  static const Color border = Color(0xFFE5E7EB);

  /// Slightly stronger divider for structural separation.
  static const Color borderStrong = Color(0xFFD1D5DB);

  // --- Text ---------------------------------------------------------------
  static const Color textPrimary = Color(0xFF111827);
  static const Color textMuted = Color(0xFF5B677A);

  /// Disabled-only. Never use for live information a user must read.
  static const Color textDisabled = Color(0xFF94A3B8);

  /// Text/icon drawn on top of [accent].
  static const Color onAccent = Color(0xFFFFFFFF);

  // --- Accent -------------------------------------------------------------
  static const Color accent = Color(0xFF0F766E);

  /// Pressed/hover state — [accent] darkened ~8%.
  static const Color accentHover = Color(0xFF0E6D65);

  /// 12%-opacity accent fill for selected chips/nav backgrounds.
  static const Color accentSoft = Color(0x1F0F766E);

  // --- Status (full-strength — fills, icons, dots) ------------------------
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  /// Neutral status foreground (e.g. Free, Printed, Stale).
  static const Color neutral = Color(0xFF5B677A);

  // --- Status text-on-tint (AA-compliant chip/label text) -----------------
  // The full-strength success/warning hues above land at only AA-large on
  // their 12%-tint chip backgrounds; 11px bold chip text is not "large" under
  // WCAG, so chip *text* uses these darker shades (green-700 / amber-700) to
  // clear AA-normal (4.5:1). Fills, icons, and dots keep the hues above.
  // info/neutral already pass on their tints, so their text == hue.
  static const Color successText = Color(0xFF15803D);
  static const Color warningText = Color(0xFFB45309);
  static const Color dangerText = Color(0xFFB91C1C);

  // --- Status soft backgrounds (chip fills) -------------------------------
  static const Color successSoft = Color(0xFFECFDF5);
  static const Color warningSoft = Color(0xFFFFFBEB);
  static const Color dangerSoft = Color(0xFFFEF2F2);
  static const Color infoSoft = Color(0xFFEFF6FF);
  static const Color neutralSoft = Color(0xFFF1F5F9);

  // --- Status soft borders (chip outlines) --------------------------------
  static const Color successBorder = Color(0xFFA7F3D0);
  static const Color warningBorder = Color(0xFFFDE68A);
  static const Color dangerBorder = Color(0xFFFECACA);
  static const Color infoBorder = Color(0xFFBFDBFE);
  static const Color neutralBorder = Color(0xFFE2E8F0);
}
