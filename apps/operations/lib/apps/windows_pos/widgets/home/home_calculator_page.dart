import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/windows_pos/screens/menu_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_calculator_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservation_table_assignment_dialog.dart';
import 'package:vynic/core/widgets/service_fee_adjust_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/receipt_language_picker_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/receipt_preview_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';

class HomeCalculatorPage extends StatefulWidget {
  const HomeCalculatorPage({
    super.key,
    required this.user,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
    this.hideTitle = false,
  });

  final User user;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;
  final bool hideTitle;

  @override
  State<HomeCalculatorPage> createState() => _HomeCalculatorPageState();
}

class _HomeCalculatorPageState extends State<HomeCalculatorPage> {
  bool _draftActionRunning = false;

  Future<void> _runDraftAction(Future<void> Function() action) async {
    if (_draftActionRunning) return;
    _draftActionRunning = true;
    try {
      await action();
    } finally {
      _draftActionRunning = false;
    }
  }

  final TextEditingController _quickOrderGuestsController =
      TextEditingController(text: '2');

  @override
  void dispose() {
    _quickOrderGuestsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quickOrderDrafts = DatabaseService.getQuickOrderDrafts();
    return HomeCalculatorSection(
      quickOrderDrafts: quickOrderDrafts,
      onStartQuickOrder: _openQuickOrder,
      onToggleServiceFee: _toggleQuickOrderServiceFee,
      onOpenServiceFeeConfig: _openQuickOrderServiceFeeConfig,
      onContinueDraft: _openQuickOrderDraft,
      onPrintDraft: (draft) =>
          _runDraftAction(() => _printQuickOrderDraft(draft)),
      onItemQuantityChanged: _changeQuickOrderItemQuantity,
      serviceFeeAvailable: DatabaseService.isServiceFeeAvailable(),
      canManageDrafts: widget.user.canManageMenuCountDrafts,
      canDeleteDrafts: widget.user.canDeleteMenuCountDrafts,
      onConfirmDraft: (draft) =>
          _runDraftAction(() => _confirmQuickOrderDraft(draft)),
      onRenameDraft: (draft) => _runDraftAction(() async {
        await _renameQuickOrderDraft(draft);
      }),
      onPreviewDraft: (draft) =>
          _runDraftAction(() => _viewQuickOrderDraftReceipt(draft)),
      onDeleteDraft: (draft) =>
          _runDraftAction(() => _deleteQuickOrderDraft(draft.id)),
      onClearAllDrafts: _clearAllQuickOrderDrafts,
      primaryColor: widget.primaryColor,
      secondaryColor: widget.secondaryColor,
      textPrimary: widget.textPrimary,
      mutedText: widget.mutedText,
      hideTitle: widget.hideTitle,
    );
  }

  Future<void> _changeQuickOrderItemQuantity(
    QuickOrderDraft draft,
    OrderItem item,
    int quantity,
  ) async {
    try {
      final nextItems = draft.items
          .where((entry) => entry.itemKey != item.itemKey || quantity > 0)
          .map((entry) {
            if (entry.itemKey != item.itemKey) return entry.clone();
            return OrderItem(
              itemKey: entry.itemKey,
              itemName: entry.itemName,
              unitPrice: entry.unitPrice,
              quantity: quantity,
              total: double.parse(
                (entry.unitPrice * quantity).toStringAsFixed(2),
              ),
              comment: entry.comment,
              menuItemId: entry.menuItemId,
              variantId: entry.variantId,
            );
          })
          .toList();

      final subtotal = nextItems.fold<double>(
        0,
        (sum, entry) => sum + entry.total,
      );

      await DatabaseService.updateQuickOrderDraft(
        id: draft.id,
        createdBy: draft.createdBy,
        items: nextItems,
        subtotal: subtotal,
        includeServiceFee: draft.includeServiceFee,
        serviceFeeRate: draft.serviceFeeRate,
      );

      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      unawaited(
        showErrorToast(context, 'რაოდენობის განახლება ვერ მოხერხდა: $error'),
      );
    }
  }

