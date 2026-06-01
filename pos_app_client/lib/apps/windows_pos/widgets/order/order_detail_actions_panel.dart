import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';

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

class OrderDetailActionsPanel extends StatelessWidget {
  const OrderDetailActionsPanel({
    super.key,
    required this.order,
    required this.actionsBundle,
    required this.serviceFeePercentageLabel,
    required this.otherActionsProvider,
  });

  final Order order;
  final OrderActionsBundle actionsBundle;
  final String serviceFeePercentageLabel;
  final List<OrderActionConfig> Function() otherActionsProvider;

  static const Color _panelColor = Colors.white;
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _titleColor = Color(0xFF1E293B);
  static const Color _mutedTextColor = Color(0xFF64748B);
  static const Color _accentColor = Color(0xFF2563EB);
  static const Color _successColor = Color(0xFF16A34A);
  static const Color _highlightColor = Color(0xFFC0AD7B);
  static const double _actionCardHeight = 122;

  @override
  Widget build(BuildContext context) {
    final combinedActions = [
      ...actionsBundle.primary,
      ...actionsBundle.secondary,
    ];
    final closeTableAction = _findActionByLabel(
      combinedActions,
      'მაგიდის დახურვა',
    );
    final receiptAction = _findActionByLabel(combinedActions, 'ქვითრის ბეჭდვა');

    final rawOtherActions = otherActionsProvider();
    final serviceAction = _findServiceAction(rawOtherActions);
    final otherActions = rawOtherActions
        .where((action) => !_isSameAction(action, serviceAction))
        .toList();
    final bool otherEnabled = otherActions.isNotEmpty;

    final quickActions = <OrderActionConfig>[
      closeTableAction ??
          const OrderActionConfig(
            label: 'მაგიდის დახურვა',
            icon: Icons.check_circle,
            onTap: null,
            accent: _mutedTextColor,
            subtitle: 'გადახდის დასრულება და მაგიდის დახურვა.',
          ),
      receiptAction ??
          const OrderActionConfig(
            label: 'ქვითრის ბეჭდვა',
            icon: Icons.receipt_long,
            onTap: null,
            accent: _mutedTextColor,
            subtitle: 'კლიენტისთვის დასაბეჭდი ქვითარი.',
          ),
      if (serviceAction != null) serviceAction,
      OrderActionConfig(
        label: 'სხვა',
        icon: Icons.apps,
        onTap: otherEnabled
            ? () => _showOtherActionsDialog(context, () => otherActions)
            : null,
        accent: otherEnabled ? _accentColor : _mutedTextColor,
        subtitle: otherEnabled
            ? 'ნახე დამატებითი პარამეტრები.'
            : 'დამატებითი მოქმედებები ხელმისაწვდომი არაა.',
      ),
    ];

    final actionsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'შეკვეთის მოქმედებები',
          style: TextStyle(
            color: _titleColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        _buildActionCardGrid(quickActions),
        if (combinedActions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'ამ შეკვეთაზე ხელმისაწვდომი მოქმედებები არ არის.',
              style: TextStyle(color: _mutedTextColor, fontSize: 12),
            ),
          ),
      ],
    );

    final totalsCard = _buildTotalsCard();

    return Container(
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double breakpoint = 560;

          if (constraints.maxWidth < breakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                actionsColumn,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: totalsCard),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: actionsColumn),
              const SizedBox(width: 16),
              totalsCard,
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionCard(OrderActionConfig action) {
    final Color accent = action.accent ?? _accentColor;
    final bool isDisabled = action.onTap == null;
    final Color borderColor = isDisabled
        ? _borderColor
        : accent.withValues(alpha: action.emphasize ? 0.5 : 0.35);
    final Color iconBackground = isDisabled
        ? _borderColor.withValues(alpha: 0.4)
        : accent.withValues(alpha: action.emphasize ? 0.22 : 0.12);
    final bool tonedDown = isDisabled || accent == _mutedTextColor;
    final Color labelColor = tonedDown ? _mutedTextColor : _titleColor;
    final Color subtitleColor = tonedDown
        ? _mutedTextColor.withValues(alpha: 0.85)
        : _mutedTextColor;

    return SizedBox(
      height: _actionCardHeight,
      child: _AnimatedOrderActionCard(
        action: action,
        accent: accent,
        isDisabled: isDisabled,
        borderColor: borderColor,
        iconBackground: iconBackground,
        labelColor: labelColor,
        subtitleColor: subtitleColor,
      ),
    );
  }

  Widget _buildActionCardGrid(List<OrderActionConfig> actions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 640.0;
        const double spacing = 12;
        const double runSpacing = 12;
        const double targetWidth = 170;

        int columns = (maxWidth / targetWidth).floor();
        if (columns < 1) {
          columns = 1;
        } else if (columns > 4) {
          columns = 4;
        }

        double cardWidth = columns == 1
            ? maxWidth
            : (maxWidth - spacing * (columns - 1)) / columns;
        cardWidth = cardWidth.clamp(145.0, 210.0);

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: actions
              .map(
                (action) =>
                    SizedBox(width: cardWidth, child: _buildActionCard(action)),
              )
              .toList(),
        );
      },
    );
  }

  OrderActionConfig? _findActionByLabel(
    List<OrderActionConfig> actions,
    String label,
  ) {
    for (final action in actions) {
      if (action.label == label) {
        return action;
      }
    }
    return null;
  }

  OrderActionConfig? _findServiceAction(List<OrderActionConfig> actions) {
    for (final action in actions) {
      if (action.label.startsWith('სერვისი')) {
        return action;
      }
    }
    return null;
  }

  bool _isSameAction(OrderActionConfig a, OrderActionConfig? b) {
    if (b == null) {
      return false;
    }
    return a.label == b.label && a.icon == b.icon;
  }

  Future<void> _showOtherActionsDialog(
    BuildContext context,
    List<OrderActionConfig> Function() actionsProvider,
  ) async {
    final initialActions = actionsProvider();
    if (initialActions.isEmpty) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final mappedActions = actionsProvider()
                .map(
                  (action) => OrderActionConfig(
                    label: action.label,
                    icon: action.icon,
                    onTap: action.onTap == null
                        ? null
                        : () {
                            action.onTap!();
                            setDialogState(() {});
                          },
                    onLongPress: action.onLongPress,
                    subtitle: action.subtitle,
                    accent: action.accent,
                    emphasize: action.emphasize,
                  ),
                )
                .toList();

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _panelColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.apps, color: _accentColor),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'სხვა მოქმედებები',
                              style: TextStyle(
                                color: _titleColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            splashRadius: 20,
                            icon: const Icon(
                              Icons.close,
                              color: _mutedTextColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (mappedActions.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'დამატებითი მოქმედებები არ არის.',
                              style: TextStyle(
                                color: _mutedTextColor,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 400),
                          child: SingleChildScrollView(
                            child: _buildActionCardGrid(mappedActions),
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

  Widget _buildTotalsCard() {
    final double subtotal = order.getItemsSubtotal();
    final double serviceFee = order.includeServiceFee
        ? order.getServiceFee()
        : 0.0;
    final bool serviceFeeGloballyEnabled =
        DatabaseService.isServiceFeeAvailable();
    final bool hasService =
        serviceFeeGloballyEnabled && order.includeServiceFee && serviceFee > 0;
    final double discount = order.discountAmount;
    final double adjustment = order.manualAdjustmentAmount;
    final bool hasAdjustment = adjustment.abs() >= 0.01;

    Widget buildRow(
      String label,
      String value, {
      Color labelColor = _mutedTextColor,
      Color valueColor = _titleColor,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'შეკვეთის ჯამი',
            style: TextStyle(
              color: _titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          buildRow('ქვეჯამი', '${subtotal.toStringAsFixed(2)} GEL'),
          if (serviceFeeGloballyEnabled)
            buildRow(
              'სერვისი ($serviceFeePercentageLabel%)',
              '${(hasService ? serviceFee : 0.0).toStringAsFixed(2)} GEL',
              labelColor: hasService
                  ? _mutedTextColor
                  : _mutedTextColor.withValues(alpha: 0.65),
              valueColor: hasService
                  ? _titleColor
                  : _mutedTextColor.withValues(alpha: 0.75),
            ),
          if (discount > 0)
            buildRow(
              'ფასდაკლება',
              '-${discount.toStringAsFixed(2)} GEL',
              labelColor: _successColor,
              valueColor: _successColor,
            ),
          if (hasAdjustment)
            buildRow(
              'კორექცია',
              '${adjustment > 0 ? '+' : ''}${adjustment.toStringAsFixed(2)} GEL',
              labelColor: adjustment > 0 ? _highlightColor : _successColor,
              valueColor: adjustment > 0 ? _highlightColor : _successColor,
            ),
          const Divider(height: 20, color: _borderColor),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ჯამი',
                style: TextStyle(
                  color: _titleColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${order.totalAmount.toStringAsFixed(2)} GEL',
                style: const TextStyle(
                  color: _accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnimatedOrderActionCard extends StatefulWidget {
  const _AnimatedOrderActionCard({
    required this.action,
    required this.accent,
    required this.isDisabled,
    required this.borderColor,
    required this.iconBackground,
    required this.labelColor,
    required this.subtitleColor,
  });

  final OrderActionConfig action;
  final Color accent;
  final bool isDisabled;
  final Color borderColor;
  final Color iconBackground;
  final Color labelColor;
  final Color subtitleColor;

  @override
  State<_AnimatedOrderActionCard> createState() =>
      _AnimatedOrderActionCardState();
}

class _AnimatedOrderActionCardState extends State<_AnimatedOrderActionCard>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  bool _isHolding = false;
  late final AnimationController _holdController;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_isPressed == value || widget.isDisabled) {
      return;
    }
    setState(() {
      _isPressed = value;
    });
  }

  void _setHolding(bool value) {
    if (_isHolding == value || widget.isDisabled) {
      return;
    }
    setState(() {
      _isHolding = value;
    });
    if (value) {
      _holdController.repeat(reverse: true);
    } else {
      _holdController.stop();
      _holdController.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double scale = _isPressed ? 0.97 : 1.0;
    final double holdStrength = _isHolding
        ? (0.08 + (_holdController.value * 0.10))
        : 0.0;

    return AnimatedBuilder(
      animation: _holdController,
      builder: (context, child) {
        return AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.action.onTap,
          onLongPress: widget.action.onLongPress == null
              ? null
              : () {
                  _setHolding(true);
                  widget.action.onLongPress!();
                },
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () {
            _setPressed(false);
            _setHolding(false);
          },
          onTapUp: (_) => _setPressed(false),
          onHighlightChanged: (isHighlighted) {
            _setPressed(isHighlighted);
            if (!isHighlighted) {
              _setHolding(false);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.borderColor,
                width: 1 + (_isHolding ? 0.2 : 0),
              ),
              boxShadow: widget.isDisabled
                  ? []
                  : [
                      BoxShadow(
                        color: widget.accent.withValues(
                          alpha: 0.08 + holdStrength,
                        ),
                        blurRadius: 8 + (_isHolding ? 6 : 0),
                        offset: Offset(0, _isHolding ? 3 : 4),
                      ),
                    ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: widget.iconBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.action.icon,
                    color: widget.accent,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.action.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.labelColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.action.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.action.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.subtitleColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!widget.isDisabled)
                  Icon(Icons.chevron_right, color: widget.accent, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
