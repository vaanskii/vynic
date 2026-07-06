import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_colors.dart';

/// Persistent staff card + admin-panel button shown alongside every Home
/// tab's content (Tables, Calculator, Takeaway, Reservations, X-report) —
/// a single shared rail rather than each screen carrying its own copy.
class HomeStaffAdminRail extends StatelessWidget {
  const HomeStaffAdminRail({
    super.key,
    required this.username,
    required this.roleLabel,
    this.onStaffSwitchTap,
    this.onOpenAdminPanel,
  });

  /// The staff member currently operating the POS and their role.
  final String username;
  final String roleLabel;

  /// Tapping the staff card locks the terminal (PIN required to continue /
  /// switch). Null hides the lock affordance (card stays static).
  final VoidCallback? onStaffSwitchTap;

  /// Opens the Management Center. Null hides the button entirely — the
  /// caller only passes this for manager/supervisor (`canAccessManagementCenter`).
  final VoidCallback? onOpenAdminPanel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (onOpenAdminPanel != null) ...[
          _AdminPanelButton(onTap: onOpenAdminPanel!),
          const SizedBox(height: 10),
        ],
        if (username.trim().isNotEmpty)
          _StaffCard(
            username: username,
            roleLabel: roleLabel,
            onLockTap: onStaffSwitchTap,
          ),
      ],
    );
  }
}

/// The current staff member's card — name, role, and (if wired) a lock
/// button to switch/lock the terminal. Flat style (bordered, no
/// shadow/gradient) matching the rest of the Vynic primitives.
class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.username,
    required this.roleLabel,
    this.onLockTap,
  });

  final String username;
  final String roleLabel;
  final VoidCallback? onLockTap;

  (IconData, Color) get _roleVisual => switch (roleLabel.trim()) {
    'მენეჯერი' => (
      Icons.admin_panel_settings_outlined,
      const Color(0xFFB45309),
    ),
    'სუპერვაიზერი' => (
      Icons.supervisor_account_outlined,
      const Color(0xFF6D28D9),
    ),
    'ოფიციანტი' => (Icons.room_service_outlined, VynicColors.info),
    _ => (Icons.badge_outlined, const Color(0xFF3F7A5A)),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _roleVisual;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: VynicColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VynicColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF102033),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5B677A),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onLockTap != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'ჩაკეტვა / სტაფის გადართვა',
              child: InkWell(
                onTap: onLockTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: VynicColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VynicColors.border),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFF5B677A),
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A flat button matching the staff card's style that opens the Management
/// Center — manager/supervisor only (the caller passes null to hide it for
/// waiters, same rule as everywhere else admin access is gated).
class _AdminPanelButton extends StatelessWidget {
  const _AdminPanelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: VynicColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VynicColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.settings_suggest_outlined,
              color: Color(0xFF075E6B),
              size: 20,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'მართვის ცენტრი',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF102033),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9AA6B2),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
