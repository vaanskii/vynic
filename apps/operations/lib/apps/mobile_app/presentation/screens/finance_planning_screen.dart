import '../widgets/manager_design_components.dart';
import 'package:vynic/core/models/inventory_decimal.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_modal.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'mobile_admin_screen.dart';
import '../widgets/finance_correction_dialog.dart';
import 'package:vynic/core/services/manager_app/finance_correction_request.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';

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
  'MANUAL': 'ხელით',
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

ThemeData financeTheme(BuildContext context) => inventoryTheme(context);

Future<void> showManagerFinancePlanning(
  BuildContext context, {
  bool obligations = false,
  FinanceRead? read,
  FinanceWrite? write,
}) => showDialog<void>(
  context: context,
  builder: (_) => FinancePlanningScreen(
    obligations: obligations,
    read: read,
    write: write,
    asDialog: true,
  ),
);

/// The Financials destinations are independent so future access policy can wrap
/// obligations without entering payroll or reserve arithmetic.
class FinancePlanningScreen extends StatefulWidget {
  const FinancePlanningScreen({
    super.key,
    this.obligations = false,
    this.asDialog = false,
    this.read,
    this.write,
    this.correctionSend,
    this.correctionScope,
  });
  final bool obligations, asDialog;
  final FinanceRead? read;
  final FinanceWrite? write;
  final FinanceCorrectionSend? correctionSend;
  final String? correctionScope;
  @override
  State<FinancePlanningScreen> createState() => _FinancePlanningState();
}

