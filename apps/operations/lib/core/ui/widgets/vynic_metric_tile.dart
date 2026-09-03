import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'package:vynic/core/ui/vynic_text_styles.dart';
import 'package:vynic/core/ui/vynic_touch_targets.dart';
import 'package:vynic/core/ui/widgets/vynic_card.dart';

/// A compact KPI tile: label on top, large value, optional icon + trailing.
///
/// For manager dashboards / landing metrics (§7-H). Value and label both
/// ellipsize so long Georgian text never overflows the tile.
class VynicMetricTile extends StatelessWidget {
  const VynicMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent = VynicColors.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return VynicCard(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: VynicTouchTargets.minPos),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: VynicSpacing.xs),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: VynicTextStyles.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: VynicSpacing.xs),
            Text(
              value,
              style: VynicTextStyles.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
