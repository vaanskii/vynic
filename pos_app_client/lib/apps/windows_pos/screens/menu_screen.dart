import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/models/menu_models.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/services/menu_service.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printer_service.dart';
import 'package:vynic/apps/windows_pos/widgets/pin_button.dart';
import 'package:vynic/apps/windows_pos/widgets/on_screen_keyboard.dart';
import 'package:vynic/core/models/reservation_context.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'order_detail_screen.dart';

const Color _menuPrimaryColor = Color(0xFF1D4ED8);
const Color _menuSecondaryColor = Color(0xFF2563EB);
const Color _menuSurfaceColor = Color(0xFFF8FAFC);
const Color _menuCardColor = Color(0xFFFFFFFF);
const Color _menuBorderColor = Color(0xFFE2E8F0);
const Color _menuTextPrimary = Color(0xFF0F172A);
const Color _menuTextMuted = Color(0xFF64748B);
const Color _menuTextSoft = Color(0xFF94A3B8);

class _CartEntry {
  final String key;
  final String name;
  final double unitPrice;
  int quantity;
  String? comment; // Item-specific comment

  _CartEntry({
    required this.key,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.comment,
  });

  double get total => unitPrice * quantity;
}

class _CartStateSnapshot {
  final double unitPrice;
  final int quantity;
  final String? comment;

  const _CartStateSnapshot({
    required this.unitPrice,
    required this.quantity,
    this.comment,
  });

  static String? _normalizeComment(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  factory _CartStateSnapshot.fromEntry(_CartEntry entry) {
    return _CartStateSnapshot(
      unitPrice: entry.unitPrice,
      quantity: entry.quantity,
      comment: _normalizeComment(entry.comment),
    );
  }

  bool matches(_CartEntry entry) {
    return entry.unitPrice == unitPrice &&
        entry.quantity == quantity &&
        _normalizeComment(entry.comment) == comment;
  }
}

class _KitchenItemSnapshot {
  final String itemName;
  final int quantity;
  final String? comment;

  const _KitchenItemSnapshot({
    required this.itemName,
    required this.quantity,
    this.comment,
  });
}

class MenuScreen extends StatefulWidget {
  final User user;
  final List<String> selectedTables;
  final int? existingOrderId;
  final bool
  isPreOrderMode; // If true, return cart items instead of creating order
  final bool isQuickOrder; // If true, just calculate and print receipt
  final bool isTakeAwayMode;
  final String? takeAwayCustomerName;
  final String? takeAwayCustomerPhone;
  final String? takeAwayPickupTime;
  final String? takeAwayNotes;
  final ReservationContext? reservationContext;
  final List<OrderItem>? initialPreOrderItems;
  final String? initialQuickOrderDraftId;

