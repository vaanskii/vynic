part of '../mobile_admin_screen.dart';

class _SettingsTab extends StatelessWidget {
  final User user;
  const _SettingsTab({required this.user});

  @override
  Widget build(BuildContext context) {
    final serverUrl = ApiConfig.baseUrl;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsSection(
          title: 'მიმდინარე სესია',
          children: [
            _SettingsTile(
              icon: Icons.person_rounded,
              label: 'მომხმარებელი',
              value: user.username,
            ),
            _SettingsTile(
              icon: Icons.admin_panel_settings_rounded,
              label: 'როლი',
              value: user.isAdmin ? 'ადმინისტრატორი' : 'მენეჯერი',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsSection(
          title: 'სერვერი',
          children: [
            _SettingsTile(
              icon: Icons.dns_rounded,
              label: 'Backend URL',
              value: serverUrl,
              small: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsSection(
          title: 'აპლიკაციის შესახებ',
          children: const [
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              label: 'სახელი',
              value: 'Vynic Manager',
            ),
            _SettingsTile(
              icon: Icons.restaurant_rounded,
              label: 'ვერსია',
              value: '1.0.0',
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(children: children),
          ),
        ],
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool small;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.value,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF64748B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: small ? 12 : 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
