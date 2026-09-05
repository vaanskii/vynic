part of '../mobile_admin_screen.dart';

enum _InventorySection { stockItems, suppliers, receiving }

class InventoryAdminTab extends StatefulWidget {
  const InventoryAdminTab({
    super.key,
    this.loadStockItems,
    this.loadSuppliers,
    this.loadReceivings,
    this.initialSection,
  });

  final Future<List<StockItem>> Function()? loadStockItems;
  final Future<List<Supplier>> Function()? loadSuppliers;
  final Future<ReceivingPage> Function()? loadReceivings;

  /// Test seam only. The console always opens on Stock Items.
  final int? initialSection;

  @override
  State<InventoryAdminTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryAdminTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late _InventorySection _section =
      _InventorySection.values[widget.initialSection ?? 0];
  final _search = TextEditingController();
  List<StockItem> _stockItems = const [];
  List<Supplier> _suppliers = const [];
  List<Receiving> _receivings = const [];
  _ReceivingStatusFilter _statusFilter = _ReceivingStatusFilter.all;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.loadStockItems?.call() ?? MobileApiService.getStockItems(),
        widget.loadSuppliers?.call() ?? MobileApiService.getSuppliers(),
        widget.loadReceivings?.call() ?? MobileApiService.getReceivings(),
      ]);
      if (!mounted) return;
      setState(() {
        _stockItems = results[0] as List<StockItem>;
        _suppliers = results[1] as List<Supplier>;
        _receivings = (results[2] as ReceivingPage).receivings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const _AdminLoading();
    if (_error != null) return _ErrorWidget(onRetry: _load);

    return RefreshIndicator(
      color: AdminTheme.primary,
      backgroundColor: AdminTheme.surface,
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 720 ? 24.0 : 16.0;
          return ListView(
            key: const Key('inventory-admin-list'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              horizontal,
              12,
              horizontal,
              MediaQuery.paddingOf(context).bottom + 108,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionSelector(),
                      const SizedBox(height: 12),
                      _searchAndAdd(constraints.maxWidth),
                      const SizedBox(height: 18),
                      if (_section == _InventorySection.stockItems)
                        _stockItemList()
                      else if (_section == _InventorySection.suppliers)
                        _supplierList()
                      else
                        _receivingList(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionSelector() {
    return SegmentedButton<_InventorySection>(
      key: const Key('inventory-section-selector'),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: _InventorySection.stockItems,
          icon: Icon(Icons.inventory_2_outlined),
          label: Text('პროდუქტები'),
        ),
        ButtonSegment(
          value: _InventorySection.suppliers,
          icon: Icon(Icons.local_shipping_outlined),
          label: Text('მომწოდებლები'),
        ),
        ButtonSegment(
          value: _InventorySection.receiving,
          icon: Icon(Icons.receipt_long_outlined),
          label: Text('მიღებები'),
        ),
      ],
      selected: {_section},
      onSelectionChanged: (selection) {
        setState(() {
          _section = selection.single;
          _search.clear();
        });
      },
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AdminTheme.textMuted,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AdminTheme.primary
              : AdminTheme.surface,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: AdminTheme.border)),
      ),
    );
  }

  Widget _searchAndAdd(double width) {
    final search = TextField(
      key: const Key('inventory-search'),
      controller: _search,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: AdminTheme.text),
      decoration:
          _adminInput(
            _section == _InventorySection.receiving
                ? 'ძებნა ზედნადებით ან მომწოდებლით'
                : 'ძებნა სახელით ან კოდით',
          ).copyWith(
            prefixIcon: Icon(Icons.search_rounded, color: AdminTheme.textDim),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'გასუფთავება',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
    );
    final add = FilledButton.icon(
      key: const Key('inventory-add'),
      onPressed: switch (_section) {
        _InventorySection.stockItems => () => _editStockItem(),
        _InventorySection.suppliers => () => _editSupplier(),
        _InventorySection.receiving => () => _editReceiving(),
      },
      icon: const Icon(Icons.add_rounded),
      label: Text(switch (_section) {
        _InventorySection.stockItems => 'პროდუქტის დამატება',
        _InventorySection.suppliers => 'მომწოდებლის დამატება',
        _InventorySection.receiving => 'მიღების დამატება',
      }),
      style: FilledButton.styleFrom(
        backgroundColor: AdminTheme.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
      ),
    );
    if (width < 620) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [search, const SizedBox(height: 10), add],
      );
    }
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 12),
        add,
      ],
    );
  }

  Widget _stockItemList() {
    final query = _search.text.trim().toLowerCase();
    final items = _stockItems
        .where((item) {
          return query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              (item.sku?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    if (items.isEmpty) {
      return _InventoryEmptyState(
        icon: Icons.inventory_2_outlined,
        title: query.isEmpty
            ? 'საწყობის პროდუქტები ჯერ არ არის'
            : 'შესაბამისი პროდუქტი ვერ მოიძებნა',
        subtitle: query.isEmpty
            ? 'დაამატეთ ინგრედიენტი ან შეფუთული პროდუქტი.'
            : 'შეცვალეთ საძიებო სიტყვა.',
      );
    }
    return Column(
      key: const Key('stock-item-list'),
      children: [
        for (final item in items)
          _StockItemCard(
            item: item,
            onEdit: () => _editStockItem(item),
            onToggle: () => _toggleStockItem(item),
            onOpen: () => _openStockItem(item),
          ),
      ],
    );
  }

  Widget _supplierList() {
    final query = _search.text.trim().toLowerCase();
    final items = _suppliers
        .where((supplier) {
          return query.isEmpty ||
              supplier.name.toLowerCase().contains(query) ||
              (supplier.taxId?.toLowerCase().contains(query) ?? false) ||
              (supplier.phone?.toLowerCase().contains(query) ?? false) ||
              (supplier.email?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    if (items.isEmpty) {
      return _InventoryEmptyState(
        icon: Icons.local_shipping_outlined,
        title: query.isEmpty
            ? 'მომწოდებლები ჯერ არ არის'
            : 'შესაბამისი მომწოდებელი ვერ მოიძებნა',
        subtitle: query.isEmpty
            ? 'დაამატეთ კომპანია ან პირი, ვისგანაც პროდუქტს ყიდულობთ.'
            : 'შეცვალეთ საძიებო სიტყვა.',
      );
    }
    return Column(
      key: const Key('supplier-list'),
      children: [
        for (final supplier in items)
          _SupplierCard(
            supplier: supplier,
            onEdit: () => _editSupplier(supplier),
            onToggle: () => _toggleSupplier(supplier),
          ),
      ],
    );
  }

  Future<void> _editStockItem([StockItem? item]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StockItemEditorDialog(item: item),
    );
    if (saved == true) {
      _adminToast(
        context,
        item == null ? 'პროდუქტი დაემატა' : 'პროდუქტი განახლდა',
      );
      await _load();
    }
  }

  Future<void> _editSupplier([Supplier? supplier]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierEditorDialog(supplier: supplier),
    );
    if (saved == true) {
      _adminToast(
        context,
        supplier == null ? 'მომწოდებელი დაემატა' : 'მომწოდებელი განახლდა',
      );
      await _load();
    }
  }

  Future<void> _toggleStockItem(StockItem item) async {
    try {
      await MobileApiService.saveStockItem(
        id: item.id,
        name: item.name,
        sku: item.sku,
        baseUnit: item.baseUnit,
        minimumStock: item.minimumStock,
        notes: item.notes,
        isActive: !item.isActive,
      );
      if (!mounted) return;
      _adminToast(
        context,
        item.isActive ? 'პროდუქტი გაითიშა' : 'პროდუქტი გააქტიურდა',
      );
      await _load();
    } catch (error) {
      if (mounted) _adminToast(context, '$error', error: true);
    }
  }

  Widget _receivingList() {
    final query = _search.text.trim().toLowerCase();
    final items = _receivings
        .where((receiving) {
          if (!_statusFilter.matches(receiving.status)) return false;
          return query.isEmpty ||
              receiving.supplierName.toLowerCase().contains(query) ||
              (receiving.waybillNumber?.toLowerCase().contains(query) ??
                  false) ||
              (receiving.invoiceNumber?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    return Column(
      key: const Key('receiving-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReceivingStatusFilterBar(
          selected: _statusFilter,
          onChanged: (value) => setState(() => _statusFilter = value),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _InventoryEmptyState(
            icon: Icons.receipt_long_outlined,
            title: query.isEmpty && _statusFilter == _ReceivingStatusFilter.all
                ? 'მიღებები ჯერ არ არის'
                : 'შესაბამისი დოკუმენტი ვერ მოიძებნა',
            subtitle:
                query.isEmpty && _statusFilter == _ReceivingStatusFilter.all
                ? 'დაამატეთ ზედნადები და აღრიცხეთ მიღებული პროდუქტი.'
                : 'შეცვალეთ ფილტრი ან საძიებო სიტყვა.',
          )
        else
          for (final receiving in items)
            _ReceivingCard(
              receiving: receiving,
              onOpen: () => _openReceiving(receiving),
            ),
      ],
    );
  }

  Future<void> _editReceiving([Receiving? receiving]) async {
    if (_suppliers.where((supplier) => supplier.isActive).isEmpty) {
      _adminToast(context, 'ჯერ დაამატეთ მომწოდებელი', error: true);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ReceivingEditorDialog(
        receiving: receiving,
        suppliers: _suppliers.where((supplier) => supplier.isActive).toList(),
        stockItems: _stockItems.where((item) => item.isActive).toList(),
      ),
    );
    if (saved == true) {
      if (mounted) {
        _adminToast(
          context,
          receiving == null ? 'მიღება შეიქმნა' : 'მიღება განახლდა',
        );
      }
      await _load();
    }
  }

  Future<void> _openReceiving(Receiving receiving) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ReceivingDetailDialog(
        receivingId: receiving.id,
        onEditDraft: (draft) async {
          Navigator.pop(context, false);
          await _editReceiving(draft);
        },
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openStockItem(StockItem item) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StockItemDetailDialog(stockItemId: item.id),
    );
  }

  Future<void> _toggleSupplier(Supplier supplier) async {
    try {
      await MobileApiService.saveSupplier(
        id: supplier.id,
        name: supplier.name,
        taxId: supplier.taxId,
        phone: supplier.phone,
        email: supplier.email,
        address: supplier.address,
        notes: supplier.notes,
        isActive: !supplier.isActive,
      );
      if (!mounted) return;
      _adminToast(
        context,
        supplier.isActive ? 'მომწოდებელი გაითიშა' : 'მომწოდებელი გააქტიურდა',
      );
      await _load();
    } catch (error) {
      if (mounted) _adminToast(context, '$error', error: true);
    }
  }
}

class _StockItemCard extends StatelessWidget {
  const _StockItemCard({
    required this.item,
    required this.onEdit,
    required this.onToggle,
    required this.onOpen,
  });

  final StockItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _AdminPanel(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          color: AdminTheme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (item.isLowStock) ...[
                      const _LowStockBadge(),
                      const SizedBox(width: 6),
                    ],
                    _InventoryStateBadge(active: item.isActive),
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _InventoryMeta(
                      icon: Icons.straighten_rounded,
                      label: 'ერთეული: ${item.baseUnit.wireValue}',
                    ),
                    _InventoryMeta(
                      icon: Icons.inventory_rounded,
                      label:
                          'ნაშთი: ${_quantityText(item.currentStock)} ${item.baseUnit.wireValue}',
                      emphasis: item.isLowStock,
                    ),
                    for (final unit in item.purchaseUnits)
                      _InventoryMeta(
                        icon: Icons.all_inbox_outlined,
                        label:
                            '1 ${unit.unit.wireValue} = ${unit.baseUnitMultiplier} ${item.baseUnit.wireValue}',
                      ),
                    if (item.minimumStock != null)
                      _InventoryMeta(
                        icon: Icons.notification_important_outlined,
                        label:
                            'მინიმუმი: ${_quantity(item.minimumStock!)} ${item.baseUnit.wireValue}',
                      ),
                    if (item.sku != null)
                      _InventoryMeta(
                        icon: Icons.qr_code_rounded,
                        label: 'SKU: ${item.sku}',
                      ),
                  ],
                ),
              ],
            );
            final actions = _InventoryActions(
              active: item.isActive,
              onEdit: onEdit,
              onToggle: onToggle,
              onOpen: onOpen,
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [content, const SizedBox(height: 10), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.onEdit,
    required this.onToggle,
  });

  final Supplier supplier;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (supplier.taxId != null) 'ს/კ ${supplier.taxId}',
      if (supplier.phone != null) supplier.phone!,
      if (supplier.email != null) supplier.email!,
      if (supplier.address != null) supplier.address!,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _AdminPanel(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        supplier.name,
                        style: TextStyle(
                          color: AdminTheme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _InventoryStateBadge(active: supplier.isActive),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    details.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
                  ),
                ],
              ],
            );
            final actions = _InventoryActions(
              active: supplier.isActive,
              onEdit: onEdit,
              onToggle: onToggle,
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [content, const SizedBox(height: 10), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InventoryActions extends StatelessWidget {
  const _InventoryActions({
    required this.active,
    required this.onEdit,
    required this.onToggle,
    this.onOpen,
  });

  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    // Bounded so the row beside it keeps its width: three actions would
    // otherwise take their full intrinsic line and overflow a wide card.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.end,
        children: [
          if (onOpen != null)
            TextButton.icon(
              key: const Key('stock-item-open'),
              onPressed: onOpen,
              icon: const Icon(Icons.history_rounded, size: 17),
              label: const Text('მოძრაობები'),
              style: TextButton.styleFrom(
                foregroundColor: AdminTheme.textMuted,
              ),
            ),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('რედაქტირება'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminTheme.text,
              side: BorderSide(color: AdminTheme.border),
            ),
          ),
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              foregroundColor: active ? AdminTheme.warn : AdminTheme.good,
            ),
            child: Text(active ? 'გათიშვა' : 'გააქტიურება'),
          ),
        ],
      ),
    );
  }
}

