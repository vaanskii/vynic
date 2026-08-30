import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/windows_pos/screens/menu_screen.dart';
import 'package:vynic/apps/windows_pos/screens/order_detail_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/table_payment_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';

class HomeTakeAwaySection extends StatefulWidget {
  const HomeTakeAwaySection({
    super.key,
    required this.user,
    required this.takeAwayReservations,
    required this.onRefreshRequested,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
  });

  final User user;
  final List<Reservation> takeAwayReservations;
  final Future<void> Function() onRefreshRequested;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;

  @override
  State<HomeTakeAwaySection> createState() => _HomeTakeAwaySectionState();
}

class _HomeTakeAwaySectionState extends State<HomeTakeAwaySection> {
  String? _selectedReservationId;

  /// Which pane a narrow window is showing: 0 = the queue, 1 = the selected
  /// take-away. Wide windows show both and ignore this.
  int _narrowPane = 0;

  // The screen used to carry its own teal-and-slate palette, so the same
  // concepts looked different here than on the floor or the order page. It
  // draws from the shared POS tokens now.
  static const Color _accent = VynicFloorTokens.accentStrong;
  static const Color _success = VynicFloorTokens.accentText;
  static const Color _warning = VynicFloorTokens.occupiedValue;
  static const Color _danger = VynicFloorTokens.dangerText;
  static const Color _surface = VynicFloorTokens.panel;
  static const Color _surfaceAlt = VynicFloorTokens.metricFill;
  static const Color _outline = VynicFloorTokens.panelBorder;

