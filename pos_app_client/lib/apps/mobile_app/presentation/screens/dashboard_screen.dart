import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/data/repositories/dashboard_repository.dart';
import 'package:vynic/apps/mobile_app/data/services/dashboard_remote_service.dart';
import 'package:vynic/apps/mobile_app/presentation/controllers/dashboard_controller.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_counted_menus_screen.dart';
import 'package:vynic/apps/mobile_app/state/providers/dashboard_state.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/app_notification_history_store.dart';
import 'package:vynic/core/services/monitoring_socket_service.dart';

/// Real manager dashboard, restyled to the dark "glass" design while staying
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
    _controller =
        DashboardController(const DashboardRepository(DashboardRemoteService()));
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _controller.addListener(_onControllerChanged);
    _controller.initialize();
    MonitoringSocketService.updateCounter
        .addListener(_controller.scheduleMetricsRefresh);
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
    MonitoringSocketService.updateCounter
        .removeListener(_controller.scheduleMetricsRefresh);
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
    if (raw is! List) return const [];
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

  /// Map of `yyyy-MM-dd` -> total revenue from the daily history.
  Map<String, double> _dailyRevenueMap(DashboardState state) {
    final map = <String, double>{};
    for (final row in state.salesDaily) {
      final date = (row['date'] ?? '').toString();
      if (date.length < 10) continue;
      final rev = row['totalRevenue'];
      map[date.substring(0, 10)] =
          rev is num ? rev.toDouble() : double.tryParse('$rev') ?? 0;
    }
    return map;
  }

  /// Last 7 closed business days ending with the active business day.
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
    final window =
        dates.length <= 7 ? dates : dates.sublist(dates.length - 7);

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

  /// % change vs the previous closed business day (null if no data).
  double? _previousBusinessDayChange(
    DashboardState state,
    double activeRevenue,
    String? activeBusinessDayId,
  ) {
    final map = _dailyRevenueMap(state);
    final activeKey = activeBusinessDayId ?? _ymd(_businessToday());
    final priorKeys =
        map.keys.where((k) => k.compareTo(activeKey) < 0).toList()..sort();
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
      totalValue += (d['total'] as num?)?.toDouble() ??
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
        builder: (_) => MobileCountedMenusScreen(user: widget.user),
      ),
    );
    if (mounted) _controller.loadAll();
  }

  Future<void> _startCountMenu() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const MobileCalculatorScreen(isCountMode: true),
      ),
    );
    if (saved == true && mounted) _controller.loadAll();
  }

  void _toast(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: color ?? _cGood,
        content: Text(msg),
      ),
    );
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
    final series =
        _last7BusinessDays(state, metrics.shiftTotalRevenue, activeDayId);
    final dayChange = _previousBusinessDayChange(
      state,
      metrics.shiftTotalRevenue,
      activeDayId,
    );
    final menuSummary = _countedMenusSummary(state.countedMenus);

    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      body: Stack(
        children: [
          const Positioned(
            top: -100,
            left: -100,
            child: _GlowOrb(color: Color(0xFF3B82F6), size: 300),
          ),
          const Positioned(
            top: 220,
            right: -150,
            child: _GlowOrb(color: Color(0xFF8B5CF6), size: 400),
          ),
          const Positioned(
            bottom: 0,
            left: 50,
            child: _GlowOrb(color: Color(0xFF10B981), size: 250),
          ),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: const Color(0xFF6366F1),
              backgroundColor: const Color(0xFF15151C),
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
                          ? const _DashboardSkeleton()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),
                                _FadeInSlide(
                                  controller: _animController,
                                  delay: 0.0,
                                  child: _Header(
                                    greeting: _greeting(),
                                    name: widget.user.username,
                                    onNotifications: widget.onOpenNotifications,
                                  ),
                                ),
                                const SizedBox(height: 26),
                                _FadeInSlide(
                                  controller: _animController,
                                  delay: 0.08,
                                  child: _ActiveBusinessDayCard(
                                    metrics: metrics,
                                    formatOpened: _formatOpenedLocal,
                                    formatDuration: () => _formatDuration(
                                      metrics.businessDayOpenedAt,
                                      metrics.businessDayDurationMinutes,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _FadeInSlide(
                                  controller: _animController,
                                  delay: 0.15,
                                  child: _HeroRevenueCard(
                                    metrics: metrics,
                                    series: series,
                                    dayChange: dayChange,
                                    onTap: () => widget.onNavigateTab?.call(2),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _FadeInSlide(
                                  controller: _animController,
                                  delay: 0.25,
                                  child: _SecondaryStats(
                                    orderCount: metrics.todayOrderCount,
                                    avgOrder: avgOrder,
                                    activeTables: metrics.activeTablesCount,
                                    occupancy:
                                        metrics.occupancyPercentage.round(),
                                    payable: metrics.openTablesPayable,
                                    onTapOrders: () =>
                                        widget.onNavigateTab?.call(2),
                                    onTapTables: () =>
                                        widget.onNavigateTab?.call(1),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                _FadeInSlide(
                                  controller: _animController,
                                  delay: 0.32,
                                  child: _ManagerPulseCard(
                                    metrics: metrics,
                                    reservations: state.todayReservations,
                                    onTapTables: () =>
                                        widget.onNavigateTab?.call(1),
                                    onTapReservations: () =>
                                        widget.onNavigateTab?.call(3),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                _FadeInSlide(
                                  controller: _animController,
                                  delay: 0.35,
                                  child: _TablesOverviewStrip(
                                    metrics: metrics,
                                    onTap: () => widget.onNavigateTab?.call(1),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                _FadeInSlide(
                                  controller: _animController,
                                  delay: 0.38,
                                  child: _QuickActionsSection(
                                    onCloseBusinessDay: () => _toast(
                                      'დღის დახურვა ხდება Windows POS-ში',
                                      color: _cWarn,
                                    ),
                                    onViewReport: () =>
                                        widget.onNavigateTab?.call(2),
                                    onExportPdf: () => _toast(
                                      'PDF ექსპორტი მალე დაემატება',
                                      color: _cInfo,
                                    ),
                                    onReservations: () =>
                                        widget.onNavigateTab?.call(3),
                                    onAnnouncement: () => _toast(
                                      'შეტყობინების გაგზავნა მალე დაემატება',
                                      color: _cInfo,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                _FadeInSlide(
                                  controller: _animController,
                                  delay: 0.42,
                                  child: _CountedMenusSection(
                                    summary: menuSummary,
                                    onOpenAll: _openCountedMenus,
                                    onNewCount: _startCountMenu,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                if (topItems.isNotEmpty) ...[
                                  _FadeInSlide(
                                    controller: _animController,
                                    delay: 0.5,
                                    child: _TopItemsSection(topItems: topItems),
                                  ),
                                  const SizedBox(height: 28),
                                ],
                                if (staff.isNotEmpty) ...[
                                  _FadeInSlide(
                                    controller: _animController,
                                    delay: 0.6,
                                    child: _WaitersSection(staff: staff),
                                  ),
                                  const SizedBox(height: 28),
                                ],
                                _FadeInSlide(
                                  controller: _animController,
                                  delay: 0.7,
                                  child: const _LiveActivitySection(),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

// Semantic palette — color carries meaning, not decoration.
const Color _cPrimary = Color(0xFF6366F1);
const Color _cGood = Color(0xFF10B981);
const Color _cBad = Color(0xFFEF4444);
const Color _cWarn = Color(0xFFF59E0B);
const Color _cInfo = Color(0xFF3B82F6);

class _DayPoint {
  final String label;
  final double value;
  final bool isToday;
  const _DayPoint(
      {required this.label, required this.value, required this.isToday});
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
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _BouncingButton(
            onTap: () => onNotifications?.call(),
            child: _GlassContainer(
              padding: const EdgeInsets.all(12),
              shape: BoxShape.circle,
              child: ValueListenableBuilder<int>(
                valueListenable:
                    AppNotificationHistoryStore.instance.unreadCount,
                builder: (_, unread, __) {
                  return Stack(
                    children: [
                      const Icon(Icons.notifications_outlined,
                          color: Colors.white),
                      if (unread > 0)
                        const Positioned(
                          top: 2,
                          right: 2,
                          child: _Dot(),
                        ),
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
    final statusColor = isOpen ? _cGood : Colors.white.withOpacity(0.5);
    final dayId = m.businessDayId ?? m.businessDate ?? '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _GlassContainer(
        padding: const EdgeInsets.all(20),
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.35)),
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
                      const SizedBox(width: 6),
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
                Icon(Icons.schedule_rounded,
                    color: Colors.white.withOpacity(0.45), size: 18),
                const SizedBox(width: 6),
                Text(
                  widget.formatDuration(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'აქტიური სამუშაო დღე',
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dayId,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.login_rounded,
                    size: 16, color: Colors.white.withOpacity(0.45)),
                const SizedBox(width: 6),
                Text(
                  'გახსნა: ${widget.formatOpened(m.businessDayOpenedAt)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 10,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₾${_money.format(amount.round())}',
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

  const _TablesOverviewStrip({
    required this.metrics,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _BouncingButton(
        onTap: onTap,
        child: _GlassContainer(
          padding: const EdgeInsets.all(18),
          borderRadius: BorderRadius.circular(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _SectionHeader(title: 'მაგიდები'),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withOpacity(0.4), size: 20),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _TableStatChip(
                    label: 'დაკავ.',
                    count: metrics.occupiedTables,
                    color: _cWarn,
                  ),
                  const SizedBox(width: 8),
                  _TableStatChip(
                    label: 'თავისუფ.',
                    count: metrics.freeTables,
                    color: _cGood,
                  ),
                  const SizedBox(width: 8),
                  _TableStatChip(
                    label: 'რეზ.',
                    count: metrics.reservedTables,
                    color: _cInfo,
                  ),
                  const Spacer(),
                  Text(
                    '${metrics.totalTables} სულ',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
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
        color: color.withOpacity(0.12),
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
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero card: shift total with closed vs open table breakdown.
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
        ? Colors.white.withOpacity(0.5)
        : (up ? _cGood : _cBad);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _BouncingButton(
        onTap: onTap,
        child: _GlassContainer(
          padding: const EdgeInsets.all(22),
          borderRadius: BorderRadius.circular(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'აქტიური ცვლის შემოსავალი',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withOpacity(0.4), size: 20),
                ],
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                key: ValueKey(total.round()),
                tween: Tween(begin: 0, end: total),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (context, val, __) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₾${_money.format(val.round())}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasOpen ? 'დახურული + ღია მაგიდები' : 'დახურული მაგიდები',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 14),
              _RevenueSplitRow(
                icon: Icons.check_circle_outline_rounded,
                label: 'დახურული მაგიდები',
                amount: closed,
                color: _cGood,
              ),
              if (hasOpen) ...[
                const SizedBox(height: 8),
                _RevenueSplitRow(
                  icon: Icons.table_bar_rounded,
                  label: 'ღია მაგიდები ($openCount)',
                  amount: open,
                  color: _cWarn,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
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
                        const SizedBox(width: 4),
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
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'წინა ცვლასთან',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (metrics.cashRevenue > 0 || metrics.cardRevenue > 0) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (metrics.cashRevenue > 0)
                      Expanded(
                        child: _PaymentChip(
                          label: 'ნაღდი (დახურ.)',
                          amount: metrics.cashRevenue,
                          color: _cGood,
                          icon: Icons.payments_outlined,
                        ),
                      ),
                    if (metrics.cashRevenue > 0 && metrics.cardRevenue > 0)
                      const SizedBox(width: 8),
                    if (metrics.cardRevenue > 0)
                      Expanded(
                        child: _PaymentChip(
                          label: 'ბარათი (დახურ.)',
                          amount: metrics.cardRevenue,
                          color: _cInfo,
                          icon: Icons.credit_card_rounded,
                        ),
                      ),
                  ],
                ),
              ],
              if (metrics.refunds > 0) ...[
                const SizedBox(height: 8),
                _RevenueSplitRow(
                  icon: Icons.replay_rounded,
                  label: 'დაბრუნებები',
                  amount: metrics.refunds,
                  color: _cBad,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(height: 64, child: _MiniBars(series: series)),
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
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '₾${_money.format(amount.round())}',
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

class _MiniBars extends StatelessWidget {
  final List<_DayPoint> series;
  const _MiniBars({required this.series});

  @override
  Widget build(BuildContext context) {
    final maxVal = series.fold<double>(
        0, (m, p) => p.value > m ? p.value : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final p in series)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final frac = maxVal <= 0 ? 0.0 : p.value / maxVal;
                        final h = (c.maxHeight * frac).clamp(4.0, c.maxHeight);
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: h),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            builder: (_, value, __) => Container(
                              height: value,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: p.isToday
                                      ? [_cPrimary, const Color(0xFF8B5CF6)]
                                      : [
                                          Colors.white.withOpacity(0.10),
                                          Colors.white.withOpacity(0.18),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.label,
                    style: TextStyle(
                      color: p.isToday
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                      fontSize: 10,
                      fontWeight:
                          p.isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
              iconColor: _cInfo,
              onTap: onTapOrders,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              title: 'მაგიდები',
              value: activeTables,
              trend: '$occupancy%',
              isPositive: occupancy < 90,
              icon: Icons.table_restaurant_rounded,
              iconColor: _cWarn,
              onTap: onTapTables,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              title: 'გადასახდელი',
              value: payable.round(),
              prefix: '₾',
              trend: '$activeTables მაგ.',
              isPositive: true,
              icon: Icons.pending_actions_rounded,
              iconColor: _cPrimary,
              onTap: onTapTables,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live "day pulse" for managers — occupancy ring + attention items
/// computed from metrics we already have (no extra backend needed).
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

  List<_PulseItem> _attentionItems() {
    final items = <_PulseItem>[];
    final occ = metrics.occupancyPercentage.round();
    final payable = metrics.openTablesPayable;
    final active = metrics.activeTablesCount;

    if (occ >= 90) {
      items.add(_PulseItem(
        icon: Icons.warning_amber_rounded,
        color: _cWarn,
        text: 'მაღალი დატვირთვა — $occ% დაკავებული',
        onTap: onTapTables,
      ));
    } else if (occ >= 70) {
      items.add(_PulseItem(
        icon: Icons.table_restaurant_rounded,
        color: _cInfo,
        text: '$active მაგიდა აქტიური ($occ%)',
        onTap: onTapTables,
      ));
    }

    if (payable >= 300) {
      items.add(_PulseItem(
        icon: Icons.payments_rounded,
        color: _cWarn,
        text: '₾${_money.format(payable.round())} გადაუხდელი ღია მაგიდებზე',
        onTap: onTapTables,
      ));
    }

    final upcoming = _upcomingReservations();
    if (upcoming.isNotEmpty) {
      final next = upcoming.first;
      items.add(_PulseItem(
        icon: Icons.event_available_rounded,
        color: _cPrimary,
        text: '${upcoming.length} რეზervაცია დღეს • შემდეგი ${next['time']}',
        onTap: onTapReservations,
      ));
    } else if (reservations.isEmpty) {
      items.add(_PulseItem(
        icon: Icons.event_busy_rounded,
        color: Colors.white.withOpacity(0.35),
        text: 'დღეს რეზერვაცია არ არის',
        onTap: onTapReservations,
      ));
    }

    if (metrics.todayOrderCount == 0 && DateTime.now().hour >= 12) {
      items.add(_PulseItem(
        icon: Icons.hourglass_empty_rounded,
        color: _cBad,
        text: 'დღეს ჯერ შეკვეთა არ ყოფილა',
      ));
    }

    if (items.isEmpty) {
      items.add(_PulseItem(
        icon: Icons.check_circle_rounded,
        color: _cGood,
        text: 'ყველაფერი ნორმალურად მიდის',
      ));
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

  Color _ringColor(int occ) {
    if (occ >= 90) return _cBad;
    if (occ >= 70) return _cWarn;
    return _cGood;
  }

  @override
  Widget build(BuildContext context) {
    final occ = metrics.occupancyPercentage.round().clamp(0, 100);
    final ringColor = _ringColor(occ);
    final items = _attentionItems();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _GlassContainer(
        padding: const EdgeInsets.all(20),
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'დღის პულსი'),
            const SizedBox(height: 16),
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
                          backgroundColor: Colors.white.withOpacity(0.08),
                          color: ringColor,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$occ%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'დატვირთ.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _miniStat('აქტიური მაგიდები',
                          '${metrics.activeTablesCount}', onTapTables),
                      const SizedBox(height: 8),
                      _miniStat('გადასახდელი',
                          '₾${_money.format(metrics.openTablesPayable.round())}',
                          onTapTables),
                      const SizedBox(height: 8),
                      _miniStat('რეზervაციები',
                          '${reservations.length}', onTapReservations),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'ყურადღება',
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
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

  Widget _miniStat(String label, String value, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
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
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (item.onTap != null)
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.3), size: 18),
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
        .map((d) =>
            (d['total'] as num?)?.toDouble() ??
            (d['subtotal'] as num?)?.toDouble() ??
            0)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _GlassContainer(
        padding: const EdgeInsets.all(20),
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _cWarn.withOpacity(0.25),
                        _cPrimary.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.fact_check_rounded,
                      color: Color(0xFFFBBF24), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'მენიუს დათვლა',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        hasDrafts
                            ? '${summary.draftCount} შენახული · ${summary.totalItems} პოზიცია'
                            : 'დათვალე და შეინახე მენიუ (ბანკეტი, ღონისძიება)',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
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
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _cPrimary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _cPrimary.withOpacity(0.35)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: _cPrimary, size: 18),
                        SizedBox(width: 4),
                        Text(
                          'ახალი',
                          style: TextStyle(
                            color: _cPrimary,
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
            const SizedBox(height: 18),
            if (hasDrafts) ...[
              Row(
                children: [
                  Expanded(
                    child: _MenuStatTile(
                      label: 'ჯამი',
                      value: '₾${_money.format(summary.totalValue.round())}',
                      color: _cGood,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MenuStatTile(
                      label: 'ჩანაწერები',
                      value: '${summary.draftCount}',
                      color: _cInfo,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MenuStatTile(
                      label: 'პოზიციები',
                      value: '${summary.totalItems}',
                      color: _cWarn,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: summary.recent.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final d = summary.recent[i];
                    final total = (d['total'] as num?)?.toDouble() ??
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
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        color: Colors.white.withOpacity(0.35), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'ჯერ არაფერი არ არის შენახული.\nდააჭირე „ახალი“ და დაითვალე მენიუ.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            _BouncingButton(
              onTap: onOpenAll,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      hasDrafts ? 'ყველა ჩანაწერის ნახვა' : 'მენიუს დათვლის გახსნა',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded,
                        color: Colors.white.withOpacity(0.45), size: 18),
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
  final String label;
  final String value;
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
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
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
  final double total;
  final int items;
  final double share;

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
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
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
                  color: _cGood.withOpacity(0.95),
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
                    backgroundColor: Colors.white.withOpacity(0.08),
                    color: _cPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$items პოზ.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
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
  final VoidCallback onCloseBusinessDay;
  final VoidCallback onViewReport;
  final VoidCallback onExportPdf;
  final VoidCallback onReservations;
  final VoidCallback onAnnouncement;

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
      _QuickAction('დღის\nდახურვა', Icons.nightlight_round,
          _cWarn, onCloseBusinessDay),
      _QuickAction('სრული\nანგარიში', Icons.assessment_outlined,
          _cPrimary, onViewReport),
      _QuickAction('PDF\nექსპორტი', Icons.picture_as_pdf_rounded,
          _cBad, onExportPdf),
      _QuickAction('რეზ.\nგახსნა', Icons.event_seat_rounded,
          _cInfo, onReservations),
      _QuickAction('შეტყობ.\nგაგზ.', Icons.campaign_outlined,
          _cGood, onAnnouncement),
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
              const SizedBox(height: 4),
              Text(
                'აქტიური ცვლის მართვა',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
                  child: _GlassContainer(
                    padding: const EdgeInsets.all(16),
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action.icon, color: action.color, size: 28),
                        const SizedBox(height: 12),
                        Text(
                          action.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
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
        const SizedBox(height: 16),
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
                      color: grad.first.withOpacity(0.35),
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
                          child: const Icon(Icons.restaurant_rounded,
                              color: Colors.white, size: 18),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
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
                    const SizedBox(height: 6),
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
          const SizedBox(height: 16),
          _GlassContainer(
            padding: const EdgeInsets.all(8),
            borderRadius: BorderRadius.circular(24),
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0)
                    Divider(color: Colors.white.withOpacity(0.08), height: 1),
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
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
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
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.waiterName.isEmpty ? 'უცნობი' : metric.waiterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${metric.orderCount} შეკვეთა',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '₾${_money.format(metric.totalSales.round())}',
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveActivitySection extends StatelessWidget {
  const _LiveActivitySection();

  String _timeAgo(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) return 'ახლახ';
    if (d.inMinutes < 60) return '${d.inMinutes} წთ';
    if (d.inHours < 24) return '${d.inHours} სთ';
    return '${d.inDays} დღე';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _SectionHeader(title: "ცოცხალი აქტივობა"),
              SizedBox(width: 8),
              _LiveIndicator(),
            ],
          ),
          const SizedBox(height: 16),
          _GlassContainer(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(24),
            child: ValueListenableBuilder<List<AppNotificationEntry>>(
              valueListenable: AppNotificationHistoryStore.instance.entries,
              builder: (_, entries, __) {
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded,
                            color: Colors.white.withOpacity(0.4), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'ჯერ არაფერია — რეალტაიმ მოვლენები აქ გამოჩნდება',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final shown = entries.take(5).toList();
                return Column(
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: i == shown.length - 1 ? 0 : 16),
                        child: _ActivityRow(
                          entry: shown[i],
                          timeAgo: _timeAgo(shown[i].at),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final AppNotificationEntry entry;
  final String timeAgo;
  const _ActivityRow({required this.entry, required this.timeAgo});

  (Color, IconData) _style() {
    final t = '${entry.title} ${entry.message}'.toLowerCase();
    if (t.contains('გაუქმ') || t.contains('წაიშ') || t.contains('cancel')) {
      return (const Color(0xFFEF4444), Icons.cancel_outlined);
    }
    if (t.contains('რეზერ')) {
      return (const Color(0xFF3B82F6), Icons.book_online);
    }
    if (t.contains('walk') || t.contains('მაგიდ')) {
      return (const Color(0xFFF59E0B), Icons.lock_open);
    }
    if (t.contains('გატან') || t.contains('აღება')) {
      return (const Color(0xFF06B6D4), Icons.takeout_dining);
    }
    if (t.contains('გადახ') || t.contains('paid') || t.contains('ჩაიხურა')) {
      return (const Color(0xFF10B981), Icons.check_circle);
    }
    return (const Color(0xFF8B5CF6), Icons.notifications);
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _style();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                entry.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ------------------------------------------------------------------
/// REUSABLE COMPONENTS
/// ------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String title;
  final int value;
  final String prefix;
  final String trend;
  final bool isPositive;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    this.prefix = '',
    required this.trend,
    required this.isPositive,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = _GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, val, child) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$prefix${_money.format(val)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            trend,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPositive ? _cGood : _cBad,
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
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
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
      decoration: const BoxDecoration(
        color: Color(0xFFEF4444),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0xFFEF4444), blurRadius: 4, spreadRadius: 1),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// EFFECTS & UTILITIES
/// ------------------------------------------------------------------

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  const _GlassContainer({
    required this.child,
    this.padding,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  @override
  Widget build(BuildContext context) {
    final radius = shape == BoxShape.circle
        ? null
        : (borderRadius ?? BorderRadius.circular(20));
    return ClipRRect(
      borderRadius: shape == BoxShape.circle
          ? BorderRadius.circular(999)
          : (radius ?? BorderRadius.zero),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            shape: shape,
            borderRadius: shape == BoxShape.rectangle ? radius : null,
            color: Colors.white.withOpacity(0.04),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Soft background glow. Uses a radial gradient (cheap) instead of a live
/// [BackdropFilter] blur — visually similar but far better for scroll perf,
/// especially with the glass cards already running their own blur.
class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(0.22),
              color.withOpacity(0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator();
  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFEF4444),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0xFFEF4444), blurRadius: 6, spreadRadius: 2),
          ],
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
    _scale = Tween<double>(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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

/// Shimmering skeleton that mimics the dashboard layout while data loads.
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
          const SizedBox(height: 16),
          Row(
            children: [
              _bone(140, 22),
              const Spacer(),
              _bone(44, 44, radius: 999),
              const SizedBox(width: 12),
              _bone(44, 44, radius: 999),
            ],
          ),
          const SizedBox(height: 28),
          _bone(double.infinity, 200, radius: 28),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _bone(double.infinity, 120, radius: 22)),
              const SizedBox(width: 12),
              Expanded(child: _bone(double.infinity, 120, radius: 22)),
              const SizedBox(width: 12),
              Expanded(child: _bone(double.infinity, 120, radius: 22)),
            ],
          ),
          const SizedBox(height: 28),
          _bone(160, 20),
          const SizedBox(height: 16),
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
                Colors.white.withOpacity(0.04),
                Colors.white.withOpacity(0.10),
                Colors.white.withOpacity(0.04),
              ],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}
