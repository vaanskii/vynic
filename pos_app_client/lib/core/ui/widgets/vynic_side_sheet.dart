import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_motion.dart';
import 'package:vynic/core/ui/vynic_responsive.dart';
import 'package:vynic/core/ui/vynic_shadows.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'package:vynic/core/ui/vynic_text_styles.dart';
import 'package:vynic/core/ui/vynic_touch_targets.dart';

/// A right-anchored side sheet shell — the preferred surface (over stacked
/// dialogs) for non-blocking flows like variant+qty, discount entry, notes
/// (docs/UI_PLAN.md §6.4).
///
/// Phase 2 ships the shell only; wiring real flows into it happens per phase.
/// Width follows the panel rules ([VynicResponsive.panelWidth]) so it stays
/// usable on compact terminals and doesn't sprawl on wide ones. Open it with
/// [show], which uses a fast slide consistent with the motion tokens.
class VynicSideSheet extends StatelessWidget {
  const VynicSideSheet({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.footer,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final Widget? footer;

  /// Slide a side sheet in from the right as a modal route.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required WidgetBuilder builder,
    Widget? footer,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: VynicMotion.normal,
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerRight,
        child: VynicSideSheet(
          title: title,
          footer: footer,
          onClose: () => Navigator.of(ctx).pop(),
          child: Builder(builder: builder),
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = VynicResponsive.panelWidth(screen.width);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: screen.height,
        decoration: const BoxDecoration(
          color: VynicColors.card,
          boxShadow: VynicShadows.overlay,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const Divider(height: 1, color: VynicColors.border),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(VynicSpacing.md),
                  child: child,
                ),
              ),
              if (footer != null) ...[
                const Divider(height: 1, color: VynicColors.border),
                Padding(
                  padding: const EdgeInsets.all(VynicSpacing.md),
                  child: footer!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VynicSpacing.md,
        VynicSpacing.sm,
        VynicSpacing.xs,
        VynicSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: VynicTextStyles.heading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              iconSize: 20,
              constraints: const BoxConstraints(
                minWidth: VynicTouchTargets.minPos,
                minHeight: VynicTouchTargets.minPos,
              ),
              icon: const Icon(Icons.close, color: VynicColors.textMuted),
            ),
        ],
      ),
    );
  }
}