  Future<void> _printQuickOrderDraft(QuickOrderDraft draft) async {
    if (draft.items.isEmpty) {
      if (mounted) {
        unawaited(
          showErrorToast(context, 'ჩეკის დასაბეჭდად ჩანაწერები არ მოიძებნა'),
        );
      }
      return;
    }

    final language = await ReceiptLanguagePickerDialog.show(context);
    if (language == null) {
      return;
    }

    final isEnglish = language == 'en';
    final lines = <String>['---'];

    for (final item in draft.items) {
      final displayName = _resolveQuickOrderItemName(item.itemName, language);
      lines.add(
        '${item.quantity}x $displayName - ${item.total.toStringAsFixed(2)} GEL',
      );
      final comment = item.comment?.trim();
      if (comment != null && comment.isNotEmpty) {
        lines.add('  ⮑ $comment');
      }
    }

    final includeService =
        DatabaseService.isServiceFeeAvailable() &&
        draft.includeServiceFee &&
        draft.serviceFeeAmount > 0.0;
    final receiptTotal = includeService ? draft.total : draft.subtotal;

    await PrinterService.printReceiptInBackground(
      items: lines,
      total: receiptTotal,
      subtotal: draft.subtotal,
      serviceFee: includeService ? draft.serviceFeeAmount : null,
      includeServiceFee: includeService,
      language: language,
      receiptType: 'menu_count',
      onComplete: (success) {
        if (!mounted) {
          return;
        }
        if (success) {
          unawaited(
            showSuccessToast(
              context,
              isEnglish
                  ? 'Sent to printer — check paper'
                  : 'გაიგზავნა პრინტერზე — შეამოწმეთ ქაღალდი',
            ),
          );
        } else {
          unawaited(
            showErrorToast(
              context,
              isEnglish
                  ? 'Printing unconfirmed — review print jobs'
                  : 'ბეჭდვა ვერ დადასტურდა — შეამოწმეთ ბეჭდვის სია',
            ),
          );
        }
      },
    );
  }

  Future<void> _viewQuickOrderDraftReceipt(QuickOrderDraft draft) async {
    if (draft.items.isEmpty) {
      if (mounted) {
        unawaited(
          showErrorToast(context, 'ჩეკის სანახავად ჩანაწერები არ მოიძებნა'),
        );
      }
      return;
    }

    final language = await ReceiptLanguagePickerDialog.show(context);
    if (language == null) {
      return;
    }

    final lines = <String>['---'];
    for (final item in draft.items) {
      final displayName = _resolveQuickOrderItemName(item.itemName, language);
      lines.add(
        '${item.quantity}x $displayName - ${item.total.toStringAsFixed(2)} GEL',
      );
      final comment = item.comment?.trim();
      if (comment != null && comment.isNotEmpty) {
        lines.add('  ⮑ $comment');
      }
    }

    final includeService =
        DatabaseService.isServiceFeeAvailable() &&
        draft.includeServiceFee &&
        draft.serviceFeeAmount > 0.0;
    final receiptTotal = includeService ? draft.total : draft.subtotal;

    if (!mounted) return;

    // Show loading indicator
    showPosModal(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pngBytes = await PrinterService.generateReceiptPngBytes(
        items: lines,
        total: receiptTotal,
        subtotal: draft.subtotal,
        serviceFee: includeService ? draft.serviceFeeAmount : null,
        includeServiceFee: includeService,
        language: language,
        receiptType: 'menu_count',
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close loading indicator
      }

      if (pngBytes != null && mounted) {
        await ReceiptPreviewDialog.show(context, pngBytes);
      } else if (mounted) {
        unawaited(showErrorToast(context, 'ჩეკის გენერაცია ვერ მოხერხდა'));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading indicator
        unawaited(showErrorToast(context, 'შეცდომა: $e'));
      }
    }
  }

  Future<void> _toggleQuickOrderServiceFee(QuickOrderDraft draft) async {
    if (!DatabaseService.isServiceFeeAvailable()) return;
    final newInclude = !draft.includeServiceFee;
    final serviceFeeRate = draft.serviceFeeRate > 0
        ? draft.serviceFeeRate
        : DatabaseService.getServiceFeeRate();
    try {
      await DatabaseService.updateQuickOrderDraft(
        id: draft.id,
        createdBy: draft.createdBy,
        items: draft.items,
        subtotal: draft.subtotal,
        includeServiceFee: newInclude,
        serviceFeeRate: serviceFeeRate,
      );
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (e) {
      if (!mounted) {
        return;
      }
      unawaited(
        showErrorToast(
          context,
          'სერვისის საფასურის განახლება ვერ მოხერხდა: $e',
        ),
      );
    }
  }

  Future<void> _openQuickOrderServiceFeeConfig(QuickOrderDraft draft) async {
    if (!DatabaseService.isServiceFeeAvailable()) return;
    final defaultPercent = DatabaseService.getServiceFeePercentage();
    final initialPercent = (draft.serviceFeeRate * 100).clamp(0.0, 100.0);

    final result = await showPosModal<ServiceFeeAdjustResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ServiceFeeAdjustDialog(
        usePosLayout: true,
        initialIncludeServiceFee: draft.includeServiceFee,
        initialPercentage: initialPercent,
        defaultPercentage: defaultPercent,
      ),
    );

    if (result == null) {
      return;
    }

    final normalizedPercent = double.parse(
      result.percentage.clamp(0.0, 100.0).toStringAsFixed(2),
    );
    final nextRate = normalizedPercent / 100;

    final changed =
        result.includeServiceFee != draft.includeServiceFee ||
        (draft.serviceFeeRate - nextRate).abs() > 0.00009;
    if (!changed) {
      return;
    }

    try {
      await DatabaseService.updateQuickOrderDraft(
        id: draft.id,
        createdBy: draft.createdBy,
        items: draft.items,
        subtotal: draft.subtotal,
        includeServiceFee: result.includeServiceFee,
        serviceFeeRate: nextRate,
      );
      if (!mounted) {
        return;
      }
      setState(() {});
      unawaited(showSuccessToast(context, 'სერვისის პარამეტრები განახლდა'));
    } catch (e) {
      if (!mounted) {
        return;
      }
      unawaited(
        showErrorToast(
          context,
          'სერვისის პარამეტრების განახლება ვერ მოხერხდა: $e',
        ),
      );
    }
  }

