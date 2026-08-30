import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'package:vynic/core/ui/vynic_text_styles.dart';

/// A centered progress indicator with an optional message. Low-key, matching
/// the calm/operational direction — no full-screen spinners or animations
/// beyond the standard indicator.
class VynicLoadingState extends StatelessWidget {
  const VynicLoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(VynicColors.accent),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: VynicSpacing.sm),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: VynicTextStyles.label,
            ),
          ],
        ],
      ),
    );
  }
}
