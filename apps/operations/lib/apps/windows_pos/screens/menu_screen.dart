import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/models/menu_models.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/services/pos/menu_service.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/widgets/pin_button.dart';
import 'package:vynic/apps/windows_pos/widgets/on_screen_keyboard.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/models/reservation_context.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'order_detail_screen.dart';

/// This screen's names for the shared floor tokens.
///
/// It used to carry its own palette — a saturated teal on cool grey — which is
/// why walking from the floor into „შეკვეთის რედაქტირება" felt like changing
/// application. The names are kept because a hundred call sites below use
/// them; only what they point at has moved.
///
/// The old `_menuPrimaryColor` did two jobs at once: it was a bare foreground
/// (prices, links, step arrows) *and* a fill behind white text (selected chips,
/// the confirm button). One colour cannot be both in this palette, so the
/// foreground and the tint are separate below, and the filled aubergine lives
/// in `PosPrimaryButton` where the one filled button on a screen belongs.
/// Mapping it to a single token would have made every one of those foregrounds
/// either invisible or shouting.
const Color _menuAccent = VynicFloorTokens.accentText;
const Color _menuAccentSoft = VynicFloorTokens.accentSoft;
const Color _menuAccentSoftBorder = Color(0xFFE2DCF2);

const Color _menuSurfaceColor = VynicFloorTokens.page;
const Color _menuCardColor = VynicFloorTokens.panel;
const Color _menuBorderColor = VynicFloorTokens.panelBorder;
const Color _menuTextPrimary = VynicFloorTokens.text;
const Color _menuTextMuted = VynicFloorTokens.textMuted;
const Color _menuTextSoft = VynicFloorTokens.textFaint;
const Color _menuDanger = VynicFloorTokens.dangerText;

// --- product card geometry --------------------------------------------------
//
// The grid used to size its cells with `childAspectRatio: 2.1`, which ties the
// card's *height* to the column width. A 1200pt layout fits three columns of
// 184.7, so every cell came out 88pt tall — for content that needs 93.6 — and
// every dish whose name wrapped to two lines wore a yellow-and-black overflow
// bar. The same layout at 1440 tore by 2.9pt, at 1920 not at all: whether the
// screen was broken depended on the resolution it was opened at.
//
// So the height is stated instead of inferred, and the two texts inside carry
// explicit `height:` multipliers to keep this arithmetic true rather than
// approximately true. Nothing here can overflow at any width.
const double _menuCardPadding = 12;
const double _menuCardBorder = 1;
const double _menuCardNameSize = 14;
const double _menuCardLineHeight = 1.2;

