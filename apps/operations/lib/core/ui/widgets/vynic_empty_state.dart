import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'package:vynic/core/ui/vynic_text_styles.dart';

/// A centered "nothing here yet" placeholder: icon, title, message, optional
/// action. Content is centered and width-constrained so it reads well in both
/// a narrow side panel and a wide content area.
class VynicEmptyState extends StatelessWidget {
  const VynicEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(VynicSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: VynicColors.cardSoft,
                  borderRadius: VynicRadius.smAll,
                  border: Border.all(color: VynicColors.border),
                ),
                child: Icon(icon, color: VynicColors.textMuted),
              ),
              const SizedBox(height: VynicSpacing.sm),
              Text(
                title,
                textAlign: TextAlign.center,
                style: VynicTextStyles.bodyStrong,
              ),
              if (message != null) ...[
                const SizedBox(height: VynicSpacing.xxs),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: VynicTextStyles.label,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: VynicSpacing.md),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
