import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';

class HomeReservationMenuPreview {
  const HomeReservationMenuPreview._();

  static Future<void> show({
    required BuildContext context,
    required Reservation reservation,
    required Color primaryColor,
    required Color textPrimary,
    required Color mutedText,
  }) async {
    final items = List<OrderItem>.from(reservation.preOrderItems ?? const []);
    final totalQuantity = items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final totalAmount = items.fold<double>(0, (sum, item) => sum + item.total);
    final reservationDateLabel = DatabaseService.getGeorgianFormattedDate(
      reservation.reservationDate,
    );
    await showPosModal<void>(
      context: context,
      builder: (context) => PosFormDialog(
        width: 680,
        title: reservation.customerName.trim().isEmpty
            ? 'რეზერვაციის მენიუ'
            : reservation.customerName.trim(),
        subtitle:
            '$reservationDateLabel · ${reservation.reservationTime} · ${reservation.numberOfGuests} სტუმარი',
        onClose: () => Navigator.of(context).pop(),
        actions: [
          Text('ერთეულის რაოდენობა: $totalQuantity'),
          Text(
            'ჯამი: ₾${totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('დახურვა'),
          ),
        ],
        child: items.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text('ამ რეზერვაციას არ აქვს დამატებული მენიუ.'),
              )
            : Column(
                children: [
                  for (final item in items)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: VynicFloorTokens.panelBorder,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.itemName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${item.quantity}x · ₾${item.unitPrice.toStringAsFixed(2)} ერთეული',
                                  style: const TextStyle(
                                    color: VynicFloorTokens.textMuted,
                                  ),
                                ),
                                if (item.comment?.trim().isNotEmpty ??
                                    false) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'შენიშვნა: ${item.comment!.trim()}',
                                    style: const TextStyle(
                                      color: VynicFloorTokens.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '₾${item.total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
