import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/ui/vynic_spacing.dart';
import 'mobile_admin_screen.dart';

typedef FinanceRead = Future<Map<String, dynamic>> Function(String path);
typedef FinanceWrite =
    Future<void> Function(
      String path,
      Map<String, dynamic> data, {
      bool update,
    });
const compensationLabels = {
  'MONTHLY_FIXED': 'თვიური',
  'DAILY_FIXED': 'დღიური',
  'MANUAL': 'ხელით დარიცხვა',
};
const obligationLabels = {
  'RENT': 'ქირა',
  'BANK_LOAN': 'ბანკის სესხი',
  'LEASE': 'ლიზინგი',
  'UTILITY': 'კომუნალური',
  'OTHER': 'სხვა',
};
List<Map<String, dynamic>> financeRows(dynamic rows) => (rows as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

ThemeData financeTheme(BuildContext context) =>
    inventoryTheme(context).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AdminTheme.primary,
        brightness: Theme.of(context).brightness,
      ),
    );

/// The Financials destinations are independent so future access policy can wrap
/// obligations without entering payroll or reserve arithmetic.
class FinancePlanningScreen extends StatefulWidget {
  const FinancePlanningScreen({
    super.key,
    this.obligations = false,
    this.read,
    this.write,
  });
  final bool obligations;
  final FinanceRead? read;
  final FinanceWrite? write;
  @override
  State<FinancePlanningScreen> createState() => _FinancePlanningState();
}

