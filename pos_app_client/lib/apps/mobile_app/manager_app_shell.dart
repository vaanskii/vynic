import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_login_screen.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/dashboard_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/live_status_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/financials_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/staff_performance_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/services/monitoring_socket_service.dart';
import 'package:vynic/core/services/mobile_auth_service.dart';
import 'package:vynic/core/services/app_notification_history_store.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/notifications_screen.dart';
import 'package:vynic/core/widgets/manager_toast.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_order_detail_screen.dart';
import 'package:vynic/core/services/pos_change_highlight_service.dart';

class ManagerAppShell extends StatefulWidget {
  final User user;
  const ManagerAppShell({super.key, required this.user});

  @override
  State<ManagerAppShell> createState() => _ManagerAppShellState();
}

class _ManagerAppShellState extends State<ManagerAppShell> {
  int _selectedIndex = 0;

  late final List<Widget> _screens;

  /// True after we showed the socket-offline pill for the current outage (reset when socket is back).
  bool _socketOutageToastEmitted = false;

  /// Show green "restored" once when [isConnected] && !apiError again after any problem toast.
  bool _pendingHealthyToast = false;
  bool _prevApiError = false;
  String? _lastToastNotificationId;

  @override
  void initState() {
    super.initState();
    MonitoringSocketService.initialize();
    MonitoringSocketService.isConnected.addListener(_onConnectionSignalsChanged);
    MonitoringSocketService.apiError.addListener(_onConnectionSignalsChanged);
    MonitoringSocketService.isInitializing.addListener(_onConnectionSignalsChanged);
    AppNotificationHistoryStore.instance.entries.addListener(
      _onNotificationEntriesChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _onConnectionSignalsChanged());
    _screens = [
      DashboardScreen(
        user: widget.user,
        onNavigateTab: _onItemTapped,
        onOpenNotifications: _openNotificationsSheet,
        onLogout: _logout,
      ),
      LiveStatusScreen(user: widget.user),
      FinancialsScreen(user: widget.user),
      StaffPerformanceScreen(user: widget.user),
      MobileAdminScreen(user: widget.user),
    ];
  }

  void _onConnectionSignalsChanged() {
    if (!mounted) return;
    if (MonitoringSocketService.isInitializing.value) return;

    final connected = MonitoringSocketService.isConnected.value;
    final apiErr = MonitoringSocketService.apiError.value;

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
    ManagerToast.show(context, '${latest.title}\n${latest.message}');
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Formats YYYY-MM-DD → e.g. "30 Apr 2026"
  String _formatBusinessDate(String? raw) {
    if (raw == null) return '';
    try {
      final parts = raw.split('-').map(int.parse).toList();
      final dt = DateTime(parts[0], parts[1], parts[2]);
      return DateFormat('d MMM yyyy').format(dt);
    } catch (_) {
      return raw;
    }
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
      setState(() => _selectedIndex = 3);
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

    setState(() => _selectedIndex = 1);

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
    // Tabs that use the dark "glass" design (own header, no shell app bar).
    final isDarkTab = _selectedIndex == 0 ||
        _selectedIndex == 1 ||
        _selectedIndex == 2 ||
        _selectedIndex == 3;
    return Scaffold(
      backgroundColor:
          isDarkTab ? const Color(0xFF050508) : const Color(0xFFF1F5F9),
      extendBody: isDarkTab,
      appBar: isDarkTab
          ? null
          : PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── main bar ──────────────────────────────────────────────
                SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        // Logo + brand name
                        Image.asset(
                          'assets/logo/vynic.png',
                          height: 30,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Vynic',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E3A8A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        // Business date chip
                        ValueListenableBuilder<String?>(
                          valueListenable:
                              MonitoringSocketService.currentBusinessDate,
                          builder: (_, date, __) {
                            final label = _formatBusinessDate(date);
                            if (label.isEmpty) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFBFDBFE),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 12,
                                    color: Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<int>(
                          valueListenable:
                              AppNotificationHistoryStore.instance.unreadCount,
                          builder: (_, unread, __) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.notifications_outlined,
                                      color: unread > 0
                                          ? const Color(0xFF2563EB)
                                          : const Color(0xFF94A3B8),
                                      size: 22,
                                    ),
                                    tooltip: 'შეტყობინებები',
                                    onPressed: _openNotificationsSheet,
                                    splashRadius: 20,
                                  ),
                                  if (unread > 0)
                                    Positioned(
                                      right: 4,
                                      top: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        constraints:
                                            const BoxConstraints(minWidth: 18),
                                        child: Text(
                                          unread > 99 ? '99+' : '$unread',
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
                          },
                        ),
                        // Logout
                        IconButton(
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Color(0xFF94A3B8),
                            size: 22,
                          ),
                          tooltip: 'გამოსვლა',
                          onPressed: _logout,
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                // Connection issues use [ManagerToast] (gradient pills) instead of a slim banner.
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: _buildFloatingNav(),
    );
  }

  static const _navItems = <_NavItem>[
    _NavItem('დაფა', Icons.dashboard_rounded),
    _NavItem('მაგიდები', Icons.table_bar_rounded),
    _NavItem('ფინანსები', Icons.account_balance_wallet_rounded),
    _NavItem('რეზერვები', Icons.book_online_rounded),
    _NavItem('მართვა', Icons.settings_rounded),
  ];

  Widget _buildFloatingNav() {
    const radius = 34.0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        // Outer layer carries the soft drop shadow (kept outside the clip so it
        // isn't cut off by the rounded mask).
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 30,
                spreadRadius: -4,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              // Heavy blur = frosted "liquid glass" feel like iOS materials.
              filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                decoration: BoxDecoration(
                  // Top-lighter → bottom-darker translucent tint gives the
                  // subtle sheen of frosted glass while staying dark enough
                  // for white glyphs to read on any screen behind it.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF3A3A48).withOpacity(0.55),
                      const Color(0xFF0B0B11).withOpacity(0.62),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.20),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(_navItems.length, (index) {
                    final item = _navItems[index];
                    final isSelected = _selectedIndex == index;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _onItemTapped(index),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withOpacity(0.16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white.withOpacity(0.22)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.icon,
                                size: 23,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.5),
                              ),
                              if (isSelected) ...[
                                const SizedBox(height: 4),
                                Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    AppNotificationHistoryStore.instance.entries.removeListener(
      _onNotificationEntriesChanged,
    );
    MonitoringSocketService.isConnected.removeListener(_onConnectionSignalsChanged);
    MonitoringSocketService.apiError.removeListener(_onConnectionSignalsChanged);
    MonitoringSocketService.isInitializing.removeListener(_onConnectionSignalsChanged);
    MonitoringSocketService.dispose();
    super.dispose();
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}
