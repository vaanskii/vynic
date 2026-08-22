import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/payment_utils.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

typedef SalesActionCallback = Future<void> Function(Map<String, dynamic> sale);

class AdminSalesSection extends StatefulWidget {
  const AdminSalesSection({
    super.key,
    required this.onReprintSaleReceipt,
    required this.onReprintFullSaleReceipt,
    required this.onConfirmCancelSale,
    required this.onRestoreClosedSale,
  });

  final SalesActionCallback onReprintSaleReceipt;
  final SalesActionCallback onReprintFullSaleReceipt;
  final SalesActionCallback onConfirmCancelSale;
  final SalesActionCallback onRestoreClosedSale;

  @override
  State<AdminSalesSection> createState() => _AdminSalesSectionState();
}

class _AdminSalesSectionState extends State<AdminSalesSection> {
  static const Color _primaryColor = AdminDesign.accentDark;
  static const Color _surfaceColor = AdminDesign.panelSoft;
  static const Color _cardColor = AdminDesign.panel;
  static const Color _borderColor = AdminDesign.border;
  static const Color _textPrimary = AdminDesign.text;
  static const Color _textMuted = AdminDesign.muted;

  late int _selectedSalesYear;
  late int _selectedSalesMonth;

  @override
  void initState() {
    super.initState();
    final availableMonths = _getAvailableOrderMonths();
    final currentBusinessDate = DatabaseService.getCurrentDate();
    final initialMonth = availableMonths.isNotEmpty
        ? availableMonths.first
        : DateTime(currentBusinessDate.year, currentBusinessDate.month, 1);
    _selectedSalesYear = initialMonth.year;
    _selectedSalesMonth = initialMonth.month;
  }

  List<DateTime> _getAvailableOrderMonths() {
    final months = <DateTime>{};
    final allSales = DatabaseService.getAllSales();
    for (final sale in allSales) {
      final dateString = sale['date'] as String?;
      if (dateString == null || dateString.isEmpty) {
        continue;
      }
      try {
        final parsed = DateTime.parse(dateString);
        months.add(DateTime(parsed.year, parsed.month, 1));
      } catch (_) {}
    }

    final sortedMonths = months.toList()..sort((a, b) => b.compareTo(a));
    return sortedMonths;
  }

  void _changeSalesMonth(int delta, List<DateTime> availableMonths) {
    if (availableMonths.isEmpty) {
      return;
    }
    final selected = DateTime(_selectedSalesYear, _selectedSalesMonth, 1);
    final currentIndex = availableMonths.indexWhere(
      (month) => month.year == selected.year && month.month == selected.month,
    );
    if (currentIndex == -1) {
      final fallback = availableMonths.first;
      setState(() {
        _selectedSalesYear = fallback.year;
        _selectedSalesMonth = fallback.month;
      });
      return;
    }

    final targetIndex = currentIndex + delta;
    if (targetIndex < 0 || targetIndex >= availableMonths.length) {
      return;
    }

    final updated = availableMonths[targetIndex];

    setState(() {
      _selectedSalesYear = updated.year;
      _selectedSalesMonth = updated.month;
    });
  }

