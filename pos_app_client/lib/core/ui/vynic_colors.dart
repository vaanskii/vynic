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
  static const Color background = Color(0xFFF7F6F4);

  /// Primary raised surface (cards, panels, dialogs).
  static const Color card = Color(0xFFFFFFFF);

  /// Secondary/inset surface (nested rows, subtle fills).
  static const Color cardSoft = Color(0xFFFAF9F7);

  // --- Lines --------------------------------------------------------------
  static const Color border = Color(0xFFE6E3DE);

  /// Slightly stronger divider for structural separation.
  static const Color borderStrong = Color(0xFFD5D1CA);

  // --- Text ---------------------------------------------------------------
  static const Color textPrimary = Color(0xFF1C1A18);
  static const Color textMuted = Color(0xFF5C574F);

  /// Disabled-only. Never use for live information a user must read.
  static const Color textDisabled = Color(0xFFB5B0A7);

  /// Text/icon drawn on top of [accent].
  static const Color onAccent = Color(0xFFFFFFFF);

  // --- Accent -------------------------------------------------------------
  static const Color accent = Color(0xFF764B7C);

  /// Pressed/hover state — [accent] darkened ~8%.
  static const Color accentHover = Color(0xFF5C3A61);

  /// 12%-opacity accent fill for selected chips/nav backgrounds.
  static const Color accentSoft = Color(0xFFF3EDF4);

  // --- Status (full-strength — fills, icons, dots) ------------------------
  static const Color success = Color(0xFF2E7D5B);
  static const Color warning = Color(0xFFB7791F);
  static const Color danger = Color(0xFFB4432F);
  static const Color info = Color(0xFF2C6E8F);

  /// Neutral status foreground (e.g. Free, Printed, Stale).
  static const Color neutral = Color(0xFF8C867C);

  // --- Status text-on-tint (AA-compliant chip/label text) -----------------
  // The full-strength success/warning hues above land at only AA-large on
  // their 12%-tint chip backgrounds; 11px bold chip text is not "large" under
  // WCAG, so chip *text* uses these darker shades (green-700 / amber-700) to
  // clear AA-normal (4.5:1). Fills, icons, and dots keep the hues above.
  // info already passes on its tint, so its text == hue.
  static const Color successText = Color(0xFF1F5F44);
  static const Color warningText = Color(0xFF8A5B14);
  static const Color dangerText = Color(0xFF8E3323);
  static const Color neutralText = Color(0xFF4F4941);

  // --- Status soft backgrounds (chip fills) -------------------------------
  static const Color successSoft = Color(0xFFE7F2EC);
  static const Color warningSoft = Color(0xFFFBF2E0);
  static const Color dangerSoft = Color(0xFFFBEAE6);
  static const Color infoSoft = Color(0xFFE4EFF4);
  static const Color neutralSoft = Color(0xFFF0EEEA);

  // --- Status soft borders (chip outlines) --------------------------------
  static const Color successBorder = Color(0xFFC7E0D3);
  static const Color warningBorder = Color(0xFFEBDCB5);
  static const Color dangerBorder = Color(0xFFEFCCC4);
  static const Color infoBorder = Color(0xFFC2DAE5);
  static const Color neutralBorder = Color(0xFFE1DED8);
}
