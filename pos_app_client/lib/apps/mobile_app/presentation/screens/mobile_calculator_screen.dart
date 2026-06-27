import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/mobile_api_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_glass_ui.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_menu_pin_sheet.dart';
import 'package:vynic/apps/windows_pos/widgets/order/helpers/service_fee_adjust_dialog.dart';

/// Mobile-native menu calculator / Count Menu.
class MobileCalculatorScreen extends StatefulWidget {
  final bool isCountMode;
  final bool selectionMode;
  final List<MenuSelectionLine> initialSelection;

  /// When non-null, the screen edits an existing counted menu (quick-order
  /// draft) instead of creating a new one: it pre-fills the cart from
  /// [initialCountItems] (resolved against the live menu by name + price),
  /// pre-fills the name with [initialName], and Confirm calls the update route.
  final String? editDraftId;
  final String? initialName;
  final List<Map<String, dynamic>> initialCountItems;

  const MobileCalculatorScreen({
    super.key,
    this.isCountMode = false,
    this.selectionMode = false,
    this.initialSelection = const [],
    this.editDraftId,
    this.initialName,
    this.initialCountItems = const [],
  });

  @override
  State<MobileCalculatorScreen> createState() => _MobileCalculatorScreenState();
}

class _MobileCalculatorScreenState extends State<MobileCalculatorScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  List<_MenuCat> _categories = [];
  int _selectedCatIndex = 0;
  int _selectedSubcatIndex = 0;

  final Map<String, int> _cart = {};
  bool _includeServiceFee = false;
  double _serviceFeeRate = 0;
  bool _serviceFeeAvailable = false;
  int _serviceFeePercent = 10;

  String _searchQuery = '';
  late TabController _tabController;
  TabController? _subTabController;

  /// Edit-mode pre-fill state (Plan A-name resolver).
  bool _editPrefillDone = false;
  final List<String> _unresolvedDraftItems = <String>[];

  static final _money = NumberFormat.currency(
    locale: 'ka_GE',
    symbol: '₾',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    for (final line in widget.initialSelection) {
      _cart[line.key] = line.qty;
    }
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        MobileApiService.getMenu(),
        MobileApiService.getRestaurantSettings(),
      ]);
      final raw = results[0] as List<dynamic>;
      final settings = results[1] as Map<String, dynamic>;
      _serviceFeeAvailable = settings['serviceFeeAvailable'] == true;
      _serviceFeePercent =
          (settings['serviceFeePercent'] as num?)?.round() ?? 10;
      _serviceFeeRate = _serviceFeeAvailable ? _serviceFeePercent / 100 : 0;
      _includeServiceFee = _serviceFeeAvailable;
      debugPrint('[CALC] Loaded raw menu: ${raw.length} categories');
      final cats = raw.cast<Map<String, dynamic>>().map(_MenuCat.fromJson).toList()
        ..sort((a, b) => _compareByWindowsOrder(a.nameKa, b.nameKa, a.slug, b.slug));

      for (final c in cats) {
        debugPrint(
          '[CALC] Category: ${c.nameKa} (Items: ${c.items.length}, Subs: ${c.subcategories.length})',
        );
        for (final s in c.subcategories) {
          debugPrint('  [SUB] ${s.nameKa} (Items: ${s.items.length})');
        }
      }

      if (mounted) {
        setState(() {
          _categories = cats;
          _tabController = TabController(length: _categories.length, vsync: this);
          _loading = false;
          _updateSubTabController();
          _applyEditPrefill();
        });
        _warnIfUnresolvedDraftItems();
        _tabController.addListener(() {
          if (!_tabController.indexIsChanging) {
            setState(() {
              _selectedCatIndex = _tabController.index;
              _selectedSubcatIndex = 0;
              _updateSubTabController();
            });
          }
        });
      }
    } catch (e) {
      debugPrint('[CALC] Error loading menu: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Edit mode: seed the cart from the draft's stored items by reconstructing
  /// each calculator key from the live menu (Plan A-name: match by Georgian name
  /// + unit price). Items that can't be matched are collected for a warning and
  /// skipped — never dropped silently.
  void _applyEditPrefill() {
    if (_editPrefillDone || widget.editDraftId == null) return;
    _editPrefillDone = true;
    for (final raw in widget.initialCountItems) {
      final name = (raw['itemName'] ?? raw['name'] ?? '').toString().trim();
      final qty = (raw['quantity'] as num?)?.toInt() ?? 0;
      final priceRaw = raw['unitPrice'] ?? raw['price'];
      final unitPrice = (priceRaw as num?)?.toDouble() ?? 0.0;
      if (name.isEmpty || qty <= 0) continue;
      final key = _resolveCartKeyForDraftItem(name, unitPrice);
      if (key == null) {
        _unresolvedDraftItems.add(name);
        continue;
      }
      _cart[key] = (_cart[key] ?? 0) + qty;
    }
  }

  /// Find the calculator cart key for a stored draft item by matching its
  /// Georgian name and unit price against the loaded menu. Returns null when no
  /// menu item matches (renamed / removed / price changed).
  String? _resolveCartKeyForDraftItem(String itemName, double unitPrice) {
    const eps = 0.001;
    final target = itemName.trim();
    for (final cat in _categories) {
      final pools = <List<_MenuItem>>[
        cat.items,
        for (final sub in cat.subcategories) sub.items,
      ];
      for (final pool in pools) {
        for (final item in pool) {
          if (item.variants.isEmpty) {
            // Base item: saved as {itemName: nameKa, unitPrice: price}.
            if (item.nameKa.trim() == target &&
                (item.price - unitPrice).abs() < eps) {
              return item.key;
            }
          } else {
            // Variant item: saved as {itemName: 'nameKa (label)',
            // unitPrice: variant.price} (see _getItemCartLines).
            for (final v in item.variants) {
              final variantName = '${item.nameKa} (${v.label})'.trim();
              if (variantName == target &&
                  (v.price - unitPrice).abs() < eps) {
                return '${item.key}_${v.size}';
              }
            }
          }
        }
      }
    }
    return null;
  }

  void _warnIfUnresolvedDraftItems() {
    if (_unresolvedDraftItems.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final names = _unresolvedDraftItems.join(', ');
      showErrorToast(
        context,
        'ვერ მოიძებნა მენიუში და გამოტოვებულია: $names',
      );
    });
  }

  void _updateSubTabController() {
    _subTabController?.dispose();
    final cat = _categories[_selectedCatIndex];
    if (cat.subcategories.isNotEmpty) {
      _subTabController = TabController(
        length: cat.subcategories.length,
        vsync: this,
      );
      _subTabController!.addListener(() {
        if (!_subTabController!.indexIsChanging) {
          setState(() => _selectedSubcatIndex = _subTabController!.index);
        }
      });
    } else {
      _subTabController = null;
    }
  }

  @override
  void dispose() {
    if (!_loading && _categories.isNotEmpty) {
      _tabController.dispose();
      _subTabController?.dispose();
    }
    super.dispose();
  }

  double get _subtotal {
    double total = 0;
    for (final cat in _categories) {
      for (final it in cat.items) {
        total += _calcItemSubtotal(it);
      }
      for (final sub in cat.subcategories) {
        for (final it in sub.items) {
          total += _calcItemSubtotal(it);
        }
      }
    }
    return total;
  }

  double _calcItemSubtotal(_MenuItem it) {
    double sum = 0;
    if (it.variants.isEmpty) {
      sum += (it.price * (_cart[it.key] ?? 0));
    } else {
      for (final v in it.variants) {
        sum += (v.price * (_cart['${it.key}_${v.size}'] ?? 0));
      }
    }
    return sum;
  }

  double get _serviceFee => _includeServiceFee ? _subtotal * _serviceFeeRate : 0.0;
  double get _total => _subtotal + _serviceFee;
  int get _totalItems => _cart.values.fold(0, (sum, qty) => sum + qty);

  /// Long-press on the service-fee row: change the percentage / include flag,
  /// same adjust dialog used elsewhere. [refreshSheet] repaints the open modal.
  Future<void> _openServiceFeeConfig(StateSetter refreshSheet) async {
    if (!_serviceFeeAvailable) return;
    final result = await showDialog<ServiceFeeAdjustResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceFeeAdjustDialog(
        initialIncludeServiceFee: _includeServiceFee,
        initialPercentage: _serviceFeePercent.toDouble(),
        defaultPercentage: _serviceFeePercent.toDouble(),
      ),
    );
    if (result == null || !mounted) return;
    final pct = result.percentage.clamp(0.0, 100.0);
    setState(() {
      _includeServiceFee = result.includeServiceFee;
      _serviceFeePercent = pct.round();
      _serviceFeeRate = pct / 100;
    });
    refreshSheet(() {});
    if (mounted) showSuccessToast(context, 'სერვისის პარამეტრები განახლდა');
  }

  List<_CartLine> get _cartLines {
    final lines = <_CartLine>[];
    for (final cat in _categories) {
      for (final item in cat.items) {
        lines.addAll(_getItemCartLines(item));
      }
      for (final sub in cat.subcategories) {
        for (final item in sub.items) {
          lines.addAll(_getItemCartLines(item));
        }
      }
    }
    return lines;
  }

  List<_CartLine> _getItemCartLines(_MenuItem it) {
    final list = <_CartLine>[];
    if (it.variants.isEmpty) {
      final qty = _cart[it.key] ?? 0;
      if (qty > 0) {
        list.add(_CartLine(item: it, qty: qty, key: it.key));
      }
    } else {
      for (final v in it.variants) {
        final key = '${it.key}_${v.size}';
        final qty = _cart[key] ?? 0;
        if (qty > 0) {
          list.add(
            _CartLine(
              item: _MenuItem(
                nameKa: '${it.nameKa} (${v.label})',
                nameEn: '${it.nameEn} (${v.label})',
                price: v.price,
                variants: [],
              ),
              qty: qty,
              key: key,
            ),
          );
        }
      }
    }
    return list;
  }

  void _increment(_MenuItem item, {double? size, double? price, int qty = 1}) {
    final key = size == null ? item.key : '${item.key}_$size';
    setState(() => _cart[key] = (_cart[key] ?? 0) + qty);
  }

  void _onItemTap(_MenuItem item, {int? initialQty, String? cartKey}) async {
    await _openPinSheet(item, cartKey: cartKey, addMode: false);
  }

  Future<void> _openPinSheet(
    _MenuItem item, {
    String? cartKey,
    bool addMode = false,
  }) async {
    final variants = item.variants
        .map((v) => MenuPinVariant(label: v.label, price: v.price, tag: v))
        .toList();

    final resolvedKey = item.variants.isEmpty
        ? item.key
        : (cartKey ?? '${item.key}_${item.variants.first.size}');

    final currentInCart = _cart[resolvedKey] ?? 0;

    final result = await showMobileMenuPinSheet(
      context,
      itemName: item.nameKa,
      unitPrice: item.price,
      variants: variants,
      inCartQty: currentInCart,
      addMode: addMode,
    );
    if (result == null) return;

    final qty = result.qty;
    final v = result.variant?.tag as _MenuVariant?;
    final finalKey = v != null ? '${item.key}_${v.size}' : item.key;

    setState(() {
      if (addMode) {
        _cart[finalKey] = currentInCart + qty;
      } else {
        if (cartKey != null && cartKey != finalKey) _cart.remove(cartKey);
        if (qty <= 0) {
          _cart.remove(finalKey);
        } else {
          _cart[finalKey] = qty;
        }
      }
    });
  }

  void _openSelectionQuantityDialog(
    _MenuItem item, {
    int totalQty = 0,
    bool addMore = false,
  }) {
    _openPinSheet(item, addMode: addMore);
  }

  void _decrement(String key) {
    final cur = _cart[key] ?? 0;
    setState(() {
      if (cur <= 1) {
        _cart.remove(key);
      } else {
        _cart[key] = cur - 1;
      }
    });
  }

  _MenuItem? _findMenuItemForCartKey(String cartKey) {
    for (final cat in _categories) {
      for (final item in cat.items) {
        if (_menuItemMatchesCartKey(item, cartKey)) return item;
      }
      for (final sub in cat.subcategories) {
        for (final item in sub.items) {
          if (_menuItemMatchesCartKey(item, cartKey)) return item;
        }
      }
    }
    return null;
  }

  bool _menuItemMatchesCartKey(_MenuItem item, String cartKey) {
    if (item.key == cartKey) return true;
    for (final v in item.variants) {
      if ('${item.key}_${v.size}' == cartKey) return true;
    }
    return false;
  }

  Future<void> _saveCount() async {
    if (_cart.isEmpty) return;

    final isEdit = widget.editDraftId != null;
    final nameController = TextEditingController(text: widget.initialName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'მენიუს განახლება' : 'მენიუს შენახვა'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: 'შეიყვანეთ სახელი (მაგ. ბანკეტი #1)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('გაუქმება'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: Text(isEdit ? 'დადასტურება' : 'შენახვა'),
          ),
        ],
      ),
    );

    if (name == null) return;

    try {
      final items = _cartLines
          .map((l) => {'itemName': l.item.nameKa, 'quantity': l.qty, 'unitPrice': l.item.price})
          .toList();
      final resolvedName = name.isEmpty
          ? 'დათვლილი ${DateFormat('HH:mm').format(DateTime.now())}'
          : name;

      if (isEdit) {
        // Edit mode: update the existing draft instead of creating a new one.
        await MobileApiService.updateCountedMenu(
          draftId: widget.editDraftId!,
          name: resolvedName,
          items: items,
          subtotal: _subtotal,
          includeServiceFee: _serviceFeeAvailable && _includeServiceFee,
        );
      } else {
        await MobileApiService.saveCountedMenu(
          name: resolvedName,
          items: items,
          subtotal: _subtotal,
          includeServiceFee: _serviceFeeAvailable && _includeServiceFee,
          createdBy: 'Manager',
        );
      }

      if (mounted) {
        showSuccessToast(
          context,
          isEdit ? 'წარმატებით განახლდა' : 'წარმატებით შეინახა',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'შენახვა ვერ მოხერხდა: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MobileGlassTheme.bg,
      appBar: AppBar(
        title: Text(
          widget.editDraftId != null
              ? 'მენიუს რედაქტირება'
              : (widget.isCountMode ? 'მენიუს დათვლა' : 'მენიუ'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: MobileGlassTheme.bg,
        foregroundColor: MobileGlassTheme.textPrimary,
        iconTheme: IconThemeData(color: MobileGlassTheme.textPrimary),
        elevation: 0,
        bottom: (_loading || _categories.isEmpty)
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: MobileGlassTheme.textPrimary,
                unselectedLabelColor: MobileGlassTheme.textSecondary,
                indicatorColor: MobileGlassTheme.primary,
                indicatorWeight: 3,
                dividerColor: Colors.transparent,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: _categories.map((c) => Tab(text: c.nameKa)).toList(),
              ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: MobileGlassTheme.primary),
            )
          : _error != null
          ? _buildError()
          : Column(
              children: [
                if (_subTabController != null && _searchQuery.isEmpty)
                  SizedBox(
                    height: 52,
                    child: TabBar(
                      controller: _subTabController,
                      isScrollable: true,
                      labelColor: MobileGlassTheme.textPrimary,
                      unselectedLabelColor: MobileGlassTheme.textSecondary,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: MobileGlassTheme.primary,
                      ),
                      indicatorPadding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 4,
                      ),
                      tabs: _categories[_selectedCatIndex].subcategories
                          .map(
                            (s) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                s.nameKa,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                _buildSearchBar(),
                Expanded(child: _buildItemGrid()),
                _buildCartSummary(),
              ],
            ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: MobileGlassTheme.textSecondary),
            SizedBox(height: 12),
            Text(
              'მენიუ ვერ ჩაიტვირთა',
              style: TextStyle(color: MobileGlassTheme.textPrimary, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _loadMenu,
              icon: Icon(Icons.refresh_rounded),
              label: Text('თავიდან ცდა'),
            ),
          ],
        ),
      );

  Widget _buildSearchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: TextField(
          style: TextStyle(color: MobileGlassTheme.textPrimary, fontSize: 15),
          cursorColor: MobileGlassTheme.primary,
          decoration: InputDecoration(
            hintText: 'პროდუქტის ძიება...',
            hintStyle: TextStyle(color: MobileGlassTheme.textSecondary),
            prefixIcon: Icon(Icons.search_rounded, color: MobileGlassTheme.textSecondary),
            filled: true,
            fillColor: MobileGlassTheme.surface(0.05),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: MobileGlassTheme.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: MobileGlassTheme.primary),
            ),
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
      );

  Widget _buildItemGrid() {
    final List<_MenuItem> items;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = _categories
          .expand((c) {
            final all = [...c.items];
            for (final sub in c.subcategories) {
              all.addAll(sub.items);
            }
            return all;
          })
          .where(
            (it) =>
                it.nameKa.toLowerCase().contains(q) ||
                it.nameEn.toLowerCase().contains(q),
          )
          .toList();
    } else {
      final cat = _categories[_selectedCatIndex];
      debugPrint('[CALC] Grid Build - Cat: ${cat.nameKa}, SubIndex: $_selectedSubcatIndex');
      if (cat.subcategories.isNotEmpty) {
        if (_selectedSubcatIndex < cat.subcategories.length) {
          items = cat.subcategories[_selectedSubcatIndex].items;
          debugPrint('[CALC] Showing subcategory items: ${items.length}');
        } else {
          items = [];
          debugPrint('[CALC] Selected subindex out of range');
        }
      } else {
        items = cat.items;
        debugPrint('[CALC] Showing root items: ${items.length}');
      }
    }

    if (items.isEmpty) {
      debugPrint('[CALC] Items list is EMPTY');
      return Center(
        child: Text('პროდუქტი ვერ მოიძებნა', style: TextStyle(color: MobileGlassTheme.textSecondary)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => SizedBox(height: 10),
      itemBuilder: (context, i) => _buildItemRow(items[i]),
    );
  }

  /// Full-width, compact menu row: 1 product per line.
  Widget _buildItemRow(_MenuItem item) {
    final hasVariants = item.variants.isNotEmpty;
    int totalQty = 0;
    if (!hasVariants) {
      totalQty = _cart[item.key] ?? 0;
    } else {
      for (final v in item.variants) {
        totalQty += _cart['${item.key}_${v.size}'] ?? 0;
      }
    }

    final bool active = totalQty > 0;
    final double lineTotal = _calcItemSubtotal(item);

    return GestureDetector(
      onTap: () {
        if (widget.selectionMode) {
          _openSelectionQuantityDialog(item, totalQty: totalQty);
        } else {
          _onItemTap(item);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? MobileGlassTheme.primary.withValues(alpha: 0.12)
              : MobileGlassTheme.surface(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? MobileGlassTheme.primary.withValues(alpha: 0.6) : MobileGlassTheme.borderSubtle,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Qty badge bubble on the left when active (quick visual count).
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
                  '$totalQty',
                  style: TextStyle(
                    color: MobileGlassTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nameKa,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: MobileGlassTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        hasVariants
                            ? 'დან ${_money.format(item.variants.first.price)}'
                            : _money.format(item.price),
                        style: TextStyle(
                          fontSize: 13,
                          color: MobileGlassTheme.accentText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (active && lineTotal > 0) ...[
                        Text(
                          '  •  ',
                          style: TextStyle(
                            color: MobileGlassTheme.muted(0.25),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '= ${_money.format(lineTotal)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: MobileGlassTheme.muted(0.6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 10),
            _buildRowTrailing(item, hasVariants, totalQty),
          ],
        ),
      ),
    );
  }

  Widget _buildRowTrailing(_MenuItem item, bool hasVariants, int totalQty) {
    if (widget.selectionMode) {
      return _circleBtn(
        Icons.add_rounded,
        filled: true,
        onTap: () => _openSelectionQuantityDialog(item, totalQty: totalQty, addMore: true),
      );
    }

    // Variant items always go through the sheet (size selection).
    if (hasVariants) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MobileGlassTheme.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MobileGlassTheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ვარიანტები',
              style: TextStyle(
                color: MobileGlassTheme.accentText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.tune_rounded, size: 15, color: MobileGlassTheme.accentText),
          ],
        ),
      );
    }

    // No-variant items: inline stepper / add button.
    if (totalQty == 0) {
      return _circleBtn(
        Icons.add_rounded,
        filled: true,
        onTap: () => _increment(item),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleBtn(
          Icons.remove_rounded,
          onTap: () => _decrement(item.key),
        ),
        SizedBox(width: 6),
        _circleBtn(
          Icons.add_rounded,
          filled: true,
          onTap: () => _increment(item),
        ),
      ],
    );
  }

  Widget _circleBtn(IconData icon, {bool filled = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? MobileGlassTheme.primary : MobileGlassTheme.surface(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled ? MobileGlassTheme.primary : MobileGlassTheme.borderSubtle,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: filled ? Colors.white : MobileGlassTheme.textPrimary,
        ),
      ),
    );
  }

  void _showCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: MobileGlassTheme.surfaceCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: MobileGlassTheme.borderSubtle)),
          ),
          child: Column(
            children: [
              SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MobileGlassTheme.muted(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'დამატებული პროდუქტები',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: MobileGlassTheme.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_sweep_rounded,
                        color: Color(0xFFEF4444),
                      ),
                      onPressed: () {
                        setState(() => _cart.clear());
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _cartLines.length,
                  separatorBuilder: (context, i) =>
                      Divider(color: MobileGlassTheme.surface(0.07)),
                  itemBuilder: (context, i) {
                    final line = _cartLines[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      line.item.nameKa,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: MobileGlassTheme.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      _money.format(line.item.price),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: MobileGlassTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _money.format(line.item.price * line.qty),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: MobileGlassTheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _qtyBtnMini(Icons.remove_rounded, () {
                                _decrement(line.key);
                                setModalState(() {});
                                if (_cart.isEmpty) {
                                  Navigator.pop(context);
                                }
                              }),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  '${line.qty}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: MobileGlassTheme.textPrimary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              _qtyBtnMini(Icons.add_rounded, () {
                                setState(
                                  () => _cart[line.key] =
                                      (_cart[line.key] ?? 0) + 1,
                                );
                                setModalState(() {});
                              }),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() => _cart.remove(line.key));
                                  setModalState(() {});
                                  if (_cart.isEmpty) {
                                    Navigator.pop(context);
                                  }
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Color(0xFFEF4444),
                                ),
                                label: const Text(
                                  'წაშლა',
                                  style: TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  24,
                  20,
                  24,
                  20 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: MobileGlassTheme.surfaceElevated,
                  border: Border(top: BorderSide(color: MobileGlassTheme.borderSubtle)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_serviceFeeAvailable) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ქვეჯამი',
                            style: TextStyle(
                              fontSize: 13,
                              color: MobileGlassTheme.muted(0.55),
                            ),
                          ),
                          Text(
                            _money.format(_subtotal),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: MobileGlassTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onLongPress: () =>
                                  _openServiceFeeConfig(setModalState),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'სერვისი ($_serviceFeePercent%)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: MobileGlassTheme.muted(0.55),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.tune_rounded,
                                    size: 14,
                                    color: MobileGlassTheme.muted(0.4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: _includeServiceFee,
                            activeColor: MobileGlassTheme.primary,
                            onChanged: (v) {
                              setState(() => _includeServiceFee = v);
                              setModalState(() {});
                            },
                          ),
                          SizedBox(
                            width: 72,
                            child: Text(
                              _money.format(_serviceFee),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: MobileGlassTheme.accentText,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(color: MobileGlassTheme.borderSubtle),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'სულ გადასახდელი',
                          style: TextStyle(
                            fontSize: 13,
                            color: MobileGlassTheme.textSecondary,
                          ),
                        ),
                        Text(
                          _money.format(_total),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: MobileGlassTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (widget.isCountMode)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _saveCount();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MobileGlassTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'შენახვა',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            final selected = _cartLines
                                .map(
                                  (line) => MenuSelectionLine(
                                    key: line.key,
                                    itemName: line.item.nameKa,
                                    unitPrice: line.item.price,
                                    qty: line.qty,
                                  ),
                                )
                                .toList();
                            Navigator.pop(context);
                            Navigator.pop(this.context, selected);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MobileGlassTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'დასრულება',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
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

  Widget _qtyBtnMini(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: MobileGlassTheme.surface(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MobileGlassTheme.borderSubtle),
        ),
        child: Icon(icon, size: 18, color: MobileGlassTheme.textPrimary),
      ),
    );
  }

  Widget _buildCartSummary() {
    final lines = _cartLines;
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: MobileGlassTheme.surfaceCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: MobileGlassTheme.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: _showCartSheet,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: MobileGlassTheme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.shopping_cart_outlined,
                      color: MobileGlassTheme.accentText),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_totalItems პროდუქტი',
                      style: TextStyle(
                        fontSize: 12,
                        color: MobileGlassTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _money.format(_total),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: MobileGlassTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _showCartSheet,
            style: ElevatedButton.styleFrom(
              backgroundColor: MobileGlassTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              widget.selectionMode ? 'ნახვა' : 'შეკვეთის ნახვა',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class MenuSelectionLine {
  final String key;
  final String itemName;
  final double unitPrice;
  final int qty;
  const MenuSelectionLine({
    required this.key,
    required this.itemName,
    required this.unitPrice,
    required this.qty,
  });
}

class _MenuCat {
  final String slug;
  final String nameKa;
  final String nameEn;
  final List<_MenuItem> items;
  final List<_MenuSubcat> subcategories;
  const _MenuCat({
    required this.slug,
    required this.nameKa,
    required this.nameEn,
    required this.items,
    required this.subcategories,
  });
  factory _MenuCat.fromJson(Map<String, dynamic> j) => _MenuCat(
        slug: j['slug'] as String? ?? '',
        nameKa: j['nameKa'] as String? ?? '',
        nameEn: j['nameEn'] as String? ?? '',
        items: ((j['items'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(_MenuItem.fromJson)
            .toList(),
        subcategories: (((j['subcategories'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(_MenuSubcat.fromJson)
            .toList()
          ..sort(
            (a, b) => _compareByWindowsOrder(a.nameKa, b.nameKa, a.slug, b.slug),
          )),
      );
}

class _MenuSubcat {
  final String slug;
  final String nameKa;
  final String nameEn;
  final List<_MenuItem> items;
  const _MenuSubcat({
    required this.slug,
    required this.nameKa,
    required this.nameEn,
    required this.items,
  });
  factory _MenuSubcat.fromJson(Map<String, dynamic> j) => _MenuSubcat(
        slug: j['slug'] as String? ?? '',
        nameKa: j['nameKa'] as String? ?? '',
        nameEn: j['nameEn'] as String? ?? '',
        items: ((j['items'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(_MenuItem.fromJson)
            .toList(),
      );
}

class _MenuVariant {
  final double size;
  final double price;
  const _MenuVariant({required this.size, required this.price});
  factory _MenuVariant.fromJson(Map<String, dynamic> j) => _MenuVariant(
        size: (j['size'] as num?)?.toDouble() ?? 0.0,
        price: (j['price'] as num?)?.toDouble() ?? 0.0,
      );
  String get label {
    if (size < 1) return '${(size * 1000).toInt()} ml';
    return '${size.toStringAsFixed(1)} L';
  }
}

class _MenuItem {
  final String nameKa;
  final String nameEn;
  final double price;
  final List<_MenuVariant> variants;
  const _MenuItem({
    required this.nameKa,
    required this.nameEn,
    required this.price,
    required this.variants,
  });
  String get key => '${nameEn}_$nameKa';
  factory _MenuItem.fromJson(Map<String, dynamic> j) => _MenuItem(
        nameKa: j['nameKa'] as String? ?? '',
        nameEn: j['nameEn'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0.0,
        variants: ((j['variants'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(_MenuVariant.fromJson)
            .toList(),
      );
}

class _CartLine {
  final _MenuItem item;
  final int qty;
  final String key;
  const _CartLine({required this.item, required this.qty, required this.key});
}

int _compareByWindowsOrder(String aName, String bName, String aSlug, String bSlug) {
  int rank(String rawName, String rawSlug) {
    final n = rawName.toLowerCase();
    final s = rawSlug.toLowerCase();
    if (n.contains('ცივი') || s.contains('cold')) return 0;
    if (n.contains('ცხელი') || s.contains('hot')) return 1;
    if (n.contains('წვნიანი') || s.contains('soup')) return 2;
    if (n.contains('სალათა') || s.contains('salad')) return 3;
    if (n.contains('გარნირი') || s.contains('garnish') || s.contains('side')) {
      return 4;
    }
    if (n.contains('დესერტ') || s.contains('dessert')) return 5;
    if (n.contains('უალკოჰოლო') || s.contains('soft') || s.contains('non-alcohol')) {
      return 6;
    }
    if (n.contains('ალკოჰოლ') || s.contains('alcohol') || s.contains('beer') || s.contains('wine')) {
      return 7;
    }
    if (n.contains('ყავა') || s.contains('coffee') || s.contains('tea')) return 8;
    return 100;
  }

  final ra = rank(aName, aSlug);
  final rb = rank(bName, bSlug);
  if (ra != rb) return ra.compareTo(rb);
  return aName.compareTo(bName);
}
