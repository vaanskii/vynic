import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:vynic/apps/windows_pos/widgets/home/pos_connection_status_indicator.dart';

class HomeFeatureSwitchItem {
  const HomeFeatureSwitchItem({
    required this.key,
    required this.label,
    required this.icon,
    this.badgeCount,
  });

  final String key;
  final String label;
  final IconData icon;
  final int? badgeCount;
}

class HomeFeatureHeader extends StatefulWidget {
  const HomeFeatureHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.username,
    required this.roleLabel,
    required this.activeKey,
    required this.destinations,
    required this.onHomeTap,
    required this.onDestinationSelected,
    required this.notificationUnreadCount,
    required this.onNotificationTap,
    this.onLogoutTap,
    this.onStaffSwitchTap,
  });

  final String title;
  final IconData icon;
  final String username;
  final String roleLabel;
  final String activeKey;
  final List<HomeFeatureSwitchItem> destinations;
  final VoidCallback onHomeTap;
  final ValueChanged<String> onDestinationSelected;
  final int notificationUnreadCount;
  final VoidCallback onNotificationTap;

  /// Optional — when null the logout button is hidden. The POS home passes null
  /// (logout lives only on the lock screen); the preview still shows it.
  final VoidCallback? onLogoutTap;

  /// Tapping the staff badge opens the quick-switch PIN dialog. Null hides the
  /// affordance (badge stays static).
  final VoidCallback? onStaffSwitchTap;

  @override
  State<HomeFeatureHeader> createState() => _HomeFeatureHeaderState();
}

class _HomeFeatureHeaderState extends State<HomeFeatureHeader> {
  static const _navy = Color(0xFF001F31);
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timeLabel {
    final hour = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final minute = _now.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${_now.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _navy,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 1000;
              return Row(
                children: [
                  _HeaderIconButton(
                    tooltip: 'მთავარ გვერდზე დაბრუნება',
                    icon: Icons.home_rounded,
                    onTap: widget.onHomeTap,
                  ),
                  if (!narrow) ...[
                    const SizedBox(width: 12),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 23),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 145,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.58),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(width: narrow ? 8 : 14),
                  Expanded(child: _buildDirectNavigation()),
                  if (!narrow) ...[
                    const SizedBox(width: 14),
                    const Icon(
                      Icons.schedule_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _timeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Staff + lock control — ALWAYS visible (incl. narrow / 1024px
                  // screens). Collapses to icon-only when narrow.
                  _RoleBadge(
                    label: widget.roleLabel,
                    onLockTap: widget.onStaffSwitchTap,
                    compact: narrow,
                  ),
                  const SizedBox(width: 10),
                  _NotificationButton(
                    unreadCount: widget.notificationUnreadCount,
                    onTap: widget.onNotificationTap,
                  ),
                  const SizedBox(width: 6),
                  PosConnectionStatusIndicator(compact: narrow),
                  if (widget.onLogoutTap != null) ...[
                    const SizedBox(width: 4),
                    _LogoutButton(onTap: widget.onLogoutTap!),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDirectNavigation() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final destination in widget.destinations)
              Flexible(
                child: _DirectNavigationItem(
                  destination: destination,
                  isActive: destination.key == widget.activeKey,
                  onTap: () => widget.onDestinationSelected(destination.key),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _DirectNavigationItem extends StatelessWidget {
  const _DirectNavigationItem({
    required this.destination,
    required this.isActive,
    required this.onTap,
  });

  final HomeFeatureSwitchItem destination;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF63D5FF);
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isActive
            ? activeColor.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: isActive
              ? activeColor.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                destination.icon,
                color: isActive ? activeColor : Colors.white70,
                size: 20,
              ),
              if ((destination.badgeCount ?? 0) > 0)
                Positioned(
                  right: -8,
                  top: -8,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      destination.badgeCount! > 9
                          ? '9+'
                          : '${destination.badgeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? activeColor : Colors.white70,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: destination.label,
      child: InkWell(
        onTap: isActive ? null : onTap,
        borderRadius: BorderRadius.circular(11),
        child: content,
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label, this.onLockTap, this.compact = false});

  final String label;

  /// Tapping the badge locks the terminal (PIN required to continue / switch).
  final VoidCallback? onLockTap;

  /// Icon-only (no role text) to fit narrow top bars (e.g. 1024px screens).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (label.trim()) {
      'მენეჯერი' => (
        Icons.admin_panel_settings_outlined,
        const Color(0xFFFFC857),
      ),
      'სუპერვაიზერი' => (
        Icons.supervisor_account_outlined,
        const Color(0xFFC69CFF),
      ),
      'ოფიციანტი' => (Icons.room_service_outlined, const Color(0xFF63D5FF)),
      _ => (Icons.badge_outlined, const Color(0xFF7DE2C3)),
    };

    // Sized to match the nav tabs (tables / count / takeaways) so the staff +
    // lock control reads as an equally prominent, tappable button.
    final badge = Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          if (!compact) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (onLockTap != null) ...[
            SizedBox(width: compact ? 8 : 9),
            Container(
              width: 1,
              height: 18,
              color: color.withValues(alpha: 0.3),
            ),
            SizedBox(width: compact ? 8 : 9),
            Icon(Icons.lock_outline_rounded, color: color, size: 20),
          ],
        ],
      ),
    );

    if (onLockTap == null) return badge;
    return Tooltip(
      message: 'ჩაკეტვა / სტაფის გადართვა',
      child: InkWell(
        onTap: onLockTap,
        borderRadius: BorderRadius.circular(11),
        child: badge,
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.unreadCount, required this.onTap});

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'შეტყობინებები',
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded, color: Colors.white),
          if (unreadCount > 0)
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFC928),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Color(0xFF1B2A36),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'გასვლა',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: const Color(0xFFEF4444).withValues(alpha: 0.34),
            ),
          ),
          child: const Icon(
            Icons.logout_rounded,
            color: Color(0xFFFF8A8A),
            size: 20,
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'Feature header — desktop', size: Size(1360, 100))
Widget homeFeatureHeaderPreview() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: HomeFeatureHeader(
          title: 'მაგიდები',
          icon: Icons.table_restaurant_outlined,
          username: 'ნინო',
          roleLabel: 'ოფიციანტი',
          activeKey: 'menu',
          destinations: const [
            HomeFeatureSwitchItem(
              key: 'menu',
              label: 'მაგიდები',
              icon: Icons.table_restaurant_outlined,
            ),
            HomeFeatureSwitchItem(
              key: 'calculate',
              label: 'მენიუს დათვლა',
              icon: Icons.functions_outlined,
            ),
            HomeFeatureSwitchItem(
              key: 'todaysTakeaways',
              label: 'გატანები',
              icon: Icons.shopping_bag_outlined,
              badgeCount: 3,
            ),
          ],
          onHomeTap: _noop,
          onDestinationSelected: _noopSelection,
          notificationUnreadCount: 2,
          onNotificationTap: _noop,
          onLogoutTap: _noop,
        ),
      ),
    ),
  );
}

void _noop() {}
void _noopSelection(String _) {}
