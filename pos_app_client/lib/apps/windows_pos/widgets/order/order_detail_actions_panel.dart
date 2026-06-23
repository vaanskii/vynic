import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

class OrderActionConfig {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? subtitle;
  final Color? accent;
  final bool emphasize;

  const OrderActionConfig({
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
}

/// Bottom footer of the order detail screen: the row of primary order actions
/// (close table, print receipt, service, edit order and an overflow "other"
/// menu).
class OrderDetailActionsPanel extends StatelessWidget {
  const OrderDetailActionsPanel({
    super.key,
    required this.order,
    required this.actionsBundle,
    required this.serviceFeePercentageLabel,
    required this.otherActionsProvider,
    required this.onEditOrder,
    required this.canEditOrder,
  });

  final Order order;
  final OrderActionsBundle actionsBundle;
  final String serviceFeePercentageLabel;
  final List<OrderActionConfig> Function() otherActionsProvider;
  final VoidCallback onEditOrder;
  final bool canEditOrder;

  @override
  Widget build(BuildContext context) {
    final combinedActions = [
      ...actionsBundle.primary,
      ...actionsBundle.secondary,
    ];
    final closeAction = _findByLabel(combinedActions, 'მაგიდის დახურვა');
    final receiptAction = _findByLabel(combinedActions, 'ქვითრის ბეჭდვა');

    final rawOther = otherActionsProvider();
    final serviceAction = _findServiceAction(rawOther);
    final otherActions = rawOther
        .where((action) => !_isSameAction(action, serviceAction))
        .toList();

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AdminDesign.panel,
        border: Border(top: BorderSide(color: AdminDesign.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildTotalsStrip(),
            const Divider(height: 1, color: AdminDesign.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: _buildActionRow(
                context,
                closeAction: closeAction,
                receiptAction: receiptAction,
                serviceAction: serviceAction,
                otherActions: otherActions,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsStrip() {
    const Color successColor = Color(0xFF16A34A);
    const Color highlightColor = Color(0xFFC0AD7B);

    final double subtotal = order.getItemsSubtotal();
    final double packageSubtotal = order.getPackageSubtotal();
    final double serviceFee = order.includeServiceFee
        ? order.getServiceFee()
        : 0.0;
    final bool serviceFeeEnabled = DatabaseService.isServiceFeeAvailable();
    final bool hasService =
        serviceFeeEnabled && order.includeServiceFee && serviceFee > 0;
    final double discount = order.discountAmount;
    final double adjustment = order.manualAdjustmentAmount;
    final bool hasAdjustment = adjustment.abs() >= 0.01;

    final lines = <Widget>[
      if (packageSubtotal > 0)
        _TotalsItem(
          label: 'პაკეტი',
          value: '${packageSubtotal.toStringAsFixed(2)} ₾',
        ),
      _TotalsItem(
        label: packageSubtotal > 0 ? 'დამატებითი' : 'ქვეჯამი',
        value: '${subtotal.toStringAsFixed(2)} ₾',
      ),
      if (serviceFeeEnabled)
        _TotalsItem(
          label: 'სერვისი ($serviceFeePercentageLabel%)',
          value: '${(hasService ? serviceFee : 0.0).toStringAsFixed(2)} ₾',
          valueColor: hasService
              ? AdminDesign.text
              : AdminDesign.muted.withValues(alpha: 0.7),
        ),
      if (discount > 0)
        _TotalsItem(
          label: 'ფასდაკლება',
          value: '−${discount.toStringAsFixed(2)} ₾',
          valueColor: successColor,
        ),
      if (hasAdjustment)
        _TotalsItem(
          label: 'კორექცია',
          value:
              '${adjustment > 0 ? '+' : '−'}${adjustment.abs().toStringAsFixed(2)} ₾',
          valueColor: adjustment > 0 ? highlightColor : successColor,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.receipt_outlined,
            size: 18,
            color: AdminDesign.accentDark,
          ),
          const SizedBox(width: 8),
          const Text(
            'ანგარიშის შეჯამება',
            style: TextStyle(
              color: AdminDesign.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (int i = 0; i < lines.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: AdminDesign.border,
                    ),
                  lines[i],
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'სულ გადასახდელი',
            style: TextStyle(
              color: AdminDesign.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${order.totalAmount.toStringAsFixed(2)} ₾',
            style: const TextStyle(
              color: AdminDesign.accentDark,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(
    BuildContext context, {
    required OrderActionConfig? closeAction,
    required OrderActionConfig? receiptAction,
    required OrderActionConfig? serviceAction,
    required List<OrderActionConfig> otherActions,
  }) {
    final buttons = <Widget>[
      if (closeAction != null)
        _ActionButton(
          label: closeAction.label,
          icon: closeAction.icon,
          onTap: closeAction.onTap,
          onLongPress: closeAction.onLongPress,
          variant: _ActionVariant.danger,
        ),
      if (receiptAction != null)
        _ActionButton(
          label: receiptAction.label,
          icon: receiptAction.icon,
          onTap: receiptAction.onTap,
          variant: _ActionVariant.outline,
        ),
      if (serviceAction != null)
        _ActionButton(
          label: serviceAction.label,
          icon: serviceAction.icon,
          onTap: serviceAction.onTap,
          onLongPress: serviceAction.onLongPress,
          variant: _ActionVariant.outline,
        ),
      _ActionButton(
        label: 'შეკვეთის რედაქტირება',
        icon: Icons.edit_outlined,
        onTap: canEditOrder ? onEditOrder : null,
        variant: _ActionVariant.primary,
      ),
      _ActionButton(
        label: 'სხვა',
        icon: Icons.more_horiz,
        trailingIcon: Icons.keyboard_arrow_down,
        onTap: otherActions.isEmpty
            ? null
            : () => _showOtherActionsDialog(context, () => otherActions),
        variant: _ActionVariant.outline,
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: buttons,
    );
  }

  OrderActionConfig? _findByLabel(
    List<OrderActionConfig> actions,
    String label,
  ) {
    for (final action in actions) {
      if (action.label == label) return action;
    }
    return null;
  }

  OrderActionConfig? _findServiceAction(List<OrderActionConfig> actions) {
    for (final action in actions) {
      if (action.label.startsWith('სერვისი')) return action;
    }
    return null;
  }

  bool _isSameAction(OrderActionConfig a, OrderActionConfig? b) {
    if (b == null) return false;
    return a.label == b.label && a.icon == b.icon;
  }

  Future<void> _showOtherActionsDialog(
    BuildContext context,
    List<OrderActionConfig> Function() actionsProvider,
  ) async {
    if (actionsProvider().isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final actions = actionsProvider();
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AdminDesign.panelDecoration(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.more_horiz,
                            color: AdminDesign.accentDark,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'სხვა მოქმედებები',
                              style: TextStyle(
                                color: AdminDesign.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            splashRadius: 20,
                            icon: const Icon(
                              Icons.close,
                              color: AdminDesign.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final action in actions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _OtherActionTile(
                            action: action,
                            onInvoke: () {
                              action.onTap?.call();
                              setDialogState(() {});
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

enum _ActionVariant { primary, outline, danger }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.variant,
    this.onLongPress,
    this.trailingIcon,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final IconData? trailingIcon;
  final _ActionVariant variant;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onTap == null;

    late final Color background;
    late final Color foreground;
    late final Color borderColor;
    switch (variant) {
      case _ActionVariant.primary:
        background = disabled ? AdminDesign.border : AdminDesign.accentDark;
        foreground = disabled ? AdminDesign.muted : Colors.white;
        borderColor = background;
        break;
      case _ActionVariant.danger:
        background = Colors.white;
        foreground = disabled ? AdminDesign.muted : const Color(0xFFDC2626);
        borderColor = disabled
            ? AdminDesign.border
            : const Color(0xFFFECACA);
        break;
      case _ActionVariant.outline:
        background = Colors.white;
        foreground = disabled ? AdminDesign.muted : AdminDesign.text;
        borderColor = AdminDesign.border;
        break;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AdminDesign.radius),
      child: InkWell(
        onTap: onTap,
        onLongPress: disabled ? null : onLongPress,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminDesign.radius),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                Icon(trailingIcon, size: 18, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherActionTile extends StatelessWidget {
  const _OtherActionTile({required this.action, required this.onInvoke});

  final OrderActionConfig action;
  final VoidCallback onInvoke;

  @override
  Widget build(BuildContext context) {
    final bool disabled = action.onTap == null;
    final Color accent = action.accent ?? AdminDesign.accentDark;
    return Material(
      color: AdminDesign.panelSoft,
      borderRadius: BorderRadius.circular(AdminDesign.radius),
      child: InkWell(
        onTap: disabled ? null : onInvoke,
        onLongPress: action.onLongPress,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminDesign.radius),
            border: Border.all(color: AdminDesign.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (disabled ? AdminDesign.muted : accent).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(AdminDesign.radius),
                ),
                child: Icon(
                  action.icon,
                  size: 18,
                  color: disabled ? AdminDesign.muted : accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: TextStyle(
                        color: disabled ? AdminDesign.muted : AdminDesign.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (action.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        action.subtitle!,
                        style: const TextStyle(
                          color: AdminDesign.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!disabled)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AdminDesign.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsItem extends StatelessWidget {
  const _TotalsItem({
    required this.label,
    required this.value,
    this.valueColor = AdminDesign.text,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: AdminDesign.muted, fontSize: 13),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
