import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

export 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';

/// The admin panel's half of the POS surface vocabulary.
///
/// The operational screens — the floor, the order detail, the home sections —
/// already share `pos_surface.dart`. The admin panel did not: it carried a dark
/// navy rail with a teal accent, and every section underneath it had grown its
/// own palette (a blue in close-day, a green in sales, an orange in packages,
/// a teal in printers). Fourteen sections, roughly seventy distinct hex codes,
/// none of them the ones the rest of the product uses.
///
/// This file closes that gap. `shared/admin_design.dart` carries the panel and
/// heading widgets the sections already use — those were retuned in place, so
/// thirteen sections inherited the new look without being touched. What lives
/// here is the part that had no home before: the semantic status tones, and the
/// one theme that restyles the panel's several hundred stock Material controls.

/// A semantic status colour: what a thing *means*, not what colour it is.
///
/// The sections were picking hues directly — `0xFF16A34A` for paid, a different
/// green for connected, a third for active — which is why the same idea looked
/// different in two tabs. Naming the meaning instead lets all of them land on
/// one warm family.
class AdminTone {
  const AdminTone({
    required this.fill,
    required this.border,
    required this.text,
  });

  final Color fill;
  final Color border;
  final Color text;
}

/// The five things an admin row can be saying.
///
/// Each tone is published twice: as an [AdminTone] triple for widgets that take
/// a whole palette, and as three flat `const Color`s. The flat ones exist
/// because `AdminTones.successText` is a field read, not a constant
/// expression — it cannot appear inside a `const TextStyle`, and most of the
/// call sites in this panel are exactly that.
abstract final class AdminTones {
  /// Settled, connected, active, paid. A muted sage — the warm palette has no
  /// green of its own, and a saturated one would be the loudest thing on a
  /// page full of quiet cards.
  static const Color successFill = Color(0xFFF4F8F4);
  static const Color successBorder = Color(0xFFD9E5D9);
  static const Color successText = Color(0xFF3E6146);
  static const AdminTone success = AdminTone(
    fill: successFill,
    border: successBorder,
    text: successText,
  );

  /// Pending, held, needs a decision. The same amber family as an occupied
  /// table, so "waiting on someone" reads the same on both screens.
  static const Color warningFill = VynicFloorTokens.statusPillFill;
  static const Color warningBorder = VynicFloorTokens.statusPillBorder;
  static const Color warningText = VynicFloorTokens.statusPillText;
  static const AdminTone warning = AdminTone(
    fill: warningFill,
    border: warningBorder,
    text: warningText,
  );

  /// Cancelled, failed, void.
  static const Color dangerFill = VynicFloorTokens.dangerFill;
  static const Color dangerBorder = VynicFloorTokens.dangerBorder;
  static const Color dangerText = VynicFloorTokens.dangerText;
  static const AdminTone danger = AdminTone(
    fill: dangerFill,
    border: dangerBorder,
    text: dangerText,
  );

  /// Neutral information — a count, a note, a label with no verdict attached.
  static const Color infoFill = VynicFloorTokens.barFill;
  static const Color infoBorder = VynicFloorTokens.barBorder;
  static const Color infoText = VynicFloorTokens.barText;
  static const AdminTone info = AdminTone(
    fill: infoFill,
    border: infoBorder,
    text: infoText,
  );

  /// The panel's own accent: selection, focus, the primary action.
  static const Color accentFill = VynicFloorTokens.accentSoft;
  static const Color accentBorder = Color(0xFFE2DCF2);
  static const Color accentText = VynicFloorTokens.accentText;
  static const AdminTone accent = AdminTone(
    fill: accentFill,
    border: accentBorder,
    text: accentText,
  );

  /// No verdict at all — a resting row.
  static const Color neutralFill = VynicFloorTokens.badgeFill;
  static const Color neutralBorder = VynicFloorTokens.panelBorder;
  static const Color neutralText = VynicFloorTokens.textMuted;
  static const AdminTone neutral = AdminTone(
    fill: neutralFill,
    border: neutralBorder,
    text: neutralText,
  );
}

