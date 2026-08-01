import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_form_controls.dart';
import 'package:vynic/core/services/pos/monthly_report_service.dart';

typedef AsyncVoidCallback = Future<void> Function();

/// Monthly and full financial report tooling.
///
/// These two cards used to sit at the bottom of the Settings tab, which mixed
/// reporting with restaurant configuration. They now render inside the sales
/// report section instead. Every control, controller and callback is the same
/// one the settings tab passed down — only the parent changed.
class AdminFinancialReportsPanel extends StatelessWidget {
  const AdminFinancialReportsPanel({
    super.key,
    required this.getGeorgianMonthName,
    required this.getDaysInMonth,
    required this.monthlyReportLeaseController,
    required this.monthlyReportStaffDailyController,
    required this.monthlyReportManualSalesController,
    required this.currencyFormatter,
    required this.monthlyReportProfitRatio,
    required this.onMonthlyReportProfitRatioChanged,
    required this.isSavingMonthlyReportConfig,
    required this.isGeneratingMonthlyReport,
    required this.selectedMonthlyReportMonth,
    required this.onSelectedMonthlyReportMonthChanged,
    required this.monthlyReportStartDay,
    required this.onMonthlyReportStartDayChanged,
    required this.monthlyReportEndDay,
    required this.onMonthlyReportEndDayChanged,
    required this.monthlyReportMonthOptions,
    required this.monthlyReportPreview,
    required this.monthlyReportInputError,
    required this.onRefreshMonthlyReportPreview,
    required this.onSaveMonthlyReportConfig,
    required this.onGenerateMonthlyReportExcel,
    required this.onGenerateMonthlyReportPdf,
    required this.fullReportStartMonth,
    required this.fullReportEndMonth,
    required this.fullReportMonthOptions,
    required this.fullReportPreviewMonths,
    required this.fullReportTotalSalesAllTime,
    required this.isGeneratingFullReport,
    required this.onFullReportStartMonthChanged,
    required this.onFullReportEndMonthChanged,
    required this.onGenerateFullReportXlsx,
    required this.onGenerateFullReportPdf,
    required this.onRefreshFullReportPreview,
  });

  final String Function(int) getGeorgianMonthName;
  final int Function(DateTime) getDaysInMonth;

  final TextEditingController monthlyReportLeaseController;
  final TextEditingController monthlyReportStaffDailyController;
  final TextEditingController monthlyReportManualSalesController;
  final NumberFormat currencyFormatter;

  final double monthlyReportProfitRatio;
  final ValueChanged<double> onMonthlyReportProfitRatioChanged;
  final bool isSavingMonthlyReportConfig;
  final bool isGeneratingMonthlyReport;
  final DateTime selectedMonthlyReportMonth;
  final ValueChanged<DateTime> onSelectedMonthlyReportMonthChanged;
  final int monthlyReportStartDay;
  final ValueChanged<int> onMonthlyReportStartDayChanged;
  final int monthlyReportEndDay;
  final ValueChanged<int> onMonthlyReportEndDayChanged;
  final List<DateTime> monthlyReportMonthOptions;
  final MonthlyReportSummary? monthlyReportPreview;
  final String? monthlyReportInputError;
  final VoidCallback onRefreshMonthlyReportPreview;
  final AsyncVoidCallback onSaveMonthlyReportConfig;
  final AsyncVoidCallback onGenerateMonthlyReportExcel;
  final AsyncVoidCallback onGenerateMonthlyReportPdf;