  @override
  Widget build(BuildContext context) {
    final orderedTakeaways = [...widget.takeAwayReservations]
      ..sort((a, b) {
        final orderIdComparison = (b.linkedOrderId ?? 0).compareTo(
          a.linkedOrderId ?? 0,
        );
        if (orderIdComparison != 0) {
          return orderIdComparison;
        }

        final createdAtComparison = b.createdAt.compareTo(a.createdAt);
        if (createdAtComparison != 0) {
          return createdAtComparison;
        }

        return b.id.compareTo(a.id);
      });
    final activeCount = widget.takeAwayReservations
        .where((reservation) => reservation.status != 'completed')
        .length;
    final completedCount = widget.takeAwayReservations
        .where((reservation) => reservation.status == 'completed')
        .length;
    final delayedCount = widget.takeAwayReservations
        .where(_isTakeAwayDelayed)
        .length;
    final totalAmount = widget.takeAwayReservations.fold<double>(
      0,
      (sum, reservation) => sum + _calculateTakeAwayTotal(reservation),
    );

    Reservation? selectedReservation;
    if (orderedTakeaways.isNotEmpty) {
      selectedReservation = orderedTakeaways.firstWhere(
        (reservation) => reservation.id == _selectedReservationId,
        orElse: () => orderedTakeaways.first,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final platformMobile =
            !kIsWeb && (Platform.isAndroid || Platform.isIOS);
        // Only a genuine phone/tablet gets the single-pane layout. Desktop
        // windows are never laid out below PosScaledSurface.designSize, so
        // the three-column layout always has the room it needs.
        final isCompact = platformMobile;

        if (isCompact) {
          // Two panes, one at a time, each filling the height. Stacking them
          // in a scroll pushed the detail below the fold, so tapping a
          // take-away appeared to do nothing.
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTakeAwayHeader(compact: true),
                const SizedBox(height: 12),
                _buildMetricGrid(
                  activeCount: activeCount,
                  completedCount: completedCount,
                  delayedCount: delayedCount,
                  totalAmount: totalAmount,
                  compact: true,
                ),
                const SizedBox(height: 12),
                if (orderedTakeaways.isEmpty)
                  Expanded(child: _buildTakeAwayEmptyState())
                else ...[
                  PosPaneSwitch(
                    labels: const ['სია', 'დეტალები'],
                    selectedIndex: _narrowPane,
                    onSelected: (index) => setState(() => _narrowPane = index),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _narrowPane == 0
                        ? _buildTakeAwayQueuePanel(
                            reservations: orderedTakeaways,
                            selectedReservation: selectedReservation,
                            compact: true,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _buildTakeAwayDetailPanel(
                                  reservation: selectedReservation,
                                  compact: true,
                                ),
                              ),
                              if (selectedReservation != null) ...[
                                const SizedBox(height: 12),
                                _buildTakeAwayActionRail(selectedReservation),
                              ],
                            ],
                          ),
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTakeAwayHeader(compact: false),
              const SizedBox(height: 16),
              _buildMetricGrid(
                activeCount: activeCount,
                completedCount: completedCount,
                delayedCount: delayedCount,
                totalAmount: totalAmount,
                compact: false,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      // The rail takes a column of its own, so the queue
                      // gives up its wider setting to pay for it.
                      width: constraints.maxWidth < 1400 ? 340 : 380,
                      child: _buildTakeAwayQueuePanel(
                        reservations: orderedTakeaways,
                        selectedReservation: selectedReservation,
                        compact: false,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildTakeAwayDetailPanel(
                        reservation: selectedReservation,
                        compact: false,
                      ),
                    ),
                    if (selectedReservation != null) ...[
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 250,
                        child: _buildTakeAwayActionRail(selectedReservation),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, String>?> _showTakeAwayDetailsDialog() async {
    return showGeneralDialog<Map<String, String>>(
      context: context,
      barrierLabel: 'გატანის შეკვეთა',
      barrierColor: Colors.black.withValues(alpha: 0.58),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final mediaQuery = MediaQuery.of(dialogContext);
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: mediaQuery.size.width > 560
                      ? 560
                      : mediaQuery.size.width - 48,
                  maxHeight: mediaQuery.size.height > 720
                      ? 640
                      : mediaQuery.size.height * 0.9,
                ),
                child: _TakeAwayDetailsSheet(
                  initialTime: TimeOfDay.now(),
                  onEditNumber: (controller) => _openNumberKeyboardSheet(
                    controller: controller,
                    title: 'ნომრის შეყვანა',
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _startTakeAwayFlow() async {
    final details = await _showTakeAwayDetailsDialog();
    if (details == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final numberValue = details['number']?.trim() ?? '';
    final waitHere = details['waitHere'] == 'true';
    final label = _buildTakeAwayLabel(waitHere ? null : numberValue);
    final takeAwayDisplayName = waitHere
        ? 'აქ დაელოდება'
        : (numberValue.isNotEmpty ? numberValue : 'გატანის სტუმარი');
    final takeAwayNotes = waitHere ? 'აქ დაელოდება' : numberValue;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MenuScreen(
          user: widget.user,
          selectedTables: [label],
          isTakeAwayMode: true,
          takeAwayCustomerName: takeAwayDisplayName,
          takeAwayCustomerPhone: null,
          takeAwayPickupTime: details['pickupTime'],
          takeAwayNotes: takeAwayNotes,
        ),
      ),
    );

    await widget.onRefreshRequested();
    if (mounted) {
      setState(() {});
    }
  }

  String _buildTakeAwayLabel(String? rawNotes) {
    if (rawNotes == null || rawNotes.trim().isEmpty) {
      return 'გატანა';
    }
    final trimmed = rawNotes.trim();
    final preview = trimmed.length > 24
        ? '${trimmed.substring(0, 24)}…'
        : trimmed;
    return 'გატანა - $preview';
  }

  Future<void> _cancelTakeAwayOrder(Reservation reservation) async {
    if (!widget.user.isManager) {
      unawaited(showErrorToast(context, 'გაუქმება მხოლოდ მენეჯერს შეუძლია'));
      return;
    }

    final orderId = reservation.linkedOrderId;
    if (orderId == null) {
      unawaited(showErrorToast(context, 'შეკვეთა ჯერ არ არის შექმნილი'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('შეკვეთის გაუქმება'),
        content: Text('${_takeAwayOrderNumber(reservation)} გაუქმდეს?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('არა'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('გაუქმება'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await DatabaseService.updateOrderStatus(
      orderId: orderId,
      status: 'cancelled',
    );
    await DatabaseService.cancelReservationByOrderId(orderId);
    await widget.onRefreshRequested();

    if (!mounted) {
      return;
    }

    setState(() {});
    unawaited(showSuccessToast(context, 'შეკვეთა გაუქმდა'));
  }

  Future<void> _closeTakeAwayOrder(Reservation reservation) async {
    final orderId = reservation.linkedOrderId;
    if (orderId == null) {
      unawaited(showErrorToast(context, 'შეკვეთა ჯერ არ არის შექმნილი'));
      return;
    }

    final order = DatabaseService.getOrder(orderId);
    if (order == null) {
      unawaited(showErrorToast(context, 'შეკვეთა ვერ მოიძებნა'));
      return;
    }

    order.includeServiceFee = false;
    order.recalculateTotal(serviceFeeRate: DatabaseService.getServiceFeeRate());
    if (order.items.isEmpty && order.packageItems.isEmpty) {
      unawaited(
        showErrorToast(context, 'შეკვეთაში დამატებული პოზიციები არ არის'),
      );
      return;
    }

    final selection = await TablePaymentService(
      context: context,
      total: order.totalAmount,
    ).collect();
    if (!mounted || selection == null) {
      return;
    }

    final saleItems = <OrderItem>[...order.packageItems, ...order.items];
    final subtotal = order.getPackageSubtotal() + order.getItemsSubtotal();
    final serviceFee = order.getServiceFee();
    final closedAt = DatabaseService.getCurrentDateTime();
    final saleBreakdown = TableClosureHelper.buildSaleBreakdown(selection);
    final paymentMethodKey = TableClosureHelper.resolvePaymentMethod(selection);
    final finalTransaction = TableClosureHelper.buildFinalTransactionRecord(
      order: order,
      selection: selection,
      paymentBreakdown: saleBreakdown,
      subtotal: subtotal,
      serviceFee: serviceFee,
      closedAt: closedAt,
      isFiscal: true,
    );

    final closeSuccess = await DatabaseService.closeOrderWithPayment(
      orderId: order.orderId,
      paymentMethod: paymentMethodKey,
      closedById: widget.user.username,
      closedByName: widget.user.username,
      paymentBreakdown: saleBreakdown,
    );
    if (!mounted) {
      return;
    }
    if (!closeSuccess) {
      unawaited(showErrorToast(context, 'შეკვეთის დახურვა ვერ მოხერხდა'));
      return;
    }

    await DatabaseService.saveSaleRecord(
      orderId: order.orderId,
      tableNumbers: order.tableNumbers,
      floor: order.floor,
      items: saleItems,
      totalAmount: order.totalAmount,
      paymentMethod: paymentMethodKey,
      paymentBreakdown: saleBreakdown,
      createdBy: order.createdBy,
      createdAt: order.createdAt,
      closedAt: closedAt,
      includeServiceFee: false,
      discountAmount: order.discountAmount,
      advanceAmount: 0,
      subtotalAmount: subtotal,
      manualAdjustmentAmount: order.manualAdjustmentAmount,
      finalTransaction: finalTransaction,
      isFiscal: true,
    );
    await DatabaseService.refreshDailySalesTotalForDate(
      DatabaseService.getCurrentDate(),
    );

    final receiptLines = _buildTakeAwayFinalReceiptLines(
      order,
      selection,
      closedAt,
    );
    PrinterService.printReceiptInBackground(
      items: receiptLines,
      total: order.totalAmount,
      subtotal: null,
      serviceFee: null,
      includeServiceFee: false,
      tableNumber: null,
      orderNumber: order.orderId.toString(),
      paymentMethod: paymentMethodKey,
      language: 'ka',
      packageSubtotal: order.getPackageSubtotal() > 0
          ? order.getPackageSubtotal()
          : null,
      additionalSubtotal: order.getAdditionalItemsSubtotal() > 0
          ? order.getAdditionalItemsSubtotal()
          : null,
      discountAmount: null,
      manualAdjustment: null,
      receiptType: 'close_table',
      onComplete: (success) {
        if (!mounted) {
          return;
        }
        if (!success) {
          unawaited(
            showErrorToast(context, 'ფინალური ქვითრის ბეჭდვა ვერ მოხერხდა'),
          );
        }
      },
    );

    await widget.onRefreshRequested();

    if (!mounted) {
      return;
    }
    setState(() {});
    unawaited(
      showSuccessToast(
        context,
        'შეკვეთა დაიხურა: ${TableClosureHelper.buildSuccessMessage(selection)}',
      ),
    );
  }

  bool _isTakeAwayFinalized(Reservation reservation) {
    final orderStatus = _linkedOrderForReservation(
      reservation,
    )?.status.toLowerCase();
    final status = orderStatus ?? reservation.status.toLowerCase();
    return status == 'completed' ||
        status == 'paid' ||
        status == 'closed' ||
        status == 'cancelled';
  }

  List<String> _buildTakeAwayFinalReceiptLines(
    Order order,
    TablePaymentSelection selection,
    DateTime closedAt,
  ) {
    final lines = <String>[
      'Order #${order.orderId}',
      'დახურვა: ${_formatTakeAwayClosureTimestamp(closedAt)}',
      for (final item in [...order.packageItems, ...order.items])
        '${item.quantity}x ${item.itemName} - ₾${item.total.toStringAsFixed(2)}',
      'გადახდა:',
    ];

    if (selection.bankAmount > 0) {
      final bankLabel = TableClosureHelper.bankDisplayLabel(selection);
      lines.add(
        '• ბანკი ($bankLabel) ₾${selection.bankAmount.toStringAsFixed(2)}',
      );
    }
    if (selection.cashAmount > 0) {
      lines.add('• ნაღდი ₾${selection.cashAmount.toStringAsFixed(2)}');
    }

    return lines;
  }

  String _formatTakeAwayClosureTimestamp(DateTime value) {
    final datePart =
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final timePart =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '$datePart $timePart';
  }

  void _openTakeAwayOrderDetails(Reservation reservation) {
    final orderId = reservation.linkedOrderId;
    if (orderId == null) {
      unawaited(showErrorToast(context, 'შეკვეთა ჯერ არ არის შექმნილი'));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OrderDetailScreen(user: widget.user, orderId: orderId),
      ),
    ).then((_) async {
      await widget.onRefreshRequested();
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _openNumberKeyboardSheet({
    required TextEditingController controller,
    required String title,
  }) async {
    final updated = await showPosNumberKeyboardInputSheet(
      context: context,
      initialValue: controller.text.trim() == '?'
          ? '?'
          : controller.text.replaceAll(RegExp(r'\D+'), ''),
      title: title,
      maxDigits: 15,
      allowQuestionMark: true,
    );

    if (!mounted || updated == null) {
      return;
    }

    final sanitized = updated.trim() == '?'
        ? '?'
        : updated.replaceAll(RegExp(r'\D+'), '');
    controller.value = TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
  }

  Widget _buildTakeAwayHeader({required bool compact}) {
    return PosPageHeading(
      title: 'გატანები',
      subtitle: 'დღევანდელი შეკვეთების მართვა და სტატუსების კონტროლი.',
      trailing: PosPrimaryButton(
        label: compact ? 'ახალი' : 'ახალი გატანა',
        icon: Icons.add,
        onTap: _startTakeAwayFlow,
      ),
    );
  }

  Widget _buildMetricGrid({
    required int activeCount,
    required int completedCount,
    required int delayedCount,
    required double totalAmount,
    required bool compact,
  }) {
    final metrics = [
      _TakeAwayMetricData(
        icon: Icons.shopping_bag_outlined,
        label: 'აქტიური შეკვეთები',
        value: '$activeCount',
        helper: 'დღეს',
        color: VynicFloorTokens.text,
      ),
      _TakeAwayMetricData(
        icon: Icons.check_circle_outline,
        label: 'გადახდილი',
        value: '$completedCount',
        helper: 'დასრულებულია',
        color: VynicFloorTokens.text,
      ),
      _TakeAwayMetricData(
        icon: Icons.schedule_outlined,
        label: 'დაგვიანებული',
        value: '$delayedCount',
        helper: 'შეკვეთა',
        color: _warning,
      ),
      _TakeAwayMetricData(
        icon: Icons.payments_outlined,
        label: 'დღიური შემოსავალი',
        value: '₾${totalAmount.toStringAsFixed(2)}',
        helper: '${widget.takeAwayReservations.length} შეკვეთა',
        color: VynicFloorTokens.text,
      ),
    ];

    if (compact) {
      // Two across rather than four stacked: four full-width cards ate most
      // of a 700px-tall window before the panes below them got any height.
      return Column(
        children: [
          for (var row = 0; row < (metrics.length + 1) ~/ 2; row++) ...[
            if (row > 0) const SizedBox(height: 10),
            // IntrinsicHeight, not a stretched Row: this sits in a
            // Column with no height budget, and stretch needs a
            // bounded cross axis.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < 2; column++) ...[
                    if (column > 0) const SizedBox(width: 10),
                    Expanded(
                      child: row * 2 + column < metrics.length
                          ? _buildMetricCard(
                              metrics[row * 2 + column],
                              compact: true,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      children: metrics
          .map(
            (metric) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: metric == metrics.last ? 0 : 12,
                ),
                child: _buildMetricCard(metric, compact: false),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMetricCard(_TakeAwayMetricData metric, {required bool compact}) {
    return PosMetricCard(
      label: metric.label,
      value: metric.value,
      // Only the figures that mean something is wrong or outstanding get a
      // colour; the rest stay plain so the coloured one actually stands out.
      tone: metric.color == VynicFloorTokens.text ? null : metric.color,
    );
  }

  Widget _buildTakeAwayQueuePanel({
    required List<Reservation> reservations,
    required Reservation? selectedReservation,
    required bool compact,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'შეკვეთები (${reservations.length})',
                    style: TextStyle(
                      color: widget.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(Icons.swap_vert, color: widget.mutedText, size: 20),
              ],
            ),
          ),
          const Divider(height: 1, color: _outline),
          // One scrolling list in both layouts. The compact branch used
          // to render every card in a plain Column, which only worked
          // while the whole section sat inside an outer scroll view;
          // in a height-bounded pane it overflowed.
          if (reservations.isEmpty)
            Expanded(child: _buildTakeAwayEmptyState())
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: reservations.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final reservation = reservations[index];
                  return _buildQueueCard(
                    reservation: reservation,
                    selected: reservation.id == selectedReservation?.id,
                    compact: false,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueCard({
    required Reservation reservation,
    required bool selected,
    required bool compact,
  }) {
    final statusColor = _takeAwayStatusColor(reservation.status);
    final statusLabel = _takeAwayStatusLabel(reservation.status);
    final itemCount = _calculateTakeAwayItems(reservation);
    final totalAmount = _calculateTakeAwayTotal(reservation);
    final customerName = _takeAwayCustomerName(reservation);
    final orderNumber = _takeAwayOrderNumber(reservation);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        _selectedReservationId = reservation.id;
        // On a narrow window, picking one is a request to see it.
        _narrowPane = 1;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.08) : _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _accent : _outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        orderNumber,
                        style: TextStyle(
                          color: widget.textPrimary.withValues(alpha: 0.78),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₾${totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: widget.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _buildStatusChip(statusLabel, statusColor),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule, size: 15, color: widget.mutedText),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${_formatTakeAwayDate(reservation.reservationDate)}, ${reservation.reservationTime}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: widget.mutedText, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 15,
                  color: widget.mutedText,
                ),
                const SizedBox(width: 5),
                Text(
                  '$itemCount პროდუქტი',
                  style: TextStyle(color: widget.mutedText, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTakeAwayDetailPanel({
    required Reservation? reservation,
    required bool compact,
  }) {
    if (reservation == null) {
      return _buildTakeAwayEmptyState();
    }

    final statusColor = _takeAwayStatusColor(reservation.status);
    final statusLabel = _takeAwayStatusLabel(reservation.status);
    final items = _takeAwayItems(reservation);
    final itemTotal = _calculateTakeAwayTotal(reservation);
    final phone = reservation.customerPhone.trim();
    final notes = reservation.notes?.trim();

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(18, compact ? 16 : 18, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _takeAwayOrderNumber(reservation),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.textPrimary,
                                fontSize: compact ? 20 : 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _buildStatusChip(statusLabel, statusColor),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            color: widget.mutedText,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'შექმნილია: ${_formatTakeAwayDate(reservation.createdAt)}, ${_formatClock(reservation.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.mutedText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _outline),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (compact)
                    Column(
                      children: [
                        _buildDetailInfoBlock(
                          icon: Icons.person_outline,
                          title: _takeAwayCustomerName(reservation),
                          subtitle: phone.isEmpty ? 'ტელეფონი არ არის' : phone,
                        ),
                        const SizedBox(height: 10),
                        _buildDetailInfoBlock(
                          icon: Icons.timer_outlined,
                          title: 'გატანის დრო',
                          subtitle: reservation.reservationTime,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailInfoBlock(
                            icon: Icons.person_outline,
                            title: _takeAwayCustomerName(reservation),
                            subtitle: phone.isEmpty
                                ? 'ტელეფონი არ არის'
                                : phone,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildDetailInfoBlock(
                            icon: Icons.timer_outlined,
                            title: 'გატანის დრო',
                            subtitle: reservation.reservationTime,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildDetailInfoBlock(
                            icon: Icons.shopping_bag_outlined,
                            title: 'პროდუქტები',
                            subtitle:
                                '${_calculateTakeAwayItems(reservation)} პოზიცია',
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  _buildOrderItemsTable(items),
                  const SizedBox(height: 14),
                  if (compact) ...[
                    _buildNotesBox(notes),
                    const SizedBox(height: 12),
                    _buildSummaryBox(itemTotal: itemTotal),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _buildNotesBox(notes)),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: _buildSummaryBox(itemTotal: itemTotal),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItemsTable(List<OrderItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: _outline)),
            ),
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildTableHeader('პროდუქტი')),
                Expanded(flex: 2, child: _buildTableHeader('რაოდენობა')),
                Expanded(flex: 2, child: _buildTableHeader('ფასი')),
                Expanded(flex: 2, child: _buildTableHeader('ჯამი')),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'პროდუქტები ჯერ არ არის დამატებული',
                style: TextStyle(color: widget.mutedText, fontSize: 15),
              ),
            )
          else
            ...items.map(
              (item) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: VynicFloorTokens.divider),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.itemName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if ((item.comment ?? '').trim().isNotEmpty)
                            Text(
                              item.comment!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.mutedText,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${item.quantity}',
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '₾${item.unitPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '₾${item.total.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotesBox(String? notes) {
    final hasNotes = notes != null && notes.isNotEmpty;
    return Container(
      height: 86,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      alignment: Alignment.topLeft,
      child: Text(
        hasNotes ? notes : 'შენიშვნა...',
        style: TextStyle(
          color: hasNotes
              ? widget.textPrimary
              : widget.mutedText.withValues(alpha: 0.75),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildSummaryBox({required double itemTotal}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5F9),
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: _outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'სულ',
                  style: TextStyle(
                    color: widget.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '₾${itemTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  color: widget.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailInfoBlock({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, color: widget.textPrimary.withValues(alpha: 0.78), size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: widget.mutedText, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    if (color == _danger) return PosStatusPill.alert(label);
    if (color == _success) return PosStatusPill.done(label);
    if (color == _warning) return PosStatusPill.active(label);
    return PosStatusPill.booked(label);
  }

  /// What you can do with the selected take-away, grouped by what it touches
  /// — the same rail the order detail screen uses.
  ///
  /// These used to be a row of buttons under the preview, which meant the
  /// detail and the actions competed for the same strip of width and the row
  /// reflowed as the window changed.
  Widget _buildTakeAwayActionRail(Reservation? reservation) {
    if (reservation == null) {
      return const SizedBox.shrink();
    }
    final hasOrder = reservation.linkedOrderId != null;
    final open = hasOrder && !_isTakeAwayFinalized(reservation);

    final buttons = <Widget>[
      PosActionButton(
        label: 'სრული დეტალები',
        icon: Icons.manage_search_outlined,
        expand: true,
        onTap: hasOrder ? () => _openTakeAwayOrderDetails(reservation) : null,
      ),
      // Closing takes the money, so it reads as the money tone rather than
      // sharing a red with „გაუქმება".
      PosActionButton(
        label: 'შეკვეთის დახურვა',
        icon: Icons.check_circle_outline,
        tone: PosActionTone.money,
        expand: true,
        onTap: open ? () => _closeTakeAwayOrder(reservation) : null,
      ),
      if (widget.user.isManager)
        PosActionButton(
          label: 'გაუქმება',
          icon: Icons.cancel_outlined,
          tone: PosActionTone.danger,
          expand: true,
          onTap: open ? () => _cancelTakeAwayOrder(reservation) : null,
        ),
    ];

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_RailGroup(title: 'შეკვეთა', children: buttons)],
      ),
    );
  }

  Widget _buildTableHeader(String label) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: widget.mutedText,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  bool _isTakeAwayDelayed(Reservation reservation) {
    if (reservation.status == 'completed' ||
        reservation.status == 'cancelled') {
      return false;
    }
    final parts = reservation.reservationTime.split(':');
    if (parts.length < 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return false;
    final pickupDateTime = DateTime(
      reservation.reservationDate.year,
      reservation.reservationDate.month,
      reservation.reservationDate.day,
      hour,
      minute,
    );
    return pickupDateTime.isBefore(DateTime.now());
  }

  String _takeAwayCustomerName(Reservation reservation) {
    final name = reservation.customerName.trim();
    if (name.isNotEmpty) return name;
    final notes = reservation.notes?.trim();
    if (notes != null && notes.isNotEmpty) return notes;
    return 'გატანის სტუმარი';
  }

  String _takeAwayOrderNumber(Reservation reservation) {
    final linkedOrderId = reservation.linkedOrderId;
    if (linkedOrderId != null) {
      return '#TA-${linkedOrderId.toString().padLeft(4, '0')}';
    }
    final compactId = reservation.id.replaceAll(RegExp(r'[^0-9A-Za-z]+'), '');
    final suffix = compactId.length > 4
        ? compactId.substring(compactId.length - 4)
        : compactId.padLeft(4, '0');
    return '#TA-$suffix';
  }

  String _formatTakeAwayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }

  String _formatClock(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  int _calculateTakeAwayItems(Reservation reservation) {
    return _takeAwayItems(
      reservation,
    ).fold<int>(0, (sum, item) => sum + item.quantity);
  }

  double _calculateTakeAwayTotal(Reservation reservation) {
    final order = _linkedOrderForReservation(reservation);
    if (order != null) {
      return order.totalAmount;
    }
    return _takeAwayItems(
      reservation,
    ).fold<double>(0, (sum, item) => sum + item.total);
  }

  List<OrderItem> _takeAwayItems(Reservation reservation) {
    final order = _linkedOrderForReservation(reservation);
    if (order != null) {
      return [...order.packageItems, ...order.items];
    }
    return reservation.preOrderItems ?? const <OrderItem>[];
  }

  Order? _linkedOrderForReservation(Reservation reservation) {
    final orderId = reservation.linkedOrderId;
    if (orderId == null) {
      return null;
    }
    return DatabaseService.getOrder(orderId);
  }

  Color _takeAwayStatusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF047857);
      case 'paid':
      case 'closed':
        return const Color(0xFF475569);
      case 'preparing':
      case 'confirmed':
        return _accent;
      case 'cancelled':
        return const Color(0xFF9F1239);
      default:
        return const Color(0xFFB45309);
    }
  }

  String _takeAwayStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'დასრულებული';
      case 'paid':
        return 'გადახდილია';
      case 'closed':
        return 'დახურული';
      case 'preparing':
        return 'მომზადება';
      case 'confirmed':
        return 'დადასტურებული';
      case 'cancelled':
        return 'გაუქმებული';
      default:
        return 'მოლოდინში';
    }
  }

  Widget _buildTakeAwayEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: widget.primaryColor.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: widget.primaryColor.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: widget.mutedText.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          const Text(
            'ჯერ არ არის გატანის შეკვეთები',
            style: TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'დაამატე ახალი გატანის შეკვეთა, რომ სია შეივსოს.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.mutedText.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _TakeAwayMetricData {
  const _TakeAwayMetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;
  final Color color;
}

class _TakeAwayDetailsSheet extends StatefulWidget {
  const _TakeAwayDetailsSheet({
    required this.initialTime,
    required this.onEditNumber,
  });

  final TimeOfDay initialTime;
  final Future<void> Function(TextEditingController controller) onEditNumber;

  @override
  State<_TakeAwayDetailsSheet> createState() => _TakeAwayDetailsSheetState();
}

class _TakeAwayDetailsSheetState extends State<_TakeAwayDetailsSheet> {
  static const Color _accent = VynicFloorTokens.accentStrong;
  static const Color _surface = VynicFloorTokens.panel;
  static const Color _surfaceAlt = VynicFloorTokens.metricFill;
  static const Color _outline = VynicFloorTokens.panelBorder;
  static const Color _label = VynicFloorTokens.sectionLabel;
  static const Color _muted = VynicFloorTokens.textMuted;
  static const Color _textPrimary = VynicFloorTokens.text;

  late TimeOfDay _selectedTime;
  final TextEditingController _numberController = TextEditingController();
  bool _waitHere = false;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.initialTime;
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (selected != null) {
      setState(() => _selectedTime = selected);
    }
  }

  void _submit() {
    final number = _numberController.text.trim();
    if (!_waitHere && number.isEmpty) {
      unawaited(
        showErrorToast(
          context,
          'გთხოვთ, ჩაწეროთ ნომერი ან მონიშნოთ "აქ დაელოდება"',
        ),
      );
      return;
    }
    if (!_waitHere && number != '?' && !RegExp(r'^\d+$').hasMatch(number)) {
      unawaited(showErrorToast(context, 'მხოლოდ ციფრებია დასაშვები'));
      return;
    }

    final pickupString =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    Navigator.of(context).pop({
      'number': _waitHere ? '' : number,
      'waitHere': _waitHere ? 'true' : 'false',
      'pickupTime': pickupString,
    });
  }

  Future<void> _handleEditNumber() async {
    if (_waitHere) {
      return;
    }
    await widget.onEditNumber(_numberController);
    final raw = _numberController.text;
    final sanitized = raw.trim() == '?'
        ? '?'
        : raw.replaceAll(RegExp(r'\D+'), '');
    if (sanitized != raw) {
      _numberController
        ..text = sanitized
        ..selection = TextSelection.collapsed(offset: sanitized.length);
      if (mounted) {
        unawaited(
          showPosToast(
            context: context,
            message: 'მხოლოდ ციფრებია დასაშვები',
            style: PosToastStyle.info,
          ),
        );
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  String _formatDisplayTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(VynicFloorTokens.panelRadius);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            border: Border.all(color: _outline),
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                      decoration: const BoxDecoration(
                        color: _surface,
                        border: Border(bottom: BorderSide(color: _outline)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: VynicFloorTokens.accentSoft,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: const Color(0xFFE2DCF2),
                              ),
                            ),
                            child: const Icon(
                              Icons.takeout_dining_outlined,
                              color: _accent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 13),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ახალი გატანის შეკვეთა',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'გატანის დეტალები',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          PosStatusPill.booked('ახალი'),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: _muted,
                              ),
                              tooltip: 'დახურვა',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('გატანის დრო'),
                            const SizedBox(height: 8),
                            _FieldShell(
                              onTap: _pickTime,
                              icon: Icons.schedule_rounded,
                              iconColor: _accent,
                              child: Row(
                                children: [
                                  Text(
                                    _formatDisplayTime(_selectedTime),
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(
                                    Icons.edit_rounded,
                                    color: _muted,
                                    size: 19,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildLabel('ნომერი'),
                            const SizedBox(height: 8),
                            _buildNumberField(),
                            const SizedBox(height: 12),
                            _buildWaitHereSwitch(),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                      decoration: const BoxDecoration(
                        color: _surface,
                        border: Border(top: BorderSide(color: _outline)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: PosActionButton(
                              label: 'გაუქმება',
                              icon: Icons.close_rounded,
                              expand: true,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PosPrimaryButton(
                              label: 'შეკვეთის დაწყება',
                              icon: Icons.arrow_forward_rounded,
                              onTap: _submit,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _label,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildNumberField() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _numberController,
      builder: (context, value, _) {
        final text = value.text.trim();
        final isEmpty = text.isEmpty || _waitHere;

        return _FieldShell(
          onTap: _handleEditNumber,
          icon: Icons.pin_outlined,
          iconColor: _waitHere ? _muted : _accent,
          disabled: _waitHere,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _waitHere ? 'აქ დაელოდება ჩართულია' : 'ნომერი',
                style: TextStyle(
                  color: isEmpty ? _muted : _accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _waitHere
                        ? 'ნომრის ველი გამორთულია'
                        : (isEmpty ? 'ჩაწერეთ ნომერი' : value.text),
                    style: TextStyle(
                      color: isEmpty ? _muted : _textPrimary,
                      fontSize: 18,
                      height: 1.2,
                      fontWeight: isEmpty ? FontWeight.w500 : FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWaitHereSwitch() {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _waitHere ? VynicFloorTokens.accentSoft : _surfaceAlt,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _outline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.chair_alt_outlined,
            color: _waitHere ? _accent : _muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'აქ დაელოდება',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PosToggle(
            value: _waitHere,
            semanticLabel: 'ადგილზე დაელოდება',
            onChanged: (value) {
              setState(() {
                _waitHere = value;
                if (_waitHere) {
                  _numberController.clear();
                }
              });
            },
          ),
        ],
      ),
    );
  }
}

class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.onTap,
    required this.icon,
    required this.iconColor,
    required this.child,
    this.disabled = false,
  });

  final VoidCallback onTap;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final fill = disabled
        ? VynicFloorTokens.metricFill
        : VynicFloorTokens.panel;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: VynicFloorTokens.panelBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: disabled
                      ? VynicFloorTokens.badgeFill
                      : VynicFloorTokens.accentSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// One titled block of rail buttons.
class _RailGroup extends StatelessWidget {
  const _RailGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}
