import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'package:vynic/core/ui/vynic_text_styles.dart';

/// A title + optional subtitle + optional trailing action row.
///
/// Collapses the trailing action below the title when the available width is
/// tight, so a long Georgian title plus an action button never overflow.
class VynicSectionHeader extends StatelessWidget {
  const VynicSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.action,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: VynicColors.accentSoft,
              borderRadius: VynicRadius.smAll,
            ),
            child: Icon(icon, color: VynicColors.accent, size: 20),
          ),
          const SizedBox(width: VynicSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: VynicTextStyles.heading,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: VynicTextStyles.label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (action == null) return titleBlock;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this width, stack the action under the title rather than
        // squeezing both onto one line (Georgian labels + a button overflow).
        final stack = constraints.maxWidth < 520;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: VynicSpacing.sm),
              Align(alignment: Alignment.centerLeft, child: action!),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: VynicSpacing.md),
            action!,
          ],
        );
      },
    );
  }
}
