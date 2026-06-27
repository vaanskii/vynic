import 'package:flutter/services.dart';
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
    MonitoringSocketService.pendingTableFocus.removeListener(
      _onPendingTableFocus,
    );
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
    ManagerToast.showSnackBar(context, message, isError: isError, icon: icon);
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
    // Step 1 — small bottom sheet: phone number OR "wait in place"
    final info = await _showTakeawayInfoSheet();
    if (info == null || !mounted) return;

    // Step 2 — open menu selector
    final selected = await Navigator.of(context).push<List<MenuSelectionLine>>(
      MaterialPageRoute(
        builder: (_) => managerThemedPage(
          MobileCalculatorScreen(
            selectionMode: true,
            initialSelection: const [],
          ),
        ),
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    // Step 3 — create the order
    final items = selected
        .map(
          (e) => {
            'itemName': e.itemName,
            'unitPrice': e.unitPrice,
            'quantity': e.qty,
          },
        )
        .toList();

    final now = DateTime.now().add(const Duration(minutes: 15));
    final defaultPickup =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    try {
      await MobileApiService.createTakeawayOrder(
        customerName: info.waitInPlace ? 'აქ დაელოდება' : info.customerName,
        pickupTime: defaultPickup,
        waiterName: widget.user.username,
        items: items,
      );
      if (!mounted) return;
      ManagerToast.show(context, 'გატანის შეკვეთა შეიქმნა');
      _loadTakeaway();
    } catch (e) {
      if (!mounted) return;
      ManagerToast.show(context, 'შეცდომა: $e', isError: true);
    }
  }

  Future<_TakeawayInfo?> _showTakeawayInfoSheet() {
    return showModalBottomSheet<_TakeawayInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _TakeawayInfoSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allTables = _tablesByFloor.values.expand((t) => t).toList();
    final occupiedCount = allTables
        .where((t) => t.activeOrderId != null)
        .length;
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
                          child: Icon(
                            Icons.add_rounded,
                            color: MobileGlassTheme.textPrimary,
                          ),
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
                    child: isTables ? _buildTablesView() : _buildTakeawayView(),
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
                color: isActive ? Colors.white : MobileGlassTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge > 0) ...[
              SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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

// ── Takeaway creation helpers ─────────────────────────────────────────────────

class _TakeawayInfo {
  final bool waitInPlace;
  final String customerName;
  const _TakeawayInfo({required this.waitInPlace, required this.customerName});
}

class _TakeawayInfoSheet extends StatefulWidget {
  const _TakeawayInfoSheet();

  @override
  State<_TakeawayInfoSheet> createState() => _TakeawayInfoSheetState();
}

class _TakeawayInfoSheetState extends State<_TakeawayInfoSheet> {
  bool _waitInPlace = false;
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _waitInPlace || _phoneController.text.trim().isNotEmpty;

  void _confirm() {
    if (!_canContinue) return;
    Navigator.of(context).pop(
      _TakeawayInfo(
        waitInPlace: _waitInPlace,
        customerName: _phoneController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: MobileGlassTheme.surfaceCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: MobileGlassTheme.borderSubtle)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MobileGlassTheme.borderSubtle,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'ახალი გატანა',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: MobileGlassTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'შეიყვანეთ მომხმარებლის ნომერი ან მონიშნეთ ადგილობრივი',
            style: TextStyle(
              fontSize: 13,
              color: MobileGlassTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              setState(() {
                _waitInPlace = !_waitInPlace;
                if (_waitInPlace) _phoneController.clear();
              });
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _waitInPlace
                    ? MobileGlassTheme.primary.withValues(alpha: 0.10)
                    : MobileGlassTheme.surface(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _waitInPlace
                      ? MobileGlassTheme.primary.withValues(alpha: 0.4)
                      : MobileGlassTheme.borderSubtle,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chair_rounded,
                    size: 20,
                    color: _waitInPlace
                        ? MobileGlassTheme.primary
                        : MobileGlassTheme.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'აქ დაელოდება (ადგილზე)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _waitInPlace
                            ? MobileGlassTheme.primary
                            : MobileGlassTheme.textPrimary,
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _waitInPlace
                          ? MobileGlassTheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: _waitInPlace
                            ? MobileGlassTheme.primary
                            : MobileGlassTheme.borderSubtle,
                        width: 1.5,
                      ),
                    ),
                    child: _waitInPlace
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          if (!_waitInPlace) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\s\+\-\(\)]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ტელეფონის ნომერი',
                prefixIcon: Icon(
                  Icons.phone_rounded,
                  size: 18,
                  color: MobileGlassTheme.textSecondary,
                ),
                filled: true,
                fillColor: MobileGlassTheme.surface(0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: MobileGlassTheme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: MobileGlassTheme.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: MobileGlassTheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (_) => _confirm(),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _canContinue ? _confirm : null,
              icon: const Icon(Icons.menu_book_rounded, size: 18),
              label: const Text(
                'გაგრძელება — მენიუს არჩევა',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: MobileGlassTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: MobileGlassTheme.primary.withValues(
                  alpha: 0.30,
                ),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
