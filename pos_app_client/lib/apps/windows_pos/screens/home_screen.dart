import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show min;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_context.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/sync_events.dart';
import 'package:vynic/core/services/pos_live_refresh.dart';
import 'package:vynic/core/services/monitoring_socket_service.dart';
import 'package:vynic/core/services/app_notification_history_store.dart';
import 'package:vynic/core/services/pos_change_highlight_service.dart';
import 'package:vynic/core/services/printer_service.dart';
import 'package:vynic/core/widgets/notification_history_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/table_selection_widget.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_top_bar_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_tables_dashboard_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_calculator_page.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_logout_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_admin_tools_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservation_menu_preview.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservations_helper.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservation_table_assignment_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_take_away_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_x_report_helper.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_x_report_section.dart';
import 'package:vynic/apps/windows_pos/widgets/reservations_management_section.dart';
import 'login_screen.dart';
import 'menu_screen.dart';
import 'order_detail_screen.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  final User user;

  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _SidebarDestination {
  const _SidebarDestination({
    required this.key,
    required this.icon,
    required this.label,
    required this.builder,
  });

  final String key;
  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

// ignore: unused_element
class _SidebarActionEntry {
  const _SidebarActionEntry(
    this.badgeLabel,
    this.badgeColor, {
    required this.icon,
    required this.label,
    required this.onTap,
    required this.background,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color iconColor;
  final String? badgeLabel;
  final Color? badgeColor;
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<TableSelectionWidgetState> _tableSelectionKey = GlobalKey();
  int _currentFloor = 1;
  static String?
  _lastActivationDate; // Track when we last activated reservations
  static const Color _primaryColor = Color(0xFF1E3A8A);
  static const Color _secondaryColor = Color(0xFF2563EB);
  static const Color _surfaceColor = Color(0xFFF4F6FF);
  static const Color _textPrimary = Color(0xFF1F2937);
  static const Color _mutedText = Color(0xFF475569);

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  late bool _isSidebarExpanded;
  final bool _showSidebarLabels = true;
  String _reservationStatusFilter = 'confirmed';
  DateTime? _reservationDateFilter;
  int _activeDestinationIndex = 0;
  late final List<_SidebarDestination> _destinations;
  final FocusNode _shortcutFocusNode = FocusNode(debugLabel: 'home-shortcuts');
  String? _lastToastNotificationId;
  bool _notificationsPanelOpen = false;
  String? _highlightedReservationId;
  Timer? _reservationHighlightTimer;
  StreamSubscription<SyncEvent>? _syncEventsSub;
  Timer? _syncRefreshDebounce;
  Timer? _syncRefreshFollowUp;
  Timer? _syncRefreshFinalFollowUp;

  void _onLiveDataChanged() {
    if (!mounted) return;
    _scheduleLiveRefresh();
  }

  @override
  void initState() {
    super.initState();
    _isSidebarExpanded = !_isMobile;
    // Activate today's confirmed reservations only if we haven't done it today
    _activateReservationsIfNeeded();
    _reservationDateFilter = null;
    _destinations = _createDestinations();
    final initialMenuIndex = _destinations.indexWhere(
      (destination) => destination.key == 'menu',
    );
    if (initialMenuIndex != -1) {
      _activeDestinationIndex = initialMenuIndex;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _shortcutFocusNode.requestFocus();
      }
    });
    AppNotificationHistoryStore.instance.entries.addListener(
      _onNotificationEntriesChanged,
    );
    // Live-refresh the floor plan / reservations when data changes locally
    // (e.g. mobile walk-in, cancellation, or reservation arriving via ingest).
    _syncEventsSub = SyncHub.events.listen(_onSyncEvent);
    // The WebSocket push (which also drives the toast notification) is the most
    // reliable cross-device signal: it bumps on every server-side change, even
    // when the local ingest write races behind it. Refresh on it too.
    MonitoringSocketService.updateCounter.addListener(_onRemoteUpdateSignal);
    PosLiveRefresh.generation.addListener(_onLiveDataChanged);
  }

  @override
  void dispose() {
    PosLiveRefresh.generation.removeListener(_onLiveDataChanged);
    AppNotificationHistoryStore.instance.entries.removeListener(
      _onNotificationEntriesChanged,
    );
    MonitoringSocketService.updateCounter.removeListener(_onRemoteUpdateSignal);
    _syncEventsSub?.cancel();
    _syncRefreshDebounce?.cancel();
    _syncRefreshFollowUp?.cancel();
    _syncRefreshFinalFollowUp?.cancel();
    _reservationHighlightTimer?.cancel();
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  void _onSyncEvent(SyncEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case SyncEventType.tables:
      case SyncEventType.orders:
      case SyncEventType.reservations:
        break;
      case SyncEventType.menu:
      case SyncEventType.connection:
        return;
    }
    _scheduleLiveRefresh();
  }

  void _onRemoteUpdateSignal() {
    if (!mounted) return;
    _scheduleLiveRefresh();
  }

  /// Coalesce bursts (a walk-in reserves multiple tables + creates an order,
  /// and the WS push + local ingest both fire) into a single refresh so the
  /// floor plan / takeaway / reservation lists repaint once, automatically.
  ///
  /// The WebSocket push can arrive before the local ingest HTTP write lands in
  /// Hive, so a single refresh may read stale data. We refresh shortly after
  /// the burst settles, then once more to guarantee the final write is shown.
  void _scheduleLiveRefresh() {
    _syncRefreshDebounce?.cancel();
    _syncRefreshDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      unawaited(_refreshTables());
      _syncRefreshFollowUp?.cancel();
      _syncRefreshFollowUp = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        unawaited(_refreshTables());
      });
      _syncRefreshFinalFollowUp?.cancel();
      _syncRefreshFinalFollowUp = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        unawaited(_refreshTables());
      });
    });
  }

  void _onNotificationEntriesChanged() {
    _scheduleLiveRefresh();
    final list = AppNotificationHistoryStore.instance.entries.value;
    if (!mounted || list.isEmpty) {
      return;
    }
    final latest = list.first;
    if (_lastToastNotificationId == latest.id) {
      return;
    }
    _lastToastNotificationId = latest.id;
    unawaited(
      showPosToast(
        context: context,
        message: '${latest.title}\n${latest.message}',
        style: PosToastStyle.info,
      ),
    );
  }

  void _toggleNotificationsPanel() {
    final opening = !_notificationsPanelOpen;
    setState(() => _notificationsPanelOpen = opening);
    if (!opening) {
      AppNotificationHistoryStore.instance.markAllRead();
      setState(() {});
    }
  }

  void _onNotificationEntryTap(AppNotificationEntry entry) {
    AppNotificationHistoryStore.instance.markEntryRead(entry.id);
    setState(() => _notificationsPanelOpen = false);
    AppNotificationHistoryStore.instance.markAllRead();
    final meta = entry.meta;
    if (meta == null) return;

    final reservationId = meta['reservationId']?.toString();
    if (reservationId != null && reservationId.isNotEmpty) {
      _openReservationFromNotification(reservationId);
      return;
    }

    final orderId = (meta['posOrderId'] as num?)?.toInt();
    if (orderId == null) return;
    final rawKeys = meta['highlightItemKeys'];
    if (rawKeys is List) {
      PosChangeHighlightService.setForOrder(
        orderId,
        rawKeys.map((e) => e.toString()),
      );
    }
    _openOrderDetail(orderId);
  }

  void _openReservationFromNotification(String reservationId) {
    final reservationIndex = _destinations.indexWhere(
      (d) => d.key == 'newReservation',
    );

    // Switch to the reservations tab and highlight the new reservation card.
    setState(() {
      if (reservationIndex >= 0) {
        _activeDestinationIndex = reservationIndex;
      }
      _highlightedReservationId = reservationId;
    });

    // Clear the highlight after a short while so it fades back to normal.
    _reservationHighlightTimer?.cancel();
    _reservationHighlightTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      setState(() => _highlightedReservationId = null);
    });
  }

  List<Widget> _notificationOverlayWidgets(BuildContext context) {
    if (!_notificationsPanelOpen) {
      return const [];
    }
    final mq = MediaQuery.of(context);
    final panelHeight = min(480.0, mq.size.height * 0.58);
    return [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _notificationsPanelOpen = false),
          child: Container(color: Colors.black.withValues(alpha: 0.22)),
        ),
      ),
      Positioned(
        top: mq.padding.top + 8,
        right: 16,
        width: min(400.0, mq.size.width - 32),
        height: panelHeight,
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Text(
                        'შეტყობინებები',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setState(() => _notificationsPanelOpen = false),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ColoredBox(
                  color: const Color(0xFFF8FAFC),
                  child: ValueListenableBuilder<List<AppNotificationEntry>>(
                    valueListenable:
                        AppNotificationHistoryStore.instance.entries,
                    builder: (_, entries, __) => NotificationHistoryPanel(
                      entries: entries,
                      dense: true,
                      onEntryTap: _onNotificationEntryTap,
                      onClear: () => setState(() {
                        AppNotificationHistoryStore.instance.clear();
                      }),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<_SidebarDestination> _createDestinations() {
    final destinations = <_SidebarDestination>[
      _SidebarDestination(
        key: 'menu',
        icon: Icons.restaurant_outlined,
        label: 'მაგიდები',
        builder: (context) => HomeTablesDashboardSection(
          primaryColor: _primaryColor,
          tableSelectionKey: _tableSelectionKey,
          onSelectionChanged: _updateButtonState,
          onTableTap: _handleReservedTableTap,
        ),
      ),
      _SidebarDestination(
        key: 'calculate',
        icon: Icons.functions_outlined,
        label: 'მენიუს დათვლა',
        builder: (context) => _buildCalculatorPage(),
      ),
      _SidebarDestination(
        key: 'todaysTakeaways',
        icon: Icons.receipt_long_outlined,
        label: 'გატანები',
        builder: (context) => _buildTodayTakeAwayPage(),
      ),
      _SidebarDestination(
        key: 'newReservation',
        icon: Icons.event_note_outlined,
        label: 'რეზერვაცია',
        builder: (context) => _buildReservationsDashboard(),
      ),
      _SidebarDestination(
        key: 'xReport',
        icon: Icons.assessment_outlined,
        label: 'X ანგარიში',
        builder: (context) => _buildXReportPage(),
      ),
    ];

    if (widget.user.canAccessManagementCenter) {
      destinations.add(
        _SidebarDestination(
          key: 'adminPanel',
          icon: Icons.settings_suggest_outlined,
          label: 'მართვის ცენტრი',
          builder: (context) => HomeAdminToolsSection(
            onOpenAdminPanel: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminScreen(user: widget.user),
                ),
              ).then((_) => setState(() {}));
            },
            primaryColor: _primaryColor,
            secondaryColor: _secondaryColor,
            textPrimary: _textPrimary,
            mutedText: _mutedText,
          ),
        ),
      );
    }

    destinations.add(
      _SidebarDestination(
        key: 'logout',
        icon: Icons.logout_outlined,
        label: 'გამოსვლა',
        builder: (context) => HomeLogoutSection(
          username: widget.user.username,
          role: widget.user.role,
          onLogout: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          },
          primaryColor: _primaryColor,
          secondaryColor: _secondaryColor,
          textPrimary: _textPrimary,
          mutedText: _mutedText,
        ),
      ),
    );

    return destinations;
  }

  int _countActiveTakeAways(DateTime date) {
    final reservations = DatabaseService.getTakeAwayReservationsForDate(date);
    return reservations.where((reservation) {
      final status = reservation.status.toLowerCase();
      return status != 'completed' && status != 'cancelled';
    }).length;
  }

  double _calculateOpenedTablesAmount(DateTime date) {
    final dateKey = date.toIso8601String().split('T')[0];
    final activeOrders = DatabaseService.getAllOrders().where((order) {
      final status = order.status.toLowerCase();
      final isOpen =
          status != 'closed' && status != 'cancelled' && status != 'paid';
      if (!isOpen) {
        return false;
      }

      final orderDateKey = order.createdAt.toIso8601String().split('T')[0];
      if (orderDateKey != dateKey) {
        return false;
      }

      final isTakeAway =
          order.floor.toLowerCase().contains('takeaway') ||
          order.floor.toLowerCase().contains('take away') ||
          order.tableNumbers.any(
            (table) => table.toLowerCase().startsWith('ta-'),
          );
      return !isTakeAway;
    });

    return activeOrders.fold<double>(
      0,
      (sum, order) => sum + order.totalAmount,
    );
  }

  Widget _buildXReportPage() {
    final dailySalesTotal = DatabaseService.getDailySalesTotal();
    final currentDate = DatabaseService.getCurrentDate();
    final takeAwayCount = _countActiveTakeAways(currentDate);
    final openedTablesAmount = widget.user.isAdmin
        ? _calculateOpenedTablesAmount(currentDate)
        : null;
    final currentDateKey = currentDate.toIso8601String().split('T')[0];
    final todaysSales = DatabaseService.getSalesForDate(currentDateKey);
    final waiterSummaries = HomeXReportHelper.buildWaiterSummaries(todaysSales);
    return HomeXReportSection(
      dailySalesTotal: dailySalesTotal,
      openedTablesAmount: openedTablesAmount,
      takeAwayCount: takeAwayCount,
      activeWaitersCount: waiterSummaries.length,
      waiterSummaries: waiterSummaries,
      onPrintReport: () => unawaited(HomeXReportHelper.printReport(context)),
      primaryColor: _primaryColor,
      secondaryColor: _secondaryColor,
      textPrimary: _textPrimary,
      mutedText: _mutedText,
    );
  }

  Widget _buildCalculatorPage() {
    return HomeCalculatorPage(
      user: widget.user,
      primaryColor: _primaryColor,
      secondaryColor: _secondaryColor,
      textPrimary: _textPrimary,
      mutedText: _mutedText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _activeDestinationIndex;
    final activeDestinationKey = _destinations[activeIndex].key;
    final currentDate = DatabaseService.getCurrentDate();
    final takeAwayCount = _countActiveTakeAways(currentDate);
    final reservationCount =
        HomeReservationsHelper.countConfirmedReservationsForDate(currentDate);

    final sidebarBadges = _destinations
        .map<int?>(
          (destination) {
            if (destination.key == 'todaysTakeaways' && takeAwayCount > 0) {
              return takeAwayCount;
            }
            if (destination.key == 'newReservation' && reservationCount > 0) {
              return reservationCount;
            }
            return null;
          },
        )
        .toList();

    final pages = _destinations
        .map(
          (destination) => KeyedSubtree(
            key: ValueKey(destination.key),
            child: destination.builder(context),
          ),
        )
        .toList();

    final mainContentStack = Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            ValueListenableBuilder<int>(
              valueListenable:
                  AppNotificationHistoryStore.instance.unreadCount,
              builder: (context, unread, _) {
                return HomeTopBarSection(
                  user: widget.user,
                  currentFloor: _currentFloor,
                  onSwitchFloor: _switchFloor,
                  primaryColor: _primaryColor,
                  secondaryColor: _secondaryColor,
                  surfaceColor: _surfaceColor,
                  textPrimary: _textPrimary,
                  mutedText: _mutedText,
                  showFloorSwitcher: activeDestinationKey == 'menu',
                  onToggleSidebar: _isMobile
                      ? () {
                          setState(() {
                            _isSidebarExpanded = !_isSidebarExpanded;
                          });
                        }
                      : null,
                  notificationUnreadCount: unread,
                  onNotificationTap: _toggleNotificationsPanel,
                );
              },
            ),
            Expanded(
              child: Container(
                padding: EdgeInsets.zero,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF8FAFF), Color(0xFFEFF4FF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: IndexedStack(index: activeIndex, children: pages),
                ),
              ),
            ),
          ],
        ),
        ..._notificationOverlayWidgets(context),
      ],
    );

    final scaffold = Scaffold(
      backgroundColor: _surfaceColor,
      appBar: null,
      body: _isMobile
          ? Stack(
              children: [
                mainContentStack,
                if (_isSidebarExpanded)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isSidebarExpanded = false;
                        });
                      },
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                _buildSidebar(
                  activeIndex: activeIndex,
                  badgeCounts: sidebarBadges,
                ),
              ],
            )
          : Row(
              children: [
                _buildSidebar(
                  activeIndex: activeIndex,
                  badgeCounts: sidebarBadges,
                ),
                Expanded(child: mainContentStack),
              ],
            ),
      bottomNavigationBar: activeDestinationKey == 'menu'
          ? _buildMenuButtonBar()
          : null,
    );

    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      child: scaffold,
    );
  }

  Widget _buildTodayTakeAwayPage() {
    final today = DatabaseService.getCurrentDate();
    final takeAwayReservations = DatabaseService.getTakeAwayReservationsForDate(
      today,
    );
    return HomeTakeAwaySection(
      user: widget.user,
      takeAwayReservations: takeAwayReservations,
      onRefreshRequested: _refreshTables,
      primaryColor: _primaryColor,
      secondaryColor: _secondaryColor,
      textPrimary: _textPrimary,
      mutedText: _mutedText,
    );
  }

  Widget _buildReservationsDashboard() {
    final currentDate = DatabaseService.getCurrentDate();
    final normalizedToday = HomeReservationsHelper.normalizeDateOnly(
      currentDate,
    );
    final adminReservations =
        HomeReservationsHelper.getAdminPanelReservations();

    final canManageReservations = widget.user.canManageReservationsOnHome;

    return SizedBox.expand(
      child: ReservationsManagementSection(
      reservations: adminReservations,
      normalizedToday: normalizedToday,
      filterDate: _reservationDateFilter,
      statusFilter: _reservationStatusFilter,
      showCancelledTab: false,
      highlightReservationId: _highlightedReservationId,
      canAssignTableToReservation: canManageReservations,
      canCancelReservation: false,
      canDeleteReservation: false,
      onFilterDateChanged: (value) {
        setState(() => _reservationDateFilter = value);
      },
      onStatusFilterChanged: (value) {
        setState(() => _reservationStatusFilter = value);
      },
      onCreateReservation: null,
      onEditReservation:
          canManageReservations ? _editReservationDetails : null,
      onViewPreOrder: (reservation) => HomeReservationMenuPreview.show(
        context: context,
        reservation: reservation,
        primaryColor: _primaryColor,
        textPrimary: _textPrimary,
        mutedText: _mutedText,
      ),
      onManagePreOrder:
          canManageReservations ? _editReservationMenu : null,
      onSendKitchenCheck: widget.user.canSendReservationKitchenCheckOnHome
          ? _sendReservationKitchenCheck
          : null,
      onAssignTable:
          canManageReservations ? _assignReservationToTable : null,
      onAssignTableUnavailable: canManageReservations
          ? (reservation) async {
              final isToday = HomeReservationsHelper.isSameDate(
                reservation.reservationDate,
                DatabaseService.getCurrentDate(),
              );
              unawaited(
                showPosToast(
                  context: context,
                  message: isToday
                      ? 'სუფრაზე გადაყვანა ვერ მოხერხდა.'
                      : 'სუფრაზე გადაყვანა შესაძლებელია მხოლოდ რეზერვაციის დღეს.',
                  style: PosToastStyle.info,
                ),
              );
            }
          : null,
        primaryColor: _primaryColor,
        secondaryColor: _secondaryColor,
        textPrimary: _textPrimary,
        mutedText: _mutedText,
      ),
    );
  }

  Future<void> _sendReservationKitchenCheck(Reservation reservation) async {
    final kitchenItems = HomeReservationsHelper.buildKitchenCheckLines(
      reservation,
    );
    if (kitchenItems.isEmpty) {
      unawaited(
        showPosToast(
          context: context,
          message: 'სამზარეულოს ჩეკისთვის პროდუქტები არ არის დამატებული.',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    final tableLabel = reservation.tableNumbers.isNotEmpty
        ? reservation.tableNumbers.join(', ')
        : null;
    final orderLabel = HomeReservationsHelper.buildKitchenOrderLabel(
      reservation,
    );
    final kitchenTime = HomeReservationsHelper.buildKitchenTime(reservation);

    PrinterService.printKitchenCheckInBackground(
      items: kitchenItems,
      tableNumber: tableLabel,
      orderNumber: orderLabel,
      waiterName: widget.user.username,
      createdAt: kitchenTime,
      onComplete: (success) {
        if (!mounted) return;
        if (success) {
          unawaited(showSuccessToast(context, 'ჩეკი გაიგზავნა სამზარეულოში'));
        } else {
          unawaited(showErrorToast(context, 'პრინტერი მიუწვდომელია'));
        }
      },
    );
  }

  Future<void> _editReservationMenu(Reservation reservation) async {
    final selectedItems = await Navigator.push<List<OrderItem>>(
      context,
      MaterialPageRoute(
        builder: (context) => MenuScreen(
          user: widget.user,
          selectedTables: reservation.tableNumbers.map((e) => '$e').toList(),
          isPreOrderMode: true,
          reservationContext: ReservationContext(
            customerName: reservation.customerName,
            customerPhone: reservation.customerPhone,
            reservationDate: reservation.reservationDate,
            reservationTime: reservation.reservationTime,
            tableNumbers: reservation.tableNumbers,
            tableLabels: reservation.tableNumbers.map((e) => '$e').toList(),
            numberOfGuests: reservation.numberOfGuests,
            notes: reservation.notes,
          ),
          initialPreOrderItems: reservation.preOrderItems,
        ),
      ),
    );

    if (selectedItems == null) {
      return;
    }

    await DatabaseService.updateReservationPreOrderItems(
      reservation.id,
      selectedItems,
    );

    if (!mounted) {
      return;
    }

    setState(() {});
    unawaited(showSuccessToast(context, 'მენიუ განახლდა'));
  }

  Future<void> _editReservationDetails(Reservation reservation) async {
    final initialTime = HomeReservationsHelper.parseReservationTime(
      reservation.reservationTime,
    );

    final result = await _showReservationSheet(
      title: 'რეზერვაციის შეცვლა',
      confirmLabel: 'შენახვა',
      initialName: reservation.customerName,
      initialPhone: reservation.customerPhone,
      initialNotes: reservation.notes,
      initialDate: reservation.reservationDate,
      initialTime: initialTime,
      initialGuests: reservation.numberOfGuests,
    );

    if (result == null) {
      return;
    }

    final selectedDate = result['date'] as DateTime?;
    final selectedTime = result['time'] as TimeOfDay?;
    if (selectedDate == null || selectedTime == null) {
      return;
    }

    final timeString =
        '${selectedTime.hour.toString().padLeft(2, '0')}:'
        '${selectedTime.minute.toString().padLeft(2, '0')}';

    reservation.customerName = (result['customerName'] as String? ?? '').trim();
    reservation.customerPhone = (result['customerPhone'] as String? ?? '')
        .trim();
    final notes = (result['notes'] as String?)?.trim();
    reservation.notes = notes != null && notes.isNotEmpty ? notes : null;
    reservation.reservationDate = selectedDate;
    reservation.reservationTime = timeString;
    reservation.numberOfGuests = HomeReservationsHelper.extractGuestCount(
      result,
    );

    await reservation.save();

    if (!mounted) {
      return;
    }

    setState(() {});
    unawaited(showSuccessToast(context, 'რეზერვაცია განახლდა'));
  }

  Future<void> _assignReservationToTable(Reservation reservation) async {
    if (!widget.user.canManageReservationsOnHome) {
      unawaited(
        showPosToast(
          context: context,
          message:
              'სუფრაზე გადაყვანა მხოლოდ მენეჯერს ან ზედამხედველს შეუძლია.',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    final today = DatabaseService.getCurrentDate();
    if (!HomeReservationsHelper.isSameDate(
      reservation.reservationDate,
      today,
    )) {
      unawaited(
        showPosToast(
          context: context,
          message: 'სუფრაზე გადაყვანა შესაძლებელია მხოლოდ რეზერვაციის დღეს.',
          style: PosToastStyle.info,
        ),
      );
      return;
    }

    final selected = await HomeReservationTableAssignmentDialog.showForReservation(
      context: context,
      reservation: reservation,
      primaryColor: _primaryColor,
      secondaryColor: _secondaryColor,
      textPrimary: _textPrimary,
    );
    if (selected == null || selected.isEmpty) {
      return;
    }

    try {
      await DatabaseService.updateReservationTables(reservation.id, selected);
      final orderId = await DatabaseService.activateReservation(
        reservationId: reservation.id,
        activatedBy: widget.user.username,
      );

      if (!mounted) {
        return;
      }

      await _refreshTables();

      if (orderId == null) {
        await DatabaseService.logError(
          title: 'Reservation activation returned null',
          error: StateError(
            "Activation returned null. Tables: ${reservation.tableNumbers.join(', ')}",
          ),
          stackTrace: StackTrace.current,
          context: 'assign_reservation_to_table',
          performedBy: widget.user.username,
          metadata: {
            'reservationId': reservation.id,
            'tables': reservation.tableNumbers,
          },
        );
        unawaited(
          showPosToast(
            context: context,
            message: 'რეზერვაციის გააქტიურება ვერ მოხერხდა.',
            style: PosToastStyle.error,
          ),
        );
        return;
      }

      unawaited(showSuccessToast(context, 'რეზერვაცია გადაყვანილია სუფრაზე'));
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      await DatabaseService.logError(
        title: 'Reservation table move failed',
        error: error,
        stackTrace: stackTrace,
        context: 'assign_reservation_to_table',
        performedBy: widget.user.username,
        metadata: {
          'reservationId': reservation.id,
          'tables': reservation.tableNumbers,
        },
      );
      unawaited(
        showPosToast(
          context: context,
          message: 'რეზერვაციის სუფრაზე გადაყვანა ვერ მოხერხდა.',
          style: PosToastStyle.error,
        ),
      );
    }
  }

  Widget _buildMenuButtonBar() {
    final hasSelection =
        _tableSelectionKey.currentState?.selectedTables.isNotEmpty ?? false;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: _primaryColor.withValues(alpha: 0.1)),
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: hasSelection ? _continueToMenu : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _primaryColor.withValues(alpha: 0.25),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(horizontal: 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: hasSelection ? 4 : 0,
              ),
              icon: const Icon(Icons.restaurant_menu, size: 24),
              label: const Text(
                'გადასვლა მენიუში',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar({
    required int activeIndex,
    required List<int?> badgeCounts,
  }) {
    final mobileWidth =
        MediaQuery.of(context).size.width * 0.85; // Standard drawer width
    final width = _isMobile
        ? (_isSidebarExpanded ? mobileWidth : 0.0)
        : (_isSidebarExpanded ? 248.0 : 88.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF1D4ED8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: _isMobile ? mobileWidth : (_isSidebarExpanded ? 248.0 : 88.0),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                if (_showSidebarLabels) _buildSidebarHeader(),
                if (_showSidebarLabels) const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _destinations.length,
                    itemBuilder: (context, index) {
                      final destination = _destinations[index];
                      return _buildSidebarItem(
                        destination: destination,
                        index: index,
                        isActive: activeIndex == index,
                        badgeValue: badgeCounts[index],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.dashboard_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'VYNIC POS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required _SidebarDestination destination,
    required int index,
    required bool isActive,
    int? badgeValue,
  }) {
    final iconColor = isActive ? Colors.white : const Color(0xFFE2E8F0);
    final textStyle = TextStyle(
      color: iconColor,
      fontSize: 12,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
    );

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.symmetric(
        horizontal: _isSidebarExpanded ? 14 : 0,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? Colors.white.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: _showSidebarLabels
          ? Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(destination.icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination.label,
                    style: textStyle,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
                if (badgeValue != null)
                  _buildSidebarBadge(badgeValue > 9 ? '9+' : '$badgeValue'),
              ],
            )
          : Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(destination.icon, color: iconColor, size: 18),
              ),
            ),
    );

    content = Tooltip(
      message: destination.label,
      waitDuration: const Duration(milliseconds: 350),
      child: content,
    );

    return Semantics(
      button: true,
      label: destination.label,
      selected: isActive,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (destination.key == 'adminPanel') {
            if (_isMobile) setState(() => _isSidebarExpanded = false);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AdminScreen(user: widget.user),
              ),
            ).then((_) => setState(() {}));
            return;
          }
          if (destination.key == 'logout') {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
            return;
          }
          setState(() {
            if (_activeDestinationIndex != index) {
              _activeDestinationIndex = index;
            }
            if (_isMobile) {
              _isSidebarExpanded = false;
            }
          });
        },
        child: content,
      ),
    );
  }

  Future<void> _activateReservationsIfNeeded() async {
    final currentDate = DatabaseService.getCurrentDate()
        .toIso8601String()
        .split('T')[0];

    // Only activate if we haven't already done so today
    if (_lastActivationDate != currentDate) {
      await DatabaseService.activateTodaysReservations();
      _lastActivationDate = currentDate;
    }
  }

  void _updateButtonState() {
    setState(() {
      final state = _tableSelectionKey.currentState;
      _currentFloor = state?.currentFloor ?? 1;
    });
  }

  void _handleReservedTableTap(TableModel table) async {
    if (table.activeOrderId != null) {
      _openOrderDetail(table.activeOrderId!);
      return;
    }

    final reservationId = table.reservationId;
    if (reservationId == null) {
      return;
    }

    final orderId = await DatabaseService.activateReservation(
      reservationId: reservationId,
      activatedBy: widget.user.username,
    );

    if (!mounted) {
      return;
    }

    if (orderId == null) {
      // Check if reservation actually exists to heal ghost tables
      final resExists =
          DatabaseService.getReservation(reservationId) != null ||
          DatabaseService.getAllReservations().any(
            (r) => r.id == reservationId,
          );
      if (!resExists) {
        table.reservationId = null;
        table.isReserved = false;
        await table.save();
      }

      await _refreshTables();
      unawaited(
        showPosToast(
          context: context,
          message: 'შეკვეთის გახსნა ვერ მოხერხდა.',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    _openOrderDetail(orderId);
  }

  void _openOrderDetail(int orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OrderDetailScreen(user: widget.user, orderId: orderId),
      ),
    ).then((result) {
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        _tableSelectionKey.currentState?.clearSelection();
        await _refreshTables();
        if (result is Map && result['status'] == 'closed') {
          final message = result['message'] as String?;
          if (message != null && message.isNotEmpty) {
            unawaited(
              showPosToast(
                context: context,
                message: message,
                style: PosToastStyle.success,
              ),
            );
          }
        }
      });
    });
  }

  Future<void> _refreshTables() async {
    // Force reload tables from database
    await _tableSelectionKey.currentState?.refreshTables();
    if (!mounted) {
      return;
    }
    setState(() {}); // Trigger rebuild
  }

  Future<Map<String, dynamic>?> _showReservationSheet({
    String title = 'New Reservation',
    String confirmLabel = 'Create Reservation',
    String? initialName,
    String? initialPhone,
    String? initialNotes,
    DateTime? initialDate,
    TimeOfDay? initialTime,
    int? initialGuests,
  }) {
    return showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierLabel: title,
      barrierColor: Colors.black.withOpacity(0.85),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final mediaQuery = MediaQuery.of(dialogContext);
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: mediaQuery.size.width * 0.9,
                  maxHeight: mediaQuery.size.height * 0.95,
                ),
                child: ReservationCreationSheet(
                  onCancel: () => Navigator.of(dialogContext).pop(),
                  title: title,
                  confirmLabel: confirmLabel,
                  initialName: initialName,
                  initialPhone: initialPhone,
                  initialNotes: initialNotes,
                  initialDate: initialDate,
                  initialTime: initialTime,
                  initialGuests: initialGuests,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _switchFloor(int floor) {
    _tableSelectionKey.currentState?.switchFloor(floor);
    setState(() {
      _currentFloor = floor;
    });
  }

  void _continueToMenu() {
    final state = _tableSelectionKey.currentState;
    if (state != null && state.selectedTables.isNotEmpty) {
      if (state.hasMixedFloorSelection) {
        unawaited(
          showErrorToast(
            context,
            'ერთ შეკვეთაში შერეული სართულების მაგიდები ვერ გამოიყენება.',
          ),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MenuScreen(
            user: widget.user,
            selectedTables: state.selectedTables,
          ),
        ),
      ).then((_) async {
        // Refresh tables and clear selection when coming back
        await _refreshTables();
        _tableSelectionKey.currentState?.clearSelection();
      });
    }
  }
}