  const MenuScreen({
    super.key,
    required this.user,
    required this.selectedTables,
    this.existingOrderId,
    this.isPreOrderMode = false,
    this.isQuickOrder = false,
    this.isTakeAwayMode = false,
    this.takeAwayCustomerName,
    this.takeAwayCustomerPhone,
    this.takeAwayPickupTime,
    this.takeAwayNotes,
    this.reservationContext,
    this.initialPreOrderItems,
    this.initialQuickOrderDraftId,
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<MenuCategory> _categories = [];
  MenuCategory? _selectedCategory;
  MenuSubcategory? _selectedSubcategory;
  bool _isLoading = true;
  late String _currentLanguage;
  late double _serviceFeeRate;
  late bool _serviceFeeDefaultEnabled;
  // Cart mapping: key -> CartEntry
  final Map<String, _CartEntry> _cart = {};
  final Map<String, _CartStateSnapshot> _initialCartSnapshot = {};
  bool _initialSnapshotCaptured = false;
  bool _initialSnapshotFrozen = false;
  bool _isOrderOpen = false;
  List<QuickOrderDraft> _quickOrderDrafts = [];
  String? _selectedQuickOrderDraftId;

  // Scroll controllers for category and subcategory bars
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _subcategoryScrollController = ScrollController();
  final ScrollController _itemsScrollController = ScrollController();

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isKeyboardVisible = false;
  static const double _searchKeyboardListInset = 340;

  String _buildKitchenDiffKey(OrderItem item) {
    final comment = item.comment?.trim() ?? '';
    return '${item.itemKey}|$comment';
  }

  List<_CartEntry> get _cartEntriesNewestFirst {
    final entries = _cart.values.toList();
    return entries.reversed.toList();
  }

  void _captureInitialCartSnapshot({bool force = false}) {
    if (_initialSnapshotFrozen) {
      return;
    }
    if (_initialSnapshotCaptured && !force) {
      return;
    }
    _initialCartSnapshot
      ..clear()
      ..addAll({
        for (final entry in _cart.entries)
          entry.key: _CartStateSnapshot.fromEntry(entry.value),
      });
    _initialSnapshotCaptured = true;
  }

  void _freezeInitialCartSnapshot() {
    if (_initialSnapshotFrozen) {
      return;
    }
    if (!_initialSnapshotCaptured) {
      _captureInitialCartSnapshot(force: true);
    }
    _initialSnapshotFrozen = true;
  }

  bool get _hasCartChanges {
    if (!_initialSnapshotCaptured) {
      return _cart.isNotEmpty;
    }
    if (_cart.length != _initialCartSnapshot.length) {
      return true;
    }
    for (final entry in _cart.entries) {
      final snapshot = _initialCartSnapshot[entry.key];
      if (snapshot == null) {
        return true;
      }
      if (!snapshot.matches(entry.value)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _confirmExitIfCartNotEmpty() async {
    if (!_hasCartChanges) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 40,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'დარწმუნებული ხართ?',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'თუ დაბრუნდებით, კალათაში დამატებული პოზიციები დაკარგული იქნება. ნამდვილად გსურთ დაბრუნება?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 16),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'გაუქმება',
                        style: TextStyle(color: Colors.black54, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'დადასტურება',
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
      ),
    );

    return result ?? false;
  }

  Future<void> _handleBackNavigation() async {
    final shouldExit = await _confirmExitIfCartNotEmpty();
    if (!mounted) {
      return;
    }
    if (shouldExit) {
      Navigator.of(context).pop();
    }
  }

  Map<String, _KitchenItemSnapshot> _createKitchenSnapshot(
    List<OrderItem> source,
  ) {
    return {
      for (final item in source)
        _buildKitchenDiffKey(item): _KitchenItemSnapshot(
          itemName: item.itemName,
          quantity: item.quantity,
          comment: item.comment,
        ),
    };
  }

  List<AuditEvent> _buildAuditEventsForOrderDiff({
    required Order existingOrder,
    required List<OrderItem> updatedItems,
    required DateTime timestamp,
  }) {
    final username = widget.user.username;
    final previous = <String, OrderItem>{
      for (final item in existingOrder.items) item.itemKey: item,
    };
    final next = <String, OrderItem>{
      for (final item in updatedItems) item.itemKey: item,
    };
    final keys = {...previous.keys, ...next.keys};
    final events = <AuditEvent>[];

    for (final key in keys) {
      final prevItem = previous[key];
      final nextItem = next[key];
      final prevQty = prevItem?.quantity ?? 0;
      final newQty = nextItem?.quantity ?? 0;
      if (prevQty == newQty) {
        continue;
      }

      final itemName = nextItem?.itemName ?? prevItem?.itemName ?? 'Item';
      final eventType = newQty <= 0
          ? AuditEventType.deleteItem
          : (prevQty == 0 || newQty > prevQty)
          ? AuditEventType.addItem
          : AuditEventType.reduceQty;

      final noteSegments = <String>[];
      final prevComment = prevItem?.comment?.trim();
      final nextComment = nextItem?.comment?.trim();

      if (prevComment != null &&
          prevComment.isNotEmpty &&
          prevComment != nextComment) {
        noteSegments.add('Prev note: $prevComment');
      }
      if (nextComment != null &&
          nextComment.isNotEmpty &&
          nextComment != prevComment) {
        noteSegments.add('Note: $nextComment');
      }

      events.add(
        AuditEvent(
          type: eventType,
          itemName: itemName,
          previousQty: prevQty,
          newQty: newQty,
          waiterId: username,
          waiterName: username,
          timestamp: timestamp,
          note: noteSegments.isEmpty ? null : noteSegments.join(' • '),
        ),
      );
    }

    return events;
  }

  String _formatKitchenItemLabel(
    String itemName,
    int quantity,
    String? comment,
  ) {
    final trimmedComment = comment?.trim() ?? '';
    if (trimmedComment.isEmpty) {
      return '${quantity}x $itemName';
    }
    return '${quantity}x $itemName\n  ⮑ $trimmedComment';
  }

  @override
  void initState() {
    super.initState();
    _currentLanguage = DatabaseService.getDefaultLanguage();
    _serviceFeeRate = DatabaseService.getServiceFeeRate();
    _serviceFeeDefaultEnabled = DatabaseService.defaultIncludeServiceFee();
    if (widget.isQuickOrder) {
      _quickOrderDrafts = DatabaseService.getQuickOrderDrafts();
      _selectedQuickOrderDraftId = widget.initialQuickOrderDraftId;
      if (widget.initialQuickOrderDraftId != null) {
        try {
          final draft = _quickOrderDrafts.firstWhere(
            (d) => d.id == widget.initialQuickOrderDraftId,
          );
          _applyDraftToCart(draft);
          _isOrderOpen = true;
        } catch (_) {}
      }
      if ((widget.initialPreOrderItems?.isNotEmpty ?? false) &&
          widget.initialQuickOrderDraftId != null) {
        _isOrderOpen = true;
      }
    }
    _loadInitialPreOrderItems();
    _loadMenu();
    _loadExistingOrder();
    if (widget.existingOrderId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _freezeInitialCartSnapshot();
      });
    }
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  void _loadInitialPreOrderItems() {
    final items = widget.initialPreOrderItems;
    if (items == null) {
      _captureInitialCartSnapshot(force: true);
      return;
    }

    for (final item in items) {
      _cart[item.itemKey] = _CartEntry(
        key: item.itemKey,
        name: item.itemName,
        unitPrice: item.unitPrice,
        quantity: item.quantity,
        comment: item.comment,
      );
    }
    _captureInitialCartSnapshot(force: true);
  }

  Future<void> _loadExistingOrder() async {
    if (widget.existingOrderId != null) {
      final order = DatabaseService.getOrder(widget.existingOrderId!);
      if (order != null) {
        setState(() {
          // Load existing order items into cart
          for (final item in order.items) {
            _cart[item.itemKey] = _CartEntry(
              key: item.itemKey,
              name: item.itemName,
              unitPrice: item.unitPrice,
              quantity: item.quantity,
              comment: item.comment,
            );
          }
        });
        _captureInitialCartSnapshot(force: true);
      }
      _freezeInitialCartSnapshot();
    }
  }

  @override
  void dispose() {
    _categoryScrollController.dispose();
    _subcategoryScrollController.dispose();
    _itemsScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMenu() async {
    final categories = await MenuService.loadMenu();
    setState(() {
      _categories = categories;
      _isLoading = false;
      if (_categories.isNotEmpty) {
        _selectedCategory = _categories[0];
      }
    });
  }

  void _toggleLanguage() {
    setState(() {
      _currentLanguage = _currentLanguage == 'ka' ? 'en' : 'ka';
    });
  }

  void _scrollItemsToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_itemsScrollController.hasClients) {
        _itemsScrollController.jumpTo(0);
      }
    });
  }

  void _selectCategory(MenuCategory category) {
    setState(() {
      _selectedCategory = category;
      _selectedSubcategory = null;
    });
    _scrollItemsToTop();
  }

  void _selectSubcategory(MenuSubcategory? subcategory) {
    setState(() {
      _selectedSubcategory = subcategory;
    });
    _scrollItemsToTop();
  }

  void _addToCartEntry(
    String key,
    String name,
    double unitPrice,
    int qty, [
    String? comment,
  ]) {
    setState(() {
      if (_cart.containsKey(key)) {
        _cart[key]!.quantity += qty;
        // If new comment provided, update it
        if (comment != null && comment.isNotEmpty) {
          _cart[key]!.comment = comment;
        }
      } else {
        _cart[key] = _CartEntry(
          key: key,
          name: name,
          unitPrice: unitPrice,
          quantity: qty,
          comment: comment,
        );
      }
    });
  }

