import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/core/ui/vynic_breakpoints.dart';

class ManagerNavItem {
  const ManagerNavItem({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// Stable public adapter used by embedded Manager navigation and its tests.
class ManagerGlassNavBar extends StatelessWidget {
  const ManagerGlassNavBar({
    super.key,
    required this.pageController,
    required this.selectedIndex,
    required this.itemCount,
    required this.items,
    required this.onTap,
  });
  final PageController pageController;
  final int selectedIndex;
  final int itemCount;
  final List<ManagerNavItem> items;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) => _BottomNavigation(
    items: items,
    selectedIndex: selectedIndex,
    onTap: onTap,
  );
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });
  final List<ManagerNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final t = managerThemeOf(context);
    return Material(
      color: t.surfaceCard,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.cardBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in items.indexed)
                Expanded(
                  child: Semantics(
                    selected: selectedIndex == entry.$1,
                    child: Tooltip(
                      message: entry.$2.label,
                      child: InkWell(
                        key: ValueKey('manager-nav-${entry.$2.label}'),
                        onTap: () => onTap(entry.$1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                entry.$2.icon,
                                size: 25,
                                color: selectedIndex == entry.$1
                                    ? t.primary
                                    : t.textSecondary,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                entry.$2.label == 'რეზერვაციები'
                                    ? 'ჯავშნები'
                                    : entry.$2.label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  fontWeight: selectedIndex == entry.$1
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selectedIndex == entry.$1
                                      ? t.primary
                                      : t.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Constraint-driven shell. Destination indexes remain owned by the existing
/// entitlement-aware PageView; More is only another way to select those indexes.
class ManagerAdaptiveNavigation extends StatelessWidget {
  const ManagerAdaptiveNavigation({
    super.key,
    required this.body,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    required this.username,
    required this.venueName,
    required this.onNotifications,
    required this.onCalculate,
    this.unreadCount = 0,
  });
  final Widget body;
  final List<ManagerNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final String username, venueName;
  final VoidCallback onNotifications, onCalculate;
  final int unreadCount;

  Future<void> _more(BuildContext context, List<int> primary) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('მეტი'),
        scrollable: true,
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in items.indexed)
                if (!primary.contains(entry.$1))
                  ListTile(
                    leading: Icon(entry.$2.icon),
                    title: Text(entry.$2.label),
                    selected: entry.$1 == selectedIndex,
                    onTap: () {
                      Navigator.pop(dialogContext);
                      onTap(entry.$1);
                    },
                  ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('დათვლა'),
                subtitle: const Text('ახალი და შენახული დათვლები'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  onCalculate();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('დახურვა'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = managerThemeOf(context);
    return CallbackShortcuts(
      bindings: {
        for (final entry in [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit6,
        ].indexed)
          if (entry.$1 < items.length)
            SingleActivator(entry.$2, meta: true): () => onTap(entry.$1),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): onCalculate,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sidebar = constraints.maxWidth >= 700;
            final expanded =
                constraints.maxWidth >= VynicBreakpoints.compactMax;
            final primary = <int>[
              for (final name in [
                'დაფა',
                'მაგიდები',
                'რეზერვაციები',
                'ფინანსები',
              ])
                if (items.any((e) => e.label == name))
                  items.indexWhere((e) => e.label == name),
            ];
            final phoneItems = [
              for (final index in primary) items[index],
              const ManagerNavItem(
                label: 'მეტი',
                icon: Icons.grid_view_rounded,
              ),
            ];
            Widget railItem(
              ManagerNavItem item,
              VoidCallback action, {
              bool selected = false,
              String? key,
            }) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Tooltip(
                message: item.label,
                child: Material(
                  color: selected ? t.primarySoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: key == null ? null : ValueKey(key),
                    borderRadius: BorderRadius.circular(12),
                    onTap: action,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 15,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            size: 22,
                            color: selected ? t.primary : t.textSecondary,
                          ),
                          if (expanded) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  color: selected ? t.primary : t.textSecondary,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            final content = Column(
              children: [
                Material(
                  color: t.surfaceCard,
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: sidebar ? 26 : 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: t.cardBorder)),
                      ),
                      child: Row(
                        children: [
                          if (!sidebar) ...[
                            Text(
                              'vynic',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                color: t.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          if (sidebar) ...[
                            Icon(
                              Icons.storefront_outlined,
                              color: t.textSecondary,
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              venueName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'შეტყობინებები',
                            onPressed: onNotifications,
                            icon: Badge(
                              isLabelVisible: unreadCount > 0,
                              child: const Icon(
                                Icons.notifications_none_rounded,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: body),
              ],
            );
            return Scaffold(
              backgroundColor: t.scaffoldBackground,
              body: Row(
                children: [
                  if (sidebar)
                    Container(
                      width: expanded ? 224 : 82,
                      decoration: BoxDecoration(
                        color: t.surfaceCard,
                        border: Border(right: BorderSide(color: t.cardBorder)),
                      ),
                      child: SafeArea(
                        child: Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                expanded ? 24 : 18,
                                30,
                                18,
                                32,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: t.primary,
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'v',
                                        style: TextStyle(
                                          fontSize: 30,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (expanded) ...[
                                    const SizedBox(width: 10),
                                    Text(
                                      'vynic',
                                      style: TextStyle(
                                        fontSize: 27,
                                        fontWeight: FontWeight.w600,
                                        color: t.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 7),
                                      child: Text(
                                        'manager',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: t.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (expanded)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  26,
                                  0,
                                  20,
                                  10,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'სამუშაო სივრცე',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: t.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  for (final entry in items.indexed)
                                    railItem(
                                      entry.$2,
                                      () => onTap(entry.$1),
                                      selected: selectedIndex == entry.$1,
                                      key: 'manager-nav-${entry.$2.label}',
                                    ),
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Divider(height: 1),
                                  ),
                                  railItem(
                                    const ManagerNavItem(
                                      label: 'დათვლა',
                                      icon: Icons.calculate_outlined,
                                    ),
                                    onCalculate,
                                    key: 'manager-count-menu',
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: t.primarySoft,
                                    foregroundColor: t.primary,
                                    child: Text(
                                      username.isEmpty
                                          ? 'V'
                                          : username.characters.first,
                                    ),
                                  ),
                                  if (expanded) ...[
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        username,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: t.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(child: content),
                ],
              ),
              bottomNavigationBar: sidebar
                  ? null
                  : _BottomNavigation(
                      items: phoneItems,
                      selectedIndex: primary.contains(selectedIndex)
                          ? primary.indexOf(selectedIndex)
                          : primary.length,
                      onTap: (index) => index < primary.length
                          ? onTap(primary[index])
                          : _more(context, primary),
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Reserves measured navigation height; no guessed trailing list padding.
class ManagerNavigationFrame extends StatelessWidget {
  const ManagerNavigationFrame({
    super.key,
    this.backgroundColor,
    required this.body,
    required this.bottomNavigationBar,
  });
  final Color? backgroundColor;
  final Widget body, bottomNavigationBar;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: backgroundColor,
    body: body,
    bottomNavigationBar: bottomNavigationBar,
  );
}
