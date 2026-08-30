import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/pos/order_item_transfer.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

/// Picking what to move off an order, and where it should land.
///
/// Answers two questions on one screen — which items, and which order — because
/// they are one decision. Splitting them across two dialogs would mean choosing
/// a destination before you know how much is going there.
///
/// Returns the chosen destination and the per-line quantities, or null if the
/// operator backed out. It performs no writes: [OrderItemTransfer] does that,
/// so the money and this layout can be wrong independently of each other.
/// Where a move can land.
///
/// Not just „another open order": „we ordered to go and now we want to sit
/// down" is the case this feature exists for, and half the time the table they
/// want is still free. Opening it as part of the move is the difference between
/// the feature working and the operator having to go back to the floor screen,
/// open a table, and come back.
sealed class OrderMoveTarget {
  const OrderMoveTarget();
}

/// An order that is already open. The items merge into it.
final class ExistingOrderTarget extends OrderMoveTarget {
  const ExistingOrderTarget(this.order);
  final Order order;
}

/// A table with nothing on it. The caller opens an order there first.
final class FreeTableTarget extends OrderMoveTarget {
  const FreeTableTarget({required this.tableNumber, required this.floor});
  final String tableNumber;
  final String floor;
}

/// A take-away that does not exist yet. The caller creates it.
final class NewTakeAwayTarget extends OrderMoveTarget {
  const NewTakeAwayTarget();
}

/// One row in the „where" pane.
///
/// Labelled by the caller rather than the dialog: a take-away's customer name
/// lives on its linked reservation, not on the order, and this widget has no
/// business reading the database to find it.
class OrderMoveOption {
  const OrderMoveOption({
    required this.target,
    required this.label,
    required this.detail,
    this.isNew = false,
  });

  final OrderMoveTarget target;
  final String label;
  final String detail;

  /// Grouped under „ახალი" — something that will be created, not joined.
  final bool isNew;
}

/// Picking what to move off an order, and where it should land.
///
/// Answers two questions on one screen — which items, and which order — because
/// they are one decision. Splitting them across two dialogs would mean choosing
/// a destination before you know how much is going there.
///
/// It performs no writes: [OrderItemTransfer] moves the items and the caller
/// opens any new order, so the money and this layout can be wrong independently
/// of each other.
class OrderMoveItemsDialog extends StatefulWidget {
  const OrderMoveItemsDialog({
    super.key,
    required this.source,
    required this.sourceLabel,
    required this.options,
  });

  final Order source;

  /// What this order is called, in the caller's words.
  final String sourceLabel;

  /// Everywhere the items may go. The caller decides what is eligible.
  final List<OrderMoveOption> options;

  @override
  State<OrderMoveItemsDialog> createState() => _OrderMoveItemsDialogState();
}

/// What the operator settled on.
class OrderMoveRequest {
  const OrderMoveRequest({required this.option, required this.moves});

  final OrderMoveOption option;
  final List<OrderItemMove> moves;
}

class _OrderMoveItemsDialogState extends State<OrderMoveItemsDialog> {
  /// Line index -> how many of it to move. Absent means none.
  final Map<int, int> _quantities = {};
  OrderMoveOption? _destination;

  List<OrderItemMove> get _moves => [
    for (final entry in _quantities.entries)
      if (entry.value > 0) (index: entry.key, quantity: entry.value),
  ];

  int get _pickedCount =>
      _quantities.values.fold(0, (sum, quantity) => sum + quantity);

  double get _pickedAmount {
    var total = 0.0;
    for (final entry in _quantities.entries) {
      if (entry.value <= 0) continue;
      final line = widget.source.items[entry.key];
      total += line.total * entry.value / line.quantity;
    }
    return double.parse(total.toStringAsFixed(2));
  }

  /// Everything on the order is going. Worth saying before it happens rather
  /// than after: the table stays open, holding nothing.
  bool get _movingEverything {
    if (widget.source.items.isEmpty) return false;
    for (var i = 0; i < widget.source.items.length; i++) {
      if ((_quantities[i] ?? 0) != widget.source.items[i].quantity) {
        return false;
      }
    }
    return true;
  }

