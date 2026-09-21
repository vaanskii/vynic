import 'package:vynic/core/models/sale_visibility.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'finance_planning_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/expense_category.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/mobile_glass_ui.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';

const List<Color> _kCatColors = [
  Color(0xFFF59E0B),
  Color(0xFF06B6D4),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF10B981),
  Color(0xFF3B82F6),
];

final NumberFormat _money = NumberFormat('#,##0.00', 'en_US');
String _gel(num v) => '₾${_money.format(v)}';

class FinancialsScreen extends StatefulWidget {
  final User user;
  final Future<Map<String, dynamic>> Function()? loadData;
  final Future<Map<String, dynamic>> Function(String id)? loadSale;
  const FinancialsScreen({
    super.key,
    required this.user,
    this.loadData,
    this.loadSale,
  });

  @override
  State<FinancialsScreen> createState() => _FinancialsScreenState();
}

class _FinancialsScreenState extends State<FinancialsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  bool _isAddingExpense = false;
  bool _isLoadingMoreSales = false;
  String? _salesCursor;

  late final AnimationController _animController;

  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _expenseDescriptionController =
      TextEditingController();
  final TextEditingController _expenseAmountController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _loadFinancials();
  }

  @override
  void dispose() {
    _animController.dispose();
    _categoryController.dispose();
    _expenseDescriptionController.dispose();
    _expenseAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadFinancials() async {
    try {
      if (widget.loadData != null) {
        final data = await widget.loadData!();
        if (mounted) {
          setState(() {
            _data = data;
            _salesCursor = data['nextCursor']?.toString();
            _isLoading = false;
            _error = null;
          });
          if (_animController.value == 0) _animController.forward();
        }
        return;
      }
      final data = await MobileApiService.getFinancials();
      final results = await Future.wait([
        MobileApiService.getFinancialSummary(),
        MobileApiService.getSales(),
        MobileApiService.getProductAnalytics(),
        MobileApiService.getSaleStaffAnalytics(),
      ]);
      data['ledgerSummary'] = results[0];
      data['sales'] = results[1]['sales'] ?? const [];
      data['saleHistoryProvenance'] = results[1]['provenance'];
      data['saleHistoryWarning'] = results[1]['warning'];
      data['products'] = results[2]['byRevenue'] ?? const [];
      data['saleStaff'] = results[3]['staff'] ?? const [];
      if (mounted) {
        setState(() {
          _data = data;
          _salesCursor = results[1]['nextCursor']?.toString();
          _isLoading = false;
          _error = null;
        });
        if (_animController.value == 0) _animController.forward();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'სერვერთან კავშირი ვერ დამყარდა';
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
    setState(() => _isLoadingMoreSales = true);
    try {
      final page = await MobileApiService.getSales(cursor: cursor);
      if (!mounted) return;
      setState(() {
        final current = _maps(_data?['sales']);
        current.addAll(_maps(page['sales']));
        _data?['sales'] = current;
        _salesCursor = page['nextCursor']?.toString();
      });
    } catch (_) {
      _toast('გაყიდვების შემდეგი გვერდი ვერ ჩაიტვირთა', error: true);
    } finally {
      if (mounted) setState(() => _isLoadingMoreSales = false);
    }
  }

  Future<void> _openSale(String id) async {
    try {
      final sale = widget.loadSale != null
          ? await widget.loadSale!(id)
          : await MobileApiService.getSale(id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
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
    return Scaffold(
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
    final double cash = (_data!['cashRevenue'] ?? 0).toDouble();
    final double card = (_data!['cardRevenue'] ?? 0).toDouble();

    return RefreshIndicator(
      color: MobileGlassTheme.primary,
      backgroundColor: MobileGlassTheme.data.surfaceCard,
      onRefresh: _loadFinancials,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fade(0.0, _buildHeader()),
                  if (ledger['warning'] != null)
                    _fade(
                      0.05,
                      _buildHistoryNotice(ledger['warning'].toString()),
                    ),
                  _fade(
                    0.1,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildBalanceCard(revenue, expenses, profit),
                    ),
                  ),
                  SizedBox(height: 28),
                  if (ManagerEntitlements.has(FeatureKeys.inventory))
                    _buildProcurement(),
                  const SizedBox(height: 16),
                  _buildPlanningLinks(),
                  const SizedBox(height: 24),
                  _fade(0.2, _buildPaymentCard(cash, card)),
                  SizedBox(height: 28),
                  _fade(0.25, _buildLedgerPaymentCard(ledger)),
                  SizedBox(height: 28),
                  _fade(0.3, _buildSalesHistory()),
                  SizedBox(height: 28),
                  _fade(0.35, _buildProductAnalytics()),
                  SizedBox(height: 28),
                  _fade(0.4, _buildStaffAnalytics()),
                  SizedBox(height: 28),
                  _fade(0.45, _buildLifecycleActivity(ledger)),
                  SizedBox(height: 28),
                  _fade(0.5, _buildExpenseBreakdownCard()),
                  SizedBox(height: 28),
                  _fade(0.6, _buildExpenseComposer()),
                  SizedBox(height: 28),

                  _fade(0.8, _buildExpenseLog()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fade(double delay, Widget child) =>
      _FadeInSlide(controller: _animController, delay: delay, child: child);

  // ── Header ────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'ფინანსები',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: MobileGlassTheme.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _GlassCard(
            onTap: _loadFinancials,
            borderRadius: BorderRadius.circular(20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.refresh_rounded,
                  color: MobileGlassTheme.textPrimary,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'განახლება',
                  style: TextStyle(
                    color: MobileGlassTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Balance + income/expense composition chart ────────────────────────
  Widget _buildBalanceCard(double revenue, double expenses, double profit) {
    final bool positive = profit >= 0;
    final double margin = revenue > 0 ? (profit / revenue * 100) : 0;
    // Composition of revenue: expense portion (red) + profit portion (green).
    final double base = revenue <= 0 ? 1 : revenue;
    final double expFrac = (expenses / base).clamp(0.0, 1.0);
    final double profFrac = (profit > 0 ? profit / base : 0.0).clamp(0.0, 1.0);

    return _GlassCard(
      borderRadius: BorderRadius.circular(28),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'გაყიდვები − გასავლები',
                      style: TextStyle(
                        color: MobileGlassTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _data?['differenceExact'] != null
                            ? '₾${_data!["differenceExact"]}'
                            : _gel(profit.abs()),
                        style: TextStyle(
                          color: MobileGlassTheme.textPrimary,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      (positive ? MobileGlassTheme.good : MobileGlassTheme.bad)
                          .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      positive
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      color: positive
                          ? MobileGlassTheme.good
                          : MobileGlassTheme.bad,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '${margin.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: positive
                            ? MobileGlassTheme.good
                            : MobileGlassTheme.bad,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _MiniStatBlock(
                  title: 'გაყიდვები',
                  amount: _data?['revenueExact'] != null
                      ? '₾${_data!["revenueExact"]}'
                      : _gel(revenue),
                  color: MobileGlassTheme.good,
                  icon: Icons.arrow_downward_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: MobileGlassTheme.border(0.15),
              ),
              Expanded(
                child: _MiniStatBlock(
                  title: 'ხარჯი',
                  amount: _data?['totalOutflows'] != null
                      ? '₾${_data!["totalOutflows"]}'
                      : _gel(expenses),
                  color: MobileGlassTheme.bad,
                  icon: Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          // Composition bar: how revenue splits into expense vs profit.
          Text(
            'შემოსავლის სტრუქტურა',
            style: TextStyle(
              color: MobileGlassTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  if (expFrac > 0)
                    Expanded(
                      flex: (expFrac * 1000).round().clamp(1, 1000),
                      child: Container(color: MobileGlassTheme.bad),
                    ),
                  if (profFrac > 0)
                    Expanded(
                      flex: (profFrac * 1000).round().clamp(1, 1000),
                      child: Container(color: MobileGlassTheme.good),
                    ),
                  if (expFrac + profFrac < 1)
                    Expanded(
                      flex: ((1 - expFrac - profFrac) * 1000).round().clamp(
                        1,
                        1000,
                      ),
                      child: Container(color: MobileGlassTheme.border(0.12)),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              _legendDot(MobileGlassTheme.bad, 'ხარჯი'),
              SizedBox(width: 16),
              _legendDot(MobileGlassTheme.good, 'სხვაობა'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: MobileGlassTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

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

  Widget _buildLedgerPaymentCard(Map<String, dynamic> ledger) {
    final rows = <(String, double, Color)>[
      ('TBC', _number(ledger['tbcCollected']), const Color(0xFF38BDF8)),
      ('BOG', _number(ledger['bogCollected']), const Color(0xFFF59E0B)),
      ('ავანსი', _number(ledger['advanceApplied']), const Color(0xFF8B5CF6)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'ბარათები და ავანსი'),
          const SizedBox(height: 16),
          _GlassCard(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 22),
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: rows[i].$3,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        rows[i].$1,
                        style: TextStyle(color: MobileGlassTheme.textPrimary),
                      ),
                      const Spacer(),
                      Text(
                        _gel(rows[i].$2),
                        style: TextStyle(
                          color: MobileGlassTheme.textPrimary,
                          fontWeight: FontWeight.w700,
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
  }

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'გაყიდვების ისტორია'),
          const SizedBox(height: 16),
          _GlassCard(
            borderRadius: BorderRadius.circular(24),
            padding: EdgeInsets.zero,
            child: sales.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      'ამ პერიოდში დეტალური გაყიდვები არ არის',
                      style: TextStyle(color: MobileGlassTheme.textSecondary),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < sales.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _saleRow(sales[i]),
                      ],
                    ],
                  ),
          ),
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
        ? 'VOIDED'
        : sale['restoredToOrder'] == true
        ? 'RESTORED'
        : sale['isFiscal'] == false
        ? 'INTERNAL'
        : null;
    return InkWell(
      key: ValueKey('sale-${sale['id']}'),
      onTap: () => _openSale(sale['id'].toString()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                time,
                style: TextStyle(color: MobileGlassTheme.textSecondary),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${sale['posOrderId']}',
                    style: TextStyle(
                      color: MobileGlassTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    status ?? (sale['paymentMethod'] ?? '—').toString(),
                    style: TextStyle(
                      color: status == null
                          ? MobileGlassTheme.textSecondary
                          : MobileGlassTheme.warn,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _gel(_number(sale['gross'])),
              style: TextStyle(
                color: MobileGlassTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
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
    title: 'თანამშრომლების შედეგები',
    rows: _maps(_data?['saleStaff']).take(5).toList(),
    label: (row) => row['staffName']?.toString() ?? 'უცნობი / სისტემა',
    value: (row) =>
        '${row['saleCount']} გაყიდვა · ${_gel(_number(row['revenue']))} · საშუალო ${_gel(_number(row['averageSale']))}',
    empty: 'სანდო თანამშრომლის ატრიბუცია ჯერ არ არის',
  );

  Widget _buildRankedSection({
    required String title,
    required List<Map<String, dynamic>> rows,
    required String Function(Map<String, dynamic>) label,
    required String Function(Map<String, dynamic>) value,
    required String empty,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
  Widget _buildPaymentCard(double cash, double card) {
    final double total = cash + card;
    final double cashFrac = total > 0 ? cash / total : 0.0;
    final double cardFrac = total > 0 ? card / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'გადახდების ტიპები'),
          SizedBox(height: 16),
          _GlassCard(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 18,
                    child: total <= 0
                        ? Container(color: MobileGlassTheme.border(0.12))
                        : Row(
                            children: [
                              if (cashFrac > 0)
                                Expanded(
                                  flex: (cashFrac * 1000).round().clamp(
                                    1,
                                    1000,
                                  ),
                                  child: Container(
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                              if (cardFrac > 0)
                                Expanded(
                                  flex: (cardFrac * 1000).round().clamp(
                                    1,
                                    1000,
                                  ),
                                  child: Container(
                                    color: const Color(0xFF38BDF8),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                SizedBox(height: 16),
                _payRow('ნაღდი', cash, total, const Color(0xFF2563EB)),
                SizedBox(height: 12),
                _payRow('ბარათი', card, total, const Color(0xFF38BDF8)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _payRow(String label, double amount, double total, Color color) {
    final pct = total > 0 ? (amount / total * 100) : 0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: MobileGlassTheme.textPrimary, fontSize: 14),
        ),
        SizedBox(width: 8),
        Text(
          '${pct.toStringAsFixed(0)}%',
          style: TextStyle(color: MobileGlassTheme.textSecondary, fontSize: 12),
        ),
        const Spacer(),
        Text(
          _gel(amount),
          style: TextStyle(
            color: MobileGlassTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // ── Expense category chart ────────────────────────────────────────────
  Widget _buildExpenseBreakdownCard() {
    final rows = _expenseBreakdown;
    final double maxAmount = rows.fold<double>(
      0,
      (m, e) => ((e['amount'] ?? 0) as num).toDouble() > m
          ? ((e['amount'] ?? 0) as num).toDouble()
          : m,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'ხარჯების კატეგორიები'),
          SizedBox(height: 16),
          _GlassCard(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(20),
            child: rows.isEmpty
                ? Text(
                    'კატეგორიები ცარიელია',
                    style: TextStyle(color: MobileGlassTheme.textSecondary),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) SizedBox(height: 16),
                        _CategoryBar(
                          label: (rows[i]['category'] ?? 'სხვა').toString(),
                          amount: ((rows[i]['amount'] ?? 0) as num).toDouble(),
                          maxAmount: maxAmount <= 0 ? 1 : maxAmount,
                          color: _kCatColors[i % _kCatColors.length],
                          formatted: _gel(
                            ((rows[i]['amount'] ?? 0) as num).toDouble(),
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

  Widget _buildProcurement() {
    final procurement = _data?['procurement'] as Map?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
    padding: const EdgeInsets.symmetric(horizontal: 24),
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
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => FinancePlanningScreen(obligations: entry.$1),
                ),
              );
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
          if (!ExpenseCategory.isSalary(e['category']))
            GestureDetector(
              onTap: () => _deleteExpense((e['id'] ?? '').toString()),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.35),
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
        fillColor: Colors.white.withValues(alpha: 0.05),
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
          foregroundColor: Colors.white,
          disabledBackgroundColor: MobileGlassTheme.primary.withValues(
            alpha: 0.4,
          ),
          disabledForegroundColor: Colors.white70,
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
  Widget build(BuildContext context) {
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
        : 'FISCAL';
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
                    color: state == 'FISCAL'
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

class _MiniStatBlock extends StatelessWidget {
  final String title;
  final String amount;
  final Color color;
  final IconData icon;

  const _MiniStatBlock({
    required this.title,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 12),
            ),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: MobileGlassTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            amount,
            style: TextStyle(
              color: MobileGlassTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String label;
  final double amount;
  final double maxAmount;
  final Color color;
  final String formatted;

  const _CategoryBar({
    required this.label,
    required this.amount,
    required this.maxAmount,
    required this.color,
    required this.formatted,
  });

  @override
  Widget build(BuildContext context) {
    final frac = (amount / maxAmount).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: MobileGlassTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              formatted,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Container(height: 9, color: Colors.white.withValues(alpha: 0.06)),
              FractionallySizedBox(
                widthFactor: frac == 0 ? 0.02 : frac,
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  const _GlassCard({
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    Widget card = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: radius,
            border: Border.all(
              color: MobileGlassTheme.data.borderSubtle,
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
    if (onTap != null) {
      card = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }
    return card;
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}

class _FadeInSlide extends StatelessWidget {
  final AnimationController controller;
  final Widget child;
  final double delay;

  const _FadeInSlide({
    required this.controller,
    required this.child,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(delay, 1.0, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 30 * (1 - animation.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
