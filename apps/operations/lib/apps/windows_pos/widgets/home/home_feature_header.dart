import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

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
    required this.activeKey,
    required this.destinations,
    required this.onDestinationSelected,
    required this.notificationUnreadCount,
    required this.onNotificationTap,
    this.businessDate,
    this.onLogoutTap,
  });

  /// The POS business date (may differ from the wall-clock date around
  /// close-day). Optional — when null the date is hidden (preview usage).
  final DateTime? businessDate;

  final String activeKey;

  /// Every section the current role can reach — all shown as inline tabs,
  /// no hidden/"More" menu. Reachability was the whole point of this row;
  /// hiding some sections behind another click undoes that.
  final List<HomeFeatureSwitchItem> destinations;
  final ValueChanged<String> onDestinationSelected;
  final int notificationUnreadCount;
  final VoidCallback onNotificationTap;

  /// Optional — when null the logout button is hidden. The POS home passes null
  /// (logout lives only on the lock screen); the preview still shows it.
  final VoidCallback? onLogoutTap;

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

  static const _months = [
    'იან',
    'თებ',
    'მარ',
    'აპრ',
    'მაი',
    'ივნ',
    'ივლ',
    'აგვ',
    'სექ',
    'ოქტ',
    'ნოე',
    'დეკ',
  ];

  String? get _businessDateLabel {
    final date = widget.businessDate;
    if (date == null) return null;
    return '${date.day} ${_months[date.month - 1]}';
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
          child: Row(
            children: [
              // Expanded (not just Flexible) so this slot deterministically
              // reserves ALL remaining free space — nav renders left-aligned
              // within it (a visible gap after the tabs, not stretched
              // tabs), and the date/clock/notification cluster after it is
              // guaranteed to land at the true right edge of the bar. Under
              // real space pressure, the inner per-tab Flexibles still
              // compress via ellipsis instead of overflowing.
              Expanded(child: _buildDirectNavigation()),
              // Business date/time and every nav tab's label stay visible at
              // every resolution — nav tabs' own per-tab Flexible+ellipsis
              // is the only space-pressure valve (no icon-only collapse).
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_businessDateLabel != null)
                    _HeaderMetaLine(
                      icon: Icons.today_rounded,
                      label: _businessDateLabel!,
                    ),
                  _HeaderMetaLine(
                    icon: Icons.schedule_rounded,
                    label: _timeLabel,
                  ),
                ],
              ),
              const SizedBox(width: 14),
              _NotificationButton(
                unreadCount: widget.notificationUnreadCount,
                onTap: widget.onNotificationTap,
              ),
              if (widget.onLogoutTap != null) ...[
                const SizedBox(width: 4),
                _LogoutButton(onTap: widget.onLogoutTap!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectNavigation() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
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

/// One icon+label row of the stacked date/time block (see [_HomeFeatureHeaderState.build]).
class _HeaderMetaLine extends StatelessWidget {
  const _HeaderMetaLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