  final DateTime fullReportStartMonth;
  final DateTime fullReportEndMonth;
  final List<DateTime> fullReportMonthOptions;
  final List<MonthlyReportSummary> fullReportPreviewMonths;
  final double fullReportTotalSalesAllTime;
  final bool isGeneratingFullReport;
  final ValueChanged<DateTime> onFullReportStartMonthChanged;
  final ValueChanged<DateTime> onFullReportEndMonthChanged;
  final AsyncVoidCallback onGenerateFullReportXlsx;
  final AsyncVoidCallback onGenerateFullReportPdf;
  final VoidCallback onRefreshFullReportPreview;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReportsHeader(
          icon: Icons.assessment,
          title: 'თვიური ანგარიში',
          subtitle:
              'დაარეგულირეთ შიდა ხარჯები და შექმენით თვიური ფინანსური ანგარიში.',
        ),
        const SizedBox(height: 12),
        _buildMonthlyReportSettingsCard(),
        const SizedBox(height: 18),
        _buildReportsHeader(
          icon: Icons.summarize,
          title: 'სრული ანგარიში',
          subtitle:
              'აირჩიეთ თვეების დიაპაზონი, დაამატეთ საჭირო კორექციები და მიიღეთ ერთიანი XLSX ანგარიში.',
        ),
        const SizedBox(height: 12),
        _buildFullReportCard(),
      ],
    );
  }

  Widget _buildReportsHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: AdminDesign.panelDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AdminDesign.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AdminDesign.radius),
            ),
            child: Icon(icon, color: AdminDesign.accentDark, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AdminDesign.muted,
                      fontSize: 13,
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

  Widget _buildMonthlySummaryRow({
    required String label,
    required String value,
    Color? valueColor,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AdminDesign.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? AdminDesign.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (helper != null && helper.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                helper,
                style: const TextStyle(color: AdminDesign.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRatioPresetChip({required String label, required double value}) {
    final isSelected = (monthlyReportProfitRatio - value).abs() < 0.005;
    return ChoiceChip(
      label: Text(
        label,
        style: const TextStyle(
          color: AdminDesign.text,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFFCCFBF1),
      backgroundColor: AdminDesign.surface,
      onSelected: (_) => onMonthlyReportProfitRatioChanged(value),
    );
  }

  Widget _buildMonthlyReportSettingsCard() {
    final summary = monthlyReportPreview;
    final ratioPercent = (monthlyReportProfitRatio * 100).toStringAsFixed(0);
    final hasSelection = monthlyReportMonthOptions.contains(
      selectedMonthlyReportMonth,
    );
    final daysInSelectedMonth = getDaysInMonth(selectedMonthlyReportMonth);
    final int startDayValue = monthlyReportStartDay
        .clamp(1, daysInSelectedMonth)
        .toInt();
    final int endDayValue = monthlyReportEndDay
        .clamp(startDayValue, daysInSelectedMonth)
        .toInt();
    final isBusy = isSavingMonthlyReportConfig || isGeneratingMonthlyReport;

    return Card(
      color: AdminDesign.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        side: const BorderSide(color: AdminDesign.border),
      ),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(_isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'შიდა თვიური ანგარიში',
              style: TextStyle(
                color: AdminDesign.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'მოარგეთ პერიოდი, ხარჯები და მარჟა თქვენი ბიზნესის მოდელს — შედეგები ახლდება მყისიერად.',
              style: TextStyle(color: AdminDesign.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<DateTime>(
              initialValue: hasSelection ? selectedMonthlyReportMonth : null,
              items: monthlyReportMonthOptions
                  .map(
                    (date) => DropdownMenuItem<DateTime>(
                      value: date,
                      child: Text(
                        '${getGeorgianMonthName(date.month)} ${date.year}',
                        style: const TextStyle(color: AdminDesign.text),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  onSelectedMonthlyReportMonthChanged(value);
                }
              },
              style: const TextStyle(color: AdminDesign.text),
              iconEnabledColor: AdminDesign.muted,
              decoration: InputDecoration(
                filled: true,
                fillColor: AdminDesign.panelSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AdminDesign.radius),
                  borderSide: const BorderSide(color: AdminDesign.border),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: startDayValue,
                    items: List.generate(daysInSelectedMonth, (index) {
                      final day = index + 1;
                      return DropdownMenuItem<int>(
                        value: day,
                        child: Text(
                          day.toString().padLeft(2, '0'),
                          style: const TextStyle(color: AdminDesign.text),
                        ),
                      );
                    }),
                    onChanged: isBusy
                        ? null
                        : (value) {
                            if (value != null) {
                              onMonthlyReportStartDayChanged(value);
                            }
                          },
                    style: const TextStyle(color: AdminDesign.text),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AdminDesign.panelSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AdminDesign.radius),
                        borderSide: const BorderSide(color: AdminDesign.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: endDayValue,
                    items: List.generate(daysInSelectedMonth, (index) {
                      final day = index + 1;
                      return DropdownMenuItem<int>(
                        value: day,
                        child: Text(
                          day.toString().padLeft(2, '0'),
                          style: const TextStyle(color: AdminDesign.text),
                        ),
                      );
                    }),
                    onChanged: isBusy
                        ? null
                        : (value) {
                            if (value != null) {
                              onMonthlyReportEndDayChanged(value);
                            }
                          },
                    style: const TextStyle(color: AdminDesign.text),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AdminDesign.panelSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AdminDesign.radius),
                        borderSide: const BorderSide(color: AdminDesign.border),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AdminPosTextField(
                    controller: monthlyReportLeaseController,
                    label: 'ქირის თვიური ხარჯი (₾)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !isBusy,
                    onChanged: (_) => onRefreshMonthlyReportPreview(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AdminPosTextField(
                    controller: monthlyReportStaffDailyController,
                    label: 'თანამშრომლის დღიური ხარჯი (₾)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !isBusy,
                    onChanged: (_) => onRefreshMonthlyReportPreview(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdminPosTextField(
              controller: monthlyReportManualSalesController,
              label: 'ხელით დამატებული გაყიდვები (მხოლოდ ანგარიშისთვის, ₾)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              enabled: !isBusy,
              onChanged: (_) => onRefreshMonthlyReportPreview(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: monthlyReportProfitRatio,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    onChanged: onMonthlyReportProfitRatioChanged,
                  ),
                ),
                SizedBox(
                  width: 68,
                  child: Text(
                    '$ratioPercent%',
                    style: const TextStyle(color: AdminDesign.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'საკვების მოგების მარჟა (%)',
              style: TextStyle(color: AdminDesign.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildRatioPresetChip(label: '40%', value: 0.40),
                _buildRatioPresetChip(label: '50%', value: 0.50),
                _buildRatioPresetChip(label: '60%', value: 0.60),
                _buildRatioPresetChip(label: '70%', value: 0.70),
              ],
            ),
            if (monthlyReportInputError != null)
              Text(
                monthlyReportInputError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              )
            else if (summary != null) ...[
              const SizedBox(height: 10),
              const Divider(color: AdminDesign.border),
              _buildMonthlySummaryRow(
                label: 'მთლიანი გაყიდვები',
                value: currencyFormatter.format(summary.totalSales),
              ),
              _buildMonthlySummaryRow(
                label: 'ნაღდი (Cash)',
                value: currencyFormatter.format(summary.cashRevenue),
              ),
              _buildMonthlySummaryRow(
                label: 'ბარათი (TBC)',
                value: currencyFormatter.format(summary.cardTbcRevenue),
              ),
              _buildMonthlySummaryRow(
                label: 'ბარათი (BOG)',
                value: currencyFormatter.format(summary.cardBogRevenue),
              ),
              _buildMonthlySummaryRow(
                label: 'ოპერაციების რაოდენობა',
                value: summary.transactionCount.toString(),
              ),
              _buildMonthlySummaryRow(
                label: 'საშუალო ჩეკი',
                value: currencyFormatter.format(summary.averageTicket),
              ),
              _buildMonthlySummaryRow(
                label: 'დღიური საშუალო გაყიდვა',
                value: currencyFormatter.format(summary.dailyAverageSales),
              ),
              _buildMonthlySummaryRow(
                label: 'საკვების თვითღირებულება',
                value: currencyFormatter.format(summary.foodCost),
              ),
              _buildMonthlySummaryRow(
                label: 'თანამშრომლების ხარჯი',
                value: currencyFormatter.format(summary.staffCost),
              ),
              _buildMonthlySummaryRow(
                label: 'ქირა',
                value: currencyFormatter.format(summary.leaseCost),
              ),
              _buildMonthlySummaryRow(
                label: 'საერთო ოპერაციული ხარჯი',
                value: currencyFormatter.format(summary.operatingCost),
              ),
              _buildMonthlySummaryRow(
                label: summary.netProfit >= 0
                    ? 'წმინდა მოგება'
                    : 'წმინდა ზარალი',
                value: currencyFormatter.format(summary.netProfit),
                valueColor: summary.netProfit >= 0
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFEF4444),
              ),
              _buildMonthlySummaryRow(
                label: 'მოგების მარჟა',
                value: '${summary.profitMarginPercent.toStringAsFixed(1)}%',
                valueColor: summary.profitMarginPercent >= 0
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFEF4444),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'აირჩიეთ ფორმატი: Excel (XLSX) ან PDF (Save As).',
              style: TextStyle(color: AdminDesign.muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            AdminActionRow(
              children: [
                ElevatedButton.icon(
                  onPressed: isSavingMonthlyReportConfig
                      ? null
                      : onSaveMonthlyReportConfig,
                  style: AdminFormButtons.primary(),
                  icon: const Icon(Icons.save),
                  label: Text(
                    isSavingMonthlyReportConfig
                        ? 'შენახვა...'
                        : 'კონფიგურაციის შენახვა',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isGeneratingMonthlyReport
                      ? null
                      : onGenerateMonthlyReportExcel,
                  style: AdminFormButtons.outline(),
                  icon: const Icon(Icons.table_view),
                  label: Text(
                    isGeneratingMonthlyReport
                        ? 'შექმნა...'
                        : 'Excel (XLSX) ანგარიშის შექმნა',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isGeneratingMonthlyReport
                      ? null
                      : onGenerateMonthlyReportPdf,
                  style: AdminFormButtons.outline(),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(
                    isGeneratingMonthlyReport
                        ? 'შექმნა...'
                        : 'PDF ანგარიშის შექმნა',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullReportCard() {
    final isBusy = isGeneratingMonthlyReport || isGeneratingFullReport;
    final ratioPercent = (monthlyReportProfitRatio * 100).toStringAsFixed(0);
    return Card(
      color: AdminDesign.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        side: const BorderSide(color: AdminDesign.border),
      ),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(_isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DateTime>(
                    initialValue:
                        fullReportMonthOptions.contains(fullReportStartMonth)
                        ? fullReportStartMonth
                        : null,
                    items: fullReportMonthOptions
                        .map(
                          (date) => DropdownMenuItem<DateTime>(
                            value: date,
                            child: Text(
                              '${getGeorgianMonthName(date.month)} ${date.year}',
                              style: const TextStyle(color: AdminDesign.text),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: isBusy
                        ? null
                        : (value) {
                            if (value != null) {
                              onFullReportStartMonthChanged(value);
                            }
                          },
                    decoration: InputDecoration(
                      labelText: 'საწყისი თვე',
                      filled: true,
                      fillColor: AdminDesign.panelSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AdminDesign.radius),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<DateTime>(
                    initialValue:
                        fullReportMonthOptions.contains(fullReportEndMonth)
                        ? fullReportEndMonth
                        : null,
                    items: fullReportMonthOptions
                        .map(
                          (date) => DropdownMenuItem<DateTime>(
                            value: date,
                            child: Text(
                              '${getGeorgianMonthName(date.month)} ${date.year}',
                              style: const TextStyle(color: AdminDesign.text),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: isBusy
                        ? null
                        : (value) {
                            if (value != null) {
                              onFullReportEndMonthChanged(value);
                            }
                          },
                    decoration: InputDecoration(
                      labelText: 'ბოლო თვე',
                      filled: true,
                      fillColor: AdminDesign.panelSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AdminDesign.radius),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AdminPosTextField(
                    controller: monthlyReportLeaseController,
                    label: 'ქირის თვიური ხარჯი (₾)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !isBusy,
                    onChanged: (_) {
                      onRefreshMonthlyReportPreview();
                      onRefreshFullReportPreview();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AdminPosTextField(
                    controller: monthlyReportStaffDailyController,
                    label: 'თანამშრომლის დღიური ხარჯი (₾)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !isBusy,
                    onChanged: (_) {
                      onRefreshMonthlyReportPreview();
                      onRefreshFullReportPreview();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: monthlyReportProfitRatio,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    onChanged: isBusy
                        ? null
                        : (v) {
                            onMonthlyReportProfitRatioChanged(v);
                            onRefreshFullReportPreview();
                          },
                  ),
                ),
                SizedBox(
                  width: 68,
                  child: Text(
                    '$ratioPercent%',
                    style: const TextStyle(color: AdminDesign.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'საკვების მოგების მარჟა (%)',
              style: TextStyle(color: AdminDesign.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (fullReportPreviewMonths.isEmpty)
              const Text(
                'არჩეულ დიაპაზონში გაყიდვები არ მოიძებნა (0 თვეები ავტომატურად დამალულია).',
                style: TextStyle(color: AdminDesign.muted, fontSize: 13),
              )
            else ...[
              const Text(
                'თვეების შეჯამება',
                style: TextStyle(
                  color: AdminDesign.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...fullReportPreviewMonths.map(
                (m) => _buildMonthlySummaryRow(
                  label: '${getGeorgianMonthName(m.month)} ${m.year}',
                  value: currencyFormatter.format(m.totalSales),
                  helper:
                      'ქირა: ${currencyFormatter.format(m.leaseCost)} • თანამშრომლები: ${currencyFormatter.format(m.staffCost)} • საკვების მარჟა: ${(m.profitRatio * 100).toStringAsFixed(1)}%',
                ),
              ),
              const Divider(color: AdminDesign.border),
              _buildMonthlySummaryRow(
                label: 'სრული გაყიდვები (ყველა დრო)',
                value: currencyFormatter.format(fullReportTotalSalesAllTime),
              ),
            ],
            const SizedBox(height: 16),
            AdminActionRow(
              children: [
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onGenerateFullReportXlsx,
                  style: AdminFormButtons.outline(),
                  icon: const Icon(Icons.table_view),
                  label: Text(
                    isBusy ? 'შექმნა...' : 'სრული XLSX ანგარიშის შექმნა',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onGenerateFullReportPdf,
                  style: AdminFormButtons.outline(),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(
                    isBusy ? 'შექმნა...' : 'სრული PDF ანგარიშის შექმნა',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