  // _incrementCart removed (not used). Use _addToCartEntry or _decrementCart/_add flows.

  void _decrementCart(String key) {
    setState(() {
      if (_cart.containsKey(key)) {
        _cart[key]!.quantity -= 1;
        if (_cart[key]!.quantity <= 0) _cart.remove(key);
      }
    });
  }

  int _getTotalItems() {
    return _cart.values.fold(0, (sum, entry) => sum + entry.quantity);
  }

  double _getCartTotal() {
    return _cart.values.fold(0.0, (sum, entry) => sum + entry.total);
  }

  List<OrderItem> _cartToOrderItems() {
    return _cart.values
        .map(
          (cartEntry) => OrderItem(
            itemKey: cartEntry.key,
            itemName: cartEntry.name,
            unitPrice: cartEntry.unitPrice,
            quantity: cartEntry.quantity,
            total: cartEntry.total,
            comment: cartEntry.comment,
          ),
        )
        .toList();
  }

  void _applyDraftToCart(QuickOrderDraft draft) {
    setState(() {
      _cart.clear();
      for (final item in draft.items) {
        _cart[item.itemKey] = _CartEntry(
          key: item.itemKey,
          name: item.itemName,
          unitPrice: item.unitPrice,
          quantity: item.quantity,
          comment: item.comment,
        );
      }
      _isOrderOpen = true;
      _selectedQuickOrderDraftId = draft.id;
      _serviceFeeDefaultEnabled =
          DatabaseService.isServiceFeeAvailable() && draft.includeServiceFee;
      _serviceFeeRate = draft.serviceFeeRate > 0
          ? draft.serviceFeeRate
          : DatabaseService.getServiceFeeRate();
    });
  }

  void _openOrderPanel() {
    setState(() {
      _isOrderOpen = true;
    });
  }

  void _closeOrderPanel() {
    setState(() {
      _isOrderOpen = false;
    });
  }

