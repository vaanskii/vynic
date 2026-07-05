import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_responsive.dart';
import 'package:vynic/core/ui/vynic_shadows.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';

/// An overflow-safe dialog shell.
///
/// Width is capped by [VynicResponsive.dialogWidth] — it never exceeds
/// `maxDialogWidth` (560) and always leaves a margin so it can't overflow a
/// 1280×720 (or smaller-after-scaling) viewport. Height is capped to 90% of
/// the screen and the body scrolls, so a tall form can't overflow vertically
/// under 150% scaling.
///
/// Reserve this for true interruptions (confirmations, PIN entry). For
/// non-blocking flows (variant+qty, discount, notes) prefer a side sheet —
/// see [VynicSideSheet].
class VynicResponsiveDialog extends StatelessWidget {
  const VynicResponsiveDialog({
    super.key,
    required this.child,
    this.preferredWidth,
  });

  final Widget child;

  /// Desired width; still clamped to the responsive cap.
  final double? preferredWidth;

  @override
  Widget build(BuildContext context) {
    final width = VynicResponsive.dialogWidth(
      context,
      preferred: preferredWidth,
    );
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(VynicSpacing.md),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: VynicColors.card,
            borderRadius: VynicRadius.lgAll,
            border: Border.all(color: VynicColors.border),
            boxShadow: VynicShadows.overlay,
          ),
          child: ClipRRect(
            borderRadius: VynicRadius.lgAll,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }
}