/// One line of the dish name, as the engine actually lays it out.
///
/// 14 x 1.2 is 16.8, but Flutter rounds every line box up to a whole logical
/// pixel, so two lines measure 34 and not 33.6. Doing the multiplication in the
/// obvious way left the card 0.4pt short — and the `Border.all` below, which is
/// drawn *inside* the box, took another 2. Between them the card overflowed by
/// 2.4pt at every resolution, which is the arithmetic being almost right.
const double _menuCardNameLine = 17;
const double _menuCardNameLines = 2;
const double _menuCardGap = 6;
const double _menuCardFooterHeight = 30;
const double _menuCardHeight =
    (_menuCardPadding + _menuCardBorder) * 2 +
    _menuCardNameLine * _menuCardNameLines +
    _menuCardGap +
    _menuCardFooterHeight;

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

  /// What the tables are *called* — used for display and on the receipt.
  final List<String> selectedTables;

  /// What the tables *are*. Supplied whenever the caller knows the legacy
  /// numbers; the order is created against these.
  ///
  /// Table names are admin-editable free text, so they cannot be parsed back
  /// into numbers. Callers that still pass raw numbers as [selectedTables]
  /// leave this null and get the old stripping behaviour.
  final List<String>? tableNumbers;

  /// Legacy floor ('first'/'second') the tables belong to. Null falls back to
  /// sniffing [selectedTables], which only ever worked for default names.
  final String? tableFloor;
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
    this.tableNumbers,
    this.tableFloor,
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
  bool _existingOrderIsTakeAway = false;
  // Discount carried over from an existing order being edited (0 for new).
  double _existingDiscount = 0.0;
  // Per-order service-fee override from an existing order (null = use global).
  double? _orderCustomServicePercent;
  // Cart mapping: key -> CartEntry
  final Map<String, _CartEntry> _cart = {};
  final Map<String, _CartStateSnapshot> _initialCartSnapshot = {};
  bool _initialSnapshotCaptured = false;
  bool _initialSnapshotFrozen = false;
  List<QuickOrderDraft> _quickOrderDrafts = [];
  String? _selectedQuickOrderDraftId;

  bool get _canApplyServiceFee =>
      DatabaseService.isServiceFeeAvailable() &&
      !widget.isPreOrderMode &&
      !widget.isTakeAwayMode &&
      !_existingOrderIsTakeAway;

  bool get _shouldIncludeServiceFee =>
      _canApplyServiceFee && _serviceFeeDefaultEnabled;

  bool _isTakeAwayOrder(Order order) {
    return order.floor.toLowerCase() == 'takeaway' ||
        order.tableNumbers.any((table) => table.startsWith('TA-'));
  }

  // Scroll controllers for category and subcategory bars
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _subcategoryScrollController = ScrollController();
  final ScrollController _itemsScrollController = ScrollController();

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
                  color: Colors.orange.withValues(alpha: 0.15),
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
    _serviceFeeDefaultEnabled =
        _canApplyServiceFee && DatabaseService.defaultIncludeServiceFee();
    if (widget.isQuickOrder) {
      _quickOrderDrafts = DatabaseService.getQuickOrderDrafts();
      _selectedQuickOrderDraftId = widget.initialQuickOrderDraftId;
      if (widget.initialQuickOrderDraftId != null) {
        try {
          final draft = _quickOrderDrafts.firstWhere(
            (d) => d.id == widget.initialQuickOrderDraftId,
          );
          _applyDraftToCart(draft);
        } catch (_) {}
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
          _existingOrderIsTakeAway = _isTakeAwayOrder(order);
          // Reflect the existing order's service-fee state in the toggle.
          _serviceFeeDefaultEnabled = _canApplyServiceFee
              ? order.includeServiceFee
              : false;
          _existingDiscount = order.discountAmount;
          _orderCustomServicePercent = order.customServiceFeePercentage;
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
      _selectedQuickOrderDraftId = draft.id;
      _serviceFeeDefaultEnabled =
          _canApplyServiceFee && draft.includeServiceFee;
      _serviceFeeRate = draft.serviceFeeRate > 0
          ? draft.serviceFeeRate
          : DatabaseService.getServiceFeeRate();
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

    if (widget.isTakeAwayMode && widget.existingOrderId == null) {
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
                  includeServiceFee: _shouldIncludeServiceFee,
                  serviceFeeRate: _serviceFeeRate,
                )
              : await DatabaseService.updateQuickOrderDraft(
                  id: _selectedQuickOrderDraftId!,
                  createdBy: widget.user.username,
                  items: _cartToOrderItems(),
                  subtotal: _getCartTotal(),
                  includeServiceFee: _shouldIncludeServiceFee,
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
          _existingOrderIsTakeAway = _isTakeAwayOrder(existingOrder);
          existingOrder.includeServiceFee = _shouldIncludeServiceFee;
          existingOrder.recalculateTotal();
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
        // Prefer the identity the caller handed us. Names are admin-editable
        // now, so deriving a table number or a floor from a display name is
        // only safe for the callers that still pass raw numbers through
        // selectedTables — they leave both fields null.
        String floor = widget.tableFloor ?? 'first';
        if (widget.tableFloor == null && widget.selectedTables.isNotEmpty) {
          if (widget.selectedTables.any(
            (t) => t.startsWith('Second Floor Table ') || t.contains('VIP'),
          )) {
            floor = 'second';
          }
        }

        final tableNumbers =
            widget.tableNumbers ??
            widget.selectedTables.map((displayName) {
              // "Table 1" -> "1", "Second Floor Table 1" -> "1"
              return displayName
                  .replaceAll('Second Floor Table ', '')
                  .replaceAll('Table ', '')
                  .replaceAll('VIP Zone ', '');
            }).toList();

        // Create order in database
        final order = await DatabaseService.createOrder(
          tableNumbers: tableNumbers,
          floor: floor,
          createdBy: widget.user.username,
          items: orderItems,
          includeServiceFee: _shouldIncludeServiceFee,
        );
        orderId = order.orderId;
      }

      // Clear cart
      setState(() {
        _cart.clear();
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

  void _clearSearch() {
    if (!mounted) return;
    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
  }

  Future<void> _openSearchKeyboard() async {
    await showPosKeyboardInputSheet(
      context: context,
      controller: _searchController,
      initialLanguage: PosKeyboardLanguage.fromCode(_currentLanguage),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        final navigator = Navigator.of(context);
        final shouldPop = await _confirmExitIfCartNotEmpty();
        if (shouldPop && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: _menuSurfaceColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // The breakpoint used to be 1100, which nothing could
                    // reach: `PosScaledSurface` never lays this screen out
                    // below 1200 wide, so the compact widths were dead code and
                    // a 1024x768 terminal spent 590 of its 1200 points on
                    // chrome — half the screen, to show three columns of
                    // 184pt cards. Moved to where a real terminal lands.
                    final compactDesktop = constraints.maxWidth < 1360;
                    final categoryWidth = compactDesktop ? 180.0 : 210.0;
                    final orderPanelWidth = compactDesktop ? 340.0 : 380.0;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCategorySidebar(width: categoryWidth),
                        Expanded(
                          child: _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: _menuAccent,
                                  ),
                                )
                              : Column(
                                  children: [
                                    if (_searchQuery.isEmpty &&
                                        _selectedCategory?.subcategories !=
                                            null &&
                                        _selectedCategory!
                                            .subcategories!
                                            .isNotEmpty)
                                      _buildSubcategoryBar(),
                                    Expanded(
                                      child: _buildItemsGrid(
                                        _getItemsToDisplay(),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        SizedBox(
                          width: orderPanelWidth,
                          child: _buildOrderPanel(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _screenTitle {
    if (widget.isPreOrderMode) {
      return 'რეზერვაციის მენიუ';
    }
    if (widget.existingOrderId != null) {
      return 'შეკვეთის რედაქტირება';
    }
    return 'ახალი შეკვეთა';
  }

  Widget _buildTopBar() {
    final subtitle = _menuSubtitle();
    return Container(
      decoration: const BoxDecoration(
        color: _menuCardColor,
        border: Border(bottom: BorderSide(color: _menuBorderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
      child: Row(
        children: [
          _TopBarIconButton(
            icon: Icons.arrow_back,
            onTap: _handleBackNavigation,
          ),
          const SizedBox(width: 14),
          // The context block gets a share of the bar rather than all the room
          // it asks for. A reservation note is free text: left unbounded it
          // used to push the search field down to nothing while the operator
          // watched, and a long enough one tore the row outright.
          Flexible(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _screenTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _menuTextPrimary,
                    height: 1.15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    // Two lines is the ceiling: the bar is the one thing on
                    // this screen whose height comes straight out of the grid
                    // below it, and at 720 the grid has none to give.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _menuTextMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 20),
          Flexible(flex: 4, child: _buildSearchField()),
          const SizedBox(width: 10),
          _TopBarIconButton(
            icon: _currentLanguage == 'en' ? Icons.language : Icons.translate,
            onTap: _toggleLanguage,
            tooltip: _currentLanguage == 'en' ? 'ქართული' : 'English',
          ),
        ],
      ),
    );
  }

  /// One line of context under the screen name: who the order is for.
  ///
  /// This used to be a stack of up to four `Text` widgets — guest, phone,
  /// tables, note — each free to be as wide and as tall as it liked. On a
  /// booked table that made the header the tallest thing on the screen and left
  /// the search field a sliver. The same facts read fine joined up and clipped
  /// at two lines; the full note is on the order detail either way.
  String? _menuSubtitle() {
    if (widget.isTakeAwayMode) {
      final customer = (widget.takeAwayCustomerName ?? 'Guest').trim();
      final pickup = widget.takeAwayPickupTime;
      return 'Take Away • $customer${pickup != null ? ' @ $pickup' : ''}';
    }

    final parts = <String>[];
    final reservationCtx = widget.reservationContext;
    if (reservationCtx != null) {
      final name = reservationCtx.customerName.trim();
      if (name.isNotEmpty) parts.add(name);

      final phone = reservationCtx.customerPhone.trim();
      if (phone.isNotEmpty && phone != '-' && phone != '--') parts.add(phone);

      if (reservationCtx.tableLabels.isNotEmpty) {
        parts.add(reservationCtx.tableLabels.join(', '));
      }

      final notes = reservationCtx.notes?.trim();
      if (notes != null && notes.isNotEmpty) parts.add(notes);

      if (parts.isNotEmpty) return parts.join('  ·  ');
    }

    if (widget.selectedTables.isEmpty) return null;
    final label = _currentLanguage == 'en' ? 'Tables' : 'მაგიდები';
    return '$label: ${widget.selectedTables.join(", ")}';
  }

  Widget _buildCategorySidebar({required double width}) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: _menuCardColor,
        border: Border(right: BorderSide(color: _menuBorderColor, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: PosSectionLabel(
              _currentLanguage == 'en' ? 'Categories' : 'კატეგორიები',
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _categoryScrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory?.slug == category.slug;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: isSelected ? _menuAccentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => _selectCategory(category),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? _menuAccentSoftBorder
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          category.getName(_currentLanguage),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? _menuAccent : _menuTextPrimary,
                            fontSize: 13.5,
                            height: 1.2,
                            fontWeight: isSelected
                                ? FontWeight.w700
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
        ],
      ),
    );
  }

  Widget _buildSubcategoryBar() {
    final subcategories = _selectedCategory?.subcategories ?? [];

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? _menuAccentSoft : _menuSurfaceColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? _menuAccentSoftBorder : _menuBorderColor,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? _menuAccent : _menuTextPrimary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: _menuCardColor,
        border: Border(bottom: BorderSide(color: _menuBorderColor, width: 1)),
      ),
      child: ListView(
        controller: _subcategoryScrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          chip(
            label: _currentLanguage == 'en' ? 'All' : 'ყველა',
            selected: _selectedSubcategory == null,
            onTap: () => _selectSubcategory(null),
          ),
          for (final subcategory in subcategories)
            chip(
              label: subcategory.getName(_currentLanguage),
              selected: _selectedSubcategory?.slug == subcategory.slug,
              onTap: () => _selectSubcategory(subcategory),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchController,
        readOnly: true, // Make read-only to prevent system keyboard
        onTap: _openSearchKeyboard,
        style: const TextStyle(color: _menuTextPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: _currentLanguage == 'en'
              ? 'Search products...'
              : 'პროდუქტის ძიება...',
          hintStyle: const TextStyle(color: _menuTextSoft),
          prefixIcon: const Icon(Icons.search, color: _menuTextMuted, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    color: _menuTextMuted,
                    size: 20,
                  ),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: _menuSurfaceColor,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _menuBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _menuBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _menuAccent),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
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

  Widget _buildItemsGrid(List<MenuItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 44, color: _menuTextSoft),
            const SizedBox(height: 10),
            Text(
              _currentLanguage == 'en'
                  ? 'No items available'
                  : 'პროდუქტები ვერ მოიძებნა',
              style: const TextStyle(color: _menuTextMuted, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double targetWidth = 200;
        const double spacing = 12;
        int columns = (constraints.maxWidth / targetWidth).floor();
        if (columns < 2) columns = 2;
        if (columns > 5) columns = 5;

        return GridView.builder(
          controller: _itemsScrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            // A height the card is known to need, not a ratio guessed against
            // the column width. See [_menuCardHeight].
            mainAxisExtent: _menuCardHeight,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return _buildItemCard(items[index]);
          },
        );
      },
    );
  }

  Widget _buildItemCard(MenuItem item) {
    final itemName = item.getName(_currentLanguage);
    final hasVariants = item.hasVariants();
    final priceLabel = hasVariants
        ? (_currentLanguage == 'en'
              ? '${item.variants!.length} variants'
              : '${item.variants!.length} ვარიანტი')
        : '${(item.price ?? 0).toStringAsFixed(2)} ₾';

    return Material(
      color: _menuCardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _onAddPressed(item),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(_menuCardPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: VynicFloorTokens.tileBorder,
              width: _menuCardBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Expanded rather than intrinsic, so the card cannot tear even
              // if a font, a text scale or a rounding rule disagrees with the
              // arithmetic above. The name gives way; the price and the add
              // button — the two things a waiter is actually reaching for —
              // keep their size.
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    itemName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _menuTextPrimary,
                      fontSize: _menuCardNameSize,
                      fontWeight: FontWeight.w700,
                      height: _menuCardLineHeight,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _menuCardGap),
              SizedBox(
                height: _menuCardFooterHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        priceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasVariants ? _menuTextMuted : _menuAccent,
                          fontSize: hasVariants ? 13 : 17,
                          fontWeight: FontWeight.w800,
                          // Pinned so the footer's height is the box's height
                          // and not whatever the font decides — the arithmetic
                          // in [_menuCardHeight] depends on it.
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: _menuCardFooterHeight,
                      height: _menuCardFooterHeight,
                      decoration: BoxDecoration(
                        color: _menuAccentSoft,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: _menuAccentSoftBorder),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 18,
                        color: _menuAccent,
                      ),
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
    return Container(
      decoration: const BoxDecoration(
        color: _menuCardColor,
        border: Border(left: BorderSide(color: _menuBorderColor, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: _menuCardColor,
              border: Border(
                bottom: BorderSide(color: _menuBorderColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Expanded(child: PosSectionLabel('შეკვეთა')),
                if (_canApplyServiceFee) ...[
                  const Flexible(
                    child: Text(
                      'სერვისი',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _menuTextMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PosToggle(
                    value: _serviceFeeDefaultEnabled,
                    semanticLabel: 'სერვისი',
                    onChanged: (value) {
                      setState(() {
                        _serviceFeeDefaultEnabled = value;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.shopping_cart_outlined,
                          size: 40,
                          color: _menuTextSoft,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _currentLanguage == 'en'
                              ? 'Cart is empty'
                              : 'პროდუქტები არ არის დამატებული',
                          style: const TextStyle(
                            color: _menuTextMuted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _cartEntriesNewestFirst.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: _menuBorderColor,
                      indent: 14,
                      endIndent: 14,
                    ),
                    itemBuilder: (context, idx) {
                      final entries = _cartEntriesNewestFirst;
                      return _buildCartItemRow(entries[idx], idx + 1);
                    },
                  ),
          ),
          _buildOrderTotals(),
        ],
      ),
    );
  }

  Widget _buildCartItemRow(_CartEntry entry, int displayIndex) {
    final hasComment =
        entry.comment != null && entry.comment!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$displayIndex',
              style: const TextStyle(
                color: _menuTextMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(
                    color: _menuTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasComment) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.comment!,
                    style: const TextStyle(
                      color: _menuTextMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                _cartLink(
                  label: hasComment ? 'კომენტარი' : '+ კომენტარი',
                  onTap: () => _editCartComment(entry),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.total.toStringAsFixed(2)} ₾',
                style: const TextStyle(
                  color: _menuTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _qtyStepper(entry),
                  const SizedBox(width: 6),
                  _cartIconButton(
                    icon: Icons.close,
                    color: _menuDanger,
                    onTap: () => setState(() => _cart.remove(entry.key)),
                    tooltip: _currentLanguage == 'en' ? 'Remove' : 'წაშლა',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qtyStepper(_CartEntry entry) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: _menuSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _menuBorderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(
            icon: Icons.remove,
            onTap: entry.quantity > 1
                ? () => setState(() => _cart[entry.key]?.quantity -= 1)
                : null,
          ),
          SizedBox(
            width: 26,
            child: Text(
              '${entry.quantity}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _menuTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _stepButton(
            icon: Icons.add,
            onTap: () => setState(() => _cart[entry.key]?.quantity += 1),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({required IconData icon, required VoidCallback? onTap}) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 28,
        height: 30,
        child: Icon(
          icon,
          size: 16,
          color: enabled ? _menuAccent : _menuTextSoft,
        ),
      ),
    );
  }

  Widget _cartIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }

  Widget _cartLink({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Text(
        label,
        style: const TextStyle(
          color: _menuAccent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Effective service-fee percentage for this order: the per-order override
  /// when set, otherwise the live global setting — so the menu always mirrors
  /// the real service-fee configuration (and the order detail screen).
  double get _effectiveServicePercent =>
      _orderCustomServicePercent ?? DatabaseService.getServiceFeePercentage();

  String _formatPercent(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  Widget _buildOrderTotals() {
    final subtotal = _getCartTotal();
    final serviceFeeOn = _shouldIncludeServiceFee;
    final servicePercent = _effectiveServicePercent;
    final serviceFee = serviceFeeOn
        ? double.parse((subtotal * (servicePercent / 100)).toStringAsFixed(2))
        : 0.0;
    final total = subtotal + serviceFee - _existingDiscount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _menuBorderColor, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PosActionButton(
            label: _currentLanguage == 'en'
                ? 'Clear order'
                : 'შეკვეთის გასუფთავება',
            icon: Icons.delete_outline,
            tone: PosActionTone.danger,
            expand: true,
            onTap: _cart.isNotEmpty ? _confirmClearCart : null,
          ),
          const SizedBox(height: 14),
          _totalLine(
            label:
                '${_currentLanguage == 'en' ? 'Items' : 'ჯამი პროდუქტები'} (${_getTotalItems()})',
            value: '${subtotal.toStringAsFixed(2)} ₾',
          ),
          if (serviceFeeOn) ...[
            const SizedBox(height: 6),
            _totalLine(
              label:
                  '${_currentLanguage == 'en' ? 'Service' : 'სერვისი'} (${_formatPercent(servicePercent)}%)',
              value: '${serviceFee.toStringAsFixed(2)} ₾',
            ),
          ],
          if (_existingDiscount > 0) ...[
            const SizedBox(height: 6),
            _totalLine(
              label: _currentLanguage == 'en' ? 'Discount' : 'ფასდაკლება',
              value: '−${_existingDiscount.toStringAsFixed(2)} ₾',
              muted: true,
            ),
          ],
          const Divider(height: 20, color: _menuBorderColor),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  _currentLanguage == 'en' ? 'Total' : 'სულ ჯამი',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _menuTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${total.toStringAsFixed(2)} ₾',
                maxLines: 1,
                style: const TextStyle(
                  color: _menuTextPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: PosPrimaryButton(
              label: widget.isPreOrderMode
                  ? 'რეზერვაციის დადასტურება'
                  : (widget.existingOrderId != null
                        ? 'შეკვეთის განახლება'
                        : 'შეკვეთის დამატება'),
              icon: widget.isPreOrderMode
                  ? Icons.restaurant_menu
                  : (widget.existingOrderId != null
                        ? Icons.check
                        : Icons.check_circle),
              onTap: widget.isPreOrderMode || _cart.isNotEmpty
                  ? _placeOrder
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalLine({
    required String label,
    required String value,
    bool muted = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _menuTextMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: muted ? _menuTextMuted : _menuTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Future<void> _editCartComment(_CartEntry entry) async {
    final comment = await showDialog<String>(
      context: context,
      builder: (context) =>
          _CommentDialog(itemName: entry.name, existingComment: entry.comment),
    );
    if (comment != null) {
      setState(() {
        _cart[entry.key]?.comment = comment.isEmpty ? null : comment;
      });
    }
  }

  void _confirmClearCart() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(
          _currentLanguage == 'en' ? 'Clear order?' : 'შეკვეთის გასუფთავება?',
          style: const TextStyle(color: _menuTextPrimary),
        ),
        content: Text(
          _currentLanguage == 'en'
              ? 'Remove all items from the order?'
              : 'ნამდვილად გსურთ ყველა პოზიციის წაშლა?',
          style: const TextStyle(color: _menuTextMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_currentLanguage == 'en' ? 'Cancel' : 'გაუქმება'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _cart.clear());
              Navigator.pop(dialogContext);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: Text(_currentLanguage == 'en' ? 'Clear' : 'გასუფთავება'),
          ),
        ],
      ),
    );
  }
}

/// A 40pt square with a hairline. The back arrow and the language toggle are
/// the same control, so they are the same shape — the language toggle used to
/// be a bare `IconButton` floating next to a bordered box.
class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: _menuSurfaceColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _menuBorderColor),
          ),
          child: Icon(icon, size: 19, color: _menuTextPrimary),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
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
    final english = widget.language == 'en';

    return AlertDialog(
      backgroundColor: _menuCardColor,
      surfaceTintColor: _menuCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.item.getName(widget.language),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _menuTextPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          PosSectionLabel(english ? 'Select a size' : 'აირჩიეთ ზომა'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          // A drinks menu with eight pours used to run straight off the bottom
          // of the dialog: the list was a bare `Column` inside a box that
          // cannot grow. It scrolls now, so the number of variants an admin
          // adds is their business rather than a layout constraint.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in variants.asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _VariantOption(
                    label: e.value.getSizeLabel(),
                    price: e.value.price,
                    selected: _selectedIndex == e.key,
                    onTap: () => setState(() => _selectedIndex = e.key),
                  ),
                ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: [
        PosActionButton(
          label: english ? 'Cancel' : 'გაუქმება',
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        PosPrimaryButton(
          label: english ? 'Next' : 'შემდეგ',
          height: 46,
          onTap: variants.isEmpty
              ? null
              : () => Navigator.of(context).pop(variants[_selectedIndex]),
        ),
      ],
    );
  }
}

/// One pour size and its price. Selected reads as a tinted card with a filled
/// radio, not as a saturated block of colour with white text on it.
class _VariantOption extends StatelessWidget {
  const _VariantOption({
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _menuAccentSoft : _menuCardColor,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? _menuAccentSoftBorder : _menuBorderColor,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? _menuAccent : _menuTextSoft,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _menuAccent : _menuTextPrimary,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${price.toStringAsFixed(2)} ₾',
                maxLines: 1,
                style: TextStyle(
                  color: selected ? _menuAccent : _menuTextPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
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
      surfaceTintColor: _menuCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      title: Text(
        widget.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _menuTextPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The running figure, in the same tinted well the rest of the POS
            // uses to say „this is what you have entered so far".
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _menuAccentSoft,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: _menuAccentSoftBorder),
              ),
              child: Text(
                _quantityInput.isEmpty ? '0' : _quantityInput,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _menuAccent,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 320,
              child: PinPad(
                onDigitPressed: _onDigitPressed,
                onClearPressed: _onClearPressed,
                onDeletePressed: _onDeletePressed,
              ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        PosActionButton(
          label: 'გაუქმება',
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        PosPrimaryButton(
          label: 'დამატება',
          height: 46,
          onTap: qty > 0 ? () => Navigator.of(context).pop(qty) : null,
        ),
      ],
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
    final hasExisting =
        widget.existingComment != null && widget.existingComment!.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // The card used to be charcoal with a brass accent, sitting directly
          // on top of a white on-screen keyboard — two products in one modal.
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _menuCardColor,
              borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
              border: Border.all(color: _menuBorderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PosSectionLabel('კომენტარი'),
                const SizedBox(height: 6),
                Text(
                  widget.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _menuTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  readOnly: true, // Prevent system keyboard
                  maxLines: 3,
                  style: const TextStyle(color: _menuTextPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'მაგალითად: ხახვის გარეშე, ცხარე...',
                    hintStyle: const TextStyle(color: _menuTextSoft),
                    filled: true,
                    fillColor: _menuSurfaceColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _menuBorderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _menuBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _menuAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (hasExisting)
                      PosActionButton(
                        label: 'წაშლა',
                        icon: Icons.delete_outline,
                        tone: PosActionTone.danger,
                        // Empty string means remove the comment; null means
                        // leave it alone. Two different answers, so they cannot
                        // share a button.
                        onTap: () => Navigator.pop(context, ''),
                      ),
                    const Spacer(),
                    PosActionButton(
                      label: 'გაუქმება',
                      onTap: () => Navigator.pop(context, null),
                    ),
                    const SizedBox(width: 8),
                    PosPrimaryButton(
                      label: 'შენახვა',
                      height: 46,
                      onTap: () {
                        final text = _controller.text.trim();
                        Navigator.pop(context, text.isEmpty ? null : text);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_showKeyboard)
            Container(
              color: _menuCardColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: const BoxDecoration(
                      color: _menuSurfaceColor,
                      border: Border(
                        top: BorderSide(color: _menuBorderColor),
                        bottom: BorderSide(color: _menuBorderColor),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _KeyboardLanguageTab(
                              label: 'ქართული',
                              selected: _currentLanguage == 'ka',
                              onTap: () =>
                                  setState(() => _currentLanguage = 'ka'),
                            ),
                            const SizedBox(width: 8),
                            _KeyboardLanguageTab(
                              label: 'English',
                              selected: _currentLanguage == 'en',
                              onTap: () =>
                                  setState(() => _currentLanguage = 'en'),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _showKeyboard = false),
                          icon: const Icon(
                            Icons.keyboard_hide,
                            color: _menuTextMuted,
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

/// Which layout the on-screen keyboard is showing. A tab, not a text button —
/// the selected one has to be visible at a glance from across a counter.
class _KeyboardLanguageTab extends StatelessWidget {
  const _KeyboardLanguageTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _menuAccentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? _menuAccentSoftBorder : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _menuAccent : _menuTextMuted,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
