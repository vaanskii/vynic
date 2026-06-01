import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class HomeXReportSection extends StatelessWidget {
  const HomeXReportSection({
    super.key,
    required this.dailySalesTotal,
    this.openedTablesAmount,
    required this.takeAwayCount,
    required this.activeWaitersCount,
    required this.waiterSummaries,
    required this.onPrintReport,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
  });

  final double dailySalesTotal;
  final double? openedTablesAmount;
  final int takeAwayCount;
  final int activeWaitersCount;
  final List<Map<String, dynamic>> waiterSummaries;
  final VoidCallback onPrintReport;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24, 
        isMobile ? 16 : 24, 
        isMobile ? 16 : 24, 
        96,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            icon: Icons.receipt_long,
            title: 'X ანგარიში',
            subtitle:
                'მიმდინარე დღის ოპერატიული ანგარიში და დეტალური მიმოხილვა.',
            isMobile: isMobile,
          ),
          SizedBox(height: isMobile ? 16 : 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildMetricTile(
                icon: Icons.payments_outlined,
                label: 'დღიური გაყიდვები',
                value: '₾${dailySalesTotal.toStringAsFixed(2)}',
                backgroundColor: const Color(0xFFE0F2FE),
                iconColor: primaryColor,
                isMobile: isMobile,
              ),
              if (openedTablesAmount != null)
                _buildMetricTile(
                  icon: Icons.table_restaurant_outlined,
                  label: 'ღია მაგიდების თანხა',
                  value: '₾${openedTablesAmount!.toStringAsFixed(2)}',
                  backgroundColor: const Color(0xFFECFDF5),
                  iconColor: const Color(0xFF0F766E),
                  isMobile: isMobile,
                ),
              _buildMetricTile(
                icon: Icons.shopping_bag_outlined,
                label: 'გატანები',
                value: '$takeAwayCount',
                backgroundColor: const Color(0xFFF1F5F9),
                iconColor: secondaryColor,
                isMobile: isMobile,
              ),
              _buildMetricTile(
                icon: Icons.people_outline,
                label: 'აქტიური ოფიციანტები',
                value: '$activeWaitersCount',
                backgroundColor: const Color(0xFFEEF2FF),
                iconColor: primaryColor,
                isMobile: isMobile,
              ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 24),
          _buildActionCard(
            icon: Icons.print_outlined,
            title: 'ანგარიშის დაბეჭდვა',
            description: 'დაბეჭდე დღიური X ანგარიში ყველა გადახდის დეტალით.',
            isMobile: isMobile,
            actions: [
              ElevatedButton.icon(
                onPressed: onPrintReport,
                icon: const Icon(Icons.print, size: 20),
                label: const Text('ბეჭდვა'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: secondaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 24),
          _buildWaiterSalesSection(waiterSummaries, isMobile),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool isMobile,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: primaryColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(color: mutedText, fontSize: isMobile ? 13 : 14),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color backgroundColor,
    required Color iconColor,
    required bool isMobile,
  }) {
    if (isMobile) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconColor.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: iconColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> actions,
    required bool isMobile,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: secondaryColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: isMobile ? 16 : 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(color: mutedText, fontSize: isMobile ? 13 : 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
        ],
      ),
    );
  }

  Widget _buildWaiterSalesSection(List<Map<String, dynamic>> summaries, bool isMobile) {
    if (summaries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primaryColor.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.info_outline),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'დღის ფისკალური გაყიდვები ოფიციანტებზე არ იძებნება',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ფიქსირებული გაყიდვების გარეშე ოფიციანტების ჩამონათვალი არ ჩანს.',
                    style: TextStyle(color: mutedText, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: primaryColor.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.person_search, color: primaryColor),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ოფიციანტების ფისკალური გაყიდვები',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: isMobile ? 16 : 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'გაფორმებული შეკვეთების ჯამი ოფიციანტების მიხედვით.',
                    style: TextStyle(color: mutedText, fontSize: isMobile ? 13 : 14),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...List.generate(summaries.length, (index) {
            final summary = summaries[index];
            return Column(
              children: [
                if (index != 0)
                  const Divider(height: 24, color: Color(0xFFE2E8F0)),
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${index + 1}.',
                        style: TextStyle(
                          color: mutedText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${summary['username'] ?? ''}',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${summary['orderCount'] ?? 0} შეკვეთა',
                      style: TextStyle(color: mutedText, fontSize: 13),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '₾${(summary['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