class _FinancePlanningState extends State<FinancePlanningScreen> {
  Map<String, dynamic>? _data;
  String? _month, _error;
  bool _loading = true;
  int _payrollTab = 0;
  String? _day;
  final _dayBusy = <String>{};
  final _dayErrors = <String, String>{};
  final _dayRequests = <String, Map<String, dynamic>>{};
  FinanceRead get read => widget.read ?? MobileApiService.financeRead;
  FinanceWrite get write => widget.write ?? MobileApiService.financeWrite;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_dayBusy.isNotEmpty) return;
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
          _dayErrors.clear();
          _dayRequests.clear();
          _month = data['periodMonth'] as String?;
          _day ??= data['businessDate'] as String?;
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

  Future<void> _history(String title, String path) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FinanceHistoryScreen(
          title: title,
          path: path,
          read: read,
          correctionSend: widget.correctionSend,
          correctionScope: widget.correctionScope,
        ),
      ),
    );
    if (mounted) await _load();
  }

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
    final from = DateTime.parse('${today.substring(0, 7)}-01');
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
          value: rules.isEmpty
              ? '${today.substring(0, 7)}-01'
              : (current['effectiveFrom'].toString().compareTo(next) > 0
                    ? current['effectiveFrom'].toString()
                    : next),
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
      lastDate: DateTime.parse(widget.obligations ? today : businessDate),
    );
    if (picked != null) {
      _month = picked.toIso8601String().substring(0, 7);
      _day = _month == businessDate.substring(0, 7)
          ? businessDate
          : '${_month!}-01';
      await _load();
    }
  }

  String get _monthTitle {
    final date = DateTime.tryParse('${_month}-01');
    if (date == null) return _month ?? '';
    const months = [
      'იანვარი',
      'თებერვალი',
      'მარტი',
      'აპრილი',
      'მაისი',
      'ივნისი',
      'ივლისი',
      'აგვისტო',
      'სექტემბერი',
      'ოქტომბერი',
      'ნოემბერი',
      'დეკემბერი',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final title = Text(
      widget.obligations ? 'ვალდებულებები' : 'ხელფასები',
      maxLines: 2,
      style: managerDesignText(
        context,
        MediaQuery.sizeOf(context).width < 700 ? 20 : 24,
        weight: FontWeight.w600,
      ),
    );
    final refresh = IconButton(
      onPressed: _loading || _dayBusy.isNotEmpty ? null : _load,
      tooltip: 'განახლება',
      icon: const Icon(Icons.refresh, size: 20),
    );
    final body = _loading
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
              constraints: const BoxConstraints(maxWidth: 880),
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  shrinkWrap: widget.asDialog,
                  physics: widget.asDialog
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 700 ? 20 : 28,
                  ),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _dayBusy.isNotEmpty ? null : _monthPicker,
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            _monthTitle,
                            style: managerDesignText(
                              context,
                              17,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!widget.obligations)
                          IconButton(
                            tooltip: 'ძველი ხელფასების ისტორია',
                            onPressed: () => _history(
                              'ძველი ხელფასების ისტორია',
                              'legacy-salaries',
                            ),
                            icon: const Icon(Icons.history, size: 20),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (widget.obligations) ...[
                      Text(
                        'პერიოდის გეგმა და უკვე შესრულებული გადახდები',
                        style: managerDesignText(context, 12, muted: true),
                      ),
                      const SizedBox(height: 16),
                      ManagerKeyValue(
                        'დარჩენილი გადასახდელი',
                        _cycleTotal('remainingToPay'),
                        emphasis: true,
                      ),
                      ManagerKeyValue(
                        'გადადებული რეზერვი',
                        _cycleTotal('reservedAmount'),
                      ),
                      const SizedBox(height: 18),
                      ..._obligations(),
                      const ManagerHelpCallout(
                        'რეზერვი დაგეგმვის თანხაა. გასავალი ჩნდება მხოლოდ გადახდის აღრიცხვისას.',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => _obligation(),
                        icon: const Icon(Icons.add),
                        label: const Text('ვალდებულების დამატება'),
                      ),
                    ] else ...[
                      ManagerSegments(
                        labels: const [
                          'მიმოხილვა',
                          'დღიური',
                          'თვიური',
                          'გადახდები',
                        ],
                        selected: _payrollTab,
                        keys: [
                          for (var i = 0; i < 4; i++)
                            ValueKey('payroll-tab-$i'),
                        ],
                        onSelect: (index) {
                          if (_dayBusy.isEmpty)
                            setState(() => _payrollTab = index);
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_payrollTab == 1)
                        ..._dailySheet()
                      else if (_payrollTab == 3)
                        ..._payments()
                      else ...[
                        if (_payrollTab == 0 && _data!['totals'] is Map) ...[
                          ManagerKeyValue(
                            'დარიცხული',
                            '${_data!['totals']['expected']} ₾',
                          ),
                          ManagerKeyValue(
                            'გადახდილი',
                            '${_data!['totals']['paid']} ₾',
                          ),
                          ManagerKeyValue(
                            'დარჩენილი',
                            '${_data!['totals']['remaining']} ₾',
                            emphasis: true,
                          ),
                          const SizedBox(height: 20),
                          ManagerPanel(
                            padding: 16,
                            muted: true,
                            child: Text(
                              'დარიცხვა და გადახდა განსხვავდება. ფინანსურ გასავლებში მხოლოდ გადახდა შედის.',
                              style: managerDesignText(
                                context,
                                12,
                                muted: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        ..._payroll(),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          );
    return Theme(
      data: financeTheme(context),
      child: widget.asDialog
          ? ManagerFormDialog(
              maxWidth: 880,
              title: Row(
                children: [
                  Expanded(child: title),
                  refresh,
                  IconButton(
                    tooltip: 'დახურვა · Esc',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 21),
                  ),
                ],
              ),
              contentPadding: EdgeInsets.zero,
              content: body,
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('დახურვა'),
                ),
              ],
            )
          : Scaffold(
              backgroundColor: AdminTheme.bg,
              appBar: AppBar(
                backgroundColor: AdminTheme.bg,
                toolbarHeight: 80,
                title: title,
                actions: [refresh],
              ),
              body: body,
            ),
    );
  }

  List<Widget> _payroll() {
    final staff = financeRows(_data!['staff'])
        .where(
          (s) =>
              _payrollTab != 2 ||
              s['period']?['compensationType'] == 'MONTHLY_FIXED',
        )
        .toList();
    if (staff.isEmpty)
      return [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'თანამშრომლები ჯერ არ არის დამატებული. დაამატეთ თანამშრომელი მართვის სექციიდან.',
          ),
        ),
      ];
    final rows = staff.map((s) {
      final p = s['period'] is Map
          ? Map<String, dynamic>.from(s['period'])
          : null;
      return ExpansionTile(
        key: PageStorageKey<String>('payroll-staff-${s['id']}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        title: Text(
          s['username'].toString(),
          style: managerDesignText(context, 14, weight: FontWeight.w500),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            p == null
                ? 'ხელფასის ტიპი დასაყენებელია'
                : '${compensationLabels[p['compensationType']]} · დარჩენილი ${p['remaining']} ₾',
            style: managerDesignText(context, 11, muted: true),
          ),
        ),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('მიმდინარე პერიოდი: $_month'),
          if (s['isActive'] == false) const Text('არააქტიური თანამშრომელი'),
          if (p != null) ...[
            Text(
              p['compensationType'] == 'MANUAL'
                  ? 'ხელფასი გამოითვლება ხელით'
                  : '${p['compensationType'] == 'DAILY_FIXED' ? 'დღიური განაკვეთი' : 'თვიური ხელფასი'}: ${p['rate']} ₾',
            ),
            ManagerKeyValue('დარიცხული', "${p['expected']} ₾"),
            ManagerKeyValue('გადახდილი', "${p['paid']} ₾"),
            ManagerKeyValue('დარჩენილი', "${p['remaining']} ₾", emphasis: true),
            if (p['overpaid'] != '0.00')
              Text('ზედმეტად გადახდილი: ${p['overpaid']} ₾'),
            if (p['compensationType'] == 'DAILY_FIXED')
              Text(
                'ამ თვეში ნამუშევარი დღეები: ${p['workedDays'] ?? financeRows(p['accruals']).length}',
              ),
          ],
          for (final rule in financeRows(s['compensation']))
            Text(
              '${compensationLabels[rule['compensationType']]}${rule['compensationType'] == 'MANUAL' ? '' : ': ${rule['amount']} ₾'} · ${rule['effectiveFrom']}${rule['isActive'] == false ? ' · შეჩერებული' : ''}',
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
              if (p != null && p['compensationType'] == 'DAILY_FIXED')
                OutlinedButton(
                  onPressed: () => setState(() => _payrollTab = 1),
                  child: const Text('დღიური თანამშრომლები'),
                ),
              if (p != null && p['compensationType'] == 'MANUAL')
                OutlinedButton(
                  onPressed: () => _form(
                    'ხელით დარიცხვა',
                    'payroll/${p['id']}/accruals',
                    [
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
                  child: const Text('ხელით დარიცხვა'),
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
      );
    }).toList();
    final list = Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          rows[i],
        ],
      ],
    );
    return [widget.asDialog ? list : ManagerPanel(padding: 0, child: list)];
  }

  Future<void> _selectDay(String value) async {
    setState(() => _day = value);
    if (value.substring(0, 7) != _month) {
      _month = value.substring(0, 7);
      await _load();
    }
  }

  Future<void> _pickDay() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_day!),
      firstDate: DateTime(2000),
      lastDate: DateTime.parse(businessDate),
    );
    if (date != null) await _selectDay(date.toIso8601String().substring(0, 10));
  }

  Future<void> _worked(Map<String, dynamic> p, bool worked) async {
    final key = '${p['id']}:$_day';
    final data = _dayRequests.putIfAbsent(
      key,
      () => {'id': const Uuid().v4(), 'businessDate': _day, 'worked': worked},
    );
    setState(() {
      _dayBusy.add(key);
      _dayErrors.remove(key);
    });
    try {
      await write('payroll/${p['id']}/day', data);
      // Reconcile from the server before permitting a different action.
      final fresh = await read('payroll?month=$_month');
      if (mounted)
        setState(() {
          _data = fresh;
          _dayRequests.remove(key);
        });
    } catch (e) {
      if (mounted)
        setState(
          () => _dayErrors[key] = e.toString().replaceFirst('Exception: ', ''),
        );
    } finally {
      if (mounted) setState(() => _dayBusy.remove(key));
    }
  }

  List<Widget> _dailySheet() {
    final staff = financeRows(
      _data!['staff'],
    ).where((s) => s['period']?['compensationType'] == 'DAILY_FIXED').toList();
    final date = DateTime.parse(_day!);
    String shift(int n) =>
        date.add(Duration(days: n)).toIso8601String().substring(0, 10);
    return [
      Text(
        'დღიური თანამშრომლები',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 440,
          child: Row(
            children: [
              IconButton(
                tooltip: 'წინა სამუშაო დღე',
                onPressed: _dayBusy.isNotEmpty || _day == '2000-01-01'
                    ? null
                    : () => _selectDay(shift(-1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _dayBusy.isNotEmpty ? null : _pickDay,
                  child: Text(
                    'სამუშაო თარიღი\n$_day',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'შემდეგი სამუშაო დღე',
                onPressed:
                    _dayBusy.isNotEmpty || _day!.compareTo(businessDate) >= 0
                    ? null
                    : () => _selectDay(shift(1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
      const Text('მონიშნეთ ნამუშევარი დღე. გადახდა ცალკე ფიქსირდება.'),
      const SizedBox(height: 12),
      if (staff.isEmpty) const Text('ამ თვეში დღიური თანამშრომლები არ არის.'),
      for (final s in staff) _dailyStaff(s),
    ];
  }

  Widget _dailyStaff(Map<String, dynamic> s) {
    final p = Map<String, dynamic>.from(s['period']);
    final days = financeRows(p['payableDays']);
    final worked = days.any(
      (d) => d['businessDate'] == _day && d['worked'] == true,
    );
    final key = '${p['id']}:$_day';
    final error = _dayErrors[key];
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s['username'].toString(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (s['isActive'] == false) const Text('არააქტიური თანამშრომელი'),
        Text('დღიური განაკვეთი: ${p['rate']} ₾ / დღე'),
      ],
    );
    final toggle = CheckboxListTile(
      key: ValueKey('worked-${s['id']}'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        _dayBusy.contains(key)
            ? 'ინახება…'
            : worked
            ? 'იმუშავა'
            : 'არ უმუშავია',
      ),
      value: worked,
      onChanged: _dayBusy.isNotEmpty || error != null
          ? null
          : (v) => _worked(p, v!),
    );
    final totals = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ნამუშევარი დღეები: ${p['workedDays'] ?? 0}'),
        Text('დარიცხული: ${p['expected']} ₾'),
        Text('გადახდილი: ${p['paid']} ₾'),
        Text('დარჩენილი: ${p['remaining']} ₾'),
      ],
    );
    final history = TextButton(
      onPressed: () =>
          _history(s['username'].toString(), 'staff/${s['id']}/history'),
      child: const Text('ისტორია'),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (constraints.maxWidth >= 680)
                  Row(
                    children: [
                      Expanded(flex: 3, child: identity),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: toggle),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: totals),
                      history,
                    ],
                  )
                else ...[
                  identity,
                  toggle,
                  totals,
                  Align(alignment: Alignment.centerLeft, child: history),
                ],
                if (error != null) ...[
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _dayBusy.isNotEmpty
                          ? null
                          : () => _worked(
                              p,
                              _dayRequests[key]!['worked'] as bool,
                            ),
                      child: const Text('თავიდან ცდა'),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _payments() {
    final staff = financeRows(
      _data!['staff'],
    ).where((s) => s['period'] != null).toList();
    return [
      const Text('ჩაწერეთ უკვე შესრულებული გადახდა.'),
      if (staff.isEmpty) const Text('გადახდისთვის ჯერ ხელფასის ტიპი დააყენეთ.'),
      for (final s in staff)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s['username'].toString(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'გადახდილი: ${s['period']['paid']} ₾ · დარჩენილი: ${s['period']['remaining']} ₾',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () =>
                          _payment('payroll/${s['period']['id']}/payments'),
                      child: const Text('გადახდის დაფიქსირება'),
                    ),
                    TextButton(
                      onPressed: () => _history(
                        s['username'].toString(),
                        'staff/${s['id']}/history',
                      ),
                      child: const Text('ისტორია'),
                    ),
                  ],
                ),
                for (final e in financeRows(s['period']['payments']))
                  Text(
                    '${e['amount']} ₾ · ${e['paymentDate']} · ${e['actorName']}',
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  // Display-only sum of the server's already-calculated period cycle values.
  // It never recalculates reserve/payment rules or substitutes zero for bad data.
  String _cycleTotal(String field) {
    try {
      var total = InventoryDecimal.zero;
      for (final cycle in financeRows(_data!['cycles'])) {
        total = total + InventoryDecimal.parse('${cycle[field]}');
      }
      return '${total.toStringAsFixed(2)} ₾';
    } on FormatException {
      return 'მიუწვდომელია';
    }
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
      final name = c?['name']?.toString() ?? t['name'].toString();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ManagerPanel(
          padding: 18,
          muted: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: managerDesignText(
                        context,
                        17,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (c != null) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${c['dueDate']}',
                          style: managerDesignText(context, 11, muted: true),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (t['isActive'] == false)
                Text(
                  'გამორთული',
                  style: managerDesignText(context, 11, muted: true),
                ),
              const SizedBox(height: 12),
              if (c == null)
                const Text('ამ თვეში გადასახდელი არ არის.')
              else ...[
                ManagerKeyValue('თვიური თანხა', '${c['targetAmount']} ₾'),
                ManagerKeyValue('რეზერვი', '${c['reservedAmount']} ₾'),
                ManagerKeyValue(
                  'რეკომენდებული დღიური',
                  '${c['dailyRecommendedReserve']} ₾',
                ),
                if (c['status'] == 'OVERDUE')
                  Text(
                    'ვადაგადაცილებულია',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (c['status'] == 'PAID') const Text('გადახდილია'),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (c['remainingToCover'] != '0.00')
                      OutlinedButton(
                        key: ValueKey('obligation-reserve-${t['id']}'),
                        onPressed: () => _payment(
                          'cycles/${c['id']}/reserves',
                          reserve: true,
                        ),
                        child: const Text('გადადება'),
                      ),
                    if (c['status'] != 'PAID')
                      FilledButton(
                        key: ValueKey('obligation-pay-${t['id']}'),
                        onPressed: () => _payment('cycles/${c['id']}/payments'),
                        child: const Text('გადახდა'),
                      ),
                  ],
                ),
              ],
              ExpansionTile(
                key: PageStorageKey('obligation-details-${t['id']}'),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'დეტალები და ისტორია',
                  style: managerDesignText(context, 12, muted: true),
                ),
                children: [
                  ManagerKeyValue(
                    'ტიპი',
                    '${obligationLabels[c?['type'] ?? t['type']]}',
                  ),
                  if (c != null) ...[
                    ManagerKeyValue('გადახდილი', '${c['paidAmount']} ₾'),
                    ManagerKeyValue(
                      'გადასადები დარჩა',
                      '${c['remainingToCover']} ₾',
                    ),
                    ManagerKeyValue(
                      'გადასახდელი დარჩა',
                      '${c['remainingToPay']} ₾',
                      emphasis: true,
                    ),
                  ],
                  ManagerDetailLink(
                    'ისტორია',
                    onTap: () =>
                        _history(name, 'obligations/${t['id']}/history'),
                  ),
                  ManagerDetailLink('რედაქტირება', onTap: () => _obligation(t)),
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
  String? get _salaryType => _controllers['compensationType']?.text;
  Iterable<FinanceField> get _visibleFields => widget.fields.where(
    (f) => !(f.name == 'amount' && _salaryType == 'MANUAL'),
  );
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
    if (_salaryType == 'MANUAL') data['amount'] = '0.00';
    for (final f in _visibleFields) {
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
    child: ManagerFormDialog(
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
                if (_salaryType == 'MANUAL')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('ხელფასი გამოითვლება ხელით'),
                  ),
                for (final f in _visibleFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: f.name == 'compensationType'
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.label),
                              RadioGroup<String>(
                                groupValue: _salaryType,
                                onChanged: (v) {
                                  if (!_saving)
                                    setState(() {
                                      if (_controllers[f.name]!.text != v)
                                        _controllers['amount']?.clear();
                                      _controllers[f.name]!.text = v!;
                                    });
                                },
                                child: Column(
                                  children: [
                                    for (final e in compensationLabels.entries)
                                      RadioListTile<String>(
                                        key: ValueKey('salary-type-${e.key}'),
                                        value: e.key,
                                        title: Text(e.value),
                                        enabled: !_saving,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : f.choices != null
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
                              labelText:
                                  f.name == 'amount' && _salaryType != null
                                  ? (_salaryType == 'DAILY_FIXED'
                                        ? 'დღიური განაკვეთი (₾ / დღე)'
                                        : 'თვიური ხელფასი (₾)')
                                  : f.label,
                              hintText: f.date ? 'YYYY-MM-DD' : null,
                            ),
                            keyboardType: f.money
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : f.integer
                                ? TextInputType.number
                                : TextInputType.text,
                            validator: (v) =>
                                f.name == 'amount' && _salaryType != null
                                ? _validate(
                                    FinanceField('amount', '', money: true),
                                    v,
                                  )
                                : _validate(f, v),
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
    this.correctionSend,
    this.correctionScope,
  });
  final String title, path;
  final FinanceRead read;
  final FinanceCorrectionSend? correctionSend;
  final String? correctionScope;
  @override
  State<FinanceHistoryScreen> createState() => _FinanceHistoryState();
}

class _FinanceHistoryState extends State<FinanceHistoryScreen> {
  late Future<Map<String, dynamic>> _future = _loadHistory();
  String? _shownScope, _shownSession, _storageError;
  final _retained = <String>{};
  Future<Map<String, dynamic>> _loadHistory() async {
    final scope = widget.correctionScope ?? _currentScope();
    final session = AuthTokenService.token;
    final data = await widget.read(widget.path);
    void requireSession() {
      if (widget.correctionScope == null &&
          scope != null &&
          (!MobileApiService.isCurrentTableRepairScope(scope) ||
              AuthTokenService.token != session)) {
        throw StateError('სესია შეიცვალა — განაახლეთ ისტორია');
      }
    }

    requireSession();
    _retained.clear();
    _storageError = null;
    if (scope != null) {
      try {
        await FinanceCorrectionRequests.init();
        requireSession();
        for (final p in financeRows(data['periods'] ?? data['cycles'])) {
          for (final group in ['payments', 'reserves']) {
            for (final entry in financeRows(p[group])) {
              final saved = FinanceCorrectionRequests.read(
                scope,
                _correctionPath(p, group, entry),
              );
              if (saved != null) _retained.add(entry['id'].toString());
            }
          }
        }
      } catch (error) {
        _storageError = error.toString();
      }
    }
    requireSession();
    _shownScope = scope;
    _shownSession = session;
    return data;
  }

  String? _currentScope() {
    try {
      return MobileApiService.tableRepairScope;
    } on StateError {
      return null;
    } on FormatException {
      return null;
    }
  }

  String _correctionPath(
    Map<String, dynamic> parent,
    String group,
    Map<String, dynamic> entry,
  ) =>
      '${parent.containsKey('staffId') ? 'payroll' : 'cycles'}/${parent['id']}/$group/${entry['id']}/reversal';
  Future<void> _correct(
    Map<String, dynamic> parent,
    String group,
    Map<String, dynamic> entry,
  ) async {
    try {
      final scope = _shownScope;
      if (scope == null) {
        throw StateError('სესია ვერ დადასტურდა — განაახლეთ ისტორია');
      }
      final session = _shownSession;
      void requireSession() {
        if (widget.correctionScope == null &&
            (!MobileApiService.isCurrentTableRepairScope(scope) ||
                AuthTokenService.token != session)) {
          throw StateError('სესია შეიცვალა — განაახლეთ ისტორია');
        }
      }

      final original = <String, dynamic>{
        for (final key in [
          'id',
          'amount',
          'businessDate',
          'paymentDate',
          'reserveConsumed',
        ])
          if (entry.containsKey(key)) key: entry[key],
      };
      requireSession();
      final path = _correctionPath(parent, group, entry);
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Theme(
          data: financeTheme(context),
          child: FinanceCorrectionDialog(
            path: path,
            original: original,
            scope: scope,
            requireSession: requireSession,
            send:
                widget.correctionSend ??
                MobileApiService.financeCorrectionWrite,
          ),
        ),
      );
      requireSession();
      if (saved == true && mounted) {
        setState(() {
          _future = _loadHistory();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('კორექტირება Cloud-ში შენახულია')),
        );
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

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
                onPressed: () => setState(() {
                  _future = _loadHistory();
                }),
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
          return ManagerContentWidth(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (legacy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'ძველი ჩანაწერები — მხოლოდ წაკითხვა. თანამშრომელზე ავტომატურად არ არის მიბმული.',
                    ),
                  ),
                if (_storageError != null)
                  Text('კორექტირების საცავი: $_storageError'),
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
                            Text(
                              'გადახდილი: ${p['paid'] ?? p['paidAmount']} ₾',
                            ),
                            Text(
                              'დარჩენილი: ${p['remaining'] ?? p['remainingToPay']} ₾',
                            ),
                            for (final group in [
                              ('payments', 'გადახდა'),
                              ('reserves', 'გადადება'),
                              ('accruals', 'დარიცხვა'),
                            ])
                              for (final e in financeRows(
                                p[group.$1],
                              ).where((e) => e['amount'] != '0.00'))
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '${e['reversalOfId'] == null ? group.$2 : 'კორექტირება'}: ${e['amount']} ₾\n'
                                        '${e['businessDate'] ?? e['payableDate'] ?? financeRows(p['accruals']).where((a) => a['id'] == e['dayEntryId']).firstOrNull?['payableDate'] ?? p['periodMonth']} · ${e['actorName']}'
                                        '${e['paymentDate'] == null ? '' : '\nგადახდის თარიღი: ${e['paymentDate']}'}'
                                        '${e['reserveConsumed'] == null ? '' : '\nრეზერვიდან: ${e['reserveConsumed']} ₾'}'
                                        '${e['notes'] == null ? '' : '\n${e['notes']}'}',
                                      ),
                                      if (e['reversalOfId'] != null)
                                        Text(
                                          'საწყისი ჩანაწერი: ${e['reversalOfId']}\n'
                                          'კორექტირების სამუშაო თარიღი: ${e['correctionBusinessDate']}\nდაფიქსირდა: ${e['createdAt']}',
                                        ),
                                      if (e['reversedById'] != null)
                                        Text(
                                          'კორექტირებულია: ${e['reversedById']}',
                                        ),
                                      if (e['correctionBlockedReason'] != null)
                                        Text(
                                          e['correctionBlockedReason']
                                              .toString(),
                                        ),
                                      if (group.$1 != 'accruals' &&
                                          e['reversalOfId'] == null &&
                                          (_retained.contains(e['id']) ||
                                              e['canReverse'] == true &&
                                                  e['reversedById'] == null))
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                _correct(p, group.$1, e),
                                            icon: const Icon(Icons.undo),
                                            label: Text(
                                              _retained.contains(e['id'])
                                                  ? 'იგივე მოთხოვნის გამეორება'
                                                  : 'ჩანაწერის კორექტირება',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
