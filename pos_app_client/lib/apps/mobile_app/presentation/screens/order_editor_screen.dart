import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_menu_pin_sheet.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_receipt_preview_dialog.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';
import 'package:vynic/core/services/pos/pos_change_highlight_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_order_detail_panel.dart';

class OrderEditorScreen extends StatefulWidget {
  final User user;
  final int orderId;
  final String tableNumber;
  final String floor;

  /// Keys from notification tap / POS diff (optional).
  final Set<String>? highlightItemKeys;

  const OrderEditorScreen({
    super.key,
    required this.user,
    required this.orderId,
    required this.tableNumber,
    required this.floor,
    this.highlightItemKeys,
  });

  @override
  State<OrderEditorScreen> createState() => _OrderEditorScreenState();
}

class _OrderEditorScreenState extends State<OrderEditorScreen> {
  Order? _order;
  List<MenuCategoryDB> _categories = [];
  String? _selectedCategorySlug;
  String? _selectedSubcategorySlug;
  bool _isLoading = true;
  bool _hasChanges = false;
  bool _isOrderPanelOpen = false;
  late Set<String> _highlightKeys;

  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _subcategoryScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _highlightKeys =
        widget.highlightItemKeys ??
        PosChangeHighlightService.takeForOrder(widget.orderId) ??
        {};
    if (_highlightKeys.isNotEmpty) {
      _isOrderPanelOpen = true;
    }
    MonitoringSocketService.updateCounter.addListener(_onRemoteOrderChange);
    _loadData();
  }

  @override
  void dispose() {
    MonitoringSocketService.updateCounter.removeListener(_onRemoteOrderChange);
    _categoryScrollController.dispose();
    _subcategoryScrollController.dispose();
    super.dispose();
  }

  void _scrollCategoryLeft() {
    _categoryScrollController.animateTo(
      (_categoryScrollController.offset - 160).clamp(
        0.0,
        _categoryScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _scrollCategoryRight() {
    _categoryScrollController.animateTo(
      (_categoryScrollController.offset + 160).clamp(
        0.0,
        _categoryScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _scrollSubcategoryLeft() {
    _subcategoryScrollController.animateTo(
      (_subcategoryScrollController.offset - 160).clamp(
        0.0,
        _subcategoryScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _scrollSubcategoryRight() {
    _subcategoryScrollController.animateTo(
      (_subcategoryScrollController.offset + 160).clamp(
        0.0,
        _subcategoryScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _onRemoteOrderChange() {
    if (!mounted) return;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        MobileApiService.getOrder(widget.orderId),
        MobileApiService.getMenu(),
      ]);

      final order = results[0] as Order;
      final rawMenu = results[1] as List<dynamic>;

      final categories = rawMenu.map((cat) {
        return MenuCategoryDB(
          slug: cat['slug'],
          translationsEn: {'name': cat['nameEn']},
          translationsKa: {'name': cat['nameKa']},
          sendToKitchen: cat['sendToKitchen'] ?? true,
          items: (cat['items'] as List<dynamic>).map((it) {
            return MenuItemDB(
              translationsEn: {'name': it['nameEn']},
              translationsKa: {'name': it['nameKa']},
              price: (it['price'] as num).toDouble(),
              sendToKitchen: it['sendToKitchen'] ?? true,
              variants: (it['variants'] as List<dynamic>?)?.map((v) {
                return MenuVariantDB(
                  size: (v['size'] as num).toDouble(),
                  price: (v['price'] as num).toDouble(),
                );
              }).toList(),
            );
          }).toList(),
          subcategories: (cat['subcategories'] as List<dynamic>?)?.map((sub) {
            return MenuSubcategoryDB(
              slug: sub['slug'],
              translationsEn: {'name': sub['nameEn']},
              translationsKa: {'name': sub['nameKa']},
              items: (sub['items'] as List<dynamic>).map((it) {
                return MenuItemDB(
                  translationsEn: {'name': it['nameEn']},
                  translationsKa: {'name': it['nameKa']},
                  price: (it['price'] as num).toDouble(),
                  sendToKitchen: it['sendToKitchen'] ?? true,
                  variants: (it['variants'] as List<dynamic>?)?.map((v) {
                    return MenuVariantDB(
                      size: (v['size'] as num).toDouble(),
                      price: (v['price'] as num).toDouble(),
                    );
                  }).toList(),
                );
              }).toList(),
            );
          }).toList(),
        );
      }).toList();

      debugPrint('[ORDER] Loaded menu: ${categories.length} categories');
      for (var c in categories) {
        debugPrint(
          '[ORDER] Cat: ${c.slug} (Items: ${c.items?.length}, Subs: ${c.subcategories?.length})',
        );
      }

      setState(() {
        _order = order;
        _categories = categories;
        if (_categories.isNotEmpty) {
          _selectedCategorySlug = _categories.first.slug;
          _selectedSubcategorySlug = null;
        }
        final pending = PosChangeHighlightService.takeForOrder(widget.orderId);
        if (pending != null && pending.isNotEmpty) {
          _highlightKeys = pending;
          _isOrderPanelOpen = true;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ManagerToast.show(
          context,
          'მონაცემების ჩატვირთვა ვერ მოხერხდა',
          isError: true,
        );
      }
    }
  }

  void _updateQuantity(int index, int delta) {
    if (_order == null) return;
    setState(() {
      _hasChanges = true;
      final item = _order!.items[index];
      final newQty = item.quantity + delta;
      if (newQty > 0) {
        _order!.items[index] = OrderItem(
          itemKey: item.itemKey,
          itemName: item.itemName,
          unitPrice: item.unitPrice,
          quantity: newQty,
          total: item.unitPrice * newQty,
          comment: item.comment,
        );
      } else {
        _order!.items.removeAt(index);
      }
      _order!.recalculateTotal();
    });
  }

  void _addItem(MenuItemDB menuItem, int quantity, {MenuVariantDB? variant}) {
    if (_order == null || quantity <= 0) return;
    setState(() {
      _hasChanges = true;
      String itemName =
          menuItem.translationsKa['name'] ??
          menuItem.translationsEn['name'] ??
          'უცნობი';

      double price = menuItem.price ?? 0.0;
      if (variant != null) {
        itemName += ' (${variant.getSizeLabel()})';
        price = variant.price;
      }

      final itemKey = variant != null
          ? '${menuItem.translationsEn['name'] ?? itemName}_${variant.size}'
          : (menuItem.translationsEn['name'] ?? itemName);

      final existingIndex = _order!.items.indexWhere(
        (it) => it.itemKey == itemKey,
      );

      if (existingIndex >= 0) {
        final existing = _order!.items[existingIndex];
        _order!.items.removeAt(existingIndex);
        _order!.items.insert(
          0,
          OrderItem(
            itemKey: existing.itemKey,
            itemName: existing.itemName,
            unitPrice: existing.unitPrice,
            quantity: existing.quantity + quantity,
            total: existing.unitPrice * (existing.quantity + quantity),
            comment: existing.comment,
          ),
        );
      } else {
        _order!.items.insert(
          0,
          OrderItem(
            itemKey: itemKey,
            itemName: itemName,
            unitPrice: price,
            quantity: quantity,
            total: price * quantity,
          ),
        );
      }
      _order!.recalculateTotal();
    });
  }

  void _showQuantityPicker(MenuItemDB menuItem) async {
    final itemName =
        menuItem.translationsKa['name'] ??
        menuItem.translationsEn['name'] ??
        '';
    final variants = (menuItem.variants ?? [])
        .map(
          (v) =>
              MenuPinVariant(label: v.getSizeLabel(), price: v.price, tag: v),
        )
        .toList();

    final currentKey = menuItem.translationsEn['name'] ?? itemName;
    final inCart =
        _order?.items
            .where((it) => it.itemKey == currentKey)
            .fold(0, (sum, it) => sum + it.quantity) ??
        0;

    if (!mounted) return;
    final result = await showMobileMenuPinSheet(
      context,
      itemName: itemName,
      unitPrice: menuItem.price ?? 0,
      variants: variants,
      inCartQty: inCart,
      addMode: true,
    );
    if (result == null) return;
    final variant = result.variant?.tag as MenuVariantDB?;
    _addItem(menuItem, result.qty, variant: variant);
  }

  Future<void> _viewCheckPdf() async {
    if (_order == null) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      final itemsList = _order!.items
          .map((i) => '${i.quantity}x ${i.itemName} - ${i.unitPrice}')
          .toList();

      final pngBytes = await PrinterService.generateReceiptPngBytes(
        items: itemsList,
        total: _order!.totalAmount,
        subtotal: _order!.getItemsSubtotal(),
        serviceFee: _order!.getServiceFee(),
        includeServiceFee: _order!.includeServiceFee,
        tableNumber: _order!.tableNumbers.join(', '),
        orderNumber: _order!.orderId.toString(),
        language: 'ka',
        packageSubtotal: _order!.packagePrice,
        discountAmount: _order!.discountAmount,
        manualAdjustment: _order!.manualAdjustmentAmount,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        if (pngBytes != null) {
          MobileReceiptPreviewDialog.show(
            context,
            pngBytes,
            title: 'ქვითარი #${_order!.orderId}',
          );
        } else {
          ManagerToast.showSnackBar(
            context,
            'ქვითრის გენერაცია ვერ მოხერხდა',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        ManagerToast.showSnackBar(context, 'შეცდომა: $e', isError: true);
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_order == null) return;

    try {
      await MobileApiService.updateOrder(
        _order!,
        updatedBy: widget.user.username,
      );
      _hasChanges = false;
      if (mounted) {
        ManagerToast.show(context, 'შეკვეთა წარმატებით შეინახა');
        Navigator.pop(context);
      }
    } catch (e, stack) {
      debugPrint('[OrderEditor] _saveChanges error: $e');
      debugPrint('[OrderEditor] stack: $stack');
      if (mounted) {
        ManagerToast.show(context, 'შეცდომა განახლებისას: $e', isError: true);
      }
    }
  }

  bool get _isTakeaway => widget.floor == 'takeaway';

  String _orderTitle() {
    if (_isTakeaway) return 'გატანა #${widget.orderId}';
    if (_order != null && _order!.tableNumbers.length > 1) {
      return 'მაგიდები ${_order!.tableNumbers.map((t) => t.replaceAll('Table ', '')).join(', ')}';
    }
    return 'მაგიდა ${widget.tableNumber}';
  }

  String? _orderSubtitle() {
    if (_isTakeaway) return null;
    return 'შეკვეთა #${widget.orderId}';
  }

  void _toggleServiceFee() {}

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MobileGlassTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'მაგიდის გაუქმება?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: MobileGlassTheme.textPrimary,
          ),
        ),
        content: Text(
          'შეკვეთა #${widget.orderId} (მაგიდა ${widget.tableNumber}) '
          'სამუდამოდ გაუქმდება.\nეს ქმედება ვერ გაუქმდება.',
          style: TextStyle(color: MobileGlassTheme.muted(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'უკან',
              style: TextStyle(color: MobileGlassTheme.muted()),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: MobileGlassTheme.bad,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('გაუქმება'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await MobileApiService.cancelOrder(widget.orderId);
      if (mounted) {
        ManagerToast.show(context, 'მაგიდა გაუქმებულია');
        Navigator.pop(context, 'cancelled');
      }
    } catch (e) {
      if (mounted) {
        ManagerToast.show(context, 'გაუქმება ვერ მოხერხდა: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MobileGlassScreen(
        orbs: [
          Positioned(
            top: -80,
            right: -50,
            child: MobileGlowOrb(color: MobileGlassTheme.primary, size: 220),
          ),
        ],
        body: Column(
          children: [
            MobileGlassHeader(
              title: 'რედაქტირება',
              subtitle: _orderSubtitle(),
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  color: MobileGlassTheme.primary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_order == null) {
      return MobileGlassScreen(
        orbs: [
          Positioned(
            top: -80,
            right: -60,
            child: MobileGlowOrb(color: MobileGlassTheme.warn, size: 220),
          ),
        ],
        body: Column(
          children: [
            MobileGlassHeader(
              title: _orderTitle(),
              subtitle: _orderSubtitle(),
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: MobileGlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 48,
                          color: MobileGlassTheme.warn,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'შეკვეთა #${widget.orderId} ვერ მოიძებნა',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: MobileGlassTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'მაგიდა ${widget.tableNumber} (${widget.floor}) ბაზაში დაკავებულად არის მონიშნული, '
                          'მაგრამ შეკვეთა ვერ მოიძებნა. '
                          'შეგიძლიათ მაგიდა გაათავისუფლოთ ან სცადოთ ხელახლა.',
                          style: TextStyle(
                            color: MobileGlassTheme.muted(0.65),
                            fontSize: 13,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 24),
                        MobileGlassPrimaryButton(
                          label: 'მაგიდის გათავისუფლება',
                          icon: Icons.lock_open_rounded,
                          onPressed: () async {
                            final ok = await MobileApiService.freeTable(
                              widget.tableNumber,
                              widget.floor,
                            );
                            if (!context.mounted) return;
                            if (ok) {
                              ManagerToast.show(context, 'მაგიდა გათავისუფლდა');
                              Navigator.pop(context, 'freed');
                            } else {
                              ManagerToast.show(
                                context,
                                'გათავისუფლება ვერ მოხერხდა',
                                isError: true,
                              );
                            }
                          },
                        ),
                        SizedBox(height: 12),
                        MobileGlassPrimaryButton(
                          label: 'შეკვეთის გაუქმება DB-ში',
                          icon: Icons.delete_outline_rounded,
                          color: MobileGlassTheme.bad,
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: MobileGlassTheme.surfaceCard,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                title: Text(
                                  'შეკვეთის გაუქმება',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: MobileGlassTheme.textPrimary,
                                  ),
                                ),
                                content: Text(
                                  'შეკვეთა #${widget.orderId} გაუქმდება '
                                  'და მაგიდა ${widget.tableNumber} გათავისუფლდება.',
                                  style: TextStyle(
                                    color: MobileGlassTheme.muted(0.7),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(
                                      'გაუქმება',
                                      style: TextStyle(
                                        color: MobileGlassTheme.muted(),
                                      ),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: MobileGlassTheme.bad,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text('დადასტურება'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !context.mounted) return;
                            try {
                              await MobileApiService.cancelOrder(
                                widget.orderId,
                              );
                              if (!context.mounted) return;
                              ManagerToast.show(context, 'შეკვეთა გაუქმებულია');
                              Navigator.pop(context, 'cancelled');
                            } catch (_) {
                              final ok = await MobileApiService.freeTable(
                                widget.tableNumber,
                                widget.floor,
                              );
                              if (!context.mounted) return;
                              ManagerToast.show(
                                context,
                                ok ? 'მაგიდა გათავისუფლდა' : 'შეცდომა',
                                isError: !ok,
                              );
                              if (ok) Navigator.pop(context, 'freed');
                            }
                          },
                        ),
                        SizedBox(height: 12),
                        TextButton.icon(
                          icon: Icon(
                            Icons.refresh_rounded,
                            color: MobileGlassTheme.muted(0.75),
                          ),
                          label: Text(
                            'თავიდან ცდა',
                            style: TextStyle(
                              color: MobileGlassTheme.muted(0.75),
                            ),
                          ),
                          onPressed: () {
                            setState(() => _isLoading = true);
                            _loadData();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: !_hasChanges && !_isOrderPanelOpen,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isOrderPanelOpen) {
          setState(() => _isOrderPanelOpen = false);
          return;
        }
        final shouldPop = await _showExitConfirmation();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: MobileGlassScreen(
        orbs: [
          Positioned(
            top: -90,
            right: -70,
            child: MobileGlowOrb(color: MobileGlassTheme.primary, size: 240),
          ),
          Positioned(
            bottom: 80,
            left: -80,
            child: MobileGlowOrb(color: MobileGlassTheme.good, size: 220),
          ),
        ],
        body: Column(
          children: [
            if (!_isOrderPanelOpen)
              MobileGlassHeader(
                title: _orderTitle(),
                subtitle: _orderSubtitle(),
                onBack: () async {
                  if (_hasChanges) {
                    final shouldPop = await _showExitConfirmation();
                    if (shouldPop && mounted) Navigator.pop(context);
                  } else if (mounted) {
                    Navigator.pop(context);
                  }
                },
                actions: [
                  IconButton(
                    onPressed: () => setState(() => _isOrderPanelOpen = true),
                    icon: Badge(
                      isLabelVisible: _order!.items.isNotEmpty,
                      backgroundColor: MobileGlassTheme.primary,
                      label: Text('${_order!.items.length}'),
                      child: Icon(
                        Icons.shopping_cart_outlined,
                        color: MobileGlassTheme.muted(0.85),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _viewCheckPdf,
                    icon: Icon(
                      Icons.receipt_long_rounded,
                      color: MobileGlassTheme.muted(0.85),
                    ),
                  ),
                  IconButton(
                    onPressed: _cancelOrder,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: MobileGlassTheme.bad.withValues(alpha: 0.9),
                    ),
                  ),
                  if (_hasChanges)
                    TextButton.icon(
                      onPressed: _saveChanges,
                      icon: Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: MobileGlassTheme.good,
                      ),
                      label: Text(
                        'შენახვა',
                        style: TextStyle(
                          color: MobileGlassTheme.good,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            Expanded(child: _buildMainStack()),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStack() {
    if (_isOrderPanelOpen) {
      return MobileOrderDetailPanel(
        order: _order!,
        highlightKeys: _highlightKeys,
        hasChanges: _hasChanges,
        serviceFeeAvailable: false,
        orderIdLabel: _isTakeaway
            ? 'გატანა #${widget.orderId}'
            : 'შეკვეთა #${widget.orderId}',
        tableLabel: _isTakeaway
            ? 'გატანა'
            : (_order!.tableNumbers.length > 1
                  ? 'მაგიდები ${_order!.tableNumbers.join(', ')}'
                  : 'მაგიდა ${widget.tableNumber}'),
        onClose: () => setState(() => _isOrderPanelOpen = false),
        onQtyDelta: (index, delta) {
          _updateQuantity(index, delta);
          if (_order!.items.isEmpty) {
            setState(() => _isOrderPanelOpen = false);
          }
        },
        onToggleServiceFee: _toggleServiceFee,
        onSave: _hasChanges ? _saveChanges : null,
      );
    }

    return Column(
      children: [
        Expanded(child: _buildMenuSelection()),
        _buildOrderSummaryBar(),
      ],
    );
  }

  Widget _buildOrderSummaryBar() {
    if (_order == null) return const SizedBox.shrink();
    final totalItems = _order!.items.fold(0, (sum, it) => sum + it.quantity);

    return Container(
      decoration: BoxDecoration(
        color: MobileGlassTheme.surface(0.1),
        border: Border(top: BorderSide(color: MobileGlassTheme.border(0.08))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isOrderPanelOpen = true),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MobileGlassTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.menu_rounded,
                    color: MobileGlassTheme.primary,
                  ),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$totalItems პროდუქტი',
                      style: TextStyle(
                        fontSize: 12,
                        color: MobileGlassTheme.muted(),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_order!.totalAmount.toStringAsFixed(2)} ₾',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: MobileGlassTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          MobileGlassPrimaryButton(
            label: 'ნახვა',
            icon: Icons.shopping_cart_outlined,
            expand: false,
            onPressed: () => setState(() => _isOrderPanelOpen = true),
          ),
        ],
      ),
    );
  }

  List<MenuItemDB> _getDisplayItems() {
    final selectedCategory = _categories.firstWhere(
      (c) => c.slug == _selectedCategorySlug,
      orElse: () => _categories.first,
    );

    if (_selectedSubcategorySlug != null &&
        selectedCategory.subcategories != null) {
      for (final sub in selectedCategory.subcategories!) {
        if (sub.slug == _selectedSubcategorySlug) {
          return sub.items;
        }
      }
    }

    final all = <MenuItemDB>[];
    if (selectedCategory.items != null) {
      all.addAll(selectedCategory.items!);
    }
    if (selectedCategory.subcategories != null) {
      for (final sub in selectedCategory.subcategories!) {
        all.addAll(sub.items);
      }
    }
    return all;
  }

  Widget _buildMenuSelection() {
    if (_categories.isEmpty) {
      return Center(
        child: Text(
          'მენიუ ცარიელია',
          style: TextStyle(color: MobileGlassTheme.muted(0.65)),
        ),
      );
    }

    final selectedCategory = _categories.firstWhere(
      (MenuCategoryDB cat) => cat.slug == _selectedCategorySlug,
      orElse: () => _categories.first,
    );
    final displayItems = _getDisplayItems();
    final hasSubs =
        selectedCategory.subcategories != null &&
        selectedCategory.subcategories!.isNotEmpty;

    return Column(
      children: [
        _buildCategoryBar(),
        if (hasSubs) _buildSubcategoryBar(selectedCategory),
        Expanded(
          child: displayItems.isEmpty
              ? Center(
                  child: Text(
                    'პროდუქტები არ მოიძებნა',
                    style: TextStyle(color: MobileGlassTheme.muted(0.65)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: displayItems.length,
                  itemBuilder: (context, index) {
                    final item = displayItems[index];
                    final itemKey =
                        item.translationsEn['name'] ?? item.getName('ka');
                    final inCart =
                        _order?.items
                            .where((it) => it.itemKey.startsWith(itemKey))
                            .fold(0, (sum, it) => sum + it.quantity) ??
                        0;
                    final lineTotal =
                        _order?.items
                            .where((it) => it.itemKey.startsWith(itemKey))
                            .fold(0.0, (sum, it) => sum + it.total) ??
                        0.0;
                    final active = inCart > 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => _showQuantityPicker(item),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? MobileGlassTheme.primary.withValues(
                                    alpha: 0.12,
                                  )
                                : MobileGlassTheme.surfaceCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: active
                                  ? MobileGlassTheme.primary.withValues(
                                      alpha: 0.6,
                                    )
                                  : MobileGlassTheme.border(0.08),
                              width: active ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (active) ...[
                                Container(
                                  width: 30,
                                  height: 30,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: MobileGlassTheme.primary,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    '$inCart',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.getName('ka'),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: MobileGlassTheme.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Text(
                                          '${item.price?.toStringAsFixed(1) ?? "0"} ₾',
                                          style: TextStyle(
                                            color: MobileGlassTheme.accentText,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (active && lineTotal > 0) ...[
                                          Text(
                                            '  •  ',
                                            style: TextStyle(
                                              color: MobileGlassTheme.muted(
                                                0.25,
                                              ),
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            '= ${lineTotal.toStringAsFixed(1)} ₾',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: MobileGlassTheme.muted(
                                                0.6,
                                              ),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: MobileGlassTheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: MobileGlassTheme.primary,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.add_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MobileGlassTheme.border(0.08)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: MobileGlassTheme.muted(0.85)),
            onPressed: _scrollCategoryLeft,
          ),
          Expanded(
            child: ListView.builder(
              controller: _categoryScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = cat.slug == _selectedCategorySlug;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Material(
                    color: isSelected
                        ? MobileGlassTheme.primary
                        : MobileGlassTheme.surface(0.08),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          _selectedCategorySlug = cat.slug;
                          _selectedSubcategorySlug = null;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          cat.getName('ka'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? MobileGlassTheme.textPrimary
                                : MobileGlassTheme.muted(0.75),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: MobileGlassTheme.muted(0.85),
            ),
            onPressed: _scrollCategoryRight,
          ),
        ],
      ),
    );
  }

  Widget _buildSubcategoryBar(MenuCategoryDB selectedCategory) {
    final subs = selectedCategory.subcategories!;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MobileGlassTheme.border(0.06)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.chevron_left,
              size: 22,
              color: MobileGlassTheme.muted(0.85),
            ),
            onPressed: _scrollSubcategoryLeft,
          ),
          Expanded(
            child: ListView.builder(
              controller: _subcategoryScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: subs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isAll = _selectedSubcategorySlug == null;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Material(
                      color: isAll
                          ? MobileGlassTheme.muted(0.35)
                          : MobileGlassTheme.surface(0.08),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () =>
                            setState(() => _selectedSubcategorySlug = null),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            'ყველა',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isAll
                                  ? MobileGlassTheme.textPrimary
                                  : MobileGlassTheme.muted(0.75),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final sub = subs[index - 1];
                final isSelected = sub.slug == _selectedSubcategorySlug;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Material(
                    color: isSelected
                        ? MobileGlassTheme.muted(0.35)
                        : MobileGlassTheme.surface(0.08),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          setState(() => _selectedSubcategorySlug = sub.slug),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          sub.getName('ka'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? MobileGlassTheme.textPrimary
                                : MobileGlassTheme.muted(0.75),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              size: 22,
              color: MobileGlassTheme.muted(0.85),
            ),
            onPressed: _scrollSubcategoryRight,
          ),
        ],
      ),
    );
  }

  Future<bool> _showExitConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MobileGlassTheme.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'დარწმუნებული ხართ?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: MobileGlassTheme.textPrimary,
          ),
        ),
        content: Text(
          'ცვლილებები არ არის შენახული და დაიკარგება.',
          style: TextStyle(color: MobileGlassTheme.muted(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'გაუქმება',
              style: TextStyle(color: MobileGlassTheme.muted()),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: MobileGlassTheme.bad,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('გამოსვლა'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