class _InventoryStateBadge extends StatelessWidget {
  const _InventoryStateBadge({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AdminTheme.good : AdminTheme.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'აქტიური' : 'გათიშული',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InventoryMeta extends StatelessWidget {
  const _InventoryMeta({
    required this.icon,
    required this.label,
    this.emphasis = false,
  });
  final IconData icon;
  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final color = emphasis ? AdminTheme.warn : AdminTheme.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: emphasis ? color : AdminTheme.textDim),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// Shown only when a threshold is configured and Cloud says it is reached.
class _LowStockBadge extends StatelessWidget {
  const _LowStockBadge();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('low-stock-badge'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AdminTheme.warn.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'მარაგი მცირდება',
      style: TextStyle(
        color: AdminTheme.warn,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _InventoryEmptyState extends StatelessWidget {
  const _InventoryEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => _AdminPanel(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AdminTheme.textDim),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AdminTheme.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _StockItemEditorDialog extends StatefulWidget {
  const _StockItemEditorDialog({this.item});
  final StockItem? item;

  @override
  State<_StockItemEditorDialog> createState() => _StockItemEditorDialogState();
}

class _StockItemEditorDialogState extends State<_StockItemEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _minimum;
  late final TextEditingController _notes;
  late InventoryUnit _unit;
  late bool _active;
  late List<_PurchaseUnitDraft> _purchaseUnits;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _sku = TextEditingController(text: item?.sku ?? '');
    _minimum = TextEditingController(
      text: item?.minimumStock == null ? '' : _quantity(item!.minimumStock!),
    );
    _notes = TextEditingController(text: item?.notes ?? '');
    _unit = item?.baseUnit ?? InventoryUnit.kg;
    _active = item?.isActive ?? true;
    _purchaseUnits = [
      for (final unit in item?.purchaseUnits ?? const <StockItemPurchaseUnit>[])
        _PurchaseUnitDraft(
          unit: unit.unit,
          multiplier: TextEditingController(text: unit.baseUnitMultiplier),
        ),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _minimum.dispose();
    _notes.dispose();
    for (final draft in _purchaseUnits) {
      draft.multiplier.dispose();
    }
    super.dispose();
  }

  /// Item-specific packaging: "1 box = 24 bottle" for this product only.
  Widget _purchaseUnitEditor() {
    return Column(
      key: const Key('purchase-unit-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'შესყიდვის შეფუთვა',
            style: TextStyle(
              color: AdminTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'მაგ. 1 ყუთი = 24 ${_unit.wireValue}. ეს კოეფიციენტი მხოლოდ ამ პროდუქტს ეხება.',
            style: TextStyle(color: AdminTheme.textDim, fontSize: 11),
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < _purchaseUnits.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: DropdownButtonFormField<InventoryUnit>(
                    initialValue: _purchaseUnits[index].unit,
                    dropdownColor: AdminTheme.surfaceElevated,
                    style: TextStyle(color: AdminTheme.text, fontSize: 13),
                    decoration: _adminInput('ერთეული'),
                    items: [
                      for (final unit in InventoryUnit.values)
                        if (unit != _unit)
                          DropdownMenuItem(
                            value: unit,
                            child: Text(unit.wireValue),
                          ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            if (value != null) {
                              _purchaseUnits[index].unit = value;
                            }
                          }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _purchaseUnits[index].multiplier,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(color: AdminTheme.text),
                    decoration: _adminInput('რაოდენობა ${_unit.wireValue}-ში'),
                  ),
                ),
                IconButton(
                  tooltip: 'წაშლა',
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _purchaseUnits.removeAt(index).multiplier.dispose();
                        }),
                  icon: Icon(Icons.close_rounded, color: AdminTheme.textDim),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('purchase-unit-add'),
            onPressed: _saving || _availablePurchaseUnit() == null
                ? null
                : () => setState(() {
                    _purchaseUnits.add(
                      _PurchaseUnitDraft(
                        unit: _availablePurchaseUnit()!,
                        multiplier: TextEditingController(),
                      ),
                    );
                  }),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('შეფუთვის დამატება'),
            style: TextButton.styleFrom(foregroundColor: AdminTheme.primary),
          ),
        ),
      ],
    );
  }

  InventoryUnit? _availablePurchaseUnit() {
    final used = _purchaseUnits.map((draft) => draft.unit).toSet()..add(_unit);
    for (final unit in InventoryUnit.values) {
      if (!used.contains(unit)) return unit;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('stock-item-editor'),
      backgroundColor: AdminTheme.surface,
      title: Text(
        widget.item == null
            ? 'ახალი საწყობის პროდუქტი'
            : 'პროდუქტის რედაქტირება',
        style: TextStyle(color: AdminTheme.text),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(_name, 'სახელი *', key: const Key('stock-name')),
              _dialogField(_sku, 'SKU'),
              DropdownButtonFormField<InventoryUnit>(
                initialValue: _unit,
                dropdownColor: AdminTheme.surfaceElevated,
                style: TextStyle(color: AdminTheme.text),
                decoration: _adminInput('საბაზო ერთეული'),
                items: [
                  for (final unit in InventoryUnit.values)
                    DropdownMenuItem(
                      value: unit,
                      child: Text(_unitLabel(unit)),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _unit = value ?? _unit),
              ),
              _dialogField(
                _minimum,
                'მინიმალური მარაგი',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              _dialogField(_notes, 'შენიშვნა', maxLines: 3),
              _purchaseUnitEditor(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'აქტიური',
                  style: TextStyle(color: AdminTheme.text),
                ),
                value: _active,
                activeTrackColor: AdminTheme.primary,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _active = value),
              ),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: AdminTheme.bad, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(
            'გაუქმება',
            style: TextStyle(color: AdminTheme.textMuted),
          ),
        ),
        FilledButton(
          key: const Key('stock-save'),
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AdminTheme.primary),
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('შენახვა', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final minimumText = _minimum.text.trim().replaceAll(',', '.');
    final minimum = minimumText.isEmpty ? null : double.tryParse(minimumText);
    if (name.isEmpty) {
      setState(() => _error = 'სახელი სავალდებულოა');
      return;
    }
    if (minimumText.isNotEmpty && (minimum == null || minimum < 0)) {
      setState(
        () => _error = 'მინიმალური მარაგი უნდა იყოს არაუარყოფითი რიცხვი',
      );
      return;
    }
    final purchaseUnits = <StockItemPurchaseUnit>[];
    for (final draft in _purchaseUnits) {
      final text = draft.multiplier.text.trim().replaceAll(',', '.');
      final value = double.tryParse(text);
      if (value == null || value <= 0) {
        setState(
          () => _error =
              '${draft.unit.wireValue}: შეფუთვის კოეფიციენტი უნდა იყოს დადებითი',
        );
        return;
      }
      purchaseUnits.add(
        StockItemPurchaseUnit(
          id: '',
          unit: draft.unit,
          baseUnitMultiplier: text,
        ),
      );
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await MobileApiService.saveStockItem(
        id: widget.item?.id,
        name: name,
        sku: _sku.text,
        baseUnit: _unit,
        minimumStock: minimum,
        notes: _notes.text,
        isActive: _active,
        purchaseUnits: purchaseUnits,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}

class _SupplierEditorDialog extends StatefulWidget {
  const _SupplierEditorDialog({this.supplier});
  final Supplier? supplier;

  @override
  State<_SupplierEditorDialog> createState() => _SupplierEditorDialogState();
}

class _SupplierEditorDialogState extends State<_SupplierEditorDialog> {
  late final Map<String, TextEditingController> _fields;
  late bool _active;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _fields = {
      'name': TextEditingController(text: supplier?.name ?? ''),
      'taxId': TextEditingController(text: supplier?.taxId ?? ''),
      'phone': TextEditingController(text: supplier?.phone ?? ''),
      'email': TextEditingController(text: supplier?.email ?? ''),
      'address': TextEditingController(text: supplier?.address ?? ''),
      'notes': TextEditingController(text: supplier?.notes ?? ''),
    };
    _active = supplier?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('supplier-editor'),
      backgroundColor: AdminTheme.surface,
      title: Text(
        widget.supplier == null
            ? 'ახალი მომწოდებელი'
            : 'მომწოდებლის რედაქტირება',
        style: TextStyle(color: AdminTheme.text),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(
                _fields['name']!,
                'სახელი *',
                key: const Key('supplier-name'),
              ),
              _dialogField(_fields['taxId']!, 'საგადასახადო კოდი'),
              _dialogField(
                _fields['phone']!,
                'ტელეფონი',
                keyboardType: TextInputType.phone,
              ),
              _dialogField(
                _fields['email']!,
                'ელფოსტა',
                keyboardType: TextInputType.emailAddress,
              ),
              _dialogField(_fields['address']!, 'მისამართი'),
              _dialogField(_fields['notes']!, 'შენიშვნა', maxLines: 3),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'აქტიური',
                  style: TextStyle(color: AdminTheme.text),
                ),
                value: _active,
                activeTrackColor: AdminTheme.primary,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _active = value),
              ),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: AdminTheme.bad, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(
            'გაუქმება',
            style: TextStyle(color: AdminTheme.textMuted),
          ),
        ),
        FilledButton(
          key: const Key('supplier-save'),
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AdminTheme.primary),
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('შენახვა', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _fields['name']!.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'სახელი სავალდებულოა');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await MobileApiService.saveSupplier(
        id: widget.supplier?.id,
        name: name,
        taxId: _fields['taxId']!.text,
        phone: _fields['phone']!.text,
        email: _fields['email']!.text,
        address: _fields['address']!.text,
        notes: _fields['notes']!.text,
        isActive: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}

Widget _dialogField(
  TextEditingController controller,
  String label, {
  Key? key,
  TextInputType? keyboardType,
  int maxLines = 1,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: AdminTheme.text),
      decoration: _adminInput(label),
    ),
  );
}

/// Trims Cloud's fixed-scale decimal text for display without re-rounding it.
String _quantityText(String exact) {
  if (!exact.contains('.')) return exact;
  final trimmed = exact.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

String _quantity(double value) {
  final fixed = value.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// One packaging row being edited, before it is validated into a ratio.
class _PurchaseUnitDraft {
  _PurchaseUnitDraft({required this.unit, required this.multiplier});

  InventoryUnit unit;
  final TextEditingController multiplier;
}

String _unitLabel(InventoryUnit unit) {
  switch (unit) {
    case InventoryUnit.kg:
      return 'კილოგრამი (kg)';
    case InventoryUnit.g:
      return 'გრამი (g)';
    case InventoryUnit.liter:
      return 'ლიტრი (L)';
    case InventoryUnit.ml:
      return 'მილილიტრი (ml)';
    case InventoryUnit.piece:
      return 'ცალი';
    case InventoryUnit.bottle:
      return 'ბოთლი';
    case InventoryUnit.pack:
      return 'შეფუთვა';
    case InventoryUnit.box:
      return 'ყუთი';
  }
}
