import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/mobile_api_service.dart';
import 'package:vynic/core/services/monitoring_socket_service.dart';
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

// Dark "glass" palette (shared with the part views; matches the dashboard tab).
const Color _kAccent = Color(0xFF6366F1);
const Color _kFree = Color(0xFF10B981);
const Color _kOccupied = Color(0xFF3B82F6);
const Color _kReserved = Color(0xFFF59E0B);

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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        elevation: 0,
        backgroundColor: Colors.transparent,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon ?? (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
                size: 18,
                color: isError ? const Color(0xFFB91C1C) : const Color(0xFF047857),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isError ? const Color(0xFF7F1D1D) : const Color(0xFF065F46),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setTableFilter(int index) {
    if (_tableFilter == index) return;
    setState(() => _tableFilter = index);
  }

  Future<void> _openNewTakeaway() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateTakeawayScreen(user: widget.user),
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
          const Positioned(
            top: -60,
            right: -80,
            child: _GlowOrb(color: Color(0xFF6366F1), size: 300),
          ),
          const Positioned(
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
                            const Text(
                              'მაგიდები',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isTables
                                  ? '$activeCount აქტიური • ${allTables.length} სულ'
                                  : '$takeawayCount აქტიური გატანა',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
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
                          child: const Icon(Icons.add_rounded,
                              color: Colors.white),
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
                      const SizedBox(width: 12),
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
                const SizedBox(height: 6),
                Expanded(
                  child: RefreshIndicator(
                    color: _kAccent,
                    backgroundColor: const Color(0xFF15151C),
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
          color: isActive ? _kAccent : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? _kAccent : Colors.white.withOpacity(0.10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.white : Colors.white.withOpacity(0.6),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color:
                    isActive ? Colors.white : Colors.white.withOpacity(0.7),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withOpacity(0.25)
                      : Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
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
    final radius = shape == BoxShape.circle
        ? BorderRadius.circular(999)
        : (borderRadius ?? BorderRadius.circular(20));
    Widget panel = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            shape: shape,
            borderRadius: shape == BoxShape.rectangle ? radius : null,
            color: Colors.white.withOpacity(0.04),
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.08),
              width: borderWidth,
            ),
          ),
          child: child,
        ),
      ),
    );
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
