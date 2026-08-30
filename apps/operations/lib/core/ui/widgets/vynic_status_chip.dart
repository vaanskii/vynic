import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'package:vynic/core/ui/vynic_status_tokens.dart';

/// A pill status chip using the Vynic status tokens.
///
/// Per docs/UI_PLAN.md §3/§6.1 a status is NEVER conveyed by color alone: this
/// chip always renders a label, and callers are expected to pass an [icon] for
/// states that colorblind staff must distinguish. Text is 11px minimum, uses
/// full-strength foreground on a 12%-tint fill with a soft border.
class VynicStatusChip extends StatelessWidget {
  const VynicStatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  }) : _token = null;

  /// Build directly from an operational state (§3), picking the tone for you.
  VynicStatusChip.forState({
    super.key,
    required this.label,
    required VynicOperationalState state,
    this.icon,
  }) : tone = VynicStatusTokens.toneForState(state),
       _token = VynicStatusTokens.ofState(state);

  final String label;
  final VynicStatusTone tone;
  final IconData? icon;
  final VynicStatusToken? _token;

  @override
  Widget build(BuildContext context) {
    final token = _token ?? VynicStatusTokens.ofTone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VynicSpacing.xs,
        vertical: VynicSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: token.background,
        borderRadius: VynicRadius.pillAll,
        border: Border.all(color: token.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: token.text),
            const SizedBox(width: VynicSpacing.xxs + 1),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: token.text,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