  Future<void> _placeOrder() async {
    // If in pre-order mode, return the cart items without creating an order
    if (widget.isPreOrderMode) {
      final orderItems = _cart.values.map((cartEntry) {
        return OrderItem(
          itemKey: cartEntry.key,
          itemName: cartEntry.name,
          unitPrice: cartEntry.unitPrice,
          quantity: cartEntry.quantity,
          total: cartEntry.total,
          comment: cartEntry.comment,
        );
      }).toList();

      // Return the items to the previous screen
      Navigator.of(context).pop(orderItems);
      return;
    }

    if (_cart.isEmpty) return;

    if (widget.isTakeAwayMode) {
      final orderItems = _cart.values.map((cartEntry) {
        return OrderItem(
          itemKey: cartEntry.key,
          itemName: cartEntry.name,
          unitPrice: cartEntry.unitPrice,
          quantity: cartEntry.quantity,
          total: cartEntry.total,
          comment: cartEntry.comment,
        );
      }).toList();

      try {
        final currentTimestamp = DatabaseService.getCurrentDateTime();
        final pickupTime =
            widget.takeAwayPickupTime ??
            '${currentTimestamp.hour.toString().padLeft(2, '0')}:${currentTimestamp.minute.toString().padLeft(2, '0')}';

        final order = await DatabaseService.createTakeAwayOrder(
          customerName: widget.takeAwayCustomerName ?? 'Take Away',
          customerPhone: widget.takeAwayCustomerPhone ?? '-',
          pickupTime: pickupTime,
          notes: widget.takeAwayNotes,
          items: orderItems,
          createdBy: widget.user.username,
        );

        setState(() {
          _cart.clear();
          _isOrderOpen = false;
        });

        if (!mounted) return;
        Navigator.of(context)
            .pushReplacement(
              MaterialPageRoute(
                builder: (context) => OrderDetailScreen(
                  user: widget.user,
                  orderId: order.orderId,
                  autoConfirmOnLoad: true,
                ),
              ),
            )
            .then((result) {
              if (!mounted) {
                return;
              }
              if (result is Map && result['status'] == 'closed') {
                final message = result['message'] as String?;
                if (message != null && message.isNotEmpty) {
                  unawaited(
                    showPosToast(
                      context: context,
                      message: message,
                      style: PosToastStyle.success,
                    ),
                  );
                }
              }
            });
      } catch (e) {
        if (!mounted) return;
        unawaited(
          showErrorToast(context, 'Error creating take-away order: $e'),
        );
      }
      return;
    }

    // Quick Order Mode: Calculate, save, reuse, and print receipt
    if (widget.isQuickOrder) {
      if (_cart.isNotEmpty) {
        try {
          final draft = _selectedQuickOrderDraftId == null
              ? await DatabaseService.saveQuickOrderDraft(
                  createdBy: widget.user.username,
                  items: _cartToOrderItems(),
                  subtotal: _getCartTotal(),
                  includeServiceFee: _serviceFeeDefaultEnabled,
                  serviceFeeRate: _serviceFeeRate,
                )
              : await DatabaseService.updateQuickOrderDraft(
                  id: _selectedQuickOrderDraftId!,
                  createdBy: widget.user.username,
                  items: _cartToOrderItems(),
                  subtotal: _getCartTotal(),
                  includeServiceFee: _serviceFeeDefaultEnabled,
                  serviceFeeRate: _serviceFeeRate,
                );

          if (mounted) {
            setState(() {
              _selectedQuickOrderDraftId = draft.id;
              _quickOrderDrafts = DatabaseService.getQuickOrderDrafts();
            });
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _cart.clear();
          _isOrderOpen = false;
          _selectedQuickOrderDraftId = null;
        });
        Navigator.pop(context);
      }
      return;
    }

    try {
      // Convert cart to OrderItems
      final orderItems = _cart.values.map((cartEntry) {
        return OrderItem(
          itemKey: cartEntry.key,
          itemName: cartEntry.name,
          unitPrice: cartEntry.unitPrice,
          quantity: cartEntry.quantity,
          total: cartEntry.total,
          comment: cartEntry.comment,
        );
      }).toList();

      int orderId;

      if (widget.existingOrderId != null) {
        // Update existing order
        final existingOrder = DatabaseService.getOrder(widget.existingOrderId!);
        if (existingOrder != null) {
          final status = existingOrder.status.toLowerCase();
          final isLockedStatus =
              status == 'closed' ||
              status == 'paid' ||
              status == 'cancelled' ||
              status == 'canceled';
          if (isLockedStatus) {
            if (mounted) {
              unawaited(
                showErrorToast(
                  context,
                  'შეკვეთა უკვე დახურულია და ცვლილება შეუძლებელია.',
                ),
              );
            }
            return;
          }
          // Check if order is confirmed AND user is not admin - then we need admin approval for removals/reductions
          final needsAdminApproval =
              !widget.user.isAdmin &&
              (existingOrder.status == 'confirmed' ||
                  existingOrder.status == 'preparing' ||
                  existingOrder.status == 'served');

          // Track changes
          final removalsAndReductions = <String>[];
          final structuredChanges = <Map<String, dynamic>>[];

          for (final oldItem in existingOrder.items) {
            final newItem = orderItems.firstWhere(
              (item) => item.itemKey == oldItem.itemKey,
              orElse: () => OrderItem(
                itemKey: '',
                itemName: '',
                unitPrice: 0,
                quantity: 0,
                total: 0,
              ),
            );

            if (newItem.itemKey.isEmpty) {
              removalsAndReductions.add(
                'წაშლა: ${oldItem.quantity}x ${oldItem.itemName}',
              );
              structuredChanges.add({
                'itemKey': oldItem.itemKey,
                'itemName': oldItem.itemName,
                'changeType': 'removed',
                'previousQuantity': oldItem.quantity,
                'newQuantity': 0,
              });
            } else if (newItem.quantity < oldItem.quantity) {
              final reduction = oldItem.quantity - newItem.quantity;
              removalsAndReductions.add(
                'შემცირება: ${oldItem.itemName} (${oldItem.quantity} → ${newItem.quantity}, -$reduction)',
              );
              structuredChanges.add({
                'itemKey': oldItem.itemKey,
                'itemName': oldItem.itemName,
                'changeType': 'reduced',
                'previousQuantity': oldItem.quantity,
                'newQuantity': newItem.quantity,
              });
            }
          }

          if (removalsAndReductions.isNotEmpty && needsAdminApproval) {
            // Show what will be removed/reduced
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.white,
                elevation: 0,
                insetPadding: const EdgeInsets.all(24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.edit_note_rounded,
                                color: Color(0xFFF97316),
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'შეკვეთის ცვლილება',
                                style: TextStyle(
                                  color: Color(0xFF1E293B),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'თქვენ აპირებთ შემდეგი ცვლილებების შეტანას:',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: removalsAndReductions
                                .map(
                                  (change) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: Color(0xFFF97316),
                                          size: 19,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            change,
                                            style: const TextStyle(
                                              color: Color(0xFF7C2D12),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: const [
                            Icon(
                              Icons.history_rounded,
                              color: Color(0xFF94A3B8),
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'ცვლილება ავტომატურად დაფიქსირდება აუდიტ ლოგში',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF64748B),
                                    side: const BorderSide(
                                      color: Color(0xFFE2E8F0),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'გაუქმება',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E3A8A),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'გაგრძელება',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
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
              ),
            );

            if (confirmed != true) return;
          }

          final diffTimestamp = DatabaseService.getCurrentDateTime();
          final auditEvents = _buildAuditEventsForOrderDiff(
            existingOrder: existingOrder,
            updatedItems: orderItems,
            timestamp: diffTimestamp,
          );

          // Track changes for kitchen check using quantity deltas
          final oldSnapshot = _createKitchenSnapshot(existingOrder.items);
          final newSnapshot = _createKitchenSnapshot(orderItems);

          final addedItems = <String>[];
          final removedItems = <String>[];

          final allKeys = <String>{...oldSnapshot.keys, ...newSnapshot.keys};

          for (final key in allKeys) {
            final oldItem = oldSnapshot[key];
            final newItem = newSnapshot[key];
            final oldQty = oldItem?.quantity ?? 0;
            final newQty = newItem?.quantity ?? 0;
            final delta = newQty - oldQty;

            if (delta > 0 && newItem != null) {
              addedItems.add(
                _formatKitchenItemLabel(
                  newItem.itemName,
                  delta,
                  newItem.comment,
                ),
              );
            } else if (delta < 0 && oldItem != null) {
              removedItems.add(
                _formatKitchenItemLabel(
                  oldItem.itemName,
                  delta.abs(),
                  oldItem.comment,
                ),
              );
            }
          }

          // Clear existing items and add new ones
          existingOrder.items.clear();
          existingOrder.items.addAll(orderItems);
          existingOrder.updatedAt = DatabaseService.getCurrentDateTime();

          orderId = existingOrder.orderId;

          if (auditEvents.isNotEmpty) {
            await DatabaseService.appendOrderAuditEvents(
              orderId: existingOrder.orderId,
              events: auditEvents,
            );
          }

          await DatabaseService.updateOrder(existingOrder);

          // Print modification to kitchen if there are changes
          if (addedItems.isNotEmpty || removedItems.isNotEmpty) {
            PrinterService.printKitchenCheckInBackground(
              items: [], // Empty for modifications
              addedItems: addedItems,
              removedItems: removedItems,
              tableNumber: existingOrder.tableNumbers.join(', '),
              orderNumber: existingOrder.orderId.toString(),
              waiterName: widget.user.username,
              createdAt: DatabaseService.getCurrentDateTime(),
              onComplete: (success) {
                if (!mounted) return;
                if (success) {
                  unawaited(
                    showSuccessToast(
                      context,
                      'ცვლილებები გაიგზავნა სამზარეულოში',
                    ),
                  );
                } else {
                  unawaited(showErrorToast(context, 'პრინტერი მიუწვდომელია'));
                }
              },
            );
          }
        } else {
          throw Exception('Order not found');
        }
      } else {
        // Create new order
        // Extract floor from selectedTables (assuming format "Table 1", "VIP Zone 1")
        String floor = 'first'; // Default
        if (widget.selectedTables.isNotEmpty) {
          // Check if any table is from second floor (VIP zones are on second floor)
          if (widget.selectedTables.any((t) => t.contains('VIP'))) {
            floor = 'second';
          }
        }

        // Extract table numbers from display names
        final tableNumbers = widget.selectedTables.map((displayName) {
          // "Table 1" -> "1", "VIP Zone 1" -> "1"
          return displayName
              .replaceAll('Table ', '')
              .replaceAll('VIP Zone ', '');
        }).toList();

        // Create order in database
        final order = await DatabaseService.createOrder(
          tableNumbers: tableNumbers,
          floor: floor,
          createdBy: widget.user.username,
          items: orderItems,
          includeServiceFee: DatabaseService.defaultIncludeServiceFee(),
        );
        orderId = order.orderId;
      }

      // Clear cart
      setState(() {
        _cart.clear();
        _isOrderOpen = false;
      });

      if (!mounted) return;

      // Navigate to Order Detail Screen
      if (widget.existingOrderId != null) {
        // If editing, just pop back to order detail screen
        Navigator.of(context).pop();
      } else {
        // If new order, replace with order detail screen
        Navigator.of(context)
            .pushReplacement(
              MaterialPageRoute(
                builder: (context) => OrderDetailScreen(
                  user: widget.user,
                  orderId: orderId,
                  autoConfirmOnLoad: true,
                ),
              ),
            )
            .then((result) {
              if (!mounted) {
                return;
              }
              if (result is Map && result['status'] == 'closed') {
                final message = result['message'] as String?;
                if (message != null && message.isNotEmpty) {
                  unawaited(
                    showPosToast(
                      context: context,
                      message: message,
                      style: PosToastStyle.success,
                    ),
                  );
                }
              }
            });
      }
    } catch (e) {
      if (!mounted) return;
      String message = 'Error placing order: $e';
      if (e is StateError &&
          e.message.toLowerCase().contains('audit report') &&
          e.message.toLowerCase().contains('locked')) {
        message = 'შეკვეთა უკვე დახურულია და ცვლილება შეუძლებელია.';
      }
      unawaited(showErrorToast(context, message));
    }
  }

  void _scrollCategoryLeft() {
    _categoryScrollController.animateTo(
      _categoryScrollController.offset - 200,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollCategoryRight() {
    _categoryScrollController.animateTo(
      _categoryScrollController.offset + 200,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollSubcategoryLeft() {
    _subcategoryScrollController.animateTo(
      _subcategoryScrollController.offset - 200,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollSubcategoryRight() {
    _subcategoryScrollController.animateTo(
      _subcategoryScrollController.offset + 200,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _clearSearch() {
    if (!mounted) return;
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _isKeyboardVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _confirmExitIfCartNotEmpty,
      child: Scaffold(
        backgroundColor: _menuSurfaceColor,
        appBar: AppBar(
          backgroundColor: _menuCardColor,
          elevation: 0,
          iconTheme: const IconThemeData(color: _menuTextPrimary),
          titleTextStyle: const TextStyle(color: _menuTextPrimary),
          toolbarHeight: 60,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28),
            onPressed: _handleBackNavigation,
            tooltip: 'Back',
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Menu',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _menuTextPrimary,
                ),
              ),
              ..._buildMenuSubtitleLines(),
            ],
          ),
          actions: [
            if (_getTotalItems() > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _menuCardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _menuBorderColor),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_getTotalItems()} items',
                          style: const TextStyle(
                            color: _menuTextPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '₾${_getCartTotal().toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: _menuPrimaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_getTotalItems() > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _openOrderPanel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _menuPrimaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.shopping_cart, size: 20),
                    label: const Text(
                      'შეკვეთის ნახვა',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: Icon(
                _currentLanguage == 'en' ? Icons.language : Icons.translate,
                size: 28,
                color: _menuTextPrimary,
              ),
              onPressed: _toggleLanguage,
              tooltip: _currentLanguage == 'en' ? 'ქართული' : 'English',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: _menuPrimaryColor),
              )
            : Stack(
                children: [
                  Column(
                    children: [
                      _buildCategoryBar(),
                      if (_selectedCategory?.subcategories != null &&
                          _selectedCategory!.subcategories!.isNotEmpty)
                        _buildSubcategoryBar(),
                      _buildSearchBar(),
                      Expanded(child: _buildItemsList(_getItemsToDisplay())),
                    ],
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    right: _isOrderOpen ? 0 : -400,
                    top: 0,
                    bottom: 0,
                    width: 400,
                    child: _buildOrderPanel(),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    left: 0,
                    right: _isOrderOpen ? 400 : 0,
                    bottom: _isKeyboardVisible ? 0 : -400,
                    child: OnScreenKeyboard(
                      controller: _searchController,
                      language: _currentLanguage,
                      onClose: () {
                        setState(() {
                          _isKeyboardVisible = false;
                        });
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildMenuSubtitleLines() {
    final List<Widget> lines = [];

    Text buildLine(String text, {bool italic = false}) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: _menuTextMuted,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      );
    }

    if (widget.isTakeAwayMode) {
      final customer = (widget.takeAwayCustomerName ?? 'Guest').trim();
      final pickup = widget.takeAwayPickupTime;
      lines.add(
        buildLine('Take Away • $customer${pickup != null ? ' @ $pickup' : ''}'),
      );
      return lines;
    }

    final reservationCtx = widget.reservationContext;
    if (reservationCtx != null) {
      final name = reservationCtx.customerName.trim();
      if (name.isNotEmpty) {
        lines.add(buildLine('სტუმარი: $name'));
      }

      final phone = reservationCtx.customerPhone.trim();
      if (phone.isNotEmpty && phone != '-' && phone != '--') {
        lines.add(buildLine('ტელეფონი: $phone'));
      }

      if (reservationCtx.tableLabels.isNotEmpty) {
        lines.add(
          buildLine('სუფრები: ${reservationCtx.tableLabels.join(", ")}'),
        );
      }

      final notes = reservationCtx.notes?.trim();
      if (notes != null && notes.isNotEmpty) {
        lines.add(buildLine('შენიშვნა: $notes', italic: true));
      }

      if (lines.isNotEmpty) {
        return lines;
      }
    }

    lines.add(buildLine('Tables: ${widget.selectedTables.join(", ")}'));
    return lines;
  }

  Widget _buildCategoryBar() {
    return Container(
      height: 50,
      decoration: const BoxDecoration(
        color: _menuCardColor,
        border: Border(bottom: BorderSide(color: _menuBorderColor, width: 1)),
      ),
      child: Row(
        children: [
          // Left arrow button
          IconButton(
            icon: const Icon(
              Icons.chevron_left,
              color: _menuPrimaryColor,
              size: 32,
            ),
            onPressed: _scrollCategoryLeft,
            tooltip: 'Scroll left',
          ),
          // Category list
          Expanded(
            child: ListView.builder(
              controller: _categoryScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory?.slug == category.slug;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: InkWell(
                    onTap: () => _selectCategory(category),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _menuPrimaryColor
                            : _menuSurfaceColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? _menuPrimaryColor
                              : _menuBorderColor,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          category.getName(_currentLanguage),
                          style: TextStyle(
                            color: isSelected ? Colors.white : _menuTextPrimary,
                            fontSize: 15,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Right arrow button
          IconButton(
            icon: const Icon(
              Icons.chevron_right,
              color: _menuPrimaryColor,
              size: 32,
            ),
            onPressed: _scrollCategoryRight,
            tooltip: 'Scroll right',
          ),
        ],
      ),
    );
  }

  Widget _buildSubcategoryBar() {
    final subcategories = _selectedCategory?.subcategories ?? [];

    return Container(
      height: 45,
      decoration: const BoxDecoration(
        color: _menuCardColor,
        border: Border(bottom: BorderSide(color: _menuBorderColor, width: 1)),
      ),
      child: Row(
        children: [
          // Left arrow button
          IconButton(
            icon: const Icon(
              Icons.chevron_left,
              color: _menuPrimaryColor,
              size: 28,
            ),
            onPressed: _scrollSubcategoryLeft,
            tooltip: 'Scroll left',
            padding: const EdgeInsets.all(4),
          ),
          // Subcategory list
          Expanded(
            child: ListView.builder(
              controller: _subcategoryScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: subcategories.length + 1, // +1 for "All" option
              itemBuilder: (context, index) {
                if (index == 0) {
                  // "All" button
                  final isSelected = _selectedSubcategory == null;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: InkWell(
                      onTap: () => _selectSubcategory(null),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _menuPrimaryColor
                              : _menuSurfaceColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? _menuPrimaryColor
                                : _menuBorderColor,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _currentLanguage == 'en' ? 'All' : 'ყველა',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : _menuTextPrimary,
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final subcategory = subcategories[index - 1];
                final isSelected =
                    _selectedSubcategory?.slug == subcategory.slug;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: InkWell(
                    onTap: () => _selectSubcategory(subcategory),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _menuPrimaryColor
                            : _menuSurfaceColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? _menuPrimaryColor
                              : _menuBorderColor,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          subcategory.getName(_currentLanguage),
                          style: TextStyle(
                            color: isSelected ? Colors.white : _menuTextPrimary,
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Right arrow button
          IconButton(
            icon: const Icon(
              Icons.chevron_right,
              color: _menuPrimaryColor,
              size: 28,
            ),
            onPressed: _scrollSubcategoryRight,
            tooltip: 'Scroll right',
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: _menuCardColor,
        border: Border(bottom: BorderSide(color: _menuBorderColor, width: 1)),
      ),
      child: TextField(
        controller: _searchController,
        readOnly: true, // Make read-only to prevent system keyboard
        onTap: () {
          setState(() {
            _isKeyboardVisible = true;
          });
        },
        style: const TextStyle(color: _menuTextPrimary, fontSize: 16),
        decoration: InputDecoration(
          hintText: _currentLanguage == 'en'
              ? 'Search items...'
              : 'მოძებნე პროდუქტი...',
          hintStyle: const TextStyle(color: _menuTextSoft),
          prefixIcon: const Icon(Icons.search, color: _menuTextMuted),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: _menuTextMuted),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: _menuSurfaceColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  List<MenuItem> _getItemsToDisplay() {
    List<MenuItem> items = [];

    // If search is active, search across ALL categories
    if (_searchQuery.isNotEmpty) {
      for (var category in _categories) {
        // Search in main category items
        if (category.items != null) {
          items.addAll(category.items!);
        }

        // Search in subcategory items
        if (category.subcategories != null) {
          for (var subcategory in category.subcategories!) {
            items.addAll(subcategory.items);
          }
        }
      }

      // Filter items by search query (search in both English and Georgian)
      return items.where((item) {
        final nameEn = item.getName('en').toLowerCase();
        final nameKa = item.getName('ka').toLowerCase();
        return nameEn.contains(_searchQuery) || nameKa.contains(_searchQuery);
      }).toList();
    }

    // No search - show based on category/subcategory selection
    if (_selectedSubcategory != null) {
      // Show only selected subcategory items
      return _selectedSubcategory!.items;
    } else if (_selectedCategory != null) {
      // "All" is selected - show category items + all subcategory items
      List<MenuItem> allItems = [];

      // Add main category items if they exist
      if (_selectedCategory!.items != null) {
        allItems.addAll(_selectedCategory!.items!);
      }

      // Add all items from all subcategories
      if (_selectedCategory!.subcategories != null) {
        for (var subcategory in _selectedCategory!.subcategories!) {
          allItems.addAll(subcategory.items);
        }
      }

      return allItems;
    }
    return [];
  }

  Widget _buildItemsList(List<MenuItem> items) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No items available',
          style: TextStyle(color: _menuTextMuted, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      controller: _itemsScrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + (_isKeyboardVisible ? _searchKeyboardListInset : 0),
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildItemCard(item);
      },
    );
  }

  Widget _buildItemCard(MenuItem item) {
    final itemName = item.getName(_currentLanguage);

    if (item.hasVariants()) {
      return Card(
        color: _menuCardColor,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _menuBorderColor),
        ),
        child: IntrinsicHeight(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Item info - takes half width
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        itemName,
                        style: const TextStyle(
                          color: _menuTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item.variants!.length} variants available',
                        style: const TextStyle(
                          color: _menuTextMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                // Empty space - takes half width
                const Expanded(flex: 1, child: SizedBox()),
                // Add button - fixed width on the right
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => _onAddPressed(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _menuSecondaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'დამატება',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Card(
        color: _menuCardColor,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _menuBorderColor),
        ),
        child: IntrinsicHeight(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Item info - takes half width
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        itemName,
                        style: const TextStyle(
                          color: _menuTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₾${item.price!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: _menuPrimaryColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // Empty space - takes half width
                const Expanded(flex: 1, child: SizedBox()),
                // Add button - fixed width on the right
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => _onAddPressed(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _menuSecondaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'დამატება',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _onAddPressed(MenuItem item) async {
    final itemName = item.getName(_currentLanguage);

    if (item.hasVariants()) {
      // Step 1: Show variant selection dialog
      final selectedVariant = await showDialog<MenuVariant>(
        context: context,
        builder: (context) {
          return _VariantSelectionDialog(
            item: item,
            language: _currentLanguage,
          );
        },
      );

      if (selectedVariant != null && mounted) {
        // Step 2: Show quantity dialog
        final qty = await showDialog<int>(
          context: context,
          builder: (context) {
            final dialogTitle = '$itemName - ${selectedVariant.getSizeLabel()}';
            return _QuantityDialog(defaultQty: 1, title: dialogTitle);
          },
        );

        if (qty != null && qty > 0) {
          final variantLabel = selectedVariant.getSizeLabel();
          _addToCartEntry(
            '$itemName - $variantLabel',
            '$itemName - $variantLabel',
            selectedVariant.price,
            qty,
          );
          _clearSearch();
        }
      }
    } else {
      // No variants: show simple quantity dialog
      final qty = await showDialog<int>(
        context: context,
        builder: (context) {
          return _QuantityDialog(defaultQty: 1, title: itemName);
        },
      );

      if (qty != null && qty > 0 && mounted) {
        _addToCartEntry(itemName, itemName, item.price ?? 0.0, qty);
        _clearSearch();
      }
    }
  }

  Widget _buildOrderPanel() {
    return Material(
      elevation: 8,
      color: _menuCardColor,
      child: Column(
        children: [
          // Compact header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: _menuCardColor,
              border: Border(
                bottom: BorderSide(color: _menuBorderColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Order Summary',
                    style: TextStyle(
                      color: _menuTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _closeOrderPanel,
                  icon: const Icon(
                    Icons.close,
                    color: _menuTextPrimary,
                    size: 24,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? const Center(
                    child: Text(
                      'Cart is empty',
                      style: TextStyle(color: _menuTextMuted),
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final cartEntries = _cartEntriesNewestFirst;
                      return ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: cartEntries.length,
                        itemBuilder: (context, idx) {
                          final entry = cartEntries[idx];
                          return Card(
                            color: _menuSurfaceColor,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: _menuBorderColor),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.name,
                                    style: const TextStyle(
                                      color: _menuTextPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (entry.comment != null &&
                                      entry.comment!.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.comment,
                                          color: _menuPrimaryColor,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            entry.comment!,
                                            style: const TextStyle(
                                              color: _menuPrimaryColor,
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Text(
                                    '₾${entry.unitPrice.toStringAsFixed(2)} each',
                                    style: const TextStyle(
                                      color: _menuTextMuted,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: ElevatedButton(
                                          onPressed: () =>
                                              _decrementCart(entry.key),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _menuSurfaceColor,
                                            foregroundColor: _menuTextPrimary,
                                            side: const BorderSide(
                                              color: _menuBorderColor,
                                            ),
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.remove,
                                            color: _menuTextPrimary,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _menuCardColor,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: _menuBorderColor,
                                          ),
                                        ),
                                        child: Text(
                                          '${entry.quantity}',
                                          style: const TextStyle(
                                            color: _menuTextPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: ElevatedButton(
                                          onPressed: () {
                                            setState(() {
                                              _cart[entry.key]!.quantity += 1;
                                            });
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                _menuSecondaryColor,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.add,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '₾${entry.total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: _menuPrimaryColor,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: IconButton(
                                          onPressed: () async {
                                            final comment =
                                                await showDialog<String>(
                                                  context: context,
                                                  builder: (context) =>
                                                      _CommentDialog(
                                                        itemName: entry.name,
                                                        existingComment:
                                                            entry.comment,
                                                      ),
                                                );
                                            if (comment != null) {
                                              setState(() {
                                                _cart[entry.key]!.comment =
                                                    comment.isEmpty
                                                    ? null
                                                    : comment;
                                              });
                                            }
                                          },
                                          icon: Icon(
                                            Icons.comment,
                                            color:
                                                (entry.comment != null &&
                                                    entry.comment!.isNotEmpty)
                                                ? _menuPrimaryColor
                                                : _menuTextMuted,
                                            size: 22,
                                          ),
                                          style: IconButton.styleFrom(
                                            backgroundColor: _menuCardColor,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _cart.remove(entry.key);
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                            size: 22,
                                          ),
                                          style: IconButton.styleFrom(
                                            backgroundColor: _menuCardColor,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
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
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: _menuBorderColor, width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Total and Clear All button
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total: ₾${_getCartTotal().toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: _menuPrimaryColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _cart.isNotEmpty
                          ? () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: _menuCardColor,
                                  title: const Text(
                                    'Clear Cart?',
                                    style: TextStyle(color: _menuTextPrimary),
                                  ),
                                  content: const Text(
                                    'Are you sure you want to remove all items from the cart?',
                                    style: TextStyle(color: _menuTextMuted),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                          color: _menuTextPrimary,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          _cart.clear();
                                        });
                                        Navigator.pop(context);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Clear All'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.delete_sweep, size: 20),
                      label: const Text('Clear All'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Place/Update Order button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: widget.isPreOrderMode || _cart.isNotEmpty
                        ? _placeOrder
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _menuSecondaryColor,
                      disabledBackgroundColor: _menuBorderColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      widget.isPreOrderMode
                          ? Icons.restaurant_menu
                          : (widget.existingOrderId != null
                                ? Icons.edit
                                : Icons.check_circle),
                      size: 24,
                    ),
                    label: Text(
                      widget.isPreOrderMode
                          ? 'რეზერვაციის დადასტურება'
                          : (widget.existingOrderId != null
                                ? 'შეკვეთის განახლება'
                                : 'შეკვეთის გაფორმება'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// New simplified variant selection dialog
class _VariantSelectionDialog extends StatefulWidget {
  final MenuItem item;
  final String language;

  const _VariantSelectionDialog({required this.item, required this.language});

  @override
  State<_VariantSelectionDialog> createState() =>
      _VariantSelectionDialogState();
}

class _VariantSelectionDialogState extends State<_VariantSelectionDialog> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final variants = widget.item.variants ?? [];

    return AlertDialog(
      backgroundColor: _menuCardColor,
      title: Text(
        widget.item.getName(widget.language),
        style: const TextStyle(
          color: _menuTextPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select Size / Variant:',
              style: TextStyle(color: _menuTextMuted, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ...variants.asMap().entries.map((e) {
              final i = e.key;
              final v = e.value;
              final label = v.getSizeLabel();
              final isSelected = _selectedIndex == i;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: InkWell(
                  onTap: () => setState(() => _selectedIndex = i),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? _menuPrimaryColor : _menuSurfaceColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? _menuPrimaryColor
                            : _menuBorderColor,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : _menuTextPrimary,
                              fontSize: 18,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '₾${v.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : _menuPrimaryColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: _menuTextPrimary, fontSize: 16),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(variants[_selectedIndex]);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _menuSecondaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
          child: const Text(
            'Next',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _QuantityDialog extends StatefulWidget {
  final int defaultQty;
  final String title;

  const _QuantityDialog({this.defaultQty = 1, required this.title});

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  String _quantityInput = ''; // Start with empty string

  @override
  void initState() {
    super.initState();
    // Start with empty string so user can type directly
    _quantityInput = '';
  }

  void _onDigitPressed(String digit) {
    if (_quantityInput.length < 3) {
      setState(() {
        _quantityInput += digit;
      });
    }
  }

  void _onClearPressed() {
    setState(() {
      _quantityInput = '';
    });
  }

  void _onDeletePressed() {
    if (_quantityInput.isNotEmpty) {
      setState(() {
        _quantityInput = _quantityInput.substring(0, _quantityInput.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final qty = int.tryParse(_quantityInput) ?? 0;

    return AlertDialog(
      backgroundColor: _menuCardColor,
      title: Text(
        widget.title,
        style: const TextStyle(color: _menuTextPrimary, fontSize: 22),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SizedBox(
        width: 400, // Set wider dialog
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Text(
                _quantityInput.isEmpty ? '0' : _quantityInput,
                style: const TextStyle(
                  color: _menuTextPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 340, // Give more width for better spacing
              child: PinPad(
                onDigitPressed: _onDigitPressed,
                onClearPressed: _onClearPressed,
                onDeletePressed: _onDeletePressed,
              ),
            ),
            const SizedBox(height: 24), // Extra spacing before buttons
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 200,
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      backgroundColor: _menuSurfaceColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'გაუქმება',
                      style: TextStyle(color: _menuTextPrimary, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 200,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: qty > 0
                        ? () => Navigator.of(context).pop(qty)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _menuSecondaryColor,
                      disabledBackgroundColor: _menuBorderColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'დამატება',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8), // Bottom padding
          ],
        ),
      ),
      actions: const [], // Remove default actions row
    );
  }
}

// Comment Dialog for menu items
class _CommentDialog extends StatefulWidget {
  final String itemName;
  final String? existingComment;

  const _CommentDialog({required this.itemName, this.existingComment});

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  late final TextEditingController _controller;
  bool _showKeyboard = true; // Show keyboard by default for touch screen
  String _currentLanguage = 'ka'; // Default to Georgian

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existingComment ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Main dialog content
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF2B2B2B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    const Icon(
                      Icons.comment,
                      color: Color(0xFFC0AD7B),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'კომენტარი',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Item name
                Text(
                  widget.itemName,
                  style: const TextStyle(
                    color: Color(0xFFC0AD7B),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                // Text field
                TextField(
                  controller: _controller,
                  readOnly: true, // Prevent system keyboard
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'მაგალითად: ხახვის გარეშე, ცხარე...',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF333333),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.existingComment != null &&
                        widget.existingComment!.isNotEmpty)
                      TextButton(
                        onPressed: () => Navigator.pop(
                          context,
                          '',
                        ), // Empty string means remove comment
                        child: const Text(
                          'წაშლა',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        null,
                      ), // Cancel - keep existing
                      child: const Text(
                        'გაუქმება',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final text = _controller.text.trim();
                        Navigator.pop(context, text.isEmpty ? null : text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC0AD7B),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'შენახვა',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // On-screen keyboard
          if (_showKeyboard)
            Container(
              color: const Color(0xFF1E1E1E),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Language toggle and hide keyboard button
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    color: const Color(0xFF2B2B2B),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _currentLanguage = 'ka';
                                });
                              },
                              child: Text(
                                'ქართული',
                                style: TextStyle(
                                  color: _currentLanguage == 'ka'
                                      ? const Color(0xFFC0AD7B)
                                      : Colors.white70,
                                  fontWeight: _currentLanguage == 'ka'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _currentLanguage = 'en';
                                });
                              },
                              child: Text(
                                'English',
                                style: TextStyle(
                                  color: _currentLanguage == 'en'
                                      ? const Color(0xFFC0AD7B)
                                      : Colors.white70,
                                  fontWeight: _currentLanguage == 'en'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _showKeyboard = false;
                            });
                          },
                          icon: const Icon(
                            Icons.keyboard_hide,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OnScreenKeyboard(
                    controller: _controller,
                    language: _currentLanguage,
                    onClose: () {
                      setState(() {
                        _showKeyboard = false;
                      });
                    },
                    onEnter: () {
                      final text = _controller.text.trim();
                      Navigator.pop(context, text.isEmpty ? null : text);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
