import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/services/database_service.dart';

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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: FractionallySizedBox(
              heightFactor: 0.68,
              alignment: Alignment.bottomCenter,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border.all(color: const Color(0xFFE1E5F2)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 24,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reservation.customerName.trim().isEmpty
                                      ? 'რეზერვაციის მენიუ'
                                      : reservation.customerName.trim(),
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _buildMenuMetaChip(
                                      icon: Icons.calendar_today_outlined,
                                      label: reservationDateLabel,
                                      primaryColor: primaryColor,
                                      textPrimary: textPrimary,
                                    ),
                                    _buildMenuMetaChip(
                                      icon: Icons.schedule_outlined,
                                      label: reservation.reservationTime,
                                      primaryColor: primaryColor,
                                      textPrimary: textPrimary,
                                    ),
                                    _buildMenuMetaChip(
                                      icon: Icons.people_outline,
                                      label:
                                          '${reservation.numberOfGuests} სტუმარი',
                                      primaryColor: primaryColor,
                                      textPrimary: textPrimary,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: Icon(Icons.close, color: mutedText),
                            tooltip: 'დახურვა',
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      color: Colors.black.withValues(alpha: 0.08),
                      height: 1,
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                              child: Text(
                                'ამ რეზერვაციას არ აქვს დამატებული მენიუ.',
                                style: TextStyle(
                                  color: mutedText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                16,
                              ),
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, index) {
                                final item = items[index];
                                return _buildMenuPreviewTile(
                                  item: item,
                                  primaryColor: primaryColor,
                                  textPrimary: textPrimary,
                                  mutedText: mutedText,
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FD),
                        border: Border(
                          top: BorderSide(
                            color: Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ერთეულის რაოდენობა: $totalQuantity',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'ჯამი: ₾${totalAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildMenuMetaChip({
    required IconData icon,
    required String label,
    required Color primaryColor,
    required Color textPrimary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildMenuPreviewTile({
    required OrderItem item,
    required Color primaryColor,
    required Color textPrimary,
    required Color mutedText,
  }) {
    final comment = item.comment?.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.itemName,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '₾${item.total.toStringAsFixed(2)}',
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${item.quantity}x',
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '₾${item.unitPrice.toStringAsFixed(2)} ერთეული',
                style: TextStyle(
                  color: mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'შენიშვნა: $comment',
              style: TextStyle(color: mutedText, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
