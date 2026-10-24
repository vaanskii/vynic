import '../widgets/manager_design_components.dart';
import '../../theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_modal.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_data_status.dart';
import 'package:vynic/core/models/sale_visibility.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'finance_planning_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/expense_category.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';

final NumberFormat _money = NumberFormat('#,##0.00', 'en_US');
String _gel(num v) => '₾${_money.format(v)}';

class FinancialsScreen extends StatefulWidget {
  final User user;
  final Future<Map<String, dynamic>> Function()? loadData;
  final Future<Map<String, dynamic>> Function(String id)? loadSale;
  final Future<Map<String, dynamic>> Function(
    String from,
    String to,
    String cursor,
  )?
  loadSalesPage;
  const FinancialsScreen({
    super.key,
    required this.user,
    this.loadData,
    this.loadSale,
    this.loadSalesPage,
  });

  @override
  State<FinancialsScreen> createState() => _FinancialsScreenState();
}

class _FinancialsScreenState extends State<FinancialsScreen> {
  Map<String, ManagerReadStatus> _displayReads = {};
  void _readFailed(Object error, String key) {
    final previous = _displayReads[key];
    final failure = error is ManagerReadFailure
        ? error.status
        : ManagerReadStatus(key: key, error: 'მონაცემები ვერ განახლდა.');
    if (failure.accessDenied) {
      if (widget.loadData == null) {
        MobileApiService.releaseReadStatuses(_displayReads.values);
      }
      _data = null;
      _salesCursor = null;
      _displayReads = {key: failure};
      return;
    }
    _displayReads = {
      ..._displayReads,
      'failure@$key@${failure.query}': failure,
      key: previous?.fetchedAt == null
          ? failure
          : previous!.failed(
              failure.error ?? 'მონაცემები ვერ განახლდა.',
              location: 'memory',
            ),
    };
  }

  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  bool _isAddingExpense = false;
  bool _isLoadingMoreSales = false;
  String? _salesCursor;
  String? _salesFrom, _salesTo;
  int _loadGeneration = 0;