class _FinancePlanningState extends State<FinancePlanningScreen> {
  Map<String, dynamic>? _data;
  String? _month, _error;
  bool _loading = true;
  FinanceRead get read => widget.read ?? MobileApiService.financeRead;
  FinanceWrite get write => widget.write ?? MobileApiService.financeWrite;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await read(
        '${widget.obligations ? 'obligations' : 'payroll'}${_month == null ? '' : '?month=$_month'}',
      );
      if (mounted)
        setState(() {
          _data = data;
          _month = data['periodMonth'] as String?;
        });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'მონაცემები ვერ ჩაიტვირთა. სცადეთ თავიდან.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _form(
    String title,
    String path,
    List<FinanceField> fields, {
    Map<String, dynamic> defaults = const {},
    bool update = false,
    String? help,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Theme(
        data: financeTheme(context),
        child: FinanceEntryDialog(
          title: title,
          fields: fields,
          defaults: defaults,
          help: help,
          save: (data) => write(path, data, update: update),
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _history(String title, String path) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              FinanceHistoryScreen(title: title, path: path, read: read),
        ),
      );
  String get businessDate => _data!['businessDate'].toString();
  String get today => _data!['today'].toString();
  Future<void> _payment(String path, {bool reserve = false}) => _form(
    reserve ? 'თანხის გადადება' : 'გადახდის დაფიქსირება',
    path,
    [
      const FinanceField('amount', 'თანხა (₾)', money: true),
      FinanceField(
        'businessDate',
        'სამუშაო თარიღი',
        value: businessDate,
        date: true,
      ),
      if (!reserve)
        FinanceField(
          'paymentDate',
          'გადახდის თარიღი',
          value: today,
          date: true,
        ),
      const FinanceField('notes', 'შენიშვნა', optional: true),
    ],
    defaults: {'id': const Uuid().v4()},
    help: reserve
        ? 'გადადებული თანხა ჯერ ხარჯი არ არის.'
        : 'ჩაწერეთ უკვე შესრულებული გადახდა. თანხა ავტომატურად არ გადაირიცხება.',
  );
  Future<void> _compensation(Map<String, dynamic> staff) {
    final rules = financeRows(staff['compensation']);
    final current = rules.isEmpty ? <String, dynamic>{} : rules.first;
    final from = DateTime.parse('${_month!}-01');
    final next = DateTime(
      from.year,
      from.month + 1,
      1,
    ).toIso8601String().substring(0, 10);
    return _form(
      'ხელფასის წესი',
      'staff/${staff['id']}/compensation',
      [
        FinanceField(
          'compensationType',
          'ხელფასის ტიპი',
          value: current['compensationType']?.toString() ?? 'MONTHLY_FIXED',
          choices: compensationLabels,
        ),
        FinanceField(
          'amount',
          'თანხა / დღიური ტარიფი (₾)',
          value: current['amount']?.toString() ?? '',
          money: true,
          allowZero: true,
        ),
        FinanceField(
          'effectiveFrom',
          'მოქმედებს თვის პირველი რიცხვიდან',
          value: rules.isEmpty ? '${_month!}-01' : next,
          date: true,
        ),
        FinanceField(
          'isActive',
          'წესის მდგომარეობა',
          value: 'true',
          choices: const {'true': 'აქტიური', 'false': 'შეჩერებული'},
        ),
        const FinanceField('notes', 'შენიშვნა', optional: true),
      ],
      help:
          'გახსნილი თვე უცვლელია. ცვლილება გამოიყენება შემდეგ თავისუფალ თვეში. დღიური ხელფასი ითვლება მხოლოდ დამატებული სამუშაო დღეებით.',
    );
  }

  Future<void> _obligation([Map<String, dynamic>? value]) {
    final v = value ?? <String, dynamic>{};
    return _form(
      value == null ? 'ვალდებულების დამატება' : 'ვალდებულების რედაქტირება',
      value == null ? 'obligations' : 'obligations/${v['id']}',
      [
        FinanceField('name', 'დასახელება', value: v['name']?.toString() ?? ''),
        FinanceField(
          'type',
          'ტიპი',
          value: v['type']?.toString() ?? 'RENT',
          choices: obligationLabels,
        ),
        FinanceField(
          'monthlyAmount',
          'თვეში (₾)',
          value: v['monthlyAmount']?.toString() ?? '',
          money: true,
        ),
        FinanceField(
          'dueDay',
          'გადახდის რიცხვი (1–31)',
          value: v['dueDay']?.toString() ?? '25',
          integer: true,
        ),
        FinanceField(
          'startsOn',
          'დაწყების თარიღი',
          value: v['startsOn']?.toString() ?? today,
          date: true,
          readOnly: value != null,
        ),
        FinanceField(
          'endsOn',
          'დასრულების თარიღი',
          value: v['endsOn']?.toString() ?? '',
          date: true,
          optional: true,
        ),
        FinanceField(
          'isActive',
          'მდგომარეობა',
          value: (v['isActive'] ?? true).toString(),
          choices: const {'true': 'აქტიური', 'false': 'გამორთული'},
        ),
        FinanceField(
          'notes',
          'შენიშვნა',
          value: v['notes']?.toString() ?? '',
          optional: true,
        ),
      ],
      defaults: value == null ? {'id': const Uuid().v4()} : const {},
      update: value != null,
      help: value == null
          ? 'თითოეულ თვეს საკუთარი თანხა და ვადა ექნება.'
          : 'ცვლილება ეხება მომავალ თვეებს. უკვე გახსნილი თვეების თანხა და ვადა უცვლელია.',
    );
  }

  Future<void> _monthPicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse('${_month!}-01'),
      firstDate: DateTime(2000),
      lastDate: DateTime.parse(today),
    );
    if (picked != null) {
      _month = picked.toIso8601String().substring(0, 7);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: financeTheme(context),
    child: Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        toolbarHeight: widget.obligations ? 80 : kToolbarHeight,
        title: Text(
          widget.obligations ? 'ყოველთვიური ვალდებულებები' : 'ხელფასები',
          maxLines: 2,
          style: const TextStyle(fontSize: 20),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'განახლება',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _load,
                      child: const Text('თავიდან ცდა'),
                    ),
                  ],
                ),
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(VynicSpacing.md),
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _monthPicker,
                            icon: const Icon(Icons.calendar_month),
                            label: Text('პერიოდი: $_month'),
                          ),
                          if (widget.obligations)
                            FilledButton.icon(
                              onPressed: () => _obligation(),
                              icon: const Icon(Icons.add),
                              label: const Text('ვალდებულების დამატება'),
                            ),
                          if (!widget.obligations)
                            OutlinedButton(
                              onPressed: () => _history(
                                'ძველი ხელფასების ისტორია',
                                'legacy-salaries',
                              ),
                              child: const Text('ძველი ხელფასების ისტორია'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (widget.obligations)
                        ..._obligations()
                      else
                        ..._payroll(),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
  List<Widget> _payroll() {
    final staff = financeRows(_data!['staff']);
    if (staff.isEmpty)
      return [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'თანამშრომლები ჯერ არ არის დამატებული. დაამატეთ თანამშრომელი მართვის სექციიდან.',
          ),
        ),
      ];
    return staff.map((s) {
      final p = s['period'] is Map
          ? Map<String, dynamic>.from(s['period'])
          : null;
      return Card(
        child: ExpansionTile(
          key: ValueKey('payroll-staff-${s['id']}'),
          title: Text(s['username'].toString()),
          subtitle: Text(
            p == null
                ? 'ხელფასის წესი დასაყენებელია'
                : '${compensationLabels[p['compensationType']]}: ${p['rate']} ₾\nდარჩენილი: ${p['remaining']} ₾',
          ),
          childrenPadding: const EdgeInsets.all(16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('მიმდინარე პერიოდი: $_month'),
            if (s['isActive'] == false) const Text('არააქტიური თანამშრომელი'),
            if (p != null) ...[
              Text('მოსალოდნელი: ${p['expected']} ₾'),
              Text('გადახდილი: ${p['paid']} ₾'),
              Text('დარჩენილი: ${p['remaining']} ₾'),
              if (p['overpaid'] != '0.00')
                Text('ზედმეტად გადახდილი: ${p['overpaid']} ₾'),
              if (p['compensationType'] == 'DAILY_FIXED')
                Text('სამუშაო დღეები: ${financeRows(p['accruals']).length}'),
            ],
            for (final rule in financeRows(s['compensation']))
              Text(
                '${compensationLabels[rule['compensationType']]}: ${rule['amount']} ₾ · ${rule['effectiveFrom']}${rule['isActive'] == false ? ' · შეჩერებული' : ''}',
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _compensation(s),
                  child: const Text('ხელფასის წესი'),
                ),
                if (p != null)
                  FilledButton(
                    onPressed: () => _payment('payroll/${p['id']}/payments'),
                    child: const Text('გადახდის დაფიქსირება'),
                  ),
                if (p != null && p['compensationType'] != 'MONTHLY_FIXED')
                  OutlinedButton(
                    onPressed: () => _form(
                      p['compensationType'] == 'DAILY_FIXED'
                          ? 'სამუშაო დღის დამატება'
                          : 'ხელით დარიცხვა',
                      'payroll/${p['id']}/accruals',
                      [
                        if (p['compensationType'] == 'DAILY_FIXED')
                          FinanceField(
                            'payableDate',
                            'ნამუშევარი დღე',
                            value: businessDate.startsWith(_month!)
                                ? businessDate
                                : '${_month!}-01',
                            date: true,
                          )
                        else
                          const FinanceField(
                            'amount',
                            'დასარიცხი თანხა (₾)',
                            money: true,
                          ),
                        const FinanceField('notes', 'შენიშვნა', optional: true),
                      ],
                      defaults: {'id': const Uuid().v4()},
                      help: 'დარიცხვა გადახდა არ არის.',
                    ),
                    child: Text(
                      p['compensationType'] == 'DAILY_FIXED'
                          ? 'სამუშაო დღის დამატება'
                          : 'ხელით დარიცხვა',
                    ),
                  ),
                OutlinedButton(
                  onPressed: () => _history(
                    s['username'].toString(),
                    'staff/${s['id']}/history',
                  ),
                  child: const Text('გადახდების ისტორია'),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _obligations() {
    final templates = financeRows(_data!['obligations']),
        cycles = financeRows(_data!['cycles']);
    if (templates.isEmpty)
      return [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'ყოველთვიური ვალდებულებები ჯერ არ გაქვთ. დაამატეთ ქირა, სესხი ან სხვა რეგულარული ვალდებულება.',
          ),
        ),
      ];
    return templates.map((t) {
      final matches = cycles.where((c) => c['obligationId'] == t['id']);
      final c = matches.isEmpty ? null : matches.first;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c?['name']?.toString() ?? t['name'].toString(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${obligationLabels[c?['type'] ?? t['type']]}${t['isActive'] == false ? ' · გამორთული' : ''}',
              ),
              const SizedBox(height: 12),
              if (c == null)
                const Text('ამ თვეში გადასახდელი არ არის.')
              else ...[
                Text('თვეში: ${c['targetAmount']} ₾'),
                Text('ვადა: ${c['dueDate']}'),
                if (c['status'] == 'OVERDUE')
                  Text(
                    'ვადაგადაცილებულია',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (c['status'] == 'PAID') const Text('გადახდილია'),
                Text('გადადებული: ${c['reservedAmount']} ₾'),
                Text('გადახდილი: ${c['paidAmount']} ₾'),
                Text('გადასადები დარჩა: ${c['remainingToCover']} ₾'),
                Text('გადასახდელი დარჩა: ${c['remainingToPay']} ₾'),
                Text(
                  'დღიური მიზანი: ${c['dailyRecommendedReserve']} ₾',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c != null && c['remainingToCover'] != '0.00')
                    FilledButton(
                      onPressed: () =>
                          _payment('cycles/${c['id']}/reserves', reserve: true),
                      child: const Text('თანხის გადადება'),
                    ),
                  if (c != null && c['status'] != 'PAID')
                    OutlinedButton(
                      onPressed: () => _payment('cycles/${c['id']}/payments'),
                      child: const Text('გადახდის დაფიქსირება'),
                    ),
                  OutlinedButton(
                    onPressed: () => _history(
                      t['name'].toString(),
                      'obligations/${t['id']}/history',
                    ),
                    child: const Text('ისტორია'),
                  ),
                  OutlinedButton(
                    onPressed: () => _obligation(t),
                    child: const Text('რედაქტირება'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

class FinanceField {
  const FinanceField(
    this.name,
    this.label, {
    this.value = '',
    this.money = false,
    this.allowZero = false,
    this.integer = false,
    this.date = false,
    this.optional = false,
    this.readOnly = false,
    this.choices,
  });
  final String name, label, value;
  final bool money, allowZero, integer, date, optional, readOnly;
  final Map<String, String>? choices;
}

class FinanceEntryDialog extends StatefulWidget {
  const FinanceEntryDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.save,
    this.defaults = const {},
    this.help,
  });
  final String title;
  final List<FinanceField> fields;
  final Map<String, dynamic> defaults;
  final String? help;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<FinanceEntryDialog> createState() => _FinanceEntryState();
}

class _FinanceEntryState extends State<FinanceEntryDialog> {
  final _form = GlobalKey<FormState>();
  late final _controllers = {
    for (final f in widget.fields) f.name: TextEditingController(text: f.value),
  };
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(FinanceField f, String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return f.optional ? null : 'შეავსეთ ველი';
    if (f.money &&
        (!RegExp(r'^\d{1,16}(\.\d{1,2})?$').hasMatch(v) ||
            (!f.allowZero &&
                BigInt.tryParse(v.replaceAll('.', '')) == BigInt.zero)))
      return 'ჩაწერეთ დადებითი თანხა (მაგ: 1500.00)';
    if (f.integer &&
        (int.tryParse(v) == null || int.parse(v) < 1 || int.parse(v) > 31))
      return 'აირჩიეთ რიცხვი 1–31';
    if (f.date &&
        (!RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(v) ||
            DateTime.tryParse(v)?.toIso8601String().substring(0, 10) != v))
      return 'თარიღის ფორმატი: YYYY-MM-DD';
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = {...widget.defaults};
    for (final f in widget.fields) {
      final value = _controllers[f.name]!.text.trim();
      data[f.name] = f.integer
          ? int.parse(value)
          : f.name == 'isActive'
          ? value == 'true'
          : value.isEmpty && f.optional
          ? null
          : value;
    }
    try {
      await widget.save(data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.help != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(widget.help!),
                  ),
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: f.choices != null
                        ? DropdownButtonFormField<String>(
                            key: ValueKey('finance-${f.name}'),
                            initialValue: f.value,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: f.choices!.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (v) => _controllers[f.name]!.text = v!,
                          )
                        : TextFormField(
                            key: ValueKey('finance-${f.name}'),
                            controller: _controllers[f.name],
                            readOnly: f.readOnly,
                            enabled: !_saving,
                            decoration: InputDecoration(
                              labelText: f.label,
                              hintText: f.date ? 'YYYY-MM-DD' : null,
                            ),
                            keyboardType: f.money
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : f.integer
                                ? TextInputType.number
                                : TextInputType.text,
                            validator: (v) => _validate(f, v),
                          ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('გაუქმება'),
        ),
        FilledButton(
          key: const Key('finance-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'ინახება…' : 'შენახვა'),
        ),
      ],
    ),
  );
}

class FinanceHistoryScreen extends StatefulWidget {
  const FinanceHistoryScreen({
    super.key,
    required this.title,
    required this.path,
    required this.read,
  });
  final String title, path;
  final FinanceRead read;
  @override
  State<FinanceHistoryScreen> createState() => _FinanceHistoryState();
}

class _FinanceHistoryState extends State<FinanceHistoryScreen> {
  late Future<Map<String, dynamic>> _future = widget.read(widget.path);
  @override
  Widget build(BuildContext context) => Theme(
    data: financeTheme(context),
    child: Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError)
            return Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => _future = widget.read(widget.path)),
                child: const Text('ვერ ჩაიტვირთა — თავიდან ცდა'),
              ),
            );
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snap.data!;
          final legacy = data.containsKey('entries');
          final periods = financeRows(
            data['periods'] ?? data['cycles'] ?? data['entries'],
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (legacy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'ძველი ჩანაწერები — მხოლოდ წაკითხვა. თანამშრომელზე ავტომატურად არ არის მიბმული.',
                  ),
                ),
              if (periods.isEmpty) const Text('ისტორია ჯერ არ არის.'),
              for (final p in periods)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (legacy)
                          Text(
                            '${p['description']} · ${p['amount']} ₾\n${p['businessDate'] == '' ? p['createdAt'] : p['businessDate']}',
                          )
                        else ...[
                          Text(
                            '${p['periodMonth']}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'მოსალოდნელი: ${p['expected'] ?? p['targetAmount']} ₾',
                          ),
                          Text('გადახდილი: ${p['paid'] ?? p['paidAmount']} ₾'),
                          Text(
                            'დარჩენილი: ${p['remaining'] ?? p['remainingToPay']} ₾',
                          ),
                          for (final group in [
                            ('payments', 'გადახდა'),
                            ('reserves', 'გადადება'),
                            ('accruals', 'დარიცხვა'),
                          ])
                            for (final e in financeRows(p[group.$1]))
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  '${group.$2}: ${e['amount']} ₾\n${e['businessDate'] ?? e['payableDate'] ?? p['periodMonth']} · ${e['actorName']}'
                                  '${e['paymentDate'] == null ? '' : '\nგადახდის თარიღი: ${e['paymentDate']}'}'
                                  '${e['reserveConsumed'] == null ? '' : '\nრეზერვიდან: ${e['reserveConsumed']} ₾'}'
                                  '${e['notes'] == null ? '' : '\n${e['notes']}'}',
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
