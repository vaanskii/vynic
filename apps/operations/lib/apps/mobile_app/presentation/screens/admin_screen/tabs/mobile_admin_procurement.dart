part of '../mobile_admin_screen.dart';

class SuppliedItemDialog extends StatefulWidget {
  const SuppliedItemDialog({
    super.key,
    required this.supplierId,
    required this.stockItems,
    this.supplierName,
    this.menuItems,
    this.save,
  });
  final String supplierId;
  final String? supplierName;
  final List<StockItem> stockItems;
  final List<RecipeMenuItem>? menuItems;
  final Future<void> Function(Map<String, dynamic>)? save;
  @override
  State<SuppliedItemDialog> createState() => _SuppliedItemState();
}

class _SuppliedItemState extends State<SuppliedItemDialog> {
  final _requestId = const Uuid().v4();
  String? _mode, _error;
  String _unit = 'kg', _package = 'pack', _query = '';
  StockItem? _stock;
  InventoryMenuSelection? _selected;
  final _name = TextEditingController();
  final _ratio = TextEditingController(text: '10');
  bool _busy = false, _packaging = false, _creating = false;
  @override
  void dispose() {
    _name.dispose();
    _ratio.dispose();
    super.dispose();
  }

  void _chooseMode(String mode) => setState(() {
    _mode = mode;
    _stock = null;
    _selected = null;
    _creating = false;
    _query = '';
    _name.clear();
    _error = null;
    _unit = mode == 'bulk' ? 'L' : 'kg';
    _packaging = mode != 'ingredient';
    _package = mode == 'bulk' ? 'keg' : 'pack';
    _ratio.text = mode == 'bulk' ? '30' : '10';
  });

  Future<void> _pickMenu() async {
    final result = await Navigator.of(context).push<InventoryMenuSelection>(
      MaterialPageRoute(
        builder: (_) => InventoryMenuPicker(items: widget.menuItems),
      ),
    );
    if (result != null && mounted)
      setState(() {
        _selected = result;
        _error = null;
      });
  }

  Future<void> _reuseCountedGoods() async {
    final item = await showDialog<StockItem>(
      context: context,
      builder: (_) => InventoryIngredientPicker(
        title: 'არსებული საქონელი',
        items: widget.stockItems
            .where(
              (i) => [
                InventoryUnit.piece,
                InventoryUnit.bottle,
              ].contains(i.baseUnit),
            )
            .toList(),
      ),
    );
    if (mounted && item != null) setState(() => _stock = item);
  }

