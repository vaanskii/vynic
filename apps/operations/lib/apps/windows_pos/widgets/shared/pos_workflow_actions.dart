import 'package:flutter/material.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/widgets/pos_text.dart';

/// 56 logical pixels remain a 48px target on the 1024-wide POS surface.
ButtonStyle posWorkflowButtonStyle(
  BuildContext context, {
  bool primary = false,
  bool danger = false,
}) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(PosTheme.controlSize),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  ),
  textStyle: WidgetStatePropertyAll(
    Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
  ),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  backgroundColor: primary
      ? const WidgetStatePropertyAll(VynicFloorTokens.accentStrong)
      : null,
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? VynicFloorTokens.textFaint
        : primary
        ? Colors.white
        : danger
        ? VynicFloorTokens.dangerText
        : VynicFloorTokens.accentStrong,
  ),
);

class PosWorkflowButton extends StatelessWidget {
  const PosWorkflowButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  @override
  Widget build(BuildContext context) => primary
      ? FilledButton.icon(
          onPressed: onPressed,
          style: posWorkflowButtonStyle(context, primary: true),
          icon: Icon(icon, size: 22),
          label: PosText(label),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          style: posWorkflowButtonStyle(context, danger: danger),
          icon: Icon(icon, size: 22),
          label: PosText(label),
        );
}

class PosWorkflowIconButton extends StatelessWidget {
  const PosWorkflowIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    style: posWorkflowButtonStyle(context, danger: danger),
    icon: Icon(icon, size: 24),
  );
}
