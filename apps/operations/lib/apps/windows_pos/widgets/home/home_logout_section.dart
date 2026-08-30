import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_common_section_widgets.dart';

class HomeLogoutSection extends StatelessWidget {
  const HomeLogoutSection({
    super.key,
    required this.username,
    required this.role,
    required this.onLogout,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
  });

  final String username;
  final String role;
  final VoidCallback onLogout;
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
            icon: Icons.logout,
            title: 'გამოსვლა',
            subtitle:
                'დაასრულე მიმდინარე სესია და დაბრუნდი ავტორიზაციის ეკრანზე უსაფრთხოდ.',
            primaryColor: primaryColor,
            textPrimary: textPrimary,
            mutedText: mutedText,
          ),
          const SizedBox(height: 20),
          HomeActionCard(
            icon: Icons.logout,
            title: 'სესიის დასრულება',
            description:
                'გთხოვ, გადაამოწმე ყველა ღია შეკვეთა დასრულებულია თუ არა სანამ გახვალ.',
            actions: [
              HomePrimaryActionButton(
                label: 'გამოსვლა',
                icon: Icons.logout,
                onPressed: onLogout,
                secondaryColor: secondaryColor,
              ),
            ],
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            textPrimary: textPrimary,
            mutedText: mutedText,
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryColor.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'მომხმარებელი: $username',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'როლი: ${role.toUpperCase()}',
                  style: TextStyle(color: mutedText, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