  Future<void> _save() async {
    if (_mode == 'menu' && _selected == null) {
      setState(() => _error = 'აირჩიეთ მენიუს პროდუქტი');
      return;
    }
    if (_mode != 'menu' &&
        _stock == null &&
        (!_creating || _name.text.trim().isEmpty)) {
      setState(() => _error = 'აირჩიეთ საქონელი ან შეიყვანეთ ახალი დასახელება');
      return;
    }
    if (_packaging &&
        (double.tryParse(_ratio.text.replaceAll(',', '.')) ?? 0) <= 0) {
      setState(() => _error = 'შეფუთვის რაოდენობა უნდა იყოს ნულზე მეტი');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'requestId': _requestId,
        'mode': _mode,
        'name': _stock?.name ?? _name.text.trim(),
        'baseUnit': _stock?.baseUnit.wireValue ?? _unit,
        if (_mode == 'menu') 'menuItemId': _selected!.item.menuItemId,
        if (_mode == 'menu' && _selected!.variant != null)
          'variantId': _selected!.variant!.variantId,
        if (_stock != null) 'stockItemId': _stock!.id,
        if (_packaging)
          'purchaseUnits': [
            {
              'unit': _package,
              'baseUnitMultiplier': _ratio.text.trim().replaceAll(',', '.'),
            },
          ],
      };
      if (widget.save != null) {
        await widget.save!(payload);
      } else {
        await MobileApiService.procurementRequest(
          'suppliers/${widget.supplierId}/items',
          payload,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.stockItems
        .where(
          (i) =>
              i.isActive &&
              (_mode != 'bulk' || i.baseUnit == InventoryUnit.liter) &&
              i.name.toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();
    return Theme(
      data: inventoryTheme(context),
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: AdminTheme.surface,
        child: SizedBox(
          width: 640,
          height: (MediaQuery.sizeOf(context).height * .86).clamp(0.0, 720.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (_mode != null)
                      IconButton(
                        tooltip: 'უკან',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _mode = null),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'საქონლის დამატება',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.supplierName != null)
                            Text(
                              widget.supplierName!,
                              style: TextStyle(color: AdminTheme.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_mode == null) ...[
                      const Text('რას გვაწვდის მომწოდებელი?'),
                      const SizedBox(height: 16),
                      _modeTile(
                        'ingredient',
                        Icons.restaurant_outlined,
                        'ნედლეული',
                        'ხორცი, ფქვილი, ყველი — კერძის მოსამზადებლად',
                      ),
                      _modeTile(
                        'menu',
                        Icons.local_drink_outlined,
                        'მენიუდან',
                        'მაგ. ბორჯომის ბოთლი — იყიდება ცალობით',
                      ),
                      _modeTile(
                        'bulk',
                        Icons.sports_bar_outlined,
                        'ჩამოსასხმელი სასმელი',
                        'ლუდი ან ღვინო — მარაგი ლიტრებში',
                      ),
                    ] else ...[
                      if (_mode == 'menu') ...[
                        OutlinedButton.icon(
                          key: const Key('supplied-menu'),
                          onPressed: _busy ? null : _pickMenu,
                          icon: const Icon(Icons.search),
                          label: Text(
                            _selected == null
                                ? 'პროდუქტის არჩევა'
                                : '${_selected!.item.name}${_selected!.variant == null ? '' : ' · ${_selected!.variant!.label}'}',
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('როგორ ვითვლით? ცალი'),
                        TextButton(
                          onPressed: _busy ? null : _reuseCountedGoods,
                          child: Text(
                            _stock == null
                                ? 'არსებული მარაგის გამოყენება'
                                : 'მარაგი: ${_stock!.name}',
                          ),
                        ),
                        if (_stock != null)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _stock = null),
                            child: const Text('ავტომატურად დაკავშირება'),
                          ),

                        const SizedBox(height: 8),
                        const Text(
                          'ხორცი ან ფქვილი? დაბრუნდით და აირჩიეთ ნედლეული. კერძის რაოდენობები ივსება მის შემადგენლობაში.',
                        ),
                      ] else ...[
                        if (_stock == null && !_creating) ...[
                          TextField(
                            key: const Key('supplied-search'),
                            decoration: _adminInput('საქონლის ძებნა'),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            key: const Key('supplied-create'),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _creating = true;
                                    _name.text = _query.trim();
                                  }),
                            icon: const Icon(Icons.add),
                            label: Text(
                              _query.trim().isEmpty
                                  ? 'ახალი საქონლის შექმნა'
                                  : 'ახალი: ${_query.trim()}',
                            ),
                          ),
                          if (matches.isEmpty)
                            const Text(
                              'ვერ მოიძებნა. შეგიძლიათ ახალი საქონლის შექმნა.',
                            ),
                          for (final item in matches)
                            ListTile(
                              key: ValueKey('supplied-stock-${item.id}'),
                              title: Text(item.name),
                              subtitle: Text(_unitShort(item.baseUnit)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _busy
                                  ? null
                                  : () => setState(() {
                                      _stock = item;
                                      _unit = item.baseUnit.wireValue;
                                    }),
                            ),
                        ] else ...[
                          if (_stock != null)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(_stock!.name),
                              subtitle: Text(_unitShort(_stock!.baseUnit)),
                              trailing: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _stock = null),
                                child: const Text('შეცვლა'),
                              ),
                            )
                          else ...[
                            TextField(
                              key: const Key('supplied-name'),
                              controller: _name,
                              enabled: !_busy,
                              decoration: _adminInput(
                                _mode == 'bulk'
                                    ? 'სასმლის დასახელება'
                                    : 'ნედლეულის დასახელება',
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_mode == 'bulk')
                              const Text('მარაგს ვითვლით ლიტრებში')
                            else
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final unit in {
                                    'kg': 'კგ',
                                    'g': 'გ',
                                    'L': 'ლ',
                                    'ml': 'მლ',
                                    'piece': 'ცალი',
                                  }.entries)
                                    ChoiceChip(
                                      label: Text(unit.value),
                                      selected: _unit == unit.key,
                                      onSelected: _busy
                                          ? null
                                          : (_) => setState(
                                              () => _unit = unit.key,
                                            ),
                                    ),
                                ],
                              ),
                          ],
                          const SizedBox(height: 12),
                          const Text(
                            'კერძში რაოდენობას ცალკე მიუთითებთ — მაგალითად, ხინკალში 35 გ ხორცი.',
                          ),
                        ],
                      ],
                      if (_selected != null || _stock != null || _creating) ...[
                        const SizedBox(height: 16),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('როგორ მოდის? შეფუთვით'),
                          value: _packaging,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _packaging = v),
                        ),
                        if (_packaging) ...[
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final pack in {
                                'pack': 'შეკვრა',
                                'box': 'ყუთი',
                                'keg': 'კეგი',
                              }.entries)
                                ChoiceChip(
                                  label: Text(pack.value),
                                  selected: _package == pack.key,
                                  onSelected: _busy
                                      ? null
                                      : (_) =>
                                            setState(() => _package = pack.key),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('supplied-package-ratio'),
                            controller: _ratio,
                            enabled: !_busy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _adminInput(
                              '1 ${_unitShort(InventoryUnit.parse(_package))} = რამდენი ${_unitShort(_stock?.baseUnit ?? InventoryUnit.parse(_mode == 'menu' ? 'piece' : _unit))}?',
                            ),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_error!, style: TextStyle(color: AdminTheme.bad)),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('დახურვა'),
                    ),
                    const Spacer(),
                    if (_mode != null)
                      FilledButton(
                        key: const Key('supplied-save'),
                        onPressed:
                            _busy ||
                                (_selected == null &&
                                    _stock == null &&
                                    !_creating)
                            ? null
                            : _save,
                        child: Text(_busy ? 'ინახება…' : 'დამატება'),
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

  Widget _modeTile(String mode, IconData icon, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: ListTile(
            key: Key('supplied-mode-$mode'),
            contentPadding: const EdgeInsets.all(16),
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _chooseMode(mode),
          ),
        ),
      );
}