/// The theme every admin section is rendered under.
///
/// The admin has ~200 stock Material buttons and a scattering of fields,
/// switches and dialogs. Restyling those one at a time would be both enormous
/// and unstable — the next button someone adds would come out navy again.
/// Setting them here means a plain `ElevatedButton` already looks like the rest
/// of the product, and a section only writes a colour when it genuinely means
/// something other than the default.
abstract final class AdminTheme {
  static ThemeData of(BuildContext context) {
    final base = Theme.of(context);
    const radius = 10.0;

    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return base.copyWith(
      scaffoldBackgroundColor: VynicFloorTokens.page,
      canvasColor: VynicFloorTokens.panel,
      dividerColor: VynicFloorTokens.divider,
      colorScheme: base.colorScheme.copyWith(
        primary: VynicFloorTokens.accentStrong,
        onPrimary: VynicFloorTokens.panel,
        primaryContainer: VynicFloorTokens.accentSoft,
        onPrimaryContainer: VynicFloorTokens.accentText,
        secondary: VynicFloorTokens.accentText,
        surface: VynicFloorTokens.panel,
        onSurface: VynicFloorTokens.text,
        error: VynicFloorTokens.dangerText,
        onError: VynicFloorTokens.panel,
        outline: VynicFloorTokens.panelBorder,
        outlineVariant: VynicFloorTokens.divider,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: VynicFloorTokens.accentStrong,
        selectionColor: VynicFloorTokens.accentSoft,
        selectionHandleColor: VynicFloorTokens.accentStrong,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VynicFloorTokens.accentStrong,
          foregroundColor: VynicFloorTokens.panel,
          disabledBackgroundColor: VynicFloorTokens.badgeFill,
          disabledForegroundColor: VynicFloorTokens.textFaint,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: VynicFloorTokens.panel,
          foregroundColor: VynicFloorTokens.text,
          disabledForegroundColor: VynicFloorTokens.textFaint,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          side: const BorderSide(color: VynicFloorTokens.panelBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: VynicFloorTokens.accentText,
          disabledForegroundColor: VynicFloorTokens.textFaint,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: VynicFloorTokens.textMuted,
          highlightColor: VynicFloorTokens.accentSoft,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VynicFloorTokens.panel,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        hintStyle: const TextStyle(
          color: VynicFloorTokens.textFaint,
          fontSize: 13.5,
        ),
        labelStyle: const TextStyle(
          color: VynicFloorTokens.textMuted,
          fontSize: 13.5,
        ),
        floatingLabelStyle: const TextStyle(
          color: VynicFloorTokens.accentText,
          fontSize: 13.5,
        ),
        prefixIconColor: VynicFloorTokens.textFaint,
        suffixIconColor: VynicFloorTokens.textFaint,
        border: border(VynicFloorTokens.panelBorder),
        enabledBorder: border(VynicFloorTokens.panelBorder),
        focusedBorder: border(VynicFloorTokens.accentStrong, 1.4),
        errorBorder: border(VynicFloorTokens.dangerBorder),
        focusedErrorBorder: border(VynicFloorTokens.dangerText, 1.4),
        disabledBorder: border(VynicFloorTokens.divider),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(
            VynicFloorTokens.panel,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: const BorderSide(color: VynicFloorTokens.panelBorder),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: VynicFloorTokens.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: VynicFloorTokens.panelBorder),
        ),
        textStyle: const TextStyle(
          color: VynicFloorTokens.text,
          fontSize: 13.5,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? VynicFloorTokens.panel
              : VynicFloorTokens.panel,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? VynicFloorTokens.accentStrong
              : VynicFloorTokens.badgeFill,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? VynicFloorTokens.accentStrong
              : VynicFloorTokens.panelBorder,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? VynicFloorTokens.accentStrong
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(VynicFloorTokens.panel),
        side: const BorderSide(color: VynicFloorTokens.tileBorderHover),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? VynicFloorTokens.accentStrong
              : VynicFloorTokens.tileBorderHover,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: VynicFloorTokens.accentStrong,
        linearTrackColor: VynicFloorTokens.badgeFill,
        circularTrackColor: VynicFloorTokens.badgeFill,
      ),
      cardTheme: CardThemeData(
        color: VynicFloorTokens.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
          side: const BorderSide(color: VynicFloorTokens.panelBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: VynicFloorTokens.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        titleTextStyle: const TextStyle(
          color: VynicFloorTokens.text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: const TextStyle(
          color: VynicFloorTokens.textMuted,
          fontSize: 13.5,
          height: 1.4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
          side: const BorderSide(color: VynicFloorTokens.panelBorder),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: VynicFloorTokens.textMuted,
        textColor: VynicFloorTokens.text,
        selectedColor: VynicFloorTokens.accentText,
        selectedTileColor: VynicFloorTokens.accentSoft,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: VynicFloorTokens.panel,
        collapsedBackgroundColor: VynicFloorTokens.panel,
        iconColor: VynicFloorTokens.accentText,
        collapsedIconColor: VynicFloorTokens.textMuted,
        textColor: VynicFloorTokens.text,
        collapsedTextColor: VynicFloorTokens.text,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: VynicFloorTokens.badgeFill,
        selectedColor: VynicFloorTokens.accentSoft,
        side: const BorderSide(color: VynicFloorTokens.panelBorder),
        labelStyle: const TextStyle(
          color: VynicFloorTokens.text,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VynicFloorTokens.badgeRadius),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: VynicFloorTokens.text,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          color: VynicFloorTokens.panel,
          fontSize: 12,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VynicFloorTokens.text,
        contentTextStyle: const TextStyle(
          color: VynicFloorTokens.panel,
          fontSize: 13.5,
        ),
        actionTextColor: VynicFloorTokens.reservedDot,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// The gutter every admin section sits in.
///
/// Sections each used to pick their own — 16, 22, 24, 28 — so switching tabs
/// nudged the content sideways by up to twelve points. One number means the
/// panels line up across the whole panel.
EdgeInsets adminSectionPadding({
  required bool isMobile,
  double bottom = 18,
}) {
  final side = isMobile ? 16.0 : 22.0;
  return EdgeInsets.fromLTRB(side, isMobile ? 16 : 18, side, bottom);
}

/// How wide a section's content is allowed to get.
///
/// A few sections capped themselves at 1080 or 1100 and centred what was left,
/// which is why Settings sat visibly further in than Staff. The cap is one
/// number now, and it is set high enough to be inert at every resolution a POS
/// terminal actually runs at — at 1280 through 1600 the content column is
/// narrower than this, so nothing is capped and every tab lines up. It only
/// engages on a very wide screen, where an unbounded settings row would
/// otherwise stretch a label and its switch a metre apart.
const double adminSectionMaxWidth = 1400;

/// A small labelled tag: status, count, role.
///
/// This is [PosStatusPill] without the dot, for the many places in the admin
/// that need a tag but not a live-status indicator.
class AdminTag extends StatelessWidget {
  const AdminTag({
    super.key,
    required this.label,
    this.tone = AdminTones.neutral,
    this.icon,
  });

  final String label;
  final AdminTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(VynicFloorTokens.badgeRadius),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone.text),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The header strip above a list: column names, in the section-label style.
class AdminTableHeaderRow extends StatelessWidget {
  const AdminTableHeaderRow({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: const BoxDecoration(
        color: VynicFloorTokens.metricFill,
        border: Border(bottom: BorderSide(color: VynicFloorTokens.panelBorder)),
      ),
      child: Row(children: children),
    );
  }
}
