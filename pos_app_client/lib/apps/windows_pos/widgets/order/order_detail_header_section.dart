import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/order_detail_common_helpers.dart';

/// Top bar of the order detail screen: table name, status pills, the current
/// date/time and a metadata chip row (zone, waiter, guests, order number and
/// open time).
class OrderDetailHeaderSection extends StatelessWidget {
  const OrderDetailHeaderSection({
    super.key,
    required this.order,
    required this.isTakeAwayOrder,
    required this.onBack,
    this.guestCount,
  });

  final Order order;
  final bool isTakeAwayOrder;
  final VoidCallback onBack;
  final int? guestCount;

  @override
  Widget build(BuildContext context) {
    final tableLabel = isTakeAwayOrder
        ? 'გასატანი #${order.orderId}'
        : OrderDetailCommonHelpers.compactTableLabel(order);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AdminDesign.panel,
        border: Border(bottom: BorderSide(color: AdminDesign.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BackButton(onTap: onBack),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tableLabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _DateTimeLabel(dateTime: DateTime.now()),
            ],
          ),
          const SizedBox(height: 12),
          _MetaChipRow(
            order: order,
            isTakeAwayOrder: isTakeAwayOrder,
            guestCount: guestCount,
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminDesign.panelSoft,
      borderRadius: BorderRadius.circular(AdminDesign.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminDesign.radius),
            border: Border.all(color: AdminDesign.border),
          ),
          child: const Icon(
            Icons.arrow_back,
            size: 20,
            color: AdminDesign.text,
          ),
        ),
      ),
    );
  }
}

class _DateTimeLabel extends StatelessWidget {
  const _DateTimeLabel({required this.dateTime});

  final DateTime dateTime;

  static const List<String> _months = [
    'იანვარი',
    'თებერვალი',
    'მარტი',
    'აპრილი',
    'მაისი',
    'ივნისი',
    'ივლისი',
    'აგვისტო',
    'სექტემბერი',
    'ოქტომბერი',
    'ნოემბერი',
    'დეკემბერი',
  ];

  String get _dateText {
    final month = _months[dateTime.month - 1];
    return '${dateTime.day} $month, ${dateTime.year}';
  }

  String get _timeText {
    final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _dateText,
          style: const TextStyle(
            color: AdminDesign.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _timeText,
          style: const TextStyle(
            color: AdminDesign.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.calendar_today_outlined,
          size: 15,
          color: AdminDesign.muted,
        ),
      ],
    );
  }
}

class _MetaChipRow extends StatelessWidget {
  const _MetaChipRow({
    required this.order,
    required this.isTakeAwayOrder,
    required this.guestCount,
  });

  final Order order;
  final bool isTakeAwayOrder;
  final int? guestCount;

  String _formatTime(DateTime dateTime) {
    final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _MetaChip(
        icon: Icons.place_outlined,
        label: 'ზონა',
        value: OrderDetailCommonHelpers.zoneLabel(order.floor),
      ),
      _MetaChip(
        icon: Icons.person_outline,
        label: 'შექმნა',
        value: DatabaseService.getDisplayOperatorName(order.createdBy),
      ),
      if (!isTakeAwayOrder && guestCount != null && guestCount! > 0)
        _MetaChip(
          icon: Icons.groups_outlined,
          label: 'სტუმრები',
          value: '$guestCount',
        ),
      _MetaChip(
        icon: Icons.receipt_long_outlined,
        label: 'შეკვეთა',
        value: '#${OrderDetailCommonHelpers.formattedOrderNumber(order)}',
      ),
      _MetaChip(
        icon: Icons.schedule_outlined,
        label: 'გახსნის დრო',
        value: _formatTime(order.createdAt),
      ),
    ];

    return Wrap(
      spacing: 0,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < chips.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: AdminDesign.border,
            ),
          chips[i],
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AdminDesign.muted),
        const SizedBox(width: 7),
        Text(
          '$label: ',
          style: const TextStyle(color: AdminDesign.muted, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AdminDesign.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
