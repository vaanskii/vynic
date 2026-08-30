import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_login_screen.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/dashboard_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/live_status_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/financials_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/staff_performance_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/services/notifications/manager_notification_inbox.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/core/services/auth/mobile_auth_service.dart';
import 'package:vynic/core/services/notifications/app_notification_history_store.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/notifications_screen.dart';
import 'package:vynic/core/widgets/manager_connection_status.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';
import 'package:vynic/core/widgets/notification_entry_style.dart';
import 'package:vynic/core/services/notifications/notification_message_copy.dart';
import 'package:vynic/core/services/pos/pos_change_highlight_service.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_glass_nav_bar.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_tab_keep_alive.dart';

class ManagerAppShell extends StatefulWidget {
  final User user;
  const ManagerAppShell({super.key, required this.user});

  @override
  State<ManagerAppShell> createState() => _ManagerAppShellState();
}

class _ManagerAppShellState extends State<ManagerAppShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late PageController _pageController;

  late List<Widget> _screens;

  static const _navItems = <ManagerNavItem>[
    ManagerNavItem(label: 'დაფა', icon: Icons.dashboard_rounded),
    ManagerNavItem(label: 'მაგიდები', icon: Icons.table_bar_rounded),
    ManagerNavItem(
      label: 'ფინანსები',
      icon: Icons.account_balance_wallet_rounded,
    ),
    ManagerNavItem(label: 'რეზერვაციები', icon: Icons.book_online_rounded),
    ManagerNavItem(label: 'მართვა', icon: Icons.settings_rounded),
  ];

  String? _lastToastNotificationId;

  /// Suppresses "connection lost/restored" toasts while reconnecting after resume.
  bool _inLifecycleReconnect = false;
  Timer? _lifecycleReconnectTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    WidgetsBinding.instance.addObserver(this);
    MonitoringSocketService.initialize();
    MonitoringSocketService.isConnected.addListener(
      _onConnectionSignalsChanged,
    );
    MonitoringSocketService.apiError.addListener(_onConnectionSignalsChanged);
    MonitoringSocketService.isInitializing.addListener(
      _onConnectionSignalsChanged,
    );
    AppNotificationHistoryStore.instance.entries.addListener(
      _onNotificationEntriesChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onConnectionSignalsChanged(),
    );
    // Initial catch-up for notifications created before socket connected.
    unawaited(ManagerNotificationInbox.syncMissedFromServer());
    _screens = _buildScreens();
    ManagerAppPreferences.dashboardAppearance.addListener(
      _onDashboardAppearanceChanged,
    );
  }

  void _onDashboardAppearanceChanged() {
    if (!mounted) return;
    _refreshForThemeChange();
  }

  /// Rebuilds tabs and recreates [PageController] on the current tab so theme
  /// applies everywhere without jumping to დაფა.
  void _refreshForThemeChange() {
    final index = _selectedIndex.clamp(0, _navItems.length - 1);
    final oldController = _pageController;
    _selectedIndex = index;
    _pageController = PageController(initialPage: index);
    setState(() => _screens = _buildScreens());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
    });
  }

  List<Widget> _buildScreens() {
    final tabs = <Widget>[
      DashboardScreen(
        user: widget.user,
        onNavigateTab: _onItemTapped,
        onOpenNotifications: _openNotificationsSheet,
      ),
      LiveStatusScreen(user: widget.user),
      FinancialsScreen(user: widget.user),
      StaffPerformanceScreen(user: widget.user),
      MobileAdminScreen(user: widget.user, onLogout: _logout),
    ];
    return List.generate(tabs.length, (index) {
      return ManagerTabKeepAlive(
        storageKey: PageStorageKey<String>('manager_main_tab_$index'),
        child: tabs[index],
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _suppressToastsForResumeReconnect();
        MonitoringSocketService.onAppResumed();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        MonitoringSocketService.onAppPaused();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _suppressToastsForResumeReconnect() {
    _inLifecycleReconnect = true;
    _lifecycleReconnectTimer?.cancel();
    _lifecycleReconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _inLifecycleReconnect = false;
    });
  }

  void _clearLifecycleReconnectSuppress() {
    _lifecycleReconnectTimer?.cancel();
    _lifecycleReconnectTimer = null;
    _inLifecycleReconnect = false;
  }

  void _onConnectionSignalsChanged() {
    if (!mounted) return;
    if (!_inLifecycleReconnect) return;
    final connected = MonitoringSocketService.isConnected.value;
    final apiErr = MonitoringSocketService.apiError.value;
    if (connected && !apiErr) {
      _clearLifecycleReconnectSuppress();
    }
  }

  void _onNotificationEntriesChanged() {
    final list = AppNotificationHistoryStore.instance.entries.value;
    if (!mounted || list.isEmpty) return;
    final latest = list.first;
    if (_lastToastNotificationId == latest.id) return;
    _lastToastNotificationId = latest.id;
    // Catch-up from server fills the panel only (avoid toast spam after resume).
    if (latest.source == 'catchup') return;
    final body = latest.message.trim();
    final line = body.isEmpty ? latest.title : '${latest.title}\n$body';
    final accent = resolveNotificationEntryStyle(latest).accent;
    ManagerToast.show(context, line, accentColor: accent);
  }

  void _goToTab(int index, {bool animate = true}) {
    final target = index.clamp(0, _screens.length - 1);
    if (_selectedIndex != target) {
      setState(() => _selectedIndex = target);
    }
    if (_pageController.hasClients) {
      if (animate) {
        _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      } else {
        _pageController.jumpToPage(target);
      }
    }
  }

  void _onItemTapped(int index) => _goToTab(index);

  void _onPageChanged(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'გამოსვლა',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('ნამდვილად გსურთ გამოსვლა?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('გაუქმება'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('გამოსვლა'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await MobileAuthService.logout();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MobileLoginScreen()),
        );
      }
    }
  }

  void _openNotificationsSheet() {
    Navigator.of(context)
        .push(
          NotificationsScreen.route(
            onEntryTap: _onNotificationEntryTap,
            onClear: () {
              AppNotificationHistoryStore.instance.clear();
              if (mounted) setState(() {});
            },
          ),
        )
        .whenComplete(() {
          AppNotificationHistoryStore.instance.markAllRead();
          if (mounted) setState(() {});
        });
  }

  int? _orderIdFromNotificationMeta(Map<String, dynamic> meta) {
    final direct = meta['posOrderId'];
    if (direct is num) return direct.toInt();
    if (direct != null) return int.tryParse(direct.toString());

    final ids = meta['posOrderIds'];
    if (ids is List && ids.isNotEmpty) {
      final first = ids.first;
      if (first is num) return first.toInt();
      return int.tryParse(first.toString());
    }

    final touches = meta['touches'];
    if (touches is List && touches.isNotEmpty) {
      final t = touches.first;
      if (t is Map) {
        final idRaw = t['posOrderId'];
        if (idRaw is num) return idRaw.toInt();
        return int.tryParse(idRaw?.toString() ?? '');
      }
    }
    return null;
  }

  Map<String, dynamic> _orderNavFieldsFromMeta(Map<String, dynamic> meta) {
    if (meta.containsKey('posOrderId')) return meta;
    final touches = meta['touches'];
    if (touches is List && touches.isNotEmpty && touches.first is Map) {
      return Map<String, dynamic>.from(touches.first as Map);
    }
    return meta;
  }

  void _onNotificationEntryTap(AppNotificationEntry entry) {
    Navigator.of(context).pop();
    AppNotificationHistoryStore.instance.markEntryRead(entry.id);

    final meta = entry.meta;
    if (meta == null) return;

    // Walk-in creates a reservation record but belongs on მაგიდები + order.
    if (isWalkInNotificationMeta(meta)) {
      _navigateToTablesFromNotification(meta, fallbackMessage: entry.message);
      return;
    }

    // Reservation notification → open the reservations tab on the right date.
    final reservationId = meta['reservationId']?.toString().trim();
    if (reservationId != null && reservationId.isNotEmpty) {
      _goToTab(3);
      final resDate = meta['reservationDate']?.toString().trim();
      if (resDate != null && resDate.isNotEmpty) {
        // Reset first so the listener always re-fires, even for the same date.
        MonitoringSocketService.lastReservationDate.value = null;
        MonitoringSocketService.lastReservationDate.value = resDate;
      }
      return;
    }

    final orderId = _orderIdFromNotificationMeta(meta);
    if (orderId == null) return;
    _navigateToTablesFromNotification(
      meta,
      orderId: orderId,
      fallbackMessage: entry.message,
    );
  }

  void _navigateToTablesFromNotification(
    Map<String, dynamic> meta, {
    int? orderId,
    String? fallbackMessage,
  }) {
    final navMeta = _orderNavFieldsFromMeta(meta);
    final resolvedOrderId =
        orderId ??
        _orderIdFromNotificationMeta(meta) ??
        orderIdFromWalkInNotificationMeta(meta) ??
        (fallbackMessage != null
            ? orderIdFromNotificationMessage(fallbackMessage)
            : null);

    final rawKeys = navMeta['highlightItemKeys'] ?? meta['highlightItemKeys'];
    if (resolvedOrderId != null && rawKeys is List && rawKeys.isNotEmpty) {
      PosChangeHighlightService.setForOrder(
        resolvedOrderId,
        rawKeys.map((e) => e.toString()).toSet(),
      );
    }

    final floor = (navMeta['floor'] ?? meta['floor'] ?? 'first').toString();
    final tableNumber =
        tableNumberFromNotificationMeta(navMeta) ??
        tableNumberFromNotificationMeta(meta) ??
        (fallbackMessage != null
            ? tableNumberFromNotificationMessage(fallbackMessage)
            : null);

    if (resolvedOrderId != null ||
        (tableNumber != null && tableNumber.isNotEmpty)) {
      MonitoringSocketService.pendingTableFocus.value = null;
      MonitoringSocketService.pendingTableFocus.value =
          ManagerTableFocusRequest(
            tableNumber: tableNumber ?? '',
            floor: floor,
            orderId: resolvedOrderId,
          );
    }

    _goToTab(1);
  }

  @override
  Widget build(BuildContext context) {
    return ManagerThemeListener(
      child: Builder(
        builder: (context) {
          final theme = managerThemeOf(context);
          return Scaffold(
            backgroundColor: theme.scaffoldBackground,
            extendBody: true,
            appBar: null,
            body: Stack(
              clipBehavior: Clip.none,
              children: [
                PageView(
                  key: ValueKey(_pageController),
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  allowImplicitScrolling: true,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  children: _screens,
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 10,
                  right: 22,
                  child: const ManagerConnectionStatusDot(),
                ),
              ],
            ),
            bottomNavigationBar: ManagerGlassNavBar(
              key: ValueKey(_pageController),
              pageController: _pageController,
              selectedIndex: _selectedIndex,
              itemCount: _navItems.length,
              items: _navItems,
              onTap: _onItemTapped,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _lifecycleReconnectTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AppNotificationHistoryStore.instance.entries.removeListener(
      _onNotificationEntriesChanged,
    );
    MonitoringSocketService.isConnected.removeListener(
      _onConnectionSignalsChanged,
    );
    MonitoringSocketService.apiError.removeListener(
      _onConnectionSignalsChanged,
    );
    MonitoringSocketService.isInitializing.removeListener(
      _onConnectionSignalsChanged,
    );
    MonitoringSocketService.dispose();
    ManagerAppPreferences.dashboardAppearance.removeListener(
      _onDashboardAppearanceChanged,
    );
    super.dispose();
  }
}
