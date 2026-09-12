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
  String _query = '';
  String? _category, _subcategory, _error;
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
  Widget build(BuildContext context) {
    final categories =
        (_items ?? <RecipeMenuItem>[])
            .map((i) => i.browseCategory)
            .toSet()
            .toList()
          ..sort();
    final subcategories =
        (_items ?? <RecipeMenuItem>[])
            .where((i) => i.browseCategory == _category)
            .map((i) => i.subcategoryName)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final rows = (_items ?? <RecipeMenuItem>[])
        .where(
          (i) =>
              (_category == null || i.browseCategory == _category) &&
              (_subcategory == null || i.subcategoryName == _subcategory) &&
              '${i.name} ${i.browseCategory} ${i.subcategoryName ?? ''} ${i.variants.map((v) => v.label).join(' ')}'
                  .toLowerCase()
                  .contains(_query.trim().toLowerCase()),
        )
        .toList();
    return Theme(
      data: inventoryTheme(context),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AdminTheme.surface,
          foregroundColor: AdminTheme.text,
          title: Text(widget.title),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      key: const Key('inventory-menu-search'),
                      decoration: _adminInput('ძებნა სახელით ან კატეგორიით'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  if (categories.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final category in <String?>[null, ...categories])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(category ?? 'ყველა'),
                                selected: _category == category,
                                onSelected: (_) => setState(() {
                                  _category = category;
                                  _subcategory = null;
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (subcategories.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final sub in <String?>[null, ...subcategories])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(sub ?? 'ყველა ქვეკატეგორია'),
                                selected: _subcategory == sub,
                                onSelected: (_) =>
                                    setState(() => _subcategory = sub),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_error != null) ...[
                    Text(_error!),
                    TextButton(
                      onPressed: _load,
                      child: const Text('ხელახლა ცდა'),
                    ),
                  ] else if (_items == null)
                    const LinearProgressIndicator(),
                  if (_items != null && rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('ვერ მოიძებნა. შეცვალეთ ძებნა ან კატეგორია.'),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final item = rows[index];
                        if (item.hasVariants)
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              for (final variant in item.variants)
                                ListTile(
                                  title: Text(
                                    '${item.name} · ${variant.label}',
                                  ),
                                  subtitle: Text(item.categoryName ?? 'სხვა'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.pop(
                                    context,
                                    InventoryMenuSelection(item, variant),
                                  ),
                                ),
                            ],
                          );
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text(item.categoryName ?? 'სხვა'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(
                            context,
                            InventoryMenuSelection(item),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SupplierPayablesDialog extends StatefulWidget {
  const SupplierPayablesDialog({super.key, this.supplierId, this.load});
  final String? supplierId;
  final Future<Map<String, dynamic>> Function()? load;
  @override
  State<SupplierPayablesDialog> createState() => _PayablesState();
}

class _PayablesState extends State<SupplierPayablesDialog> {
  Map<String, dynamic>? _data;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data =
          await (widget.load?.call() ??
              MobileApiService.procurementRequest(
                'payables${widget.supplierId == null ? '' : '?supplierId=${Uri.encodeQueryComponent(widget.supplierId!)}'}',
              ));
      if (mounted)
        setState(() {
          _data = data;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: inventoryTheme(context),
    child: AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: const Text('გადახდები და დავალიანება'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_data == null && _error == null)
                const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('ხელახლა ცდა')),
              ],
              Text('დავალიანება: ${_data?['outstanding'] ?? '—'} ₾'),
              Text('შესამოწმებელი: ${_data?['unverified'] ?? '—'} ₾'),
              for (final row
                  in (_data?['receivings'] as List? ?? []).cast<Map>()) ...[
                const Divider(height: 24),
                Text(
                  '${row['supplierName']} · ${row['businessDate']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'მიღება: ${row['documentTotal']} ₾ · გადახდილი: ${row['paid']} ₾',
                ),
                Text(
                  'დარჩენილი: ${row['remaining']} ₾ · ${_paymentLabel(row['paymentStatus'])}',
                ),
                if (row['dueDate'] != null) Text('ვადა: ${row['dueDate']}'),
                FilledButton.tonal(
                  onPressed: () => _payment(row),
                  child: const Text('გადახდის დაფიქსირება'),
                ),
                for (final p in (row['payments'] as List? ?? []).cast<Map>())
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${p['paymentDate']} · ${p['amount']} ₾'),
                    subtitle: Text(
                      '${p['actorName']} · ${p['method'] == 'cash' ? 'ნაღდი' : 'ბანკი'}',
                    ),
                    trailing: p['reversalOfId'] == null
                        ? IconButton(
                            tooltip: 'გადახდის უკუქცევა',
                            icon: const Icon(Icons.undo),
                            onPressed: () => _reverse(row, p),
                          )
                        : null,
                  ),
                if (row['paymentStatus'] == 'UNVERIFIED')
                  TextButton(
                    onPressed: () => _verify(row),
                    child: const Text('ძველი გადახდების შემოწმება'),
                  ),
              ],
              if (_data != null && (_data!['receivings'] as List).isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('გატარებული მიღება ჯერ არ არის.'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('დახურვა'),
        ),
      ],
    ),
  );
  Future<void> _payment(Map row) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => SupplierPaymentDialog(
        receiving: {...row, 'currentBusinessDate': _data?['businessDate']},
      ),
    );
    await _load();
  }

  Future<void> _reverse(Map row, Map payment) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => SupplierPaymentDialog(
        receiving: {...row, 'currentBusinessDate': _data?['businessDate']},
        reversal: payment,
      ),
    );
    await _load();
  }

  Future<void> _verify(Map row) async {
    final ok = await _confirmInventoryAction(
      context,
      title: 'ძველი გადახდები შემოწმებულია?',
      message:
          'ჯერ შეიტანეთ ყველა რეალური გადახდა თავისი თარიღით. დადასტურება ნიშნავს, რომ აღურიცხავი გადახდა აღარ დარჩა.',
      confirmLabel: 'შემოწმებულია',
    );
    if (ok != true) return;
    try {
      await MobileApiService.procurementRequest(
        'receivings/${row['id']}/verify-settlement',
        {
          'confirmNoUnrecordedPayments': true,
          'notes': 'Manager confirmed all historical supplier payments entered',
        },
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
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
  builder: (context) => AlertDialog(
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
);

/// A search over existing goods, shared across dishes. Selecting never creates stock.
class InventoryIngredientPicker extends StatefulWidget {
  final String title;
  const InventoryIngredientPicker({
    super.key,
    required this.items,
    this.title = 'ინგრედიენტის დამატება',
  });
  final List<StockItem> items;
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
              decoration: _adminInput('ინგრედიენტის ძებნა'),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  for (final item in widget.items.where(
                    (i) => i.isActive && i.name.toLowerCase().contains(_query),
                  ))
                    ListTile(
                      title: Text(item.name),
                      subtitle: Text(_unitShort(item.baseUnit)),
                      onTap: () => Navigator.pop(context, item),
                    ),
                  if (!widget.items.any(
                    (i) => i.isActive && i.name.toLowerCase().contains(_query),
                  ))
                    const Text(
                      'ვერ მოიძებნა. დახურეთ ძებნა და აირჩიეთ ახალი ნედლეულის შექმნა.',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
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
    this.classification = StockItemClassification.food,
  });
  final String initialName;
  final StockItemClassification classification;
  @override
  State<IngredientQuickDialog> createState() => _IngredientQuickState();
}

class _IngredientQuickState extends State<IngredientQuickDialog> {
  final _requestId = const Uuid().v4();
  late final _name = TextEditingController(text: widget.initialName);
  InventoryUnit _unit = InventoryUnit.kg;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'შეიყვანეთ დასახელება');
      return;
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
        classification: widget.classification,
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
      title: const Text('ახალი ნედლეული'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: _adminInput('დასახელება'),
                enabled: !_busy,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<InventoryUnit>(
                initialValue: _unit,
                decoration: _adminInput('როგორ ვითვლით?'),
                items: [
                  for (final unit in [
                    InventoryUnit.kg,
                    InventoryUnit.liter,
                    InventoryUnit.piece,
                  ])
                    DropdownMenuItem(
                      value: unit,
                      child: Text(_unitShort(unit)),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _unit = v!),
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
