import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/monthly_report_service.dart';

typedef AsyncVoidCallback = Future<void> Function();

class AdminSettingsSection extends StatelessWidget {
  const AdminSettingsSection({
    super.key,
    required this.formatDateTimeDisplay,
    required this.getPrintersList,
    required this.printerNameControllers,
    required this.printerIpControllers,
    required this.printerPortControllers,
    required this.onAddPrinter,
    required this.onRemovePrinter,
    required this.getPrinterRole,
    required this.onPrinterRoleChanged,
    required this.formatRelativeTime,
    required this.getGeorgianMonthName,
    required this.getDaysInMonth,
    required this.kitchenPrinterController,
    required this.receiptPrinterController,
    required this.printerPortController,
    required this.serviceFeeController,
    required this.currentCancellationPasswordController,
    required this.newCancellationPasswordController,
    required this.confirmCancellationPasswordController,
    required this.cancellationPasswordHintController,
    required this.monthlyReportLeaseController,
    required this.monthlyReportStaffDailyController,
    required this.monthlyReportManualSalesController,
    required this.serviceFeeEnabledByDefault,
    required this.onServiceFeeEnabledByDefaultChanged,
    required this.serviceFeePercentDisplay,
    required this.isSavingPrinterSettings,
    required this.isTestingPrinters,
    required this.isSavingServiceFee,
    required this.defaultLanguageSetting,
    required this.onDefaultLanguageSettingChanged,
    required this.isSavingLocalization,
    required this.lastBackupPath,
    required this.lastRestorePath,
    required this.isCreatingBackup,
    required this.isRestoringBackup,
    required this.isCancellationPasswordSet,
    required this.isSavingCancellationPassword,
    required this.cancellationPasswordUpdatedAt,
    required this.restrictTableCloseToOwner,
    required this.onRestrictTableCloseToOwnerChanged,
    required this.isSavingTableOwnershipSettings,
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
    required this.currencyFormatter,
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
    required this.onRefreshMonthlyReportPreview,
    required this.onSaveMonthlyReportConfig,
    required this.onGenerateMonthlyReportExcel,
    required this.onGenerateMonthlyReportPdf,
    required this.onSavePrinterSettings,
    required this.onTestPrinterConnections,
    required this.onScanPrinters,
    required this.onSaveServiceFeeSettings,
    required this.onSaveCancellationPassword,
    required this.onSaveTableOwnershipSettings,
    required this.onSaveLocalizationSettings,
    required this.onCreateBackupFile,
    required this.onRestoreBackupFromFile,
  });
  // Multiple printers support
  final List<Map<String, dynamic>> Function() getPrintersList;
  final List<TextEditingController> printerNameControllers;
  final List<TextEditingController> printerIpControllers;
  final List<TextEditingController> printerPortControllers;
  final VoidCallback onAddPrinter;
  final ValueChanged<int> onRemovePrinter;
  final String Function(int index) getPrinterRole;
  final void Function(int index, String role) onPrinterRoleChanged;

  final String Function(DateTime) formatDateTimeDisplay;
  final String Function(DateTime) formatRelativeTime;
  final String Function(int) getGeorgianMonthName;
  final int Function(DateTime) getDaysInMonth;

  final TextEditingController kitchenPrinterController;
  final TextEditingController receiptPrinterController;
  final TextEditingController printerPortController;
  final TextEditingController serviceFeeController;
  final TextEditingController currentCancellationPasswordController;
  final TextEditingController newCancellationPasswordController;
  final TextEditingController confirmCancellationPasswordController;
  final TextEditingController cancellationPasswordHintController;
  final TextEditingController monthlyReportLeaseController;
  final TextEditingController monthlyReportStaffDailyController;
  final TextEditingController monthlyReportManualSalesController;

