import 'package:vynic/apps/mobile_app/widgets/mobile_glass_ui.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/widgets/manager_toast.dart';


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
  const FinancialsScreen({super.key, required this.user});

  @override
  State<FinancialsScreen> createState() => _FinancialsScreenState();
}

class _FinancialsScreenState extends State<FinancialsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  bool _isAddingExpense = false;
  bool _isApplyingSalaries = false;

  late final AnimationController _animController;

  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _expenseDescriptionController =
      TextEditingController();
  final TextEditingController _expenseAmountController = TextEditingController();
  final TextEditingController _staffNameController = TextEditingController();
  final TextEditingController _staffSalaryController = TextEditingController();

  final List<_SalaryItem> _salaryItems = [];

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
    _staffNameController.dispose();
    _staffSalaryController.dispose();
    super.dispose();
  }

  Future<void> _loadFinancials() async {
    try {
      final data = await MobileApiService.getFinancials();
      if (mounted) {
        setState(() {
          _data = data;
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
    rows.sort((a, b) =>
        ((b['amount'] ?? 0) as num).compareTo((a['amount'] ?? 0) as num));
    return rows;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ManagerToast.showSnackBar(context, msg, isError: error);
  }

  Future<void> _addExpense() async {
    final category = _categoryController.text.trim();
    final description = _expenseDescriptionController.text.trim();
    final amount = double.tryParse(_expenseAmountController.text.trim());
    if (category.isEmpty || description.isEmpty || amount == null || amount <= 0) {
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

  void _addSalaryDraft() {
    final name = _staffNameController.text.trim();
    final salary = double.tryParse(_staffSalaryController.text.trim());
    if (name.isEmpty || salary == null || salary <= 0) {
      _toast('შეავსეთ სახელი და ხელფასი სწორად', error: true);
      return;
    }
    setState(() {
      _salaryItems.add(_SalaryItem(name: name, amount: salary));
      _staffNameController.clear();
      _staffSalaryController.clear();
    });
  }

  Future<void> _applySelectedSalaries() async {
    final selected = _salaryItems.where((e) => e.selected).toList();
    if (selected.isEmpty) {
      _toast('მონიშნეთ მინიმუმ ერთი თანამშრომელი', error: true);
      return;
    }
    setState(() => _isApplyingSalaries = true);
    try {
      for (final item in selected) {
        await MobileApiService.createExpense(
          description: item.name,
          amount: item.amount,
          category: 'პერსონალი',
        );
      }
      setState(() {
        _salaryItems.removeWhere((item) => item.selected);
      });
      await _loadFinancials();
      _toast('მონიშნული ხელფასები დაემატა ხარჯებში');
    } catch (_) {
      _toast('ხელფასების დამატება ვერ მოხერხდა', error: true);
    } finally {
      if (mounted) setState(() => _isApplyingSalaries = false);
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
            child: _GlowOrb(color: Color(0xFFEC4899), size: 300),
          ),
          Positioned(
            top: 300,
            left: -100,
            child: _GlowOrb(color: Color(0xFF6366F1), size: 250),
          ),
          SafeArea(
            bottom: false,
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: MobileGlassTheme.primary),
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
            Icon(Icons.wifi_off_rounded, size: 56, color: MobileGlassTheme.textSecondary),
            SizedBox(height: 14),
            Text(
              _error!,
              style: TextStyle(
                  color: MobileGlassTheme.textPrimary, fontWeight: FontWeight.w600),
            ),
            TextButton.icon(
              onPressed: _loadFinancials,
              icon: Icon(Icons.refresh_rounded, color: MobileGlassTheme.accentText),
              label: Text('თავიდან ცდა',
                  style: TextStyle(color: MobileGlassTheme.accentText)),
            ),
          ],
        ),
      );

  Widget _buildContent() {
    final double revenue = (_data!['revenue'] ?? 0).toDouble();
    final double expenses = (_data!['expenses'] ?? 0).toDouble();
    final double profit = revenue - expenses;
    final double cash = (_data!['cashRevenue'] ?? 0).toDouble();
    final double card = (_data!['cardRevenue'] ?? 0).toDouble();
    final selectedSalariesTotal = _salaryItems
        .where((e) => e.selected)
        .fold<double>(0, (sum, e) => sum + e.amount);

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
                  _fade(
                    0.1,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildBalanceCard(revenue, expenses, profit),
                    ),
                  ),
                  SizedBox(height: 28),
                  _fade(0.2, _buildPaymentCard(cash, card)),
                  SizedBox(height: 28),
                  _fade(0.3, _buildExpenseBreakdownCard()),
                  SizedBox(height: 28),
                  _fade(0.4, _buildExpenseComposer()),
                  SizedBox(height: 28),
                  _fade(0.5, _buildSalaryPlanner(selectedSalariesTotal)),
                  SizedBox(height: 28),
                  _fade(0.6, _buildExpenseLog()),
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
          Text(
            'ფინანსები',
            style: TextStyle(
              color: MobileGlassTheme.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          _GlassCard(
            onTap: _loadFinancials,
            borderRadius: BorderRadius.circular(20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.refresh_rounded, color: MobileGlassTheme.textPrimary, size: 18),
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
                      positive ? 'წმინდა მოგება (დღეს)' : 'ზარალი (დღეს)',
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
                        _gel(profit.abs()),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (positive ? MobileGlassTheme.good : MobileGlassTheme.bad).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      positive
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      color: positive ? MobileGlassTheme.good : MobileGlassTheme.bad,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '${margin.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: positive ? MobileGlassTheme.good : MobileGlassTheme.bad,
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
                  title: 'შემოსავალი',
                  amount: _gel(revenue),
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
                  amount: _gel(expenses),
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
                      flex: ((1 - expFrac - profFrac) * 1000)
                          .round()
                          .clamp(1, 1000),
                      child: Container(
                        color: MobileGlassTheme.border(0.12),
                      ),
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
              _legendDot(MobileGlassTheme.good, 'მოგება'),
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
          style: TextStyle(
            color: MobileGlassTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
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
                                  flex: (cashFrac * 1000).round().clamp(1, 1000),
                                  child: Container(color: const Color(0xFF3B82F6)),
                                ),
                              if (cardFrac > 0)
                                Expanded(
                                  flex: (cardFrac * 1000).round().clamp(1, 1000),
                                  child: Container(color: const Color(0xFF8B5CF6)),
                                ),
                            ],
                          ),
                  ),
                ),
                SizedBox(height: 16),
                _payRow('ნაღდი', cash, total, const Color(0xFF3B82F6)),
                SizedBox(height: 12),
                _payRow('ბარათი', card, total, const Color(0xFF8B5CF6)),
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
        0, (m, e) => ((e['amount'] ?? 0) as num).toDouble() > m
            ? ((e['amount'] ?? 0) as num).toDouble()
            : m);

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
                          formatted:
                              _gel(((rows[i]['amount'] ?? 0) as num).toDouble()),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
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
          const _SectionHeader(title: 'ახალი ხარჯი'),
          SizedBox(height: 16),
          _GlassCard(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _darkField(_categoryController, 'კატეგორია (მაგ: ბაზარი)'),
                SizedBox(height: 12),
                _darkField(_expenseDescriptionController, 'აღწერა'),
                SizedBox(height: 12),
                _darkField(
                  _expenseAmountController,
                  'თანხა',
                  number: true,
                ),
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

  // ── Salary planner ────────────────────────────────────────────────────
  Widget _buildSalaryPlanner(double selectedSalariesTotal) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'პერსონალის ხელფასები'),
          SizedBox(height: 16),
          _GlassCard(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'დაამატეთ სახელი და ხელფასი, შემდეგ მონიშნულები ერთიანად ჩასვით ხარჯებში.',
                  style: TextStyle(
                    color: MobileGlassTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: 14),
                _darkField(_staffNameController, 'სახელი'),
                SizedBox(height: 12),
                _darkField(_staffSalaryController, 'ხელფასი', number: true),
                SizedBox(height: 12),
                _outlineButton(label: 'სიაში დამატება', onTap: _addSalaryDraft),
                if (_salaryItems.isNotEmpty) ...[
                  SizedBox(height: 14),
                  for (var idx = 0; idx < _salaryItems.length; idx++)
                    _buildSalaryRow(idx, _salaryItems[idx]),
                  SizedBox(height: 8),
                  Divider(color: MobileGlassTheme.border(0.12)),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'მონიშნული ჯამი',
                        style: TextStyle(
                          color: MobileGlassTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _gel(selectedSalariesTotal),
                        style: TextStyle(
                          color: MobileGlassTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  _primaryButton(
                    label: _isApplyingSalaries
                        ? 'ინახება...'
                        : 'მონიშნულის ხარჯებში დამატება',
                    onTap: _isApplyingSalaries ? null : _applySelectedSalaries,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalaryRow(int idx, _SalaryItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() =>
                _salaryItems[idx] = item.copyWith(selected: !item.selected)),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: item.selected ? MobileGlassTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: item.selected
                      ? MobileGlassTheme.primary
                      : Colors.white.withValues(alpha: 0.25),
                ),
              ),
              child: item.selected
                  ? Icon(Icons.check_rounded, size: 16, color: MobileGlassTheme.textPrimary)
                  : null,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                      color: MobileGlassTheme.textPrimary, fontWeight: FontWeight.w600),
                ),
                Text(
                  _gel(item.amount),
                  style: TextStyle(
                    color: MobileGlassTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _salaryItems.removeAt(idx)),
            behavior: HitTestBehavior.opaque,
            child: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

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
                      style:
                          TextStyle(color: MobileGlassTheme.textSecondary),
                    ),
                  )
                : Column(
                    children: [
                      for (final e in entries)
                        _buildExpenseLogRow(e, fmt),
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
    final double amt =
        amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0;
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
            child: Icon(Icons.receipt_long_rounded,
                color: MobileGlassTheme.bad, size: 20),
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
                      color: MobileGlassTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
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
                color: MobileGlassTheme.bad, fontWeight: FontWeight.bold, fontSize: 14),
          ),
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
      keyboardType:
          number ? const TextInputType.numberWithOptions(decimal: true) : null,
      style: TextStyle(color: MobileGlassTheme.textPrimary, fontSize: 15),
      cursorColor: MobileGlassTheme.primary,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: MobileGlassTheme.textSecondary, fontSize: 13),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          disabledBackgroundColor: MobileGlassTheme.primary.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _outlineButton({required String label, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: MobileGlassTheme.accentText,
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: MobileGlassTheme.primary.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _SalaryItem {
  final String name;
  final double amount;
  final bool selected;

  const _SalaryItem({
    required this.name,
    required this.amount,
    this.selected = true,
  });

  _SalaryItem copyWith({String? name, double? amount, bool? selected}) {
    return _SalaryItem(
      name: name ?? this.name,
      amount: amount ?? this.amount,
      selected: selected ?? this.selected,
    );
  }
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
              decoration:
                  BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 12),
            ),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                  color: MobileGlassTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
        SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            amount,
            style: TextStyle(
                color: MobileGlassTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
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
                  color: MobileGlassTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
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
              Container(
                height: 9,
                color: Colors.white.withValues(alpha: 0.06),
              ),
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
                          offset: const Offset(0, 2)),
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
            border: Border.all(color: MobileGlassTheme.data.borderSubtle, width: 1),
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