  String _resolveQuickOrderItemName(String originalName, String language) {
    final trimmedOriginal = originalName.trim();
    if (trimmedOriginal.isEmpty) {
      return originalName;
    }

    final targetLanguage = language == 'en' ? 'en' : 'ka';

    try {
      final categories = DatabaseService.getAllMenuCategories();
      for (final category in categories) {
        final localized = _findLocalizedQuickMenuName(
          category.items,
          trimmedOriginal,
          targetLanguage,
        );
        if (localized != null) {
          return localized;
        }

        if (category.subcategories != null) {
          for (final subcategory in category.subcategories!) {
            final subLocalized = _findLocalizedQuickMenuName(
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
    } catch (e) {
      debugPrint('Error resolving quick order item name: $e');
    }

    return originalName;
  }

  String? _findLocalizedQuickMenuName(
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

      if (_quickOrderItemNameMatches(original, nameKa)) {
        return _composeLocalizedQuickMenuName(
          baseKa: nameKa,
          baseEn: nameEn,
          targetLanguage: targetLanguage,
          original: original,
          matchedBase: nameKa,
        );
      }

      if (_quickOrderItemNameMatches(original, nameEn)) {
        return _composeLocalizedQuickMenuName(
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

  bool _quickOrderItemNameMatches(String original, String candidate) {
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

  String _composeLocalizedQuickMenuName({
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
    return ReservationCreationSheet.show(
      context,
      form: ReservationCreationSheet(
        title: title,
        confirmLabel: confirmLabel,
        initialName: initialName,
        initialPhone: initialPhone,
        initialNotes: initialNotes,
        initialDate: initialDate,
        initialTime: initialTime,
        initialGuests: initialGuests,
      ),
    );
  }

  Future<Map<String, dynamic>?> _showQuickOrderConfirmationDialog(
    QuickOrderDraft draft,
  ) async {
    final int? initialGuests = int.tryParse(
      _quickOrderGuestsController.text.trim(),
    );
    final DateTime initialDate = DatabaseService.getCurrentDate().add(
      const Duration(days: 1),
    );

    return _showReservationSheet(
      title: 'რეზერვაციის დადასტურება',
      confirmLabel: 'დადასტურება',
      initialDate: initialDate,
      initialGuests: initialGuests,
      initialName: draft.customerName,
      initialPhone: draft.customerPhone,
    );
  }

  Future<void> _confirmQuickOrderDraft(QuickOrderDraft draft) async {
    if (!widget.user.canManageMenuCountDrafts) return;
    final result = await _showQuickOrderConfirmationDialog(draft);
    if (result == null) {
      return;
    }

    final selectedDate = result['date'] as DateTime;
    final selectedTime = result['time'] as TimeOfDay;
    final guests =
        result['numberOfGuests'] as int? ?? result['guests'] as int? ?? 0;
    final customerName =
        (result['customerName'] as String?)?.trim().isNotEmpty == true
        ? (result['customerName'] as String).trim()
        : 'Quick Order';
    final customerPhone =
        (result['customerPhone'] as String?)?.trim().isNotEmpty == true
        ? (result['customerPhone'] as String).trim()
        : '-';
    final userNotes = (result['notes'] as String?)?.trim();
    final timeString =
        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

    final notes = (userNotes != null && userNotes.isNotEmpty)
        ? userNotes
        : null;

    _quickOrderGuestsController.text = guests > 0 ? '$guests' : '';

    if (!mounted) {
      return;
    }

    final tableRefs = await HomeReservationTableAssignmentDialog.show(
      context: context,
      reservationDate: selectedDate,
      reservationTime: timeString,
      primaryColor: widget.primaryColor,
      secondaryColor: widget.secondaryColor,
      textPrimary: widget.textPrimary,
    );
    if (!mounted || tableRefs == null || tableRefs.isEmpty) {
      return;
    }

    try {
      await DatabaseService.createReservation(
        customerName: customerName,
        customerPhone: customerPhone,
        tableRefs: tableRefs,
        reservationDate: selectedDate,
        reservationTime: timeString,
        numberOfGuests: guests,
        notes: notes,
        createdBy: widget.user.username,
        preOrderItems: draft.items,
        status: result['status'] as String? ?? 'confirmed',
        advanceAmount: result['advanceAmount'] as double? ?? 0,
        id: result['id'] as String?,
      );
    } catch (error) {
      if (mounted)
        unawaited(showErrorToast(context, 'რეზერვაცია ვერ შეიქმნა: $error'));
      return;
    }

    // Converting an estimate is not deletion. Keep it available for reference;
    // only an authenticated manager can explicitly remove it.

    if (!mounted) {
      return;
    }

    setState(() {});
    unawaited(
      showSuccessToast(context, 'რეზერვაცია შექმნილია და დამატებულია სიაში'),
    );
  }

  Future<void> _deleteQuickOrderDraft(String id) async {
    if (!(PosSession.user ?? widget.user).canDeleteMenuCountDrafts) return;
    final confirmed = await showPosModal<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('მენიუს წაშლა'),
        content: const Text('ნამდვილად გსურთ ამ დათვლილი მენიუს წაშლა?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await DatabaseService.deleteQuickOrderDraft(id);
    if (!mounted) {
      return;
    }
    setState(() {});
    unawaited(
      showPosToast(
        context: context,
        message: 'შენახული მენიუ წაიშალა.',
        style: PosToastStyle.info,
      ),
    );
  }

  Future<void> _clearAllQuickOrderDrafts() async {
    if (!(PosSession.user ?? widget.user).canDeleteMenuCountDrafts) {
      return;
    }

    final drafts = DatabaseService.getQuickOrderDrafts();
    if (drafts.isEmpty) {
      if (!mounted) {
        return;
      }
      unawaited(
        showPosToast(
          context: context,
          message: 'შენახული მენიუები არ მოიძებნა.',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    final confirmed = await showPosModal<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ყველას წაშლა'),
        content: Text(
          'ნამდვილად გსურთ ყველა დათვლილი მენიუს წაშლა? (${drafts.length})',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await DatabaseService.clearQuickOrderDrafts();
    if (!mounted) {
      return;
    }
    setState(() {});
    unawaited(
      showPosToast(
        context: context,
        message: 'ყველა შენახული მენიუ წაიშალა.',
        style: PosToastStyle.info,
      ),
    );
  }

  Future<String?> _renameQuickOrderDraft(QuickOrderDraft draft) async {
    if (!widget.user.canManageMenuCountDrafts) {
      return null;
    }

    final controller = TextEditingController(text: draft.displayName ?? '');
    final initialTextLength = controller.text.length;
    controller.selection = TextSelection.collapsed(offset: initialTextLength);

    final value = await _openQuickOrderNameKeyboardSheet(controller);
    controller.dispose();

    if (value == null) {
      return null;
    }

    await DatabaseService.setQuickOrderDraftDisplayName(
      id: draft.id,
      displayName: value,
    );
    if (!mounted) {
      return value;
    }
    draft.displayName = value.trim().isEmpty ? null : value.trim();
    setState(() {});
    return value;
  }

  Future<String?> _openQuickOrderNameKeyboardSheet(
    TextEditingController controller,
  ) async {
    return showPosKeyboardInputSheet(
      standalone: true,
      context: context,
      controller: controller,
      initialLanguage: PosKeyboardLanguage.fromCode(
        DatabaseService.getDefaultLanguage(),
      ),
      title: 'მენიუს სახელის შეცვლა',
    );
  }

  void _openQuickOrderDraft(QuickOrderDraft draft) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MenuScreen(
          user: widget.user,
          selectedTables: [],
          isQuickOrder: true,
          initialQuickOrderDraftId: draft.id,
        ),
      ),
    ).then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _openQuickOrder() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MenuScreen(
          user: widget.user,
          selectedTables: [],
          isQuickOrder: true,
        ),
      ),
    ).then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }
}