  final bool serviceFeeEnabledByDefault;
  final ValueChanged<bool> onServiceFeeEnabledByDefaultChanged;
  final String serviceFeePercentDisplay;
  final bool isSavingPrinterSettings;
  final bool isTestingPrinters;
  final bool isSavingServiceFee;
  final String defaultLanguageSetting;
  final ValueChanged<String> onDefaultLanguageSettingChanged;
  final bool isSavingLocalization;
  final String? lastBackupPath;
  final String? lastRestorePath;
  final bool isCreatingBackup;
  final bool isRestoringBackup;
  final bool isCancellationPasswordSet;
  final bool isSavingCancellationPassword;
  final DateTime? cancellationPasswordUpdatedAt;
  final bool restrictTableCloseToOwner;
  final ValueChanged<bool> onRestrictTableCloseToOwnerChanged;
  final bool isSavingTableOwnershipSettings;

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
  final NumberFormat currencyFormatter;

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
  final AsyncVoidCallback onSavePrinterSettings;
  final AsyncVoidCallback onTestPrinterConnections;
  final AsyncVoidCallback onScanPrinters;
  final AsyncVoidCallback onSaveServiceFeeSettings;
  final AsyncVoidCallback onSaveCancellationPassword;
  final AsyncVoidCallback onSaveTableOwnershipSettings;
  final AsyncVoidCallback onSaveLocalizationSettings;
  final AsyncVoidCallback onCreateBackupFile;
  final AsyncVoidCallback onRestoreBackupFromFile;
  static const Color _secondaryColor = Color(0xFF2563EB);
  static const Color _surfaceColor = Color(0xFFF4F6FF);
  static const Color _cardColor = Colors.white;
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF64748B);

  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFBFDBFE),
      foregroundColor: _textPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    );
  }

  ButtonStyle _outlineButtonStyle() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      side: const BorderSide(color: _secondaryColor, width: 1.5),
      foregroundColor: _secondaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 24,
            0,
            isMobile ? 16 : 24,
            24,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSettingsHeader(
                  icon: Icons.print,
                  title: 'პრინტერის კონფიგურაცია',
                  subtitle:
                      'დააყენეთ პრინტერების IP მისამართები, პორტი და შეამოწმეთ კავშირი ბარისა და სამზარეულოს ჩეკების ბეჭდვისთვის.',
                ),
                const SizedBox(height: 16),
                _buildPrinterSettingsCard(context),
                const SizedBox(height: 32),
                _buildSettingsHeader(
                  icon: Icons.percent,
                  title: 'მომსახურების საკომისიო',
                  subtitle:
                      'განაახლეთ მომსახურების საკომისიოს პროცენტი და განსაზღვრეთ ავტომატური გამოყენება.',
                ),
                const SizedBox(height: 16),
                _buildServiceFeeCard(),
                const SizedBox(height: 32),
                _buildSettingsHeader(
                  icon: Icons.lock_outline,
                  title: 'გაუქმების პაროლი',
                  subtitle:
                      'მართეთ დადასტურების პაროლი, რომელიც საჭიროა შეკვეთის გაუქმებამდე.',
                ),
                const SizedBox(height: 16),
                _buildCancellationPasswordCard(),
                const SizedBox(height: 32),
                _buildSettingsHeader(
                  icon: Icons.table_restaurant,
                  title: 'მაგიდის დახურვის უფლებები',
                  subtitle:
                      'განსაზღვრეთ, შეუძლია თუ არა ყველა ოფიციანტს მაგიდის დახურვა, თუ მხოლოდ მის შემქმნელს.',
                ),
                const SizedBox(height: 16),
                _buildTableOwnershipCard(),
                const SizedBox(height: 32),
                _buildSettingsHeader(
                  icon: Icons.language,
                  title: 'ენის პარამეტრები',
                  subtitle:
                      'აირჩიეთ ნაგულისხმევი ენა მენიუს, კლავიატურისა და ბეჭდური ჩეკებისთვის.',
                ),
                const SizedBox(height: 16),
                _buildLocalizationCard(),
                const SizedBox(height: 32),
                _buildSettingsHeader(
                  icon: Icons.assessment,
                  title: 'თვიური ანგარიში',
                  subtitle:
                      'დაარეგულირეთ შიდა ხარჯები და შექმენით თვიური ფინანსური ანგარიში.',
                ),
                const SizedBox(height: 16),
                _buildMonthlyReportSettingsCard(),
                const SizedBox(height: 32),
                _buildSettingsHeader(
                  icon: Icons.summarize,
                  title: 'სრული ანგარიში',
                  subtitle:
                      'აირჩიეთ თვეების დიაპაზონი, დაამატეთ საჭირო კორექციები და მიიღეთ ერთიანი XLSX ანგარიში.',
                ),
                const SizedBox(height: 16),
                _buildFullReportCard(),
                const SizedBox(height: 32),
                _buildSettingsHeader(
                  icon: Icons.save_alt,
                  title: 'მონაცემები და სარეზერვო ასლები',
                  subtitle:
                      'შექმენით ოფლაინ სარეზერვო ასლი მომხმარებლების, მენიუს, ჯავშნებისა და გაყიდვების მონაცემებისთვის.',
                ),
                const SizedBox(height: 16),
                _buildBackupCard(),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor),
          ),
          child: Icon(icon, color: _secondaryColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: _textMuted, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrinterSettingsCard(BuildContext context) {
    final isBusy = isSavingPrinterSettings || isTestingPrinters;
    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ქსელური პრინტერები',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildIpTextField(
              controller: kitchenPrinterController,
              label: 'სამზარეულოს ჩეკი IP',
              hint: 'მაგ. 192.168.100.33',
              enabled: !isBusy,
            ),
            const SizedBox(height: 8),
            _buildIpPinPad(
              controller: kitchenPrinterController,
              enabled: !isBusy,
            ),
            const SizedBox(height: 12),
            _buildIpTextField(
              controller: receiptPrinterController,
              label: 'ბარის ჩეკი IP',
              hint: 'მაგ. 192.168.100.34',
              enabled: !isBusy,
            ),
            const SizedBox(height: 8),
            _buildIpPinPad(
              controller: receiptPrinterController,
              enabled: !isBusy,
            ),
            const SizedBox(height: 12),
            _buildSettingsTextField(
              controller: printerPortController,
              label: 'პორტი',
              hint: '9100',
              keyboardType: TextInputType.number,
              enabled: false,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: isSavingPrinterSettings
                      ? null
                      : onSavePrinterSettings,
                  style: _primaryButtonStyle(),
                  icon: isSavingPrinterSettings
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    isSavingPrinterSettings
                        ? 'შენახვა...'
                        : 'პარამეტრების შენახვა',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isTestingPrinters
                      ? null
                      : onTestPrinterConnections,
                  style: _outlineButtonStyle(),
                  icon: isTestingPrinters
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(
                    isTestingPrinters
                        ? 'შემოწმება...'
                        : 'კავშირის შემოწმება',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (!isBusy)
                  const Text(
                    'გამოიყენება კლასიკური კონფიგურაცია: 2 IP + ფიქსირებული პორტი 9100.',
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIpTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool enabled,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: const TextStyle(color: _textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _textMuted),
        hintStyle: TextStyle(color: _textMuted.withValues(alpha: 0.6)),
        filled: true,
        fillColor: _surfaceColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _secondaryColor, width: 2),
        ),
      ),
    );
  }

  Widget _buildIpPinPad({
    required TextEditingController controller,
    required bool enabled,
  }) {
    Widget key(String label, VoidCallback onTap) {
      return SizedBox(
        width: 38,
        height: 34,
        child: OutlinedButton(
          onPressed: enabled ? onTap : null,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            side: BorderSide(color: _borderColor),
            foregroundColor: _textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    void append(String value) {
      controller.text = '${controller.text}$value';
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }

    void backspace() {
      final text = controller.text;
      if (text.isEmpty) {
        return;
      }
      controller.text = text.substring(0, text.length - 1);
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        key('1', () => append('1')),
        key('2', () => append('2')),
        key('3', () => append('3')),
        key('4', () => append('4')),
        key('5', () => append('5')),
        key('6', () => append('6')),
        key('7', () => append('7')),
        key('8', () => append('8')),
        key('9', () => append('9')),
        key('.', () => append('.')),
        key('0', () => append('0')),
        key('<', backspace),
      ],
    );
  }

  Widget _buildSettingsTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      style: const TextStyle(color: _textPrimary),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _textMuted),
        hintStyle: TextStyle(color: _textMuted.withValues(alpha: 0.6)),
        filled: true,
        fillColor: _surfaceColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _secondaryColor, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _borderColor.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  Widget _buildServiceFeeCard() {
    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ნაგულისხმევი საკომისიო',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Switch(
                  value: serviceFeeEnabledByDefault,
                  activeThumbColor: _secondaryColor,
                  onChanged: onServiceFeeEnabledByDefaultChanged,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    serviceFeeEnabledByDefault
                        ? 'საკომისიო ავტომატურად ემატება ახალ შეკვეთებს.'
                        : 'საკომისიო ნაგულისხმევად გამორთულია ახალი შეკვეთებისთვის.',
                    style: const TextStyle(color: _textMuted, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: serviceFeeController,
              enabled: !isSavingServiceFee,
              keyboardType: const TextInputType.numberWithOptions(
                signed: false,
                decimal: true,
              ),
              style: const TextStyle(color: _textPrimary),
              decoration: InputDecoration(
                labelText:
                    'საკომისიოს პროცენტი',
                hintText: 'მაგ. 10',
                suffixText: '%',
                suffixStyle: const TextStyle(color: _textMuted),
                labelStyle: const TextStyle(color: _textMuted),
                hintStyle: TextStyle(color: _textMuted),
                filled: true,
                fillColor: _surfaceColor,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: _secondaryColor,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'მიმდინარე განაკვეთი: $serviceFeePercentDisplay% (გამოიყენება ჩეკებსა და ანგარიშებში).',
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 280,
                child: ElevatedButton.icon(
                  onPressed: isSavingServiceFee
                      ? null
                      : onSaveServiceFeeSettings,
                  style: _primaryButtonStyle(),
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: Text(
                    isSavingServiceFee
                        ? 'შენახვა...'
                        : 'საკომისიოს განახლება',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
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
                    color: _textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? _textPrimary,
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
                style: const TextStyle(color: _textMuted, fontSize: 12),
              ),
            ),
        ],
      ),
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
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderColor),
      ),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'შიდა თვიური ანგარიში',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'მოარგეთ პერიოდი, ხარჯები და მარჟა თქვენი ბიზნესის მოდელს — შედეგები ახლდება მყისიერად.',
              style: TextStyle(color: _textMuted, fontSize: 13),
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
                        style: const TextStyle(color: _textPrimary),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  onSelectedMonthlyReportMonthChanged(value);
                }
              },
              style: const TextStyle(color: _textPrimary),
              iconEnabledColor: _textMuted,
              decoration: InputDecoration(
                filled: true,
                fillColor: _surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
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
                          style: const TextStyle(color: _textPrimary),
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
                    style: const TextStyle(color: _textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _surfaceColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderColor),
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
                          style: const TextStyle(color: _textPrimary),
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
                    style: const TextStyle(color: _textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _surfaceColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderColor),
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
                  child: _buildSettingsTextField(
                    controller: monthlyReportLeaseController,
                    label:
                        'ქირის თვიური ხარჯი (₾)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !isBusy,
                    onChanged: (_) => onRefreshMonthlyReportPreview(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSettingsTextField(
                    controller: monthlyReportStaffDailyController,
                    label:
                        'თანამშრომლის დღიური ხარჯი (₾)',
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
            _buildSettingsTextField(
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
                    style: const TextStyle(color: _textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'საკვების მოგების მარჟა (%)',
              style: TextStyle(color: _textMuted, fontSize: 12),
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
              const Divider(color: _borderColor),
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
                label:
                    'ოპერაციების რაოდენობა',
                value: summary.transactionCount.toString(),
              ),
              _buildMonthlySummaryRow(
                label: 'საშუალო ჩეკი',
                value: currencyFormatter.format(summary.averageTicket),
              ),
              _buildMonthlySummaryRow(
                label:
                    'დღიური საშუალო გაყიდვა',
                value: currencyFormatter.format(summary.dailyAverageSales),
              ),
              _buildMonthlySummaryRow(
                label:
                    'საკვების თვითღირებულება',
                value: currencyFormatter.format(summary.foodCost),
              ),
              _buildMonthlySummaryRow(
                label:
                    'თანამშრომლების ხარჯი',
                value: currencyFormatter.format(summary.staffCost),
              ),
              _buildMonthlySummaryRow(
                label: 'ქირა',
                value: currencyFormatter.format(summary.leaseCost),
              ),
              _buildMonthlySummaryRow(
                label:
                    'საერთო ოპერაციული ხარჯი',
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
            Text(
              'აირჩიეთ ფორმატი: Excel (XLSX) ან PDF (Save As).',
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: isSavingMonthlyReportConfig
                      ? null
                      : onSaveMonthlyReportConfig,
                  style: _primaryButtonStyle(),
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
                  style: _outlineButtonStyle(),
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
                  style: _outlineButtonStyle(),
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
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderColor),
      ),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DateTime>(
                    initialValue: fullReportMonthOptions.contains(fullReportStartMonth)
                        ? fullReportStartMonth
                        : null,
                    items: fullReportMonthOptions
                        .map(
                          (date) => DropdownMenuItem<DateTime>(
                            value: date,
                            child: Text(
                              '${getGeorgianMonthName(date.month)} ${date.year}',
                              style: const TextStyle(color: _textPrimary),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: isBusy
                        ? null
                        : (value) {
                            if (value != null) onFullReportStartMonthChanged(value);
                          },
                    decoration: InputDecoration(
                      labelText: 'საწყისი თვე',
                      filled: true,
                      fillColor: _surfaceColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<DateTime>(
                    initialValue: fullReportMonthOptions.contains(fullReportEndMonth)
                        ? fullReportEndMonth
                        : null,
                    items: fullReportMonthOptions
                        .map(
                          (date) => DropdownMenuItem<DateTime>(
                            value: date,
                            child: Text(
                              '${getGeorgianMonthName(date.month)} ${date.year}',
                              style: const TextStyle(color: _textPrimary),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: isBusy
                        ? null
                        : (value) {
                            if (value != null) onFullReportEndMonthChanged(value);
                          },
                    decoration: InputDecoration(
                      labelText: 'ბოლო თვე',
                      filled: true,
                      fillColor: _surfaceColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
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
                  child: _buildSettingsTextField(
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
                  child: _buildSettingsTextField(
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
                    style: const TextStyle(color: _textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'საკვების მოგების მარჟა (%)',
              style: TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (fullReportPreviewMonths.isEmpty)
              const Text(
                'არჩეულ დიაპაზონში გაყიდვები არ მოიძებნა (0 თვეები ავტომატურად დამალულია).',
                style: TextStyle(color: _textMuted, fontSize: 13),
              )
            else ...[
              const Text(
                'თვეების შეჯამება',
                style: TextStyle(
                  color: _textPrimary,
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
              const Divider(color: _borderColor),
              _buildMonthlySummaryRow(
                label: 'სრული გაყიდვები (ყველა დრო)',
                value: currencyFormatter.format(fullReportTotalSalesAllTime),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onGenerateFullReportXlsx,
                  style: _outlineButtonStyle(),
                  icon: const Icon(Icons.table_view),
                  label: Text(
                    isBusy ? 'შექმნა...' : 'სრული XLSX ანგარიშის შექმნა',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onGenerateFullReportPdf,
                  style: _outlineButtonStyle(),
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

  Widget _buildCancellationPasswordCard() {
    final statusLabel = isCancellationPasswordSet
        ? 'გაუქმების პაროლი აქტიურია.'
        : 'გაუქმების პაროლი ჯერ არ არის დაყენებული.';
    final statusColor = isCancellationPasswordSet
        ? const Color(0xFF16A34A)
        : const Color(0xFFEA580C);

    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _borderColor),
      ),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'გაუქმების დადასტურების პაროლი',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  isCancellationPasswordSet
                      ? Icons.shield
                      : Icons.warning_amber,
                  color: statusColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cancellationPasswordUpdatedAt != null
                        ? '$statusLabel ბოლოს განახლდა ${formatRelativeTime(cancellationPasswordUpdatedAt!)} (${formatDateTimeDisplay(cancellationPasswordUpdatedAt!)}).'
                        : statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSettingsTextField(
              controller: currentCancellationPasswordController,
              label: 'მიმდინარე პაროლი',
              enabled:
                  isCancellationPasswordSet && !isSavingCancellationPassword,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildSettingsTextField(
              controller: newCancellationPasswordController,
              label: 'ახალი პაროლი (6 ციფრი)',
              enabled: !isSavingCancellationPassword,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildSettingsTextField(
              controller: confirmCancellationPasswordController,
              label:
                  'გაიმეორეთ ახალი პაროლი',
              enabled: !isSavingCancellationPassword,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildSettingsTextField(
              controller: cancellationPasswordHintController,
              label: 'პაროლის მინიშნება',
              hint:
                  'მოკლე შეხსენება ადმინებისთვის',
              enabled: !isSavingCancellationPassword,
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 280,
                child: ElevatedButton.icon(
                  onPressed: isSavingCancellationPassword
                      ? null
                      : onSaveCancellationPassword,
                  style: _primaryButtonStyle(),
                  icon: const Icon(Icons.save),
                  label: Text(
                    isSavingCancellationPassword
                        ? 'შენახვა...'
                        : isCancellationPasswordSet
                        ? 'პაროლის განახლება'
                        : 'პაროლის დაყენება',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableOwnershipCard() {
    final modeTitle = restrictTableCloseToOwner
        ? 'რეჟიმი ჩართულია: მხოლოდ მფლობელი ხურავს მაგიდას'
        : 'რეჟიმი გამორთულია: ყველა ოფიციანტს შეუძლია დახურვა';

    final modeDescription = restrictTableCloseToOwner
        ? 'როდესაც ჩართულია, მაგიდის დახურვა შეუძლია მხოლოდ იმ ოფიციანტს, ვინც გახსნა/აიღო მაგიდა. ეს იცავს პასუხისმგებლობას და ამცირებს შეცდომებს.'
        : 'როდესაც გამორთულია, ნებისმიერ უფლებამოსილ ოფიციანტს შეუძლია ნებისმიერი მაგიდის დახურვა. ეს რეჟიმი სწრაფია ცვლაში, მაგრამ ნაკლებად მკაცრია კონტროლში.';

    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    modeTitle,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: restrictTableCloseToOwner
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    restrictTableCloseToOwner ? 'ON' : 'OFF',
                    style: const TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              modeDescription,
              style: const TextStyle(color: _textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor),
              ),
              child: const Text(
                'მაგალითი: ჩართულ რეჟიმში, ოფიციანტი A-ს გახსნილ მაგიდას ოფიციანტი B ვერ დახურავს.',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Switch(
              value: restrictTableCloseToOwner,
              activeThumbColor: _secondaryColor,
              onChanged: isSavingTableOwnershipSettings
                  ? null
                  : onRestrictTableCloseToOwnerChanged,
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 280,
                child: ElevatedButton.icon(
                  onPressed: isSavingTableOwnershipSettings
                      ? null
                      : onSaveTableOwnershipSettings,
                  style: _primaryButtonStyle(),
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: Text(
                    isSavingTableOwnershipSettings
                        ? 'შენახვა...'
                        : 'პარამეტრის შენახვა',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalizationCard() {
    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: defaultLanguageSetting,
              decoration: InputDecoration(
                filled: true,
                fillColor: _surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'ka', child: Text('Georgian (KA)')),
                DropdownMenuItem(value: 'en', child: Text('English (EN)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  onDefaultLanguageSettingChanged(value);
                }
              },
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 280,
                child: ElevatedButton.icon(
                  onPressed: isSavingLocalization
                      ? null
                      : onSaveLocalizationSettings,
                  style: _primaryButtonStyle(),
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: Text(
                    isSavingLocalization
                        ? 'შენახვა...'
                        : 'ენის პარამეტრის შენახვა',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatioPresetChip({required String label, required double value}) {
    final isSelected = (monthlyReportProfitRatio - value).abs() < 0.005;
    return ChoiceChip(
      label: Text(
        label,
        style: const TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFFBFDBFE),
      backgroundColor: _surfaceColor,
      onSelected: (_) => onMonthlyReportProfitRatioChanged(value),
    );
  }

  Widget _buildBackupCard() {
    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'სარეზერვო ასლი და აღდგენა',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'მოიცავს მომხმარებლებს, მენიუს, მაგიდებს, გაყიდვებს, პაკეტებს, ჯავშნებსა და პარამეტრებს.',
              style: TextStyle(color: _textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (lastBackupPath != null)
              SelectableText(
                'ბოლო ასლი: $lastBackupPath',
                style: const TextStyle(color: _secondaryColor, fontSize: 12),
              ),
            if (lastRestorePath != null)
              SelectableText(
                'ბოლო აღდგენა: $lastRestorePath',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 12),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 360,
                child: ElevatedButton.icon(
                  onPressed: isCreatingBackup ? null : onCreateBackupFile,
                  style: _primaryButtonStyle(),
                  icon: const Icon(Icons.cloud_download, size: 20),
                  label: Text(
                    isCreatingBackup
                        ? 'შექმნა...'
                        : 'სარეზერვო ფაილის შექმნა',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 360,
                child: OutlinedButton.icon(
                  onPressed: isRestoringBackup ? null : onRestoreBackupFromFile,
                  style: _outlineButtonStyle(),
                  icon: const Icon(Icons.restore, size: 20),
                  label: Text(
                    isRestoringBackup
                        ? 'აღდგენა...'
                        : 'სარეზერვო ასლიდან აღდგენა',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
