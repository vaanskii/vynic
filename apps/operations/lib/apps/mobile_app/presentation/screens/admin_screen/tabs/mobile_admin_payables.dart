part of '../mobile_admin_screen.dart';

class SupplierPayablesScreen extends StatelessWidget {
  const SupplierPayablesScreen({super.key, this.supplierId, this.load});
  final String? supplierId;
  final Future<Map<String, dynamic>> Function()? load;
  @override
  Widget build(BuildContext context) => Theme(
    data: inventoryTheme(context),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('გადახდები და დავალიანება'),
        backgroundColor: AdminTheme.surface,
        foregroundColor: AdminTheme.text,
      ),
      body: SupplierPayablesView(supplierId: supplierId, load: load),
    ),
  );
}

class SupplierPayablesView extends StatefulWidget {
  const SupplierPayablesView({super.key, this.supplierId, this.load});
  final String? supplierId;
  final Future<Map<String, dynamic>> Function()? load;
  @override
  State<SupplierPayablesView> createState() => _PayablesViewState();
}

class _PayablesViewState extends State<SupplierPayablesView> {
  Map<String, dynamic>? _data;
  String? _error;
  late String? _supplier = widget.supplierId;
  bool _payments = false;
  String _status = 'OUTSTANDING';
  DateTimeRange? _range;
  final _scroll = ScrollController(keepScrollOffset: false);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _filter(VoidCallback change) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(change);
  }

  Future<void> _load() async {
    try {
      final data =
          await (widget.load?.call() ??
              MobileApiService.procurementRequest('payables'));
      if (mounted)
        setState(() {
          _data = data;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  bool _inRange(dynamic day) {
    if (_range == null) return true;
    final value = '$day';
    return value.compareTo(_isoDate(_range!.start)) >= 0 &&
        value.compareTo(_isoDate(_range!.end)) <= 0;
  }

  String _supplierKey(Map row) => '${row['supplierId'] ?? 'self'}';
  String _sum(Iterable<Map> rows, String field) {
    var raw = BigInt.zero;
    for (final row in rows) {
      final amount = '${row[field] ?? '0'}';
      final negative = amount.startsWith('-');
      final value = InventoryDecimal.parse(
        negative ? amount.substring(1) : amount,
      ).raw;
      raw += negative ? -value : value;
    }
    final cents = raw.abs() ~/ (InventoryDecimal.scale ~/ BigInt.from(100));
    return '${raw.isNegative ? '-' : ''}${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
  }

  Future<void> _dates() async {
    final now =
        DateTime.tryParse('${_data?['businessDate']}') ?? DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      builder: (context, child) =>
          Theme(data: inventoryTheme(context), child: child!),
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 366)),
      initialDateRange: _range,
    );
    if (picked != null && mounted) _filter(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null)
      return _error == null
          ? const _AdminLoading()
          : _ErrorWidget(onRetry: _load);
    final all = (_data!['receivings'] as List? ?? []).cast<Map>();
    final names = <String, String>{
      for (final r in all)
        _supplierKey(r): r['supplierId'] == null
            ? 'საკუთარი შესყიდვები'
            : '${r['supplierName']}',
    };
    if (_supplier != null && !names.containsKey(_supplier)) {
      names[_supplier!] = 'არჩეული მომწოდებელი · მიღებები არ აქვს';
    }
    final scoped = all
        .where((r) => _supplier == null || _supplierKey(r) == _supplier)
        .toList();
    final current = scoped.where(
      (r) => r['status'] != 'CANCELLED' && r['paymentStatus'] != 'UNVERIFIED',
    );
    final debts = scoped
        .where(
          (r) =>
              r['status'] != 'CANCELLED' &&
              _inRange(r['businessDate']) &&
              switch (_status) {
                'ALL' => true,
                'OUTSTANDING' =>
                  r['paymentStatus'] != 'UNVERIFIED' &&
                      (InventoryDecimal.parse('${r['remaining']}').raw >
                          BigInt.zero),
                'OVERDUE' =>
                  r['paymentStatus'] != 'UNVERIFIED' &&
                      (InventoryDecimal.parse('${r['remaining']}').raw >
                          BigInt.zero) &&
                      r['dueDate'] != null &&
                      '${r['dueDate']}'.compareTo('${_data!['businessDate']}') <
                          0,
                _ => r['paymentStatus'] == _status,
              },
        )
        .toList();
    final payments =
        <({Map receipt, Map payment})>[
          for (final r in scoped)
            for (final p in (r['payments'] as List? ?? []).cast<Map>())
              if (_inRange(p['paymentDate'])) (receipt: r, payment: p),
        ]..sort(
          (a, b) => '${b.payment['paymentDate']}'.compareTo(
            '${a.payment['paymentDate']}',
          ),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('payables-debts'),
                    label: const Text('დავალიანება'),
                    selected: !_payments,
                    onSelected: (_) => _filter(() => _payments = false),
                  ),
                  ChoiceChip(
                    key: const Key('payables-payments'),
                    label: const Text('გადახდების ისტორია'),
                    selected: _payments,
                    onSelected: (_) => _filter(() => _payments = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  key: const Key('payables-list'),
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (_error != null) ...[
                      Text(
                        'განახლება ვერ მოხერხდა: $_error',
                        style: TextStyle(color: AdminTheme.bad),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: const Text('ხელახლა ცდა'),
                      ),
                    ],
                    DropdownButtonFormField<String>(
                      key: ValueKey('payables-supplier-${_supplier ?? 'all'}'),
                      initialValue: names.containsKey(_supplier)
                          ? _supplier
                          : '',
                      isExpanded: true,
                      decoration: _adminInput('მომწოდებელი'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('ყველა მომწოდებელი'),
                        ),
                        for (final e in names.entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          _filter(() => _supplier = v == '' ? null : v),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('payables-dates'),
                          onPressed: _dates,
                          icon: const Icon(Icons.date_range),
                          label: Text(
                            _range == null
                                ? (_payments
                                      ? 'გადახდის თარიღი: ყველა'
                                      : 'მიღების თარიღი: ყველა')
                                : '${_payments ? 'გადახდა' : 'მიღება'}: ${_isoDate(_range!.start)} – ${_isoDate(_range!.end)}',
                          ),
                        ),
                        if (_range != null)
                          TextButton(
                            onPressed: () => _filter(() => _range = null),
                            child: const Text('ყველა თარიღი'),
                          ),
                        TextButton(
                          key: const Key('payables-last-30'),
                          onPressed: () {
                            final end =
                                DateTime.tryParse(
                                  '${_data?['businessDate']}',
                                ) ??
                                DateTime.now();
                            _filter(
                              () => _range = DateTimeRange(
                                start: end.subtract(const Duration(days: 29)),
                                end: end,
                              ),
                            );
                          },
                          child: const Text('ბოლო 30 დღე'),
                        ),
                      ],
                    ),
                    if (!_payments) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const Key('payables-status'),
                        initialValue: _status,
                        isExpanded: true,
                        decoration: _adminInput('სტატუსი'),
                        items: [
                          for (final e in const {
                            'OUTSTANDING': 'გადასახდელი',
                            'OVERDUE': 'ვადაგადაცილებული',
                            'PARTIALLY_PAID': 'ნაწილობრივ გადახდილი',
                            'PAID': 'გადახდილი',
                            'UNVERIFIED': 'შესამოწმებელი',
                            'ALL': 'ყველა',
                          }.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                        ],
                        onChanged: (v) => _filter(() => _status = v!),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'მიმდინარე დავალიანება: ${_sum(current, 'remaining')} ₾',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'ყველა თარიღი · არჩეული მომწოდებელი',
                        style: TextStyle(
                          color: AdminTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (scoped.any(
                        (r) =>
                            r['status'] != 'CANCELLED' &&
                            r['paymentStatus'] == 'UNVERIFIED',
                      ))
                        Text(
                          'შესამოწმებელი: ${_sum(scoped.where((r) => r['status'] != 'CANCELLED' && r['paymentStatus'] == 'UNVERIFIED'), 'remaining')} ₾',
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'არჩეული ფილტრები: ${debts.length} მიღება · ${_sum(debts.where((r) => r['paymentStatus'] != 'UNVERIFIED'), 'remaining')} ₾ გადასახდელი',
                      ),
                      const SizedBox(height: 8),
                      if (debts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('ამ ფილტრებით მიღებები არ არის.'),
                        ),
                      for (final row in debts)
                        Card(
                          key: ValueKey('payable-${row['id']}'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${row['supplierName']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'მიღება: ${row['businessDate']} · ${row['documentTotal']} ₾',
                                ),
                                Text(
                                  'გადახდილი: ${row['paid']} ₾ · დარჩა: ${row['remaining']} ₾',
                                ),
                                Text(
                                  _paymentLabel(row['paymentStatus']),
                                  style: TextStyle(color: AdminTheme.textMuted),
                                ),
                                if (row['dueDate'] != null)
                                  Text('ვადა: ${row['dueDate']}'),
                                if ((InventoryDecimal.parse(
                                      '${row['remaining']}',
                                    ).raw >
                                    BigInt.zero))
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.tonal(
                                      key: ValueKey('payable-pay-${row['id']}'),
                                      onPressed: () => _payment(row),
                                      child: const Text('გადახდის დაფიქსირება'),
                                    ),
                                  ),
                                if (row['paymentStatus'] == 'UNVERIFIED')
                                  TextButton(
                                    onPressed: () => _verify(row),
                                    child: const Text(
                                      'ძველი გადახდების შემოწმება',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ] else ...[
                      const SizedBox(height: 20),
                      Text(
                        'პერიოდში გადახდილი: ${_sum(payments.map((e) => e.payment), 'amount')} ₾',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'უკუქცევების გათვალისწინებით',
                        style: TextStyle(
                          color: AdminTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (payments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('ამ პერიოდში გადახდები არ არის.'),
                        ),
                      for (final entry in payments)
                        Card(
                          child: ListTile(
                            key: ValueKey('payment-${entry.payment['id']}'),
                            title: Text(
                              '${entry.payment['amount']} ₾ · ${entry.receipt['supplierName']}',
                            ),
                            subtitle: Text(
                              '${entry.payment['paymentDate']} · ${entry.payment['method'] == 'cash' ? 'ნაღდი' : 'ბანკი'}\nმიღება: ${entry.receipt['businessDate']}${entry.payment['reversalOfId'] != null ? '\nუკუქცევა' : ''}${entry.receipt['status'] == 'CANCELLED' ? '\nმიღება გაუქმებულია' : ''}',
                            ),
                            isThreeLine: true,
                            trailing:
                                entry.payment['reversalOfId'] == null &&
                                    !(entry.receipt['payments'] as List)
                                        .cast<Map>()
                                        .any(
                                          (p) =>
                                              p['reversalOfId'] ==
                                              entry.payment['id'],
                                        ) &&
                                    entry.receipt['status'] != 'CANCELLED'
                                ? IconButton(
                                    tooltip: 'გადახდის უკუქცევა',
                                    icon: const Icon(Icons.undo),
                                    onPressed: () =>
                                        _reverse(entry.receipt, entry.payment),
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
