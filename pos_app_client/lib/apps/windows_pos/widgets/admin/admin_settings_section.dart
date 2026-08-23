import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/venue_identity_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:flutter/foundation.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_form_controls.dart';

typedef AsyncVoidCallback = Future<void> Function();

/// The Settings tab: restaurant configuration and access control.
///
/// Reporting tooling (monthly + full report) moved to the sales report
/// section, and backup/restore moved to the connection section — both were
/// tools that happened to be parked here rather than settings.
class AdminSettingsSection extends StatelessWidget {
  const AdminSettingsSection({
    super.key,
    required this.dataBackup,
    required this.formatDateTimeDisplay,
    required this.formatRelativeTime,
    required this.serviceFeeController,
    required this.currentCancellationPasswordController,
    required this.newCancellationPasswordController,
    required this.confirmCancellationPasswordController,
    required this.cancellationPasswordHintController,
    required this.serviceFeeEnabledByDefault,
    required this.onServiceFeeEnabledByDefaultChanged,
    required this.receiptServiceFeeLineVisible,
    required this.onReceiptServiceFeeLineVisibleChanged,
    required this.closeReceiptServiceFeeLineVisible,
    required this.onCloseReceiptServiceFeeLineVisibleChanged,
    required this.serviceFeePercentDisplay,
    required this.isSavingServiceFee,
    required this.defaultLanguageSetting,
    required this.onDefaultLanguageSettingChanged,
    required this.isSavingLocalization,
    required this.isCancellationPasswordSet,
    required this.isSavingCancellationPassword,
    required this.cancellationPasswordUpdatedAt,
    required this.restrictTableCloseToOwner,
    required this.onRestrictTableCloseToOwnerChanged,
    required this.isSavingTableOwnershipSettings,
    required this.onSaveServiceFeeSettings,
    required this.onSaveCancellationPassword,
    required this.onSaveTableOwnershipSettings,
    required this.onSaveLocalizationSettings,
  });

  /// Backup and restore. Small enough that it does not warrant a destination
  /// of its own — it sits at the foot of Settings, where the rest of the
  /// terminal's housekeeping lives.
  final Widget dataBackup;

  final String Function(DateTime) formatDateTimeDisplay;
  final String Function(DateTime) formatRelativeTime;

  final TextEditingController serviceFeeController;
  final TextEditingController currentCancellationPasswordController;
  final TextEditingController newCancellationPasswordController;
  final TextEditingController confirmCancellationPasswordController;
  final TextEditingController cancellationPasswordHintController;

  final bool serviceFeeEnabledByDefault;
  final ValueChanged<bool> onServiceFeeEnabledByDefaultChanged;
  final bool receiptServiceFeeLineVisible;
  final ValueChanged<bool> onReceiptServiceFeeLineVisibleChanged;

  /// The closing (fiscal) check is a separate document from the customer
  /// receipt, so it carries its own switch.
  final bool closeReceiptServiceFeeLineVisible;
  final ValueChanged<bool> onCloseReceiptServiceFeeLineVisibleChanged;
  final String serviceFeePercentDisplay;
  final bool isSavingServiceFee;
  final String defaultLanguageSetting;
  final ValueChanged<String> onDefaultLanguageSettingChanged;
  final bool isSavingLocalization;
  final bool isCancellationPasswordSet;
  final bool isSavingCancellationPassword;
  final DateTime? cancellationPasswordUpdatedAt;
  final bool restrictTableCloseToOwner;
  final ValueChanged<bool> onRestrictTableCloseToOwnerChanged;
  final bool isSavingTableOwnershipSettings;

