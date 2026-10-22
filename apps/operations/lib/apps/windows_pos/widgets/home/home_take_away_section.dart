import '../shared/pos_guest_fields.dart';
import '../shared/pos_workflow_actions.dart';
import '../order/helpers/order_detail_common_helpers.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/widgets/pos_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/database/transactions/cancel_order_transaction.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/takeaway_order.dart';
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
    required this.tickets,
    required this.onRefreshRequested,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
  });

  final User user;

  /// The day's takeaway orders. Built from `Order` — see [TakeawayTickets].
  final List<TakeawayTicket> tickets;
  final Future<void> Function() onRefreshRequested;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;

  @override
  State<HomeTakeAwaySection> createState() => _HomeTakeAwaySectionState();
}

class _HomeTakeAwaySectionState extends State<HomeTakeAwaySection> {
  int? _selectedOrderId;
  bool _actionRunning = false;

  /// Which pane a narrow window is showing: 0 = the queue, 1 = the selected
  /// take-away. Wide windows show both and ignore this.
  int _narrowPane = 0;
  final _searchController = TextEditingController();
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  /// What a takeaway is called when no guest name was taken with the order.
  static const String _takeAwayGuestFallback = 'გატანის სტუმარი';

  @override
  Widget build(BuildContext context) {
    // Already newest-first from the source; the panel does not re-sort.
    final orderedTakeaways = widget.tickets
        .where((ticket) => ticket.matchesSearch(_searchController.text))
        .toList();
    final now = DateTime.now();
    final activeCount = orderedTakeaways
        .where((ticket) => ticket.isActive)
        .length;
    final completedCount = orderedTakeaways
        .where((ticket) => ticket.isCompleted)
        .length;
    final delayedCount = orderedTakeaways
        .where((ticket) => ticket.isDelayedAt(now))
        .length;
    final totalAmount = orderedTakeaways.fold<double>(
      0,
      (sum, ticket) => sum + ticket.total,
    );

    TakeawayTicket? selectedTicket;
    if (orderedTakeaways.isNotEmpty) {
      selectedTicket = orderedTakeaways.firstWhere(
        (ticket) => ticket.orderId == _selectedOrderId,
        orElse: () => orderedTakeaways.first,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTakeAwayHeader(compact: false),
          const SizedBox(height: 8),
          _buildMetricGrid(
            activeCount: activeCount,
            completedCount: completedCount,
            delayedCount: delayedCount,
            totalAmount: totalAmount,
            compact: false,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PosWorkspace(
              paneLabels: const ['სია', 'შეკვეთა'],
              selectedPane: _narrowPane,
              onPaneSelected: (value) => setState(() => _narrowPane = value),
              master: _buildTakeAwayQueuePanel(
                tickets: orderedTakeaways,
                selectedTicket: selectedTicket,
                compact: false,
              ),
              detail: _buildTakeAwayDetailPanel(
                ticket: selectedTicket,
                compact: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, String>?> _showTakeAwayDetailsDialog() async {
    return showPosModal<Map<String, String>>(
      context: context,
      builder: (_) => _TakeAwayDetailsSheet(
        initialTime: TimeOfDay.now(),
        onEditNumber: (controller) => _openNumberKeyboardSheet(
          controller: controller,
          title: 'ნომრის შეყვანა',
        ),
      ),
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
    final enteredName = details['customerName']?.trim() ?? '';
    final takeAwayDisplayName = enteredName.isNotEmpty
        ? enteredName
        : waitHere
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
          takeAwayCustomerPhone: details['customerPhone'],
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

  Future<void> _cancelTakeAwayOrder(TakeawayTicket ticket) async {
    if (!widget.user.isManager) {
      unawaited(showErrorToast(context, 'გაუქმება მხოლოდ მენეჯერს შეუძლია'));
      return;
    }

    final orderId = ticket.orderId;

    final confirmed = await showPosModal<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const PosText('შეკვეთის გაუქმება'),
        content: PosText('${ticket.orderNumber} გაუქმდეს?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const PosText('უკან დაბრუნება'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const PosText('შეკვეთის გაუქმება'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    // Same routine as the detail screen: the Order stays as history with a
    // typed cancellation event and a non-revenue record. No physical table
    // is involved for a Takeaway.
    final outcome = await DatabaseService.cancelOrder(
      orderId: orderId,
      actorId: widget.user.username,
      actorName: widget.user.username,
      source: AuditSource.pos,
      reason: 'Takeaway cancelled from the home panel',
      approvedBy: widget.user.username,
    );
    if (!mounted) return;
    if (outcome == CancelOrderOutcome.notCancellable) {
      unawaited(
        showErrorToast(
          context,
          'დახურული შეკვეთის გაუქმება შეუძლებელია — ჯერ აღადგინეთ.',
        ),
      );
      return;
    }
    if (outcome == CancelOrderOutcome.failed ||
        outcome == CancelOrderOutcome.notFound) {
      unawaited(showErrorToast(context, 'შეკვეთის გაუქმება ვერ მოხერხდა'));
      return;
    }
    await widget.onRefreshRequested();

    if (!mounted) {
      return;
    }

    setState(() {});
    unawaited(showSuccessToast(context, 'შეკვეთა გაუქმდა'));
  }

  Future<void> _closeTakeAwayOrder(TakeawayTicket ticket) =>
      UpdateReadiness.track(
        'closeTakeAwayOrder',
        () => _admittedcloseTakeAwayOrder(ticket),
      );

  Future<void> _admittedcloseTakeAwayOrder(TakeawayTicket ticket) async {
    final orderId = ticket.orderId;
    // Re-read rather than closing the copy the panel was built with: the
    // order may have been edited on the detail screen since.
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
      grossTotal: order.grossAmount,
      advanceApplied: order.effectiveAdvanceAmount,
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

    // Same idempotent closure path as a dine-in table. A take-away order
    // used to write its sale here directly, which meant it kept none of the
    // gross/advance split and a retry could book it twice.
    final money = ClosureMoney.fromOrder(order, collectedNow: selection.total);
    final result = await DatabaseService.closeTable(
      orderId: order.orderId,
      money: money,
      paymentMethod: paymentMethodKey,
      tenderBreakdown: saleBreakdown ?? const {},
      closedById: widget.user.username,
      closedByName: widget.user.username,
      isFiscal: true,
      saleItems: saleItems,
      subtotalAmount: subtotal,
      finalTransaction: finalTransaction,
    );
    if (!mounted) {
      return;
    }
    if (!result.isSuccess) {
      unawaited(
        showErrorToast(
          context,
          result.outcome == ClosureOutcome.moneyMismatch
              ? 'გადახდის ჯამი არ ემთხვევა შეკვეთის თანხას — დახურვა შეჩერდა'
              : 'შეკვეთის დახურვა ვერ მოხერხდა',
        ),
      );
      return;
    }

    final receiptLines = _buildTakeAwayFinalReceiptLines(
      order,
      selection,
      closedAt,
    );
    await PrinterService.printReceiptInBackground(
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

  void _openTakeAwayOrderDetails(TakeawayTicket ticket) {
    final orderId = ticket.orderId;

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
      subtitle: 'შეკვეთები და გატანის დრო',
      trailing: PosWorkflowButton(
        label: compact ? 'ახალი' : 'ახალი გატანა',
        icon: Icons.add,
        onPressed: _actionRunning
            ? null
            : () => _runOrderAction(_startTakeAwayFlow),
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
        helper: '${widget.tickets.length} შეკვეთა',
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
      framed: false,
      // Only the figures that mean something is wrong or outstanding get a
      // colour; the rest stay plain so the coloured one actually stands out.
      tone: metric.color == VynicFloorTokens.text ? null : metric.color,
    );
  }

  Widget _buildTakeAwayQueuePanel({
    required List<TakeawayTicket> tickets,
    required TakeawayTicket? selectedTicket,
    required bool compact,
  }) {
    return Container(
      color: _surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: PosOnScreenTextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'ძებნა',
                helperText: 'სახელი · ტელეფონი · თანხა',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: PosText(
                    'შეკვეთები (${tickets.length})',
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
          if (tickets.isEmpty)
            Expanded(child: _buildTakeAwayEmptyState())
          else
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: tickets.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: _outline),
                itemBuilder: (context, index) {
                  final ticket = tickets[index];
                  return _buildQueueCard(
                    ticket: ticket,
                    selected: ticket.orderId == selectedTicket?.orderId,
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
    required TakeawayTicket ticket,
    required bool selected,
    required bool compact,
  }) {
    final statusColor = _takeAwayStatusColor(ticket.status);
    final statusLabel = _takeAwayStatusLabel(ticket.status);
    final itemCount = ticket.itemCount;
    final totalAmount = ticket.total;
    final customerName = ticket.customerName(_takeAwayGuestFallback);
    final orderNumber = ticket.orderNumber;

    return InkWell(
      onTap: () => setState(() {
        _selectedOrderId = ticket.orderId;
        // On a narrow window, picking one is a request to see it.
        _narrowPane = 1;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? VynicFloorTokens.accentSoft : _surface,

          border: Border(
            left: BorderSide(
              color: selected ? _accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              customerName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: widget.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              orderNumber,
              style: TextStyle(color: widget.mutedText, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatusChip(statusLabel, statusColor)),
                const SizedBox(width: 8),
                Text(
                  '₾${totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: widget.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${_formatTakeAwayDate(ticket.createdAt)}, ${ticket.pickupTime ?? _formatClock(ticket.createdAt)} · $itemCount პროდუქტი',
              style: TextStyle(color: widget.mutedText, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTakeAwayDetailPanel({
    required TakeawayTicket? ticket,
    required bool compact,
  }) {
    if (ticket == null) {
      return _buildTakeAwayEmptyState();
    }

    final statusColor = _takeAwayStatusColor(ticket.status);
    final statusLabel = _takeAwayStatusLabel(ticket.status);
    final items = ticket.items;
    final itemTotal = ticket.total;
    final phone = ticket.customerPhone ?? '';
    final notes = ticket.notes;
    final pickupTime = ticket.pickupTime ?? _formatClock(ticket.createdAt);

    return Container(
      color: _surface,
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
                            child: PosText(
                              ticket.orderNumber,
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
                            child: PosText(
                              'შექმნილია: ${_formatTakeAwayDate(ticket.createdAt)}, ${_formatClock(ticket.createdAt)}',
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
                          title: ticket.customerName(_takeAwayGuestFallback),
                          subtitle: phone.isEmpty ? 'ტელეფონი არ არის' : phone,
                        ),
                        const SizedBox(height: 10),
                        _buildDetailInfoBlock(
                          icon: Icons.timer_outlined,
                          title: 'გატანის დრო',
                          subtitle: pickupTime,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailInfoBlock(
                            icon: Icons.person_outline,
                            title: ticket.customerName(_takeAwayGuestFallback),
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
                            subtitle: pickupTime,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildDetailInfoBlock(
                            icon: Icons.shopping_bag_outlined,
                            title: 'პროდუქტები',
                            subtitle: '${ticket.itemCount} პოზიცია',
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  _buildOrderItemsTable(items),
                  const SizedBox(height: 14),
                  if (notes != null && notes.trim().isNotEmpty)
                    _buildNotesBox(notes),
                ],
              ),
            ),
          ),
          _buildSummaryBox(itemTotal: itemTotal),
          _buildTakeAwayActions(ticket),
        ],
      ),
    );
  }

  Widget _buildOrderItemsTable(List<OrderItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,

        border: const Border(top: BorderSide(color: _outline)),
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
              child: PosText(
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
                      child: PosText(
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
                      child: PosText(
                        '₾${item.unitPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: widget.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: PosText(
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
        color: VynicFloorTokens.panel,

        border: const Border(top: BorderSide(color: _outline)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: PosText(
                  'სულ',
                  style: TextStyle(
                    color: widget.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              PosText(
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
              PosText(
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
              PosText(
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

  Future<void> _runOrderAction(Future<void> Function() action) async {
    if (_actionRunning) return;
    setState(() => _actionRunning = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  Future<void> _editTakeAwayOrder(TakeawayTicket ticket) async {
    final order = DatabaseService.getOrder(ticket.orderId);
    if (order == null ||
        OrderDetailCommonHelpers.isFinalizedStatus(order.status)) {
      unawaited(
        showErrorToast(context, 'შეკვეთა აღარ არის ხელმისაწვდომი შესაცვლელად'),
      );
      return;
    }
    if (!OrderDetailCommonHelpers.canModifyOrder(widget.user, order)) {
      unawaited(
        showErrorToast(
          context,
          'ამ მაგიდის ცვლილება მხოლოდ შემქმნელს შეუძლია.',
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          user: widget.user,
          selectedTables: order.tableNumbers,
          existingOrderId: order.orderId,
        ),
      ),
    );
    await widget.onRefreshRequested();
    if (mounted) setState(() {});
  }

  Widget _buildTakeAwayActions(TakeawayTicket ticket) {
    final open = !ticket.isFinalized && !_actionRunning;
    final canEdit =
        open &&
        OrderDetailCommonHelpers.canModifyOrder(widget.user, ticket.order);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: VynicFloorTokens.metricFill,
        border: Border(top: BorderSide(color: _outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              PosWorkflowButton(
                label: 'მენიუს შეცვლა',
                icon: Icons.edit_outlined,
                onPressed: canEdit
                    ? () => _runOrderAction(() => _editTakeAwayOrder(ticket))
                    : null,
              ),
              PosWorkflowButton(
                label: 'გადახდა',
                icon: Icons.payments_outlined,
                primary: true,
                onPressed: open
                    ? () => _runOrderAction(() => _closeTakeAwayOrder(ticket))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton.icon(
                style: posWorkflowButtonStyle(context),
                onPressed: _actionRunning
                    ? null
                    : () => _openTakeAwayOrderDetails(ticket),
                icon: const Icon(Icons.history),
                label: const PosText('ისტორია და სხვა'),
              ),
              if (widget.user.isManager)
                TextButton.icon(
                  style: posWorkflowButtonStyle(context, danger: true),
                  onPressed: open
                      ? () =>
                            _runOrderAction(() => _cancelTakeAwayOrder(ticket))
                      : null,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const PosText('შეკვეთის გაუქმება'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String label) {
    return PosText(
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

  String _formatTakeAwayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }

  String _formatClock(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
          const PosText(
            'ჯერ არ არის გატანის შეკვეთები',
            style: TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          PosText(
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
  static const Color _surfaceAlt = VynicFloorTokens.metricFill;
  static const Color _outline = VynicFloorTokens.panelBorder;
  static const Color _muted = VynicFloorTokens.textMuted;
  static const Color _textPrimary = VynicFloorTokens.text;

  late TimeOfDay _selectedTime;
  final TextEditingController _numberController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _waitHere = false;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.initialTime;
  }

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
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
      'customerName': _nameController.text.trim(),
      'customerPhone': _phoneController.text.trim(),
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
  Widget build(BuildContext context) => PosFormDialog(
    title: 'გატანის შეკვეთა',
    onClose: () => Navigator.pop(context),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const PosText('გაუქმება'),
      ),
      ElevatedButton(
        onPressed: _submit,
        child: const PosText('შეკვეთის დაწყება'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule_rounded),
          label: PosText('გატანის დრო · ${_formatDisplayTime(_selectedTime)}'),
        ),
        const SizedBox(height: 24),
        PosGuestFields(
          name: _nameController,
          phone: _phoneController,
          optional: true,
        ),
        const SizedBox(height: 24),
        const PosText('ნომერი'),
        const SizedBox(height: 8),
        _buildNumberField(),
        const SizedBox(height: 12),
        _buildWaitHereSwitch(),
      ],
    ),
  );

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
              PosText(
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
                  child: PosText(
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
            child: PosText(
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
