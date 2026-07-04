import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/windows_pos/screens/menu_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_calculator_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservation_table_assignment_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/service_fee_adjust_dialog.dart';
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
      onPrintDraft: _printQuickOrderDraft,
      onItemQuantityChanged: _changeQuickOrderItemQuantity,
      serviceFeeAvailable: DatabaseService.isServiceFeeAvailable(),
      canManageDrafts: widget.user.canManageMenuCountDrafts,
      onOpenDraftManage: _openDraftManageModal,
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

    PrinterService.printReceiptInBackground(
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
              isEnglish ? 'Receipt printed' : 'ჩეკი დაიბეჭდა',
            ),
          );
        } else {
          unawaited(
            showErrorToast(
              context,
              isEnglish ? 'Printer unavailable' : 'პრინტერი მიუწვდომელია',
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
    showDialog(
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

    final result = await showDialog<ServiceFeeAdjustResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ServiceFeeAdjustDialog(
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
    return showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierLabel: title,
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

  Future<Map<String, dynamic>?> _showQuickOrderConfirmationDialog() async {
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
    );
  }

  Future<void> _confirmQuickOrderDraft(QuickOrderDraft draft) async {
    final result = await _showQuickOrderConfirmationDialog();
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

    final tableNumbers = await HomeReservationTableAssignmentDialog.show(
      context: context,
      reservationDate: selectedDate,
      reservationTime: timeString,
      primaryColor: widget.primaryColor,
      secondaryColor: widget.secondaryColor,
      textPrimary: widget.textPrimary,
    );
    if (!mounted || tableNumbers == null || tableNumbers.isEmpty) {
      return;
    }

    await DatabaseService.createReservation(
      customerName: customerName,
      customerPhone: customerPhone,
      tableNumbers: tableNumbers,
      reservationDate: selectedDate,
      reservationTime: timeString,
      numberOfGuests: guests,
      notes: notes,
      createdBy: widget.user.username,
      preOrderItems: draft.items,
      status: 'confirmed',
    );

    await DatabaseService.deleteQuickOrderDraft(draft.id);

    if (!mounted) {
      return;
    }

    setState(() {});
    unawaited(
      showSuccessToast(context, 'რეზერვაცია შექმნილია და დამატებულია სიაში'),
    );
  }

  Future<void> _deleteQuickOrderDraft(String id) async {
    final confirmed = await showDialog<bool>(
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
    if (!widget.user.canManageMenuCountDrafts) {
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

    final confirmed = await showDialog<bool>(
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

  Future<void> _openDraftManageModal(QuickOrderDraft draft) async {
    if (!widget.user.canManageMenuCountDrafts) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        return _DraftManagementDialog(
          draft: draft,
          onConfirm: () {
            Navigator.pop(dialogContext);
            unawaited(_confirmQuickOrderDraft(draft));
          },
          onRename: () {
            return _renameQuickOrderDraft(draft);
          },
          onPreview: () {
            Navigator.pop(dialogContext);
            unawaited(_viewQuickOrderDraftReceipt(draft));
          },
          onDelete: () {
            Navigator.pop(dialogContext);
            unawaited(_deleteQuickOrderDraft(draft.id));
          },
        );
      },
    );
  }

  Future<String?> _openQuickOrderNameKeyboardSheet(
    TextEditingController controller,
  ) async {
    return showPosKeyboardInputSheet(
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

class _DraftManagementDialog extends StatefulWidget {
  const _DraftManagementDialog({
    required this.draft,
    required this.onConfirm,
    required this.onRename,
    required this.onPreview,
    required this.onDelete,
  });

  final QuickOrderDraft draft;
  final VoidCallback onConfirm;
  final Future<String?> Function() onRename;
  final VoidCallback onPreview;
  final VoidCallback onDelete;

  @override
  State<_DraftManagementDialog> createState() => _DraftManagementDialogState();
}

class _DraftManagementDialogState extends State<_DraftManagementDialog> {
  late String _title;

  @override
  void initState() {
    super.initState();
    _title = _resolveTitle(widget.draft.displayName);
  }

  String _resolveTitle(String? value) {
    final normalized = value?.trim();
    return normalized?.isNotEmpty == true ? normalized! : 'დათვლილი მენიუ';
  }

  Future<void> _rename() async {
    final value = await widget.onRename();
    if (value == null || !mounted) return;
    setState(() => _title = _resolveTitle(value));
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.draft.items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDDE4ED)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x260F172A),
                blurRadius: 32,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF4FB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        color: Color(0xFF075E6B),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF102033),
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$itemCount პროდუქტი  •  ${widget.draft.total.toStringAsFixed(2)} ₾',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'დახურვა',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 16, 22, 10),
                child: Text(
                  'მენიუს მართვა',
                  style: TextStyle(
                    color: Color(0xFF102033),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.7,
                  children: [
                    _DraftManagementAction(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'დადასტურება',
                      subtitle: 'რეზერვაციაში გადატანა',
                      color: const Color(0xFF16A34A),
                      onTap: widget.onConfirm,
                    ),
                    _DraftManagementAction(
                      icon: Icons.drive_file_rename_outline_rounded,
                      title: 'სახელის შეცვლა',
                      subtitle: 'მენიუს დასახელება',
                      color: const Color(0xFF1E3A8A),
                      onTap: () => unawaited(_rename()),
                    ),
                    _DraftManagementAction(
                      icon: Icons.visibility_outlined,
                      title: 'ნახვა / PDF',
                      subtitle: 'ქვითრის წინასწარი ნახვა',
                      color: const Color(0xFF0F766E),
                      onTap: widget.onPreview,
                    ),
                    _DraftManagementAction(
                      icon: Icons.delete_outline_rounded,
                      title: 'წაშლა',
                      subtitle: 'მენიუს სამუდამოდ წაშლა',
                      color: const Color(0xFFDC2626),
                      onTap: widget.onDelete,
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

class _DraftManagementAction extends StatelessWidget {
  const _DraftManagementAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.055),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF102033),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}
