import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/core/theme/dashboard_colors.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/widgets/skeleton.dart';

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: dashboardTextPrimary,
      ),
    );
  }
}

class DashboardSkeletons extends StatelessWidget {
  const DashboardSkeletons({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Skeleton(height: 170, borderRadius: 24),
        SizedBox(height: 16),
        Row(
          children: List.generate(
            3,
            (_) => const Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 8),
                child: Skeleton(height: 80, borderRadius: 16),
              ),
            ),
          ),
        ),
        SizedBox(height: 16),
        const Skeleton(height: 140, borderRadius: 20),
        SizedBox(height: 12),
        const Skeleton(height: 100, borderRadius: 20),
      ],
    );
  }
}

class HeroCard extends StatelessWidget {
  final ManagerDashboardMetrics metrics;
  final double revenueChange;
  const HeroCard({
    super.key,
    required this.metrics,
    required this.revenueChange,
  });

  @override
  Widget build(BuildContext context) {
    final up = metrics.todayRevenue >= metrics.yesterdayRevenue;
    final fmt = NumberFormat('#,##0.00', 'ka_GE');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'დღევანდელი შემოსავალი',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              _LiveBadge(),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '${fmt.format(metrics.todayRevenue)} ₾',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 14),
          Row(
            children: [
              _ChangePill(up: up, pct: revenueChange),
              SizedBox(width: 10),
              Text(
                'გუშინ: ${fmt.format(metrics.yesterdayRevenue)} ₾',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'დახურული მაგიდები: ${fmt.format(metrics.closedTablesRevenue)} ₾',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'არაფისკალური დახურული: ${fmt.format(metrics.nonFiscalClosedRevenue)} ₾',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'ღია მაგიდების გადასახდელი: ${fmt.format(metrics.openTablesPayable)} ₾',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class KpiRow extends StatelessWidget {
  final ManagerDashboardMetrics metrics;
  final double avgOrder;
  const KpiRow({super.key, required this.metrics, required this.avgOrder});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _KpiCard('შეკვეთები', metrics.todayOrderCount.toString(), Icons.receipt_long_rounded, dashboardBlue),
        SizedBox(width: 10),
        _KpiCard('საშუალო ჩეკი', '${avgOrder.toStringAsFixed(1)} ₾', Icons.payments_rounded, dashboardGreen),
        SizedBox(width: 10),
        _KpiCard('აქტიური', '${metrics.activeTablesCount} მაგ.', Icons.table_restaurant_rounded, dashboardAmber),
      ],
    );
  }
}

class RevenueCompareCard extends StatelessWidget {
  final ManagerDashboardMetrics metrics;
  const RevenueCompareCard({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final maxVal = math.max(metrics.todayRevenue, metrics.yesterdayRevenue);
    final todayFrac = maxVal > 0 ? metrics.todayRevenue / maxVal : 0.0;
    final yestFrac = maxVal > 0 ? metrics.yesterdayRevenue / maxVal : 0.0;
    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('დღეს vs. გუშინ', Icons.bar_chart_rounded, dashboardBlue),
          SizedBox(height: 16),
          _BarRow('დღეს', metrics.todayRevenue, todayFrac, dashboardBlue),
          SizedBox(height: 10),
          _BarRow('გუშინ', metrics.yesterdayRevenue, yestFrac, dashboardTextSecondary),
        ],
      ),
    );
  }
}

class PaymentSplitCard extends StatelessWidget {
  final Map<String, dynamic>? salesReport;
  const PaymentSplitCard({super.key, required this.salesReport});

