import 'package:vynic/apps/mobile_app/core/theme/manager_theme.dart';
import 'package:vynic/apps/mobile_app/widgets/mobile_glass_ui.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/mobile_api_service.dart';
import 'package:vynic/core/utils/table_group_style.dart';
import 'package:vynic/core/services/monitoring_socket_service.dart';
import 'package:vynic/core/widgets/manager_toast.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/create_takeaway_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_order_detail_screen.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_calculator_screen.dart';

part 'views/live_status_tables_part.dart';
part 'views/live_status_takeaway_part.dart';

class LiveStatusScreen extends StatefulWidget {
  final User user;
  const LiveStatusScreen({super.key, required this.user});

  @override
  State<LiveStatusScreen> createState() => _LiveStatusScreenState();
}


class _LiveStatusScreenState extends State<LiveStatusScreen> {
  Timer? _refreshTimer;

  Map<String, List<TableModel>> _tablesByFloor = {};
  bool _tablesLoading = true;

  List<Order> _takeawayOrders = [];
  bool _takeawayLoading = true;

  int _viewIndex = 0;

  /// 0 = all, 1 = free, 2 = occupied, 3 = reserved.
  int _tableFilter = 0;
  static const List<String> _tableFilters = [
    'ყველა',
    'თავისუფალი',
    'დაკავებული',
    'რეზერვი',
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadAll(),
    );
    MonitoringSocketService.updateCounter.addListener(_loadAll);
    MonitoringSocketService.isConnected.addListener(_onConnectionChange);
    MonitoringSocketService.pendingTableFocus.addListener(_onPendingTableFocus);
  }

  void _onPendingTableFocus() {
    if (MonitoringSocketService.pendingTableFocus.value == null) return;
    unawaited(_consumePendingTableFocus());
  }

  void _onConnectionChange() {
    if (MonitoringSocketService.isConnected.value) {
      _loadAll();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    MonitoringSocketService.updateCounter.removeListener(_loadAll);
    MonitoringSocketService.isConnected.removeListener(_onConnectionChange);
    MonitoringSocketService.pendingTableFocus.removeListener(_onPendingTableFocus);
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadTables(), _loadTakeaway()]);
  }

  Future<void> _loadTables() async {
    try {
      final allTables = await MobileApiService.getTables();
      MonitoringSocketService.apiError.value = false;
      final Map<String, List<TableModel>> grouped = {};
      for (final table in allTables) {
        grouped.putIfAbsent(table.floor, () => []).add(table);
      }
      if (mounted) {
        setState(() {
          _tablesByFloor = grouped;
          _tablesLoading = false;
        });
        if (MonitoringSocketService.pendingTableFocus.value != null) {
          unawaited(_consumePendingTableFocus());
        }
      }
    } catch (_) {
      MonitoringSocketService.apiError.value = true;
      if (mounted) setState(() => _tablesLoading = false);
    }
  }

  Future<void> _loadTakeaway() async {
    try {
      final orders = await MobileApiService.getTakeawayOrders();
      if (mounted) {
        setState(() {
          _takeawayOrders = orders;
          _takeawayLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _takeawayLoading = false);
    }
  }

  void _showStatusToast(
    String message, {
    bool isError = false,
    IconData? icon,
  }) {
    if (!mounted) return;
    ManagerToast.showSnackBar(
      context,
      message,
      isError: isError,
      icon: icon,
    );
  }

  void _setTableFilter(int index) {
    if (_tableFilter == index) return;
    setState(() => _tableFilter = index);
  }

  void _showTablesTabForExternalFocus() {
    setState(() {
      _viewIndex = 0;
      _tableFilter = 0;
    });
  }

  Future<void> _openNewTakeaway() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => managerThemedPage(CreateTakeawayScreen(user: widget.user)),
      ),
    );
    if (result == true) _loadTakeaway();
  }

  @override
  Widget build(BuildContext context) {
    final allTables = _tablesByFloor.values.expand((t) => t).toList();
    final occupiedCount =
        allTables.where((t) => t.activeOrderId != null).length;
    final reservedCount = allTables
        .where((t) => t.isReserved && t.activeOrderId == null)
        .length;
    final activeCount = occupiedCount + reservedCount;
    final takeawayCount = _takeawayOrders
        .where((o) => !_isFinalizedStatus(o.status))
        .length;

    final isTables = _viewIndex == 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            top: -60,
            right: -80,
            child: _GlowOrb(color: Color(0xFF6366F1), size: 300),
          ),
          Positioned(
            bottom: 120,
            left: -100,
            child: _GlowOrb(color: Color(0xFF10B981), size: 260),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // ── Header ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'მაგიდები',
                              style: TextStyle(
                                color: MobileGlassTheme.textPrimary,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              isTables
                                  ? '$activeCount აქტიური • ${allTables.length} სულ'
                                  : '$takeawayCount აქტიური გატანა',
                              style: TextStyle(
                                color: MobileGlassTheme.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isTables)
                        _GlassPanel(
                          onTap: _openNewTakeaway,
                          shape: BoxShape.circle,
                          padding: const EdgeInsets.all(12),
                          child: Icon(Icons.add_rounded,
                              color: MobileGlassTheme.textPrimary),
                        ),
                    ],
                  ),
                ),
                // ── View switcher (Tables / Takeaways) ────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: _viewPill(
                          label: 'მაგიდები',
                          icon: Icons.table_bar_rounded,
                          badge: activeCount,
                          isActive: isTables,
                          onTap: () => setState(() => _viewIndex = 0),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: _viewPill(
                          label: 'გატანები',
                          icon: Icons.takeout_dining_rounded,
                          badge: takeawayCount,
                          isActive: !isTables,
                          onTap: () => setState(() => _viewIndex = 1),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 6),
                Expanded(
                  child: RefreshIndicator(
                    color: MobileGlassTheme.primary,
                    backgroundColor: MobileGlassTheme.surfaceCard,
                    onRefresh: _loadAll,
                    child: isTables
                        ? _buildTablesView()
                        : _buildTakeawayView(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewPill({
    required String label,
    required IconData icon,
    required int badge,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: isActive
              ? MobileGlassTheme.primary
              : MobileGlassTheme.surface(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? MobileGlassTheme.primary
                : MobileGlassTheme.border(0.12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.white : MobileGlassTheme.textSecondary,
            ),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color:
                    isActive ? Colors.white : MobileGlassTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge > 0) ...[
              SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.25)
                      : MobileGlassTheme.surface(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    color: isActive
                        ? Colors.white
                        : MobileGlassTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// SHARED DARK "GLASS" WIDGETS (available to the part views)
/// ------------------------------------------------------------------

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? borderColor;
  final double borderWidth;

  const _GlassPanel({
    required this.child,
    this.padding,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.onTap,
    this.onLongPress,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MobileGlassTheme.of(context);
    final radius = shape == BoxShape.circle
        ? BorderRadius.circular(999)
        : (borderRadius ?? BorderRadius.circular(20));

    final fill = theme.useGlassCards
        ? theme.surfaceCard
        : theme.heroCardBackground;

    Widget panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? radius : null,
        color: fill,
        border: Border.all(
          color: borderColor ?? theme.cardBorder,
          width: borderWidth,
        ),
        boxShadow: theme.isDark
            ? null
            : [
                BoxShadow(
                  color: theme.cardShadow,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );

    if (theme.useGlassCards) {
      panel = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: panel,
        ),
      );
    } else {
      panel = ClipRRect(borderRadius: radius, child: panel);
    }

    if (onTap != null || onLongPress != null) {
      panel = GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: panel,
      );
    }
    return panel;
  }
}

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
          color: color.withOpacity(0.15),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
