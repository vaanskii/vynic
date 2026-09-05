part of '../mobile_admin_screen.dart';

enum _InventorySection { stockItems, suppliers }

class InventoryAdminTab extends StatefulWidget {
  const InventoryAdminTab({super.key, this.loadStockItems, this.loadSuppliers});

  final Future<List<StockItem>> Function()? loadStockItems;
  final Future<List<Supplier>> Function()? loadSuppliers;

  @override
  State<InventoryAdminTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryAdminTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  _InventorySection _section = _InventorySection.stockItems;
  final _search = TextEditingController();
  List<StockItem> _stockItems = const [];
  List<Supplier> _suppliers = const [];
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
      ]);
      if (!mounted) return;
      setState(() {
        _stockItems = results[0] as List<StockItem>;
        _suppliers = results[1] as List<Supplier>;
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
                      else
                        _supplierList(),
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
      segments: const [
        ButtonSegment(
          value: _InventorySection.stockItems,
          icon: Icon(Icons.inventory_2_outlined),
          label: Text('საწყობის პროდუქტები'),
        ),
        ButtonSegment(
          value: _InventorySection.suppliers,
          icon: Icon(Icons.local_shipping_outlined),
          label: Text('მომწოდებლები'),
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
      decoration: _adminInput('ძებნა სახელით ან კოდით').copyWith(
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
      onPressed: _section == _InventorySection.stockItems
          ? () => _editStockItem()
          : () => _editSupplier(),
      icon: const Icon(Icons.add_rounded),
      label: Text(
        _section == _InventorySection.stockItems
            ? 'პროდუქტის დამატება'
            : 'მომწოდებლის დამატება',
      ),
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
  });

  final StockItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

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
                      icon: Icons.layers_clear_outlined,
                      label: 'მოძრაობები ჯერ არ არის',
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
  });

  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
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
  const _InventoryMeta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: AdminTheme.textDim),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: AdminTheme.textMuted, fontSize: 12)),
    ],
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
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _minimum.dispose();
    _notes.dispose();
    super.dispose();
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

String _quantity(double value) {
  final fixed = value.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
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
