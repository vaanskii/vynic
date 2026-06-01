import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/mobile_api_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

/// Mobile-native menu calculator / Count Menu.
class MobileCalculatorScreen extends StatefulWidget {
  final bool isCountMode;
  final bool selectionMode;
  final List<MenuSelectionLine> initialSelection;
  const MobileCalculatorScreen({
    super.key,
    this.isCountMode = false,
    this.selectionMode = false,
    this.initialSelection = const [],
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

  // Dark "glass" palette (matches the dashboard / tables tabs).
  static const _bg = Color(0xFF050508);
  static const _accent = Color(0xFF6366F1);
  static const _accentText = Color(0xFFC7D2FE);
  static const _surface = Color(0xFF15151C);
  static const _textPrimary = Colors.white;
  static const _muted = Color(0xFF9AA0AE);
  static const _cardBorder = Color(0x14FFFFFF);
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
        });
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
                variants: const [],
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
    _MenuVariant? selectedVariant;
    if (cartKey != null && item.variants.isNotEmpty) {
      for (final v in item.variants) {
        if ('${item.key}_${v.size}' == cartKey) {
          selectedVariant = v;
          break;
        }
      }
    } else if (item.variants.isNotEmpty) {
      selectedVariant = item.variants.first;
    }

    int selectedQty = initialQty ?? 1;
    final TextEditingController qtyController = TextEditingController(
      text: selectedQty.toString(),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AnimatedPadding(
          padding: MediaQuery.of(context).viewInsets,
          duration: const Duration(milliseconds: 100),
          child: Container(
            decoration: const BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              border: Border(top: BorderSide(color: _cardBorder)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  item.nameKa,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  selectedVariant != null
                      ? '${_money.format(selectedVariant!.price)} (${selectedVariant!.label})'
                      : '${_money.format(item.price)} / ცალი',
                  style: const TextStyle(color: _muted, fontSize: 14),
                ),
                if (item.variants.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    children: item.variants.map((v) {
                      final isSel = selectedVariant == v;
                      return ChoiceChip(
                        label: Text(v.label),
                        selected: isSel,
                        onSelected: (val) {
                          if (val) {
                            setModalState(() => selectedVariant = v);
                          }
                        },
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        selectedColor: _accent,
                        side: BorderSide(
                          color: isSel ? _accent : _cardBorder,
                        ),
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _modalQtyBtn(Icons.remove_rounded, () {
                      if (selectedQty > 1) {
                        setModalState(() {
                          selectedQty--;
                          qtyController.text = selectedQty.toString();
                        });
                      }
                    }),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                        decoration: const InputDecoration(border: InputBorder.none),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            selectedQty = parsed;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 20),
                    _modalQtyBtn(Icons.add_rounded, () {
                      setModalState(() {
                        selectedQty++;
                        qtyController.text = selectedQty.toString();
                      });
                    }),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _quickAddBtn('+5', () {
                      setModalState(() {
                        selectedQty += 5;
                        qtyController.text = selectedQty.toString();
                      });
                    }),
                    const SizedBox(width: 12),
                    _quickAddBtn('+10', () {
                      setModalState(() {
                        selectedQty += 10;
                        qtyController.text = selectedQty.toString();
                      });
                    }),
                    const SizedBox(width: 12),
                    _quickAddBtn('+20', () {
                      setModalState(() {
                        selectedQty += 20;
                        qtyController.text = selectedQty.toString();
                      });
                    }),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      final finalQty =
                          int.tryParse(qtyController.text) ?? selectedQty;
                      Navigator.pop(context);
                      if (cartKey != null) {
                        setState(() {
                          if (finalQty <= 0) {
                            _cart.remove(cartKey);
                          } else {
                            _cart[cartKey] = finalQty;
                          }
                        });
                      } else {
                        _increment(
                          item,
                          size: selectedVariant?.size,
                          price: selectedVariant?.price,
                          qty: finalQty,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'დამატება',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickAddBtn(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, color: _accentText),
      ),
      onPressed: onTap,
      backgroundColor: _accent.withValues(alpha: 0.15),
      side: BorderSide(color: _accent.withValues(alpha: 0.4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _modalQtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          shape: BoxShape.circle,
          border: Border.all(color: _cardBorder),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
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

  Future<void> _saveCount() async {
    if (_cart.isEmpty) return;

    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('მენიუს შენახვა'),
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
            child: const Text('გაუქმება'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('შენახვა'),
          ),
        ],
      ),
    );

    if (name == null) return;

    try {
      final items = _cartLines
          .map((l) => {'itemName': l.item.nameKa, 'quantity': l.qty, 'unitPrice': l.item.price})
          .toList();

      await MobileApiService.saveCountedMenu(
        name: name.isEmpty
            ? 'დათვლილი ${DateFormat('HH:mm').format(DateTime.now())}'
            : name,
        items: items,
        subtotal: _subtotal,
        includeServiceFee: _serviceFeeAvailable && _includeServiceFee,
        createdBy: 'Manager',
      );

      if (mounted) {
        showSuccessToast(context, 'წარმატებით შეინახა');
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
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          widget.isCountMode ? 'მენიუს დათვლა' : 'მენიუ',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        bottom: (_loading || _categories.isEmpty)
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: _muted,
                indicatorColor: _accent,
                indicatorWeight: 3,
                dividerColor: Colors.transparent,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: _categories.map((c) => Tab(text: c.nameKa)).toList(),
              ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accent),
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
                      labelColor: Colors.white,
                      unselectedLabelColor: _muted,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: _accent,
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
            const Icon(Icons.wifi_off_rounded, size: 48, color: _muted),
            const SizedBox(height: 12),
            const Text(
              'მენიუ ვერ ჩაიტვირთა',
              style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _loadMenu,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('თავიდან ცდა'),
            ),
          ],
        ),
      );

  Widget _buildSearchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: TextField(
          style: const TextStyle(color: Colors.white, fontSize: 15),
          cursorColor: _accent,
          decoration: InputDecoration(
            hintText: 'პროდუქტის ძიება...',
            hintStyle: const TextStyle(color: _muted),
            prefixIcon: const Icon(Icons.search_rounded, color: _muted),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _accent),
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
      return const Center(
        child: Text('პროდუქტი ვერ მოიძებნა', style: TextStyle(color: _muted)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
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
      onTap: () => _onItemTap(item),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? _accent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? _accent.withValues(alpha: 0.6) : _cardBorder,
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
                  color: _accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$totalQty',
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
                    item.nameKa,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        hasVariants
                            ? 'დან ${_money.format(item.variants.first.price)}'
                            : _money.format(item.price),
                        style: const TextStyle(
                          fontSize: 13,
                          color: _accentText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (active && lineTotal > 0) ...[
                        Text(
                          '  •  ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '= ${_money.format(lineTotal)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.6),
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
            _buildRowTrailing(item, hasVariants, totalQty),
          ],
        ),
      ),
    );
  }

  Widget _buildRowTrailing(_MenuItem item, bool hasVariants, int totalQty) {
    // Variant items always go through the sheet (size selection).
    if (hasVariants) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'ვარიანტები',
              style: TextStyle(
                color: _accentText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.tune_rounded, size: 15, color: _accentText),
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
        const SizedBox(width: 6),
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
          color: filled ? _accent : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled ? _accent : _cardBorder,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: filled ? Colors.white : Colors.white.withValues(alpha: 0.8),
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
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: _cardBorder)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'დამატებული პროდუქტები',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
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
                      Divider(color: Colors.white.withValues(alpha: 0.07)),
                  itemBuilder: (context, i) {
                    final line = _cartLines[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.item.nameKa,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  _money.format(line.item.price),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _qtyBtnMini(Icons.remove_rounded, () {
                                _decrement(line.key);
                                setModalState(() {});
                                if (_cart.isEmpty) {
                                  Navigator.pop(context);
                                }
                              }),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '${line.qty}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              _qtyBtnMini(Icons.add_rounded, () {
                                setState(
                                  () => _cart[line.key] = (_cart[line.key] ?? 0) + 1,
                                );
                                setModalState(() {});
                              }),
                            ],
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 80,
                            child: Text(
                              _money.format(line.item.price * line.qty),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _accent,
                              ),
                              textAlign: TextAlign.end,
                            ),
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
                decoration: const BoxDecoration(
                  color: Color(0xFF0C0C12),
                  border: Border(top: BorderSide(color: _cardBorder)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_serviceFeeAvailable) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'ქვეჯამი',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                                Text(
                                  _money.format(_subtotal),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'სერვისი ($_serviceFeePercent%)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Colors.white.withValues(alpha: 0.55),
                                    ),
                                  ),
                                ),
                                Switch.adaptive(
                                  value: _includeServiceFee,
                                  activeColor: _accent,
                                  onChanged: (v) {
                                    setState(() => _includeServiceFee = v);
                                    setModalState(() {});
                                  },
                                ),
                                Text(
                                  _money.format(_serviceFee),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _accentText,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          const Text(
                            'სულ გადასახდელი',
                            style: TextStyle(fontSize: 12, color: _muted),
                          ),
                          Text(
                            _money.format(_total),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (widget.isCountMode)
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _saveCount();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'შენახვა',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      )
                    else
                      ElevatedButton(
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
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'დასრულება',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _cardBorder),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  Widget _buildCartSummary() {
    final lines = _cartLines;
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: _cardBorder)),
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
                    color: _accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shopping_cart_outlined,
                      color: _accentText),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_totalItems პროდუქტი',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _muted,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _money.format(_total),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'შეკვეთის ნახვა',
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