  final _expenseComposerKey = GlobalKey();

  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _expenseDescriptionController =
      TextEditingController();
  final TextEditingController _expenseAmountController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFinancials();
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _expenseDescriptionController.dispose();
    _expenseAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadFinancials() async {
    final generation = ++_loadGeneration;
    _isLoadingMoreSales = false;
    String? scope;
    bool current() =>
        mounted &&
        generation == _loadGeneration &&
        (scope == null || MobileApiService.isCurrentTableRepairScope(scope));
    try {
      if (widget.loadData != null) {
        final data = await widget.loadData!();
        if (current()) {
          setState(() {
            _data = data;
            _salesCursor = data['nextCursor']?.toString();
            _salesFrom = data['saleHistoryFrom']?.toString();
            _salesTo = data['saleHistoryTo']?.toString();
            _isLoading = false;
            _error = null;
          });
        }
        return;
      }
      scope = MobileApiService.tableRepairScope;
      final data = await MobileApiService.getFinancials();
      final procurement = data['procurement'];
      final day =
          (data['businessDate'] ??
                  (procurement is Map ? procurement['businessDate'] : null))
              ?.toString();
      if (day == null)
        throw ManagerReadFailure(
          const ManagerReadStatus(
            key: 'financials',
            error: 'ანგარიშის საქმიანი დღე მიუწვდომელია. სცადეთ განახლება.',
          ),
        );
      final summary = await MobileApiService.getFinancialSummary(
        from: day,
        to: day,
      );
      final from = summary['from']?.toString();
      final to = summary['to']?.toString();
      if (from == null || to == null)
        throw ManagerReadFailure(
          const ManagerReadStatus(
            key: 'ledger_summary',
            error: 'ანგარიშის პერიოდი მიუწვდომელია. სცადეთ განახლება.',
          ),
        );
      final results = await Future.wait([
        Future.value(summary),
        MobileApiService.getSales(from: from, to: to),
        MobileApiService.getProductAnalytics(from: from, to: to),
        MobileApiService.getSaleStaffAnalytics(from: from, to: to),
      ]);
      data['ledgerSummary'] = results[0];
      data['sales'] = results[1]['sales'] ?? const [];
      data['saleHistoryProvenance'] = results[1]['provenance'];
      data['saleHistoryWarning'] = results[1]['warning'];
      data['products'] = results[2]['byRevenue'] ?? const [];
      data['saleStaff'] = results[3]['staff'] ?? const [];
      if (current()) {
        setState(() {
          MobileApiService.releaseReadStatuses(_displayReads.values);
          _displayReads = {
            'financials': MobileApiService.statusFor(data)!,
            for (final entry in [
              'ledger_summary',
              'sale_history',
              'product_analytics',
              'sale_staff',
            ].asMap().entries)
              entry.value: MobileApiService.statusFor(results[entry.key])!,
          };
          _data = data;
          _salesCursor = results[1]['nextCursor']?.toString();
          _salesFrom = results[1]['from']?.toString();
          _salesTo = results[1]['to']?.toString();
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (current()) {
        setState(() {
          if (e is ManagerReadFailure)
            _readFailed(e, e.status.key);
          else
            _readFailed(e, 'financials');
          _isLoading = false;
          _error = _data == null ? 'სერვერთან კავშირი ვერ დამყარდა' : null;
        });
      }
    }
  }

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : <Map<String, dynamic>>[];

  Future<void> _loadMoreSales() async {
    final cursor = _salesCursor;
    if (cursor == null || _isLoadingMoreSales) return;
    final generation = _loadGeneration;
    final scope = widget.loadSalesPage == null
        ? MobileApiService.tableRepairScope
        : null;
    bool current() =>
        mounted &&
        generation == _loadGeneration &&
        (scope == null || MobileApiService.isCurrentTableRepairScope(scope));
    setState(() => _isLoadingMoreSales = true);
    try {
      final from = _salesFrom, to = _salesTo;
      if (from == null || to == null)
        throw StateError(
          'Refresh the reporting range before loading another page',
        );
      final page = widget.loadSalesPage != null
          ? await widget.loadSalesPage!(from, to, cursor)
          : await MobileApiService.getSales(from: from, to: to, cursor: cursor);
      if (!current()) return;
      if (page['from'] != from || page['to'] != to)
        throw StateError('Sale page reporting range changed');
      setState(() {
        final current = _maps(_data?['sales']);
        final ids = current.map((sale) => sale['id']).toSet();
        current.addAll(
          _maps(page['sales']).where((sale) => ids.add(sale['id'])),
        );
        _data?['sales'] = current;
        if (_data?['saleHistoryProvenance'] != 'PARTIAL' ||
            page['provenance'] == 'PARTIAL') {
          _data?['saleHistoryProvenance'] = page['provenance'];
          _data?['saleHistoryWarning'] = page['warning'];
        }
        final status = MobileApiService.statusFor(page);
        if (status != null) _displayReads['sale_history@$cursor'] = status;
        _salesCursor = page['nextCursor']?.toString();
      });
    } catch (error) {
      if (!current()) return;
      setState(() => _readFailed(error, 'sale_history'));
      _toast('გაყიდვების შემდეგი გვერდი ვერ ჩაიტვირთა', error: true);
    } finally {
      if (current()) setState(() => _isLoadingMoreSales = false);
    }
  }

  Future<void> _openSale(String id) async {
    try {
      final sale = widget.loadSale != null
          ? await widget.loadSale!(id)
          : await MobileApiService.getSale(id);
      if (!mounted) return;
      await showManagerModal<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SaleDetailSheet(sale: sale),
      );
    } catch (_) {
      _toast('გაყიდვის დეტალები ვერ ჩაიტვირთა', error: true);
    }
  }

  List<Map<String, dynamic>> get _expenseEntries {
    final list = _data?['expenseEntries'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  List<Map<String, dynamic>> get _expenseBreakdown {
    final raw = _data?['expenseBreakdown'];
    final rows = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) rows.add(Map<String, dynamic>.from(e));
      }
    }
    rows.sort(
      (a, b) =>
          ((b['amount'] ?? 0) as num).compareTo((a['amount'] ?? 0) as num),
    );
    return rows;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ManagerToast.showSnackBar(context, msg, isError: error);
  }

  Future<void> _addExpense() async {
    final category = _categoryController.text.trim();
    if (ExpenseCategory.isProcurement(category)) {
      _toast('შესყიდვა დაამატეთ მარაგებში — დღიური მიღება', error: true);
      return;
    }
    if (ExpenseCategory.isSalary(category)) {
      _toast('ხელფასი დაამატეთ ფინანსებში — ხელფასები', error: true);
      return;
    }
    final description = _expenseDescriptionController.text.trim();
    final amount = double.tryParse(_expenseAmountController.text.trim());
    if (category.isEmpty ||
        description.isEmpty ||
        amount == null ||
        amount <= 0) {
      _toast('შეავსეთ კატეგორია, აღწერა და სწორი თანხა', error: true);
      return;
    }
    setState(() => _isAddingExpense = true);
    try {
      await MobileApiService.createExpense(
        description: description,
        amount: amount,
        category: category,
      );
      _expenseDescriptionController.clear();
      _expenseAmountController.clear();
      await _loadFinancials();
      _toast('ხარჯი დაემატა');
    } catch (_) {
      _toast('ხარჯის დამატება ვერ მოხერხდა', error: true);
    } finally {
      if (mounted) setState(() => _isAddingExpense = false);
    }
  }

  Future<void> _deleteExpense(String id) async {
    try {
      await MobileApiService.deleteExpense(id);
      await _loadFinancials();
    } catch (_) {
      _toast('ხარჯის წაშლა ვერ მოხერხდა', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ManagerDataBoundary(
      reads: _displayReads,
      blocks: const {
        'financials',
        'ledger_summary',
        'sale_history',
        'product_analytics',
        'sale_staff',
      },
      onRefresh: _loadFinancials,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned(
              top: -100,
              right: -50,
              child: _GlowOrb(color: Color(0xFF0EA5E9), size: 300),
            ),
            Positioned(
              top: 300,
              left: -100,
              child: _GlowOrb(color: Color(0xFF2563EB), size: 250),
            ),
            SafeArea(
              bottom: false,
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: MobileGlassTheme.primary,
                      ),
                    )
                  : _error != null
                  ? _buildError()
                  : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.wifi_off_rounded,
          size: 56,
          color: MobileGlassTheme.textSecondary,
        ),
        SizedBox(height: 14),
        Text(
          _error!,
          style: TextStyle(
            color: MobileGlassTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextButton.icon(
          onPressed: _loadFinancials,
          icon: Icon(Icons.refresh_rounded, color: MobileGlassTheme.accentText),
          label: Text(
            'თავიდან ცდა',
            style: TextStyle(color: MobileGlassTheme.accentText),
          ),
        ),
      ],
    ),
  );

  Widget _buildContent() {
    final ledger = _data!['ledgerSummary'] is Map
        ? Map<String, dynamic>.from(_data!['ledgerSummary'] as Map)
        : <String, dynamic>{};
    final double revenue = ledger.isNotEmpty
        ? _number(ledger['revenue'])
        : _number(_data!['revenue']);
    final double expenses = _number(
      _data!['totalOutflows'] ?? _data!['expenses'],
    );
    final double profit = revenue - expenses;
    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in children.indexed) ...[
          if (entry.$1 > 0) const SizedBox(height: 20),
          entry.$2,
        ],
      ],
    );
    return RefreshIndicator(
      color: MobileGlassTheme.primary,
      onRefresh: _loadFinancials,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1424),
                child: Padding(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 700 ? 20 : 32,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final summary = _buildBalanceCard(
                        revenue,
                        expenses,
                        profit,
                      );
                      return column([
                        _buildHeader(),
                        if (ledger['warning'] != null)
                          _buildHistoryNotice(ledger['warning'].toString()),
                        summary,
                        if (constraints.maxWidth > 850)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildLedgerPaymentCard(ledger)),
                              const SizedBox(width: 22),
                              Expanded(child: _buildExpenseBreakdownCard()),
                            ],
                          )
                        else ...[
                          _buildLedgerPaymentCard(ledger),
                          _buildExpenseBreakdownCard(),
                        ],
                        _buildSalesHistory(),
                        _buildPlanningLinks(),
                        Container(
                          key: _expenseComposerKey,
                          child: _buildExpenseComposer(),
                        ),
                        _buildExpenseLog(),
                        _buildLifecycleActivity(ledger),
                        if (ManagerEntitlements.has(FeatureKeys.inventory))
                          _buildProcurement(),
                        if (constraints.maxWidth >= 940)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildProductAnalytics()),
                              const SizedBox(width: 20),
                              Expanded(child: _buildStaffAnalytics()),
                            ],
                          )
                        else ...[
                          _buildProductAnalytics(),
                          _buildStaffAnalytics(),
                        ],
                      ]);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────
  Widget _buildHeader() => LayoutBuilder(
    builder: (context, constraints) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ფინანსები',
            style: TextStyle(
              color: MobileGlassTheme.textPrimary,
              fontSize: constraints.maxWidth < 700 ? 25 : 30,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'შემოსავალი, გასავლები და აღრიცხვა',
            style: TextStyle(
              color: MobileGlassTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      );
      final actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          IconButton.outlined(
            onPressed: _loadFinancials,
            tooltip: 'განახლება',
            icon: const Icon(Icons.refresh, size: 18),
          ),
          FilledButton.icon(
            onPressed: () {
              final target = _expenseComposerKey.currentContext;
              if (target != null)
                Scrollable.ensureVisible(
                  target,
                  duration: const Duration(milliseconds: 250),
                  alignment: .1,
                );
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('ხარჯის დამატება'),
          ),
        ],
      );
      return constraints.maxWidth >= 850
          ? Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                actions,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 18), actions],
            );
    },
  );

  // ── Balance + income/expense composition chart ────────────────────────
  Widget _buildBalanceCard(
    double revenue,
    double expenses,
    double profit,
  ) => LayoutBuilder(
    builder: (context, box) {
      final small = box.maxWidth < 650;
      final t = managerThemeOf(context);
      Widget metric(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: managerDesignText(context, 11, muted: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: managerDesignText(context, 20, weight: FontWeight.w500),
          ),
        ],
      );
      final expenseFraction = revenue <= 0
          ? (expenses > 0 ? 1.0 : 0.0)
          : (expenses / revenue).clamp(0.0, 1.0);
      return ManagerPanel(
        padding: small ? 20 : 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'აღრიცხული ნაშთი',
              style: managerDesignText(context, 12, muted: true),
            ),
            const SizedBox(height: 9),
            Text(
              _data?['differenceExact'] != null
                  ? '${_data!['differenceExact']} ₾'
                  : _gel(profit),
              style: managerDesignText(
                context,
                small ? 34 : 42,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'გაყიდვები − აღრიცხული გასავლები',
              style: managerDesignText(context, 11, muted: true),
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: metric(
                    'გაყიდვები',
                    _data?['revenueExact'] != null
                        ? '${_data!['revenueExact']} ₾'
                        : _gel(revenue),
                    t.primary,
                  ),
                ),
                Container(width: 1, height: 50, color: t.cardBorder),
                const SizedBox(width: 24),
                Expanded(
                  child: metric(
                    'გასავლები',
                    _data?['totalOutflows'] != null
                        ? '${_data!['totalOutflows']} ₾'
                        : _gel(expenses),
                    t.warn,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  if (expenseFraction < 1)
                    Expanded(
                      flex: ((1 - expenseFraction) * 10000).round().clamp(
                        1,
                        10000,
                      ),
                      child: Container(height: 9, color: t.primary),
                    ),
                  if (expenseFraction > 0)
                    Expanded(
                      flex: (expenseFraction * 10000).round().clamp(1, 10000),
                      child: Container(
                        height: 9,
                        color: t.isDark
                            ? t.warn.withValues(alpha: .45)
                            : const Color(0xFFE5D7BF),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'სხვაობა არ არის რეალიზებული მოგება ან სრული ფულადი ნაკადი. გაყიდვები შეიცავს გამოყენებულ ავანსს; გასავლები მოიცავს აღრიცხულ ხარჯებსა და მომწოდებლის, ხელფასის და ვალდებულების გადახდებს.',
              key: const Key('financial-metric-definition'),
              style: managerDesignText(context, 10, muted: true),
            ),
          ],
        ),
      );
    },
  );

  Widget _buildHistoryNotice(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
    child: _GlassCard(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: MobileGlassTheme.warn,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: MobileGlassTheme.textSecondary,
                height: 1.35,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildLedgerPaymentCard(Map<String, dynamic> ledger) => ManagerPanel(
    padding: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ManagerSectionHeading('დახურვებზე მიღებული თანხა'),
        for (final row in [
          ('ნაღდი', 'cashCollected'),
          ('ბარათი · TBC', 'tbcCollected'),
          ('ბარათი · BOG', 'bogCollected'),
          ('ძველი ბარათი', 'legacyCardCollected'),
          ('გამოყენებული ავანსი', 'advanceApplied'),
        ])
          ManagerKeyValue(
            row.$1,
            ledger[row.$2] == null ? '—' : _gel(_number(ledger[row.$2])),
          ),
        const SizedBox(height: 8),
        Text(
          'გამოყენებული ავანსი: ${ledger['advanceApplied'] ?? '—'} ₾ · წინასწარ მიღებული თანხაა და ამ დახურვებზე მიღებულ თანხაში არ შედის.',
          key: const Key('financial-advance-definition'),
          style: managerDesignText(context, 10, muted: true),
        ),
      ],
    ),
  );

  Widget _buildSalesHistory() {
    final sales = _maps(_data?['sales'])
        .where(
          (sale) => SaleVisibility.visible(
            sale,
            nonFiscalEnabled: ManagerEntitlements.has(
              FeatureKeys.nonFiscalClose,
            ),
          ),
        )
        .toList();
    return ManagerPanel(
      padding: MediaQuery.sizeOf(context).width < 700 ? 18 : 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ManagerSectionHeading('გაყიდვების ისტორია'),
          if (_data?['saleHistoryWarning'] != null &&
              _data?['saleHistoryWarning'] !=
                  (_data?['ledgerSummary'] as Map?)?['warning'])
            _buildHistoryNotice(_data!['saleHistoryWarning'].toString()),
          if (MediaQuery.sizeOf(context).width > 900)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'შეკვეთა / დრო',
                      style: managerDesignText(context, 10, muted: true),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'გადახდა',
                      style: managerDesignText(context, 10, muted: true),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'სტატუსი',
                      style: managerDesignText(context, 10, muted: true),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'თანხა',
                      textAlign: TextAlign.right,
                      style: managerDesignText(context, 10, muted: true),
                    ),
                  ),
                  const SizedBox(width: 28),
                ],
              ),
            ),
          if (sales.isEmpty)
            Text(
              'ამ პერიოდში დეტალური გაყიდვები არ არის',
              style: managerDesignText(context, 12, muted: true),
            ),
          for (final sale in sales) ...[
            const Divider(height: 1),
            _saleRow(sale),
          ],
          if (_salesCursor != null)
            TextButton(
              onPressed: _isLoadingMoreSales ? null : _loadMoreSales,
              child: Text(_isLoadingMoreSales ? 'იტვირთება…' : 'მეტის ნახვა'),
            ),
        ],
      ),
    );
  }

  Widget _saleRow(Map<String, dynamic> sale) {
    final closedAt = DateTime.tryParse(sale['closedAt']?.toString() ?? '');
    final time = closedAt == null
        ? '—'
        : DateFormat('HH:mm').format(closedAt.toLocal());
    final status = sale['isCancelled'] == true
        ? 'გაუქმებული'
        : sale['restoredToOrder'] == true
        ? 'აღდგენილი'
        : sale['isFiscal'] == false
        ? 'შიდა დახურვა'
        : (ManagerEntitlements.has(FeatureKeys.nonFiscalClose)
              ? 'ფისკალური'
              : 'გაყიდვა');
    final payment =
        const {
          'cash': 'ნაღდი',
          'card-tbc': 'ბარათი · TBC',
          'card-bog': 'ბარათი · BOG',
          'card': 'ბარათი',
          'mixed': 'შერეული',
          'advance': 'ავანსი',
        }[sale['paymentMethod']] ??
        '${sale['paymentMethod'] ?? '—'}';
    final wide = MediaQuery.sizeOf(context).width > 900;
    return InkWell(
      key: ValueKey('sale-${sale['id']}'),
      onTap: () => _openSale(sale['id'].toString()),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${sale['posOrderId']}',
                    style: managerDesignText(
                      context,
                      13,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    wide ? time : '$time · $payment',
                    style: managerDesignText(context, 10, muted: true),
                  ),
                  if (!wide)
                    Text(
                      status,
                      style: managerDesignText(context, 10, muted: true),
                    ),
                ],
              ),
            ),
            if (wide) ...[
              Expanded(
                child: Text(payment, style: managerDesignText(context, 12)),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color:
                          ((status == 'ფისკალური' || status == 'გაყიდვა')
                                  ? MobileGlassTheme.good
                                  : MobileGlassTheme.warn)
                              .withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      style: managerDesignText(context, 11).copyWith(
                        color: (status == 'ფისკალური' || status == 'გაყიდვა')
                            ? MobileGlassTheme.good
                            : MobileGlassTheme.warn,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            Expanded(
              child: Text(
                _gel(_number(sale['gross'])),
                textAlign: TextAlign.right,
                style: managerDesignText(context, 13, weight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: MobileGlassTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductAnalytics() => _buildRankedSection(
    title: 'ტოპ პროდუქტები',
    rows: _maps(_data?['products']).take(5).toList(),
    label: (row) => [
      row['name'],
      if ((row['variantName']?.toString() ?? '').isNotEmpty) row['variantName'],
    ].join(' · '),
    value: (row) => '${row['quantity']} ×  ${_gel(_number(row['revenue']))}',
    empty: 'პროდუქტის მონაცემები ჯერ არ არის',
  );

  Widget _buildStaffAnalytics() => _buildRankedSection(
    title: 'დამხურავი ოპერატორები',
    rows: _maps(_data?['saleStaff']).take(5).toList(),
    label: (row) => row['staffName']?.toString() ?? 'უცნობი / სისტემა',
    value: (row) =>
        '${row['saleCount']} გაყიდვა · ${_gel(_number(row['revenue']))} · საშუალო ${_gel(_number(row['averageSale']))}',
    empty: 'დახურვის ოპერატორის მონაცემები ჯერ არ არის',
  );

  Widget _buildRankedSection({
    required String title,
    required List<Map<String, dynamic>> rows,
    required String Function(Map<String, dynamic>) label,
    required String Function(Map<String, dynamic>) value,
    required String empty,
  }) => Padding(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title),
        const SizedBox(height: 16),
        _GlassCard(
          borderRadius: BorderRadius.circular(24),
          padding: const EdgeInsets.all(18),
          child: rows.isEmpty
              ? Text(
                  empty,
                  style: TextStyle(color: MobileGlassTheme.textSecondary),
                )
              : Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const Divider(height: 22),
                      Row(
                        children: [
                          Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: MobileGlassTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label(rows[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: MobileGlassTheme.textPrimary,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              value(rows[i]),
                              maxLines: 2,
                              textAlign: TextAlign.end,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: MobileGlassTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    ),
  );

  Widget _buildLifecycleActivity(Map<String, dynamic> ledger) {
    final entries = [
      ('გაუქმებული', (ledger['voidedCount'] as num?)?.toInt() ?? 0),
      ('აღდგენილი', (ledger['restoredCount'] as num?)?.toInt() ?? 0),
      if (ManagerEntitlements.has(FeatureKeys.nonFiscalClose))
        ('შიდა დახურვა', (ledger['internalCount'] as num?)?.toInt() ?? 0),
    ];
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'გაუქმება და აღდგენა'),
          const SizedBox(height: 16),
          _GlassCard(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${entries[i].$2}',
                          style: TextStyle(
                            color: MobileGlassTheme.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          entries[i].$1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: MobileGlassTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Payment type chart (cash vs card) ─────────────────────────────────
  Widget _buildExpenseBreakdownCard() {
    final procurement = _data?['procurement'] as Map?;
    final supplierPayments = procurement?['supplierPayments'] as Map?;
    final dayPayments = supplierPayments?['businessDay'] as Map?;
    return ManagerPanel(
      padding: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ManagerSectionHeading(
            'გასავლების კატეგორიები',
            action: 'ისტორია',
            onAction: () => showDialog<void>(
              context: context,
              builder: (_) => ManagerFormDialog(
                title: const Text('დღის ხარჯების ისტორია'),
                content: _buildExpenseLog(),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('დახურვა'),
                  ),
                ],
              ),
            ),
          ),
          for (final row in [
            ('მომწოდებლები', dayPayments?['total']),
            ('ხელფასის გადახდები', _data?['salaryPayments']),
            ('ვალდებულებები', _data?['obligationPayments']),
            ('სხვა ხარჯი', _data?['otherExpenses'] ?? _data?['expenses']),
          ])
            ManagerKeyValue(row.$1, row.$2 == null ? '—' : '${row.$2} ₾'),
          const SizedBox(height: 8),
          Text(
            'მხოლოდ შესრულებული გადახდები.',
            style: managerDesignText(context, 10, muted: true),
          ),
          if (_expenseBreakdown.isNotEmpty)
            ExpansionTile(
              key: const PageStorageKey<String>('financial-expense-categories'),
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                'ხარჯების დეტალური კატეგორიები',
                style: managerDesignText(context, 12, muted: true),
              ),
              children: [
                for (final row in _expenseBreakdown)
                  ManagerKeyValue(
                    '${row['category'] ?? 'სხვა'}',
                    _gel(_number(row['amount'])),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildProcurement() {
    final procurement = _data?['procurement'] as Map?;
    return Padding(
      padding: EdgeInsets.zero,
      child: _GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(title: 'შესყიდვები'),
            if (procurement == null)
              const Text('შესყიდვების მონაცემები მიუწვდომელია'),
            if (procurement != null) ...[
              for (final entry in [
                ('calendarDay', 'დღევანდელი შესყიდვები'),
                ('businessDay', 'სამუშაო დღის შესყიდვები'),
                ('calendarMonth', 'ამ თვის შესყიდვები'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    children: [
                      Text(entry.$2),
                      Text('${(procurement[entry.$1] as Map)['total']} ₾'),
                    ],
                  ),
                ),
              Text(
                'სამუშაო დღე: ${procurement['businessDate']} · თვე: ${procurement['month']}',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('financials-receiving'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => InventoryScreen(
                      section: 2,
                      businessDate: procurement['businessDate'] as String?,
                    ),
                  ),
                ),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('დღიური მიღება'),
              ),
            ],
            Text(
              'მომწოდებლებს დღეს გადახდილი: ${((procurement?['supplierPayments'] as Map?)?['calendarDay'] as Map?)?['total'] ?? '—'} ₾',
            ),
            Text(
              'მომწოდებლის დავალიანება: ${procurement?['outstanding'] ?? '—'} ₾',
            ),
            Text(
              'შესამოწმებელი ძველი ნაშთი: ${procurement?['unverified'] ?? '—'} ₾',
            ),
            const Divider(height: 32),
            Text(
              'სხვა ხარჯები: ${_data?['otherExpenses'] ?? _data?['expenses'] ?? '—'} ₾',
            ),
            Text('ხელფასები: ${_data?['salaryPayments'] ?? '—'} ₾'),
            if (_data?['legacySalaryPayments'] != null)
              Text(
                'მათ შორის ძველი ჩანაწერები: ${_data!['legacySalaryPayments']} ₾',
              ),
            Text(
              'ვალდებულებების გადახდები: ${_data?['obligationPayments'] ?? '—'} ₾',
            ),
            Text('სულ გასავლები: ${_data?['totalOutflows'] ?? '—'} ₾'),
            const SizedBox(height: 8),
            const Text('გასავლებში შედის მომწოდებელთან გადახდილი თანხა.'),
          ],
        ),
      ),
    );
  }

  // ── Add-expense composer ──────────────────────────────────────────────
  Widget _buildExpenseComposer() {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'სხვა ხარჯის დამატება'),
          SizedBox(height: 16),
          _GlassCard(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _darkField(_categoryController, 'კატეგორია (მაგ: ტრანსპორტი)'),
                SizedBox(height: 12),
                _darkField(_expenseDescriptionController, 'აღწერა'),
                SizedBox(height: 12),
                _darkField(_expenseAmountController, 'თანხა', number: true),
                SizedBox(height: 16),
                _primaryButton(
                  label: _isAddingExpense ? 'ემატება...' : 'ხარჯის დამატება',
                  onTap: _isAddingExpense ? null : _addExpense,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanningLinks() => Padding(
    padding: EdgeInsets.zero,
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final entry in [
          if (ManagerEntitlements.has(FeatureKeys.payroll))
            (false, 'ხელფასები', Icons.people_outline),
          if (ManagerEntitlements.has(FeatureKeys.financialPlanning))
            (true, 'ყოველთვიური ვალდებულებები', Icons.event_repeat),
        ])
          OutlinedButton.icon(
            key: ValueKey(
              entry.$1 ? 'financials-obligations' : 'financials-payroll',
            ),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () async {
              await showManagerFinancePlanning(context, obligations: entry.$1);
              if (mounted) await _loadFinancials();
            },
            icon: Icon(entry.$3),
            label: Text(entry.$2),
          ),
      ],
    ),
  );

  // ── Expense history ───────────────────────────────────────────────────
  Widget _buildExpenseLog() {
    final entries = _expenseEntries;
    final fmt = DateFormat('dd MMM, HH:mm');
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'დღის ხარჯების ისტორია'),
          SizedBox(height: 16),
          _GlassCard(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(8),
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'დღეს ხარჯები არ არის',
                      style: TextStyle(color: MobileGlassTheme.textSecondary),
                    ),
                  )
                : Column(
                    children: [
                      for (final e in entries) _buildExpenseLogRow(e, fmt),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseLogRow(Map<String, dynamic> e, DateFormat fmt) {
    final createdAtRaw = e['createdAt']?.toString();
    DateTime? createdAt;
    if (createdAtRaw != null) {
      createdAt = DateTime.tryParse(createdAtRaw)?.toLocal();
    }
    final amount = (e['amount'] ?? 0);
    final double amt = amount is num
        ? amount.toDouble()
        : double.tryParse('$amount') ?? 0;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MobileGlassTheme.bad.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              color: MobileGlassTheme.bad,
              size: 20,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e['category'] ?? 'სხვა'} • ${e['description'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MobileGlassTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (createdAt != null)
                  Text(
                    fmt.format(createdAt),
                    style: TextStyle(
                      color: MobileGlassTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Text(
            '-${_gel(amt)}',
            style: TextStyle(
              color: MobileGlassTheme.bad,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (e['canDelete'] == true &&
              !ExpenseCategory.isSalary(e['category']))
            GestureDetector(
              key: ValueKey('expense-delete-${e['id']}'),
              onTap: () => _deleteExpense((e['id'] ?? '').toString()),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: MobileGlassTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Shared form widgets ───────────────────────────────────────────────
  Widget _darkField(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      style: TextStyle(color: MobileGlassTheme.textPrimary, fontSize: 15),
      cursorColor: MobileGlassTheme.primary,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: MobileGlassTheme.textSecondary,
          fontSize: 13,
        ),
        filled: true,
        fillColor: MobileGlassTheme.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MobileGlassTheme.data.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MobileGlassTheme.primary),
        ),
      ),
    );
  }

  Widget _primaryButton({required String label, VoidCallback? onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: MobileGlassTheme.primary,
          foregroundColor: MobileGlassTheme.onPrimary,
          disabledBackgroundColor: MobileGlassTheme.primary.withValues(
            alpha: 0.4,
          ),
          disabledForegroundColor: MobileGlassTheme.textSecondary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _SaleDetailSheet extends StatelessWidget {
  const _SaleDetailSheet({required this.sale});

  final Map<String, dynamic> sale;

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : <Map<String, dynamic>>[];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<String>>(
    valueListenable: ManagerEntitlements.features,
    builder: (context, _, child) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    if (!SaleVisibility.visible(
      sale,
      nonFiscalEnabled: ManagerEntitlements.has(FeatureKeys.nonFiscalClose),
    )) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('ჩანაწერი მიუწვდომელია')),
      );
    }
    final lines = _maps(sale['lines']);
    final payments = _maps(sale['payments']);
    final audit = sale['auditLink'] is Map
        ? Map<String, dynamic>.from(sale['auditLink'] as Map)
        : null;
    final state = sale['isCancelled'] == true
        ? 'VOIDED'
        : sale['restoredToOrder'] == true
        ? 'RESTORED'
        : sale['isFiscal'] == false
        ? 'INTERNAL'
        : (ManagerEntitlements.has(FeatureKeys.nonFiscalClose)
              ? 'FISCAL'
              : 'SALE');
    return DraggableScrollableSheet(
      initialChildSize: 0.84,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: MobileGlassTheme.data.scaffoldBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 36),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: MobileGlassTheme.border(0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order #${sale['posOrderId']}',
                    style: TextStyle(
                      color: MobileGlassTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  state,
                  style: TextStyle(
                    color: (state == 'FISCAL' || state == 'SALE')
                        ? MobileGlassTheme.good
                        : MobileGlassTheme.warn,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${sale['businessDate']} · ${sale['floor']} · ${(sale['tableNumbers'] as List?)?.join(', ') ?? '—'}',
              style: TextStyle(color: MobileGlassTheme.textSecondary),
            ),
            const SizedBox(height: 22),
            _detailCard(
              children: [
                _detailRow('Closed at', sale['closedAt']?.toString() ?? '—'),
                _detailRow('Gross', _gel(_number(sale['gross']))),
                _detailRow('Advance', _gel(_number(sale['advanceApplied']))),
                _detailRow('Amount due', _gel(_number(sale['amountDueNow']))),
                _detailRow(
                  'Collected now',
                  _gel(_number(sale['collectedNow'])),
                ),
                _detailRow(
                  'Staff',
                  sale['closedById']?.toString() ?? 'Unknown / system',
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Items',
              style: TextStyle(
                color: MobileGlassTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _detailCard(
              children: lines.isEmpty
                  ? [
                      Text(
                        'No frozen line detail',
                        style: TextStyle(color: MobileGlassTheme.textSecondary),
                      ),
                    ]
                  : [
                      for (final line in lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '${line['quantity']} × ${line['itemName']}'
                                  '${(line['variantName']?.toString() ?? '').isEmpty ? '' : ' · ${line['variantName']}'}',
                                  style: TextStyle(
                                    color: MobileGlassTheme.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '${_gel(_number(line['unitPrice']))}  ${_gel(_number(line['lineTotal']))}',
                                style: TextStyle(
                                  color: MobileGlassTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
            ),
            const SizedBox(height: 18),
            Text(
              'Payments',
              style: TextStyle(
                color: MobileGlassTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _detailCard(
              children: [
                for (final payment in payments)
                  _detailRow(
                    payment['method']?.toString() ?? 'other',
                    _gel(_number(payment['amount'])),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _detailCard(
              children: [
                _detailRow('Sale ID', sale['posSaleId']?.toString() ?? '—'),
                _detailRow('Closure ID', sale['closureId']?.toString() ?? '—'),
                _detailRow(
                  'Audit report',
                  audit?['reportId']?.toString() ?? 'Unavailable',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailCard({required List<Widget> children}) => _GlassCard(
    borderRadius: BorderRadius.circular(20),
    padding: const EdgeInsets.all(16),
    child: Column(children: children),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: MobileGlassTheme.textSecondary),
          ),
        ),
        Flexible(
          child: SelectableText(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: MobileGlassTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// ------------------------------------------------------------------
/// REUSABLE DARK "GLASS" WIDGETS
/// ------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: MobileGlassTheme.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding, this.borderRadius});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    final radius = borderRadius ?? BorderRadius.circular(18);
    return Material(
      color: theme.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: theme.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
