import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_login_screen.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/dashboard_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/live_status_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/financials_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/staff_performance_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/services/manager_notification_inbox.dart';
import 'package:vynic/core/services/monitoring_socket_service.dart';
import 'package:vynic/core/services/mobile_auth_service.dart';
import 'package:vynic/core/services/app_notification_history_store.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/notifications_screen.dart';
import 'package:vynic/core/widgets/manager_toast.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_order_detail_screen.dart';
import 'package:vynic/core/services/pos_change_highlight_service.dart';
import 'package:vynic/apps/mobile_app/widgets/manager_glass_nav_bar.dart';
import 'package:vynic/apps/mobile_app/widgets/manager_tab_keep_alive.dart';

class ManagerAppShell extends StatefulWidget {
  final User user;
  const ManagerAppShell({super.key, required this.user});

  @override
  State<ManagerAppShell> createState() => _ManagerAppShellState();
}

class _ManagerAppShellState extends State<ManagerAppShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final PageController _pageController;

  late final List<Widget> _screens;

  static const _navItems = <ManagerNavItem>[
    ManagerNavItem(label: 'დაფა', icon: Icons.dashboard_rounded),
    ManagerNavItem(label: 'მაგიდები', icon: Icons.table_bar_rounded),
    ManagerNavItem(label: 'ფინანსები', icon: Icons.account_balance_wallet_rounded),
    ManagerNavItem(label: 'რეზერვები', icon: Icons.book_online_rounded),
    ManagerNavItem(label: 'მართვა', icon: Icons.settings_rounded),
  ];

  /// True after we showed the socket-offline pill for the current outage (reset when socket is back).
  bool _socketOutageToastEmitted = false;

  /// Show green "restored" once when [isConnected] && !apiError again after any problem toast.
  bool _pendingHealthyToast = false;
  bool _prevApiError = false;
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
        _pendingHealthyToast = false;
        MonitoringSocketService.onAppPaused();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _suppressToastsForResumeReconnect() {
    _inLifecycleReconnect = true;
    _pendingHealthyToast = false;
    _socketOutageToastEmitted = true;
    _lifecycleReconnectTimer?.cancel();
    // If the socket is still down after a few seconds, show a real outage toast.
    _lifecycleReconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _inLifecycleReconnect = false;
      _socketOutageToastEmitted = false;
      _onConnectionSignalsChanged();
    });
  }

  void _clearLifecycleReconnectSuppress() {
    _lifecycleReconnectTimer?.cancel();
    _lifecycleReconnectTimer = null;
    _inLifecycleReconnect = false;
    _socketOutageToastEmitted = false;
  }

  void _onConnectionSignalsChanged() {
    if (!mounted) return;
    if (MonitoringSocketService.isInitializing.value) return;
    if (MonitoringSocketService.isAppPaused) return;

    final connected = MonitoringSocketService.isConnected.value;
    final apiErr = MonitoringSocketService.apiError.value;

    if (_inLifecycleReconnect) {
      if (connected && !apiErr) {
        _clearLifecycleReconnectSuppress();
      }
      return;
    }

    // Fully healthy again → single restored toast if we had surfaced a problem.
    if (connected && !apiErr && _pendingHealthyToast) {
      ManagerToast.showConnectionRestored(context);
      _pendingHealthyToast = false;
    }

    // Realtime socket down (includes “never reached server” after bootstrap ends).
    if (!connected) {
      if (!_socketOutageToastEmitted) {
        ManagerToast.showConnectionLost(context, socketIssue: true);
        _socketOutageToastEmitted = true;
        _pendingHealthyToast = true;
      }
    } else {
      _socketOutageToastEmitted = false;
    }

    // HTTP / dashboard errors while the websocket is technically connected.
    if (connected && apiErr && !_prevApiError) {
      ManagerToast.showConnectionLost(context, socketIssue: false);
      _pendingHealthyToast = true;
    }

    _prevApiError = apiErr;
  }

  void _onNotificationEntriesChanged() {
    final list = AppNotificationHistoryStore.instance.entries.value;
    if (!mounted || list.isEmpty) return;
    final latest = list.first;
    if (_lastToastNotificationId == latest.id) return;
    _lastToastNotificationId = latest.id;
    // Catch-up from server fills the panel only (avoid toast spam after resume).
    if (latest.source == 'catchup') return;
    ManagerToast.show(context, '${latest.title}\n${latest.message}');
  }

  void _goToTab(int index, {bool animate = true}) {
    final target = index.clamp(0, _screens.length - 1);
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
    } else {
      setState(() => _selectedIndex = target);
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
    final nav = Navigator.of(context);
    nav.pop();
    AppNotificationHistoryStore.instance.markEntryRead(entry.id);

    final meta = entry.meta;
    if (meta == null) return;

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

    final navMeta = _orderNavFieldsFromMeta(meta);
    final rawKeys = navMeta['highlightItemKeys'] ?? meta['highlightItemKeys'];
    Set<String>? highlightKeys;
    if (rawKeys is List && rawKeys.isNotEmpty) {
      highlightKeys = rawKeys.map((e) => e.toString()).toSet();
      PosChangeHighlightService.setForOrder(orderId, highlightKeys);
    }

    final tableLabel = navMeta['tableLabel']?.toString() ?? '';
    final floor = navMeta['floor']?.toString() ?? 'first';
    final tableNumber = tableLabel.isNotEmpty
        ? tableLabel.replaceAll('Table ', '').split(',').first.trim()
        : '';

    _goToTab(1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => MobileOrderDetailScreen(
            user: widget.user,
            orderId: orderId,
            tableNumber: tableNumber.isNotEmpty ? tableNumber : null,
            floor: floor,
            highlightItemKeys: highlightKeys,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      extendBody: true,
      appBar: null,
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        allowImplicitScrolling: true,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: _screens,
      ),
      bottomNavigationBar: ManagerGlassNavBar(
        pageController: _pageController,
        itemCount: _navItems.length,
        items: _navItems,
        onTap: _onItemTapped,
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
    super.dispose();
  }
}

