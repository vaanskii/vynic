import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  static const Color _accent = Color(0xFF0F766E);
  static const Color _success = Color(0xFF047857);
  static const Color _warning = Color(0xFFB45309);
  static const Color _danger = Color(0xFFB91C1C);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceAlt = Color(0xFFF7F8FB);
  static const Color _outline = Color(0xFFDDE4ED);

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
        final isCompact = platformMobile || constraints.maxWidth < 980;

        if (isCompact) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 92),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTakeAwayHeader(compact: true),
                const SizedBox(height: 14),
                _buildMetricGrid(
                  activeCount: activeCount,
                  completedCount: completedCount,
                  delayedCount: delayedCount,
                  totalAmount: totalAmount,
                  compact: true,
                ),
                const SizedBox(height: 14),
                if (orderedTakeaways.isEmpty)
                  _buildTakeAwayEmptyState()
                else ...[
                  _buildTakeAwayQueuePanel(
                    reservations: orderedTakeaways,
                    selectedReservation: selectedReservation,
                    compact: true,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 620,
                    child: _buildTakeAwayDetailPanel(
                      reservation: selectedReservation,
                      compact: true,
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
                      width: constraints.maxWidth < 1200 ? 340 : 380,
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
      barrierColor: Colors.black.withValues(alpha: 0.85),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final mediaQuery = MediaQuery.of(dialogContext);
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: mediaQuery.size.width > 560
                      ? 480
                      : mediaQuery.size.width - 48,
                  maxHeight: mediaQuery.size.height > 720
                      ? 620
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

  Future<void> _openNumberKeyboardSheet({
    required TextEditingController controller,
    required String title,
  }) async {
    final updated = await showPosNumberKeyboardInputSheet(
      context: context,
      initialValue: controller.text.replaceAll(RegExp(r'\D+'), ''),
      title: title,
      maxDigits: 15,
    );

    if (!mounted || updated == null) {
      return;
    }

    final sanitized = updated.replaceAll(RegExp(r'\D+'), '');
    controller.value = TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
  }

  Widget _buildTakeAwayHeader({required bool compact}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'გატანები',
                style: TextStyle(
                  color: widget.textPrimary,
                  fontSize: compact ? 24 : 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'დღევანდელი შეკვეთების მართვა და სტატუსების კონტროლი',
                style: TextStyle(
                  color: widget.mutedText,
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _startTakeAwayFlow,
          icon: const Icon(Icons.add, size: 19),
          label: Text(compact ? 'ახალი' : 'ახალი გატანა'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 22,
              vertical: compact ? 13 : 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
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
        color: _accent,
      ),
      _TakeAwayMetricData(
        icon: Icons.check_circle_outline,
        label: 'გადახდილი',
        value: '$completedCount',
        helper: 'დასრულებულია',
        color: _success,
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
        color: const Color(0xFF7C3AED),
      ),
    ];

    if (compact) {
      return Column(
        children: metrics
            .map(
              (metric) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildMetricCard(metric, compact: true),
              ),
            )
            .toList(),
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
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 86 : 96),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 14 : 16,
      ),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(metric.icon, color: metric.color, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.textPrimary,
                    fontSize: compact ? 19 : 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metric.helper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: widget.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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
          if (reservations.isEmpty)
            Expanded(child: _buildTakeAwayEmptyState())
          else if (compact)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: reservations
                    .map(
                      (reservation) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildQueueCard(
                          reservation: reservation,
                          selected: reservation.id == selectedReservation?.id,
                          compact: true,
                        ),
                      ),
                    )
                    .toList(),
              ),
            )
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
      onTap: () => setState(() => _selectedReservationId = reservation.id),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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
          const Divider(height: 1, color: _outline),
          Padding(
            padding: const EdgeInsets.all(14),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildEditOrderButton(reservation),
                      const SizedBox(height: 8),
                      _buildCloseOrderButton(reservation),
                      if (widget.user.isManager) ...[
                        const SizedBox(height: 8),
                        _buildCancelOrderButton(reservation),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildEditOrderButton(reservation)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildCloseOrderButton(reservation)),
                      if (widget.user.isManager) ...[
                        const SizedBox(width: 10),
                        Expanded(child: _buildCancelOrderButton(reservation)),
                      ],
                    ],
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
        borderRadius: BorderRadius.circular(8),
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
                  border: Border(bottom: BorderSide(color: Color(0xFFE8EDF4))),
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
        borderRadius: BorderRadius.circular(8),
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
        borderRadius: BorderRadius.circular(8),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEditOrderButton(Reservation reservation) {
    final hasOrder = reservation.linkedOrderId != null;
    final canOpen = hasOrder;
    return ElevatedButton.icon(
      onPressed: canOpen ? () => _openTakeAwayOrderDetails(reservation) : null,
      icon: const Icon(Icons.manage_search_outlined),
      label: const Text('დეტალები'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE5EAF1),
        disabledForegroundColor: widget.mutedText,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _buildCloseOrderButton(Reservation reservation) {
    final hasOrder = reservation.linkedOrderId != null;
    final canClose = hasOrder && !_isTakeAwayFinalized(reservation);
    return ElevatedButton.icon(
      onPressed: canClose ? () => _closeTakeAwayOrder(reservation) : null,
      icon: const Icon(Icons.check_circle_outline),
      label: const Text('შეკვეთის დახურვა'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _danger,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE5EAF1),
        disabledForegroundColor: widget.mutedText,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _buildCancelOrderButton(Reservation reservation) {
    final hasOrder = reservation.linkedOrderId != null;
    final canCancel = hasOrder && !_isTakeAwayFinalized(reservation);
    return OutlinedButton.icon(
      onPressed: canCancel ? () => _cancelTakeAwayOrder(reservation) : null,
      icon: const Icon(Icons.cancel_outlined),
      label: const Text('გაუქმება'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _danger,
        disabledForegroundColor: widget.mutedText,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        side: BorderSide(color: _danger.withValues(alpha: 0.28)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
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
  static const Color _accent = Color(0xFF0F766E);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceAlt = Color(0xFFF6F8F7);
  static const Color _outline = Color(0xFFDDE4ED);
  static const Color _label = Color(0xFF115E59);
  static const Color _muted = Color(0xFF64748B);
  static const Color _textPrimary = Color(0xFF0F172A);

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
    if (!_waitHere && !RegExp(r'^\d+$').hasMatch(number)) {
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
    final sanitized = raw.replaceAll(RegExp(r'\D+'), '');
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
    final borderRadius = BorderRadius.circular(20);
    const double bottomPadding = 24;

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_surface, _surfaceAlt],
            ),
            border: Border.all(color: _outline),
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 14),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: _surface,
                        border: Border(bottom: BorderSide(color: _outline)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ახალი გატანის შეკვეთა',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: _muted),
                            tooltip: 'დახურვა',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          20,
                          20,
                          bottomPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('გატანის დრო'),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _pickTime,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _outline),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x11000000),
                                      blurRadius: 14,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.schedule,
                                      color: _accent,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      _formatDisplayTime(_selectedTime),
                                      style: const TextStyle(
                                        color: _textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Icon(
                                      Icons.edit,
                                      color: _muted,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildLabel('ნომერი'),
                            const SizedBox(height: 8),
                            _buildNumberField(),
                            const SizedBox(height: 14),
                            _buildWaitHereSwitch(),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _muted,
                                      side: BorderSide(
                                        color: _muted.withValues(alpha: 0.4),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text('გაუქმება'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _accent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 3,
                                    ),
                                    child: const Text(
                                      'შეკვეთის დაწყება',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildNumberField() {
    return GestureDetector(
      onTap: _handleEditNumber,
      behavior: HitTestBehavior.opaque,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _numberController,
        builder: (context, value, _) {
          final text = value.text.trim();
          final isEmpty = text.isEmpty || _waitHere;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: _waitHere ? _surfaceAlt.withValues(alpha: 0.8) : _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _outline, width: 1),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.pin_outlined,
                      color: _waitHere ? _muted : _accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _waitHere
                          ? 'აქ დაელოდება ჩართულია'
                          : (isEmpty ? 'ჩაწერეთ ნომერი' : 'ნომერი'),
                      style: TextStyle(
                        color: isEmpty ? _muted : _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      _waitHere
                          ? 'ნომრის ველი გამორთულია'
                          : (isEmpty
                                ? 'დააჭირეთ და ჩაწერეთ ნომერი'
                                : value.text),
                      style: TextStyle(
                        color: isEmpty ? _muted : _textPrimary,
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWaitHereSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.chair_alt_outlined, color: _accent, size: 20),
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
          Switch(
            value: _waitHere,
            activeThumbColor: _accent,
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
