import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

enum _SalesPeriod { today, week, month }

class AdminSalesReportSection extends StatefulWidget {
  const AdminSalesReportSection({
    super.key,
    required this.selectedSalesYear,
    required this.selectedSalesMonth,
    required this.onChangeSalesMonth,
    required this.onSetSelectedSalesMonth,
  });

  final int selectedSalesYear;
  final int selectedSalesMonth;
  final ValueChanged<int> onChangeSalesMonth;
  final ValueChanged<DateTime> onSetSelectedSalesMonth;

  @override
  State<AdminSalesReportSection> createState() =>
      _AdminSalesReportSectionState();
}

class _AdminSalesReportSectionState extends State<AdminSalesReportSection> {
  static const Color _primary = AdminDesign.accentDark;
  static const Color _accent = AdminDesign.accent;
  static const Color _surface = AdminDesign.panelSoft;
  static const Color _card = AdminDesign.panel;
  static const Color _border = AdminDesign.border;
  static const Color _text = AdminDesign.text;
  static const Color _muted = AdminDesign.muted;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'ka_GE',
    symbol: '₾',
    decimalDigits: 2,
  );

  _SalesPeriod _selectedPeriod = _SalesPeriod.month;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final allSales = DatabaseService.getAllSales();
    final currentBusinessDate = DatabaseService.getCurrentDate();
    final selectedMonthDate = DateTime(
      widget.selectedSalesYear,
      widget.selectedSalesMonth,
    );

    final filtered = _filterSalesByPeriod(
      allSales: allSales,
      businessDate: currentBusinessDate,
      selectedMonthDate: selectedMonthDate,
      period: _selectedPeriod,
    );

    final menuReport = _generateMenuReport(filtered.activeSales);
    final kpis = _buildKpis(
      rawSales: filtered.sales,
      activeSales: filtered.activeSales,
      summaries: menuReport,
    );

    final monthOptionsSet = <DateTime>{};
    for (final sale in allSales) {
      final date = _resolveSaleDate(sale);
      if (date != null) {
        monthOptionsSet.add(DateTime(date.year, date.month, 1));
      }
    }

    final monthOptions = monthOptionsSet.toList()
      ..sort((a, b) => b.compareTo(a));

    final selectedMonthInOptions = monthOptions.any(
      (month) =>
          month.year == selectedMonthDate.year &&
          month.month == selectedMonthDate.month,
    );

    final effectiveSelectedMonth =
        selectedMonthInOptions && monthOptions.isNotEmpty
        ? selectedMonthDate
        : (monthOptions.isNotEmpty ? monthOptions.first : selectedMonthDate);

    if (!selectedMonthInOptions && monthOptions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSetSelectedSalesMonth(monthOptions.first);
      });
    }

    final selectedIndex = monthOptions.indexWhere(
      (month) =>
          month.year == effectiveSelectedMonth.year &&
          month.month == effectiveSelectedMonth.month,
    );
    final isPrevDisabled = monthOptions.isEmpty || selectedIndex <= 0;
    final isNextDisabled =
        monthOptions.isEmpty ||
        selectedIndex == -1 ||
        selectedIndex >= monthOptions.length - 1;

    return SizedBox.expand(
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminSectionHeader(
                  icon: Icons.insights_outlined,
                  title: 'გაყიდვების ანალიტიკა',
                  subtitle:
                      'ძირითადი მაჩვენებლები, პერიოდული დინამიკა და მენიუს შედეგები.',
                  badge: AdminStatusBadge(
                    icon: Icons.calendar_month_outlined,
                    label: filtered.label,
                  ),
                ),
                const SizedBox(height: 12),
                _buildPeriodToggleCard(),
                const SizedBox(height: 10),
                if (_selectedPeriod == _SalesPeriod.month)
                  _buildMonthFilterCard(
                    selectedMonthDate: effectiveSelectedMonth,
                    monthOptions: monthOptions,
                    selectedIndex: selectedIndex,
                    isPrevDisabled: isPrevDisabled,
                    isNextDisabled: isNextDisabled,
                  )
                else
                  _buildActivePeriodInfo(filtered),
                const SizedBox(height: 12),
                _buildKpiGrid(kpis),
                const SizedBox(height: 12),
                _buildLegendAndNotes(kpis),
                const SizedBox(height: 12),
                _buildMenuReportCard(
                  periodLabel: filtered.label,
                  summaries: menuReport,
                  totalRevenue: kpis.revenue,
                  totalQuantity: kpis.totalItems,
                  isMobile: isMobile,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodToggleCard() {
    Widget periodChip(_SalesPeriod period, String label, IconData icon) {
      final isSelected = _selectedPeriod == period;
      return ChoiceChip(
        selected: isSelected,
        selectedColor: const Color(0xFFDBEAFE),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isSelected ? const Color(0xFFBFDBFE) : _border,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        avatar: Icon(icon, size: 16, color: isSelected ? _primary : _muted),
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? _primary : _text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        onSelected: (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _selectedPeriod = period;
          });
        },
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          periodChip(_SalesPeriod.today, 'დღეს', Icons.today_outlined),
          periodChip(_SalesPeriod.week, 'ეს კვირა', Icons.date_range_outlined),
          periodChip(
            _SalesPeriod.month,
            'ეს თვე',
            Icons.calendar_month_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildMonthFilterCard({
    required DateTime selectedMonthDate,
    required List<DateTime> monthOptions,
    required int selectedIndex,
    required bool isPrevDisabled,
    required bool isNextDisabled,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFECFDF5),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'საანგარიშო თვე',
                  style: TextStyle(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_getGeorgianMonthName(selectedMonthDate.month)} ${selectedMonthDate.year}',
                  style: TextStyle(
                    color: _text,
                    fontSize: MediaQuery.of(context).size.width < 400 ? 14 : 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (MediaQuery.of(context).size.width > 500) ...[
            IconButton(
              tooltip: 'Previous month',
              onPressed: isPrevDisabled
                  ? null
                  : () => widget.onSetSelectedSalesMonth(
                      monthOptions[selectedIndex - 1],
                    ),
              icon: const Icon(Icons.chevron_left, size: 20),
              color: _text,
              splashRadius: 18,
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<DateTime>(
                value: monthOptions.isNotEmpty ? selectedMonthDate : null,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border),
                  ),
                ),
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                iconEnabledColor: _primary,
                items: monthOptions.map((monthDate) {
                  final label =
                      '${_getGeorgianMonthName(monthDate.month)} ${monthDate.year}';
                  return DropdownMenuItem<DateTime>(
                    value: monthDate,
                    child: Text(label),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    widget.onSetSelectedSalesMonth(value);
                  }
                },
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: isNextDisabled
                  ? null
                  : () => widget.onSetSelectedSalesMonth(
                      monthOptions[selectedIndex + 1],
                    ),
              icon: const Icon(Icons.chevron_right, size: 20),
              color: _text,
              splashRadius: 18,
            ),
          ] else
            PopupMenuButton<DateTime>(
              icon: const Icon(Icons.calendar_month, color: _primary),
              onSelected: (value) => widget.onSetSelectedSalesMonth(value),
              itemBuilder: (context) => monthOptions.map((m) {
                return PopupMenuItem(
                  value: m,
                  child: Text('${_getGeorgianMonthName(m.month)} ${m.year}'),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildActivePeriodInfo(_FilteredSales filtered) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdminDesign.panelSoft,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: _border),
      ),
      child: Text(
        '${filtered.label} • ${_formatDate(filtered.start)} - ${_formatDate(filtered.end)}',
        style: const TextStyle(
          color: _text,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildKpiGrid(_SalesKpis kpis) {
    final cards = <Widget>[
      _kpiCard(
        title: 'წმინდა შემოსავალი',
        value: _money.format(kpis.revenue),
        subtitle: 'აქტიური გაყიდვები',
        color: AdminDesign.accentDark,
      ),
      _kpiCard(
        title: 'ტრანზაქციები',
        value: kpis.transactions.toString(),
        subtitle: 'გაუქმების გარეშე',
        color: const Color(0xFF7C3AED),
      ),
      _kpiCard(
        title: 'საშუალო ჩეკი',
        value: _money.format(kpis.avgCheck),
        subtitle: 'საშუალო ჩეკი',
        color: const Color(0xFF0EA5E9),
      ),
      _kpiCard(
        title: 'გაუქმებული',
        value: kpis.cancelledCount.toString(),
        subtitle: 'გაუქმებული გაყიდვები',
        color: const Color(0xFFEF4444),
      ),
      _kpiCard(
        title: 'Items Sold',
        value: kpis.totalItems.toString(),
        subtitle: 'მენიუს ერთეულები',
        color: const Color(0xFF16A34A),
      ),
      _kpiCard(
        title: 'Top Category',
        value: kpis.topCategoryName,
        subtitle: _money.format(kpis.topCategoryRevenue),
        color: const Color(0xFFF59E0B),
      ),
    ];

    final isMobile = MediaQuery.of(context).size.width < 600;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: cards
          .map(
            (c) => SizedBox(
              width: isMobile
                  ? (MediaQuery.of(context).size.width - 42) / 2
                  : 220,
              child: c,
            ),
          )
          .toList(),
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _text,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendAndNotes(_SalesKpis kpis) {
    final cancelRate = kpis.totalSalesCount == 0
        ? 0.0
        : (kpis.cancelledCount / kpis.totalSalesCount) * 100;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick insights',
            style: TextStyle(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _infoPill(
                icon: Icons.trending_up,
                text: 'Top კატეგორია: ${kpis.topCategoryName}',
                color: const Color(0xFFF59E0B),
              ),
              _infoPill(
                icon: Icons.cancel_outlined,
                text: 'გაუქმების წილი: ${cancelRate.toStringAsFixed(1)}%',
                color: const Color(0xFFEF4444),
              ),
              _infoPill(
                icon: Icons.shopping_cart_outlined,
                text:
                    'ერთ ტრანზაქციაზე საშუალო ერთეული: ${kpis.avgItemsPerTransaction.toStringAsFixed(1)}',
                color: const Color(0xFF16A34A),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoPill({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  _FilteredSales _filterSalesByPeriod({
    required List<Map<String, dynamic>> allSales,
    required DateTime businessDate,
    required DateTime selectedMonthDate,
    required _SalesPeriod period,
  }) {
    final businessDay = DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
    );

    late DateTime start;
    late DateTime end;
    late String label;

    switch (period) {
      case _SalesPeriod.today:
        start = businessDay;
        end = businessDay;
        label = 'Today';
        break;
      case _SalesPeriod.week:
        start = businessDay.subtract(Duration(days: businessDay.weekday - 1));
        end = start.add(const Duration(days: 6));
        label = 'This Week';
        break;
      case _SalesPeriod.month:
        start = DateTime(selectedMonthDate.year, selectedMonthDate.month, 1);
        end = DateTime(selectedMonthDate.year, selectedMonthDate.month + 1, 0);
        label = 'This Month';
        break;
    }

    final sales = allSales.where((sale) {
      final date = _resolveSaleDate(sale);
      if (date == null) {
        return false;
      }
      final normalized = DateTime(date.year, date.month, date.day);
      return !normalized.isBefore(start) && !normalized.isAfter(end);
    }).toList();

    final activeSales = sales
        .where((sale) => sale['isCancelled'] != true)
        .toList();

    return _FilteredSales(
      period: period,
      label: label,
      start: start,
      end: end,
      sales: sales,
      activeSales: activeSales,
    );
  }

  DateTime? _resolveSaleDate(Map<String, dynamic> sale) {
    final dateRaw = sale['date'] as String?;
    if (dateRaw != null && dateRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(dateRaw);
      if (parsed != null) {
        return parsed;
      }
      final withTime = DateTime.tryParse('${dateRaw}T00:00:00');
      if (withTime != null) {
        return withTime;
      }
    }

    final closedAtRaw = sale['closedAt'] as String?;
    if (closedAtRaw != null && closedAtRaw.isNotEmpty) {
      return DateTime.tryParse(closedAtRaw);
    }

    return null;
  }

  List<_MonthlyMenuCategorySummary> _generateMenuReport(
    List<Map<String, dynamic>> activeSales,
  ) {
    if (activeSales.isEmpty) {
      return const <_MonthlyMenuCategorySummary>[];
    }

    final lookup = _buildMenuItemLookup();
    final summaries = <String, _MonthlyMenuCategorySummary>{};

    for (final sale in activeSales) {
      final rawItems = sale['items'] as List?;
      if (rawItems == null || rawItems.isEmpty) {
        continue;
      }

      for (final rawItem in rawItems) {
        if (rawItem is! Map) {
          continue;
        }

        final item = rawItem.cast<String, dynamic>();
        final rawName = (item['itemName'] as String?)?.trim();
        if (rawName == null || rawName.isEmpty) {
          continue;
        }

        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        final total = (item['total'] as num?)?.toDouble();
        final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
        final effectiveTotal =
            total ?? (unitPrice * (quantity > 0 ? quantity : 1));
        if (quantity <= 0 && effectiveTotal <= 0) {
          continue;
        }

        final meta = _matchMenuItemMeta(rawName, lookup);
        final categoryName = meta?.categoryName ?? 'სხვა';
        final displayName = meta?.displayName ?? rawName;
        final subcategoryName = meta?.subcategoryName;

        final categorySummary = summaries.putIfAbsent(
          categoryName,
          () => _MonthlyMenuCategorySummary(categoryName: categoryName),
        );
        if (quantity > 0) {
          categorySummary.totalQuantity += quantity;
        }
        categorySummary.totalAmount += effectiveTotal;

        final itemSummary = categorySummary.items.putIfAbsent(
          displayName,
          () => _MonthlyMenuItemSummary(
            itemName: displayName,
            subcategoryName: subcategoryName,
          ),
        );
        if (quantity > 0) {
          itemSummary.quantity += quantity;
        }
        itemSummary.totalAmount += effectiveTotal;
      }
    }

    final result = summaries.values.toList()
      ..removeWhere((summary) => summary.items.isEmpty);

    for (final summary in result) {
      summary.totalAmount = double.parse(
        summary.totalAmount.toStringAsFixed(2),
      );
      for (final entry in summary.items.entries) {
        entry.value.totalAmount = double.parse(
          entry.value.totalAmount.toStringAsFixed(2),
        );
      }
    }

    result.sort((a, b) {
      final amountCompare = b.totalAmount.compareTo(a.totalAmount);
      if (amountCompare != 0) {
        return amountCompare;
      }
      return a.categoryName.compareTo(b.categoryName);
    });

    return result;
  }

  _SalesKpis _buildKpis({
    required List<Map<String, dynamic>> rawSales,
    required List<Map<String, dynamic>> activeSales,
    required List<_MonthlyMenuCategorySummary> summaries,
  }) {
    final revenue = activeSales.fold<double>(0.0, (sum, sale) {
      final total = sale['totalAmount'] ?? sale['total'];
      if (total is num) {
        return sum + total.toDouble();
      }
      if (total is String) {
        return sum + (double.tryParse(total) ?? 0.0);
      }
      return sum;
    });

    final totalItems = summaries.fold<int>(
      0,
      (sum, category) => sum + category.totalQuantity,
    );

    final transactions = activeSales.length;
    final cancelledCount = rawSales.length - transactions;

    final avgCheck = transactions == 0 ? 0.0 : revenue / transactions;
    final avgItemsPerTransaction = transactions == 0
        ? 0.0
        : totalItems / transactions;

    String topCategoryName = '-';
    double topCategoryRevenue = 0;
    if (summaries.isNotEmpty) {
      final top = summaries.first;
      topCategoryName = top.categoryName;
      topCategoryRevenue = top.totalAmount;
    }

    return _SalesKpis(
      revenue: revenue,
      transactions: transactions,
      cancelledCount: cancelledCount,
      totalSalesCount: rawSales.length,
      totalItems: totalItems,
      avgCheck: avgCheck,
      avgItemsPerTransaction: avgItemsPerTransaction,
      topCategoryName: topCategoryName,
      topCategoryRevenue: topCategoryRevenue,
    );
  }

  Map<String, _MenuItemMeta> _buildMenuItemLookup() {
    final lookup = <String, _MenuItemMeta>{};
    final categories = DatabaseService.getAllMenuCategories();

    for (final category in categories) {
      final categoryName = category.getName('ka').trim().isNotEmpty
          ? category.getName('ka').trim()
          : category.translationsEn['name'] ?? category.slug;

      final directItems = category.items ?? const <MenuItemDB>[];
      for (final item in directItems) {
        _addMenuItemToLookup(lookup, item, categoryName, null);
      }

      final subcategories =
          category.subcategories ?? const <MenuSubcategoryDB>[];
      for (final subcategory in subcategories) {
        final subcategoryName = subcategory.getName('ka').trim().isNotEmpty
            ? subcategory.getName('ka').trim()
            : subcategory.getName('en');
        for (final item in subcategory.items) {
          _addMenuItemToLookup(lookup, item, categoryName, subcategoryName);
        }
      }
    }

    return lookup;
  }

  void _addMenuItemToLookup(
    Map<String, _MenuItemMeta> lookup,
    MenuItemDB item,
    String categoryName,
    String? subcategoryName,
  ) {
    final nameKa = item.getName('ka').trim();
    final nameEn = item.getName('en').trim();

    if (item.hasVariants()) {
      for (final variant in item.variants!) {
        final sizeLabel = variant.getSizeLabel();
        _registerMenuItemNames(
          lookup: lookup,
          categoryName: categoryName,
          subcategoryName: subcategoryName,
          baseNameKa: nameKa,
          baseNameEn: nameEn,
          variantLabel: sizeLabel,
        );
      }
    }

    _registerMenuItemNames(
      lookup: lookup,
      categoryName: categoryName,
      subcategoryName: subcategoryName,
      baseNameKa: nameKa,
      baseNameEn: nameEn,
      variantLabel: null,
    );
  }

  void _registerMenuItemNames({
    required Map<String, _MenuItemMeta> lookup,
    required String categoryName,
    String? subcategoryName,
    required String baseNameKa,
    required String baseNameEn,
    String? variantLabel,
  }) {
    final baseKa = baseNameKa.trim();
    final baseEn = baseNameEn.trim();

    if (baseKa.isEmpty && baseEn.isEmpty) {
      return;
    }

    final displayBase = baseKa.isNotEmpty ? baseKa : baseEn;
    final displayName = variantLabel == null
        ? displayBase
        : '$displayBase • ${variantLabel.trim()}';

    final meta = _MenuItemMeta(
      categoryName: categoryName,
      subcategoryName: subcategoryName?.trim().isEmpty == true
          ? null
          : subcategoryName?.trim(),
      displayName: displayName,
    );

    final candidates = <String>{
      displayName,
      if (baseKa.isNotEmpty) baseKa,
      if (baseEn.isNotEmpty) baseEn,
      if (variantLabel != null && baseKa.isNotEmpty)
        '${baseKa.trim()} ${variantLabel.trim()}',
      if (variantLabel != null && baseKa.isNotEmpty)
        '${baseKa.trim()} (${variantLabel.trim()})',
      if (variantLabel != null && baseKa.isNotEmpty)
        '${baseKa.trim()}-${variantLabel.trim()}',
      if (variantLabel != null && baseEn.isNotEmpty)
        '${baseEn.trim()} ${variantLabel.trim()}',
      if (variantLabel != null && baseEn.isNotEmpty)
        '${baseEn.trim()} (${variantLabel.trim()})',
      if (variantLabel != null && baseEn.isNotEmpty)
        '${baseEn.trim()}-${variantLabel.trim()}',
    };

    for (final candidate in candidates) {
      _registerMenuNameKey(lookup, candidate, meta);
    }
  }

  void _registerMenuNameKey(
    Map<String, _MenuItemMeta> lookup,
    String? rawName,
    _MenuItemMeta meta,
  ) {
    if (rawName == null) {
      return;
    }
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final normalized = _normalizeMenuKey(trimmed);
    if (normalized.isEmpty) {
      return;
    }

    lookup.putIfAbsent(normalized, () => meta);

    final simplified = normalized.replaceAll(RegExp(r'[0-9]+'), '');
    if (simplified.isNotEmpty) {
      lookup.putIfAbsent(simplified, () => meta);
    }
  }

  _MenuItemMeta? _matchMenuItemMeta(
    String rawName,
    Map<String, _MenuItemMeta> lookup,
  ) {
    final normalized = _normalizeMenuKey(rawName);
    if (normalized.isEmpty) {
      return null;
    }

    final direct = lookup[normalized];
    if (direct != null) {
      return direct;
    }

    final simplified = normalized.replaceAll(RegExp(r'[0-9]+'), '');
    if (simplified.isNotEmpty && lookup.containsKey(simplified)) {
      return lookup[simplified];
    }

    for (final entry in lookup.entries) {
      final key = entry.key;
      if (normalized.contains(key) || key.contains(normalized)) {
        return entry.value;
      }
    }

    return null;
  }

  String _normalizeMenuKey(String input) {
    final lower = input.toLowerCase();
    final matches = RegExp(r'[a-z0-9ა-ჰ]+').allMatches(lower);
    if (matches.isEmpty) {
      return '';
    }
    return matches.map((match) => match.group(0)!).join();
  }

  Widget _buildMenuReportCard({
    required String periodLabel,
    required List<_MonthlyMenuCategorySummary> summaries,
    required double totalRevenue,
    required int totalQuantity,
    required bool isMobile,
  }) {
    if (summaries.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 3,
      shadowColor: _primary.withValues(alpha: 0.08),
      color: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'კატეგორიების დეტალური განაწილება',
                    style: TextStyle(
                      color: _text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$periodLabel • ${_money.format(totalRevenue)} • $totalQuantity ერთეული',
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            for (final summary in summaries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildCategoryTile(summary, totalRevenue, isMobile),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(
    _MonthlyMenuCategorySummary summary,
    double totalRevenue,
    bool isMobile,
  ) {
    final progress = totalRevenue <= 0
        ? 0.0
        : (summary.totalAmount / totalRevenue).clamp(0.0, 1.0);
    final items = summary.items.values.toList()
      ..sort((a, b) {
        final quantityCompare = b.quantity.compareTo(a.quantity);
        if (quantityCompare != 0) {
          return quantityCompare;
        }
        return b.totalAmount.compareTo(a.totalAmount);
      });

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE7FF)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: const Color(0xFFDDE7FF),
          expansionTileTheme: const ExpansionTileThemeData(
            tilePadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            childrenPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        child: ExpansionTile(
          title: Text(
            summary.categoryName,
            style: const TextStyle(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                '${summary.totalQuantity} ერთეული • ${_money.format(summary.totalAmount)}',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: const Color(0xFFE2E8F0),
                  color: _primary,
                ),
              ),
            ],
          ),
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Divider(
                  color: Color(0xFFDDE7FF),
                  height: 12,
                  thickness: 1,
                ),
              _buildMenuItemTile(items[i], summary.totalAmount, isMobile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItemTile(
    _MonthlyMenuItemSummary item,
    double categoryTotal,
    bool isMobile,
  ) {
    final share = categoryTotal <= 0
        ? 0.0
        : (item.totalAmount / categoryTotal) * 100;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (item.subcategoryName != null &&
                    item.subcategoryName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subcategoryName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: isMobile ? 80 : 110,
              maxWidth: isMobile ? 100 : 140,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.quantity} ცალი',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _money.format(item.totalAmount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!isMobile) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${share.toStringAsFixed(1)}% of category',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _getGeorgianMonthName(int month) {
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
    if (month < 1 || month > 12) {
      return 'უცნობი';
    }
    return months[month - 1];
  }
}

class _FilteredSales {
  const _FilteredSales({
    required this.period,
    required this.label,
    required this.start,
    required this.end,
    required this.sales,
    required this.activeSales,
  });

  final _SalesPeriod period;
  final String label;
  final DateTime start;
  final DateTime end;
  final List<Map<String, dynamic>> sales;
  final List<Map<String, dynamic>> activeSales;
}

class _MenuItemMeta {
  _MenuItemMeta({
    required this.categoryName,
    required this.displayName,
    this.subcategoryName,
  });

  final String categoryName;
  final String displayName;
  final String? subcategoryName;
}

class _MonthlyMenuCategorySummary {
  _MonthlyMenuCategorySummary({required this.categoryName});

  final String categoryName;
  final Map<String, _MonthlyMenuItemSummary> items = {};
  int totalQuantity = 0;
  double totalAmount = 0.0;
}

class _MonthlyMenuItemSummary {
  _MonthlyMenuItemSummary({required this.itemName, this.subcategoryName});

  final String itemName;
  final String? subcategoryName;
  int quantity = 0;
  double totalAmount = 0.0;
}

class _SalesKpis {
  const _SalesKpis({
    required this.revenue,
    required this.transactions,
    required this.cancelledCount,
    required this.totalSalesCount,
    required this.totalItems,
    required this.avgCheck,
    required this.avgItemsPerTransaction,
    required this.topCategoryName,
    required this.topCategoryRevenue,
  });

  final double revenue;
  final int transactions;
  final int cancelledCount;
  final int totalSalesCount;
  final int totalItems;
  final double avgCheck;
  final double avgItemsPerTransaction;
  final String topCategoryName;
  final double topCategoryRevenue;
}
