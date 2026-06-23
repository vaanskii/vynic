import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/order_detail_common_helpers.dart';

/// A single label/value row in a side panel.
class OrderDetailKeyValue {
  const OrderDetailKeyValue({
    required this.label,
    this.value,
    this.valueWidget,
    this.valueColor = AdminDesign.text,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final Color valueColor;
}

/// Left column panel of the order detail screen. Shows reservation details
/// when available (phone, guests, time, table, notes) and falls back to basic
/// order details for walk-in/dine-in orders without a linked reservation.
class OrderDetailDetailsPanel extends StatelessWidget {
  const OrderDetailDetailsPanel({
    super.key,
    required this.order,
    required this.isTakeAwayOrder,
    required this.hasReservation,
    this.customerName,
    this.customerPhone,
    this.scheduleLabel,
    this.guestCount,
    this.notes,
    this.onEditReservation,
    this.onGuestsChanged,
  });

  final Order order;
  final bool isTakeAwayOrder;
  final bool hasReservation;
  final String? customerName;
  final String? customerPhone;
  final String? scheduleLabel;
  final int? guestCount;
  final String? notes;
  final VoidCallback? onEditReservation;
  final ValueChanged<int>? onGuestsChanged;

  String get _title {
    if (isTakeAwayOrder) return 'გატანის დეტალები';
    return hasReservation ? 'რეზერვაციის დეტალები' : 'მაგიდის დეტალები';
  }

  IconData get _titleIcon =>
      isTakeAwayOrder ? Icons.takeout_dining_outlined : Icons.event_note;

  @override
  Widget build(BuildContext context) {
    final rows = <OrderDetailKeyValue>[];

    if (customerName != null) {
      rows.add(OrderDetailKeyValue(label: 'სახელი', value: customerName));
    }
    if (customerPhone != null) {
      rows.add(OrderDetailKeyValue(label: 'ტელეფონი', value: customerPhone));
    }
    if (!isTakeAwayOrder && guestCount != null) {
      rows.add(
        OrderDetailKeyValue(
          label: 'სტუმრები',
          valueWidget: onGuestsChanged == null
              ? Text(
                  '$guestCount',
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : _GuestStepper(
                  value: guestCount!,
                  onChanged: onGuestsChanged!,
                ),
        ),
      );
    }
    if (scheduleLabel != null) {
      rows.add(
        OrderDetailKeyValue(
          label: isTakeAwayOrder ? 'გატანის დრო' : 'დრო',
          value: scheduleLabel,
        ),
      );
    }
    if (!isTakeAwayOrder) {
      rows.add(
        OrderDetailKeyValue(
          label: 'მაგიდა',
          value: order.tableNumbers.join(', '),
        ),
      );
      rows.add(
        OrderDetailKeyValue(
          label: 'ზონა',
          value: OrderDetailCommonHelpers.zoneLabel(order.floor),
        ),
      );
    }
    rows.add(
      OrderDetailKeyValue(
        label: 'ოპერატორი',
        value: DatabaseService.getDisplayOperatorName(order.createdBy),
      ),
    );

    final trimmedNotes = notes?.trim();

    return Container(
      width: double.infinity,
      decoration: AdminDesign.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Icon(_titleIcon, size: 18, color: AdminDesign.accentDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _title,
                    style: const TextStyle(
                      color: AdminDesign.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminDesign.border),
          for (int i = 0; i < rows.length; i++)
            _KeyValueRow(row: rows[i], shaded: i.isOdd),
          if (trimmedNotes != null && trimmedNotes.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(AdminDesign.radius),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.sticky_note_2_outlined,
                    size: 16,
                    color: AdminDesign.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trimmedNotes,
                      style: const TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (onEditReservation != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onEditReservation,
                  style: AdminDesign.outlineButtonStyle(),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('დეტალების შეცვლა'),
                ),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.row, required this.shaded});

  final OrderDetailKeyValue row;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: shaded ? AdminDesign.panelSoft : AdminDesign.panel,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              style: const TextStyle(color: AdminDesign.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          row.valueWidget ??
              Text(
                row.value ?? '—',
                style: TextStyle(
                  color: row.valueColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
        ],
      ),
    );
  }
}

class _GuestStepper extends StatelessWidget {
  const _GuestStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminDesign.panel,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: AdminDesign.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove,
            onTap: value > 1 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminDesign.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AdminDesign.radius),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AdminDesign.accentDark : AdminDesign.border,
        ),
      ),
    );
  }
}
