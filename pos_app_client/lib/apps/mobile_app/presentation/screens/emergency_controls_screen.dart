import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/windows_pos/screens/admin_screen.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_glass_ui.dart';

class EmergencyControlsScreen extends StatelessWidget {
  final User user;
  const EmergencyControlsScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MobileGlassTheme.bg,
      appBar: AppBar(
        title: Text(
          'მართვა და პარამეტრები',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: MobileGlassTheme.textPrimary,
          ),
        ),
        backgroundColor: MobileGlassTheme.surfaceCard,
        foregroundColor: MobileGlassTheme.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('სისტემური მართვა'),
            SizedBox(height: 12),
            _buildAdminPanelCard(context),
            SizedBox(height: 24),
            _buildSectionHeader('სწრაფი კონტროლი'),
            SizedBox(height: 12),
            _buildControlToggle(
              'რესტორნის სტატუსი (ღია)',
              true,
              Icons.storefront_rounded,
            ),
            SizedBox(height: 12),
            _buildControlToggle(
              'ონლაინ შეკვეთები',
              false,
              Icons.cloud_done_outlined,
            ),
            SizedBox(height: 24),
            _buildSectionHeader('პერსონალის შეტყობინებები'),
            SizedBox(height: 12),
            _buildActionCard(
              'ახალი განცხადების გაგზავნა',
              Icons.campaign_outlined,
              Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: MobileGlassTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildAdminPanelCard(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => AdminScreen(user: user)),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.settings_suggest_rounded, color: MobileGlassTheme.textPrimary),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'სრული მართვის ცენტრი',
                    style: TextStyle(
                      color: MobileGlassTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'მენიუ, მომხმარებლები, პარამეტრები',
                    style: TextStyle(color: MobileGlassTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildControlToggle(String title, bool value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: MobileGlassTheme.textPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF64748B), size: 22),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: (v) {},
            activeColor: const Color(0xFF10B981),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MobileGlassTheme.textPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          SizedBox(width: 16),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const Spacer(),
          const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF64748B)),
        ],
      ),
    );
  }
}
