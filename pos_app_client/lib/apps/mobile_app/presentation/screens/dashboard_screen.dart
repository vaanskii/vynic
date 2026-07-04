import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import 'package:vynic/apps/mobile_app/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/dashboard_theme_scope.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';

import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/data/repositories/dashboard_repository.dart';
import 'package:vynic/apps/mobile_app/data/services/dashboard_remote_service.dart';
import 'package:vynic/apps/mobile_app/presentation/controllers/dashboard_controller.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_counted_menus_screen.dart';
import 'package:vynic/apps/mobile_app/state/providers/dashboard_state.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/notifications/app_notification_history_store.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_toast.dart';

final _empty = ManagerDashboardMetrics(
  todayRevenue: 0,
  closedTablesRevenue: 0,
  nonFiscalClosedRevenue: 0,
  todayOrderCount: 0,
  activeTablesCount: 0,
  openTablesAmount: 0,
  openTablesPayable: 0,
  occupancyPercentage: 0,
  yesterdayRevenue: 0,
);

final _money = NumberFormat('#,##0', 'en_US');
final _moneyExact = NumberFormat('#,##0.00', 'en_US');

String _gelExact(num amount) => '₾${_moneyExact.format(amount)}';

/// Manager dashboard (light/dark via [ManagerAppPreferences]) while staying
/// wired to the live [DashboardController] data (revenue, orders, tables,
/// staff, top items) and the in-app notification history for live activity.
class DashboardScreen extends StatefulWidget {
  final User user;
  final void Function(int index)? onNavigateTab;
  final VoidCallback? onOpenNotifications;
  const DashboardScreen({
    super.key,
    required this.user,
    this.onNavigateTab,
    this.onOpenNotifications,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final DashboardController _controller;
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController(
      const DashboardRepository(DashboardRemoteService()),
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _controller.addListener(_onControllerChanged);
    _controller.initialize();
    MonitoringSocketService.updateCounter.addListener(
      _controller.scheduleMetricsRefresh,
    );
    MonitoringSocketService.isConnected.addListener(_onConnect);
    MonitoringSocketService.dayClosedCounter.addListener(_onDayClosed);
  }

  void _onControllerChanged() {
    if (_controller.state.firstLoadDone && _animController.value == 0) {
      _animController.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  void _onConnect() {
    if (MonitoringSocketService.isConnected.value) _controller.loadAll();
  }

  void _onDayClosed() {
    _controller.loadAll();
  }

  @override
  void dispose() {
    MonitoringSocketService.updateCounter.removeListener(
      _controller.scheduleMetricsRefresh,
    );
    MonitoringSocketService.isConnected.removeListener(_onConnect);
    MonitoringSocketService.dayClosedCounter.removeListener(_onDayClosed);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'ღამე მშვიდობისა,';
    if (h < 12) return 'დილა მშვიდობისა,';
    if (h < 18) return 'გაუმარჯოს,';
    return 'საღამო მშვიდობისა,';
  }

  List<Map<String, dynamic>> _topItems(DashboardState state) {
    final raw = state.salesReport?['topItems'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .take(5)
        .toList();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _businessToday() {
    final raw = MonitoringSocketService.currentBusinessDate.value;
    if (raw != null && raw.trim().length >= 10) {
      final p = raw.substring(0, 10).split('-');
      final y = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      final d = int.tryParse(p[2]);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Map<String, double> _dailyRevenueMap(DashboardState state) {
    final map = <String, double>{};
    for (final row in state.salesDaily) {
      final date = (row['date'] ?? '').toString();
      if (date.length < 10) continue;
      final rev = row['totalRevenue'];
      map[date.substring(0, 10)] = rev is num
          ? rev.toDouble()
          : double.tryParse('$rev') ?? 0;
    }
    return map;
  }

  List<_DayPoint> _last7BusinessDays(
    DashboardState state,
    double activeRevenue,
    String? activeBusinessDayId,
  ) {
    final map = _dailyRevenueMap(state);
    final activeKey = activeBusinessDayId ?? _ymd(_businessToday());
    final dates = map.keys.toList()..sort();
    if (!dates.contains(activeKey)) dates.add(activeKey);
    dates.sort();
    final window = dates.length <= 7 ? dates : dates.sublist(dates.length - 7);

    return window.map((dateKey) {
      final isActive = dateKey == activeKey;
      final parts = dateKey.split('-');
      final label = parts.length >= 3 ? '${parts[2]}.${parts[1]}' : dateKey;
      return _DayPoint(
        label: label,
        value: isActive ? activeRevenue : (map[dateKey] ?? 0),
        isToday: isActive,
      );
    }).toList();
  }

  double? _previousBusinessDayChange(
    DashboardState state,
    double activeRevenue,
    String? activeBusinessDayId,
  ) {
    final map = _dailyRevenueMap(state);
    final activeKey = activeBusinessDayId ?? _ymd(_businessToday());
    final priorKeys = map.keys.where((k) => k.compareTo(activeKey) < 0).toList()
      ..sort();
    if (priorKeys.isEmpty) return null;
    final prevRev = map[priorKeys.last] ?? 0;
    if (prevRev <= 0) return null;
    return (activeRevenue - prevRev) / prevRev * 100;
  }

  String _formatOpenedLocal(String? isoUtc) {
    if (isoUtc == null || isoUtc.isEmpty) return '—';
    final dt = DateTime.tryParse(isoUtc);
    if (dt == null) return '—';
    return DateFormat('HH:mm, dd.MM').format(dt.toLocal());
  }

  String _formatDuration(String? isoUtc, int? snapshotMinutes) {
    if (isoUtc != null && isoUtc.isNotEmpty) {
      final opened = DateTime.tryParse(isoUtc);
      if (opened != null) {
        final mins = DateTime.now().difference(opened.toLocal()).inMinutes;
        return _durationLabel(mins);
      }
    }
    if (snapshotMinutes != null) return _durationLabel(snapshotMinutes);
    return '—';
  }

  String _durationLabel(int minutes) {
    if (minutes < 60) return '$minutes წთ';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h სთ';
    return '$h სთ $m წთ';
  }

  List<Map<String, dynamic>> _sortedCountedMenus(List<dynamic> raw) {
    final out = raw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    out.sort((a, b) {
      final ad = DateTime.tryParse('${a['createdAt'] ?? ''}');
      final bd = DateTime.tryParse('${b['createdAt'] ?? ''}');
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return out;
  }

  _CountedMenusSummary _countedMenusSummary(List<dynamic> raw) {
    final drafts = _sortedCountedMenus(raw);
    var totalValue = 0.0;
    var totalItems = 0;
    for (final d in drafts) {
      totalValue +=
          (d['total'] as num?)?.toDouble() ??
          (d['subtotal'] as num?)?.toDouble() ??
          0;
      totalItems += (d['items'] as List?)?.length ?? 0;
    }
    return _CountedMenusSummary(
      drafts: drafts,
      totalValue: totalValue,
      totalItems: totalItems,
    );
  }

  Future<void> _openCountedMenus() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            managerThemedPage(MobileCountedMenusScreen(user: widget.user)),
      ),
    );
    if (mounted) _controller.loadAll();
  }

  Future<void> _startCountMenu() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            managerThemedPage(const MobileCalculatorScreen(isCountMode: true)),
      ),
    );
    if (saved == true && mounted) _controller.loadAll();
  }

  void _toast(String msg, {Color? color}) {
    if (!mounted) return;
    ManagerToast.showSnackBar(context, msg, accentColor: color);
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final metrics = state.metrics ?? _empty;
    final avgOrder = metrics.todayOrderCount > 0
        ? metrics.todayRevenue / metrics.todayOrderCount
        : 0.0;

    final staff = [...state.staff]
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
    final topItems = _topItems(state);
    final activeDayId = metrics.businessDayId ?? metrics.businessDate;
    final series = _last7BusinessDays(
      state,
      metrics.shiftTotalRevenue,
      activeDayId,
    );
    final dayChange = _previousBusinessDayChange(
      state,
      metrics.shiftTotalRevenue,
      activeDayId,
    );
    final menuSummary = _countedMenusSummary(state.countedMenus);

    return ValueListenableBuilder<ManagerDashboardAppearance>(
      valueListenable: ManagerAppPreferences.dashboardAppearance,
      builder: (context, appearance, _) {
        final theme = DashboardThemeData.forAppearance(appearance);
        return DashboardThemeScope(
          theme: theme,
          child: Scaffold(
            backgroundColor: theme.scaffoldBackground,
            body: Stack(
              children: [
                Positioned(
                  top: -150,
                  right: -100,
                  child: _SoftGlow(
                    color: theme.glowTopRight,
                    size: 500,
                    opacity: theme.glowTopRightOpacity,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: -150,
                  child: _SoftGlow(
                    color: theme.glowBottomLeft,
                    size: 400,
                    opacity: theme.glowBottomLeftOpacity,
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: RefreshIndicator(
                    color: theme.primary,
                    backgroundColor: theme.refreshIndicatorBackground,
                    onRefresh: _controller.loadAll,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 120),
                            child: state.loading && state.metrics == null
                                ? _DashboardSkeleton()
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      Widget fade(double delay, Widget child) =>
                                          _FadeInSlide(
                                            controller: _animController,
                                            delay: delay,
                                            child: child,
                                          );

                                      // Build every section once, then arrange
                                      // them responsively below.
                                      final header = _Header(
                                        greeting: _greeting(),
                                        name: widget.user.username,
                                        onNotifications:
                                            widget.onOpenNotifications,
                                      );
                                      const aiCard = _AIInsightsCard();
                                      final activeDay = _ActiveBusinessDayCard(
                                        metrics: metrics,
                                        formatOpened: _formatOpenedLocal,
                                        formatDuration: () => _formatDuration(
                                          metrics.businessDayOpenedAt,
                                          metrics.businessDayDurationMinutes,
                                        ),
                                      );
                                      final hero = _HeroRevenueCard(
                                        metrics: metrics,
                                        series: series,
                                        dayChange: dayChange,
                                        onTap: () =>
                                            widget.onNavigateTab?.call(2),
                                      );
                                      final secondary = _SecondaryStats(
                                        orderCount: metrics.todayOrderCount,
                                        avgOrder: avgOrder,
                                        activeTables: metrics.activeTablesCount,
                                        occupancy: metrics.occupancyPercentage
                                            .round(),
                                        payable: metrics.openTablesPayable,
                                        onTapOrders: () =>
                                            widget.onNavigateTab?.call(2),
                                        onTapTables: () =>
                                            widget.onNavigateTab?.call(1),
                                      );
                                      final pulse = _ManagerPulseCard(
                                        metrics: metrics,
                                        reservations: state.todayReservations,
                                        onTapTables: () =>
                                            widget.onNavigateTab?.call(1),
                                        onTapReservations: () =>
                                            widget.onNavigateTab?.call(3),
                                      );
                                      final tables = _TablesOverviewStrip(
                                        metrics: metrics,
                                        onTap: () =>
                                            widget.onNavigateTab?.call(1),
                                      );
                                      final quickActions = _QuickActionsSection(
                                        onCloseBusinessDay: () => _toast(
                                          'დღის დახურვა ხდება Windows POS-ში',
                                          color: context.dash.warn,
                                        ),
                                        onViewReport: () =>
                                            widget.onNavigateTab?.call(2),
                                        onExportPdf: () => _toast(
                                          'PDF ექსპორტი მალე დაემატება',
                                          color: context.dash.info,
                                        ),
                                        onReservations: () =>
                                            widget.onNavigateTab?.call(3),
                                        onAnnouncement: () => _toast(
                                          'შეტყობინების გაგზავნა მალე დაემატება',
                                          color: context.dash.info,
                                        ),
                                      );
                                      final countedMenus = _CountedMenusSection(
                                        summary: menuSummary,
                                        onOpenAll: _openCountedMenus,
                                        onNewCount: _startCountMenu,
                                      );
                                      final Widget? topItemsWidget =
                                          topItems.isNotEmpty
                                          ? _TopItemsSection(topItems: topItems)
                                          : null;
                                      final Widget? waitersWidget =
                                          staff.isNotEmpty
                                          ? _WaitersSection(staff: staff)
                                          : null;

                                      // Phones (< 880px): single column, in the
                                      // original priority order. Tablets / Mac
                                      // (>= 880px): a centered two-column
                                      // masonry mirroring the dashboard mockup.
                                      if (constraints.maxWidth < 880) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 12),
                                            fade(0.0, header),
                                            const SizedBox(height: 24),
                                            fade(0.04, aiCard),
                                            const SizedBox(height: 24),
                                            fade(0.08, activeDay),
                                            const SizedBox(height: 16),
                                            fade(0.15, hero),
                                            const SizedBox(height: 16),
                                            fade(0.25, secondary),
                                            const SizedBox(height: 28),
                                            fade(0.32, pulse),
                                            const SizedBox(height: 28),
                                            fade(0.35, tables),
                                            const SizedBox(height: 28),
                                            fade(0.38, quickActions),
                                            const SizedBox(height: 28),
                                            fade(0.42, countedMenus),
                                            if (topItemsWidget != null) ...[
                                              const SizedBox(height: 28),
                                              fade(0.5, topItemsWidget),
                                            ],
                                            if (waitersWidget != null) ...[
                                              const SizedBox(height: 28),
                                              fade(0.6, waitersWidget),
                                            ],
                                            const SizedBox(height: 28),
                                          ],
                                        );
                                      }

                                      // Header + AI banner always span full
                                      // width; the responsive grid sits below.
                                      Widget shell(
                                        double maxWidth,
                                        Widget grid,
                                      ) {
                                        return Center(
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: maxWidth,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(height: 16),
                                                fade(0.0, header),
                                                const SizedBox(height: 20),
                                                fade(0.04, aiCard),
                                                const SizedBox(height: 20),
                                                grid,
                                                const SizedBox(height: 28),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      Widget col(List<Widget> children) =>
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: children,
                                          );

                                      // Extra-wide desktop (e.g. 1728px Mac):
                                      // three balanced columns like the mockup.
                                      if (constraints.maxWidth >= 1320) {
                                        return shell(
                                          1600,
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: col([
                                                  fade(0.15, hero),
                                                  const SizedBox(height: 20),
                                                  fade(0.25, secondary),
                                                ]),
                                              ),
                                              Expanded(
                                                child: col([
                                                  fade(0.42, countedMenus),
                                                  const SizedBox(height: 20),
                                                  fade(0.38, quickActions),
                                                  if (topItemsWidget !=
                                                      null) ...[
                                                    const SizedBox(height: 20),
                                                    fade(0.5, topItemsWidget),
                                                  ],
                                                ]),
                                              ),
                                              Expanded(
                                                child: col([
                                                  fade(0.08, activeDay),
                                                  const SizedBox(height: 20),
                                                  fade(0.32, pulse),
                                                  const SizedBox(height: 20),
                                                  fade(0.35, tables),
                                                  if (waitersWidget !=
                                                      null) ...[
                                                    const SizedBox(height: 20),
                                                    fade(0.6, waitersWidget),
                                                  ],
                                                ]),
                                              ),
                                            ],
                                          ),
                                        );
                                      }

                                      // Tablet / small desktop: two columns.
                                      return shell(
                                        1240,
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: col([
                                                fade(0.15, hero),
                                                const SizedBox(height: 20),
                                                fade(0.25, secondary),
                                                const SizedBox(height: 20),
                                                fade(0.42, countedMenus),
                                                if (topItemsWidget != null) ...[
                                                  const SizedBox(height: 20),
                                                  fade(0.5, topItemsWidget),
                                                ],
                                              ]),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: col([
                                                fade(0.08, activeDay),
                                                const SizedBox(height: 20),
                                                fade(0.32, pulse),
                                                const SizedBox(height: 20),
                                                fade(0.35, tables),
                                                const SizedBox(height: 20),
                                                fade(0.38, quickActions),
                                                if (waitersWidget != null) ...[
                                                  const SizedBox(height: 20),
                                                  fade(0.6, waitersWidget),
                                                ],
                                              ]),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayPoint {
  final String label;
  final double value;
  final bool isToday;
  const _DayPoint({
    required this.label,
    required this.value,
    required this.isToday,
  });
}

class _CountedMenusSummary {
  final List<Map<String, dynamic>> drafts;
  final double totalValue;
  final int totalItems;

  const _CountedMenusSummary({
    required this.drafts,
    required this.totalValue,
    required this.totalItems,
  });

  int get draftCount => drafts.length;
  List<Map<String, dynamic>> get recent => drafts.take(3).toList();
}

/// ------------------------------------------------------------------
/// SECTIONS
/// ------------------------------------------------------------------

class _Header extends StatelessWidget {
  final String greeting;
  final String name;
  final VoidCallback? onNotifications;

  const _Header({
    required this.greeting,
    required this.name,
    this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    color: context.dash.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.dash.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          _BouncingButton(
            onTap: () => onNotifications?.call(),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.dash.headerButtonBackground,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: context.dash.textPrimary.withOpacity(0.04),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ValueListenableBuilder<int>(
                valueListenable:
                    AppNotificationHistoryStore.instance.unreadCount,
                builder: (_, unread, __) {
                  return Stack(
                    children: [
                      Icon(
                        Icons.notifications_outlined,
                        color: context.dash.textPrimary,
                      ),
                      if (unread > 0)
                        Positioned(top: 2, right: 2, child: _Dot()),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AIInsightsCard extends StatelessWidget {
  const _AIInsightsCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.dash.primarySoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.dash.primary.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.dash.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vynic AI პროგნოზი',
                    style: TextStyle(
                      color: context.dash.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'ამინდის გაუარესების გამო, დღეს მოსალოდნელია მიტანის სერვისზე მოთხოვნის 25%-ით ზრდა.',
                    style: TextStyle(
                      color: context.dash.textPrimary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBusinessDayCard extends StatefulWidget {
  final ManagerDashboardMetrics metrics;
  final String Function(String?) formatOpened;
  final String Function() formatDuration;

  const _ActiveBusinessDayCard({
    required this.metrics,
    required this.formatOpened,
    required this.formatDuration,
  });

  @override
  State<_ActiveBusinessDayCard> createState() => _ActiveBusinessDayCardState();
}

class _ActiveBusinessDayCardState extends State<_ActiveBusinessDayCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final isOpen = m.businessDayStatus.toUpperCase() == 'OPEN';
    final statusColor = isOpen ? context.dash.good : context.dash.textSecondary;
    final dayId = m.businessDayId ?? m.businessDate ?? '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _DashboardCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        isOpen ? 'ღია' : 'დახურული',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.schedule_rounded,
                  color: context.dash.textSecondary,
                  size: 18,
                ),
                SizedBox(width: 6),
                Text(
                  widget.formatDuration(),
                  style: TextStyle(
                    color: context.dash.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            Text(
              'აქტიური სამუშაო დღე',
              style: TextStyle(color: context.dash.textSecondary, fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              dayId,
              style: TextStyle(
                color: context.dash.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.login_rounded,
                  size: 16,
                  color: context.dash.textSecondary,
                ),
                SizedBox(width: 6),
                Text(
                  'გახსნა: ${widget.formatOpened(m.businessDayOpenedAt)}',
                  style: TextStyle(
                    color: context.dash.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _PaymentChip({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.dash.textSecondary,
                    fontSize: 10,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _gelExact(amount),
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TablesOverviewStrip extends StatelessWidget {
  final ManagerDashboardMetrics metrics;
  final VoidCallback onTap;

  const _TablesOverviewStrip({required this.metrics, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _BouncingButton(
        onTap: onTap,
        child: _DashboardCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _SectionHeader(title: 'მაგიდები'),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.dash.textSecondary,
                    size: 20,
                  ),
                ],
              ),
              SizedBox(height: 14),
              Row(
                children: [
                  _TableStatChip(
                    label: 'დაკავ.',
                    count: metrics.occupiedTables,
                    color: context.dash.warn,
                  ),
                  SizedBox(width: 8),
                  _TableStatChip(
                    label: 'თავისუფ.',
                    count: metrics.freeTables,
                    color: context.dash.good,
                  ),
                  SizedBox(width: 8),
                  _TableStatChip(
                    label: 'რეზ.',
                    count: metrics.reservedTables,
                    color: context.dash.info,
                  ),
                  const Spacer(),
                  Text(
                    '${metrics.totalTables} სულ',
                    style: TextStyle(
                      color: context.dash.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableStatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _TableStatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: context.dash.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _HeroRevenueCard extends StatelessWidget {
  final ManagerDashboardMetrics metrics;
  final List<_DayPoint> series;
  final double? dayChange;
  final VoidCallback onTap;

  const _HeroRevenueCard({
    required this.metrics,
    required this.series,
    required this.dayChange,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final closed = metrics.closedTablesRevenue;
    final open = metrics.openTablesPayable;
    final openCount = metrics.occupiedTables;
    final hasOpen = openCount > 0 && open > 0.005;
    final total = hasOpen ? metrics.shiftTotalRevenue : closed;
    final hasCompare = dayChange != null;
    final up = (dayChange ?? 0) >= 0;
    final compareColor = !hasCompare
        ? context.dash.textSecondary
        : (up ? context.dash.good : context.dash.bad);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _BouncingButton(
        onTap: onTap,
        child: _HeroRevenueShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'აქტიური ცვლის შემოსავალი',
                          style: TextStyle(
                            color: context.dash.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: context.dash.textSecondary,
                          size: 20,
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    TweenAnimationBuilder<double>(
                      key: ValueKey(total.toStringAsFixed(2)),
                      tween: Tween(begin: 0, end: total),
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.easeOutCubic,
                      builder: (context, val, __) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _gelExact(val),
                          style: TextStyle(
                            color: context.dash.textPrimary,
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      hasOpen ? 'დახურული + ღია მაგიდები' : 'დახურული მაგიდები',
                      style: TextStyle(
                        color: context.dash.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    SizedBox(height: 14),
                    _RevenueSplitRow(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'დახურული',
                      amount: closed,
                      color: context.dash.good,
                    ),
                    if (metrics.nonFiscalClosedRevenue > 0.005) ...[
                      SizedBox(height: 8),
                      _RevenueSplitRow(
                        icon: Icons.receipt_long_rounded,
                        label: 'აქედან არაფისკ.',
                        amount: metrics.nonFiscalClosedRevenue,
                        color: context.dash.info,
                      ),
                    ],
                    if (hasOpen) ...[
                      SizedBox(height: 8),
                      _RevenueSplitRow(
                        icon: Icons.table_bar_rounded,
                        label: 'ღია ($openCount)',
                        amount: open,
                        color: context.dash.warn,
                      ),
                    ],
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: compareColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                !hasCompare
                                    ? Icons.remove_rounded
                                    : (up
                                          ? Icons.trending_up_rounded
                                          : Icons.trending_down_rounded),
                                color: compareColor,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                hasCompare
                                    ? '${up ? '+' : ''}${dayChange!.toStringAsFixed(1)}%'
                                    : '—',
                                style: TextStyle(
                                  color: compareColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'წინა ცვლასთან',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.dash.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (metrics.cashRevenue > 0 || metrics.cardRevenue > 0) ...[
                      SizedBox(height: 14),
                      Row(
                        children: [
                          if (metrics.cashRevenue > 0)
                            Expanded(
                              child: _PaymentChip(
                                label: 'ნაღდი (დახურ.)',
                                amount: metrics.cashRevenue,
                                color: context.dash.good,
                                icon: Icons.payments_outlined,
                              ),
                            ),
                          if (metrics.cashRevenue > 0 &&
                              metrics.cardRevenue > 0)
                            SizedBox(width: 8),
                          if (metrics.cardRevenue > 0)
                            Expanded(
                              child: _PaymentChip(
                                label: 'ბარათი (დახურ.)',
                                amount: metrics.cardRevenue,
                                color: context.dash.info,
                                icon: Icons.credit_card_rounded,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (metrics.refunds > 0) ...[
                      SizedBox(height: 8),
                      _RevenueSplitRow(
                        icon: Icons.replay_rounded,
                        label: 'დაბრუნებები',
                        amount: metrics.refunds,
                        color: context.dash.bad,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 20),

              // NEW SMOOTH AREA CHART
              SizedBox(
                height: 100,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                  child: CustomPaint(
                    painter: _SmoothAreaChartPainter(
                      series: series,
                      theme: context.dash,
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

class _RevenueSplitRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double amount;
  final Color color;

  const _RevenueSplitRow({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.dash.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _gelExact(amount),
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryStats extends StatelessWidget {
  final int orderCount;
  final double avgOrder;
  final int activeTables;
  final int occupancy;
  final double payable;
  final VoidCallback onTapOrders;
  final VoidCallback onTapTables;

  const _SecondaryStats({
    required this.orderCount,
    required this.avgOrder,
    required this.activeTables,
    required this.occupancy,
    required this.payable,
    required this.onTapOrders,
    required this.onTapTables,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              title: 'შეკვეთები',
              value: orderCount,
              trend: 'საშ ₾${_money.format(avgOrder.round())}',
              isPositive: true,
              icon: Icons.receipt_long_rounded,
              iconColor: context.dash.info,
              onTap: onTapOrders,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              title: 'მაგიდები',
              value: activeTables,
              trend: '$occupancy%',
              isPositive: occupancy < 90,
              icon: Icons.table_restaurant_rounded,
              iconColor: context.dash.warn,
              onTap: onTapTables,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              title: 'გადასახდელი',
              value: payable.round(),
              valueLabel: _gelExact(payable),
              trend: '$activeTables მაგ.',
              isPositive: true,
              icon: Icons.pending_actions_rounded,
              iconColor: context.dash.primary,
              onTap: onTapTables,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerPulseCard extends StatelessWidget {
  final ManagerDashboardMetrics metrics;
  final List<Map<String, dynamic>> reservations;
  final VoidCallback? onTapTables;
  final VoidCallback? onTapReservations;

  const _ManagerPulseCard({
    required this.metrics,
    required this.reservations,
    this.onTapTables,
    this.onTapReservations,
  });

  List<_PulseItem> _attentionItems(DashboardThemeData t) {
    final items = <_PulseItem>[];
    final occ = metrics.occupancyPercentage.round();
    final payable = metrics.openTablesPayable;
    final active = metrics.activeTablesCount;

    if (occ >= 90) {
      items.add(
        _PulseItem(
          icon: Icons.warning_amber_rounded,
          color: t.bad,
          text: 'მაღალი დატვირთვა — $occ% დაკავებული',
          onTap: onTapTables,
        ),
      );
    } else if (occ >= 70) {
      items.add(
        _PulseItem(
          icon: Icons.table_restaurant_rounded,
          color: t.warn,
          text: '$active მაგიდა აქტიური ($occ%)',
          onTap: onTapTables,
        ),
      );
    }
    if (payable >= 300) {
      items.add(
        _PulseItem(
          icon: Icons.payments_rounded,
          color: t.warn,
          text: '${_gelExact(payable)} გადაუხდელი',
          onTap: onTapTables,
        ),
      );
    }

    final upcoming = _upcomingReservations();
    if (upcoming.isNotEmpty) {
      items.add(
        _PulseItem(
          icon: Icons.event_available_rounded,
          color: t.primary,
          text: '${upcoming.length} რეზ. • შემდეგი ${upcoming.first['time']}',
          onTap: onTapReservations,
        ),
      );
    } else if (reservations.isEmpty) {
      items.add(
        _PulseItem(
          icon: Icons.event_busy_rounded,
          color: t.textSecondary,
          text: 'დღეს რეზერვაცია არ არის',
          onTap: onTapReservations,
        ),
      );
    }

    if (metrics.todayOrderCount == 0 && DateTime.now().hour >= 12) {
      items.add(
        _PulseItem(
          icon: Icons.hourglass_empty_rounded,
          color: t.bad,
          text: 'დღეს ჯერ შეკვეთა არ ყოფილა',
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        _PulseItem(
          icon: Icons.check_circle_rounded,
          color: t.good,
          text: 'ყველაფერი ნორმალურად მიდის',
        ),
      );
    }
    return items.take(4).toList();
  }

  List<Map<String, String>> _upcomingReservations() {
    final out = <Map<String, String>>[];
    for (final r in reservations) {
      final s = (r['status'] ?? '').toString().toLowerCase();
      if (s.startsWith('cancelled') || s.startsWith('completed')) continue;
      final t = (r['reservationTime'] ?? '').toString();
      if (t.isEmpty) continue;
      out.add({'time': t, 'name': (r['customerName'] ?? '').toString()});
    }
    out.sort((a, b) => a['time']!.compareTo(b['time']!));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final occ = metrics.occupancyPercentage.round().clamp(0, 100);
    final ringColor = occ >= 90
        ? context.dash.bad
        : (occ >= 70 ? context.dash.warn : context.dash.good);
    final t = context.dash;
    final items = _attentionItems(t);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _DashboardCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'დღის პულსი'),
            SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 88,
                        height: 88,
                        child: CircularProgressIndicator(
                          value: occ / 100,
                          strokeWidth: 8,
                          backgroundColor: ringColor.withOpacity(0.15),
                          color: ringColor,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$occ%',
                            style: TextStyle(
                              color: context.dash.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'დატვირთ.',
                            style: TextStyle(
                              color: context.dash.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _miniStat(
                        context,
                        'აქტიური მაგიდები',
                        '${metrics.activeTablesCount}',
                        onTapTables,
                      ),
                      SizedBox(height: 8),
                      _miniStat(
                        context,
                        'გადასახდელი',
                        _gelExact(metrics.openTablesPayable),
                        onTapTables,
                      ),
                      SizedBox(height: 8),
                      _miniStat(
                        context,
                        'რეზერვაციები',
                        '${reservations.length}',
                        onTapReservations,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            Text(
              'ყურადღება',
              style: TextStyle(
                color: context.dash.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 10),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PulseRow(item: item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(
    BuildContext context,
    String label,
    String value,
    VoidCallback? onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.dash.textSecondary, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: context.dash.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseItem {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onTap;
  const _PulseItem({
    required this.icon,
    required this.color,
    required this.text,
    this.onTap,
  });
}

class _PulseRow extends StatelessWidget {
  final _PulseItem item;
  const _PulseRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: item.color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: item.color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(item.icon, color: item.color, size: 16),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                item.text,
                style: TextStyle(
                  color: context.dash.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (item.onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: context.dash.textSecondary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _CountedMenusSection extends StatelessWidget {
  final _CountedMenusSummary summary;
  final VoidCallback onOpenAll;
  final VoidCallback onNewCount;

  const _CountedMenusSection({
    required this.summary,
    required this.onOpenAll,
    required this.onNewCount,
  });

  @override
  Widget build(BuildContext context) {
    final hasDrafts = summary.draftCount > 0;
    final maxTotal = summary.recent
        .map(
          (d) =>
              (d['total'] as num?)?.toDouble() ??
              (d['subtotal'] as num?)?.toDouble() ??
              0,
        )
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _DashboardCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.dash.warn.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.fact_check_rounded,
                    color: context.dash.warn,
                    size: 22,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'მენიუს დათვლა',
                        style: TextStyle(
                          color: context.dash.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        hasDrafts
                            ? '${summary.draftCount} შენახული · ${summary.totalItems} პოზიცია'
                            : 'დათვალე და შეინახე მენიუ',
                        style: TextStyle(
                          color: context.dash.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _BouncingButton(
                  onTap: onNewCount,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.dash.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          color: context.dash.primary,
                          size: 18,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'ახალი',
                          style: TextStyle(
                            color: context.dash.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            if (hasDrafts) ...[
              Row(
                children: [
                  Expanded(
                    child: _MenuStatTile(
                      label: 'ჯამი',
                      value: '₾${_money.format(summary.totalValue.round())}',
                      color: context.dash.good,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _MenuStatTile(
                      label: 'ჩანაწერები',
                      value: '${summary.draftCount}',
                      color: context.dash.info,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _MenuStatTile(
                      label: 'პოზიციები',
                      value: '${summary.totalItems}',
                      color: context.dash.warn,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: summary.recent.length,
                  separatorBuilder: (_, __) => SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final d = summary.recent[i];
                    final total =
                        (d['total'] as num?)?.toDouble() ??
                        (d['subtotal'] as num?)?.toDouble() ??
                        0;
                    final items = (d['items'] as List?)?.length ?? 0;
                    final share = maxTotal > 0 ? total / maxTotal : 0.0;
                    return _MenuDraftChip(
                      name: (d['displayName'] ?? 'დაუსახელებელი').toString(),
                      total: total,
                      items: items,
                      share: share,
                    );
                  },
                ),
              ),
            ] else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.dash.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.dash.textSecondary.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: context.dash.textSecondary,
                      size: 28,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'ჯერ არაფერი არ არის შენახული.\nდააჭირე „ახალი“ და დაითვალე მენიუ.',
                        style: TextStyle(
                          color: context.dash.textSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: 14),
            _BouncingButton(
              onTap: onOpenAll,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: context.dash.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      hasDrafts
                          ? 'ყველა ჩანაწერის ნახვა'
                          : 'მენიუს დათვლის გახსნა',
                      style: TextStyle(
                        color: context.dash.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: context.dash.textSecondary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuStatTile extends StatelessWidget {
  final String label, value;
  final Color color;

  const _MenuStatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: context.dash.textSecondary, fontSize: 10),
          ),
          SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuDraftChip extends StatelessWidget {
  final String name;
  final double total, share;
  final int items;

  const _MenuDraftChip({
    required this.name,
    required this.total,
    required this.items,
    required this.share,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.dash.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.dash.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '₾${_money.format(total.round())}',
                style: TextStyle(
                  color: context.dash.good,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: share.clamp(0.05, 1.0),
                    minHeight: 4,
                    backgroundColor: context.dash.textSecondary.withOpacity(
                      0.1,
                    ),
                    color: context.dash.primary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '$items პოზ.',
                  style: TextStyle(
                    color: context.dash.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(this.title, this.icon, this.color, this.onTap);
}

class _QuickActionsSection extends StatelessWidget {
  final VoidCallback onCloseBusinessDay,
      onViewReport,
      onExportPdf,
      onReservations,
      onAnnouncement;

  const _QuickActionsSection({
    required this.onCloseBusinessDay,
    required this.onViewReport,
    required this.onExportPdf,
    required this.onReservations,
    required this.onAnnouncement,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(
        'დღის\nდახურვა',
        Icons.nightlight_round,
        context.dash.warn,
        onCloseBusinessDay,
      ),
      _QuickAction(
        'სრული\nანგარიში',
        Icons.assessment_outlined,
        context.dash.primary,
        onViewReport,
      ),
      _QuickAction(
        'PDF\nექსპორტი',
        Icons.picture_as_pdf_rounded,
        context.dash.bad,
        onExportPdf,
      ),
      _QuickAction(
        'რეზ.\nგახსნა',
        Icons.event_seat_rounded,
        context.dash.info,
        onReservations,
      ),
      _QuickAction(
        'შეტყობ.\nგაგზ.',
        Icons.campaign_outlined,
        context.dash.good,
        onAnnouncement,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(title: 'სწრაფი ქმედებები'),
              SizedBox(height: 4),
              Text(
                'აქტიური ცვლის მართვა',
                style: TextStyle(
                  color: context.dash.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              return _BouncingButton(
                onTap: action.onTap,
                child: Container(
                  width: 110,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: _DashboardCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action.icon, color: action.color, size: 28),
                        SizedBox(height: 12),
                        Text(
                          action.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.dash.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TopItemsSection extends StatelessWidget {
  final List<Map<String, dynamic>> topItems;
  const _TopItemsSection({required this.topItems});

  static const _gradients = <List<Color>>[
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFF3B82F6), Color(0xFF06B6D4)],
    [Color(0xFFF59E0B), Color(0xFFEF4444)],
    [Color(0xFF10B981), Color(0xFF059669)],
    [Color(0xFFEC4899), Color(0xFF8B5CF6)],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _SectionHeader(title: "პოპულარული (აქტიური ცვლა)"),
        ),
        SizedBox(height: 16),
        SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: topItems.length,
            itemBuilder: (context, index) {
              final item = topItems[index];
              final name = (item['name'] as String?) ?? '';
              final qty = (item['qty'] as num?)?.toInt() ?? 0;
              final revenue = (item['revenue'] as num?)?.toDouble() ?? 0;
              final grad = _gradients[index % _gradients.length];
              return Container(
                width: 160,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: grad,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: grad.first.withOpacity(0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.restaurant_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '#${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$qty ცალი',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '₾${_money.format(revenue.round())}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WaitersSection extends StatelessWidget {
  final List<StaffMetric> staff;
  const _WaitersSection({required this.staff});

  @override
  Widget build(BuildContext context) {
    final top = staff.take(5).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: "პერსონალის რეიტინგი"),
          SizedBox(height: 16),
          _DashboardCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0)
                    Divider(
                      color: context.dash.textSecondary.withOpacity(0.1),
                      height: 1,
                    ),
                  _WaiterRow(metric: top[i], isFirst: i == 0),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaiterRow extends StatelessWidget {
  final StaffMetric metric;
  final bool isFirst;

  const _WaiterRow({required this.metric, required this.isFirst});

  String get _initials {
    final parts = metric.waiterName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      context.dash.primary,
                      context.dash.avatarGradientEnd,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isFirst)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: context.dash.warn,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.star, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.waiterName.isEmpty ? 'უცნობი' : metric.waiterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.dash.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '${metric.orderCount} შეკვეთა',
                  style: TextStyle(
                    color: context.dash.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '₾${_money.format(metric.totalSales.round())}',
            style: TextStyle(
              color: context.dash.good,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// REUSABLE COMPONENTS
/// ------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String title;
  final int value;
  final String? valueLabel;
  final String trend;
  final bool isPositive;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    this.valueLabel,
    required this.trend,
    required this.isPositive,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = _DashboardCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          SizedBox(height: 14),
          if (valueLabel != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                valueLabel!,
                style: TextStyle(
                  color: context.dash.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            )
          else
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: value),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (context, val, child) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _money.format(val),
                    style: TextStyle(
                      color: context.dash.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                );
              },
            ),
          SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.dash.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            trend,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPositive ? context.dash.good : context.dash.bad,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return _BouncingButton(onTap: onTap!, child: card);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: context.dash.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: context.dash.bad,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: context.dash.bad, blurRadius: 4, spreadRadius: 1),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// EFFECTS & UTILITIES
/// ------------------------------------------------------------------

class _HeroRevenueShell extends StatelessWidget {
  final Widget child;

  const _HeroRevenueShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final t = context.dash;
    const radius = BorderRadius.all(Radius.circular(32));

    if (t.useGlassCards) {
      return ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: t.heroCardBackground,
              border: Border.all(color: t.heroCardBorder),
            ),
            child: child,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.heroCardBackground,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: t.heroCardShadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: t.heroCardBorder),
      ),
      child: child,
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _DashboardCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final t = context.dash;
    const radius = BorderRadius.all(Radius.circular(24));

    if (t.useGlassCards) {
      return ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: t.heroCardBackground,
              border: Border.all(color: t.cardBorder),
            ),
            child: child,
          ),
        ),
      );
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.heroCardBackground,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: t.cardShadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: t.cardBorder),
      ),
      child: child,
    );
  }
}

class _SoftGlow extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;
  const _SoftGlow({
    required this.color,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(opacity), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}

class _FadeInSlide extends StatelessWidget {
  final AnimationController controller;
  final Widget child;
  final double delay;

  const _FadeInSlide({
    required this.controller,
    required this.child,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(delay, 1.0, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - animation.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _BouncingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _BouncingButton({required this.child, required this.onTap});

  @override
  State<_BouncingButton> createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<_BouncingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

class _DashboardSkeleton extends StatefulWidget {
  const _DashboardSkeleton();
  @override
  State<_DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<_DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;
  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 16),
          Row(
            children: [
              _bone(140, 22),
              const Spacer(),
              _bone(44, 44, radius: 999),
              SizedBox(width: 12),
              _bone(44, 44, radius: 999),
            ],
          ),
          SizedBox(height: 28),
          _bone(double.infinity, 200, radius: 28),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _bone(double.infinity, 120, radius: 22)),
              SizedBox(width: 12),
              Expanded(child: _bone(double.infinity, 120, radius: 22)),
              SizedBox(width: 12),
              Expanded(child: _bone(double.infinity, 120, radius: 22)),
            ],
          ),
          SizedBox(height: 28),
          _bone(160, 20),
          SizedBox(height: 16),
          _bone(double.infinity, 110, radius: 24),
        ],
      ),
    );
  }

  Widget _bone(double w, double h, {double radius = 12}) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        final t = _shimmer.value;
        return Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t), 0),
              colors: [
                context.dash.skeletonBase,
                context.dash.skeletonHighlight,
                context.dash.skeletonBase,
              ],
              stops: [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------
// SMOOTH AREA CHART PAINTER (Replaces MiniBars)
// ------------------------------------------------------------------
class _SmoothAreaChartPainter extends CustomPainter {
  final List<_DayPoint> series;
  final DashboardThemeData theme;

  _SmoothAreaChartPainter({required this.series, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final maxVal = series.fold<double>(0, (m, p) => p.value > m ? p.value : m);
    final minVal = 0.0; // Assume baseline is 0

    final path = Path();
    final stepX = size.width / (series.length <= 1 ? 1 : series.length - 1);

    // Calculate Y coordinates
    double getY(double val) {
      if (maxVal == 0) return size.height;
      final fraction = (val - minVal) / (maxVal - minVal);
      // Give some padding at the top so it doesn't touch the very edge
      return size.height - (fraction * (size.height * 0.9));
    }

    path.moveTo(0, getY(series[0].value));

    for (int i = 0; i < series.length - 1; i++) {
      final p0x = i * stepX;
      final p0y = getY(series[i].value);
      final p1x = (i + 1) * stepX;
      final p1y = getY(series[i + 1].value);

      // Control points for smooth bezier curve
      final cx = (p0x + p1x) / 2;
      path.cubicTo(cx, p0y, cx, p1y, p1x, p1y);
    }

    // Paint the stroke (The Line)
    final strokePaint = Paint()
      ..color = theme.chartLine
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, strokePaint);

    // Create the area fill
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    // Paint the gradient area
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [theme.chartFillTop, theme.chartFillBottom],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SmoothAreaChartPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.theme != theme;
}
