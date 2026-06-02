part of '../mobile_admin_screen.dart';

class _SalesTab extends StatefulWidget {
  @override
  State<_SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<_SalesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  String _monthKey = DateFormat('yyyy-MM').format(DateTime.now());

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
      _rows = const [];
    });
    try {
      final data = await MobileApiService.getSalesDaily(month: _monthKey);
      setState(() {
        _rows = data;
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
    if (_loading) return const _AdminLoading();
    if (_error != null) return _ErrorWidget(onRetry: _load);
    final monthDt = DateTime.tryParse('$_monthKey-01') ?? DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(monthDt);

    final monthTotal = _rows.fold<double>(
      0,
      (s, r) => s + ((r['totalRevenue'] as num?)?.toDouble() ?? 0),
    );

    return RefreshIndicator(
      color: AdminTheme.primary,
      backgroundColor: AdminTheme.surface,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: _adminScrollPadding(context),
        children: [
          _AdminMonthNav(
            label: 'გაყიდვები • $monthLabel',
            onPrev: _prevMonth,
            onNext: _nextMonth,
          ),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            _AdminStatCard(
              label: 'თვის შემოსავალი',
              value: _money.format(monthTotal),
              icon: Icons.summarize_rounded,
              accent: AdminTheme.good,
              subtitle: '${_rows.length} დღე',
            ),
          ],
          const SizedBox(height: 10),
          if (_rows.isEmpty)
            _AdminPanel(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 14),
              child: Center(
                child: Text(
                  'ამ თვეში გაყიდვები არ არის',
                  style: TextStyle(
                    color: AdminTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            ..._rows.map((r) => _buildDayCard(r)),
        ],
      ),
    );
  }

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

  Widget _buildDayCard(Map<String, dynamic> row) {
    final date = (row['date'] ?? '').toString();
    final totalRevenue = (row['totalRevenue'] as num?)?.toDouble() ?? 0;
    final totalOrders = (row['totalOrders'] as num?)?.toInt() ?? 0;
    final closedOrders = (row['closedOrders'] as num?)?.toInt() ?? 0;
    final cancelledOrders = (row['cancelledOrders'] as num?)?.toInt() ?? 0;
    final totalExpenses = (row['totalExpenses'] as num?)?.toDouble() ?? 0;
    final profit = (row['profit'] as num?)?.toDouble() ?? (totalRevenue - totalExpenses);
    final breakdown = Map<String, dynamic>.from(
      (row['paymentBreakdown'] as Map?) ?? const {},
    );
    final closedTables = ((row['closedTables'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final nonFiscalAmount = _nonFiscalFromBreakdown(breakdown);
    final entries = breakdown.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _AdminPanel(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        iconColor: AdminTheme.primary,
        collapsedIconColor: AdminTheme.textDim,
        title: Text(
          date,
          style: const TextStyle(fontWeight: FontWeight.w700, color: AdminTheme.text),
        ),
        subtitle: Text(
          'დახურული $closedOrders / გაუქმებული $cancelledOrders / სულ $totalOrders • ${_money.format(totalRevenue)}\nხარჯი: ${_money.format(totalExpenses)} • მოგება: ${_money.format(profit)}\nარაფისკალური დახურული: ${_money.format(nonFiscalAmount)}',
          style: TextStyle(fontSize: 12, color: AdminTheme.textMuted),
        ),
        children: [
          if (nonFiscalAmount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'არაფისკალური დახურული',
                      style: TextStyle(
                        color: Color(0xFF9A3412),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _money.format(nonFiscalAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9A3412),
                    ),
                  ),
                ],
              ),
            ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'გადახდის დეტალი არ არის',
                  style: TextStyle(color: AdminTheme.textMuted),
                ),
              ),
            )
          else
            ...entries.map((e) {
              final key = e.key.toString();
              final amount = (e.value as num).toDouble();
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AdminTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdminTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _paymentLabel(key),
                        style: const TextStyle(color: AdminTheme.text),
                      ),
                    ),
                    Text(
                      _money.format(amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.primary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (closedTables.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'დახურული მაგიდები',
                style: TextStyle(
                  color: AdminTheme.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 6),
            ...closedTables.map(
              (sale) => _buildClosedTableRow(context, sale),
            ),
          ],
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildClosedTableRow(BuildContext context, Map<String, dynamic> sale) {
    final tableLabel = (sale['tableLabel'] ?? '').toString().trim();
    final orderId = (sale['orderId'] as num?)?.toInt();
    final totalAmount = (sale['totalAmount'] as num?)?.toDouble() ?? 0;
    final paymentBreakdown = Map<String, dynamic>.from(
      (sale['paymentBreakdown'] as Map?) ?? const {},
    );
    final paymentLabel = _closedPaymentLabel(paymentBreakdown);
    final paymentColors = _closedPaymentColors(paymentBreakdown);
    final items = ((sale['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final title = tableLabel.isNotEmpty
        ? 'მაგიდა: $tableLabel'
        : 'მაგიდა #${orderId ?? 0}';

    return InkWell(
      onTap: () => _showClosedSaleDetails(
        context,
        title: title,
        totalAmount: totalAmount,
        items: items,
        orderId: orderId,
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AdminTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminTheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AdminTheme.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: paymentColors.$1,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                paymentLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: paymentColors.$2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _money.format(totalAmount),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AdminTheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  String _paymentLabel(String key) {
    switch (key) {
      case 'card-tbc':
        return 'ბარათი TBC';
      case 'card-bog':
        return 'ბარათი BOG';
      case 'cash':
        return 'ნაღდი';
      case 'non-fiscal':
        return 'არაფისკალური';
      default:
        return key;
    }
  }

  double _nonFiscalFromBreakdown(Map<String, dynamic> breakdown) {
    double sum = 0;
    for (final entry in breakdown.entries) {
      final normalized = entry.key.trim().toLowerCase();
      if (normalized == 'non-fiscal' ||
          normalized == 'nonfiscal' ||
          normalized == 'non_fiscal') {
        sum += (entry.value as num?)?.toDouble() ?? 0;
      }
    }
    return sum;
  }

  String _closedPaymentLabel(Map<String, dynamic> breakdown) {
    if (breakdown.isEmpty) return 'უცნობი გადახდა';
    final keys = breakdown.keys.map((k) => k.trim().toLowerCase()).toSet();
    if (keys.contains('non-fiscal') ||
        keys.contains('nonfiscal') ||
        keys.contains('non_fiscal')) {
      return 'არაფისკალური';
    }
    if (keys.length > 1) {
      return 'split';
    }
    final key = keys.first;
    if (key == 'cash') return 'ნაღდი';
    if (key == 'card-tbc') return 'ბარათი TBC';
    if (key == 'card-bog') return 'ბარათი BOG';
    if (key.startsWith('card')) return 'ბარათი';
    if (key == 'advance') return 'ავანსი';
    return key;
  }

  (Color, Color) _closedPaymentColors(Map<String, dynamic> breakdown) {
    final label = _closedPaymentLabel(breakdown).toLowerCase();
    if (label.contains('არაფისკალური')) {
      return (const Color(0xFFFFEDD5), const Color(0xFF9A3412));
    }
    if (label.contains('split')) {
      return (const Color(0xFFEDE9FE), const Color(0xFF5B21B6));
    }
    if (label.contains('ნაღდი')) {
      return (const Color(0xFFDCFCE7), const Color(0xFF166534));
    }
    if (label.contains('tbc')) {
      return (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8));
    }
    if (label.contains('bog')) {
      return (const Color(0xFFFFEDD5), const Color(0xFF9A3412));
    }
    return (const Color(0xFFE2E8F0), const Color(0xFF334155));
  }

  Future<void> _showClosedSaleDetails(
    BuildContext context, {
    required String title,
    required double totalAmount,
    required List<Map<String, dynamic>> items,
    required int? orderId,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.72,
          decoration: const BoxDecoration(
            color: AdminTheme.surfaceElevated,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        orderId != null ? '$title • #$orderId' : title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AdminTheme.text,
                        ),
                      ),
                    ),
                    Text(
                      _money.format(totalAmount),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'ამ გაყიდვაზე პოზიციები არ მოიძებნა',
                          style: TextStyle(color: AdminTheme.textMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final name = (item['name'] ?? '').toString();
                          final qty = (item['qty'] as num?)?.toInt() ?? 0;
                          final unitPrice =
                              (item['unitPrice'] as num?)?.toDouble() ?? 0;
                          final total =
                              (item['total'] as num?)?.toDouble() ?? 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AdminTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AdminTheme.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name.isNotEmpty ? name : 'უცნობი პოზიცია',
                                    style: const TextStyle(
                                      color: AdminTheme.text,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$qty x ${_money.format(unitPrice)}',
                                  style: TextStyle(
                                    color: AdminTheme.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _money.format(total),
                                  style: const TextStyle(
                                    color: AdminTheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
