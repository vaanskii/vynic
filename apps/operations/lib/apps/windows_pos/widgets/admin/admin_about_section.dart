import 'package:vynic/core/widgets/pos_text.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/apps/windows_pos/widgets/pos_quit_action.dart';
import 'package:vynic/apps/windows_pos/widgets/update/pos_update_ui.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';

class AdminAboutSection extends StatelessWidget {
  const AdminAboutSection({super.key, this.updater});
  final PosUpdater? updater;

  @override
  Widget build(BuildContext context) {
    final settings = DatabaseCore.settingsBox;
    final terminal = settings != null && settings.isOpen
        ? settings.get('enrolledDeviceName') as String?
        : null;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            key: const ValueKey('pos-about-content'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PosText(
                  'პროგრამის შესახებ',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AdminDesign.text,
                  ),
                ),
                const SizedBox(height: 8),
                const PosText(
                  'Vynic POS · Windows',
                  style: TextStyle(fontSize: 16, color: AdminDesign.muted),
                ),
                const SizedBox(height: 24),
                PosUpdateSettings(updater: updater),
                const SizedBox(height: 24),
                const PosText(
                  'ტერმინალის ინფორმაცია',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AdminDesign.text,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'რესტორანი',
                  value:
                      EdgeDeviceCredentialStore.venueName ??
                      'არ არის დაკავშირებული',
                ),
                _InfoRow(label: 'ტერმინალი', value: terminal ?? '—'),
                const Divider(height: 32),
                const PosText(
                  'მონაცემები და განახლება',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AdminDesign.text,
                  ),
                ),
                const SizedBox(height: 10),
                const PosText(
                  'შეკვეთები და მაგიდები ინახება ამ ტერმინალზე. პროგრამის განახლებისას ისინი შენარჩუნდება.\n\nგანახლების დაყენებამდე დაასრულეთ მიმდინარე გადახდა ან მაგიდის დახურვა.',
                  style: TextStyle(height: 1.5, color: AdminDesign.muted),
                ),
                const SizedBox(height: 24),
                const PosQuitAction(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = PosText(
          label,
          style: const TextStyle(color: AdminDesign.muted),
        );
        final valueWidget = SelectableText(
          value,
          style: const TextStyle(
            color: AdminDesign.text,
            fontWeight: FontWeight.w600,
          ),
        );
        if (constraints.maxWidth <
            420 * MediaQuery.textScalerOf(context).scale(1)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelWidget, const SizedBox(height: 4), valueWidget],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: labelWidget),
            const SizedBox(width: 16),
            Expanded(child: valueWidget),
          ],
        );
      },
    ),
  );
}
