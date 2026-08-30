part of '../mobile_admin_screen.dart';

class _ReportTab extends StatefulWidget {
  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _period = 'today';
  String _monthKey = DateFormat('yyyy-MM').format(DateTime.now());
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

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
      final data = await MobileApiService.getSalesReport(
        period: _period,
        month: _period == 'month' ? _monthKey : null,
      );
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPeriodSelector(),
        Expanded(
          child: _loading
              ? const _AdminLoading()
              : _error != null
              ? _ErrorWidget(onRetry: _load)
              : _buildReport(),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AdminFilterChip(
              label: 'დღეს',
              selected: _period == 'today',
              onTap: () {
                setState(() => _period = 'today');
                _load();
              },
            ),
            _AdminFilterChip(
              label: 'კვირა',
              selected: _period == 'week',
              onTap: () {
                setState(() => _period = 'week');
                _load();
              },
            ),
            _AdminFilterChip(
              label: 'თვე',
              selected: _period == 'month',
              onTap: () {
                setState(() => _period = 'month');
                _load();
              },
            ),
          ],
        ),
        if (_period == 'month') ...[
          SizedBox(height: 8),
          _AdminMonthNav(
            label: _monthKey,
            onPrev: _prevMonth,
            onNext: _nextMonth,
          ),
        ],
      ],
    ),
  );

  void _prevMonth() {
    final d = DateTime.tryParse('$_monthKey-01') ?? DateTime.now();
    final p = DateTime(d.year, d.month - 1, 1);
    setState(() => _monthKey = DateFormat('yyyy-MM').format(p));
    _load();
  }

  void _nextMonth() {
    final d = DateTime.tryParse('$_monthKey-01') ?? DateTime.now();
    final n = DateTime(d.year, d.month + 1, 1);
    setState(() => _monthKey = DateFormat('yyyy-MM').format(n));
    _load();
  }

  String _periodLabel() {
    switch (_period) {
      case 'week':
        return 'ბოლო 7 დღე';
      case 'month':
        return _monthKey;
      default:
        return 'დღეს';
    }
  }

  Widget _buildReport() {
    final d = _data!;
    final topItems = (d['topItems'] as List?) ?? [];
    final topItemsByCategory = (d['topItemsByCategory'] as List?) ?? [];
    final byWaiter = (d['byWaiter'] as List?) ?? [];
    final paymentBreakdown = Map<String, dynamic>.from(
      (d['paymentBreakdown'] as Map?) ?? const {},
    );
    final totalRevenue = (d['totalRevenue'] as num?)?.toDouble() ?? 0;
    final orderCount = d['orderCount'] ?? 0;
    final avgOrder = (d['avgOrderValue'] as num?)?.toDouble() ?? 0;
    final cashRevenue = (d['cashRevenue'] as num?)?.toDouble() ?? 0;
    final cardRevenue = (d['cardRevenue'] as num?)?.toDouble() ?? 0;
    final nonFiscalRevenue = _nonFiscalFromBreakdown(paymentBreakdown);
    final breakdownEntries = paymentBreakdown.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return RefreshIndicator(
      color: AdminTheme.primary,
      backgroundColor: AdminTheme.surface,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: _adminScrollPadding(context).copyWith(top: 0),
        children: [
          _AdminHeroMetric(
            label: 'შემოსავალი',
            value: _adminGel(totalRevenue),
            subtitle:
                '${_periodLabel()} · $orderCount შეკვეთა · საშ. ${_adminGel(avgOrder)}',
            accent: AdminTheme.good,
          ),
          SizedBox(height: 16),
          _AdminKpiGrid(
            items: [
              _AdminKpiItem(
                label: 'ნაღდი',
                value: _adminGel(cashRevenue),
                subtitle: _adminShareSubtitle(cashRevenue, totalRevenue),
                icon: Icons.payments_outlined,
                color: AdminTheme.good,
              ),
              _AdminKpiItem(
                label: 'ბარათი',
                value: _adminGel(cardRevenue),
                subtitle: _adminShareSubtitle(cardRevenue, totalRevenue),
                icon: Icons.credit_card_outlined,
                color: AdminTheme.accent,
              ),
              _AdminKpiItem(
                label: 'არაფისკალური',
                value: _adminGel(nonFiscalRevenue),
                subtitle: _adminShareSubtitle(nonFiscalRevenue, totalRevenue),
                icon: Icons.receipt_long_outlined,
                color: AdminTheme.warn,
              ),
              _AdminKpiItem(
                label: 'შეკვეთები',
                value: '$orderCount',
                subtitle: 'საშ. ${_adminGel(avgOrder)}',
                icon: Icons.receipt_outlined,
                color: AdminTheme.primary,
              ),
            ],
          ),
          SizedBox(height: 16),
          _AdminSection(
            title: 'გადახდის დეტალი',
            child: _AdminPanel(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: breakdownEntries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'გადახდის დეტალი არ არის',
                        style: TextStyle(color: AdminTheme.textMuted),
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < breakdownEntries.length; i++) ...[
                          if (i > 0)
                            Divider(height: 1, color: AdminTheme.border),
                          _AdminMetricRow(
                            label: _adminPaymentLabel(breakdownEntries[i].key),
                            value: _adminGel(
                              (breakdownEntries[i].value as num?)?.toDouble() ??
                                  0,
                            ),
                            color: _adminPaymentColor(breakdownEntries[i].key),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          if (byWaiter.isNotEmpty) ...[
            SizedBox(height: 20),
            _AdminSection(
              title: 'ოფიციანტები',
              trailing: '${byWaiter.length}',
              child: Column(
                children: byWaiter
                    .cast<Map<String, dynamic>>()
                    .map(
                      (w) => _WaiterRow(
                        name: w['waiterName'] as String? ?? '',
                        total: (w['totalSales'] as num?)?.toDouble() ?? 0,
                        count: w['orderCount'] as int? ?? 0,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          if (topItemsByCategory.isNotEmpty) ...[
            SizedBox(height: 20),
            const _SectionTitle('კატეგორიების მიხედვით გაყიდული პოზიციები'),
            SizedBox(height: 8),
            ...topItemsByCategory.cast<Map<String, dynamic>>().map((cat) {
              final catName = cat['category'] as String? ?? 'სხვა';
              final catRevenue = (cat['totalRevenue'] as num?)?.toDouble() ?? 0;
              final catItems = (cat['items'] as List?) ?? [];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AdminTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AdminTheme.border),
                ),
                child: ExpansionTile(
                  key: PageStorageKey<String>('admin-report-cat-$catName'),
                  tilePadding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                  title: Text(
                    catName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.text,
                    ),
                  ),
                  subtitle: Text(
                    _adminGel(catRevenue),
                    style: TextStyle(color: AdminTheme.textMuted),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  children: catItems
                      .cast<Map<String, dynamic>>()
                      .asMap()
                      .entries
                      .map((e) {
                        return _TopItemRow(
                          rank: e.key + 1,
                          name: e.value['name'] as String? ?? '',
                          qty: (e.value['qty'] as num?)?.toInt() ?? 0,
                          revenue:
                              (e.value['revenue'] as num?)?.toDouble() ?? 0,
                        );
                      })
                      .toList(),
                ),
              );
            }),
          ] else if (topItems.isNotEmpty) ...[
            SizedBox(height: 20),
            const _SectionTitle('ტოპ პროდუქტები'),
            SizedBox(height: 8),
            ...topItems.cast<Map<String, dynamic>>().asMap().entries.map(
              (e) => _TopItemRow(
                rank: e.key + 1,
                name: e.value['name'] as String? ?? '',
                qty: e.value['qty'] as int? ?? 0,
                revenue: (e.value['revenue'] as num?)?.toDouble() ?? 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

double _nonFiscalFromBreakdown(Map<String, dynamic> breakdown) {
  double sum = 0;
  for (final entry in breakdown.entries) {
    final key = entry.key.trim().toLowerCase();
    if (key == 'non-fiscal' || key == 'nonfiscal' || key == 'non_fiscal') {
      sum += (entry.value as num?)?.toDouble() ?? 0;
    }
  }
  return sum;
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: AdminTheme.primary,
    ),
  );
}

class _WaiterRow extends StatelessWidget {
  final String name;
  final double total;
  final int count;

  const _WaiterRow({
    required this.name,
    required this.total,
    required this.count,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AdminTheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminTheme.border),
    ),
    child: Row(
      children: [
        const Icon(Icons.person_rounded, size: 18, color: Color(0xFF94A3B8)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AdminTheme.text,
            ),
          ),
        ),
        Text(
          '$count შეკ.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        SizedBox(width: 12),
        Text(
          _adminGel(total),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AdminTheme.primary,
          ),
        ),
      ],
    ),
  );
}

class _TopItemRow extends StatelessWidget {
  final int rank;
  final String name;
  final int qty;
  final double revenue;

  const _TopItemRow({
    required this.rank,
    required this.name,
    required this.qty,
    required this.revenue,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AdminTheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminTheme.border),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$rank.',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF94A3B8),
            ),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AdminTheme.text,
            ),
          ),
        ),
        Text(
          '$qtyც.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        SizedBox(width: 12),
        Text(
          _adminGel(revenue),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AdminTheme.primary,
          ),
        ),
      ],
    ),
  );
}