  @override
  Widget build(BuildContext context) {
    final breakdown = <String, double>{};
    final rawBreakdown = salesReport?['paymentBreakdown'];
    if (rawBreakdown is Map) {
      rawBreakdown.forEach((key, value) {
        final amount = (value as num?)?.toDouble();
        if (amount != null && amount > 0) breakdown[key.toString()] = amount;
      });
    }
    if (breakdown.isEmpty) return const SizedBox.shrink();

    final total = breakdown.values.fold<double>(0, (s, v) => s + v);
    final entries = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('გადახდის მეთოდი', Icons.donut_large_rounded, dashboardPurple),
          SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                height: 110,
                width: 110,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 32,
                    sections: entries
                        .map(
                          (entry) => PieChartSectionData(
                            value: entry.value,
                            color: _paymentColor(entry.key),
                            radius: 22,
                            title: '',
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _LegendItem(
                          label: _paymentLabel(entry.key),
                          value: entry.value,
                          color: _paymentColor(entry.key),
                        ),
                      ),
                    ),
                    _LegendItem(label: 'ჯამი', value: total, color: dashboardTextPrimary),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class EfficiencyRow extends StatelessWidget {
  final ManagerDashboardMetrics metrics;
  final Map<String, dynamic>? salesReport;
  const EfficiencyRow({super.key, required this.metrics, required this.salesReport});

  @override
  Widget build(BuildContext context) {
    final orderCount = (salesReport?['orderCount'] as num?)?.toInt() ?? metrics.todayOrderCount;
    final totalRev = (salesReport?['totalRevenue'] as num?)?.toDouble() ?? metrics.todayRevenue;
    final avgOrder = orderCount > 0 ? totalRev / orderCount : 0.0;
    final occ = metrics.occupancyPercentage;
    final score = (occ * 0.5 + math.min(avgOrder / 100.0, 1.0) * 100.0 * 0.5).clamp(0, 100).toDouble();

    return Row(
      children: [
        Expanded(child: _EffCard(label: 'საშ. ჩეკი', value: '${avgOrder.toStringAsFixed(2)} ₾', icon: Icons.receipt_rounded, color: dashboardGreen)),
        SizedBox(width: 10),
        Expanded(child: _EffCard(label: 'ეფექტურობა', value: '${score.toStringAsFixed(0)}%', icon: Icons.speed_rounded, color: score >= 70 ? dashboardGreen : score >= 40 ? dashboardAmber : dashboardRed)),
        SizedBox(width: 10),
        Expanded(child: _EffCard(label: 'დატვირთვა', value: '${occ.toStringAsFixed(0)}%', icon: Icons.pie_chart_rounded, color: occ >= 70 ? dashboardRed : occ >= 40 ? dashboardAmber : dashboardGreen)),
      ],
    );
  }
}

class StaffChartCard extends StatelessWidget {
  final List<StaffMetric> staff;
  const StaffChartCard({super.key, required this.staff});

  @override
  Widget build(BuildContext context) {
    final sorted = [...staff]..sort((a, b) => b.totalSales.compareTo(a.totalSales));
    final top = sorted.take(5).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    final maxSales = top.first.totalSales;
    const colors = [dashboardBlue, dashboardPurple, dashboardGreen, dashboardAmber, dashboardRed];

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('პერსონალის რეიტინგი', Icons.leaderboard_rounded, dashboardBlue),
          SizedBox(height: 16),
          ...top.asMap().entries.map((e) {
            final i = e.key;
            final s = e.value;
            final frac = maxSales > 0 ? s.totalSales / maxSales : 0.0;
            final color = colors[i % colors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}. ${s.waiterName}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dashboardTextPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${s.totalSales.toStringAsFixed(2)} ₾',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                      ),
                    ],
                  ),
                  SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: frac,
                      backgroundColor: dashboardBorder,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class TopItemsCard extends StatelessWidget {
  final List<Map<String, dynamic>> topItems;
  const TopItemsCard({super.key, required this.topItems});

  @override
  Widget build(BuildContext context) {
    if (topItems.isEmpty) return const SizedBox.shrink();
    final maxRev = topItems.fold<double>(0, (m, e) => math.max(m, (e['revenue'] as num).toDouble()));
    final barGroups = topItems.asMap().entries.map((e) {
      final i = e.key;
      final rev = (e.value['revenue'] as num).toDouble();
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: rev,
            gradient: const LinearGradient(
              colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
      );
    }).toList();

    return _CardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Top პოზიციები (შემოსავლით)', Icons.star_rounded, dashboardAmber),
          SizedBox(height: 16),
          const Text(
            'Top 10 (შემოსავლით)',
            style: TextStyle(fontSize: 11, color: dashboardTextSecondary, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(360, topItems.length * 56),
              height: 290,
              child: BarChart(
                BarChartData(
                  maxY: maxRev * 1.35,
                  barGroups: barGroups,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        if (groupIndex < 0 || groupIndex >= topItems.length) {
                          return null;
                        }
                        final name = (topItems[groupIndex]['name'] as String?) ?? '';
                        final revenue =
                            (topItems[groupIndex]['revenue'] as num?)?.toDouble() ?? 0;
                        return BarTooltipItem(
                          '$name\n${revenue.toStringAsFixed(2)} ₾',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(color: dashboardBorder, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          space: 6,
                          child: Text(
                            _compactAxisValue(v),
                            style: const TextStyle(
                              fontSize: 9,
                              color: dashboardTextSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 38,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= topItems.length) return const SizedBox.shrink();
                          final name = (topItems[idx]['name'] as String?) ?? '';
                          final short = name.length > 10 ? '${name.substring(0, 9)}…' : name;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(short, style: const TextStyle(fontSize: 9, color: dashboardTextSecondary)),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _compactAxisValue(double value) {
  final abs = value.abs();
  if (abs >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(1)}B';
  }
  if (abs >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (abs >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return value.toStringAsFixed(0);
}

class QuickActionsRow extends StatelessWidget {
  final VoidCallback onOpenCountedMenus;
  final VoidCallback onOpenCalculator;
  const QuickActionsRow({
    super.key,
    required this.onOpenCountedMenus,
    required this.onOpenCalculator,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickButton(
            title: 'დათვლილი მენიუ',
            subtitle: 'ისტორია',
            icon: Icons.inventory_2_rounded,
            color: dashboardPurple,
            onTap: onOpenCountedMenus,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _QuickButton(
            title: 'ახალი დათვლა',
            subtitle: 'მენიუს აღრიცხვა',
            icon: Icons.add_task_rounded,
            color: const Color(0xFFEC4899),
            onTap: onOpenCalculator,
          ),
        ),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
      child: const Text('Live', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _ChangePill extends StatelessWidget {
  final bool up;
  final double pct;
  const _ChangePill({required this.up, required this.pct});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: up ? const Color(0xFF4ADE80).withValues(alpha: 0.2) : const Color(0xFFF87171).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '${pct.abs().toStringAsFixed(1)}%',
        style: TextStyle(
          color: up ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _KpiCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: dashboardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dashboardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: dashboardTextPrimary)),
            SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: dashboardTextSecondary)),
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final double value;
  final double fraction;
  final Color color;
  const _BarRow(this.label, this.value, this.fraction, this.color);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'ka_GE');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: dashboardTextSecondary)),
            Text('${fmt.format(value)} ₾', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: dashboardTextPrimary)),
          ],
        ),
        SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            backgroundColor: dashboardBorder,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _LegendItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'ka_GE');
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: dashboardTextSecondary)),
              Text('${fmt.format(value)} ₾', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: dashboardTextPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _EffCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _EffCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: dashboardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dashboardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: dashboardTextPrimary)),
          SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: dashboardTextSecondary)),
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QuickButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

class _CardContainer extends StatelessWidget {
  final Widget child;
  const _CardContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dashboardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dashboardBorder),
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _CardTitle(this.title, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: dashboardTextPrimary),
        ),
      ],
    );
  }
}

String _paymentLabel(String key) {
  switch (key.trim().toLowerCase()) {
    case 'cash':
      return 'ნაღდი';
    case 'card':
      return 'ბარათი';
    case 'card-tbc':
      return 'ბარათი (TBC)';
    case 'card-bog':
      return 'ბარათი (BOG)';
    case 'non-fiscal':
      return 'არაფისკალური';
    case 'advance':
      return 'ავანსი';
    default:
      return key;
  }
}

Color _paymentColor(String key) {
  switch (key.trim().toLowerCase()) {
    case 'cash':
      return dashboardGreen;
    case 'card':
    case 'card-tbc':
      return dashboardBlue;
    case 'card-bog':
      return dashboardAmber;
    case 'non-fiscal':
      return dashboardRed;
    default:
      return dashboardPurple;
  }
}
