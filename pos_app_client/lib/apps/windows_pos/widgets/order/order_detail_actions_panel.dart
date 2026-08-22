import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';

/// Stable identity for an order action.
///
/// The rail places each action in a specific slot, so it needs to recognise
/// them by something sturdier than their Georgian label — a wording change
/// should not silently drop a button off the screen.
enum OrderActionId {
  confirmOrder,
  printKitchenCheck,
  printReceipt,
  toggleServiceFee,
  receiptServiceFeeLine,
  nonFiscalClose,
  advance,
  priceAdjustment,
  changeTable,
  cancelOrder,
  closeTable,
}

class OrderActionConfig {
  final OrderActionId id;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? subtitle;
  final Color? accent;
  final bool emphasize;

  const OrderActionConfig({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.subtitle,
    this.accent,
    this.emphasize = false,
  });
}

class OrderActionsBundle {
  final List<OrderActionConfig> primary;
  final List<OrderActionConfig> secondary;

  const OrderActionsBundle({required this.primary, required this.secondary});

  bool get isEmpty => primary.isEmpty && secondary.isEmpty;

  List<OrderActionConfig> get all => [...primary, ...secondary];

  OrderActionConfig? operator [](OrderActionId id) {
    for (final action in all) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// Right-hand rail of the order detail screen: what the table owes, then the
/// things a waiter can do about it, grouped by what they affect.
///
/// The grouping is the point. Money-changing actions, printing and
/// table-level operations are three different kinds of decision, and the one
/// irreversible action — closing the table — sits alone at the bottom as the
/// only filled button on the screen.
class OrderDetailActionRail extends StatelessWidget {
  const OrderDetailActionRail({
    super.key,
    required this.order,
    required this.actionsBundle,
    required this.serviceFeePercentageLabel,
    required this.onEditOrder,
    required this.canEditOrder,
  });

  final Order order;
  final OrderActionsBundle actionsBundle;
  final String serviceFeePercentageLabel;
  final VoidCallback onEditOrder;
  final bool canEditOrder;

  @override
  Widget build(BuildContext context) {
    final closeTable = actionsBundle[OrderActionId.closeTable];

    final orderActions = <Widget>[
      ?_action(actionsBundle[OrderActionId.confirmOrder]),
      PosActionButton(
        label: 'მენიუს რედაქტირება',
        onTap: canEditOrder ? onEditOrder : null,
        expand: true,
      ),
      ?_action(actionsBundle[OrderActionId.advance], tone: PosActionTone.money),
      ?_action(
        actionsBundle[OrderActionId.priceAdjustment],
        tone: PosActionTone.money,
      ),
      ?_serviceFeeAction(),
      ?_receiptLineAction(),
    ];

    final printActions = <OrderActionConfig>[
      ?actionsBundle[OrderActionId.printKitchenCheck],
      ?actionsBundle[OrderActionId.printReceipt],
    ];

    final tableActions = <Widget>[
      ?_action(actionsBundle[OrderActionId.changeTable]),
      ?_action(
        actionsBundle[OrderActionId.nonFiscalClose],
        tone: PosActionTone.caution,
      ),
      ?_action(
        actionsBundle[OrderActionId.cancelOrder],
        tone: PosActionTone.danger,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TotalsCard(
                  order: order,
                  serviceFeePercentageLabel: serviceFeePercentageLabel,
                ),
                if (orderActions.isNotEmpty)
                  _ActionGroup(title: 'შეკვეთა', children: orderActions),
                if (printActions.isNotEmpty)
                  _ActionGroup(
                    title: 'ბეჭდვა',
                    // Two checks fit side by side; a lone one takes the width.
                    children: printActions.length == 2
                        ? [
                            Row(
                              children: [
                                for (var i = 0; i < 2; i++) ...[
                                  if (i > 0) const SizedBox(width: 10),
                                  Expanded(child: _action(printActions[i])!),
                                ],
                              ],
                            ),
                          ]
                        : [_action(printActions.first)!],
                  ),
                if (tableActions.isNotEmpty)
                  _ActionGroup(title: 'მაგიდა', children: tableActions),
              ],
            ),
          ),
        ),
        if (closeTable != null) ...[
          const SizedBox(height: 16),
          PosPrimaryButton(
            label: closeTable.label,
            onTap: closeTable.onTap,
            onLongPress: closeTable.onLongPress,
            height: 56,
          ),
        ],
      ],
    );
  }

  Widget? _action(
    OrderActionConfig? action, {
    PosActionTone tone = PosActionTone.neutral,
  }) {
    if (action == null) return null;
    return PosActionButton(
      label: action.label,
      onTap: action.onTap,
      onLongPress: action.onLongPress,
      tone: tone,
      expand: true,
    );
  }

  /// The service fee carries state, so it gets a dot: on or off at a glance,
  /// without having to read the totals card to find out.
  ///
  /// Tap toggles it; press and hold opens the rate configuration. That
  /// long-press is the only way into the custom service rates from here, so it
  /// is threaded through deliberately rather than left to the generic path.
  Widget? _serviceFeeAction() {
    final action = actionsBundle[OrderActionId.toggleServiceFee];
    if (action == null) return null;
    return PosActionButton(
      label: action.label,
      onTap: action.onTap,
      onLongPress: action.onLongPress,
      tone: PosActionTone.money,
      expand: true,
      trailing: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: order.includeServiceFee
                ? VynicFloorTokens.occupiedDot
                : VynicFloorTokens.freeDot,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Whether the service row is printed on the receipt.
///
/// Display only, and separate from whether the fee is charged: the row can be
/// hidden while the fee is still in the total.
extension _ReceiptLineAction on OrderDetailActionRail {
  Widget? _receiptLineAction() {
    final action = actionsBundle[OrderActionId.receiptServiceFeeLine];
    if (action == null) return null;
    return PosActionButton(
      label: action.label,
      onTap: action.onTap,
      tone: PosActionTone.money,
      expand: true,
      trailing: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: action.emphasize
                ? VynicFloorTokens.occupiedDot
                : VynicFloorTokens.freeDot,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// What the table owes, broken down. Nothing here is interactive — the actions
/// that change these figures live below.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.order,
    required this.serviceFeePercentageLabel,
  });

  final Order order;
  final String serviceFeePercentageLabel;

  @override
  Widget build(BuildContext context) {
    final subtotal = order.getItemsSubtotal();
    final packageSubtotal = order.getPackageSubtotal();
    final serviceFee = order.includeServiceFee ? order.getServiceFee() : 0.0;
    final serviceFeeEnabled = DatabaseService.isServiceFeeAvailable();
    final advance = order.discountAmount;
    final adjustment = order.manualAdjustmentAmount;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (packageSubtotal > 0)
            _TotalsLine(label: 'პაკეტი', amount: packageSubtotal),
          _TotalsLine(
            label: packageSubtotal > 0 ? 'დამატებითი' : 'ჯამი',
            amount: subtotal,
          ),
          if (serviceFeeEnabled)
            _TotalsLine(
              label: 'მომსახურება $serviceFeePercentageLabel%',
              amount: serviceFee,
              muted: serviceFee <= 0,
            ),
          // The advance is money already taken, so it reads as a deduction in
          // the accent colour rather than as another charge.
          if (advance > 0)
            _TotalsLine(
              label: 'ავანსი',
              amount: -advance,
              color: VynicFloorTokens.accentText,
            ),
          if (adjustment.abs() >= 0.01)
            _TotalsLine(
              label: 'კორექცია',
              amount: adjustment,
              color: adjustment > 0
                  ? VynicFloorTokens.occupiedValue
                  : VynicFloorTokens.accentText,
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: VynicFloorTokens.divider),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'გადასახდელი',
                  style: TextStyle(
                    color: VynicFloorTokens.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${order.totalAmount.toStringAsFixed(2)} ₾',
                    style: const TextStyle(
                      color: VynicFloorTokens.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalsLine extends StatelessWidget {
  const _TotalsLine({
    required this.label,
    required this.amount,
    this.color,
    this.muted = false,
  });

  final String label;
  final double amount;
  final Color? color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final sign = amount < 0 ? '− ' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color ?? VynicFloorTokens.textMuted,
                fontSize: 13.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$sign${amount.abs().toStringAsFixed(2)} ₾',
            style: TextStyle(
              color:
                  color ??
                  (muted ? VynicFloorTokens.textFaint : VynicFloorTokens.text),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: PosSectionLabel(title),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
  }
}
