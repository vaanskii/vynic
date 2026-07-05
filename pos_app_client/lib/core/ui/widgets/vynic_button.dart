import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'package:vynic/core/ui/vynic_touch_targets.dart';

/// Visual weight of a [VynicButton].
enum VynicButtonVariant { primary, secondary, danger }

/// The standard Vynic action button.
///
/// Enforces the 44px POS touch-target floor by default and the token palette.
/// Additive: no screen uses it yet. Label uses [Text] with ellipsis so a long
/// Georgian string can't overflow the button — it truncates instead.
class VynicButton extends StatelessWidget {
  const VynicButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = VynicButtonVariant.primary,
    this.expand = false,
    this.minHeight = VynicTouchTargets.minPos,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final VynicButtonVariant variant;

  /// When true, stretches to the parent's width.
  final bool expand;

  /// Minimum tap height. Defaults to the POS floor; pass
  /// [VynicTouchTargets.minAdmin] on mouse-only admin surfaces.
  final double minHeight;

  bool get _isFilled => variant != VynicButtonVariant.secondary;

  Color get _fill {
    switch (variant) {
      case VynicButtonVariant.primary:
        return VynicColors.accent;
      case VynicButtonVariant.danger:
        return VynicColors.danger;
      case VynicButtonVariant.secondary:
        return VynicColors.card;
    }
  }

  Color get _foreground {
    switch (variant) {
      case VynicButtonVariant.primary:
      case VynicButtonVariant.danger:
        return VynicColors.onAccent;
      case VynicButtonVariant.secondary:
        return VynicColors.textPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(expand ? double.infinity : 0, minHeight),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: VynicSpacing.md,
          vertical: VynicSpacing.sm,
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return VynicColors.border;
        return _fill;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return VynicColors.textDisabled;
        }
        return _foreground;
      }),
      elevation: const WidgetStatePropertyAll(0),
      side: _isFilled
          ? null
          : const WidgetStatePropertyAll(BorderSide(color: VynicColors.border)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: VynicRadius.smAll),
      ),
    );

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: VynicSpacing.xs),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );

    return _isFilled
        ? ElevatedButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}
