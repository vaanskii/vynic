part of '../mobile_admin_screen.dart';

class SuppliedItemDialog extends StatefulWidget {
  const SuppliedItemDialog({
    super.key,
    required this.supplierId,
    required this.stockItems,
    this.menuItems,
    this.save,
  });
  final String supplierId;
  final List<StockItem> stockItems;
  final List<RecipeMenuItem>? menuItems;
  final Future<void> Function(Map<String, dynamic>)? save;
  @override
  State<SuppliedItemDialog> createState() => _SuppliedItemState();
}

class _SuppliedItemState extends State<SuppliedItemDialog> {
  final _requestId = const Uuid().v4();
  String _mode = 'menu', _unit = 'kg', _package = 'pack';
  String? _menuId, _stockId, _variantId, _error;
  final _name = TextEditingController(),
      _ratio = TextEditingController(text: '10');
  List<RecipeMenuItem>? _menu;
  bool _busy = false, _packaging = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows =
          widget.menuItems ?? await MobileApiService.getRecipeMenuItems();
      if (mounted) setState(() => _menu = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _ratio.dispose();
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
        'mode': _mode,
        'name': _name.text.trim(),
        'baseUnit': _unit,
        if (_mode == 'menu') 'menuItemId': _menuId,
        if (_variantId != null) 'variantId': _variantId,
        if (_stockId != null) 'stockItemId': _stockId,
        if (_packaging && _mode != 'existing')
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
    final selected = _menu?.where((m) => m.menuItemId == _menuId).firstOrNull;
    return Theme(
      data: inventoryTheme(context),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('საქონლის დამატება'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('supplied-mode'),
                  initialValue: _mode,
                  isExpanded: true,
                  decoration: _adminInput('საქონლის ტიპი'),
                  items: const [
                    DropdownMenuItem(
                      value: 'menu',
                      child: Text('მენიუდან არჩევა'),
                    ),
                    DropdownMenuItem(
                      value: 'ingredient',
                      child: Text('ნედლეულის დამატება'),
                    ),
                    DropdownMenuItem(
                      value: 'bulk',
                      child: Text('ჩამოსასხმელი სასმელი'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _mode = v!;
                          _packaging = v == 'menu' || v == 'bulk';
                          _package = v == 'bulk' ? 'keg' : 'pack';
                          _ratio.text = v == 'bulk' ? '30' : '10';
                          _stockId = null;
                        }),
                ),
                const SizedBox(height: 16),
                if (_mode == 'menu') ...[
                  if (_menu == null) const LinearProgressIndicator(),
                  DropdownButtonFormField<String>(
                    key: const Key('supplied-menu'),
                    initialValue: _menuId,
                    isExpanded: true,
                    decoration: _adminInput('აირჩიეთ მენიუდან'),
                    items: [
                      for (final m in _menu ?? <RecipeMenuItem>[])
                        DropdownMenuItem(
                          value: m.menuItemId,
                          child: Text(m.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _menuId = v;
                            _variantId = null;
                          }),
                  ),
                  if (selected?.hasVariants ?? false)
                    DropdownButtonFormField<String>(
                      key: ValueKey(_menuId),
                      initialValue: _variantId,
                      isExpanded: true,
                      decoration: _adminInput('ზომა'),
                      items: [
                        for (final v in selected!.variants)
                          DropdownMenuItem(
                            value: v.variantId,
                            child: Text('${v.size}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _variantId = v),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('1 გაყიდვა = 1 ცალი მარაგიდან'),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('უკვე გვაქვს ეს საქონელი?'),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _stockId ?? '',
                        isExpanded: true,
                        decoration: _adminInput('არსებული საქონელი'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('ავტომატურად'),
                          ),
                          for (final item in widget.stockItems.where(
                            (i) =>
                                i.isActive &&
                                [
                                  InventoryUnit.piece,
                                  InventoryUnit.bottle,
                                ].contains(i.baseUnit),
                          ))
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _stockId = v == '' ? null : v),
                      ),
                    ],
                  ),
                ] else if (_mode == 'existing')
                  DropdownButtonFormField<String>(
                    initialValue: _stockId,
                    isExpanded: true,
                    decoration: _adminInput('საქონელი'),
                    items: [
                      for (final item in widget.stockItems.where(
                        (i) => i.isActive,
                      ))
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _stockId = v),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('reuse-$_mode'),
                    initialValue: _stockId ?? '',
                    isExpanded: true,
                    decoration: _adminInput('რას გვაწვდის?'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('ახალი ნედლეულის დამატება'),
                      ),
                      for (final item in widget.stockItems.where(
                        (i) =>
                            i.isActive &&
                            (_mode != 'bulk' ||
                                i.baseUnit == InventoryUnit.liter),
                      ))
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _stockId = v == '' ? null : v;
                            if (_stockId != null) {
                              final item = widget.stockItems.firstWhere(
                                (i) => i.id == v,
                              );
                              _unit = item.baseUnit.wireValue;
                            }
                          }),
                  ),
                  const SizedBox(height: 16),
                  if (_stockId == null)
                    TextField(
                      key: const Key('supplied-name'),
                      controller: _name,
                      decoration: _adminInput('დასახელება'),
                    ),
                  const SizedBox(height: 12),
                  if (_stockId != null)
                    const Text(
                      'სხვა მომწოდებლის მიღებაც ამავე მარაგს დაემატება.',
                    )
                  else if (_mode == 'bulk')
                    const Text('როგორ ვითვლით? ლიტრი')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _unit,
                      decoration: _adminInput('როგორ ვითვლით?'),
                      items: const [
                        DropdownMenuItem(value: 'kg', child: Text('კგ')),
                        DropdownMenuItem(value: 'L', child: Text('ლიტრი')),
                        DropdownMenuItem(value: 'piece', child: Text('ცალი')),
                      ],
                      onChanged: (v) => setState(() => _unit = v!),
                    ),
                ],
                if (_mode != 'existing') ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('მოაქვს შეფუთვით'),
                    value: _packaging,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _packaging = v),
                  ),
                  if (_packaging) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey(_package),
                      initialValue: _package,
                      decoration: _adminInput('როგორ მოაქვს მომწოდებელს?'),
                      items: const [
                        DropdownMenuItem(value: 'pack', child: Text('შეკვრა')),
                        DropdownMenuItem(value: 'box', child: Text('ყუთი')),
                        DropdownMenuItem(value: 'keg', child: Text('კეგი')),
                      ],
                      onChanged: (v) => setState(() => _package = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('supplied-package-ratio'),
                      controller: _ratio,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _adminInput(
                        '1 შეფუთვაში რამდენი ${_mode == 'menu'
                            ? 'ცალი'
                            : _mode == 'bulk'
                            ? 'ლიტრი'
                            : _unit}?',
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
            child: const Text('გაუქმება'),
          ),
          FilledButton(
            key: const Key('supplied-save'),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'ინახება…' : 'დამატება'),
          ),
        ],
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
  const InventoryIngredientPicker({super.key, required this.items});
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
      title: const Text('ინგრედიენტის დამატება'),
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