class InventoryMenuSelection {
  const InventoryMenuSelection(this.item, [this.variant]);
  final RecipeMenuItem item;
  final RecipeMenuVariant? variant;
}

/// A dedicated menu browser keeps search and categories above a bounded list.
class InventoryMenuPicker extends StatefulWidget {
  const InventoryMenuPicker({
    super.key,
    this.items,
    this.title = 'პროდუქტის არჩევა',
  });
  final List<RecipeMenuItem>? items;
  final String title;
  @override
  State<InventoryMenuPicker> createState() => _InventoryMenuPickerState();
}

class _InventoryMenuPickerState extends State<InventoryMenuPicker> {
  List<RecipeMenuItem>? _items;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = widget.items ?? await MobileApiService.getRecipeMenuItems();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: inventoryTheme(context),
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AdminTheme.surface,
        foregroundColor: AdminTheme.text,
      ),
      body: _error != null
          ? _ErrorWidget(onRetry: _load)
          : _items == null
          ? const _AdminLoading()
          : InventoryMenuBrowser(
              items: _items!,
              onSelected: (selection) => Navigator.pop(context, selection),
            ),
    ),
  );
}

/// Shared category → subcategory → product browsing for stock setup and recipes.
class InventoryMenuBrowser extends StatefulWidget {
  const InventoryMenuBrowser({
    super.key,
    required this.items,
    required this.onSelected,
    this.composition = false,
  });
  final List<RecipeMenuItem> items;
  final ValueChanged<InventoryMenuSelection> onSelected;
  final bool composition;
  @override
  State<InventoryMenuBrowser> createState() => _InventoryMenuBrowserState();
}

