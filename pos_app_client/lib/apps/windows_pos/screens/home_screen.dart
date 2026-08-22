import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_context.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import 'package:vynic/core/services/sync/pos_live_refresh.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';
import 'package:vynic/core/services/sync/connection_status_service.dart';
import 'package:vynic/core/services/notifications/app_notification_history_store.dart';
import 'package:vynic/core/services/pos/pos_change_highlight_service.dart';
import 'package:vynic/core/services/pos/pos_display_settings_controller.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/auth/session_lock.dart';
import 'package:vynic/core/widgets/notification_history_panel.dart';
import 'package:vynic/apps/windows_pos/widgets/table_selection_widget.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_status_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_tables_dashboard_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_calculator_page.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservation_menu_preview.dart';
import 'package:vynic/core/utils/home_reservations_helper.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservation_table_assignment_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_take_away_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_x_report_helper.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_x_report_section.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_reservations_section.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<TableSelectionWidgetState> _tableSelectionKey = GlobalKey();
  int _currentFloor = 1;
  static String?
  _lastActivationDate; // Track when we last activated reservations
  static const Color _primaryColor = Color(0xFF1E3A8A);
  static const Color _secondaryColor = Color(0xFF2563EB);
  static const Color _textPrimary = Color(0xFF1F2937);
  static const Color _mutedText = Color(0xFF475569);

  int _activeDestinationIndex = 0;
  // Indices of feature pages that have been opened at least once — drives the
  // lazy IndexedStack so unopened sections are never built.
  final Set<int> _builtPages = <int>{};
  late final List<_SidebarDestination> _destinations;
  final FocusNode _shortcutFocusNode = FocusNode(debugLabel: 'home-shortcuts');
  String? _lastToastNotificationId;
  bool _notificationsPanelOpen = false;
  StreamSubscription<SyncEvent>? _syncEventsSub;
  Timer? _syncRefreshDebounce;
  Timer? _syncRefreshFollowUp;
  Timer? _syncRefreshFinalFollowUp;

  /// The staff member currently operating the POS. Quick-switch flips
  /// [PosSession]; everything in this screen reads this getter so a switch
  /// re-stamps actions and re-flows to child screens without a re-login.
  User get _user => PosSession.user ?? widget.user;

  void _onLiveDataChanged() {
    if (!mounted) return;
    _scheduleLiveRefresh();
  }

  /// Locks the terminal full-screen until a PIN is entered (manual, from the
  /// staff role button). Resume/switch handling lives in [SessionLock].
  void _lockTerminal() => SessionLock.lock();

  /// Fired by [SessionLock] when an unlock switched to a DIFFERENT user: reset
  /// to the landing tab (Tables) and drop cached pages so the new staff
  /// starts fresh.
  void _onSwitchResetToLanding() {
    if (!mounted) return;
    setState(() {
      _builtPages.clear();
      final tablesIndex = _destinations.indexWhere((d) => d.key == 'menu');
      _activeDestinationIndex = tablesIndex >= 0 ? tablesIndex : 0;
    });
  }

  @override
  void initState() {
    super.initState();
    PosSession.start(widget.user);
    // Arm the idle auto-lock and react to staff switches that happen from the
    // lock screen (idle or manual).
    SessionLock.arm();
    SessionLock.resetToLanding.addListener(_onSwitchResetToLanding);
    // Activate today's confirmed reservations only if we haven't done it today
    _activateReservationsIfNeeded();
    _destinations = _createDestinations();
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
    ConnectionStatusService.initialize();
  }

  @override
  void dispose() {
    PosLiveRefresh.generation.removeListener(_onLiveDataChanged);
    AppNotificationHistoryStore.instance.entries.removeListener(
      _onNotificationEntriesChanged,
    );
    MonitoringSocketService.updateCounter.removeListener(_onRemoteUpdateSignal);
    SessionLock.resetToLanding.removeListener(_onSwitchResetToLanding);
    _syncEventsSub?.cancel();
    _syncRefreshDebounce?.cancel();
    _syncRefreshFollowUp?.cancel();
    _syncRefreshFinalFollowUp?.cancel();
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

    // Switch to the reservations tab so the new booking is visible.
    if (reservationIndex >= 0) {
      setState(() => _activeDestinationIndex = reservationIndex);
    }
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
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
      // Tables is the landing destination (index 0) — UI Phase 3 retires the
      // decorative HomeLandingDashboard route (docs/UI_PLAN.md §9 Phase 3):
      // waiters/managers land directly on the operational floor plan instead
      // of a dashboard they had to click through first.
      _SidebarDestination(
        key: 'menu',
        icon: Icons.table_restaurant_outlined,
        label: 'მაგიდები',
        builder: (context) => HomeTablesDashboardSection(
          textPrimary: _textPrimary,
          mutedText: _mutedText,
          tableSelectionKey: _tableSelectionKey,
          onSelectionChanged: _updateButtonState,
          onTableTap: _handleReservedTableTap,
          onContinueToMenu: _continueToMenu,
          currentFloor: _currentFloor,
          onSwitchFloor: _switchFloor,
          onOpenReservations: () => _selectDestination('newReservation'),
          displaySettings: PosDisplaySettingsController.settings.value,
        ),
      ),
      _SidebarDestination(
        key: 'calculate',
        icon: Icons.functions_outlined,
        label: 'დათვლა',
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
    ];

    if (_user.canAccessXReport) {
      destinations.add(
        _SidebarDestination(
          key: 'xReport',
          icon: Icons.assessment_outlined,
          label: 'X',
          builder: (context) => _buildXReportPage(),
        ),
      );
    }

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
    final openedTablesAmount = _user.isAdmin
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
      closedTables: HomeXReportHelper.buildClosedTables(todaysSales),
      soldItems: HomeXReportHelper.buildSoldItems(todaysSales),
      onPrintReport: () => unawaited(HomeXReportHelper.printReport(context)),
      primaryColor: _primaryColor,
      secondaryColor: _secondaryColor,
      textPrimary: _textPrimary,
      mutedText: _mutedText,
    );
  }

  Widget _buildCalculatorPage() {
    return HomeCalculatorPage(
      user: _user,
      primaryColor: _primaryColor,
      secondaryColor: _secondaryColor,
      textPrimary: _textPrimary,
      mutedText: _mutedText,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PosDisplaySettings>(
      valueListenable: PosDisplaySettingsController.settings,
      builder: (context, displaySettings, _) {
        return _buildWithDisplaySettings(context, displaySettings);
      },
    );
  }

  Widget _buildWithDisplaySettings(
    BuildContext context,
    PosDisplaySettings displaySettings,
  ) {
    final activeIndex = _activeDestinationIndex;
    final activeDestinationKey = _destinations[activeIndex].key;
    final currentDate = DatabaseService.getCurrentDate();
    final takeAwayCount = _countActiveTakeAways(currentDate);

    // Lazily build feature pages: only pages the user has actually opened are
    // constructed (and then kept alive by IndexedStack to preserve their
    // state). This avoids building every section — calculator, takeaways,
    // x-report, etc. — up front on each home rebuild. Each page is wrapped in a
    // RepaintBoundary so a repaint in one doesn't ripple into the others.
    _builtPages.add(activeIndex);
    final pages = [
      for (var i = 0; i < _destinations.length; i++)
        KeyedSubtree(
          key: ValueKey(_destinations[i].key),
          child: _builtPages.contains(i)
              ? RepaintBoundary(child: _destinations[i].builder(context))
              : const SizedBox.shrink(),
        ),
    ];

    final scaffold = Scaffold(
      backgroundColor: VynicColors.background,
      appBar: null,
      body: ValueListenableBuilder<int>(
        valueListenable: AppNotificationHistoryStore.instance.unreadCount,
        builder: (context, unread, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final layoutClass = displaySettings.layoutClassForWidth(
                constraints.maxWidth,
              );
              final density = displaySettings.effectiveDensityForWidth(
                constraints.maxWidth,
              );
              final narrow = layoutClass.isXs;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      _HomeUtilityBar(
                        businessDate: currentDate,
                        activeLabel: _destinations[activeIndex].label,
                        username: _user.username,
                        roleLabel: _user.roleLabelKa,
                        languageCode: DatabaseService.getDefaultLanguage()
                            .toUpperCase(),
                        unreadCount: unread,
                        density: density,
                        layoutClass: layoutClass,
                        onNotificationTap: _toggleNotificationsPanel,
                        onLockTap: _lockTerminal,
                        onLanguageTap: _user.canAccessManagementCenter
                            ? _openAdminPanel
                            : null,
                        fullscreenPosMode: displaySettings.fullscreenPosMode,
                      ),
                      _HomeNavigationTabs(
                        destinations: _destinations,
                        activeKey: activeDestinationKey,
                        takeAwayCount: takeAwayCount,
                        compact: density == PosUiDensity.compact,
                        narrow: narrow,
                        onDestinationSelected: _selectDestination,
                        onOpenAdminPanel: _user.canAccessManagementCenter
                            ? _openAdminPanel
                            : null,
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: VynicColors.background,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              constraints.maxWidth < 1180 ? 10 : 16,
                              0,
                              constraints.maxWidth < 1180 ? 10 : 16,
                              0,
                            ),
                            child: IndexedStack(
                              index: activeIndex,
                              children: pages,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  ..._notificationOverlayWidgets(context),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: null,
    );

    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      child: scaffold,
    );
  }

  void _selectDestination(String key) {
    final index = _destinations.indexWhere(
      (destination) => destination.key == key,
    );
    if (index < 0 || index == _activeDestinationIndex) return;
    setState(() {
      _activeDestinationIndex = index;
    });
  }

  void _openAdminPanel() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AdminScreen(user: _user)),
    ).then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Widget _buildTodayTakeAwayPage() {
    final today = DatabaseService.getCurrentDate();
    final takeAwayReservations = DatabaseService.getTakeAwayReservationsForDate(
      today,
    );
    return HomeTakeAwaySection(
      user: _user,
      takeAwayReservations: takeAwayReservations,
      onRefreshRequested: _refreshTables,
      primaryColor: _primaryColor,
      secondaryColor: _secondaryColor,
      textPrimary: _textPrimary,
      mutedText: _mutedText,
    );
  }

  Widget _buildReservationsDashboard() {
    final canManageReservations = _user.canManageReservationsOnHome;

    final reservations = HomeReservationsHelper.getAdminPanelReservations()
        .where(
          (reservation) => HomeReservationsHelper.normalizeStatus(
            reservation.status,
          ).startsWith('confirmed'),
        )
        .toList();

    return SizedBox.expand(
      child: HomeReservationsSection(
        user: _user,
        reservations: reservations,
        onRefreshRequested: _refreshTables,
        canAssignTable: canManageReservations,
        onEditReservation: canManageReservations
            ? _editReservationDetails
            : null,
        onViewPreOrder: (reservation) async => HomeReservationMenuPreview.show(
          context: context,
          reservation: reservation,
          primaryColor: _primaryColor,
          textPrimary: _textPrimary,
          mutedText: _mutedText,
        ),
        onManagePreOrder: canManageReservations ? _editReservationMenu : null,
        onSendKitchenCheck: _user.canSendReservationKitchenCheckOnHome
            ? _sendReservationKitchenCheck
            : null,
        onAssignTable: canManageReservations ? _assignReservationToTable : null,
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

    final reservationTables = ReservationTableAvailability.tableRefsOf(
      reservation,
    );
    final tableLabel = reservationTables.isNotEmpty
        ? reservationTables.map((ref) => ref.tableNumber).join(', ')
        : null;
    final orderLabel = HomeReservationsHelper.buildKitchenOrderLabel(
      reservation,
    );
    final kitchenTime = HomeReservationsHelper.buildKitchenTime(reservation);

    PrinterService.printKitchenCheckInBackground(
      items: kitchenItems,
      tableNumber: tableLabel,
      orderNumber: orderLabel,
      waiterName: _user.username,
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
          user: _user,
          selectedTables: ReservationTableAvailability.tableRefsOf(
            reservation,
          ).map((ref) => ref.tableNumber).toList(),
          isPreOrderMode: true,
          reservationContext: ReservationContext(
            customerName: reservation.customerName,
            customerPhone: reservation.customerPhone,
            reservationDate: reservation.reservationDate,
            reservationTime: reservation.reservationTime,
            tableLabels: ReservationTableAvailability.tableRefsOf(
              reservation,
            ).map((ref) => ref.tableNumber).toList(),
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
    if (!_user.canManageReservationsOnHome) {
      unawaited(
        showPosToast(
          context: context,
          message: 'სუფრაზე გადაყვანა მხოლოდ მენეჯერს ან ზედამხედველს შეუძლია.',
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

    final selected =
        await HomeReservationTableAssignmentDialog.showForReservation(
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
      await DatabaseService.updateReservationTables(
        reservation.id,
        const [],
        tableRefs: selected,
      );
      final result = await DatabaseService.activateReservation(
        reservationId: reservation.id,
        activatedBy: _user.username,
      );

      if (!mounted) {
        return;
      }

      await _refreshTables();

      if (!result.isSuccess) {
        final reason = result.failureReason ?? 'Unknown reason';
        await DatabaseService.logError(
          title: 'Reservation activation failed',
          error: StateError(reason),
          stackTrace: StackTrace.current,
          context: 'assign_reservation_to_table',
          performedBy: _user.username,
          metadata: {
            'reservationId': reservation.id,
            'tables': selected.map((ref) => ref.encode()).toList(),
            'reason': reason,
          },
        );
        unawaited(
          showPosToast(
            context: context,
            message: 'რეზერვაციის გააქტიურება ვერ მოხერხდა: $reason',
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
        performedBy: _user.username,
        metadata: {
          'reservationId': reservation.id,
          'tables': selected.map((ref) => ref.encode()).toList(),
        },
      );
      unawaited(
        showPosToast(
          context: context,
          message: 'რეზერვაციის სუფრაზე გადაყვანა ვერ მოხერხდა: $error',
          style: PosToastStyle.error,
        ),
      );
    }
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

    final ReservationActivationResult result;
    try {
      result = await DatabaseService.activateReservation(
        reservationId: reservationId,
        activatedBy: _user.username,
      );
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      await DatabaseService.logError(
        title: 'Reserved table activation failed',
        error: error,
        stackTrace: stackTrace,
        context: 'reserved_table_tap',
        performedBy: _user.username,
        metadata: {'reservationId': reservationId},
      );
      await _refreshTables();
      unawaited(
        showPosToast(
          context: context,
          message: 'შეკვეთის გახსნა ვერ მოხერხდა: $error',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    if (!result.isSuccess) {
      final reason = result.failureReason ?? 'Unknown reason';
      await DatabaseService.logError(
        title: 'Reserved table activation failed',
        error: StateError(reason),
        stackTrace: StackTrace.current,
        context: 'reserved_table_tap',
        performedBy: _user.username,
        metadata: {'reservationId': reservationId, 'reason': reason},
      );

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

      if (!mounted) {
        return;
      }

      await _refreshTables();
      unawaited(
        showPosToast(
          context: context,
          message: 'შეკვეთის გახსნა ვერ მოხერხდა: $reason',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    _openOrderDetail(result.orderId!);
  }

  void _openOrderDetail(int orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailScreen(user: _user, orderId: orderId),
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
            user: _user,
            selectedTables: state.selectedTables,
            // The names above are whatever the admin typed; these carry the
            // identity the order is actually written against.
            tableNumbers: state.selectedTableNumbers,
            tableFloor: state.selectedFloor,
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

class _HomeNavigationTabs extends StatelessWidget {
  const _HomeNavigationTabs({
    required this.destinations,
    required this.activeKey,
    required this.takeAwayCount,
    required this.compact,
    required this.narrow,
    required this.onDestinationSelected,
    required this.onOpenAdminPanel,
  });

  final List<_SidebarDestination> destinations;
  final String activeKey;
  final int takeAwayCount;
  final bool compact;
  final bool narrow;
  final ValueChanged<String> onDestinationSelected;
  final VoidCallback? onOpenAdminPanel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 56 : 64,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: VynicColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final destination in destinations) ...[
                    _HomeNavigationTab(
                      label: destination.label,
                      active: destination.key == activeKey,
                      badgeCount:
                          destination.key == 'todaysTakeaways' &&
                              takeAwayCount > 0
                          ? takeAwayCount
                          : null,
                      compact: compact,
                      onTap: () => onDestinationSelected(destination.key),
                    ),
                    SizedBox(width: compact ? 6 : 10),
                  ],
                ],
              ),
            ),
          ),
          if (onOpenAdminPanel != null) ...[
            SizedBox(width: narrow ? 8 : 12),
            _TopAdminButton(
              compact: compact,
              narrow: narrow,
              onTap: onOpenAdminPanel!,
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeNavigationTab extends StatelessWidget {
  const _HomeNavigationTab({
    required this.label,
    required this.active,
    required this.compact,
    required this.onTap,
    this.badgeCount,
  });

  final String label;
  final bool active;
  final bool compact;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: active ? null : onTap,
      borderRadius: VynicRadius.smAll,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: compact ? 38 : 42,
        padding: EdgeInsets.symmetric(horizontal: compact ? 13 : 16),
        decoration: BoxDecoration(
          color: active ? VynicColors.accentSoft : Colors.transparent,
          borderRadius: VynicRadius.smAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active
                    ? VynicFloorTokens.accentText
                    : VynicFloorTokens.textMuted,
                fontSize: compact ? 13 : 13.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if ((badgeCount ?? 0) > 0) ...[
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 17),
                height: 17,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? VynicFloorTokens.panel
                      : VynicColors.dangerSoft,
                  // A fixed 9px radius, not a pill: at 17px tall a pill
                  // rounds the sides into an oval, which is what read as
                  // "not rounded right".
                  borderRadius: BorderRadius.circular(
                    VynicFloorTokens.badgeRadius,
                  ),
                ),
                child: Text(
                  badgeCount! > 9 ? '9+' : '$badgeCount',
                  style: const TextStyle(
                    color: VynicFloorTokens.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

class _TopAdminButton extends StatelessWidget {
  const _TopAdminButton({
    required this.compact,
    required this.narrow,
    required this.onTap,
  });

  final bool compact;
  final bool narrow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: VynicFloorTokens.accentText,
        foregroundColor: VynicFloorTokens.panel,
        minimumSize: Size(narrow ? 40 : 0, compact ? 32 : 34),
        padding: EdgeInsets.symmetric(horizontal: narrow ? 0 : 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: narrow
          ? const Icon(Icons.settings_outlined, size: 17)
          : const Text(
              'პარამეტრები',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
    );
  }
}

class _HomeUtilityBar extends StatelessWidget {
  const _HomeUtilityBar({
    required this.businessDate,
    required this.activeLabel,
    required this.username,
    required this.roleLabel,
    required this.languageCode,
    required this.unreadCount,
    required this.density,
    required this.layoutClass,
    required this.onNotificationTap,
    required this.onLockTap,
    required this.onLanguageTap,
    required this.fullscreenPosMode,
  });

  final DateTime businessDate;
  final String activeLabel;
  final String username;
  final String roleLabel;
  final String languageCode;
  final int unreadCount;
  final PosUiDensity density;
  final PosLayoutClass layoutClass;
  final VoidCallback onNotificationTap;
  final VoidCallback onLockTap;
  final VoidCallback? onLanguageTap;
  final bool fullscreenPosMode;

  @override
  Widget build(BuildContext context) {
    final compact = density == PosUiDensity.compact;
    final narrow = layoutClass.isXs;
    final hideSecondary = layoutClass.isCompactWidth || fullscreenPosMode;
    return Container(
      height: compact ? 58 : 64,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: VynicColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: VynicColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Text(
              'V',
              style: TextStyle(
                color: VynicColors.accentHover,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (!narrow) ...[
            const Text(
              'Vynic POS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: VynicColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 24, color: VynicColors.border),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Text(
              activeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: VynicColors.neutral,
                fontSize: narrow ? 13 : 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: narrow ? 8 : 16),
          if (!fullscreenPosMode && !hideSecondary) ...[
            _BusinessDayChip(label: _formatBusinessDate(businessDate)),
            const SizedBox(width: 8),
          ],
          _ConnectionChip(compact: narrow),
          SizedBox(width: narrow ? 6 : 10),
          _ClockChip(compact: narrow),
          SizedBox(width: narrow ? 6 : 10),
          _LanguageButton(code: languageCode, onTap: onLanguageTap),
          SizedBox(width: narrow ? 6 : 8),
          _NotificationUtilityButton(
            unreadCount: unreadCount,
            onTap: onNotificationTap,
          ),
          SizedBox(width: narrow ? 6 : 10),
          _EmployeeChip(
            username: username,
            roleLabel: hideSecondary ? '' : roleLabel,
            compact: narrow,
            onTap: onLockTap,
          ),
        ],
      ),
    );
  }

  static String _formatBusinessDate(DateTime date) {
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
    return '${date.day} ${months[date.month - 1]}';
  }
}

class _ClockChip extends StatelessWidget {
  const _ClockChip({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Text(
      label,
      style: TextStyle(
        color: VynicColors.textPrimary,
        fontSize: compact ? 12 : 14,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _BusinessDayChip extends StatelessWidget {
  const _BusinessDayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: VynicColors.warningSoft,
        borderRadius: VynicRadius.smAll,
        border: Border.all(color: VynicColors.warningBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFD7A72C),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VynicColors.warningText,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackendConnectionState>(
      valueListenable: ConnectionStatusService.backendState,
      builder: (context, state, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: ConnectionStatusService.hasPendingLocalChanges,
          builder: (context, pending, _) {
            final presentation = _connectionPresentation(state, pending);
            final token = VynicStatusTokens.ofTone(presentation.tone);
            return Container(
              height: 34,
              padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 10),
              decoration: BoxDecoration(
                color: token.background,
                borderRadius: VynicRadius.smAll,
                border: Border.all(color: token.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(presentation.icon, size: 16, color: token.text),
                  if (!compact) ...[
                    const SizedBox(width: 7),
                    Text(
                      presentation.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: token.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  ({String label, IconData icon, VynicStatusTone tone}) _connectionPresentation(
    BackendConnectionState state,
    bool pending,
  ) {
    if (pending && state != BackendConnectionState.offline) {
      return (
        label: 'რიგშია',
        icon: Icons.cloud_upload_outlined,
        tone: VynicStatusTone.warning,
      );
    }
    switch (state) {
      case BackendConnectionState.syncing:
        return (
          label: 'სინქი',
          icon: Icons.sync_rounded,
          tone: VynicStatusTone.info,
        );
      case BackendConnectionState.connected:
        return (
          label: 'სინქრონულია',
          icon: Icons.cloud_done_outlined,
          tone: VynicStatusTone.success,
        );
      case BackendConnectionState.offline:
        return (
          label: 'ოფლაინი',
          icon: Icons.cloud_off_outlined,
          tone: VynicStatusTone.warning,
        );
      case BackendConnectionState.idle:
        return (
          label: 'ლოკალური',
          icon: Icons.storage_outlined,
          tone: VynicStatusTone.neutral,
        );
    }
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.code, required this.onTap});

  final String code;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'ენის პარამეტრები',
      child: InkWell(
        onTap: onTap,
        borderRadius: VynicRadius.smAll,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: VynicRadius.smAll,
            border: Border.all(color: VynicColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.language_outlined,
                size: 16,
                color: VynicColors.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                code,
                style: const TextStyle(
                  color: VynicColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationUtilityButton extends StatelessWidget {
  const _NotificationUtilityButton({
    required this.unreadCount,
    required this.onTap,
  });

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'შეტყობინებები',
      child: InkWell(
        onTap: onTap,
        borderRadius: VynicRadius.smAll,
        child: Container(
          width: 38,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: VynicRadius.smAll,
            border: Border.all(color: VynicColors.border),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                size: 19,
                color: VynicColors.textPrimary,
              ),
              if (unreadCount > 0)
                Positioned(
                  right: -8,
                  top: -8,
                  child: _MiniBadge(count: unreadCount),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeChip extends StatelessWidget {
  const _EmployeeChip({
    required this.username,
    required this.roleLabel,
    required this.compact,
    required this.onTap,
  });

  final String username;
  final String roleLabel;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initials = username.trim().isEmpty
        ? 'POS'
        : username
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((part) => part.characters.first.toUpperCase())
              .join();
    return Tooltip(
      message: 'ტერმინალის ჩაკეტვა / თანამშრომლის შეცვლა',
      child: InkWell(
        onTap: onTap,
        borderRadius: VynicRadius.smAll,
        child: Container(
          height: 38,
          padding: EdgeInsets.only(left: 4, right: compact ? 4 : 10),
          decoration: BoxDecoration(
            color: VynicColors.cardSoft,
            borderRadius: VynicRadius.smAll,
            border: Border.all(color: VynicColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: VynicColors.accentSoft,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  initials,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    color: VynicColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VynicColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (roleLabel.isNotEmpty)
                        Text(
                          roleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VynicColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: VynicColors.danger,
        shape: BoxShape.circle,
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
