import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';

/// The reservation strip above the order.
///
/// A table either has a booking against it or it doesn't, and that is a
/// one-line fact — so it reads as a single band rather than the old tall side
/// panel. With a booking it lays the guest's details out inline; without one
/// it says so plainly and offers to attach one.
class OrderDetailReservationPanel extends StatelessWidget {
  const OrderDetailReservationPanel({
    super.key,
    required this.isTakeAwayOrder,
    required this.hasReservation,
    this.customerName,
    this.customerPhone,
    this.scheduleLabel,
    this.notes,
    this.onEditReservation,
    this.onAddReservation,
  });

  final bool isTakeAwayOrder;
  final bool hasReservation;
  final String? customerName;
  final String? customerPhone;
  final String? scheduleLabel;
  final String? notes;
  final VoidCallback? onEditReservation;
  final VoidCallback? onAddReservation;

  String get _title => isTakeAwayOrder ? 'გატანა' : 'RESERVATION';

  @override
  Widget build(BuildContext context) {
    final trimmedNotes = notes?.trim();
    final facts = <String>[
      if (customerName != null && customerName!.trim().isNotEmpty)
        customerName!.trim(),
      if (customerPhone != null && customerPhone!.trim().isNotEmpty)
        customerPhone!.trim(),
      if (scheduleLabel != null && scheduleLabel!.trim().isNotEmpty)
        scheduleLabel!.trim(),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: BoxDecoration(
        color: VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                PosSectionLabel(_title),
                const SizedBox(height: 6),
                if (!hasReservation)
                  const Text(
                    'ამ მაგიდაზე რეზერვაცია არ არის',
                    style: TextStyle(
                      color: VynicFloorTokens.text,
                      fontSize: 14.5,
                    ),
                  )
                else
                  Text(
                    facts.isEmpty ? 'რეზერვაცია' : facts.join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VynicFloorTokens.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (trimmedNotes != null && trimmedNotes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.sticky_note_2_outlined,
                        size: 14,
                        color: VynicFloorTokens.occupiedMeta,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          trimmedNotes,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VynicFloorTokens.occupiedMeta,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (hasReservation && onEditReservation != null) ...[
            const SizedBox(width: 16),
            PosActionButton(
              label: 'დეტალების შეცვლა',
              onTap: onEditReservation,
            ),
          ] else if (!hasReservation && onAddReservation != null) ...[
            const SizedBox(width: 16),
            PosActionButton(
              label: 'რეზერვაციის დამატება',
              onTap: onAddReservation,
            ),
          ],
        ],
      ),
    );
  }
}
