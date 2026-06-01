import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';

class OrderDetailHeaderSection extends StatelessWidget {
  const OrderDetailHeaderSection({
    super.key,
    required this.order,
    required this.statusColor,
    required this.showReservationDetails,
    required this.isReservationDetailsExpanded,
    required this.isTakeAwayOrder,
    required this.onToggleReservationDetails,
    this.reservationCustomerName,
    this.reservationCustomerPhone,
    this.reservationScheduleDescription,
    this.reservationGuestCountLabel,
    this.reservationNotesLabel,
    this.onEditReservationDetails,
  });

  final Order order;
  final Color statusColor;
  final bool showReservationDetails;
  final bool isReservationDetailsExpanded;
  final bool isTakeAwayOrder;
  final VoidCallback onToggleReservationDetails;
  final String? reservationCustomerName;
  final String? reservationCustomerPhone;
  final String? reservationScheduleDescription;
  final String? reservationGuestCountLabel;
  final String? reservationNotesLabel;
  final VoidCallback? onEditReservationDetails;

  static const Color _surfaceColor = Color(0xFFF5F7FB);
  static const Color _panelColor = Colors.white;
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _titleColor = Color(0xFF1E293B);
  static const Color _mutedTextColor = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _panelColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'შექმნილია: ${_formatDateTime(order.createdAt)}',
                      style: const TextStyle(
                        color: _mutedTextColor,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ოპერატორი: ${DatabaseService.getDisplayOperatorName(order.createdBy)}',
                      style: const TextStyle(
                        color: _mutedTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    order.status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (showReservationDetails) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: onToggleReservationDetails,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                isTakeAwayOrder
                                    ? 'გატანის დეტალები'
                                    : 'რეზერვაციის დეტალები',
                                style: const TextStyle(
                                  color: _titleColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(
                              isReservationDetailsExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: _mutedTextColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isTakeAwayOrder && onEditReservationDetails != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: onEditReservationDetails,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _titleColor,
                              side: const BorderSide(color: _borderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(
                              Icons.edit_calendar_outlined,
                              size: 18,
                            ),
                            label: const Text('რეზერვაციის დეტალების შეცვლა'),
                          ),
                        ),
                      ),
                    if (isReservationDetailsExpanded) ...[
                      if (reservationCustomerName != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'სახელი: $reservationCustomerName',
                          style: const TextStyle(
                            color: _mutedTextColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (reservationCustomerPhone != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'ტელეფონი: $reservationCustomerPhone',
                          style: const TextStyle(
                            color: _mutedTextColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (reservationScheduleDescription != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          reservationScheduleDescription!,
                          style: const TextStyle(
                            color: _mutedTextColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (reservationGuestCountLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          reservationGuestCountLabel!,
                          style: const TextStyle(
                            color: _mutedTextColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (reservationNotesLabel != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          reservationNotesLabel!,
                          style: const TextStyle(
                            color: _mutedTextColor,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
