import 'package:flutter/widgets.dart';
import 'package:vynic/core/ui/vynic_colors.dart';

/// The five visual tones a status can carry.
enum VynicStatusTone { neutral, info, success, warning, danger }

/// A resolved status token: the colors needed to render a chip/badge
/// consistently.
///
/// [foreground] is the full-strength hue for dots/icons/large fills.
/// [text] is the WCAG-AA-compliant shade for small chip text on [background]
/// (identical to [foreground] for tones that already pass; darker for
/// success/warning/neutral). [background]/[border] are the 12%-tint fill and
/// outline.
@immutable
class VynicStatusToken {
  const VynicStatusToken({
    required this.tone,
    required this.foreground,
    required this.text,
    required this.background,
    required this.border,
  });

  final VynicStatusTone tone;
  final Color foreground;
  final Color text;
  final Color background;
  final Color border;
}

/// The operational states from docs/UI_PLAN.md §3, as a UI-layer enum.
///
/// This is deliberately a *presentation* enum — it maps 1:1 to the §3 table so
/// a widget can pick a token by state name. It does NOT replace the domain
/// status enums (`OrderStatus`, `ReservationStatus`, `TableOperationalStatus`,
/// `BackendConnectionState`); a future phase's widget derives the right
/// [VynicOperationalState] from those and then asks for its token. Keeping the
/// list complete is enforced by `test/unit/vynic_tokens_test.dart`.
enum VynicOperationalState {
  free,
  occupied,
  reserved,
  reservedSoon,
  seatedLate,
  dirty,
  unpaid,
  printed,
  sentToKitchen,
  kitchenFailed,
  syncFailed,
  printerFailed,
  managerApprovalNeeded,
  offline,
  stale,
  blocked,
}

/// Resolves tones and operational states to concrete color tokens.
abstract final class VynicStatusTokens {
  /// The token for a bare tone.
  static VynicStatusToken ofTone(VynicStatusTone tone) {
    switch (tone) {
      case VynicStatusTone.neutral:
        return const VynicStatusToken(
          tone: VynicStatusTone.neutral,
          foreground: VynicColors.neutral,
          text: VynicColors.neutralText,
          background: VynicColors.neutralSoft,
          border: VynicColors.neutralBorder,
        );
      case VynicStatusTone.info:
        return const VynicStatusToken(
          tone: VynicStatusTone.info,
          foreground: VynicColors.info,
          text: VynicColors.info,
          background: VynicColors.infoSoft,
          border: VynicColors.infoBorder,
        );
      case VynicStatusTone.success:
        return const VynicStatusToken(
          tone: VynicStatusTone.success,
          foreground: VynicColors.success,
          text: VynicColors.successText,
          background: VynicColors.successSoft,
          border: VynicColors.successBorder,
        );
      case VynicStatusTone.warning:
        return const VynicStatusToken(
          tone: VynicStatusTone.warning,
          foreground: VynicColors.warning,
          text: VynicColors.warningText,
          background: VynicColors.warningSoft,
          border: VynicColors.warningBorder,
        );
      case VynicStatusTone.danger:
        return const VynicStatusToken(
          tone: VynicStatusTone.danger,
          foreground: VynicColors.danger,
          text: VynicColors.dangerText,
          background: VynicColors.dangerSoft,
          border: VynicColors.dangerBorder,
        );
    }
  }

  /// The tone assigned to each §3 operational state.
  ///
  /// Matches the "Token" and "Severity" columns of the §3 table. Note several
  /// states intentionally share a tone (e.g. all failure states are danger) —
  /// per the §3 design rule, they are distinguished by icon/label at the
  /// widget level, never by color alone, so sharing a tone here is correct.
  static VynicStatusTone toneForState(VynicOperationalState state) {
    switch (state) {
      case VynicOperationalState.free:
      case VynicOperationalState.stale:
        return VynicStatusTone.neutral;
      case VynicOperationalState.printed:
        return VynicStatusTone.neutral;
      case VynicOperationalState.occupied:
      case VynicOperationalState.sentToKitchen:
        return VynicStatusTone.info;
      case VynicOperationalState.reserved:
      case VynicOperationalState.reservedSoon:
      case VynicOperationalState.dirty:
      case VynicOperationalState.managerApprovalNeeded:
      case VynicOperationalState.offline:
        return VynicStatusTone.warning;
      case VynicOperationalState.seatedLate:
      case VynicOperationalState.unpaid:
      case VynicOperationalState.kitchenFailed:
      case VynicOperationalState.syncFailed:
      case VynicOperationalState.printerFailed:
      case VynicOperationalState.blocked:
        return VynicStatusTone.danger;
    }
  }

  /// The full color token for an operational state.
  static VynicStatusToken ofState(VynicOperationalState state) =>
      ofTone(toneForState(state));
}
