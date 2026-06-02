import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';

class HomeTopBarSection extends StatelessWidget {
  const HomeTopBarSection({
    super.key,
    required this.user,
    required this.currentFloor,
    required this.onSwitchFloor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.surfaceColor,
    required this.textPrimary,
    required this.mutedText,
    required this.showFloorSwitcher,
    this.onToggleSidebar,
    this.notificationUnreadCount = 0,
    this.onNotificationTap,
  });

  final User user;
  final int currentFloor;
  final ValueChanged<int> onSwitchFloor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color surfaceColor;
  final Color textPrimary;
  final Color mutedText;
  final bool showFloorSwitcher;
  final VoidCallback? onToggleSidebar;

  /// Unread badge for mobile-origin / POS notification panel (Windows).
  final int notificationUnreadCount;
  final VoidCallback? onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: primaryColor.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                return _buildMobileLayout();
              }
              return _buildDesktopLayout();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (onToggleSidebar != null)
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: InkWell(
                  onTap: onToggleSidebar,
                  borderRadius: BorderRadius.circular(8),
                  child: Icon(
                    Icons.menu,
                    color: primaryColor,
                    size: 28,
                  ),
                ),
              ),
            Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(2),
              child: Image.asset('assets/logo/vynic.png', fit: BoxFit.contain),
            ),
            const Spacer(),
            if (onNotificationTap != null) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildNotificationBell(),
              ),
            ],
            if (showFloorSwitcher) _buildMobileFloorSwitcher(),
          ],
        ),
        const SizedBox(height: 16),
        _buildUserInfo(isMobile: true),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onToggleSidebar != null)
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 24.0),
            child: InkWell(
              onTap: onToggleSidebar,
              borderRadius: BorderRadius.circular(8),
              child: Icon(
                Icons.menu,
                color: primaryColor,
                size: 32,
              ),
            ),
          ),
        Container(
          height: 80,
          width: 80,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(2),
          child: Image.asset('assets/logo/vynic.png', fit: BoxFit.contain),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildUserInfo(isMobile: false),
        ),
        if (onNotificationTap != null) ...[
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _buildNotificationBell(),
          ),
        ],
        if (showFloorSwitcher) ...[
          const SizedBox(width: 24),
          _buildDesktopFloorSwitcher(),
        ],
      ],
    );
  }

  Widget _buildUserInfo({required bool isMobile}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'მოგესალმებით, ${user.username}!',
          style: TextStyle(
            color: textPrimary,
            fontSize: isMobile ? 18 : 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: isMobile ? 12 : 18),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: user.isManager
                    ? secondaryColor
                    : user.isSupervisor
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFF38BDF8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                user.roleLabelKa,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_month,
                  size: 18,
                  color: primaryColor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  DatabaseService.getGeorgianFormattedDate(
                    DatabaseService.getCurrentDate(),
                  ),
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopFloorSwitcher() {
    return SizedBox(
      height: 100,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFloorButton(1, isMobile: false),
            const SizedBox(height: 4),
            _buildFloorButton(2, isMobile: false),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileFloorSwitcher() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFloorButton(1, isMobile: true),
          const SizedBox(width: 4),
          _buildFloorButton(2, isMobile: true),
        ],
      ),
    );
  }

  Widget _buildNotificationBell() {
    final onTap = onNotificationTap;
    if (onTap == null) return const SizedBox.shrink();

    return Tooltip(
      message: 'შეტყობინებები',
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          IconButton(
            onPressed: onTap,
            splashRadius: 22,
            icon: Icon(
              Icons.notifications_outlined,
              color: primaryColor,
              size: 26,
            ),
          ),
          if (notificationUnreadCount > 0)
            Positioned(
              right: 4,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(999),
                ),
                constraints: const BoxConstraints(minWidth: 18),
                child: Text(
                  notificationUnreadCount > 99
                      ? '99+'
                      : '$notificationUnreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFloorButton(int floor, {required bool isMobile}) {
    final isActive = currentFloor == floor;
    final label = 'სართული $floor';

    return Semantics(
      selected: isActive,
      button: true,
      label: label,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isActive ? null : () => onSwitchFloor(floor),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 16,
              vertical: isMobile ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: isActive ? primaryColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? Colors.transparent
                    : primaryColor.withValues(alpha: 0.2),
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.24),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : primaryColor,
                fontWeight: FontWeight.w600,
                fontSize: isMobile ? 12 : 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
