import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos_change_highlight_service.dart';
import 'package:vynic/core/services/pos_live_refresh.dart';
import 'package:vynic/core/services/sync_events.dart';
import 'package:vynic/core/services/printer_service.dart';
import 'package:vynic/apps/windows_pos/widgets/comment_input_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/pin_button.dart';
import 'package:vynic/core/services/table_payment_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_content_section.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_actions_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_header_section.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_side_panels.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/order_detail_action_helpers.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/order_detail_common_helpers.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/apps/windows_pos/widgets/receipt_language_picker_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/service_fee_adjust_dialog.dart';
import 'menu_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final User user;
  final int orderId;
  final bool autoConfirmOnLoad;

  const OrderDetailScreen({
    super.key,
    required this.user,
    required this.orderId,
    this.autoConfirmOnLoad = false,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Order? _order;
  Reservation? _linkedReservation;
  late bool _serviceFeeAvailable;
  bool _autoConfirmTriggered = false;
  Set<String>? _mobileHighlightItemKeys;
  StreamSubscription<SyncEvent>? _syncEventsSub;

  void _onExternalOrderChange() {
    if (!mounted) return;
    _loadOrder();
  }

  void _onSyncEvent(SyncEvent event) {
    if (!mounted) return;
    if (event.type != SyncEventType.orders &&
        event.type != SyncEventType.tables &&
        event.type != SyncEventType.reservations) {
      return;
    }
    final payload = event.payload;
    if (payload != null) {
      final rawOrderId = payload['orderId'];
      final orderId = rawOrderId is int
          ? rawOrderId
          : int.tryParse(rawOrderId?.toString() ?? '');
      if (orderId != null && orderId != widget.orderId) {
        return;
      }
    }
    _loadOrder();
  }
  static const Color _surfaceColor = Color(0xFFF6F7F9);
  static const Color _panelColor = Colors.white;
  static const Color _titleColor = Color(0xFF111827);

  void _popWithResult(Map<String, dynamic> resultPayload) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(resultPayload);
    });
  }

  void _popToHomeWithResult(Map<String, dynamic> resultPayload) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(resultPayload);
      }
      navigator.popUntil((route) => route.isFirst);
    });
  }

  OrderActionsBundle _resolveOrderActions({
    required String status,
    required bool canPrintKitchenCheck,
    required bool canPrintReceipt,
  }) {
    final order = _order!;
    final bool canModify =
        !_isFinalizedStatus(status) && _canCurrentUserModifyOrder(order);
    final bool canCloseTable =
        (status == 'confirmed' ||
            status == 'preparing' ||
            status == 'served') &&
        canModify &&
        _canCurrentUserCloseOrder(order);
    final bool canNonFiscalClose = _canNonFiscalCloseTable(order, status);
    return OrderDetailActionHelpers.buildActions(
      status: status,
      order: order,
      user: widget.user,
      canPrintKitchenCheck: canPrintKitchenCheck,
      canPrintReceipt: canPrintReceipt,
      canModify: canModify,
      isTakeAwayOrder: _isTakeAwayOrder,
      canCloseTable: canCloseTable,
      canNonFiscalClose: canNonFiscalClose,
      serviceFeeAvailable: _serviceFeeAvailable,
      serviceFeePercentageLabel: _serviceFeeLabelForOrder(order),
      onConfirmOrder: () => _updateStatus('confirmed'),
      onPrintKitchenCheck: _printKitchenCheck,
      onPrintReceipt: _printReceipt,
      onToggleServiceFee: _toggleServiceFee,
      onOpenServiceFeeConfig: _openServiceFeeAdjustDialog,
      onStartNonFiscalClosureFlow: _startNonFiscalClosureFlow,
      onShowDiscountDialog: _showDiscountDialog,
      onShowManualAdjustmentDialog: _showManualAdjustmentDialog,
      onShowChangeTableDialog: _showChangeTableDialog,
      onConfirmCancelOrder: _confirmCancelOrder,
      onStartTableClosureFlow: _startTableClosureFlow,
    );
  }

  bool _canNonFiscalCloseTable(Order order, String status) {
    if (!widget.user.canCloseTablesNonFiscal) {
      return false;
    }
    if (_isFinalizedStatus(status)) {
      return false;
    }
    if (widget.user.isManager || widget.user.isSupervisor) {
      return true;
    }
    return _canCurrentUserModifyOrder(order);
  }

  bool _canCurrentUserCloseOrder(Order order) {
    if (widget.user.isManager) {
      return true;
    }

    // Check if ownership restriction is enabled
    final restrictToOwner = DatabaseService.isTableCloseRestrictedToOwner();

    if (!restrictToOwner) {
      // Default behavior: any waiter can close any open table
      return true;
    }

    // Ownership mode: only the user who opened/activated the table can close it
    // Use openedByUserId if available (new field), otherwise fall back to createdBy
    final ownerId = order.openedByUserId ?? order.createdBy;
    return ownerId == widget.user.username;
  }

  bool _canCurrentUserModifyOrder(Order order) {
    // Admin can always modify orders
    if (widget.user.isAdmin) {
      return true;
    }

    final restrictToOwner = DatabaseService.isTableCloseRestrictedToOwner();
    if (!restrictToOwner) {
      return true;
    }

    final ownerId = order.openedByUserId ?? order.createdBy;
    return ownerId == widget.user.username;
  }

  bool get _isTakeAwayOrder => _order != null && _isTakeAway(_order!);

  bool _isFinalizedStatus(String status) {
    return OrderDetailCommonHelpers.isFinalizedStatus(status);
  }

  bool _isTakeAway(Order order) {
    return OrderDetailCommonHelpers.isTakeAway(order);
  }

  String? get _reservationCustomerName {
    return OrderDetailCommonHelpers.reservationCustomerName(_linkedReservation);
  }

  String? get _reservationCustomerPhone {
    return OrderDetailCommonHelpers.reservationCustomerPhone(
      _linkedReservation,
    );
  }

  String? get _reservationNotesLabel {
    return OrderDetailCommonHelpers.reservationNotesLabel(_linkedReservation);
  }

  TimeOfDay? _parseReservationTime(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<Map<String, dynamic>?> _showReservationSheet({
    String title = 'New Reservation',
    String confirmLabel = 'Create Reservation',
    String? initialName,
    String? initialPhone,
    String? initialNotes,
    DateTime? initialDate,
    TimeOfDay? initialTime,
    int? initialGuests,
  }) {
    return showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierLabel: title,
      barrierColor: Colors.black.withOpacity(0.85),
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
                  maxWidth: mediaQuery.size.width * 0.9,
                  maxHeight: mediaQuery.size.height * 0.95,
                ),
                child: ReservationCreationSheet(
                  onCancel: () => Navigator.of(dialogContext).pop(),
                  title: title,
                  confirmLabel: confirmLabel,
                  initialName: initialName,
                  initialPhone: initialPhone,
                  initialNotes: initialNotes,
                  initialDate: initialDate,
                  initialTime: initialTime,
                  initialGuests: initialGuests,
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

  Future<void> _editLinkedReservationDetails() async {
    final reservation = _linkedReservation;
    if (reservation == null) {
      return;
    }

    final initialTime = _parseReservationTime(reservation.reservationTime);
    final result = await _showReservationSheet(
      title: 'რეზერვაციის დეტალების შეცვლა',
      confirmLabel: 'შენახვა',
      initialName: reservation.customerName,
      initialPhone: reservation.customerPhone,
      initialNotes: reservation.notes,
      initialDate: reservation.reservationDate,
      initialTime: initialTime,
      initialGuests: reservation.numberOfGuests,
    );

    if (result == null) {
      return;
    }

    final selectedDate = result['date'] as DateTime?;
    final selectedTime = result['time'] as TimeOfDay?;
    if (selectedDate == null || selectedTime == null) {
      return;
    }

    final guestCountRaw =
        (result['numberOfGuests'] as int?) ?? (result['guests'] as int?);
    final guestCount = guestCountRaw != null && guestCountRaw > 0
        ? guestCountRaw
        : reservation.numberOfGuests;

    reservation.customerName = (result['customerName'] as String? ?? '').trim();
    reservation.customerPhone = (result['customerPhone'] as String? ?? '')
        .trim();
    final notes = (result['notes'] as String?)?.trim();
    reservation.notes = notes != null && notes.isNotEmpty ? notes : null;
    reservation.reservationDate = selectedDate;
    reservation.reservationTime =
        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
    reservation.numberOfGuests = guestCount;

    await reservation.save();

    if (!mounted) {
      return;
    }

    _loadOrder();
    unawaited(showSuccessToast(context, 'რეზერვაციის დეტალები განახლდა'));
  }

  @override
  void initState() {
    super.initState();
    _mobileHighlightItemKeys =
        PosChangeHighlightService.takeForOrder(widget.orderId);
    _serviceFeeAvailable = DatabaseService.isServiceFeeAvailable();
    _loadOrder();
    _syncEventsSub = SyncHub.events.listen(_onSyncEvent);
    PosLiveRefresh.generation.addListener(_onExternalOrderChange);
  }

  @override
  void dispose() {
    _syncEventsSub?.cancel();
    PosLiveRefresh.generation.removeListener(_onExternalOrderChange);
    super.dispose();
  }

  void _loadOrder() {
    final fetchedOrder = DatabaseService.getOrder(widget.orderId);
    final serviceFeeAvailable = DatabaseService.isServiceFeeAvailable();
    Reservation? linkedReservation;

    if (fetchedOrder != null) {
      final isTakeAway = _isTakeAway(fetchedOrder);
      if (!serviceFeeAvailable &&
          fetchedOrder.includeServiceFee &&
          !_isFinalizedStatus(fetchedOrder.status)) {
        fetchedOrder.includeServiceFee = false;
        fetchedOrder.recalculateTotal();
        fetchedOrder.updatedAt = DatabaseService.getCurrentDateTime();
        fetchedOrder.save();
      }
      if (isTakeAway &&
          fetchedOrder.includeServiceFee &&
          !_isFinalizedStatus(fetchedOrder.status)) {
        fetchedOrder.includeServiceFee = false;
        fetchedOrder.recalculateTotal();
        fetchedOrder.updatedAt = DatabaseService.getCurrentDateTime();
        fetchedOrder.save();
      }
      linkedReservation = DatabaseService.findReservationForOrder(fetchedOrder);
    }

    setState(() {
      _order = fetchedOrder;
      _linkedReservation = linkedReservation;
      _serviceFeeAvailable = serviceFeeAvailable;
    });

    if (widget.autoConfirmOnLoad &&
        !_autoConfirmTriggered &&
        fetchedOrder != null &&
        fetchedOrder.status == 'pending') {
      final binding = WidgetsBinding.instance;
      binding.addPostFrameCallback((_) => _autoConfirmIfNeeded());
    }
  }

  Future<void> _autoConfirmIfNeeded() async {
    if (!mounted || _autoConfirmTriggered) {
      return;
    }

    final order = _order;
    if (order == null || order.status != 'pending') {
      return;
    }

    _autoConfirmTriggered = true;

    try {
      await _updateStatus('confirmed');
    } catch (_) {
      _autoConfirmTriggered = false;
      if (mounted) {
        unawaited(
          showErrorToast(
            context,
            'შეკვეთის ავტომატური დადასტურება ვერ მოხერხდა',
          ),
        );
      }
    }
  }

  Future<void> _printReceipt() async {
    if (_order == null) return;

    final language = await ReceiptLanguagePickerDialog.show(
      context,
      barrierDismissible: false,
    );

    // If user cancelled the dialog, don't print
    if (language == null) return;

    final isEnglish = language == 'en';

    String resolveDisplayName(String name) {
      return _getItemNameForLanguage(name, language);
    }

    final receiptLines = <String>[];

    if (_order!.packageItems.isNotEmpty) {
      final hasPackageName =
          _order!.packageName != null && _order!.packageName!.trim().isNotEmpty;
      final packageLabel = hasPackageName
          ? _getItemNameForLanguage(_order!.packageName!.trim(), language)
          : (isEnglish ? 'Package' : 'პაკეტი');
      final packageGuestCount = _order!.packageGuestCount;
      final packageTotalRaw = _order!.getPackageSubtotal();
      final packageTotal = packageTotalRaw > 0
          ? packageTotalRaw
          : _order!.packagePrice;

      receiptLines.add('[$packageLabel]');

      final summaryBuffer = StringBuffer();
      if (packageGuestCount > 0) {
        summaryBuffer.write('${packageGuestCount}x ');
      }
      summaryBuffer.write(packageLabel);
      if (packageTotal > 0) {
        summaryBuffer.write(' - ${packageTotal.toStringAsFixed(2)} GEL');
      }
      receiptLines.add(summaryBuffer.toString());

      for (final packageItem in _order!.packageItems) {
        final displayName = resolveDisplayName(packageItem.itemName);
        final itemLine = '  ⮑ ${packageItem.quantity}x $displayName';
        receiptLines.add(itemLine);
      }

      if (_order!.items.isNotEmpty) {
        receiptLines.add('---');
      }
    }

    if (_order!.items.isNotEmpty) {
      if (_order!.packageItems.isNotEmpty) {
        receiptLines.add(isEnglish ? '[Additional Items]' : '[დამატებითი]');
      }
      receiptLines.addAll(
        _order!.items.map((item) {
          final displayName = resolveDisplayName(item.itemName);
          return '${item.quantity}x $displayName - '
              '${item.total.toStringAsFixed(2)} GEL';
        }),
      );
    }

    // Add waiter name to receipt items (at the beginning) - language dependent
    final waiterLabel = isEnglish ? 'Waiter' : 'ოფიციანტი';
    final itemsWithWaiter = <String>[
      '$waiterLabel: ${_order!.createdBy}',
      '---',
      ...receiptLines,
    ];

    final packageSubtotal = _order!.getPackageSubtotal();
    final additionalSubtotal = _order!.getAdditionalItemsSubtotal();
    final discountAmount = _order!.discountAmount > 0
        ? _order!.discountAmount
        : null;
    final manualAdjustment = _order!.manualAdjustmentAmount.abs() >= 0.01
        ? _order!.manualAdjustmentAmount
        : null;
    final receiptType = _isTakeAwayOrder ? 'take_away' : 'client';

    // Print receipt in background with selected language
    final receiptTableNumber = _isTakeAwayOrder
        ? null
        : _order!.tableNumbers.join(', ');

    PrinterService.printReceiptInBackground(
      items: itemsWithWaiter,
      total: _order!.totalAmount,
      subtotal: _order!.getItemsSubtotal(),
      serviceFee: _order!.getServiceFee(),
      includeServiceFee: _order!.includeServiceFee,
      tableNumber: receiptTableNumber,
      orderNumber: _order!.orderId.toString(),
      language: language,
      packageSubtotal: packageSubtotal > 0 ? packageSubtotal : null,
      additionalSubtotal: additionalSubtotal > 0 ? additionalSubtotal : null,
      discountAmount: discountAmount,
      manualAdjustment: manualAdjustment,
      receiptType: receiptType,
      onComplete: (success) {
        if (!mounted) return;
        if (success) {
          unawaited(showSuccessToast(context, 'ქვითარი დაიბეჭდა'));
        } else {
          unawaited(showErrorToast(context, 'პრინტერი მიუწვდომელია'));
        }
      },
    );
  }

  /// Localize a menu item name to the requested language using menu metadata.
  String _getItemNameForLanguage(String originalName, String language) {
    final targetLanguage = language == 'en' ? 'en' : 'ka';
    final trimmedOriginal = originalName.trim();
    if (trimmedOriginal.isEmpty) {
      return originalName;
    }

    try {
      final categories = DatabaseService.getAllMenuCategories();
      for (final category in categories) {
        final localized = _findLocalizedName(
          category.items,
          trimmedOriginal,
          targetLanguage,
        );
        if (localized != null) {
          return localized;
        }

        if (category.subcategories != null) {
          for (final subcategory in category.subcategories!) {
            final subLocalized = _findLocalizedName(
              subcategory.items,
              trimmedOriginal,
              targetLanguage,
            );
            if (subLocalized != null) {
              return subLocalized;
            }
          }
        }
      }
    } catch (_) {
      // Fall back to original name if localization lookup fails.
    }

    return originalName;
  }

  String? _findLocalizedName(
    List<dynamic>? items,
    String original,
    String targetLanguage,
  ) {
    if (items == null) {
      return null;
    }

    for (final item in items) {
      final nameKa = item.getName('ka').trim();
      final nameEn = item.getName('en').trim();

      if (_itemNameMatches(original, nameKa)) {
        return _composeLocalizedName(
          baseKa: nameKa,
          baseEn: nameEn,
          targetLanguage: targetLanguage,
          original: original,
          matchedBase: nameKa,
        );
      }

      if (_itemNameMatches(original, nameEn)) {
        return _composeLocalizedName(
          baseKa: nameKa,
          baseEn: nameEn,
          targetLanguage: targetLanguage,
          original: original,
          matchedBase: nameEn,
        );
      }
    }

    return null;
  }

  bool _itemNameMatches(String original, String candidate) {
    if (candidate.isEmpty) {
      return false;
    }
    final normalizedOriginal = original.trim().toLowerCase();
    final normalizedCandidate = candidate.trim().toLowerCase();
    return normalizedOriginal == normalizedCandidate ||
        normalizedOriginal.startsWith('$normalizedCandidate ') ||
        normalizedOriginal.startsWith('$normalizedCandidate-') ||
        normalizedOriginal.startsWith('$normalizedCandidate(');
  }

  String _composeLocalizedName({
    required String baseKa,
    required String baseEn,
    required String targetLanguage,
    required String original,
    required String matchedBase,
  }) {
    final suffix = original.length > matchedBase.length
        ? original.substring(matchedBase.length)
        : '';
    final targetBase = targetLanguage == 'en' ? baseEn.trim() : baseKa.trim();
    if (targetBase.isEmpty) {
      return original;
    }
    return targetBase + suffix;
  }

  String _formatServiceFeePercentage(
    double value, {
    int maxFractionDigits = 1,
  }) {
    final precision = value == value.roundToDouble()
        ? 0
        : value < 1
        ? (maxFractionDigits + 1)
        : maxFractionDigits;
    return value.toStringAsFixed(precision);
  }

  String _serviceFeeLabelForOrder(Order order) {
    final globalPercent = DatabaseService.getServiceFeePercentage();
    final effectivePercent = order.getEffectiveServiceFeePercentage(
      globalDefaultPercentage: globalPercent,
    );
    return _formatServiceFeePercentage(effectivePercent);
  }

  void _toggleServiceFee() {
    final order = _order;
    if (order == null || _isTakeAwayOrder) {
      return;
    }
    if (!_serviceFeeAvailable) {
      return;
    }
    if (_isFinalizedStatus(order.status)) {
      return;
    }

    final defaultPercent = DatabaseService.getServiceFeePercentage();
    final effectivePercent = order.getEffectiveServiceFeePercentage(
      globalDefaultPercentage: defaultPercent,
    );

    setState(() {
      final prevInclude = order.includeServiceFee;
      order.includeServiceFee = !prevInclude;
      order.recalculateTotal(serviceFeeRate: effectivePercent / 100);
      order.updatedAt = DatabaseService.getCurrentDateTime();
      unawaited(
        DatabaseService.updateOrder(
          order,
          previousIncludeServiceFee: prevInclude,
        ),
      );
    });
  }

  void _openServiceFeeAdjustDialog() {
    unawaited(_showServiceFeeAdjustDialog());
  }

  Future<void> _showServiceFeeAdjustDialog() async {
    final order = _order;
    if (order == null || _isTakeAwayOrder) {
      return;
    }
    if (!_serviceFeeAvailable) {
      return;
    }
    if (_isFinalizedStatus(order.status)) {
      return;
    }

    final defaultPercent = DatabaseService.getServiceFeePercentage();
    final initialPercent = order.getEffectiveServiceFeePercentage(
      globalDefaultPercentage: defaultPercent,
    );

    final result = await showDialog<ServiceFeeAdjustResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ServiceFeeAdjustDialog(
        initialIncludeServiceFee: order.includeServiceFee,
        initialPercentage: initialPercent,
        defaultPercentage: defaultPercent,
        showQuickValues: true,
        showSteppers: true,
      ),
    );

    if (result == null) {
      return;
    }

    final normalizedPercent = double.parse(
      result.percentage.clamp(0.0, 100.0).toStringAsFixed(2),
    );
    final useGlobalDefault = (normalizedPercent - defaultPercent).abs() < 0.01;

    final prevInclude = order.includeServiceFee;
    setState(() {
      order
        ..includeServiceFee = result.includeServiceFee
        ..customServiceFeePercentage = useGlobalDefault
            ? null
            : normalizedPercent;

      order.recalculateTotal(serviceFeeRate: normalizedPercent / 100);
      order.updatedAt = DatabaseService.getCurrentDateTime();
    });
    unawaited(
      DatabaseService.updateOrder(
        order,
        previousIncludeServiceFee: prevInclude,
      ),
    );
  }

  Future<void> _showDiscountDialog() async {
    if (_order == null) return;

    // Calculate the maximum discount based on the full pre-discount total
    final packageSubtotal = _order!.getPackageSubtotal();
    final additionalSubtotal = _order!.getAdditionalItemsSubtotal();
    final serviceFeeAmount = _order!.includeServiceFee
        ? _order!.getServiceFee()
        : 0.0;
    final manualAdjustment = _order!.manualAdjustmentAmount;
    final maxDiscount =
        packageSubtotal +
        additionalSubtotal +
        serviceFeeAmount +
        (manualAdjustment > 0 ? manualAdjustment : 0.0);

    final TextEditingController controller = TextEditingController(
      text: _order!.discountAmount > 0
          ? _order!.discountAmount.toStringAsFixed(2)
          : '',
    );

    final discount = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.discount,
                            color: Color(0xFF2563EB),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'ფასდაკლება',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'მაქსიმალური: ${maxDiscount.toStringAsFixed(2)} GEL',
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      readOnly: true,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        suffixText: 'GEL',
                        suffixStyle: const TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildNumericKeyboard(controller),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_order!.discountAmount > 0)
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, 0.0),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                            ),
                            child: const Text(
                              'წაშლა',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                          ),
                          child: const Text('გაუქმება'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final value =
                                double.tryParse(controller.text) ?? 0.0;
                            const double epsilon = 0.01;
                            if (value - maxDiscount > epsilon) {
                              unawaited(
                                showErrorToast(
                                  dialogContext,
                                  'ფასდაკლება არ უნდა აღემატებოდეს ${maxDiscount.toStringAsFixed(2)} GEL',
                                ),
                              );
                              return;
                            }
                            Navigator.pop(dialogContext, value);
                          },
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('შენახვა'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (discount != null) {
      setState(() {
        _order!.setDiscount(discount);
      });
    }

    controller.dispose();
  }

  Future<void> _showManualAdjustmentDialog() async {
    if (_order == null) return;

    final controller = TextEditingController(
      text: _order!.manualAdjustmentAmount.abs() >= 0.01
          ? _order!.manualAdjustmentAmount.toStringAsFixed(2)
          : '',
    );

    double parseAdjustment(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty ||
          trimmed == '-' ||
          trimmed == '-.' ||
          trimmed == '.') {
        return 0.0;
      }
      final parsed = double.tryParse(trimmed) ?? 0.0;
      return double.parse(parsed.toStringAsFixed(2));
    }

    final adjustment = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.price_change,
                            color: Color(0xFF2563EB),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'ფასის კორექცია',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'დადებითი ზრდის ჯამს, უარყოფითი ამცირებს.',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      readOnly: true,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        suffixText: 'GEL',
                        suffixStyle: const TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildNumericKeyboard(controller, allowNegative: true),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_order!.manualAdjustmentAmount.abs() >= 0.01)
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, 0.0),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                            ),
                            child: const Text(
                              'განულება',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                          ),
                          child: const Text('გაუქმება'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final raw = controller.text;
                            final value = parseAdjustment(raw);
                            Navigator.pop(dialogContext, value);
                          },
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('შენახვა'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (adjustment != null) {
      setState(() {
        _order!.setManualAdjustment(adjustment);
      });
    }

    controller.dispose();
  }

  Widget _buildNumericKeyboard(
    TextEditingController controller, {
    bool allowNegative = false,
  }) {
    void addDigit(String digit) {
      final currentText = controller.text;
      if (digit == '.' && currentText.contains('.')) {
        return; // Only one decimal point
      }
      controller.text = currentText + digit;
    }

    void backspace() {
      final currentText = controller.text;
      if (currentText.isNotEmpty) {
        controller.text = currentText.substring(0, currentText.length - 1);
      }
    }

    void clear() {
      controller.clear();
    }

    void toggleSign() {
      final currentText = controller.text;
      if (currentText.startsWith('-')) {
        controller.text = currentText.substring(1);
      } else {
        controller.text = currentText.isEmpty ? '-' : '-$currentText';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PinButton(number: '1', onPressed: () => addDigit('1')),
              const SizedBox(width: 12),
              PinButton(number: '2', onPressed: () => addDigit('2')),
              const SizedBox(width: 12),
              PinButton(number: '3', onPressed: () => addDigit('3')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PinButton(number: '4', onPressed: () => addDigit('4')),
              const SizedBox(width: 12),
              PinButton(number: '5', onPressed: () => addDigit('5')),
              const SizedBox(width: 12),
              PinButton(number: '6', onPressed: () => addDigit('6')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PinButton(number: '7', onPressed: () => addDigit('7')),
              const SizedBox(width: 12),
              PinButton(number: '8', onPressed: () => addDigit('8')),
              const SizedBox(width: 12),
              PinButton(number: '9', onPressed: () => addDigit('9')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PinButton(number: '.', onPressed: () => addDigit('.')),
              const SizedBox(width: 12),
              PinButton(number: '0', onPressed: () => addDigit('0')),
              const SizedBox(width: 12),
              PinButton(number: '⌫', onPressed: backspace, isSpecial: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (allowNegative) ...[
                PinButton(
                  number: '+/-',
                  onPressed: toggleSign,
                  isSpecial: true,
                ),
                const SizedBox(width: 12),
              ],
              PinButton(number: 'Clear', onPressed: clear, isSpecial: true),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeTableDialog() async {
    if (_order == null) return;

    final allTables = DatabaseService.getAllTables();
    final freeTables = allTables
        .where(
          (t) =>
              DatabaseService.isTableConfigured(
                tableNumber: t.tableNumber,
                floor: t.floor,
              ) &&
              !t.isReserved,
        )
        .toList();

    if (freeTables.isEmpty) {
      unawaited(
        showPosToast(
          context: context,
          message: 'თავისუფალი მაგიდები არ მოიძებნა',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    final Set<String> selectedTableIds = {};
    final currentTableLabels = OrderDetailCommonHelpers.orderTableDisplayLabel(
      _order!,
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 480,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 35,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFC0AD7B,
                            ).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.table_restaurant_rounded,
                            color: Color(0xFFC0AD7B),
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            'მაგიდის შეცვლა',
                            style: TextStyle(
                              color: Color(0xFF1F2937),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          splashRadius: 24,
                          icon: const Icon(Icons.close, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'მიმდინარე: $currentTableLabels. აირჩიეთ ახალი მაგიდები.',
                              style: const TextStyle(
                                color: Color(0xFF4B5563),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 320),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: freeTables.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final t = freeTables[index];
                          final tableId = '${t.tableNumber}|${t.floor}';
                          final isSelected = selectedTableIds.contains(tableId);

                          return CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
                            ),
                            value: isSelected,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  selectedTableIds.add(tableId);
                                } else {
                                  selectedTableIds.remove(tableId);
                                }
                              });
                            },
                            title: Text(
                              OrderDetailCommonHelpers.tableDisplayName(
                                tableNumber: t.tableNumber,
                                floor: t.floor,
                              ),
                              style: TextStyle(
                                color: const Color(0xFF374151),
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              t.floor == 'first'
                                  ? 'პირველი სართული'
                                  : 'მეორე სართული',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            activeColor: const Color(0xFFC0AD7B),
                            checkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            checkboxShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'გაუქმება',
                              style: TextStyle(
                                color: Colors.black45,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedTableIds.isEmpty
                                ? null
                                : () async {
                                    final ids = selectedTableIds.toList();
                                    Navigator.of(ctx).pop();
                                    await _changeTables(ids);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC0AD7B),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'შეცვლა',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _changeTables(List<String> selectedTableIds) async {
    if (_order == null || selectedTableIds.isEmpty) return;

    final fromTables = List<String>.from(_order!.tableNumbers);
    final fromFloor = _order!.floor;

    final List<String> toTableNumbers = [];
    String? toFloor;

    for (final id in selectedTableIds) {
      final parts = id.split('|');
      toTableNumbers.add(parts[0]);
      toFloor ??= parts[1];
    }

    if (toFloor == null) return;

    // Apply the change in memory
    _order!.tableNumbers = toTableNumbers;
    _order!.floor = toFloor;
    _order!.updatedAt = DatabaseService.getCurrentDateTime();

    try {
      // Save order changes
      await DatabaseService.updateOrder(_order!);

      // Free all previously occupied tables
      for (final oldNum in fromTables) {
        await DatabaseService.freeTable(tableNumber: oldNum, floor: fromFloor);
      }

      // Reserve all new tables
      for (final newNum in toTableNumbers) {
        await DatabaseService.reserveTable(
          tableNumber: newNum,
          floor: toFloor,
          username: _order!.createdBy,
          orderId: _order!.orderId,
        );
      }

      // Also update any linked reservation if it exists
      if (_linkedReservation != null) {
        try {
          final List<int> tableInts = toTableNumbers
              .map((n) {
                final parsed = int.tryParse(n);
                if (parsed == null) return null;
                // Add offset for second floor tables in reservation system
                return toFloor == 'second' ? parsed + 10 : parsed;
              })
              .whereType<int>()
              .toList();

          await DatabaseService.updateReservationTables(
            _linkedReservation!.id,
            tableInts,
          );
        } catch (e) {
          debugPrint('Note: Linked reservation table update failed: $e');
        }
      }

      // Refresh UI
      _loadOrder();

      if (mounted) {
        unawaited(
          showSuccessToast(
            context,
            'მაგიდა შეიცვალა: ${toTableNumbers.join(", ")}',
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Error changing tables: $error');
      if (!mounted) {
        return;
      }
      await DatabaseService.logError(
        title: 'Order table change failed',
        error: error,
        stackTrace: stackTrace,
        context: 'change_tables',
        performedBy: widget.user.username,
        metadata: {
          'orderId': _order?.orderId,
          'fromTables': fromTables,
          'toTables': toTableNumbers,
        },
      );
      if (!mounted) {
        return;
      }
      unawaited(showErrorToast(context, 'მაგიდის შეცვლა ვერ მოხერხდა'));
    }
  }

  Future<bool> _promptCancellationPassword() async {
    if (!DatabaseService.hasDestructiveActionPassword()) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2B2B2B),
          title: const Text(
            'პაროლი არ არის დაყენებული',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'გაუქმების დასადასტურებელი 6-ნიშნა პაროლი ჯერ არ არის კონფიგურირებული. გთხოვთ, დააყენოთ იგი ადმინის პარამეტრებიდან სანამ სრულ შეკვეთას გააუქმებთ.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'გასაგებია',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String error = '';
        String enteredPin = '';

        void setError(String message, void Function(void Function()) update) {
          update(() {
            error = message;
          });
        }

        bool tryValidate(void Function(void Function()) update) {
          if (enteredPin.length != 6) {
            setError('შეიყვანეთ სრული 6-ნიშნა კოდი.', update);
            return false;
          }
          final ok = DatabaseService.verifyDestructiveActionPassword(
            enteredPin,
          );
          if (ok) {
            Navigator.of(context).pop(true);
            return true;
          }
          update(() {
            error = 'არასწორი კოდი. სცადეთ კიდევ ერთხელ.';
            enteredPin = '';
          });
          return false;
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void addDigit(String digit) {
              if (enteredPin.length >= 6) {
                return;
              }
              setDialogState(() {
                enteredPin += digit;
                error = '';
              });
              if (enteredPin.length == 6) {
                tryValidate(setDialogState);
              }
            }

            void clearPin() {
              setDialogState(() {
                enteredPin = '';
                error = '';
              });
            }

            void deleteDigit() {
              if (enteredPin.isEmpty) {
                return;
              }
              setDialogState(() {
                enteredPin = enteredPin.substring(0, enteredPin.length - 1);
                error = '';
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF2B2B2B),
              title: const Text(
                'გაუქმების პაროლი',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'შეიყვანეთ 6-ნიშნა პაროლი, რათა დაადასტუროთ შეკვეთის სრულად გაუქმება.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      final isFilled = index < enteredPin.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 38,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F1F1F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isFilled
                                ? const Color(0xFFC0AD7B)
                                : const Color(0xFF444444),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            isFilled ? '●' : '',
                            style: const TextStyle(
                              color: Color(0xFFC0AD7B),
                              fontSize: 24,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  PinPad(
                    onDigitPressed: addDigit,
                    onClearPressed: clearPin,
                    onDeletePressed: deleteDigit,
                    showDecimalButton: false,
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'გაუქმება',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => tryValidate(setDialogState),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC0AD7B),
                  ),
                  child: const Text(
                    'დადასტურება',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    return result == true;
  }

  Future<void> _confirmCancelOrder() async {
    if (_order == null) {
      return;
    }

    final passwordConfirmed = widget.user.isAdmin
        ? true
        : await _promptCancellationPassword();
    if (!mounted || _order == null) {
      return;
    }
    if (!passwordConfirmed) {
      return;
    }

    String? comment;
    if (!widget.user.isAdmin) {
      comment = await showDialog<String>(
        context: context,
        builder: (context) => const CommentInputDialog(
          title: 'გაუქმების მიზეზი',
          hint: 'შეიყვანეთ გაუქმების მიზეზი...',
        ),
      );
      if (!mounted || _order == null) {
        return;
      }

      if (comment == null || comment.trim().isEmpty) {
        return;
      }
    }

    final requestTime = DatabaseService.getCurrentDateTime();
    final tablesLabel = _order!.tableNumbers.join(', ');
    final waiterName = widget.user.username;
    final commentText = comment?.trim() ?? '';
    final approvalDescriptor = widget.user.isAdmin
        ? 'Administrator (${widget.user.username})'
        : 'Cancellation PIN Verified';
    final approvedBy = widget.user.isAdmin
        ? widget.user.username
        : 'Cancellation PIN';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 580,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'შეკვეთის გაუქმება',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'შეკვეთა #${_order!.orderId}',
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'მაგიდა: $tablesLabel',
                style: const TextStyle(color: Color(0xFF475569), fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'მოითხოვა: $waiterName • ${requestTime.year.toString().padLeft(4, '0')}-${requestTime.month.toString().padLeft(2, '0')}-${requestTime.day.toString().padLeft(2, '0')} ${requestTime.hour.toString().padLeft(2, '0')}:${requestTime.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'დადასტურება: $approvalDescriptor',
                style: const TextStyle(
                  color: Color(0xFF0F766E),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (commentText.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'მიზეზი:',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  commentText,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'დარწმუნებული ხართ, რომ გსურთ შეკვეთის სრულად გაუქმება?',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'არა',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'დიახ, გაუქმება',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || _order == null) {
      return;
    }

    if (confirmed == true) {
      final cancelledOrder = _order!;
      final logComment = commentText.isEmpty
          ? 'Order cancelled after cancellation password confirmation.'
          : commentText;

      final totalQuantity = _order!.items.fold<int>(
        0,
        (sum, item) => sum + item.quantity,
      );
      final noteParts = <String>[];
      if (logComment.isNotEmpty) {
        noteParts.add(logComment);
      }
      if (approvedBy.trim().isNotEmpty) {
        noteParts.add('Approved by ${approvedBy.trim()}');
      }
      final closerId = (approvedBy.trim().isNotEmpty)
          ? approvedBy.trim()
          : waiterName;
      final cancellationEvent = AuditEvent(
        type: AuditEventType.cancelTable,
        itemName: 'ORDER',
        previousQty: totalQuantity,
        newQty: 0,
        waiterId: waiterName,
        waiterName: waiterName,
        timestamp: DatabaseService.getCurrentDateTime(),
        note: noteParts.join(' • '),
      );

      try {
        await DatabaseService.appendOrderAuditEvents(
          orderId: _order!.orderId,
          events: [cancellationEvent],
          statusOverride: AuditReportStatus.cancelled,
          lockReport: true,
          closedById: closerId,
          closedByName: closerId,
        );
      } catch (e) {
        final message = e.toString().toLowerCase();
        if (!message.contains('locked')) {
          rethrow;
        }
        if (mounted) {
          unawaited(
            showPosToast(
              context: context,
              message: 'აუდიტის ჩანაწერი უკვე დახურულია, გაუქმება გაგრძელდება.',
              style: PosToastStyle.info,
            ),
          );
        }
      }

      final cancelledSaleItems = <OrderItem>[
        ...cancelledOrder.packageItems,
        ...cancelledOrder.items,
      ];
      final cancelledSubtotal = _calculateOrderSubtotal(cancelledOrder);
      final cancelledServiceFee = cancelledOrder.getServiceFee();
      final cancelledClosedAt = DatabaseService.getCurrentDateTime();

      await DatabaseService.saveSaleRecord(
        orderId: cancelledOrder.orderId,
        tableNumbers: cancelledOrder.tableNumbers,
        floor: cancelledOrder.floor,
        items: cancelledSaleItems,
        totalAmount: cancelledOrder.totalAmount,
        paymentMethod: 'cancelled',
        paymentBreakdown: null,
        createdBy: cancelledOrder.createdBy,
        createdAt: cancelledOrder.createdAt,
        closedAt: cancelledClosedAt,
        includeServiceFee: cancelledOrder.includeServiceFee,
        discountAmount: cancelledOrder.discountAmount,
        advanceAmount: 0.0,
        subtotalAmount: cancelledSubtotal,
        manualAdjustmentAmount: cancelledOrder.manualAdjustmentAmount,
        finalTransaction: {
          'type': 'cancelled_order',
          'orderId': cancelledOrder.orderId,
          'subtotal': double.parse(cancelledSubtotal.toStringAsFixed(2)),
          'serviceFee': double.parse(cancelledServiceFee.toStringAsFixed(2)),
          'total': double.parse(cancelledOrder.totalAmount.toStringAsFixed(2)),
          'comment': commentText,
          'isFiscal': false,
        },
        isFiscal: false,
        isCancelled: true,
        cancelledAt: cancelledClosedAt,
      );

      await _updateStatus('cancelled');
    }
  }

  Future<void> _startTableClosureFlow() async {
    if (_order == null) {
      return;
    }

    if (!_canCurrentUserCloseOrder(_order!)) {
      final restrictToOwner = DatabaseService.isTableCloseRestrictedToOwner();
      final errorMessage = restrictToOwner
          ? 'მაგიდის დახურვა შესაძლებელია მხოლოდ მის შემქმნელს'
          : 'მხოლოდ მაგიდის ავტორს ან ადმინისტრატორს შეუძლია დახურვა';
      await showErrorToast(context, errorMessage);
      return;
    }

    final serviceRate = DatabaseService.getServiceFeeRate();
    final freshOrder = DatabaseService.getOrder(widget.orderId);
    if (freshOrder != null) {
      freshOrder.recalculateTotal(serviceFeeRate: serviceRate);
      if (mounted) {
        setState(() {
          _order = freshOrder;
        });
      } else {
        _order = freshOrder;
      }
    } else {
      _order!.recalculateTotal(serviceFeeRate: serviceRate);
    }

    final currentOrder = _order!;
    if (currentOrder.items.isEmpty && currentOrder.packageItems.isEmpty) {
      await showErrorToast(context, 'შეკვეთაში დამატებული პოზიციები არ არის');
      return;
    }

    final paymentService = TablePaymentService(
      context: context,
      total: currentOrder.totalAmount,
    );
    final selection = await paymentService.collect();
    if (selection == null) {
      return;
    }

    await _finalizeTableClosure(currentOrder, selection);
  }

  Future<void> _startNonFiscalClosureFlow() async {
    if (!widget.user.canCloseTablesNonFiscal) {
      unawaited(
        showErrorToast(
          context,
          'არაფისკალური დახურვა მხოლოდ მენეჯერს ან ზედამხედველს შეუძლია',
        ),
      );
      return;
    }

    if (_order == null) {
      return;
    }

    final serviceRate = DatabaseService.getServiceFeeRate();
    final freshOrder = DatabaseService.getOrder(widget.orderId);
    if (freshOrder != null) {
      freshOrder.recalculateTotal(serviceFeeRate: serviceRate);
      if (mounted) {
        setState(() {
          _order = freshOrder;
        });
      } else {
        _order = freshOrder;
      }
    } else {
      _order!.recalculateTotal(serviceFeeRate: serviceRate);
    }

    final currentOrder = _order!;
    if (currentOrder.items.isEmpty && currentOrder.packageItems.isEmpty) {
      await showErrorToast(context, 'შეკვეთაში დამატებული პოზიციები არ არის');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F0F172A),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFFEA580C),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'არაფისკალური დახურვა',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'დახურეთ მაგიდა არაფისკალურად. ეს ოპერაცია არ გამოჩნდება Z რეპორტში, მაგრამ ჩაიწერება გაყიდვების ისტორიაში.',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'გაუქმება',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFFEA580C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'დახურვა და დაფიქსირება',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) {
      return;
    }

    if (confirmed != true) {
      return;
    }

    final autoCashSelection = TablePaymentSelection(
      method: TablePaymentMethod.cash,
      cashAmount: double.parse(currentOrder.totalAmount.toStringAsFixed(2)),
      bankAmount: 0,
    );

    await _finalizeNonFiscalClosure(currentOrder, autoCashSelection);
  }

  Future<void> _finalizeNonFiscalClosure(
    Order order,
    TablePaymentSelection? selection,
  ) async {
    final saleItems = <OrderItem>[...order.packageItems, ...order.items];
    final subtotal = _calculateOrderSubtotal(order);
    final serviceFee = order.getServiceFee();
    final closedAt = DatabaseService.getCurrentDateTime();

    final saleBreakdown = TableClosureHelper.buildSaleBreakdown(selection);
    final finalTransaction = TableClosureHelper.buildFinalTransactionRecord(
      order: order,
      selection: selection,
      paymentBreakdown: saleBreakdown,
      subtotal: subtotal,
      serviceFee: serviceFee,
      closedAt: closedAt,
      isFiscal: false,
    );

    final closeSuccess = await DatabaseService.closeOrderNonFiscal(
      orderId: order.orderId,
      closedById: widget.user.username,
      closedByName: widget.user.username,
    );

    if (!closeSuccess) {
      if (!mounted) {
        return;
      }
      await showErrorToast(context, 'არაფისკალური დახურვა ვერ შესრულდა');
      return;
    }

    await DatabaseService.saveSaleRecord(
      orderId: order.orderId,
      tableNumbers: order.tableNumbers,
      floor: order.floor,
      items: saleItems,
      totalAmount: order.totalAmount,
      paymentMethod: 'non-fiscal',
      paymentBreakdown: saleBreakdown,
      createdBy: order.createdBy,
      createdAt: order.createdAt,
      closedAt: closedAt,
      includeServiceFee: order.includeServiceFee,
      discountAmount: order.discountAmount,
      subtotalAmount: subtotal,
      manualAdjustmentAmount: order.manualAdjustmentAmount,
      finalTransaction: finalTransaction,
      isFiscal: false,
    );

    await DatabaseService.refreshDailySalesTotalForDate(
      DatabaseService.getCurrentDate(),
    );

    final message = TableClosureHelper.buildNonFiscalSuccessMessage();
    if (!mounted) {
      return;
    }

    final resultPayload = <String, dynamic>{
      'status': 'closed',
      'orderId': order.orderId,
      'message': message,
      'isFiscal': false,
    };

    _popToHomeWithResult(resultPayload);
  }

  Future<void> _finalizeTableClosure(
    Order order,
    TablePaymentSelection selection,
  ) async {
    // Recalculate right before persistence to avoid stale totals in sales.
    order.recalculateTotal(serviceFeeRate: DatabaseService.getServiceFeeRate());

    final subtotal = _calculateOrderSubtotal(order);
    final serviceFee = order.getServiceFee();
    final closedAt = DatabaseService.getCurrentDateTime();
    final advanceAmount = order.discountAmount > 0 ? order.discountAmount : 0.0;
    final computedRemainingTotal =
        subtotal + serviceFee + order.manualAdjustmentAmount - advanceAmount;
    final remainingFiscalTotal = double.parse(
      (computedRemainingTotal < 0 ? 0.0 : computedRemainingTotal)
          .toStringAsFixed(2),
    );

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

    if (!closeSuccess) {
      if (!mounted) {
        return;
      }
      await showErrorToast(context, 'შეკვეთის დახურვა ვერ მოხერხდა');
      return;
    }

    await DatabaseService.saveSaleRecord(
      orderId: order.orderId,
      tableNumbers: order.tableNumbers,
      floor: order.floor,
      items: order.items,
      totalAmount: remainingFiscalTotal,
      paymentMethod: paymentMethodKey,
      paymentBreakdown: saleBreakdown,
      createdBy: order.createdBy,
      createdAt: order.createdAt,
      closedAt: closedAt,
      includeServiceFee: order.includeServiceFee,
      discountAmount: 0.0,
      advanceAmount: 0.0,
      subtotalAmount: subtotal,
      manualAdjustmentAmount: order.manualAdjustmentAmount,
      finalTransaction: finalTransaction,
      isFiscal: true,
    );

    if (advanceAmount > 0) {
      await DatabaseService.saveSaleRecord(
        orderId: order.orderId,
        tableNumbers: order.tableNumbers,
        floor: order.floor,
        items: const <OrderItem>[],
        totalAmount: advanceAmount,
        paymentMethod: 'advance',
        paymentBreakdown: {'advance': advanceAmount},
        createdBy: order.createdBy,
        createdAt: order.createdAt,
        closedAt: closedAt,
        includeServiceFee: false,
        discountAmount: 0.0,
        advanceAmount: advanceAmount,
        subtotalAmount: advanceAmount,
        manualAdjustmentAmount: 0.0,
        finalTransaction: {
          'type': 'advance_payment',
          'orderId': order.orderId,
          'amount': double.parse(advanceAmount.toStringAsFixed(2)),
          'source': 'reservation_prepayment',
          'isFiscal': false,
        },
        isFiscal: false,
      );
    }

    await DatabaseService.refreshDailySalesTotalForDate(
      DatabaseService.getCurrentDate(),
    );
    const receiptLanguage = 'ka';

    final receiptLines = _buildFinalReceiptLines(order, selection, closedAt);
    final closePackageSubtotal = order.getPackageSubtotal();
    final closeAdditionalSubtotal = order.getAdditionalItemsSubtotal();
    final closeTableNumber = _isTakeAway(order)
        ? null
        : order.tableNumbers.join(', ');

    PrinterService.printReceiptInBackground(
      items: receiptLines,
      total: remainingFiscalTotal,
      subtotal: null,
      serviceFee: null,
      // Close-table receipt keeps service in total but does not print service row.
      includeServiceFee: false,
      tableNumber: closeTableNumber,
      orderNumber: order.orderId.toString(),
      paymentMethod: paymentMethodKey,
      language: receiptLanguage,
      packageSubtotal: closePackageSubtotal > 0 ? closePackageSubtotal : null,
      additionalSubtotal: closeAdditionalSubtotal > 0
          ? closeAdditionalSubtotal
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

    final message = TableClosureHelper.buildSuccessMessage(selection);
    final resultPayload = <String, dynamic>{
      'status': 'closed',
      'orderId': order.orderId,
      'message': message,
    };

    _popWithResult(resultPayload);
  }

  double _calculateOrderSubtotal(Order order) {
    final packageSubtotal = order.getPackageSubtotal();
    final additionalSubtotal = order.getAdditionalItemsSubtotal();
    return double.parse(
      (packageSubtotal + additionalSubtotal).toStringAsFixed(2),
    );
  }

  List<String> _buildFinalReceiptLines(
    Order order,
    TablePaymentSelection selection,
    DateTime closedAt,
  ) {
    final lines = <String>[
      'Order #${order.orderId}',
      'სუფრა: ${order.tableNumbers.join(', ')}',
      'დახურვა: ${_formatClosureTimestamp(closedAt)}',
      ..._buildReceiptItemLines(order),
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

  List<String> _buildReceiptItemLines(Order order) {
    final lines = <String>[];

    if (order.packageItems.isNotEmpty) {
      final packageLabel = (order.packageName ?? '').trim().isNotEmpty
          ? order.packageName!.trim()
          : 'პაკეტი';
      lines.add('[$packageLabel]');
      for (final packageItem in order.packageItems) {
        final localized = _getItemNameForLanguage(packageItem.itemName, 'ka');
        var line =
            '${packageItem.quantity}x $localized - ₾${packageItem.total.toStringAsFixed(2)}';
        final comment = packageItem.comment?.trim();
        if (comment != null && comment.isNotEmpty) {
          line += '\n  ⮑ $comment';
        }
        lines.add(line);
      }
      if (order.items.isNotEmpty) {
        lines.add('---');
        lines.add('[დამატება / Additional]');
      }
    }

    for (final item in order.items) {
      final localized = _getItemNameForLanguage(item.itemName, 'ka');
      var line =
          '${item.quantity}x $localized - ₾${item.total.toStringAsFixed(2)}';
      final comment = item.comment?.trim();
      if (comment != null && comment.isNotEmpty) {
        line += '\n  ⮑ $comment';
      }
      lines.add(line);
    }

    return lines;
  }

  String _formatClosureTimestamp(DateTime value) {
    final local = value;
    final datePart =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final timePart =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$datePart $timePart';
  }

  List<String> _buildKitchenCheckLines(Order order) {
    final lines = <String>[];

    if (order.packageItems.isNotEmpty) {
      final hasPackageName =
          order.packageName != null && order.packageName!.trim().isNotEmpty;
      final packageLabel = hasPackageName
          ? order.packageName!.trim()
          : 'პაკეტი';
      lines.add('[$packageLabel]');

      for (final packageItem in order.packageItems) {
        final localizedName = _getItemNameForLanguage(
          packageItem.itemName,
          'ka',
        );
        var itemStr = '${packageItem.quantity}x $localizedName';
        if (packageItem.comment != null &&
            packageItem.comment!.trim().isNotEmpty) {
          itemStr += '\n  ⮑ ${packageItem.comment}';
        }
        lines.add(itemStr);
      }

      if (order.items.isNotEmpty) {
        lines.add('---');
      }
    }

    for (final item in order.items) {
      final localizedName = _getItemNameForLanguage(item.itemName, 'ka');
      var itemStr = '${item.quantity}x $localizedName';
      if (item.comment != null && item.comment!.trim().isNotEmpty) {
        itemStr += '\n  ⮑ ${item.comment}';
      }
      lines.add(itemStr);
    }

    return lines;
  }

  Future<void> _printKitchenCheck() async {
    if (_order == null) {
      return;
    }

    final kitchenItems = _buildKitchenCheckLines(_order!);
    if (kitchenItems.isEmpty) {
      unawaited(
        showPosToast(
          context: context,
          message: 'სამზარეულოს ჩეკისთვის პროდუქტები არ არის დამატებული.',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    PrinterService.printKitchenCheckInBackground(
      items: kitchenItems,
      tableNumber: OrderDetailCommonHelpers.kitchenTableLabel(_order!),
      orderNumber: _order!.orderId.toString(),
      waiterName: _order!.createdBy,
      createdAt: _order!.createdAt,
      onComplete: (success) {
        if (!mounted) return;
        if (success) {
          unawaited(
            showSuccessToast(context, 'სამზარეულოს სრული ჩეკი დაიბეჭდა'),
          );
        } else {
          unawaited(showErrorToast(context, 'პრინტერი მიუწვდომელია'));
        }
      },
    );
  }

  Future<void> _updateStatus(String newStatus) async {
    // Update order status in database
    await DatabaseService.updateOrderStatus(
      orderId: widget.orderId,
      status: newStatus,
    );

    // Update associated reservation status
    if (newStatus == 'cancelled' && _order != null) {
      // Mark reservation as cancelled
      final currentDate = DatabaseService.getCurrentDate();
      final dateString = currentDate.toIso8601String().split('T')[0];

      final allReservations = DatabaseService.getAllReservations();
      for (var reservation in allReservations) {
        final resDateString = reservation.reservationDate
            .toIso8601String()
            .split('T')[0];
        if (resDateString == dateString &&
            reservation.notes != null &&
            reservation.notes!.contains('Order #${widget.orderId}')) {
          await DatabaseService.updateReservationStatus(
            reservation.id,
            'cancelled',
          );
          break;
        }
      }
    }

    // If confirming order, print kitchen check (instant, non-blocking)
    if (newStatus == 'confirmed' && _order != null) {
      final kitchenItems = _buildKitchenCheckLines(_order!);
      if (kitchenItems.isNotEmpty) {
        PrinterService.printKitchenCheckInBackground(
          items: kitchenItems,
          tableNumber: OrderDetailCommonHelpers.kitchenTableLabel(_order!),
          orderNumber: _order!.orderId.toString(),
          waiterName: _order!.createdBy,
          createdAt: _order!.createdAt,
          onComplete: (success) {
            if (!mounted) return;
            if (success) {
              unawaited(showSuccessToast(context, 'სამზარეულოს ჩეკი დაიბეჭდა'));
            } else {
              unawaited(showErrorToast(context, 'პრინტერი მიუწვდომელია'));
            }
          },
        );
      }
    }

    _loadOrder();

    // After cancellation, return to previous screen using the same payload
    // shape as table-close flows so parent screens handle it consistently.
    final normalizedStatus = newStatus.toLowerCase();
    if (normalizedStatus == 'cancelled') {
      _popToHomeWithResult(<String, dynamic>{
        'status': 'closed',
        'orderId': widget.orderId,
        'message': 'შეკვეთა გაუქმდა',
        'isFiscal': false,
      });
      return;
    }

    if (normalizedStatus == 'paid') {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _editOrder() {
    if (_order != null) {
      if (!_canCurrentUserModifyOrder(_order!)) {
        unawaited(
          showPosToast(
            context: context,
            message: 'ამ მაგიდის ცვლილება მხოლოდ შემქმნელს შეუძლია.',
            style: PosToastStyle.info,
          ),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MenuScreen(
            user: widget.user,
            selectedTables: _order!.tableNumbers,
            existingOrderId: widget.orderId,
          ),
        ),
      ).then((_) => _loadOrder());
    }
  }

  static const List<String> _kaMonths = [
    'იანვარი',
    'თებერვალი',
    'მარტი',
    'აპრილი',
    'მაისი',
    'ივნისი',
    'ივლისი',
    'აგვისტო',
    'სექტემბერი',
    'ოქტომბერი',
    'ნოემბერი',
    'დეკემბერი',
  ];

  int? get _guestCount {
    final reservationGuests = _linkedReservation?.numberOfGuests ?? 0;
    if (reservationGuests > 0) {
      return reservationGuests;
    }
    if (_order != null && _order!.packageGuestCount > 0) {
      return _order!.packageGuestCount;
    }
    return null;
  }

  String? get _reservationScheduleLabelKa {
    final reservation = _linkedReservation;
    if (reservation == null) {
      return null;
    }
    final time = reservation.reservationTime.trim();
    if (_isTakeAwayOrder) {
      return time.isEmpty ? null : time;
    }
    final date = reservation.reservationDate;
    final base = '${date.day} ${_kaMonths[date.month - 1]}, ${date.year}';
    return time.isEmpty ? base : '$base, $time';
  }

  Future<void> _updateReservationGuests(int guests) async {
    final reservation = _linkedReservation;
    if (reservation == null || guests < 1) {
      return;
    }
    reservation.numberOfGuests = guests;
    await reservation.save();
    if (!mounted) {
      return;
    }
    _loadOrder();
  }


  @override
  Widget build(BuildContext context) {
    if (_order == null) {
      return Scaffold(
        backgroundColor: _surfaceColor,
        appBar: AppBar(
          backgroundColor: _panelColor,
          foregroundColor: _titleColor,
          elevation: 0,
          title: const Text('Order Not Found'),
        ),
        body: const Center(
          child: Text('Order not found', style: TextStyle(fontSize: 18)),
        ),
      );
    }

    final status = _order!.status;
    final bool canPrintReceipt =
        status == 'confirmed' ||
        status == 'preparing' ||
        status == 'served' ||
        _isFinalizedStatus(status);
    final bool canPrintKitchenCheck =
        (_order!.items.isNotEmpty || _order!.packageItems.isNotEmpty) &&
        status != 'cancelled';
    final bool canEditOrder =
        !_isFinalizedStatus(status) && _canCurrentUserModifyOrder(_order!);
    final actionsBundle = _resolveOrderActions(
      status: status,
      canPrintKitchenCheck: canPrintKitchenCheck,
      canPrintReceipt: canPrintReceipt,
    );

    final bool canModify =
        !_isFinalizedStatus(status) && _canCurrentUserModifyOrder(_order!);
    final bool canEditReservation =
        !_isTakeAwayOrder && _linkedReservation != null;

    return Scaffold(
      backgroundColor: _surfaceColor,
      body: Column(
        children: [
          OrderDetailHeaderSection(
            order: _order!,
            isTakeAwayOrder: _isTakeAwayOrder,
            guestCount: _guestCount,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      child: OrderDetailDetailsPanel(
                        order: _order!,
                        isTakeAwayOrder: _isTakeAwayOrder,
                        hasReservation: _linkedReservation != null,
                        customerName: _reservationCustomerName,
                        customerPhone: _reservationCustomerPhone,
                        scheduleLabel: _reservationScheduleLabelKa,
                        guestCount: _guestCount,
                        notes: _reservationNotesLabel,
                        onEditReservation: canEditReservation
                            ? _editLinkedReservationDetails
                            : null,
                        onGuestsChanged: canModify && canEditReservation
                            ? _updateReservationGuests
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OrderDetailContentSection(
                      order: _order!,
                      canModify: canModify,
                      isAdmin: widget.user.isAdmin,
                      highlightItemKeys: _mobileHighlightItemKeys,
                      onOrderUpdated: () async {
                        _loadOrder();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          OrderDetailActionsPanel(
            order: _order!,
            actionsBundle: actionsBundle,
            serviceFeePercentageLabel: _serviceFeeLabelForOrder(_order!),
            onEditOrder: _editOrder,
            canEditOrder: canEditOrder,
            otherActionsProvider: () {
              final refreshedBundle = _resolveOrderActions(
                status: _order?.status ?? status,
                canPrintKitchenCheck: canPrintKitchenCheck,
                canPrintReceipt: canPrintReceipt,
              );
              final merged = <OrderActionConfig>[
                ...refreshedBundle.primary,
                ...refreshedBundle.secondary,
              ];
              merged.removeWhere(
                (action) =>
                    action.label == 'მაგიდის დახურვა' ||
                    action.label == 'ქვითრის ბეჭდვა' ||
                    action.label == 'სხვა',
              );
              return merged;
            },
          ),
        ],
      ),
    );
  }
}