  final AsyncVoidCallback onSaveServiceFeeSettings;
  final AsyncVoidCallback onSaveCancellationPassword;
  final AsyncVoidCallback onSaveTableOwnershipSettings;
  final AsyncVoidCallback onSaveLocalizationSettings;
  static const Color _accent = AdminDesign.accentDark;
  static const Color _accentDark = AdminDesign.accentDark;
  static const Color _panelSoft = AdminDesign.panelSoft;
  static const Color _cardColor = Colors.white;
  static const Color _borderColor = AdminDesign.border;
  static const Color _textPrimary = AdminDesign.text;
  static const Color _textMuted = AdminDesign.muted;

  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: _cardColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _borderColor),
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
                isMobile ? 16 : 22,
                isMobile ? 16 : 18,
                isMobile ? 16 : 22,
                18,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: adminSectionMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModernHeader(),
                    const SizedBox(height: 14),
                    _buildStatusStrip(),
                    const SizedBox(height: 16),
                    _buildSettingsHeader(
                      icon: Icons.storefront,
                      title: 'რესტორნის მონაცემები',
                      subtitle:
                          'სახელი, მისამართი, ტელეფონი და ლოგო — ჩეკის თავში იბეჭდება.',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: AdminDesign.panelDecoration(),
                      child: const VenueIdentityCard(),
                    ),
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
                      icon: Icons.backup_outlined,
                      title: 'სარეზერვო ასლი',
                      subtitle:
                          'შექმენით ბაზის სრული ასლი ან აღადგინეთ ფაილიდან.',
                    ),
                    const SizedBox(height: 12),
                    dataBackup,
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
                  'რესტორნის კონფიგურაცია, უსაფრთხოება და წვდომის უფლებები.',
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
            background: AdminTones.successFill,
            border: AdminTones.successBorder,
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
          ],
        ),
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
                PosToggle(
                  value: serviceFeeEnabledByDefault,
                  semanticLabel: 'საკომისიო ნაგულისხმევად',
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
            AdminPosTextField(
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
                PosToggle(
                  value: receiptServiceFeeLineVisible,
                  semanticLabel: 'სერვისის ხაზი ჩეკზე',
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
            const SizedBox(height: 20),
            const Divider(height: 1, color: _borderColor),
            const SizedBox(height: 20),
            const Text(
              'დახურვის ჩეკზე ასახვა',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                PosToggle(
                  value: closeReceiptServiceFeeLineVisible,
                  semanticLabel: 'სერვისის ხაზი დახურვის ჩეკზე',
                  onChanged: onCloseReceiptServiceFeeLineVisibleChanged,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    closeReceiptServiceFeeLineVisible
                        ? 'მაგიდის დახურვის ჩეკზე საკომისიო ცალკე ხაზად იბეჭდება.'
                        : 'მაგიდის დახურვის ჩეკზე საკომისიოს ცალკე ხაზი არ იბეჭდება.',
                    style: const TextStyle(color: _textMuted, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'ეს ეხება მხოლოდ იმ ჩეკს, რომელიც მაგიდის დახურვისას იბეჭდება '
              '(ნაღდი, ბარათი ან გაყოფილი გადახდა). ჯამური თანხა უცვლელია.',
              style: TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            AdminActionRow(
              children: [
                SizedBox(
                  width: 280,
                  child: ElevatedButton.icon(
                    onPressed: isSavingServiceFee
                        ? null
                        : onSaveServiceFeeSettings,
                    style: AdminFormButtons.primary(),
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

  Widget _buildCancellationPasswordCard() {
    final statusLabel = isCancellationPasswordSet
        ? 'გაუქმების პაროლი აქტიურია.'
        : 'გაუქმების პაროლი ჯერ არ არის დაყენებული.';
    final statusColor = isCancellationPasswordSet
        ? AdminTones.successText
        : AdminTones.warningText;

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
            AdminPosTextField(
              controller: currentCancellationPasswordController,
              label: 'მიმდინარე პაროლი',
              enabled:
                  isCancellationPasswordSet && !isSavingCancellationPassword,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            AdminPosTextField(
              controller: newCancellationPasswordController,
              label: 'ახალი პაროლი (6 ციფრი)',
              enabled: !isSavingCancellationPassword,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            AdminPosTextField(
              controller: confirmCancellationPasswordController,
              label: 'გაიმეორეთ ახალი პაროლი',
              enabled: !isSavingCancellationPassword,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            AdminPosTextField(
              controller: cancellationPasswordHintController,
              label: 'პაროლის მინიშნება',
              hint: 'მოკლე შეხსენება ადმინებისთვის',
              enabled: !isSavingCancellationPassword,
            ),
            const SizedBox(height: 20),
            AdminActionRow(
              children: [
                SizedBox(
                  width: 280,
                  child: ElevatedButton.icon(
                    onPressed: isSavingCancellationPassword
                        ? null
                        : onSaveCancellationPassword,
                    style: AdminFormButtons.primary(),
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
                        ? AdminTones.successFill
                        : AdminDesign.border,
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
            PosToggle(
              value: restrictTableCloseToOwner,
              semanticLabel: 'მაგიდას მხოლოდ გამხსნელი ხურავს',
              onChanged: isSavingTableOwnershipSettings
                  ? null
                  : onRestrictTableCloseToOwnerChanged,
            ),
            const SizedBox(height: 24),
            AdminActionRow(
              children: [
                SizedBox(
                  width: 280,
                  child: ElevatedButton.icon(
                    onPressed: isSavingTableOwnershipSettings
                        ? null
                        : onSaveTableOwnershipSettings,
                    style: AdminFormButtons.primary(),
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
            AdminActionRow(
              children: [
                SizedBox(
                  width: 280,
                  child: ElevatedButton.icon(
                    onPressed: isSavingLocalization
                        ? null
                        : onSaveLocalizationSettings,
                    style: AdminFormButtons.primary(),
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
}
