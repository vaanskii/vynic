import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/order_detail_common_helpers.dart';

/// Top bar of the order detail screen.
///
/// One line, sitting on the page rather than in a panel: back to the floor,
/// the table's own name with its zone and seat count, the live status, and the
/// amount owed pinned to the right. Everything a waiter needs to confirm they
/// opened the right table, before any of the detail below.
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
    final title = isTakeAwayOrder
        ? 'გასატანი #${OrderDetailCommonHelpers.formattedOrderNumber(order)}'
        : OrderDetailCommonHelpers.tableTitle(order);

    final subtitle = _subtitle();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          _BackButton(onTap: onBack),
          const SizedBox(width: 18),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VynicFloorTokens.text,
                fontSize: 25,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VynicFloorTokens.textMuted,
                  fontSize: 14,
                ),
              ),
            ),
          ],
          const SizedBox(width: 16),
          OrderStatusPill(status: order.status),
          const Spacer(),
          // The amount owed is stated once, on the totals card in the rail.
          // Repeating it here gave the screen two competing headline figures
          // that had to be read against each other to be trusted.
        ],
      ),
    );
  }

  /// „სართული 1 · 4 ადგილი" — the zone's own name, and the seats only when the
  /// layout actually knows them.
  String? _subtitle() {
    if (isTakeAwayOrder) {
      return null;
    }
    final seats = OrderDetailCommonHelpers.seatCount(order);
    return [
      OrderDetailCommonHelpers.zoneName(order),
      if (seats != null) '$seats ადგილი',
    ].join(' · ');
  }
}

/// Status of the order as a dotted pill. Amber while the table is live, and
/// the neutral/danger tones once it is finalised.
class OrderStatusPill extends StatelessWidget {
  const OrderStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final finalized = OrderDetailCommonHelpers.isFinalizedStatus(status);
    final cancelled = status == 'cancelled';

    late final Color fill;
    late final Color borderColor;
    late final Color textColor;
    late final Color dot;
    if (cancelled) {
      fill = VynicFloorTokens.dangerFill;
      borderColor = VynicFloorTokens.dangerBorder;
      textColor = VynicFloorTokens.dangerText;
      dot = VynicFloorTokens.dangerText;
    } else if (finalized) {
      fill = VynicFloorTokens.badgeFill;
      borderColor = VynicFloorTokens.panelBorder;
      textColor = VynicFloorTokens.textMuted;
      dot = VynicFloorTokens.freeDot;
    } else {
      fill = VynicFloorTokens.statusPillFill;
      borderColor = VynicFloorTokens.statusPillBorder;
      textColor = VynicFloorTokens.statusPillText;
      dot = VynicFloorTokens.occupiedDot;
    }

    // An open table reads as „დაკავებული" to a waiter; the finer order states
    // (მზადდება, მზად არის) matter once it is finalised or being worked.
    final label = finalized || cancelled || status == 'pending'
        ? OrderDetailCommonHelpers.statusLabel(status)
        : 'დაკავებული';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The four figures a waiter is asked for at the table: who opened it, when,
/// how long it has been running and how many are sitting there.
class OrderDetailMetricsRow extends StatefulWidget {
  const OrderDetailMetricsRow({
    super.key,
    required this.order,
    required this.isTakeAwayOrder,
    this.guestCount,
    this.onGuestsChanged,
  });

  final Order order;
  final bool isTakeAwayOrder;
  final int? guestCount;

  /// Null when guests are not editable here (no linked reservation, or the
  /// order is finalised) — the card then just reads the number out.
  final ValueChanged<int>? onGuestsChanged;

  @override
  State<OrderDetailMetricsRow> createState() => _OrderDetailMetricsRowState();
}

class _OrderDetailMetricsRowState extends State<OrderDetailMetricsRow> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The elapsed card is the only thing on this screen that changes on its
    // own, so it drives its own second-by-second repaint rather than making
    // the whole screen rebuild.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _clock(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static String _elapsed(Duration value) {
    final seconds = value.inSeconds < 0 ? 0 : value.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final finalized = OrderDetailCommonHelpers.isFinalizedStatus(order.status);

    final cards = <Widget>[
      _MetricCard(
        label: 'ოფიციანტი',
        value: DatabaseService.getDisplayOperatorName(order.createdBy),
      ),
      _MetricCard(label: 'გახსნა', value: _clock(order.createdAt)),
      _MetricCard(
        label: 'ხანგრძლივობა',
        // A closed table's timer stops at the total it ran for, rather than
        // carrying on counting after the guests have left.
        //
        // Measured against the business clock, not the wall clock. Orders are
        // stamped with DatabaseService.getCurrentDateTime(), which carries the
        // *business* date with the current time of day — so on a venue whose
        // business day is not today, subtracting DateTime.now() reported the
        // gap between the two calendars (a table opened seconds ago showed as
        // 1368:08:05) instead of how long the guests had been sitting.
        value: _elapsed(
          (finalized
                  ? order.updatedAt ?? DatabaseService.getCurrentDateTime()
                  : DatabaseService.getCurrentDateTime())
              .difference(order.createdAt),
        ),
      ),
      if (!widget.isTakeAwayOrder && widget.guestCount != null)
        _MetricCard(
          label: 'სტუმარი',
          value: '${widget.guestCount}',
          onChanged: widget.onGuestsChanged,
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, this.onChanged});

  final String label;
  final String value;

  /// When set, the card carries a stepper instead of a plain readout.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final current = int.tryParse(value) ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(VynicFloorTokens.metricRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VynicFloorTokens.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 26,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: const TextStyle(
                          color: VynicFloorTokens.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                if (onChanged != null) ...[
                  _StepButton(
                    icon: Icons.remove,
                    onTap: current > 1 ? () => onChanged!(current - 1) : null,
                  ),
                  const SizedBox(width: 4),
                  _StepButton(
                    icon: Icons.add,
                    onTap: () => onChanged!(current + 1),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: VynicFloorTokens.metricFill,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 15,
            color: enabled
                ? VynicFloorTokens.accentText
                : VynicFloorTokens.freeDot,
          ),
        ),
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
      color: VynicFloorTokens.panel,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: VynicFloorTokens.panelBorder),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back,
                size: 16,
                color: VynicFloorTokens.textMuted,
              ),
              SizedBox(width: 8),
              Text(
                'მაგიდები',
                style: TextStyle(
                  color: VynicFloorTokens.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