  void _setSelectedSalesMonth(DateTime month, List<DateTime> availableMonths) {
    final sanitized = DateTime(month.year, month.month, 1);
    final exists = availableMonths.any(
      (entry) => entry.year == sanitized.year && entry.month == sanitized.month,
    );
    if (!exists) {
      return;
    }

    setState(() {
      _selectedSalesYear = sanitized.year;
      _selectedSalesMonth = sanitized.month;
    });
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

  String _formatDateNumeric(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }

  double _resolveSaleTotal(Map<String, dynamic> sale) {
    final totalAmount = sale['totalAmount'];
    if (totalAmount is num) {
      return totalAmount.toDouble();
    }
    final total = sale['total'];
    if (total is num) {
      return total.toDouble();
    }
    final parsedTotalAmount = totalAmount != null
        ? double.tryParse(totalAmount.toString())
        : null;
    if (parsedTotalAmount != null) {
      return parsedTotalAmount;
    }
    final parsedTotal = total != null
        ? double.tryParse(total.toString())
        : null;
    return parsedTotal ?? 0.0;
  }

  double _resolveAppliedAdvanceFromSale(Map<String, dynamic> sale) {
    double parseNum(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      if (value == null) {
        return 0.0;
      }
      return double.tryParse(value.toString()) ?? 0.0;
    }

    final finalTransaction = sale['finalTransaction'];
    if (finalTransaction is Map) {
      final discount = parseNum(finalTransaction['discount']);
      if (discount > 0) {
        return discount;
      }
    }

    final discountAmount = parseNum(sale['discountAmount']);
    if (discountAmount > 0) {
      return discountAmount;
    }

    return 0.0;
  }

  double _expenseForDate(String date) {
    return DatabaseService.getExpenseTotalForDate(date);
  }

  bool _isFiscalSale(Map<String, dynamic> sale) {
    if (sale['isFiscal'] == false) {
      return false;
    }
    final dynamic paymentMethodRaw = sale['paymentMethod'];
    final String? paymentMethod = paymentMethodRaw != null
        ? paymentMethodRaw.toString()
        : null;
    if (paymentMethod == PaymentUtils.methodNonFiscal) {
      return false;
    }
    return true;
  }

  bool _isAdvanceSale(Map<String, dynamic> sale) {
    final dynamic paymentMethodRaw = sale['paymentMethod'];
    final String paymentMethod = paymentMethodRaw?.toString() ?? '';
    return PaymentUtils.normalizeMethodKey(paymentMethod) ==
        PaymentUtils.methodAdvance;
  }

  Map<String, double> _aggregatePaymentTotals(
    List<Map<String, dynamic>> sales,
  ) {
    final totals = <String, double>{};
    for (final sale in sales) {
      if (!_isFiscalSale(sale)) {
        continue;
      }
      final breakdown = PaymentUtils.extractBreakdown(sale);
      if (breakdown.isEmpty) {
        final amount = _resolveSaleTotal(sale);
        if (amount <= 0) {
          continue;
        }
        totals['Unknown'] = (totals['Unknown'] ?? 0) + amount;
        continue;
      }

      breakdown.forEach((methodKey, amount) {
        final label = PaymentUtils.methodLabel(methodKey);
        totals[label] = (totals[label] ?? 0) + amount;
      });
    }

    return totals;
  }

  List<Map<String, dynamic>> _resolveSaleItems(Map<String, dynamic> sale) {
    List<Map<String, dynamic>> parseItems(dynamic rawItems) {
      if (rawItems is! List) {
        return const [];
      }

      return rawItems.whereType<Map>().map((raw) {
        return {
          'itemName': raw['itemName'] ?? raw['name'] ?? 'უცნობი პოზიცია',
          'quantity': (raw['quantity'] as num?)?.toInt() ?? 0,
          'total': (raw['total'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList();
    }

    final directItems = parseItems(sale['items']);
    if (directItems.isNotEmpty) {
      return directItems;
    }

    final finalTransaction = sale['finalTransaction'];
    if (finalTransaction is Map) {
      return parseItems(finalTransaction['items']);
    }

    return const [];
  }

  Future<void> _showSaleItemsModal(Map<String, dynamic> sale) async {
    final items = _resolveSaleItems(sale);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: AdminDesign.panelSoft,
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: _borderColor)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: _textPrimary,
                      ),
                      Expanded(
                        child: Text(
                          'შეკვეთა #${sale['orderId']} - პოზიციები',
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Text(
                            'პოზიციები ვერ მოიძებნა',
                            style: TextStyle(
                              color: _textMuted,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final qty =
                                (item['quantity'] as num?)?.toInt() ?? 0;
                            final name =
                                item['itemName']?.toString() ??
                                'უცნობი პოზიცია';
                            final total =
                                (item['total'] as num?)?.toDouble() ?? 0.0;

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: AdminDesign.accentSoft,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AdminDesign.accentSoftBorder,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        qty.toString(),
                                        style: const TextStyle(
                                          color: _primaryColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        color: _textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '₾${total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontSize: 14,
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
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textMuted, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    Color accent = _primaryColor,
  }) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPercent(double value) {
    return '${value.toStringAsFixed(1)}%';
  }

  bool _isRestoredSale(Map<String, dynamic> sale) {
    return sale['restoredToOrder'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    final allSales = DatabaseService.getAllSales();
    final currentBusinessDate = DatabaseService.getCurrentDate();
    final todayDate = currentBusinessDate.toIso8601String().split('T')[0];
    final todaySales = allSales
        .where(
          (sale) =>
              sale['date'] == todayDate &&
              sale['isCancelled'] != true &&
              !_isRestoredSale(sale),
        )
        .toList();
    final todayFiscalSales = todaySales.where(_isFiscalSale).toList();
    final todayNonFiscalSales = todaySales
        .where((sale) => !_isFiscalSale(sale))
        .toList();
    final todayAdvanceSales = todayNonFiscalSales
        .where(_isAdvanceSale)
        .toList();
    final todayOperationalNonFiscalSales = todayNonFiscalSales
        .where((sale) => !_isAdvanceSale(sale))
        .toList();
    final todayFiscalTotal = todayFiscalSales.fold<double>(
      0,
      (sum, sale) => sum + _resolveSaleTotal(sale),
    );
    final todayNonFiscalTotal = todayOperationalNonFiscalSales.fold<double>(
      0,
      (sum, sale) => sum + _resolveSaleTotal(sale),
    );
    final todayAdvanceTotal = todayAdvanceSales.fold<double>(
      0,
      (sum, sale) => sum + _resolveSaleTotal(sale),
    );
    final todayAppliedAdvanceFromTables = todayFiscalSales.fold<double>(
      0,
      (sum, sale) => sum + _resolveAppliedAdvanceFromSale(sale),
    );
    final todayCombinedTotal = todayFiscalTotal + todayNonFiscalTotal;
    final todayTablesGrossTotal =
        todayCombinedTotal + todayAppliedAdvanceFromTables;
    final todayExpenses = _expenseForDate(todayDate);
    final todayProfit = todayCombinedTotal - todayExpenses;

    final selectedMonthDate = DateTime(_selectedSalesYear, _selectedSalesMonth);
    final monthPrefix =
        '${selectedMonthDate.year.toString().padLeft(4, '0')}-${selectedMonthDate.month.toString().padLeft(2, '0')}';
    final monthlySales = allSales.where((sale) {
      final inMonth =
          (sale['date'] as String?)?.startsWith(monthPrefix) ?? false;
      return inMonth && !_isRestoredSale(sale);
    }).toList();
    final monthlyActiveSales = monthlySales
        .where((sale) => sale['isCancelled'] != true)
        .toList();
    final monthlyAdvanceSales = monthlyActiveSales
        .where(_isAdvanceSale)
        .toList();
    final monthlyCoreActiveSales = monthlyActiveSales
        .where((sale) => !_isAdvanceSale(sale))
        .toList();
    final monthlyActiveCount = monthlyCoreActiveSales.length;
    final monthlyFiscalSales = monthlyCoreActiveSales
        .where(_isFiscalSale)
        .toList();
    final monthlyFiscalCount = monthlyFiscalSales.length;
    final monthlyTotal = monthlyFiscalSales.fold<double>(
      0,
      (sum, sale) => sum + _resolveSaleTotal(sale),
    );
    final monthlyNonFiscalSales = monthlyCoreActiveSales
        .where((sale) => !_isFiscalSale(sale))
        .toList();
    final monthlyNonFiscalCount = monthlyNonFiscalSales.length;
    final monthlyNonFiscalTotal = monthlyNonFiscalSales.fold<double>(
      0,
      (sum, sale) => sum + _resolveSaleTotal(sale),
    );
    final monthlyAdvanceTotal = monthlyAdvanceSales.fold<double>(
      0,
      (sum, sale) => sum + _resolveSaleTotal(sale),
    );
    final monthlyAppliedAdvanceFromTables = monthlyFiscalSales.fold<double>(
      0,
      (sum, sale) => sum + _resolveAppliedAdvanceFromSale(sale),
    );
    final monthlyCombinedTotal = monthlyTotal + monthlyNonFiscalTotal;
    final monthlyTablesGrossTotal =
        monthlyCombinedTotal + monthlyAppliedAdvanceFromTables;
    final monthlyExpenseDates = <String>{};
    for (final sale in monthlyCoreActiveSales) {
      final date = (sale['date'] as String?) ?? '';
      if (date.isNotEmpty) monthlyExpenseDates.add(date);
    }
    final monthlyExpenses = monthlyExpenseDates.fold<double>(
      0.0,
      (sum, date) => sum + _expenseForDate(date),
    );
    final monthlyProfit = monthlyCombinedTotal - monthlyExpenses;
    final monthlyCancelled = monthlySales.length - monthlyActiveSales.length;
    final averageOrderValue = monthlyActiveCount == 0
        ? 0.0
        : monthlyCombinedTotal / monthlyActiveCount;
    final cancellationRate = monthlySales.isEmpty
        ? 0.0
        : (monthlyCancelled / monthlySales.length) * 100;
    final nonFiscalRate = monthlyCombinedTotal <= 0
        ? 0.0
        : (monthlyNonFiscalTotal / monthlyCombinedTotal) * 100;
    final averageItemsPerOrder = monthlyActiveCount == 0
        ? 0.0
        : monthlyCoreActiveSales.fold<double>(0, (sum, sale) {
                final items = sale['items'];
                if (items is List) {
                  return sum + items.length;
                }
                return sum;
              }) /
              monthlyActiveCount;

    final paymentBreakdown = _aggregatePaymentTotals(monthlyFiscalSales);
    final paymentBreakdownEntries = paymentBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topPaymentMethod = paymentBreakdownEntries.isEmpty
        ? null
        : paymentBreakdownEntries.first;
    final topPaymentShare = (topPaymentMethod != null && monthlyTotal > 0)
        ? (topPaymentMethod.value / monthlyTotal) * 100
        : 0.0;

    final activeSalesByDate = <String, double>{};
    for (final sale in monthlyCoreActiveSales) {
      final date = sale['date'] as String?;
      if (date == null || date.isEmpty) {
        continue;
      }
      activeSalesByDate[date] =
          (activeSalesByDate[date] ?? 0) + _resolveSaleTotal(sale);
    }
    final topDateEntry = activeSalesByDate.entries.isEmpty
        ? null
        : (activeSalesByDate.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;

    final endOfMonth = DateTime(
      selectedMonthDate.year,
      selectedMonthDate.month + 1,
      0,
    );
    final monthOptions = _getAvailableOrderMonths();
    final selectedMonthInOptions = monthOptions.any(
      (m) =>
          m.year == selectedMonthDate.year &&
          m.month == selectedMonthDate.month,
    );
    final effectiveSelectedMonth =
        selectedMonthInOptions && monthOptions.isNotEmpty
        ? selectedMonthDate
        : (monthOptions.isNotEmpty ? monthOptions.first : selectedMonthDate);

    if (!selectedMonthInOptions && monthOptions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedSalesYear = monthOptions.first.year;
          _selectedSalesMonth = monthOptions.first.month;
        });
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

    final salesByDate = <String, List<Map<String, dynamic>>>{};
    for (final sale in monthlySales) {
      final date = sale['date'] as String;
      salesByDate.putIfAbsent(date, () => []).add(sale);
    }

    final dates = salesByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return SizedBox.expand(
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 22,
            isMobile ? 16 : 18,
            isMobile ? 16 : 22,
            24,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminSectionHeader(
                  icon: Icons.history_outlined,
                  title: 'გაყიდვების ისტორია',
                  subtitle:
                      'დღიური და თვიური ოპერაციები, გადახდები, გაუქმებები და ჩეკის ხელახალი ბეჭდვა.',
                  badge: AdminStatusBadge(
                    icon: Icons.receipt_long_outlined,
                    label: '$monthlyActiveCount აქტიური',
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  color: _cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AdminDesign.radius),
                    side: const BorderSide(color: _borderColor),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'დღევანდელი გაყიდვები',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: isMobile ? 18 : 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: isMobile ? 12 : 16),
                        isMobile
                            ? Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatCard(
                                          icon: Icons.receipt_long,
                                          label: 'შეკვეთები',
                                          value:
                                              '${todayFiscalSales.length} / ${todayOperationalNonFiscalSales.length}',
                                          color: AdminTones.infoText,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          icon: Icons.attach_money,
                                          label: 'ფისკალური',
                                          value:
                                              '₾${todayFiscalTotal.toStringAsFixed(2)}',
                                          color: AdminTones.successText,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatCard(
                                          icon: Icons.shield_outlined,
                                          label: 'არაფისკალური',
                                          value:
                                              '₾${todayNonFiscalTotal.toStringAsFixed(2)}',
                                          color: AdminTones.warningText,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          icon: Icons.summarize_outlined,
                                          label: 'სრული',
                                          value:
                                              '₾${todayCombinedTotal.toStringAsFixed(2)}',
                                          color: AdminDesign.accentDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Icons.receipt_long,
                                      label:
                                          'შეკვეთები (ფისკალური / არაფისკალური)',
                                      value:
                                          '${todayFiscalSales.length} / ${todayOperationalNonFiscalSales.length}',
                                      color: AdminTones.infoText,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Icons.attach_money,
                                      label: 'ფისკალური თანხა',
                                      value:
                                          '₾${todayFiscalTotal.toStringAsFixed(2)}',
                                      color: AdminTones.successText,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Icons.shield_outlined,
                                      label: 'არაფისკალური თანხა',
                                      value:
                                          '₾${todayNonFiscalTotal.toStringAsFixed(2)}',
                                      color: AdminTones.warningText,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Icons.summarize_outlined,
                                      label: 'სრული თანხა',
                                      value:
                                          '₾${todayCombinedTotal.toStringAsFixed(2)}',
                                      color: AdminDesign.accentDark,
                                    ),
                                  ),
                                ],
                              ),
                        if (todayAdvanceTotal > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              'ავანსი (ჯამში არ შედის): ₾${todayAdvanceTotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: AdminTones.warningText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (todayAppliedAdvanceFromTables > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'სუფრების სრული თანხა (ავანსით): ₾${todayTablesGrossTotal.toStringAsFixed(2)}  =  გადახდილი ₾${todayCombinedTotal.toStringAsFixed(2)} + ავანსი ₾${todayAppliedAdvanceFromTables.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: AdminDesign.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'სულ ხარჯი: ₾${todayExpenses.toStringAsFixed(2)} • მოგება: ₾${todayProfit.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: AdminDesign.accentDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  color: _cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AdminDesign.radius),
                    side: const BorderSide(color: _borderColor),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        isMobile
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'თვიური შეჯამება',
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: isMobile ? 18 : 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_getGeorgianMonthName(effectiveSelectedMonth.month)} ${effectiveSelectedMonth.year}',
                                    style: const TextStyle(
                                      color: _textMuted,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      IconButton(
                                        onPressed: isPrevDisabled
                                            ? null
                                            : () => _changeSalesMonth(
                                                -1,
                                                monthOptions,
                                              ),
                                        icon: const Icon(Icons.chevron_left),
                                        color: _primaryColor,
                                      ),
                                      Expanded(
                                        child: DropdownButtonHideUnderline(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _surfaceColor,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _borderColor,
                                              ),
                                            ),
                                            child: DropdownButton<DateTime>(
                                              isExpanded: true,
                                              value: monthOptions.isNotEmpty
                                                  ? effectiveSelectedMonth
                                                  : null,
                                              items: monthOptions.map((
                                                monthDate,
                                              ) {
                                                final label =
                                                    '${_getGeorgianMonthName(monthDate.month)} ${monthDate.year}';
                                                return DropdownMenuItem<
                                                  DateTime
                                                >(
                                                  value: monthDate,
                                                  child: Text(
                                                    label,
                                                    style: const TextStyle(
                                                      color: _textPrimary,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (value) {
                                                if (value != null)
                                                  _setSelectedSalesMonth(
                                                    value,
                                                    monthOptions,
                                                  );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: isNextDisabled
                                            ? null
                                            : () => _changeSalesMonth(
                                                1,
                                                monthOptions,
                                              ),
                                        icon: const Icon(Icons.chevron_right),
                                        color: _primaryColor,
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'თვიური შეჯამება',
                                          style: TextStyle(
                                            color: _textPrimary,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_getGeorgianMonthName(effectiveSelectedMonth.month)} ${effectiveSelectedMonth.year} • ${_formatDateNumeric(effectiveSelectedMonth)} - ${_formatDateNumeric(endOfMonth)}',
                                          style: const TextStyle(
                                            color: _textMuted,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: isPrevDisabled
                                            ? null
                                            : () => _changeSalesMonth(
                                                -1,
                                                monthOptions,
                                              ),
                                        icon: const Icon(Icons.chevron_left),
                                        color: _primaryColor,
                                        disabledColor: AdminDesign.muted,
                                      ),
                                      const SizedBox(width: 8),
                                      DropdownButtonHideUnderline(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _surfaceColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: _borderColor,
                                            ),
                                          ),
                                          child: DropdownButton<DateTime>(
                                            value: monthOptions.isNotEmpty
                                                ? effectiveSelectedMonth
                                                : null,
                                            dropdownColor: Colors.white,
                                            iconEnabledColor: _primaryColor,
                                            iconDisabledColor: AdminDesign.muted,
                                            style: const TextStyle(
                                              color: _textPrimary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            items: monthOptions.map((
                                              monthDate,
                                            ) {
                                              final label =
                                                  '${_getGeorgianMonthName(monthDate.month)} ${monthDate.year}';
                                              return DropdownMenuItem<DateTime>(
                                                value: monthDate,
                                                child: Text(
                                                  label,
                                                  style: const TextStyle(
                                                    color: _textPrimary,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (value) {
                                              if (value != null) {
                                                _setSelectedSalesMonth(
                                                  value,
                                                  monthOptions,
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        onPressed: isNextDisabled
                                            ? null
                                            : () => _changeSalesMonth(
                                                1,
                                                monthOptions,
                                              ),
                                        icon: const Icon(Icons.chevron_right),
                                        color: _primaryColor,
                                        disabledColor: AdminDesign.muted,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                        const SizedBox(height: 24),
                        isMobile
                            ? Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatCard(
                                          icon: Icons.receipt_long,
                                          label: 'შეკვეთები',
                                          value:
                                              '${monthlyFiscalCount} / ${monthlyNonFiscalCount}',
                                          color: AdminTones.infoText,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          icon: Icons.attach_money,
                                          label: 'ფისკალური',
                                          value:
                                              '₾${monthlyTotal.toStringAsFixed(2)}',
                                          color: AdminTones.successText,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatCard(
                                          icon: Icons.shield_outlined,
                                          label: 'არაფისკალური',
                                          value:
                                              '₾${monthlyNonFiscalTotal.toStringAsFixed(2)}',
                                          color: AdminTones.warningText,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          icon: Icons.summarize_outlined,
                                          label: 'სრული',
                                          value:
                                              '₾${monthlyCombinedTotal.toStringAsFixed(2)}',
                                          color: AdminDesign.accentDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Icons.receipt_long,
                                      label:
                                          'შეკვეთები (ფისკალური / არაფისკალური)',
                                      value:
                                          '${monthlyFiscalCount.toString()} / ${monthlyNonFiscalCount.toString()}',
                                      color: AdminTones.infoText,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Icons.attach_money,
                                      label: 'ფისკალური თანხა',
                                      value:
                                          '₾${monthlyTotal.toStringAsFixed(2)}',
                                      color: AdminTones.successText,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Icons.shield_outlined,
                                      label: 'არაფისკალური თანხა',
                                      value:
                                          '₾${monthlyNonFiscalTotal.toStringAsFixed(2)}',
                                      color: AdminTones.warningText,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      icon: Icons.summarize_outlined,
                                      label: 'სრული თანხა',
                                      value:
                                          '₾${monthlyCombinedTotal.toStringAsFixed(2)}',
                                      color: AdminDesign.accentDark,
                                    ),
                                  ),
                                ],
                              ),
                        if (monthlyAdvanceTotal > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              'ავანსი (ჯამში არ შედის): ₾${monthlyAdvanceTotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: AdminTones.warningText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (monthlyAppliedAdvanceFromTables > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'სუფრების სრული თანხა (ავანსით): ₾${monthlyTablesGrossTotal.toStringAsFixed(2)}  =  გადახდილი ₾${monthlyCombinedTotal.toStringAsFixed(2)} + ავანსი ₾${monthlyAppliedAdvanceFromTables.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: AdminDesign.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'სულ ხარჯი: ₾${monthlyExpenses.toStringAsFixed(2)} • მოგება: ₾${monthlyProfit.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: AdminDesign.accentDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.shopping_bag,
                                label: monthlyCancelled > 0
                                    ? 'შეკვეთები (აქტიური/სულ)'
                                    : 'აქტიური შეკვეთები',
                                value: monthlyCancelled > 0
                                    ? '$monthlyActiveCount / ${monthlySales.length}'
                                    : '$monthlyActiveCount',
                                color: AdminTones.infoText,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.show_chart,
                                label: 'საშუალო შეკვეთა',
                                value:
                                    '₾${averageOrderValue.toStringAsFixed(2)}',
                                color: AdminDesign.accentDark,
                              ),
                            ),
                          ],
                        ),
                        if (monthlyCancelled > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              'გაუქმებული შეკვეთები: $monthlyCancelled',
                              style: TextStyle(
                                color: AdminTones.warningText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (paymentBreakdown.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'გადახდის მეთოდები',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: paymentBreakdownEntries.map((
                                    entry,
                                  ) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _surfaceColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: _borderColor),
                                      ),
                                      child: Text(
                                        '${entry.key}: ₾${entry.value.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: _textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        if (monthlySales.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ინსაითები',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    SizedBox(
                                      width: isMobile ? double.infinity : 260,
                                      child: _buildInsightCard(
                                        icon: Icons.event_available_outlined,
                                        title: 'საუკეთესო დღე',
                                        value: topDateEntry == null
                                            ? 'მონაცემი არ არის'
                                            : '${topDateEntry.key} • ₾${topDateEntry.value.toStringAsFixed(2)}',
                                        subtitle:
                                            'ყველაზე მაღალი დღიური ამონაგები',
                                        accent: AdminDesign.accentDark,
                                      ),
                                    ),
                                    SizedBox(
                                      width: isMobile ? double.infinity : 260,
                                      child: _buildInsightCard(
                                        icon: Icons.pie_chart_outline,
                                        title: 'არაფისკალური წილი',
                                        value: _formatPercent(nonFiscalRate),
                                        subtitle:
                                            'არაფისკალური ₾${monthlyNonFiscalTotal.toStringAsFixed(2)} / სრული ₾${monthlyCombinedTotal.toStringAsFixed(2)}',
                                        accent: AdminTones.warningText,
                                      ),
                                    ),
                                    SizedBox(
                                      width: isMobile ? double.infinity : 260,
                                      child: _buildInsightCard(
                                        icon: Icons.cancel_outlined,
                                        title: 'გაუქმების მაჩვენებელი',
                                        value: _formatPercent(cancellationRate),
                                        subtitle:
                                            '$monthlyCancelled გაუქმებული / ${monthlySales.length} სულ',
                                        accent: AdminDesign.danger,
                                      ),
                                    ),
                                    SizedBox(
                                      width: isMobile ? double.infinity : 260,
                                      child: _buildInsightCard(
                                        icon: Icons
                                            .shopping_cart_checkout_outlined,
                                        title: 'საშ. პოზიციები შეკვეთაში',
                                        value: averageItemsPerOrder
                                            .toStringAsFixed(1),
                                        subtitle:
                                            'აქტიური შეკვეთები: $monthlyActiveCount',
                                        accent: AdminTones.infoText,
                                      ),
                                    ),
                                    SizedBox(
                                      width: isMobile ? double.infinity : 260,
                                      child: _buildInsightCard(
                                        icon: Icons
                                            .account_balance_wallet_outlined,
                                        title: 'წამყვანი გადახდის მეთოდი',
                                        value: topPaymentMethod == null
                                            ? 'მონაცემი არ არის'
                                            : '${topPaymentMethod.key} • ₾${topPaymentMethod.value.toStringAsFixed(2)}',
                                        subtitle: topPaymentMethod == null
                                            ? 'ამ თვეში ფისკალური გაყიდვები არ არის'
                                            : 'ფისკალური ბრუნვის ${_formatPercent(topPaymentShare)}',
                                        accent: AdminDesign.accentDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        if (monthlyActiveCount == 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                              'ამ თვეში აქტიური გაყიდვები არ ფიქსირდება.',
                              style: TextStyle(color: _textMuted, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (dates.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48.0),
                      child: Text(
                        'გაყიდვები ჯერ არ არის დაფიქსირებული',
                        style: TextStyle(color: _textMuted, fontSize: 16),
                      ),
                    ),
                  )
                else
                  ...dates.map((date) {
                    final dateSales = salesByDate[date]!;
                    final activeSales = dateSales
                        .where((sale) => sale['isCancelled'] != true)
                        .toList();
                    final advanceSalesForDate = activeSales
                        .where(_isAdvanceSale)
                        .toList();
                    final coreActiveSalesForDate = activeSales
                        .where((sale) => !_isAdvanceSale(sale))
                        .toList();
                    final activeCount = coreActiveSalesForDate.length;
                    final cancelledCount =
                        dateSales.length - activeSales.length;
                    final fiscalSalesForDate = coreActiveSalesForDate
                        .where(_isFiscalSale)
                        .toList();
                    final nonFiscalSalesForDate = coreActiveSalesForDate
                        .where((sale) => !_isFiscalSale(sale))
                        .toList();
                    final dateTotal = fiscalSalesForDate.fold<double>(
                      0,
                      (sum, sale) => sum + _resolveSaleTotal(sale),
                    );
                    final nonFiscalDateTotal = nonFiscalSalesForDate
                        .fold<double>(
                          0,
                          (sum, sale) => sum + _resolveSaleTotal(sale),
                        );
                    advanceSalesForDate.fold<double>(
                      0,
                      (sum, sale) => sum + _resolveSaleTotal(sale),
                    );
                    fiscalSalesForDate.fold<double>(
                      0,
                      (sum, sale) => sum + _resolveAppliedAdvanceFromSale(sale),
                    );
                    final dateCombinedTotal = dateTotal + nonFiscalDateTotal;
                    final dateExpenses = _expenseForDate(date);
                    final dateProfit = dateCombinedTotal - dateExpenses;
                    final dateAverageOrderValue = activeCount == 0
                        ? 0.0
                        : dateCombinedTotal / activeCount;
                    final dateCancellationRate = dateSales.isEmpty
                        ? 0.0
                        : (cancelledCount / dateSales.length) * 100;
                    final dateAvgItems = activeCount == 0
                        ? 0.0
                        : coreActiveSalesForDate.fold<double>(0, (sum, sale) {
                                final items = sale['items'];
                                if (items is List) {
                                  return sum + items.length;
                                }
                                return sum;
                              }) /
                              activeCount;
                    _aggregatePaymentTotals(fiscalSalesForDate);
                    final dateObj = DateTime.parse(date);
                    final georgianDate =
                        DatabaseService.getGeorgianFormattedDate(dateObj);

                    return Card(
                      color: _cardColor,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: _borderColor),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                          splashColor: _primaryColor.withOpacity(0.06),
                          colorScheme: const ColorScheme.light(),
                        ),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 24,
                            vertical: 8,
                          ),
                          childrenPadding: EdgeInsets.all(isMobile ? 12 : 20),
                          iconColor: _primaryColor,
                          collapsedIconColor: _textMuted,
                          leading: const Icon(
                            Icons.calendar_month_outlined,
                            color: _primaryColor,
                            size: 28,
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                georgianDate,
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                date,
                                style: const TextStyle(
                                  color: _textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              cancelledCount > 0
                                  ? 'აქტიური $activeCount / სულ ${dateSales.length} • ₾${dateCombinedTotal.toStringAsFixed(2)} • ხარჯი ₾${dateExpenses.toStringAsFixed(2)} • მოგება ₾${dateProfit.toStringAsFixed(2)}'
                                  : '$activeCount შეკვეთა • ₾${dateCombinedTotal.toStringAsFixed(2)} • ხარჯი ₾${dateExpenses.toStringAsFixed(2)} • მოგება ₾${dateProfit.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: _primaryColor,
                                fontSize: isMobile ? 12 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                SizedBox(
                                  width: isMobile ? double.infinity : 260,
                                  child: _buildInsightCard(
                                    icon: Icons.show_chart,
                                    title: 'საშუალო შეკვეთა',
                                    value:
                                        '₾${dateAverageOrderValue.toStringAsFixed(2)}',
                                    subtitle: 'აქტიური შეკვეთები: $activeCount',
                                    accent: AdminDesign.accentDark,
                                  ),
                                ),
                                SizedBox(
                                  width: isMobile ? double.infinity : 260,
                                  child: _buildInsightCard(
                                    icon: Icons.pie_chart_outline,
                                    title: 'არაფისკალური წილი',
                                    value: dateCombinedTotal <= 0
                                        ? '0.0%'
                                        : _formatPercent(
                                            (nonFiscalDateTotal /
                                                    dateCombinedTotal) *
                                                100,
                                          ),
                                    subtitle:
                                        'არაფისკალური ₾${nonFiscalDateTotal.toStringAsFixed(2)}',
                                    accent: AdminTones.warningText,
                                  ),
                                ),
                                SizedBox(
                                  width: isMobile ? double.infinity : 260,
                                  child: _buildInsightCard(
                                    icon: Icons.cancel_outlined,
                                    title: 'გაუქმების მაჩვენებელი',
                                    value: _formatPercent(dateCancellationRate),
                                    subtitle:
                                        '$cancelledCount გაუქმებული / ${dateSales.length} სულ',
                                    accent: AdminDesign.danger,
                                  ),
                                ),
                                SizedBox(
                                  width: isMobile ? double.infinity : 260,
                                  child: _buildInsightCard(
                                    icon: Icons.shopping_cart_checkout_outlined,
                                    title: 'საშ. პოზიციები შეკვეთაში',
                                    value: dateAvgItems.toStringAsFixed(1),
                                    subtitle:
                                        'დღის აქტიური შეკვეთების მიხედვით',
                                    accent: AdminTones.infoText,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ...dateSales.map((sale) {
                              final tableNumbers =
                                  (sale['tableNumbers'] as List).cast<String>();
                              final discountAmount =
                                  (sale['discountAmount'] as num?)
                                      ?.toDouble() ??
                                  0.0;
                              final advanceAmount =
                                  (sale['advanceAmount'] as num?)?.toDouble() ??
                                  discountAmount;
                              final breakdown = PaymentUtils.extractBreakdown(
                                sale,
                              );
                              final paymentDisplay = sale['isCancelled'] == true
                                  ? 'გაუქმებული'
                                  : PaymentUtils.formatPaymentDisplay(sale);
                              final orderTotal = _resolveSaleTotal(sale);
                              final bool isCancelled =
                                  sale['isCancelled'] == true;
                              final bool isRestored =
                                  sale['restoredToOrder'] == true;
                              final bool canRestore =
                                  !isRestored && sale['date'] == todayDate;
                              final bool isNonFiscal =
                                  !isCancelled && !_isFiscalSale(sale);

                              IconData paymentIcon = Icons.payments;
                              Color paymentColor = AdminTones.successText;

                              if (isNonFiscal) {
                                paymentIcon = Icons.shield_outlined;
                                paymentColor = AdminTones.warningText;
                              } else if (breakdown.length == 1) {
                                final entry = breakdown.entries.first;
                                final normalized =
                                    PaymentUtils.normalizeMethodKey(entry.key);
                                switch (normalized) {
                                  case PaymentUtils.methodCardTbc:
                                    paymentIcon = Icons.credit_card;
                                    paymentColor = AdminTones.infoText;
                                    break;
                                  case PaymentUtils.methodCardBog:
                                    paymentIcon = Icons.credit_card;
                                    // Ochre against TBC's slate: the two card
                                    // brands still read apart, but both now sit
                                    // inside the warm palette.
                                    paymentColor = AdminTones.warningText;
                                    break;
                                  case PaymentUtils.methodCardLegacy:
                                    paymentIcon = Icons.credit_card;
                                    paymentColor = AdminTones.infoText;
                                    break;
                                  case PaymentUtils.methodCash:
                                    paymentIcon = Icons.payments;
                                    paymentColor = AdminTones.successText;
                                    break;
                                  case PaymentUtils.methodOther:
                                    paymentIcon = Icons.account_balance_wallet;
                                    paymentColor = AdminDesign.muted;
                                    break;
                                }
                              } else if (breakdown.length > 1) {
                                paymentIcon = Icons.account_balance_wallet;
                                paymentColor = AdminDesign.accentDark;
                              }

                              return Card(
                                color: _cardColor,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: _borderColor),
                                ),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: Colors.transparent,
                                    splashColor: paymentColor.withOpacity(0.08),
                                    colorScheme: const ColorScheme.light(),
                                  ),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    childrenPadding: const EdgeInsets.all(16),
                                    iconColor: paymentColor,
                                    collapsedIconColor: paymentColor,
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: paymentColor.withOpacity(
                                        0.12,
                                      ),
                                      child: Icon(
                                        paymentIcon,
                                        color: paymentColor,
                                      ),
                                    ),
                                    title: Text(
                                      'შეკვეთა #${sale['orderId']} • ${tableNumbers.join(', ')}',
                                      style: const TextStyle(
                                        color: _textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'ოპერატორი: ${DatabaseService.getDisplayOperatorName(sale['createdBy'] as String?)} • $paymentDisplay',
                                          style: const TextStyle(
                                            color: _textMuted,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              '₾${orderTotal.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: paymentColor,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (advanceAmount > 0) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                'ავანსი: ₾${advanceAmount.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  color: AdminTones.warningText,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (isNonFiscal)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Chip(
                                              backgroundColor: Colors
                                                  .orangeAccent
                                                  .withOpacity(0.14),
                                              side: BorderSide.none,
                                              label: const Text(
                                                'არაფისკალური',
                                                style: TextStyle(
                                                  color: AdminTones.warningText,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (isCancelled)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Chip(
                                              backgroundColor: AdminDesign.danger
                                                  .withOpacity(0.12),
                                              side: BorderSide.none,
                                              label: const Text(
                                                'გაუქმებული',
                                                style: TextStyle(
                                                  color: AdminDesign.danger,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    children: [
                                      Divider(color: _borderColor),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          if (!isMobile) ...[
                                            TextButton.icon(
                                              onPressed: canRestore
                                                  ? () {
                                                      unawaited(
                                                        widget
                                                            .onRestoreClosedSale(
                                                              sale,
                                                            ),
                                                      );
                                                    }
                                                  : null,
                                              style: TextButton.styleFrom(
                                                foregroundColor: const Color(
                                                  0xFF0F766E,
                                                ),
                                                disabledForegroundColor:
                                                    const Color(
                                                      0xFF0F766E,
                                                    ).withValues(alpha: 0.35),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                              ),
                                              icon: const Icon(
                                                Icons.restart_alt_rounded,
                                              ),
                                              label: const Text(
                                                'მაგიდაზე დაბრუნება',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            TextButton.icon(
                                              onPressed: () {
                                                unawaited(
                                                  widget.onReprintSaleReceipt(
                                                    sale,
                                                  ),
                                                );
                                              },
                                              style: TextButton.styleFrom(
                                                foregroundColor: _primaryColor,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                              ),
                                              icon: const Icon(Icons.print),
                                              label: const Text(
                                                'ქვითრის ბეჭდვა',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            TextButton.icon(
                                              onPressed: () {
                                                unawaited(
                                                  widget
                                                      .onReprintFullSaleReceipt(
                                                        sale,
                                                      ),
                                                );
                                              },
                                              style: TextButton.styleFrom(
                                                foregroundColor: const Color(
                                                  0xFF0F766E,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                              ),
                                              icon: const Icon(
                                                Icons.receipt_long,
                                              ),
                                              label: const Text(
                                                'სრული ქვითარი',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          TextButton.icon(
                                            onPressed: () {
                                              unawaited(
                                                _showSaleItemsModal(sale),
                                              );
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor: _textPrimary,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                            ),
                                            icon: const Icon(
                                              Icons
                                                  .format_list_bulleted_rounded,
                                            ),
                                            label: const Text(
                                              'მენიუს ნახვა',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          TextButton.icon(
                                            onPressed: isCancelled
                                                ? null
                                                : () {
                                                    unawaited(
                                                      widget
                                                          .onConfirmCancelSale(
                                                            sale,
                                                          ),
                                                    );
                                                  },
                                            style: TextButton.styleFrom(
                                              foregroundColor: AdminDesign.danger,
                                              disabledForegroundColor: Colors
                                                  .redAccent
                                                  .withOpacity(0.3),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                            ),
                                            icon: const Icon(
                                              Icons.cancel_schedule_send,
                                            ),
                                            label: const Text(
                                              'გაყიდვის გაუქმება',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
