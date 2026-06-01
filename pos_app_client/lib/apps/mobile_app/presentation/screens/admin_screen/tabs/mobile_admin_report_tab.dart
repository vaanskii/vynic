part of '../mobile_admin_screen.dart';

const _reportSurface = Color(0xFFF8FAFF);
const _reportCard = Color(0xFFFFFFFF);
const _reportBorder = Color(0xFFDDE7FF);
const _reportPrimary = Color(0xFF3B82F6);
const _reportText = Color(0xFF1E293B);
const _reportMuted = Color(0xFF64748B);

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

  static final _money = NumberFormat.currency(
    locale: 'ka_GE',
    symbol: '₾',
    decimalDigits: 2,
  );

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
      children: [
        _buildPeriodSelector(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: _ErrorWidget(onRetry: _load))
        else
          Expanded(child: _buildReport()),
      ],
    );
  }

  Widget _buildPeriodSelector() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PeriodChip(
                  label: 'დღეს',
                  selected: _period == 'today',
                  onTap: () {
                    setState(() => _period = 'today');
                    _load();
                  },
                ),
                _PeriodChip(
                  label: 'კვირა',
                  selected: _period == 'week',
                  onTap: () {
                    setState(() => _period = 'week');
                    _load();
                  },
                ),
                _PeriodChip(
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
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _reportSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _reportBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      size: 16,
                      color: _reportPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _monthKey,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _reportText,
                      ),
                    ),
                    const Spacer(),
                    _ReportMonthNavButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: _prevMonth,
                    ),
                    const SizedBox(width: 6),
                    _ReportMonthNavButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: _nextMonth,
                    ),
                  ],
                ),
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

  Widget _buildReport() {
    final d = _data!;
    final topItems = (d['topItems'] as List?) ?? [];
    final topItemsByCategory = (d['topItemsByCategory'] as List?) ?? [];
    final byWaiter = (d['byWaiter'] as List?) ?? [];
    final paymentBreakdown = Map<String, dynamic>.from(
      (d['paymentBreakdown'] as Map?) ?? const {},
    );
    final nonFiscalRevenue = _nonFiscalFromBreakdown(paymentBreakdown);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'შემოსავალი',
                  value: _money.format((d['totalRevenue'] as num?)?.toDouble() ?? 0),
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: 'შეკვეთები',
                  value: '${d['orderCount'] ?? 0}',
                  icon: Icons.receipt_rounded,
                  color: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'ნაღდი',
                  value: _money.format((d['cashRevenue'] as num?)?.toDouble() ?? 0),
                  icon: Icons.money_rounded,
                  color: const Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: 'ბარათი',
                  value: _money.format((d['cardRevenue'] as num?)?.toDouble() ?? 0),
                  icon: Icons.credit_card_rounded,
                  color: const Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _KpiCard(
            label: 'არაფისკალური',
            value: _money.format(nonFiscalRevenue),
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 12),
          _KpiCard(
            label: 'საშ. შეკვეთა',
            value: _money.format((d['avgOrderValue'] as num?)?.toDouble() ?? 0),
            icon: Icons.trending_up_rounded,
            color: const Color(0xFFF59E0B),
          ),
          if (byWaiter.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('ოფიციანტების შედეგები'),
            const SizedBox(height: 8),
            ...byWaiter.cast<Map<String, dynamic>>().map(
                  (w) => _WaiterRow(
                    name: w['waiterName'] as String? ?? '',
                    total: (w['totalSales'] as num?)?.toDouble() ?? 0,
                    count: w['orderCount'] as int? ?? 0,
                    money: _money,
                  ),
                ),
          ],
          if (topItemsByCategory.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('კატეგორიების მიხედვით გაყიდული პოზიციები'),
            const SizedBox(height: 8),
            ...topItemsByCategory.cast<Map<String, dynamic>>().map((cat) {
              final catName = cat['category'] as String? ?? 'სხვა';
              final catRevenue = (cat['totalRevenue'] as num?)?.toDouble() ?? 0;
              final catItems = (cat['items'] as List?) ?? [];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _reportCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _reportBorder),
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                  title: Text(
                    catName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _reportText,
                    ),
                  ),
                  subtitle: Text(
                    _money.format(catRevenue),
                    style: const TextStyle(color: _reportMuted),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  children: catItems.cast<Map<String, dynamic>>().asMap().entries.map((e) {
                    return _TopItemRow(
                      rank: e.key + 1,
                      name: e.value['name'] as String? ?? '',
                      qty: (e.value['qty'] as num?)?.toInt() ?? 0,
                      revenue: (e.value['revenue'] as num?)?.toDouble() ?? 0,
                      money: _money,
                    );
                  }).toList(),
                ),
              );
            }),
          ] else if (topItems.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('ტოპ პროდუქტები'),
            const SizedBox(height: 8),
            ...topItems.cast<Map<String, dynamic>>().asMap().entries.map(
                  (e) => _TopItemRow(
                    rank: e.key + 1,
                    name: e.value['name'] as String? ?? '',
                    qty: e.value['qty'] as int? ?? 0,
                    revenue: (e.value['revenue'] as num?)?.toDouble() ?? 0,
                    money: _money,
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
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: _reportPrimary,
        ),
      );
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _reportCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _reportBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: _reportMuted),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _reportText,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _WaiterRow extends StatelessWidget {
  final String name;
  final double total;
  final int count;
  final NumberFormat money;

  const _WaiterRow({
    required this.name,
    required this.total,
    required this.count,
    required this.money,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _reportCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _reportBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_rounded, size: 18, color: Color(0xFF94A3B8)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _reportText,
                ),
              ),
            ),
            Text(
              '$count შეკ.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 12),
            Text(
              money.format(total),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _reportPrimary,
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
  final NumberFormat money;

  const _TopItemRow({
    required this.rank,
    required this.name,
    required this.qty,
    required this.revenue,
    required this.money,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _reportCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _reportBorder),
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
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _reportText,
                ),
              ),
            ),
            Text(
              '$qtyც.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 12),
            Text(
              money.format(revenue),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _reportPrimary,
              ),
            ),
          ],
        ),
      );
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? _reportPrimary : _reportCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? _reportPrimary : _reportBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _reportMuted,
            ),
          ),
        ),
      );
}

class _ReportMonthNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ReportMonthNavButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Ink(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _reportCard,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _reportBorder),
          ),
          child: Icon(icon, size: 18, color: _reportText),
        ),
      );
}
