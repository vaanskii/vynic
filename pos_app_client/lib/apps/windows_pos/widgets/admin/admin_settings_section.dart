import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/pos/monthly_report_service.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';

typedef AsyncVoidCallback = Future<void> Function();

class AdminSettingsSection extends StatelessWidget {
  const AdminSettingsSection({
    super.key,
    required this.formatDateTimeDisplay,
    required this.formatRelativeTime,
    required this.getGeorgianMonthName,
    required this.getDaysInMonth,
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
    required this.receiptServiceFeeLineVisible,
    required this.onReceiptServiceFeeLineVisibleChanged,
    required this.serviceFeePercentDisplay,
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
    required this.onSaveServiceFeeSettings,
    required this.onSaveCancellationPassword,
    required this.onSaveTableOwnershipSettings,
    required this.onSaveLocalizationSettings,
    required this.onCreateBackupFile,
    required this.onRestoreBackupFromFile,
  });
  final String Function(DateTime) formatDateTimeDisplay;
  final String Function(DateTime) formatRelativeTime;
  final String Function(int) getGeorgianMonthName;
  final int Function(DateTime) getDaysInMonth;

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
  final bool receiptServiceFeeLineVisible;
  final ValueChanged<bool> onReceiptServiceFeeLineVisibleChanged;
  final String serviceFeePercentDisplay;
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
  final AsyncVoidCallback onSaveServiceFeeSettings;
  final AsyncVoidCallback onSaveCancellationPassword;
  final AsyncVoidCallback onSaveTableOwnershipSettings;
  final AsyncVoidCallback onSaveLocalizationSettings;
  final AsyncVoidCallback onCreateBackupFile;
  final AsyncVoidCallback onRestoreBackupFromFile;
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _accentDark = Color(0xFF0F766E);
  static const Color _surfaceColor = Color(0xFFF6F7F9);
  static const Color _panelSoft = Color(0xFFF9FAFB);
  static const Color _cardColor = Colors.white;
  static const Color _borderColor = Color(0xFFE5E7EB);
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textMuted = Color(0xFF6B7280);

  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: _accentDark,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 0,
    );
  }

  ButtonStyle _outlineButtonStyle() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      side: const BorderSide(color: _borderColor, width: 1.4),
      foregroundColor: _textPrimary,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: _cardColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _borderColor),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 28,
                isMobile ? 16 : 20,
                isMobile ? 16 : 28,
                18,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModernHeader(),
                    const SizedBox(height: 14),
                    _buildStatusStrip(),
                    const SizedBox(height: 16),
                    _buildSettingsHeader(
                      icon: Icons.percent,
                      title: 'მომსახურების საკომისიო',
                      subtitle:
                          'განაახლეთ მომსახურების საკომისიოს პროცენტი და განსაზღვრეთ ავტომატური გამოყენება.',
                    ),
                    const SizedBox(height: 12),
                    _buildServiceFeeCard(),
                    const SizedBox(height: 18),
                    _buildSettingsHeader(
                      icon: Icons.lock_outline,
                      title: 'გაუქმების პაროლი',
                      subtitle:
                          'მართეთ დადასტურების პაროლი, რომელიც საჭიროა შეკვეთის გაუქმებამდე.',
                    ),
                    const SizedBox(height: 12),
                    _buildCancellationPasswordCard(),
                    const SizedBox(height: 18),
                    _buildSettingsHeader(
                      icon: Icons.table_restaurant,
                      title: 'მაგიდის დახურვის უფლებები',
                      subtitle:
                          'განსაზღვრეთ, შეუძლია თუ არა ყველა ოფიციანტს მაგიდის დახურვა, თუ მხოლოდ მის შემქმნელს.',
                    ),
                    const SizedBox(height: 12),
                    _buildTableOwnershipCard(),
                    const SizedBox(height: 18),
                    _buildSettingsHeader(
                      icon: Icons.language,
                      title: 'ენის პარამეტრები',
                      subtitle:
                          'აირჩიეთ ნაგულისხმევი ენა მენიუს, კლავიატურისა და ბეჭდური ჩეკებისთვის.',
                    ),
                    const SizedBox(height: 12),
                    _buildLocalizationCard(),
                    const SizedBox(height: 18),
                    _buildSettingsHeader(
                      icon: Icons.assessment,
                      title: 'თვიური ანგარიში',
                      subtitle:
                          'დაარეგულირეთ შიდა ხარჯები და შექმენით თვიური ფინანსური ანგარიში.',
                    ),
                    const SizedBox(height: 12),
                    _buildMonthlyReportSettingsCard(),
                    const SizedBox(height: 18),
                    _buildSettingsHeader(
                      icon: Icons.summarize,
                      title: 'სრული ანგარიში',
                      subtitle:
                          'აირჩიეთ თვეების დიაპაზონი, დაამატეთ საჭირო კორექციები და მიიღეთ ერთიანი XLSX ანგარიში.',
                    ),
                    const SizedBox(height: 12),
                    _buildFullReportCard(),
                    const SizedBox(height: 18),
                    _buildSettingsHeader(
                      icon: Icons.save_alt,
                      title: 'მონაცემები და სარეზერვო ასლები',
                      subtitle:
                          'შექმენით ოფლაინ სარეზერვო ასლი მომხმარებლების, მენიუს, ჯავშნებისა და გაყიდვების მონაცემებისთვის.',
                    ),
                    const SizedBox(height: 12),
                    _buildBackupCard(),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomDock(),
        ],
      ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.settings_outlined, color: _accentDark),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'პარამეტრები',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'სისტემის, უსაფრთხოების, ანგარიშებისა და მონაცემების მართვა.',
                  style: TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildStatusBadge(
            icon: Icons.keyboard_alt_outlined,
            label: 'POS კლავიატურა',
            color: _accentDark,
            background: const Color(0xFFECFDF5),
            border: const Color(0xFFA7F3D0),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStrip() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 780;
        final cards = [
          _buildInfoTile(
            icon: Icons.percent_outlined,
            label: 'საკომისიო',
            value: '$serviceFeePercentDisplay%',
            helper: serviceFeeEnabledByDefault ? 'ავტომატურად' : 'ხელით',
          ),
          _buildInfoTile(
            icon: Icons.verified_user_outlined,
            label: 'გაუქმების დაცვა',
            value: isCancellationPasswordSet ? 'აქტიური' : 'არააქტიური',
            helper: isCancellationPasswordSet
                ? 'PIN დაყენებულია'
                : 'საჭიროა PIN',
          ),
          _buildInfoTile(
            icon: Icons.language_outlined,
            label: 'ენა',
            value: defaultLanguageSetting.toUpperCase(),
            helper: 'მენიუ / ჩეკი / კლავიატურა',
          ),
        ];

        if (narrow) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSettingsHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _panelDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _accentDark, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _textMuted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required String helper,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _accentDark, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  helper,
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

  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomDock() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 28,
        12,
        isMobile ? 16 : 28,
        12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borderColor)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.info_outline,
                size: 19,
                color: _accentDark,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'ცვლილებები ინახება შესაბამის ბლოკში. ტექსტისა და ციფრების ველები იყენებს ახალ POS კლავიატურას.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (!isMobile) ...[
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: isRestoringBackup ? null : onRestoreBackupFromFile,
                  style: _outlineButtonStyle(),
                  icon: const Icon(Icons.restore_outlined, size: 20),
                  label: Text(isRestoringBackup ? 'აღდგენა...' : 'აღდგენა'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: isCreatingBackup ? null : onCreateBackupFile,
                style: _primaryButtonStyle(),
                icon: const Icon(Icons.cloud_download_outlined, size: 20),
                label: Text(isCreatingBackup ? 'შექმნა...' : 'Backup'),
              ),
            ),
          ],
        ),
      ),
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
    return Builder(
      builder: (context) {
        final usesNumberKeyboard =
            keyboardType.index == TextInputType.number.index ||
            keyboardType == TextInputType.phone;
        final allowsDecimal =
            keyboardType.index == TextInputType.number.index &&
            keyboardType.decimal == true;

        return TextField(
          controller: controller,
          enabled: enabled,
          readOnly: enabled,
          keyboardType: keyboardType,
          style: const TextStyle(color: _textPrimary),
          onChanged: onChanged,
          onTap: !enabled
              ? null
              : () async {
                  String? updated;
                  if (usesNumberKeyboard) {
                    updated = await showPosNumberKeyboardInputSheet(
                      context: context,
                      initialValue: controller.text,
                      title: label,
                      allowDecimal: allowsDecimal,
                    );
                  } else {
                    updated = await showPosKeyboardInputSheet(
                      context: context,
                      controller: controller,
                      initialLanguage: PosKeyboardLanguage.georgian,
                      title: label,
                    );
                  }

                  if (updated == null) return;
                  if (controller.text != updated) {
                    controller.value = TextEditingValue(
                      text: updated,
                      selection: TextSelection.collapsed(
                        offset: updated.length,
                      ),
                    );
                  }
                  onChanged?.call(controller.text);
                },
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: const TextStyle(color: _textMuted),
            hintStyle: TextStyle(color: _textMuted.withValues(alpha: 0.6)),
            suffixIcon: enabled
                ? Icon(
                    usesNumberKeyboard
                        ? Icons.dialpad_outlined
                        : Icons.keyboard_alt_outlined,
                    color: _accentDark,
                    size: 20,
                  )
                : null,
            filled: true,
            fillColor: enabled ? _panelSoft : _surfaceColor,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _accentDark, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: _borderColor.withValues(alpha: 0.5),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionRow({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: children,
      ),
    );
  }

  Widget _buildServiceFeeCard() {
    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      elevation: 0,
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
                  activeThumbColor: _accentDark,
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
            _buildSettingsTextField(
              controller: serviceFeeController,
              label: 'საკომისიოს პროცენტი',
              hint: 'მაგ. 10',
              enabled: !isSavingServiceFee,
              keyboardType: const TextInputType.numberWithOptions(
                signed: false,
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'მიმდინარე განაკვეთი: $serviceFeePercentDisplay% (გამოიყენება ჩეკებსა და ანგარიშებში).',
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: _borderColor),
            const SizedBox(height: 20),
            const Text(
              'ჩეკზე ასახვა',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Switch(
                  value: receiptServiceFeeLineVisible,
                  activeThumbColor: _accentDark,
                  onChanged: onReceiptServiceFeeLineVisibleChanged,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    receiptServiceFeeLineVisible
                        ? 'ჩეკზე საკომისიო ცალკე ხაზად იბეჭდება.'
                        : 'ჩეკზე საკომისიოს ცალკე ხაზი არ იბეჭდება — თანხა ჯამშია.',
                    style: const TextStyle(color: _textMuted, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'მხოლოდ ჩეკის ვიზუალი იცვლება — ჯამური თანხა და ანგარიშები უცვლელია.',
              style: TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            _buildActionRow(
              children: [
                SizedBox(
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
              ],
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
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _borderColor),
      ),
      elevation: 0,
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
                fillColor: _panelSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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
                      fillColor: _panelSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
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
                      fillColor: _panelSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
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
                  child: _buildSettingsTextField(
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
            Text(
              'აირჩიეთ ფორმატი: Excel (XLSX) ან PDF (Save As).',
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _buildActionRow(
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
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _borderColor),
      ),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
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
                              style: const TextStyle(color: _textPrimary),
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
                      fillColor: _panelSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
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
                              style: const TextStyle(color: _textPrimary),
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
                      fillColor: _panelSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
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
            _buildActionRow(
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
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _borderColor),
      ),
      elevation: 0,
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
              label: 'გაიმეორეთ ახალი პაროლი',
              enabled: !isSavingCancellationPassword,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildSettingsTextField(
              controller: cancellationPasswordHintController,
              label: 'პაროლის მინიშნება',
              hint: 'მოკლე შეხსენება ადმინებისთვის',
              enabled: !isSavingCancellationPassword,
            ),
            const SizedBox(height: 20),
            _buildActionRow(
              children: [
                SizedBox(
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
              ],
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
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      elevation: 0,
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
                color: _panelSoft,
                borderRadius: BorderRadius.circular(8),
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
              activeThumbColor: _accentDark,
              onChanged: isSavingTableOwnershipSettings
                  ? null
                  : onRestrictTableCloseToOwnerChanged,
            ),
            const SizedBox(height: 24),
            _buildActionRow(
              children: [
                SizedBox(
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
              ],
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
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: defaultLanguageSetting,
              decoration: InputDecoration(
                filled: true,
                fillColor: _panelSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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
            _buildActionRow(
              children: [
                SizedBox(
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
              ],
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
      selectedColor: const Color(0xFFCCFBF1),
      backgroundColor: _surfaceColor,
      onSelected: (_) => onMonthlyReportProfitRatioChanged(value),
    );
  }

  Widget _buildBackupCard() {
    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      elevation: 0,
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
                style: const TextStyle(color: _accentDark, fontSize: 12),
              ),
            if (lastRestorePath != null)
              SelectableText(
                'ბოლო აღდგენა: $lastRestorePath',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 12),
              ),
            const SizedBox(height: 12),
            _buildActionRow(
              children: [
                SizedBox(
                  width: 330,
                  child: ElevatedButton.icon(
                    onPressed: isCreatingBackup
                        ? null
                        : () async {
                            debugPrint('[BackupUI] Save backup button clicked');
                            try {
                              await onCreateBackupFile();
                              debugPrint(
                                '[BackupUI] Save backup callback finished',
                              );
                            } catch (e, st) {
                              debugPrint(
                                '[BackupUI] Save backup callback error: $e',
                              );
                              debugPrint('$st');
                            }
                          },
                    style: _primaryButtonStyle(),
                    icon: const Icon(Icons.cloud_download, size: 20),
                    label: Text(
                      isCreatingBackup
                          ? 'შექმნა...'
                          : 'სარეზერვო ფაილის შექმნა',
                    ),
                  ),
                ),
                SizedBox(
                  width: 330,
                  child: OutlinedButton.icon(
                    onPressed: isRestoringBackup
                        ? null
                        : () async {
                            debugPrint(
                              '[BackupUI] Restore backup button clicked',
                            );
                            try {
                              await onRestoreBackupFromFile();
                              debugPrint(
                                '[BackupUI] Restore backup callback finished',
                              );
                            } catch (e, st) {
                              debugPrint(
                                '[BackupUI] Restore backup callback error: $e',
                              );
                              debugPrint('$st');
                            }
                          },
                    style: _outlineButtonStyle(),
                    icon: const Icon(Icons.restore, size: 20),
                    label: Text(
                      isRestoringBackup
                          ? 'აღდგენა...'
                          : 'სარეზერვო ასლიდან აღდგენა',
                    ),
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