class _InventoryMenuBrowserState extends State<InventoryMenuBrowser> {
  final _search = TextEditingController();
  final _scroll = ScrollController(keepScrollOffset: false);
  String? _category, _subcategory;
  bool _all = false, _allSubcategories = false;
  _RecipeFilter _filter = _RecipeFilter.all;
  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final categories =
        widget.items.map((i) => i.browseCategory).toSet().toList()..sort();
    final subcategories =
        widget.items
            .where((i) => i.browseCategory == _category)
            .map((i) => i.subcategoryName)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final categoryStage = query.isEmpty && _category == null && !_all;
    final subcategoryStage =
        query.isEmpty &&
        _category != null &&
        _subcategory == null &&
        !_allSubcategories &&
        subcategories.isNotEmpty;
    final rows = widget.items.where((item) {
      if (widget.composition && !_filter.matches(item)) return false;
      if (query.isNotEmpty)
        return '${item.name} ${item.browseCategory} ${item.subcategoryName ?? ''} ${item.variants.map((v) => v.label).join(' ')}'
            .toLowerCase()
            .contains(query);
      return (_category == null || item.browseCategory == _category) &&
          (_subcategory == null || item.subcategoryName == _subcategory);
    }).toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const Key('inventory-menu-search'),
                controller: _search,
                decoration: _adminInput('მენიუში ძებნა').copyWith(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'გასუფთავება',
                          onPressed: () => _change(_search.clear),
                          icon: const Icon(Icons.close),
                        ),
                ),
                onChanged: (_) => _change(() {}),
              ),
            ),
            if (!categoryStage && query.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      key: const Key('menu-category-back'),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('კატეგორიები'),
                      onPressed: () => _change(() {
                        _category = null;
                        _subcategory = null;
                        _all = false;
                        _allSubcategories = false;
                      }),
                    ),
                    Expanded(
                      child: Text(
                        [
                          _category,
                          _subcategory,
                        ].whereType<String>().join(' / '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.composition && !categoryStage && !subcategoryStage)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _RecipeFilterBar(
                  selected: _filter,
                  onChanged: (f) => _change(() => _filter = f),
                ),
              ),
            Expanded(
              child: ListView(
                key: const Key('inventory-menu-results'),
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (categoryStage || subcategoryStage) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        categoryStage
                            ? 'აირჩიეთ კატეგორია'
                            : 'აირჩიეთ ქვეკატეგორია',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, box) {
                        final names = categoryStage
                            ? categories
                            : subcategories;
                        final columns = (box.maxWidth / 190).floor().clamp(
                          2,
                          4,
                        );
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final name in names)
                              SizedBox(
                                width:
                                    (box.maxWidth - 12 * (columns - 1)) /
                                    columns,
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    key: ValueKey('menu-category-$name'),
                                    onTap: () => _change(() {
                                      if (categoryStage) {
                                        _category = name;
                                        _subcategory = null;
                                        _allSubcategories = false;
                                      } else {
                                        _subcategory = name;
                                      }
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            categoryStage
                                                ? Icons.restaurant_menu
                                                : Icons.menu_book_outlined,
                                            color: AdminTheme.primary,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${widget.items.where((i) => categoryStage ? i.browseCategory == name : i.browseCategory == _category && i.subcategoryName == name).length} პროდუქტი',
                                            style: TextStyle(
                                              color: AdminTheme.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('menu-show-all'),
                      onPressed: () => _change(() {
                        if (categoryStage) {
                          _all = true;
                        } else {
                          _allSubcategories = true;
                        }
                      }),
                      child: const Text('ყველა პროდუქტის ნახვა'),
                    ),
                    if (widget.items.isEmpty) const Text('მენიუ ჯერ არ არის.'),
                  ] else ...[
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'პროდუქტი ვერ მოიძებნა. შეცვალეთ ძებნა ან ფილტრი.',
                        ),
                      ),
                    for (final item in rows)
                      if (widget.composition)
                        _RecipeCard(
                          item: item,
                          onOpen: (variant) => widget.onSelected(
                            InventoryMenuSelection(item, variant),
                          ),
                        )
                      else if (item.hasVariants) ...[
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (final variant in item.variants)
                          ListTile(
                            title: Text('${item.name} · ${variant.label}'),
                            subtitle: Text(
                              item.categoryName ?? item.browseCategory,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => widget.onSelected(
                              InventoryMenuSelection(item, variant),
                            ),
                          ),
                      ] else
                        ListTile(
                          title: Text(item.name),
                          subtitle: Text(
                            item.categoryName ?? item.browseCategory,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              widget.onSelected(InventoryMenuSelection(item)),
                        ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _paymentLabel(dynamic value) => switch (value) {
  'PAID' => 'გადახდილი',
  'PARTIALLY_PAID' => 'ნაწილობრივ გადახდილი',
  'UNVERIFIED' => 'შესამოწმებელი',
  _ => 'გადასახდელი',
};

class SupplierPaymentDialog extends StatefulWidget {
  const SupplierPaymentDialog({
    super.key,
    required this.receiving,
    this.reversal,
    this.save,
  });
  final Map receiving;
  final Map? reversal;
  final Future<void> Function(Map<String, dynamic>)? save;
  @override
  State<SupplierPaymentDialog> createState() => _PaymentState();
}

class _PaymentState extends State<SupplierPaymentDialog> {
  final _amount = TextEditingController(),
      _notes = TextEditingController(),
      _reference = TextEditingController();
  final _requestId = const Uuid().v4();
  late final _date = TextEditingController(text: _isoDate(DateTime.now()));
  late final _businessDate = TextEditingController(
    text:
        widget.receiving['currentBusinessDate'] as String? ??
        _isoDate(DateTime.now()),
  );
  String _method = 'cash';
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    _reference.dispose();
    _date.dispose();
    _businessDate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'requestId': _requestId,
        'amount': _amount.text.replaceAll(',', '.'),
        'paymentDate': _date.text,
        'businessDate': _businessDate.text,
        'method': _method,
        'notes': _notes.text,
        'reference': _reference.text,
      };
      if (widget.reversal != null) {
        final ok = await _confirmInventoryAction(
          context,
          title: 'გადახდის უკუქცევა',
          message:
              'დაადასტურეთ მხოლოდ რეალური დაბრუნება ან შეცდომით შეტანილი გადახდის შესწორება. თანხა: ${widget.reversal!['amount']} ₾.',
          confirmLabel: 'უკუქცევა',
        );
        if (ok != true) return;
      }
      if (widget.save != null) {
        await widget.save!(payload);
      } else {
        await MobileApiService.procurementRequest(
          'receivings/${widget.receiving['id']}/payments${widget.reversal == null ? '' : '/${widget.reversal!['id']}/reverse'}',
          payload,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: inventoryTheme(context),
    child: AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(
        widget.reversal == null ? 'გადახდის დაფიქსირება' : 'გადახდის უკუქცევა',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('დარჩენილი: ${widget.receiving['remaining']} ₾'),
              const SizedBox(height: 16),
              if (widget.reversal == null)
                TextField(
                  key: const Key('supplier-payment-amount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _adminInput('თანხა ₾'),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _date,
                decoration: _adminInput('გადახდის თარიღი YYYY-MM-DD'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _businessDate,
                decoration: _adminInput('სამუშაო დღე YYYY-MM-DD'),
              ),
              if (widget.reversal == null)
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('ნაღდი')),
                    DropdownMenuItem(value: 'bank', child: Text('ბანკი')),
                  ],
                  onChanged: (v) => setState(() => _method = v!),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: _adminInput(
                  widget.reversal == null ? 'შენიშვნა' : 'უკუქცევის მიზეზი',
                ),
              ),
              if (widget.reversal == null) const SizedBox(height: 12),
              if (widget.reversal == null)
                TextField(
                  controller: _reference,
                  decoration: _adminInput('გადახდის ნომერი / მითითება'),
                ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: AdminTheme.bad)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('გაუქმება'),
        ),
        FilledButton(
          key: const Key('supplier-payment-save'),
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'ინახება…' : 'დაფიქსირება'),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmInventoryAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) => showDialog<bool>(
  context: context,
  builder: (context) => Theme(
    data: inventoryTheme(context),
    child: AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('გაუქმება'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  ),
);

/// A search over existing goods, shared across dishes. Selecting never creates stock.
class InventoryIngredientPicker extends StatefulWidget {
  final String title;
  const InventoryIngredientPicker({
    super.key,
    required this.items,
    this.title = 'ინგრედიენტის დამატება',
    this.onCreate,
  });
  final List<StockItem> items;
  final Future<StockItem?> Function(String name)? onCreate;
  @override
  State<InventoryIngredientPicker> createState() => _IngredientPickerState();
}

class _IngredientPickerState extends State<InventoryIngredientPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) => Theme(
    data: inventoryTheme(context),
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 360,
        child: Column(
          children: [
            TextField(
              key: const Key('ingredient-search'),
              decoration: _adminInput('პროდუქტის ძებნა'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  for (final item in widget.items.where(
                    (i) =>
                        i.isActive &&
                        i.name.toLowerCase().contains(_query.toLowerCase()),
                  ))
                    ListTile(
                      title: Text(item.name),
                      subtitle: Text(_unitShort(item.baseUnit)),
                      onTap: () => Navigator.pop(context, item),
                    ),
                  if (!widget.items.any(
                    (i) =>
                        i.isActive &&
                        i.name.toLowerCase().contains(_query.toLowerCase()),
                  ))
                    const Text(
                      'პროდუქტი ვერ მოიძებნა. შეცვალეთ ძებნა ან შექმენით ახალი.',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.onCreate != null)
          FilledButton.icon(
            key: const Key('receiving-create-product'),
            icon: const Icon(Icons.add),
            label: const Text('ახალი პროდუქტი'),
            onPressed: () async {
              final item = await widget.onCreate!(_query.trim());
              if (item != null && context.mounted) Navigator.pop(context, item);
            },
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('დახურვა'),
        ),
      ],
    ),
  );
}

class IngredientQuickDialog extends StatefulWidget {
  const IngredientQuickDialog({
    super.key,
    this.initialName = '',
    this.receivingProduct = false,
    this.classification = StockItemClassification.food,
  });
  final String initialName;
  final bool receivingProduct;
  final StockItemClassification classification;
  @override
  State<IngredientQuickDialog> createState() => _IngredientQuickState();
}

class _IngredientQuickState extends State<IngredientQuickDialog> {
  final _requestId = const Uuid().v4();
  late final _name = TextEditingController(text: widget.initialName);
  InventoryUnit _unit = InventoryUnit.kg;
  late StockItemClassification _classification = widget.classification;
  bool _packaged = false;
  InventoryUnit _package = InventoryUnit.pack;
  final _ratio = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _ratio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'შეიყვანეთ დასახელება');
      return;
    }
    if (_packaged) {
      try {
        if (InventoryDecimal.parse(_ratio.text).raw <= BigInt.zero)
          throw const FormatException();
      } on FormatException {
        setState(
          () => _error = 'შეიყვანეთ შეფუთვაში რაოდენობა — ნულზე მეტი რიცხვი',
        );
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final item = await MobileApiService.saveStockItem(
        requestId: _requestId,
        name: _name.text.trim(),
        baseUnit: _unit,
        isActive: true,
        classification: _classification,
        purchaseUnits: _packaged
            ? [
                StockItemPurchaseUnit(
                  id: '',
                  unit: _package,
                  baseUnitMultiplier: _ratio.text.trim().replaceAll(',', '.'),
                ),
              ]
            : null,
      );
      if (mounted) Navigator.pop(context, item);
    } catch (e) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = '$e';
        });
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: inventoryTheme(context),
    child: AlertDialog(
      title: Text(
        widget.receivingProduct ? 'ახალი პროდუქტი' : 'ახალი ნედლეული',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('new-product-name'),
                controller: _name,
                decoration: _adminInput('დასახელება'),
                enabled: !_busy,
              ),
              const SizedBox(height: 16),
              if (widget.receivingProduct) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in StockItemClassification.values)
                      ChoiceChip(
                        label: Text(
                          value == StockItemClassification.food
                              ? 'საკვები / ინგრედიენტი'
                              : 'სასმელი',
                        ),
                        selected: _classification == value,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _classification = value),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('როგორ ვითვლით მარაგს?'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final unit in [
                    InventoryUnit.kg,
                    InventoryUnit.g,
                    InventoryUnit.liter,
                    InventoryUnit.ml,
                    InventoryUnit.piece,
                  ])
                    ChoiceChip(
                      key: ValueKey('new-product-unit-${unit.wireValue}'),
                      label: Text(_unitShort(unit)),
                      selected: _unit == unit,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _unit = unit),
                    ),
                ],
              ),
              if (widget.receivingProduct) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('შეფუთვით ვიღებთ'),
                  value: _packaged,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _packaged = v),
                ),
                if (_packaged) ...[
                  DropdownButtonFormField<InventoryUnit>(
                    initialValue: _package,
                    decoration: _adminInput('შეფუთვა'),
                    items: [
                      for (final u in [
                        InventoryUnit.pack,
                        InventoryUnit.box,
                        InventoryUnit.keg,
                      ])
                        DropdownMenuItem(value: u, child: Text(_unitShort(u))),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _package = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('new-product-package-ratio'),
                    controller: _ratio,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _adminInput(
                      '1 ${_unitShort(_package)} = რამდენი ${_unitShort(_unit)}?',
                    ),
                  ),
                ],
              ],
              if (_error != null)
                Text(_error!, style: TextStyle(color: AdminTheme.bad)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('დახურვა'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'ინახება…' : 'დამატება'),
        ),
      ],
    ),
  );
}
