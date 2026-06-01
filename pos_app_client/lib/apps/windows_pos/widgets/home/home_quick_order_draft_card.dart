import 'package:flutter/material.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/services/database_service.dart';

class HomeQuickOrderDraftCard extends StatelessWidget {
  const HomeQuickOrderDraftCard({
    super.key,
    required this.draft,
    required this.onToggleServiceFee,
    required this.onOpenServiceFeeConfig,
    required this.onContinue,
    required this.onPrint,
    required this.canManage,
    required this.onOpenManage,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
  });

  final QuickOrderDraft draft;
  final VoidCallback onToggleServiceFee;
  final VoidCallback onOpenServiceFeeConfig;
  final VoidCallback onContinue;
  final VoidCallback onPrint;
  final bool canManage;
  final VoidCallback onOpenManage;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;

  @override
  Widget build(BuildContext context) {
    final serviceFeeGloballyEnabled = DatabaseService.isServiceFeeAvailable();
    final serviceFeeActive =
        serviceFeeGloballyEnabled && draft.includeServiceFee;
    final serviceFeeText = serviceFeeActive
        ? 'სერვისის საფასური: ₾${draft.serviceFeeAmount.toStringAsFixed(2)}'
        : 'სერვისის საფასურის გარეშე';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.receipt_long, color: primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₾${draft.total.toStringAsFixed(2)} • ${_getTotalQuantity(draft)} ცალი',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (draft.displayName != null && draft.displayName!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'სახელი: ${draft.displayName}',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${_formatTimestamp(draft.createdAt)} • ${DatabaseService.getDisplayOperatorName(draft.createdBy)}',
                  style: TextStyle(color: mutedText, fontSize: 12),
                ),
                const SizedBox(height: 4),
                if (serviceFeeGloballyEnabled)
                  Row(
                    children: [
                      Icon(
                        Icons.miscellaneous_services,
                        color: serviceFeeActive ? secondaryColor : mutedText,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        serviceFeeText,
                        style: TextStyle(
                          color: serviceFeeActive ? secondaryColor : mutedText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              runAlignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (serviceFeeGloballyEnabled)
                  OutlinedButton.icon(
                    onPressed: onToggleServiceFee,
                    onLongPress: onOpenServiceFeeConfig,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: secondaryColor,
                      side: BorderSide(
                        color: secondaryColor.withValues(alpha: 0.2),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      serviceFeeActive ? Icons.toggle_off : Icons.toggle_on,
                      size: 18,
                    ),
                    label: Text(
                      serviceFeeActive
                          ? 'სერვისის გამორთვა'
                          : 'სერვისის ჩართვა',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: onContinue,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(
                      color: primaryColor.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('გაგრძელება'),
                ),
                OutlinedButton.icon(
                  onPressed: onPrint,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(
                      color: primaryColor.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('ბეჭდვა'),
                ),
                if (canManage)
                  OutlinedButton.icon(
                    onPressed: onOpenManage,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF7C3AED),
                      side: const BorderSide(color: Color(0xFFDDD6FE)),
                      backgroundColor: const Color(0xFFF5F3FF),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('მართვა'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _getTotalQuantity(QuickOrderDraft draft) {
    return draft.items.fold<int>(0, (sum, item) => sum + item.quantity);
  }

  String _formatTimestamp(DateTime timestamp) {
    final datePart =
        '${timestamp.year.toString().padLeft(4, '0')}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    final timePart =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    return '$datePart $timePart';
  }
}
