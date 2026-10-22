import '../widgets/manager_preview_charts.dart';
import '../widgets/manager_design_components.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_data_status.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import '../widgets/financial_planning_card.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/inventory_summary_card.dart';
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
import 'package:vynic/apps/mobile_app/state/providers/dashboard_state.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

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

String _gelExact(num amount) => '${_moneyExact.format(amount)} ₾';

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

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController(
      const DashboardRepository(DashboardRemoteService()),
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
    final raw = state.productAnalytics?['byQuantity'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => {...e.cast<String, dynamic>(), 'qty': e['quantity']})
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

  Map<String, double?> _dailyRevenueMap(DashboardState state) {
    final map = <String, double?>{};
    for (final row in state.salesDaily) {
      final date = (row['date'] ?? '').toString();
      if (date.length < 10) continue;
      final rev = row['totalRevenue'];
      final value = rev is num ? rev.toDouble() : double.tryParse('$rev');
      map[date.substring(0, 10)] = value != null && value.isFinite
          ? value
          : null;
    }
    return map;
  }

  List<ManagerRevenuePoint> _last7BusinessDays(
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
      const months = [
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
      final month = parts.length >= 3 ? int.tryParse(parts[1]) : null;
      final label = month != null && month >= 1 && month <= 12
          ? '${int.tryParse(parts[2]) ?? parts[2]} ${months[month - 1]}'
          : dateKey;
      return ManagerRevenuePoint(
        label: label,
        value: isActive ? activeRevenue : map[dateKey],
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

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final metrics = state.metrics ?? _empty;

    final staff = [...state.staff]
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
    final topItems = _topItems(state);
    final activeDayId = metrics.businessDate ?? metrics.businessDayId;
    final series = _last7BusinessDays(
      state,
      metrics.closedTablesRevenue,
      activeDayId,
    );
    final dayChange = _previousBusinessDayChange(
      state,
      metrics.closedTablesRevenue,
      activeDayId,
    );

    return ManagerDataBoundary(
      reads: state.reads,
      blocks: const {
        'dashboard',
        'product_analytics',
        'staff_performance',
        'sales_daily',
        'financials',
        'reservations',
        'counted_menus',
      },
      onRefresh: _controller.loadAll,
      child: ManagerThemeListener(
        child: Builder(
          builder: (context) {
            final theme = managerThemeOf(context);
            return Scaffold(
              backgroundColor: theme.scaffoldBackground,
              body: SafeArea(
                bottom: false,
                child: RefreshIndicator(
                  color: theme.primary,
                  onRefresh: () async {
                    await MobileApiService.refreshEntitlements();
                    await _controller.loadAll();
                  },
                  child: CustomScrollView(
                    key: const PageStorageKey<String>(
                      'manager-dashboard-scroll',
                    ),
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1424),
                            child: Padding(
                              padding: EdgeInsets.all(
                                MediaQuery.sizeOf(context).width < 700
                                    ? 20
                                    : 32,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _Header(
                                    greeting: _greeting(),
                                    name: widget.user.username,
                                    onNotifications: widget.onOpenNotifications,
                                  ),
                                  SizedBox(
                                    height:
                                        MediaQuery.sizeOf(context).width < 700
                                        ? 16
                                        : 24,
                                  ),
                                  if (state.loading && state.metrics == null)
                                    _DashboardSkeleton()
                                  else if (state.metrics == null)
                                    const ManagerDataUnavailable(label: 'დაფა')
                                  else
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final hero = _HeroRevenueCard(
                                          metrics: metrics,
                                          series: series,
                                          financials: state.financials,
                                          financialsAvailable:
                                              state
                                                  .reads['financials']
                                                  ?.location !=
                                              'unavailable',
                                          dayChange: dayChange,
                                          onTap: () =>
                                              widget.onNavigateTab?.call(2),
                                        );
                                        final pulse = ManagerDataSection(
                                          block: 'reservations',
                                          status: state.reads['reservations'],
                                          child: _ManagerPulseCard(
                                            metrics: metrics,
                                            reservations:
                                                state.todayReservations,
                                            onTapTables: () =>
                                                widget.onNavigateTab?.call(1),
                                            onTapReservations: () =>
                                                widget.onNavigateTab?.call(4),
                                          ),
                                        );
                                        final activeDay = _ActiveBusinessDayCard(
                                          metrics: metrics,
                                          formatOpened: _formatOpenedLocal,
                                          formatDuration: () => _formatDuration(
                                            metrics.businessDayOpenedAt,
                                            metrics.businessDayDurationMinutes,
                                          ),
                                        );
                                        Widget column(List<Widget> children) =>
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                for (final entry
                                                    in children.indexed) ...[
                                                  if (entry.$1 > 0)
                                                    const SizedBox(height: 20),
                                                  entry.$2,
                                                ],
                                              ],
                                            );
                                        final bookings = ManagerDataSection(
                                          block: 'reservations',
                                          status: state.reads['reservations'],
                                          child: _UpcomingReservations(
                                            reservations:
                                                state.todayReservations,
                                            onOpen: () =>
                                                widget.onNavigateTab?.call(4),
                                          ),
                                        );
                                        final planning =
                                            ManagerEntitlements.has(
                                              FeatureKeys.financialPlanning,
                                            )
                                            ? const FinancialPlanningCard()
                                            : const SizedBox.shrink();
                                        final products = ManagerDataSection(
                                          block: 'product_analytics',
                                          status:
                                              state.reads['product_analytics'],
                                          child: _TopItemsSection(
                                            topItems: topItems,
                                          ),
                                        );
                                        final extras = [
                                          activeDay,
                                          _TablesOverviewStrip(
                                            metrics: metrics,
                                            onTap: () =>
                                                widget.onNavigateTab?.call(1),
                                          ),
                                          if (ManagerEntitlements.has(
                                            FeatureKeys.inventory,
                                          ))
                                            InventorySummaryCard(
                                              onOpenInventory: () =>
                                                  widget.onNavigateTab?.call(3),
                                            ),
                                          if (staff.isNotEmpty)
                                            _WaitersSection(staff: staff),
                                        ];
                                        if (constraints.maxWidth <= 850)
                                          return column([
                                            hero,
                                            pulse,
                                            if (ManagerEntitlements.has(
                                              FeatureKeys.managerReservations,
                                            ))
                                              bookings,
                                            planning,
                                            products,
                                            ...extras,
                                          ]);
                                        Widget pair(
                                          Widget left,
                                          Widget right,
                                        ) => Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(flex: 5, child: left),
                                            const SizedBox(width: 22),
                                            Expanded(flex: 6, child: right),
                                          ],
                                        );
                                        return column([
                                          hero,
                                          pair(
                                            pulse,
                                            ManagerEntitlements.has(
                                                  FeatureKeys
                                                      .managerReservations,
                                                )
                                                ? bookings
                                                : const SizedBox.shrink(),
                                          ),
                                          pair(planning, products),
                                          ...extras,
                                        ]);
                                      },
                                    ),
                                ],
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
          },
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// SECTIONS
/// ------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.greeting,
    required this.name,
    this.onNotifications,
  });
  final String greeting, name;
  final VoidCallback? onNotifications;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'დღის მიმოხილვა',
            style: TextStyle(
              color: context.dash.textPrimary,
              fontSize: constraints.maxWidth < 700 ? 25 : 30,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$greeting $name',
            style: TextStyle(color: context.dash.textSecondary, fontSize: 14),
          ),
        ],
      );
      return title;
    },
  );
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
    final dayId = m.businessDate ?? m.businessDayId ?? '—';

    return Padding(
      padding: EdgeInsets.zero,
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

class _LedgerProviderChip extends StatelessWidget {
  const _LedgerProviderChip({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: context.dash.info.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.dash.info.withValues(alpha: 0.18)),
    ),
    child: Text(
      '$label ${_gelExact(amount)}',
      style: TextStyle(
        color: context.dash.info,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _TablesOverviewStrip extends StatelessWidget {
  final ManagerDashboardMetrics metrics;
  final VoidCallback onTap;

  const _TablesOverviewStrip({required this.metrics, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _TableStatChip(
                    label: 'დაკავ.',
                    count: metrics.occupiedTables,
                    color: context.dash.warn,
                  ),

                  _TableStatChip(
                    label: 'თავისუფ.',
                    count: metrics.freeTables,
                    color: context.dash.good,
                  ),

                  _TableStatChip(
                    label: 'რეზ.',
                    count: metrics.reservedTables,
                    color: context.dash.info,
                  ),
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
  final List<ManagerRevenuePoint> series;
  final Map<String, dynamic>? financials;
  final bool financialsAvailable;
  final double? dayChange;
  final VoidCallback onTap;

  const _HeroRevenueCard({
    required this.metrics,
    required this.series,
    required this.financials,
    required this.financialsAvailable,
    required this.dayChange,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.dash;
    final closed = metrics.closedTablesRevenue;
    final hasOpen =
        metrics.occupiedTables > 0 && metrics.openTablesPayable > .005;
    final total = hasOpen ? metrics.shiftTotalRevenue : closed;
    // Existing financial endpoint resolves outflows and reporting date together.
    // Do not combine a cached prior business day with the current dashboard.
    final procurement = financials?['procurement'];
    final financialDate = procurement is Map
        ? procurement['businessDate']?.toString()
        : null;
    final sameDay =
        financialsAvailable &&
        financialDate != null &&
        financialDate == (metrics.businessDate ?? metrics.businessDayId);
    final outflows = sameDay
        ? double.tryParse('${financials?['totalOutflows']}')
        : null;
    final difference = sameDay
        ? double.tryParse('${financials?['differenceExact']}')
        : null;
    final expenseValue = outflows == null ? '—' : _gelExact(outflows);
    final balanceValue = difference == null ? '—' : _gelExact(difference);
    final up = (dayChange ?? 0) >= 0;
    final comparison = dayChange == null
        ? '—'
        : '${up ? '+' : ''}${dayChange!.toStringAsFixed(1)}%';
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _PaymentChip(
                label: 'ნაღდი (დახურ.)',
                amount: metrics.cashRevenue,
                color: t.good,
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PaymentChip(
                label: 'ბარათი (დახურ.)',
                amount: metrics.cardRevenue,
                color: t.info,
                icon: Icons.credit_card_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (metrics.tbcRevenue > 0)
              _LedgerProviderChip(label: 'TBC', amount: metrics.tbcRevenue),
            if (metrics.bogRevenue > 0)
              _LedgerProviderChip(label: 'BOG', amount: metrics.bogRevenue),
            if (metrics.advanceApplied > 0)
              _LedgerProviderChip(
                label: 'ავანსი',
                amount: metrics.advanceApplied,
              ),
          ],
        ),
        if (ManagerEntitlements.has(FeatureKeys.nonFiscalClose) &&
            metrics.nonFiscalClosedRevenue > .005)
          _RevenueSplitRow(
            icon: Icons.receipt_long_outlined,
            label: 'აქედან არაფისკ.',
            amount: metrics.nonFiscalClosedRevenue,
            color: t.info,
          ),
        if (metrics.refunds > 0)
          _RevenueSplitRow(
            icon: Icons.replay,
            label: 'დაბრუნებები',
            amount: metrics.refunds,
            color: t.bad,
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 850;
        Widget metric(
          String title,
          String value, {
          String? sub,
          bool large = false,
        }) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: managerDesignText(context, compact ? 11 : 12, muted: true),
            ),
            SizedBox(height: compact ? 5 : 12),
            Text(
              value,
              style: managerDesignText(
                context,
                compact ? 19 : 24,
                weight: compact ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 12),
              Text(sub, style: managerDesignText(context, 10, muted: true)),
            ],
          ],
        );
        final primary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'დღის გაყიდვები',
                    style: managerDesignText(context, 12, muted: true),
                  ),
                ),
                if (compact)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: t.isDark
                          ? t.good.withValues(alpha: .12)
                          : const Color(0xFFEDF5F1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '• დღეს',
                      style: managerDesignText(
                        context,
                        11,
                        weight: FontWeight.w500,
                      ).copyWith(color: t.good),
                    ),
                  ),
              ],
            ),
            SizedBox(height: compact ? 10 : 8),
            Text(
              _gelExact(closed),
              style: managerDesignText(
                context,
                compact ? 36 : 38,
                weight: FontWeight.w600,
              ),
            ),
            SizedBox(height: compact ? 5 : 8),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!compact && dayChange != null)
                  Icon(
                    up ? Icons.trending_up : Icons.trending_down,
                    size: 15,
                    color: up ? t.good : t.bad,
                  ),
                Text(
                  comparison,
                  style: managerDesignText(
                    context,
                    12,
                    weight: FontWeight.w600,
                  ).copyWith(color: up ? t.good : t.bad),
                ),
                Text(
                  'წინა საქმიან დღესთან',
                  style: managerDesignText(
                    context,
                    compact ? 10 : 11,
                    muted: true,
                  ),
                ),
              ],
            ),
          ],
        );
        return ManagerPanel(
          padding: compact ? 20 : 26,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact)
                primary
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: primary),
                    for (final value in [
                      (
                        'გასავლები',
                        expenseValue,
                        outflows == null
                            ? 'მონაცემი მიუწვდომელია'
                            : 'უკვე გადახდილი',
                      ),
                      (
                        'ნაშთი',
                        balanceValue,
                        difference == null
                            ? 'მონაცემი მიუწვდომელია'
                            : 'გაყიდვები − გასავლები',
                      ),
                      (
                        'შეკვეთები',
                        '${metrics.todayOrderCount}',
                        'დღეს დასრულებული',
                      ),
                    ])
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.only(left: 24),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: t.cardBorder),
                            ),
                          ),
                          child: metric(value.$1, value.$2, sub: value.$3),
                        ),
                      ),
                  ],
                ),
              if (!compact) ...[
                const SizedBox(height: 28),
                const Divider(height: 1),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'გაყიდვების დინამიკა',
                      style: managerDesignText(
                        context,
                        12,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    'ბოლო 7 საქმიანი დღე',
                    style: managerDesignText(context, 10, muted: true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ManagerRevenueBars(points: series, compact: compact),
              if (compact) ...[
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: metric('გასავლები', expenseValue)),
                    Container(height: 43, width: 1, color: t.cardBorder),
                    const SizedBox(width: 20),
                    Expanded(child: metric('ნაშთი', balanceValue)),
                  ],
                ),
                if (outflows == null) const SizedBox(height: 8),
                if (outflows == null)
                  Text(
                    'გასავლების მონაცემი მიუწვდომელია',
                    style: managerDesignText(context, 10, muted: true),
                  ),
              ],
              if (metrics.financialWarning != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    metrics.financialWarning!,
                    style: managerDesignText(
                      context,
                      12,
                    ).copyWith(color: t.warn),
                  ),
                ),
              const SizedBox(height: 12),
              ExpansionTile(
                key: const PageStorageKey<String>('manager-dashboard-payments'),
                minTileHeight: 40,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(
                  'გადახდის დეტალები',
                  style: managerDesignText(context, 12, muted: true),
                ),
                children: [
                  ManagerKeyValue('აქტიური ცვლის ჯამი', _gelExact(total)),
                  ManagerKeyValue(
                    'ღია შეკვეთები',
                    _gelExact(metrics.openTablesPayable),
                  ),
                  details,
                ],
              ),
            ],
          ),
        );
      },
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
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
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
                fontWeight: FontWeight.w600,
              ),
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
    if (ManagerEntitlements.has(FeatureKeys.managerReservations) &&
        upcoming.isNotEmpty) {
      items.add(
        _PulseItem(
          icon: Icons.event_available_rounded,
          color: t.primary,
          text: '${upcoming.length} რეზ. • შემდეგი ${upcoming.first['time']}',
          onTap: onTapReservations,
        ),
      );
    } else if (ManagerEntitlements.has(FeatureKeys.managerReservations) &&
        reservations.isEmpty) {
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
    final t = context.dash;
    return ManagerPanel(
      padding: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManagerSectionHeading(
            'რესტორანი ახლა',
            action: 'მაგიდები',
            onAction: onTapTables,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${metrics.occupiedTables}',
                style: managerDesignText(context, 34, weight: FontWeight.w600),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 7, left: 6),
                  child: Text(
                    '/ ${metrics.totalTables} მაგიდა დაკავებულია',
                    style: managerDesignText(context, 12, muted: true),
                  ),
                ),
              ),
              Text(
                '${metrics.occupancyPercentage.round()}%',
                style: managerDesignText(
                  context,
                  15,
                  weight: FontWeight.w600,
                ).copyWith(color: t.primary),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ManagerOccupancyBars(
            total: metrics.totalTables,
            occupied: metrics.occupiedTables,
          ),
          const SizedBox(height: 17),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ManagerKeyValue(
            'ღია შეკვეთების თანხა',
            _gelExact(metrics.openTablesPayable),
          ),
          const ManagerKeyValue('წაღების შეკვეთები', 'მიუწვდომელია'),
          ExpansionTile(
            key: const PageStorageKey<String>('manager-dashboard-attention'),
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              'ყურადღება',
              style: managerDesignText(context, 12, muted: true),
            ),
            children: [
              for (final item in _attentionItems(t))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PulseRow(item: item),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpcomingReservations extends StatelessWidget {
  const _UpcomingReservations({required this.reservations, this.onOpen});
  final List<Map<String, dynamic>> reservations;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final t = context.dash;
    final upcoming =
        reservations.where((r) {
          final status = '${r['status']}'.toLowerCase();
          return !status.startsWith('cancelled') &&
              !status.startsWith('completed');
        }).toList()..sort(
          (a, b) =>
              '${a['reservationTime']}'.compareTo('${b['reservationTime']}'),
        );
    return ManagerPanel(
      padding: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ManagerSectionHeading(
            'მომდევნო რეზერვაციები',
            action: 'ყველა',
            onAction: onOpen,
          ),
          if (upcoming.isEmpty)
            Text(
              'დღეს რეზერვაცია არ არის',
              style: managerDesignText(context, 12, muted: true),
            ),
          for (final r in upcoming.take(3))
            InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: t.scaffoldBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${r['reservationTime'] ?? '—'}',
                        textAlign: TextAlign.center,
                        style: managerDesignText(
                          context,
                          12,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['customerName'] ?? ''}',
                            style: managerDesignText(
                              context,
                              12,
                              weight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${r['numberOfGuests'] ?? '—'} სტუმარი · მაგიდა ${(r['tableNumbers'] as List? ?? const []).join(', ')}',
                            style: managerDesignText(context, 10, muted: true),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 17, color: t.textSecondary),
                  ],
                ),
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

class _TopItemsSection extends StatelessWidget {
  final List<Map<String, dynamic>> topItems;
  const _TopItemsSection({required this.topItems});

  @override
  Widget build(BuildContext context) => ManagerPanel(
    padding: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ManagerSectionHeading(
          'პოპულარული პროდუქტები',
          subtitle: 'დღეს გაყიდული რაოდენობა',
        ),
        if (topItems.isEmpty)
          Text(
            'პროდუქტების მონაცემები არ არის',
            style: managerDesignText(context, 12, muted: true),
          ),
        for (final item in topItems)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['name'] ?? ''}',
                    style: managerDesignText(context, 12),
                  ),
                ),
                Text(
                  '${item['qty'] ?? '—'} ც',
                  style: managerDesignText(context, 11, muted: true),
                ),
                const SizedBox(width: 28),
                SizedBox(
                  width: 80,
                  child: Text(
                    item['revenue'] == null
                        ? '—'
                        : _gelExact((item['revenue'] as num)),
                    textAlign: TextAlign.right,
                    style: managerDesignText(
                      context,
                      12,
                      weight: FontWeight.w500,
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

class _WaitersSection extends StatelessWidget {
  final List<StaffMetric> staff;
  const _WaitersSection({required this.staff});

  @override
  Widget build(BuildContext context) {
    final top = staff.take(5).toList();
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: "პერსონალის რეიტინგი"),
          if (top.isNotEmpty)
            Text(
              'შეკვეთის შემქმნელის ჩაწერილი სახელით',
              style: TextStyle(fontSize: 11, color: context.dash.textSecondary),
            ),
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
                  color: context.dash.primarySoft,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: context.dash.primary,
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

/// ------------------------------------------------------------------
/// EFFECTS & UTILITIES
/// ------------------------------------------------------------------

class _DashboardCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _DashboardCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final t = context.dash;
    const radius = BorderRadius.all(Radius.circular(18));

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

class _BouncingButton extends StatelessWidget {
  const _BouncingButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: child,
    ),
  );
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
      padding: EdgeInsets.zero,
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