  /// The two orders disagree about service. Moving between them changes what
  /// is owed in total, which is legitimate but should not be a surprise.
  bool get _serviceFeeDiffers {
    final target = _destination?.target;
    if (target is! ExistingOrderTarget) return false;
    return target.order.includeServiceFee != widget.source.includeServiceFee;
  }

  void _setQuantity(int index, int quantity) {
    setState(() {
      final max = widget.source.items[index].quantity;
      final clamped = quantity.clamp(0, max);
      if (clamped == 0) {
        _quantities.remove(index);
      } else {
        _quantities[index] = clamped;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    // The POS is never laid out below 1200x720, but the dialog still sizes
    // itself from the box it is actually in rather than assuming it.
    final width = media.width.clamp(0.0, 880.0);
    final height = (media.height - 80).clamp(360.0, 640.0);
    final canMove = _destination != null && _moves.isNotEmpty;

    return Dialog(
      backgroundColor: VynicFloorTokens.panel,
      surfaceTintColor: VynicFloorTokens.panel,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _header(),
            const Divider(height: 1, color: VynicFloorTokens.panelBorder),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: _itemsPane()),
                  const VerticalDivider(
                    width: 1,
                    color: VynicFloorTokens.panelBorder,
                  ),
                  Expanded(flex: 4, child: _destinationPane()),
                ],
              ),
            ),
            const Divider(height: 1, color: VynicFloorTokens.panelBorder),
            _footer(canMove: canMove),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'პროდუქტების გადატანა',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: VynicFloorTokens.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                // Both ends of the move, on one line. Without this the dialog
                // showed where the items were coming from and never said, in
                // one place, where they were going.
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.sourceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VynicFloorTokens.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: VynicFloorTokens.textFaint,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        _destination?.label ?? 'აირჩიეთ დანიშნულება',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _destination == null
                              ? VynicFloorTokens.textFaint
                              : VynicFloorTokens.accentText,
                          fontSize: 13,
                          fontWeight: _destination == null
                              ? FontWeight.w400
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: VynicFloorTokens.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _itemsPane() {
    final items = widget.source.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: PosSectionLabel('რა გადაგაქვთ'),
        ),
        Expanded(
          child: items.isEmpty
              ? const _EmptyPane(message: 'შეკვეთაზე პროდუქტი არ არის')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _MoveLineRow(
                    item: items[index],
                    picked: _quantities[index] ?? 0,
                    onChanged: (quantity) => _setQuantity(index, quantity),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _destinationPane() {
    final existing = widget.options.where((o) => !o.isNew).toList();
    final fresh = widget.options.where((o) => o.isNew).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: PosSectionLabel('სად'),
        ),
        Expanded(
          child: widget.options.isEmpty
              ? const _EmptyPane(
                  message:
                      'დანიშნულება არ მოიძებნა.\n'
                      'ყველა მაგიდა დაკავებულია.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  children: [
                    // „Join something open" and „open something new" are
                    // different decisions, so they are not one flat list.
                    if (existing.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 0, 6, 8),
                        child: PosSectionLabel('უკვე გახსნილი'),
                      ),
                      for (final option in existing) ...[
                        _destinationRow(option),
                        const SizedBox(height: 8),
                      ],
                    ],
                    if (fresh.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 6, 6, 8),
                        child: PosSectionLabel('ახლად გაიხსნება'),
                      ),
                      for (final option in fresh) ...[
                        _destinationRow(option),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _destinationRow(OrderMoveOption option) {
    return _DestinationRow(
      label: option.label,
      detail: option.detail,
      isNew: option.isNew,
      selected: identical(_destination, option),
      onTap: () => setState(() => _destination = option),
    );
  }

  Widget _footer({required bool canMove}) {
    final warning = _movingEverything
        ? 'მთელი შეკვეთა გადადის — ${widget.sourceLabel} გათავისუფლდება.'
        : (_serviceFeeDiffers
              ? 'შეკვეთებს განსხვავებული სერვისი აქვთ — ჯამები შესაბამისად შეიცვლება.'
              : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The running total appears as soon as anything is picked,
                // not once the move is confirmable. Waiting for a destination
                // meant tapping through five steppers with no feedback on how
                // much was going across.
                Text(
                  _pickedCount == 0
                      ? 'აირჩიეთ პროდუქტები და დანიშნულება'
                      : '$_pickedCount ცალი  ·  '
                            '${_pickedAmount.toStringAsFixed(2)} ₾'
                            '${_destination == null ? '  ·  აირჩიეთ დანიშნულება' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _pickedCount == 0
                        ? VynicFloorTokens.textMuted
                        : VynicFloorTokens.text,
                    fontSize: 14,
                    fontWeight: _pickedCount == 0
                        ? FontWeight.w500
                        : FontWeight.w800,
                  ),
                ),
                if (warning != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    warning,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VynicFloorTokens.occupiedValue,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          PosActionButton(
            label: 'გაუქმება',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          PosPrimaryButton(
            label: 'გადატანა',
            icon: Icons.swap_horiz,
            height: 46,
            onTap: canMove
                ? () => Navigator.of(
                    context,
                  ).pop(OrderMoveRequest(option: _destination!, moves: _moves))
                : null,
          ),
        ],
      ),
    );
  }
}

/// One line of the bill, with how many of it are going.
class _MoveLineRow extends StatelessWidget {
  const _MoveLineRow({
    required this.item,
    required this.picked,
    required this.onChanged,
  });

  final OrderItem item;
  final int picked;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = picked > 0;
    final comment = item.comment?.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 10, 10),
      decoration: BoxDecoration(
        color: active ? VynicFloorTokens.accentSoft : VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: active
              ? const Color(0xFFE2DCF2)
              : VynicFloorTokens.panelBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active
                        ? VynicFloorTokens.accentText
                        : VynicFloorTokens.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (comment != null && comment.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    comment,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VynicFloorTokens.textMuted,
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  'შეკვეთაზე ${item.quantity}  ·  '
                  '${item.unitPrice.toStringAsFixed(2)} ₾',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VynicFloorTokens.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _QuantityStepper(
            value: picked,
            max: item.quantity,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// How many of one line are going across.
///
/// „All" is there because moving the whole line is the common case and nobody
/// should have to tap `+` ten times to say so on a touchscreen.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: VynicFloorTokens.panel,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: VynicFloorTokens.panelBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepButton(
                icon: Icons.remove,
                onTap: value > 0 ? () => onChanged(value - 1) : null,
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: value > 0
                        ? VynicFloorTokens.accentText
                        : VynicFloorTokens.textFaint,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add,
                onTap: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _AllButton(
          selected: value == max,
          onTap: () => onChanged(value == max ? 0 : max),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 30,
        height: 34,
        child: Icon(
          icon,
          size: 16,
          color: onTap == null
              ? VynicFloorTokens.freeDot
              : VynicFloorTokens.accentText,
        ),
      ),
    );
  }
}

class _AllButton extends StatelessWidget {
  const _AllButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? VynicFloorTokens.accentStrong : VynicFloorTokens.panel,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? VynicFloorTokens.accentStrong
                  : VynicFloorTokens.panelBorder,
            ),
          ),
          child: Text(
            'ყველა',
            style: TextStyle(
              color: selected
                  ? VynicFloorTokens.panel
                  : VynicFloorTokens.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// One candidate order. Selected reads as a tinted card with a filled radio —
/// the same shape the variant picker uses, so „pick one of these" looks like
/// itself everywhere on the POS.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.label,
    required this.detail,
    required this.isNew,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;

  /// Something that will be opened by this move. Marked with a `+` so it is
  /// obvious which rows create a table and which join one.
  final bool isNew;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? VynicFloorTokens.accentSoft : VynicFloorTokens.panel,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? const Color(0xFFE2DCF2)
                  : VynicFloorTokens.panelBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : (isNew
                          ? Icons.add_circle_outline
                          : Icons.radio_button_unchecked),
                size: 18,
                color: selected
                    ? VynicFloorTokens.accentText
                    : VynicFloorTokens.textFaint,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? VynicFloorTokens.accentText
                            : VynicFloorTokens.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VynicFloorTokens.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: VynicFloorTokens.textMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
