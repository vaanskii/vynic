import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_common_section_widgets.dart';

class HomeAdminToolsSection extends StatelessWidget {
  const HomeAdminToolsSection({
    super.key,
    required this.onOpenAdminPanel,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
  });

  final VoidCallback onOpenAdminPanel;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeSectionTitle(
            icon: Icons.admin_panel_settings,
            title: 'ადმინისტრატორის ზონა',
            subtitle:
                'მართე მენიუ, მოწყობილობები და სისტემის პარამეტრები ერთობლივად.',
            primaryColor: primaryColor,
            textPrimary: textPrimary,
            mutedText: mutedText,
          ),
          const SizedBox(height: 20),
          HomeActionCard(
            icon: Icons.dashboard_customize_outlined,
            title: 'გადადით ადმინისტრატორის პანელში',
            description:
                'განაახლე მენიუს ფასები, მართე პრინტერები და განახორციელე სისტემის კონფიგურაცია.',
            actions: [
              HomePrimaryActionButton(
                label: 'ადმინისტრატორის პანელი',
                icon: Icons.open_in_new,
                onPressed: onOpenAdminPanel,
                secondaryColor: secondaryColor,
              ),
            ],
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            textPrimary: textPrimary,
            mutedText: mutedText,
          ),
        ],
      ),
    );
  }
}
