import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/windows_pos/screens/menu_screen.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printer_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_calculator_section.dart';
import 'package:vynic/apps/windows_pos/widgets/on_screen_keyboard.dart';
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

    final includeService = DatabaseService.isServiceFeeAvailable() &&
        draft.includeServiceFee &&
        draft.serviceFeeAmount > 0.0;
    final receiptTotal =
        includeService ? draft.total : draft.subtotal;

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

    final includeService = DatabaseService.isServiceFeeAvailable() &&
        draft.includeServiceFee &&
        draft.serviceFeeAmount > 0.0;
    final receiptTotal =
        includeService ? draft.total : draft.subtotal;

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
    try {
      await DatabaseService.updateQuickOrderDraft(
        id: draft.id,
        createdBy: draft.createdBy,
        items: draft.items,
        subtotal: draft.subtotal,
        includeServiceFee: newInclude,
        serviceFeeRate: draft.serviceFeeRate,
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

    await DatabaseService.createReservation(
      customerName: customerName,
      customerPhone: customerPhone,
      tableNumbers: const [],
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

  Future<void> _renameQuickOrderDraft(QuickOrderDraft draft) async {
    if (!widget.user.canManageMenuCountDrafts) {
      return;
    }

    final controller = TextEditingController(text: draft.displayName ?? '');
    final initialTextLength = controller.text.length;
    controller.selection = TextSelection.collapsed(offset: initialTextLength);

    final value = await _openQuickOrderNameKeyboardSheet(controller);
    controller.dispose();

    if (value == null) {
      return;
    }

    await DatabaseService.setQuickOrderDraftDisplayName(
      id: draft.id,
      displayName: value,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openDraftManageModal(QuickOrderDraft draft) async {
    if (!widget.user.canManageMenuCountDrafts) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.displayName?.isNotEmpty == true
                      ? 'მენიუ: ${draft.displayName}'
                      : 'მენიუს მართვა',
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₾${draft.total.toStringAsFixed(2)} • ${draft.items.fold<int>(0, (sum, item) => sum + item.quantity)} ცალი',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_confirmQuickOrderDraft(draft));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('დადასტურება'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_renameQuickOrderDraft(draft));
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E3A8A),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                      minimumSize: const Size.fromHeight(46),
                    ),
                    icon: const Icon(Icons.drive_file_rename_outline),
                    label: const Text('სახელის მართვა'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_viewQuickOrderDraftReceipt(draft));
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F766E),
                      side: const BorderSide(color: Color(0xFF99F6E4)),
                      backgroundColor: const Color(0xFFF0FDFA),
                      minimumSize: const Size.fromHeight(46),
                    ),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('ნახვა / PDF'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_deleteQuickOrderDraft(draft.id));
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      backgroundColor: const Color(0xFFFFF1F2),
                      minimumSize: const Size.fromHeight(46),
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('წაშლა'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _openQuickOrderNameKeyboardSheet(
    TextEditingController controller,
  ) async {
    String keyboardLanguage = DatabaseService.getDefaultLanguage();
    String? result;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: FractionallySizedBox(
                  heightFactor: 0.78,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xCCF5F6FB),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 24,
                          offset: Offset(0, -6),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          const SizedBox(height: 1),
                          Container(
                            width: 44,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.drive_file_rename_outline,
                                  color: Color(0xFF9B7C4A),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'მენიუს სახელის დამატება',
                                    style: TextStyle(
                                      color: Color(0xFF1F2330),
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    setSheetState(() {
                                      keyboardLanguage =
                                          keyboardLanguage == 'ka'
                                          ? 'en'
                                          : 'ka';
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.language,
                                    color: Color(0xFF9B7C4A),
                                  ),
                                  label: Text(
                                    keyboardLanguage.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF1F2330),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                TextButton.icon(
                                  onPressed: () {
                                    result = controller.text;
                                    Navigator.pop(sheetContext);
                                  },
                                  icon: const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF9B7C4A),
                                  ),
                                  label: const Text(
                                    'შენახვა',
                                    style: TextStyle(color: Color(0xFF1F2330)),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Color(0x991F2330),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE1E5EE),
                                ),
                              ),
                              child: ValueListenableBuilder<TextEditingValue>(
                                valueListenable: controller,
                                builder: (context, value, _) {
                                  final displayText = value.text.isEmpty
                                      ? 'მაგ: ლევანის მენიუ'
                                      : value.text;
                                  return Text(
                                    displayText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF1F2330),
                                      fontSize: 18,
                                      letterSpacing: 0.3,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              top: 8,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => controller.clear(),
                                icon: const Icon(
                                  Icons.clear,
                                  color: Colors.redAccent,
                                ),
                                label: const Text(
                                  'სახელის გასუფთავება',
                                  style: TextStyle(color: Colors.redAccent),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: OnScreenKeyboard(
                                controller: controller,
                                language: keyboardLanguage,
                                onClose: () => Navigator.pop(sheetContext),
                                onEnter: () {
                                  result = controller.text;
                                  Navigator.pop(sheetContext);
                                },
                                showHeader: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return result;
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
