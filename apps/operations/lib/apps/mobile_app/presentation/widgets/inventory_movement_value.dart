import 'package:flutter/material.dart';
import 'package:vynic/core/models/receiving.dart';

/// The movement's frozen value, never today's recipe price or realized COGS.
class InventoryMovementValue extends StatelessWidget {
  const InventoryMovementValue({super.key, required this.movement});
  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final origin = movement.valueOrigin == 'FROZEN_ORIGINAL_REVERSAL'
        ? 'აღდგენა საწყისი ჩანაწერის ღირებულებით'
        : movement.valuationStatus == 'RECONSTRUCTED'
        ? 'ისტორიიდან აღდგენილი შეფასება'
        : 'სერვერზე მიღებისას გაყინული შეფასება';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            movement.inventoryValueDelta == null
                ? 'გაყინული ღირებულება ხელმისაწვდომი არ არის'
                : 'მარაგის ღირებულების ცვლილება: ${movement.inventoryValueDelta} ₾',
          ),
          if (movement.valuationStatus != null) ...[
            Text(origin, style: Theme.of(context).textTheme.bodySmall),
            if (movement.valueOrigin == 'FROZEN_ORIGINAL_REVERSAL' &&
                movement.valuationStatus == 'RECONSTRUCTED')
              const Text('საწყისი ღირებულება ისტორიიდან აღდგენილი შეფასებაა'),
            if (movement.valuationStatus == 'PROVISIONAL')
              const Text(
                'წინასწარი შეფასება — ღირებულების საფუძველი არასრულია',
              ),
            Text(
              'სამუშაო დღე: ${movement.businessDate} · მიღებულია: ${movement.createdAt.toUtc().toIso8601String()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
