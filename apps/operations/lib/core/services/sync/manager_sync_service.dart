import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vynic/core/services/sync/connection_status_service.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/sync/audit_sync_state.dart';
import 'package:vynic/core/services/sync/staff_credential_sync_state.dart';
import 'package:vynic/core/services/sync/sale_ledger_sync_state.dart';
import 'package:vynic/core/services/sync/manager_sales_history_builder.dart';
import 'package:vynic/core/services/sync/sync_timing.dart';
import 'package:vynic/core/services/sync/pos_callback_config.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/services/pos/pos_change_highlight_service.dart';
import 'package:vynic/core/utils/payment_utils.dart';
import 'package:vynic/core/contracts/table_identity.dart' as table_identity;

/// Serializes a manager-data payload to JSON. Runs in a background isolate via
/// [compute] so the (potentially large) encode never blocks the UI thread —
/// this is what keeps the POS responsive (no PIN-typing or animation jank)
/// while a sync is in flight.
String _encodeManagerPayload(Map<String, dynamic> payload) =>
    json.encode(payload);

class ManagerSyncService {
  static String get serverUrl => ApiConfig.baseUrl;

  static bool _startupSyncScheduled = false;

  /// Last synced line snapshot per order — diff drives manager notifications + highlights.
  static final Map<int, List<OrderItem>> _lastOrderItemsByOrderId =
      <int, List<OrderItem>>{};
  static final Map<int, ({bool includeServiceFee, double totalAmount})>
  _lastOrderBillingByOrderId = {};
  static bool _orderFingerprintsBootstrapped = false;

  /// Occupancy snapshot per table — drives `touchedTableHints` (walk-in / close).
  static final Map<String, bool> _lastTableOccupiedByKey = <String, bool>{};
  static bool _tableFingerprintsBootstrapped = false;

  /// Explicit hints from [SyncHub] reserve/free (reliable vs fingerprint diff).
  static final List<Map<String, dynamic>> _pendingTableHints =
      <Map<String, dynamic>>[];

  /// Explicit hints for billing changes (service fee toggle) — fingerprint diff can miss these.
  static final List<Map<String, dynamic>> _pendingOrderHints =
      <Map<String, dynamic>>[];

  /// Reservation changes from [SyncHub] — drives mobile realtime + notification.
  static final List<Map<String, dynamic>> _pendingReservationHints =
      <Map<String, dynamic>>[];

  static void Function(SyncEvent event)? _previousOnLocalChange;
  static bool _hooksRegistered = false;
  static bool _realtimeOnly = false;

  /// Periodic retry that flushes pending local changes to the backend so a POS
  /// edit made while the server was unreachable reaches it on its own once it
  /// comes back — no manual "Retry Sync Now" needed.
  static Timer? _pendingFlushTimer;

  /// Guards the periodic flush against overlapping its own pushes.
  static bool _pendingFlushInFlight = false;

  static const Duration _pendingFlushInterval = Duration(seconds: 30);

  /// Monotonic reading of when the oldest currently-unpushed local change
  /// arrived, or null when everything local has been pushed.
  ///
  /// This is what makes the wait before a sync measurable. A POS edit does not
  /// push: it marks pending and the periodic flush picks it up, so the delay
  /// between the two is real time a manager is looking at stale data, and it
  /// belongs in the timing summary rather than being invisible.
  static int? _pendingSinceMicros;

  /// Records a local change as unpushed, and when it happened.
  static void _markPendingLocalChange() {
    _pendingSinceMicros ??= SyncTiming.nowMicros();
    ConnectionStatusService.markPendingLocalChange();
  }

  static void initialize() {
    if (_shuttingDown) return;
    ConnectionStatusService.initialize();

    // Always wire Hive changes to pending sync status.
    if (!_hooksRegistered) {
      _previousOnLocalChange = SyncHub.onLocalChange;
      SyncHub.onLocalChange = (SyncEvent event) {
        _previousOnLocalChange?.call(event);
        _onLocalHiveChange(event);
      };
      DatabaseService.registerAuditChangedCallback(_markPendingLocalChange);
      DatabaseService.registerUsersChangedCallback(_markPendingLocalChange);
      _hooksRegistered = true;
    }

    _bootstrapTableFingerprintsFromLocal();

    // Auto-flush retry loop. The POS has no monitoring socket (that runs on the
    // mobile app), so it can't react to the server returning — instead it polls:
    // whenever there are unpushed local changes, re-attempt the push until it
    // lands. A successful push clears the pending flag, so this is a no-op once
    // everything is in sync.
    _pendingFlushTimer ??= Timer.periodic(_pendingFlushInterval, (_) {
      if (_pendingFlushInFlight) return;
      if (!ConnectionStatusService.hasPendingLocalChanges.value) return;
      _pendingFlushInFlight = true;
      syncToManagerApp().whenComplete(() => _pendingFlushInFlight = false);
    });

    if (_startupSyncScheduled) return;
    _startupSyncScheduled = true;

    // Delay the initial sync by 3 seconds to ensure the local Hive DB
    // is fully loaded before we push data. This prevents an empty push
    // from overwriting reserved table state on the cloud.
    Timer(const Duration(seconds: 3), () {
      debugPrint(
        '[ManagerSync] Backend=${ApiConfig.baseUrl} '
        'ingest=${PosCallbackConfig.baseUrl ?? "not running"}',
      );
      syncToManagerApp();
    });
  }

  static void _onLocalHiveChange(SyncEvent event) {
    _markPendingLocalChange();

    if (event.type == SyncEventType.tables) {
      final payload = event.payload;
      final action = event.action;
      if (payload != null && (action == 'reserved' || action == 'freed')) {
        final tableNumber = payload['tableNumber']?.toString().trim() ?? '';
        final floor = payload['floor']?.toString().trim() ?? 'first';
        if (tableNumber.isNotEmpty) {
          final orderRaw = payload['orderId'];
          final orderId = orderRaw is int
              ? orderRaw
              : int.tryParse(orderRaw?.toString() ?? '');
          _enqueuePendingTableHint(
            tableNumber: tableNumber,
            floor: floor,
            changeType: action == 'freed' ? 'freed' : 'reserved',
            orderId: orderId,
          );
        }
      }
      syncRealtimeToManagerAppDebounced();
      return;
    }
    if (event.type == SyncEventType.orders && event.action == 'created') {
      final orderRaw = event.payload?['orderId'];
      final orderId = orderRaw is int
          ? orderRaw
          : int.tryParse(orderRaw?.toString() ?? '');
      if (orderId != null) {
        final order = DatabaseService.getOrder(orderId);
        if (order != null && !order.floor.toLowerCase().contains('takeaway')) {
          for (final rawNum in order.tableNumbers) {
            final tableNumber = _normalizeTableNumberForSync(
              rawNum.toString(),
              order.floor,
            );
            if (tableNumber == null || tableNumber.isEmpty) continue;
            _enqueuePendingTableHint(
              tableNumber: tableNumber,
              floor: order.floor,
              changeType: 'reserved',
              orderId: order.orderId,
            );
          }
        }
      }
    }
    if (event.type == SyncEventType.orders &&
        event.action == 'updated' &&
        event.payload?['serviceFeeChanged'] == true) {
      final orderRaw = event.payload?['orderId'];
      final orderId = orderRaw is int
          ? orderRaw
          : int.tryParse(orderRaw?.toString() ?? '');
      if (orderId != null) {
        final order = DatabaseService.getOrder(orderId);
        if (order != null && !order.floor.toLowerCase().contains('takeaway')) {
          _enqueuePendingOrderHint(
            posOrderId: orderId,
            tableLabel: _tableLabelForSyncOrder({
              'floor': order.floor,
              'tableNumbers': order.tableNumbers,
            }),
            floor: order.floor,
            changeSummary: order.includeServiceFee
                ? 'სერვისის საფასური ჩართულია'
                : 'სერვისის საფასური გამორთულია',
            changeKind: 'service_fee',
          );
          _syncServiceFeeToManagerDebounced();
          return;
        }
      }
    }
    if (event.type == SyncEventType.reservations) {
      _enqueuePendingReservationHint(event);
    }
    switch (event.type) {
      case SyncEventType.orders:
      case SyncEventType.reservations:
        syncRealtimeToManagerAppDebounced();
        break;
      case SyncEventType.menu:
      case SyncEventType.connection:
        break;
      default:
        break;
    }
  }

  static void _enqueuePendingReservationHint(SyncEvent event) {
    final reservationId = event.payload?['reservationId']?.toString().trim();
    if (reservationId == null || reservationId.isEmpty) return;
    final action = (event.action ?? 'updated').toString();

    String customerName = '';
    String reservationDate = '';
    String reservationTime = '';
    List<int> tableNumbers = const [];
    int? linkedOrderId;
    String notes = '';
    try {
      final reservation = DatabaseService.findReservationById(reservationId);
      customerName = reservation?.customerName.trim() ?? '';
      reservationDate = reservation?.reservationDate.toIso8601String() ?? '';
      reservationTime = reservation?.reservationTime.trim() ?? '';
      tableNumbers = List<int>.from(reservation?.tableNumbers ?? const []);
      linkedOrderId = reservation?.linkedOrderId;
      notes = reservation?.notes?.trim() ?? '';
    } catch (_) {
      customerName = '';
      reservationDate = '';
      reservationTime = '';
      tableNumbers = const [];
      linkedOrderId = null;
      notes = '';
    }

    final walkIn =
        customerName.toLowerCase() == 'walk-in' ||
        customerName.toLowerCase().contains('walk-in');

    // Collapse repeated hints for the same reservation — latest wins.
    _pendingReservationHints.removeWhere(
      (h) => h['reservationId'] == reservationId,
    );
    _pendingReservationHints.add({
      'reservationId': reservationId,
      'action': action,
      if (customerName.isNotEmpty) 'customerName': customerName,
      if (reservationDate.isNotEmpty) 'reservationDate': reservationDate,
      if (reservationTime.isNotEmpty) 'reservationTime': reservationTime,
      if (tableNumbers.isNotEmpty) 'tableNumbers': tableNumbers,
      if (linkedOrderId != null) 'linkedOrderId': linkedOrderId,
      if (notes.isNotEmpty) 'notes': notes,
      if (walkIn) 'walkIn': true,
      'occurredAt': DatabaseService.getCurrentDateTime().toIso8601String(),
    });
  }

  static List<Map<String, dynamic>> _drainReservationHints() {
    if (_pendingReservationHints.isEmpty) return const [];
    final drained = _pendingReservationHints
        .map((h) => Map<String, dynamic>.from(h))
        .toList();
    _pendingReservationHints.clear();
    return drained;
  }

  static void dispose() {
    _startupSyncScheduled = false;
    _pendingSinceMicros = null;
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
    _pendingFlushInFlight = false;
  }

  /// Marks that local POS data should be pushed on the next manual sync.
  static void syncToManagerAppDebounced() {
    _markPendingLocalChange();
  }

  static Future<bool> testBackendConnection({
    String? backendUrl,
    bool updateStatus = true,
  }) async {
    if (updateStatus) {
      ConnectionStatusService.markAttempt();
    }
    final targetUrl = backendUrl ?? serverUrl;
    try {
      final response = await http
          .get(Uri.parse('$targetUrl/sync/ping'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (updateStatus) {
          ConnectionStatusService.markConnectionTestSuccess();
        }
        return true;
      }
      if (updateStatus) {
        ConnectionStatusService.markFailure(
          'Backend test failed (${response.statusCode}): ${response.body}',
        );
      }
      return false;
    } catch (e) {
      if (updateStatus) {
        ConnectionStatusService.markFailure(e);
      }
      return false;
    }
  }

  /// Manual-first mode: local changes mark pending instead of auto-pushing.
  static void syncRealtimeToManagerAppDebounced() {
    _markPendingLocalChange();
  }

  /// Manual-first mode: service-fee changes mark pending instead of auto-pushing.
  static void _syncServiceFeeToManagerDebounced() {
    _markPendingLocalChange();
  }

  static Future<void> syncRealtimeToManagerApp() async {
    _realtimeOnly = true;
    try {
      await syncToManagerApp();
    } finally {
      _realtimeOnly = false;
    }
  }

  /// Guards against two pushes being in flight at once.
  ///
  /// The periodic flush had its own flag, but every other caller — login,
  /// the connection test, close-day, the backup flow — went straight in. Two
  /// overlapping pushes made the server delete and recreate the same order's
  /// lines twice over, which surfaced on the manager app as duplicated items.
  static Future<void>? _inFlight;
  static bool _shuttingDown = false;

  /// Stop this POS's mirror worker; pending durable work resumes next launch.
  static Future<void> shutdown() async {
    _shuttingDown = true;
    dispose();
    await _inFlight;
  }

  static Future<void> syncToManagerApp() {
    if (_shuttingDown) return Future<void>.value();
    final running = _inFlight;
    if (running != null) {
      // Coalesce: the push already running carries the same local state.
      return running;
    }
    final next = _syncToManagerApp();
    _inFlight = next;
    return next.whenComplete(() {
      if (identical(_inFlight, next)) _inFlight = null;
    });
  }

  /// Builds the Order portion of a POS snapshot without consulting
  /// Reservation storage. Takeaway guest and pickup metadata is Order-owned.
  @visibleForTesting
  static List<Map<String, dynamic>> buildOrdersSyncPayload({
    required Iterable<Order> orders,
    required DateTime businessDate,
  }) {
    return orders
        .where(
          (order) =>
              order.createdAt.year == businessDate.year &&
              order.createdAt.month == businessDate.month &&
              order.createdAt.day == businessDate.day,
        )
        .map((order) {
          final tableIds = _canonicalTableIdsForOrder(order);
          return <String, dynamic>{
            'posOrderId': order.orderId,
            'status': order.status,
            // Last local-edit time — lets the server resolve same-order
            // conflicts by last-write-wins against a queued mobile change.
            'updatedAt': (order.updatedAt ?? order.createdAt).toIso8601String(),
            'totalAmount': order.totalAmount,
            'paymentType': (order.paymentMethod ?? 'cash')
                .toString()
                .toLowerCase(),
            'waiterName': order.createdBy,
            'tableNumbers': order.tableNumbers
                .map((table) => table.toString())
                .toList(),
            if (tableIds != null) 'tableIds': tableIds,
            'floor': order.floor,
            'customerName': order.customerName,
            'customerPhone': order.customerPhone,
            'pickupTime': order.pickupTime,
            'includeServiceFee': order.includeServiceFee,
            'discountAmount': order.discountAmount,
            // Signed operator override of the bill total. Without it the
            // Cloud's totalAmount cannot be reconciled against its own item
            // lines, discount and service fee.
            'manualAdjustmentAmount': order.manualAdjustmentAmount,
            'serviceFeePercent': (order.customServiceFeePercentage ?? 10.0),
            'items': order.items
                .map(
                  (item) => {
                    'name': item.itemName,
                    'quantity': item.quantity,
                    'price': item.unitPrice,
                    if (item.menuItemId != null) 'menuItemId': item.menuItemId,
                    if (item.variantId != null) 'variantId': item.variantId,
                  },
                )
                .toList(),
          };
        })
        .toList();
  }

  static Future<void> _syncToManagerApp() async {
    // Measurement starts where the work does, carrying how long the oldest
    // unpushed change waited to get here.
    final timing = SyncTiming.begin(pendingSinceMicros: _pendingSinceMicros);
    try {
      // 1. Prepare Today's Orders (needed to enrich table occupancy)
      final allOrders = DatabaseService.getAllOrders();

      // 2. Prepare Today's Orders
      final businessDate = DatabaseService.getCurrentDate();
      final businessDateString =
          '${businessDate.year.toString().padLeft(4, '0')}-'
          '${businessDate.month.toString().padLeft(2, '0')}-'
          '${businessDate.day.toString().padLeft(2, '0')}';
      final allReservations = DatabaseService.getAllReservations();
      final todayOrders = buildOrdersSyncPayload(
        orders: allOrders,
        businessDate: businessDate,
      );
      timing.mark('orders');

      final tables = _buildTablesSyncPayload(allOrders, businessDate);
      final orderMaps = todayOrders
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final touchedOrderHints = _mergeTouchedOrderHints(
        _computeTouchedOrderHints(orderMaps),
        _drainPendingOrderHints(),
      );
      final touchedTableHints = _collectTableHintsForSync(
        tables.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
      final touchedReservationHints = _drainReservationHints();
      final reservedInPayload = tables.where(_isTableOccupiedRaw).length;
      timing.mark('tables');

      // Only sum bills on tables that are actually occupied right now.
      final openTablesPayable = tables
          .where(_isTableOccupiedRaw)
          .fold<double>(
            0,
            (sum, t) => sum + ((t['currentBill'] as num?)?.toDouble() ?? 0),
          );

      if (_realtimeOnly) {
        final payload = <String, dynamic>{
          'realtimeOnly': true,
          'tables': tables,
          'orders': todayOrders,
          if (touchedOrderHints.isNotEmpty)
            'touchedOrderHints': touchedOrderHints,
          if (touchedTableHints.isNotEmpty)
            'touchedTableHints': touchedTableHints,
          if (touchedReservationHints.isNotEmpty)
            'touchedReservationHints': touchedReservationHints,
          'syncedAt': DateTime.now().toIso8601String(),
          'businessDate': businessDateString,
          'dailySalesTotal': double.parse(
            DatabaseService.getDailySalesTotal().toStringAsFixed(2),
          ),
          'openTablesPayable': double.parse(
            openTablesPayable.toStringAsFixed(2),
          ),
          'settings': {
            'serviceFeePercent': DatabaseService.getServiceFeePercentage(),
            'serviceFeeEnabled': DatabaseService.isServiceFeeEnabledByDefault(),
          },
          if (PosCallbackConfig.baseUrl != null)
            'posCallbackUrl': PosCallbackConfig.baseUrl,
          if (PosCallbackConfig.connectionKey != null &&
              PosCallbackConfig.connectionKey!.isNotEmpty)
            'posConnectionKey': PosCallbackConfig.connectionKey,
        };
        debugPrint(
          '[ManagerSync] Realtime push: ${tables.length} tables '
          '($reservedInPayload reserved), ${todayOrders.length} orders, '
          'tableHints=${touchedTableHints.length}.',
        );
        timing.mark('payload');
        ConnectionStatusService.markAttempt();
        final body = await compute(_encodeManagerPayload, payload);
        timing.payloadBytes = body.length;
        timing.mark('encode');
        final response = await http.post(
          Uri.parse('$serverUrl/sync/manager-data'),
          headers: ApiConfig.posSyncHeaders,
          body: body,
        );
        timing.mark('http');
        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('[ManagerSync] Realtime OK (${response.statusCode})');
          _pendingSinceMicros = null;
          await ConnectionStatusService.markSuccess();
        } else {
          debugPrint(
            '[ManagerSync] Realtime failed (${response.statusCode}): ${response.body}',
          );
          ConnectionStatusService.markFailure(
            'Realtime sync failed (${response.statusCode}): ${response.body}',
          );
        }
        _runAuditSyncTimed(timing, 'POS/realtime');
        return;
      }

      // 2.1 Prepare Sales Summary from local closed-sales records.
      // This is the authoritative source for payment-method analytics.
      await SaleLedgerSyncState.ensureSaleIdentities();
      final todaysSales = DatabaseService.getSalesForDate(businessDateString);
      final paymentBreakdown = <String, double>{};
      final totalRevenue = DatabaseService.grossSalesTotalForDate(
        businessDateString,
      );
      int fiscalOrderCount = 0;
      for (final sale in todaysSales) {
        final isCancelled = sale['isCancelled'] == true;
        final restoredToOrder = sale['restoredToOrder'] == true;
        // A deposit taken today against an order that has not closed yet is
        // its own thing: cash in the drawer, not revenue and not an internal
        // closure. It used to fall into the `non-fiscal` bucket, which made
        // the manager app read deposits as internal closures.
        if (DatabaseService.saleIsAdvanceReceipt(sale)) {
          final amount = (sale['totalAmount'] as num?)?.toDouble() ?? 0.0;
          paymentBreakdown['advance-received'] =
              (paymentBreakdown['advance-received'] ?? 0) + amount;
          continue;
        }
        final totalAmount = DatabaseService.saleGrossOf(sale);
        if (!DatabaseService.saleCountsAsRevenue(sale)) {
          if (!isCancelled && !restoredToOrder && sale['isFiscal'] == false) {
            // Kept as a separately labelled operational figure. It is never
            // added to revenue, fiscal payment totals, or order count.
            paymentBreakdown['non-fiscal'] =
                (paymentBreakdown['non-fiscal'] ?? 0) + totalAmount;
          }
          continue;
        }
        fiscalOrderCount += 1;
        final breakdown = PaymentUtils.extractBreakdown(sale);
        breakdown.forEach((key, amount) {
          paymentBreakdown[key] = (paymentBreakdown[key] ?? 0) + amount;
        });
      }
      final roundedBreakdown = <String, double>{};
      paymentBreakdown.forEach((key, value) {
        roundedBreakdown[key] = double.parse(value.toStringAsFixed(2));
      });
      final cashRevenue = roundedBreakdown['cash'] ?? 0.0;
      final cardRevenue = roundedBreakdown.entries.fold<double>(
        0,
        (sum, entry) => entry.key.startsWith('card') ? sum + entry.value : sum,
      );
      final salesSummary = {
        'date': businessDateString,
        'totalRevenue': double.parse(totalRevenue.toStringAsFixed(2)),
        'orderCount': fiscalOrderCount,
        'cashRevenue': double.parse(cashRevenue.toStringAsFixed(2)),
        'cardRevenue': double.parse(cardRevenue.toStringAsFixed(2)),
        'paymentBreakdown': roundedBreakdown,
        'totalExpenses': double.parse(
          DatabaseService.getExpenseTotalForDate(
            businessDateString,
          ).toStringAsFixed(2),
        ),
        'profit': double.parse(
          (totalRevenue -
                  DatabaseService.getExpenseTotalForDate(businessDateString))
              .toStringAsFixed(2),
        ),
      };

      // 2.2 Prepare all-time sales summary from local sales history.
      final allSales = DatabaseService.getAllSales();
      final saleLedger = SaleLedgerSyncState.buildBatch(allSales);
      final saleLedgerDays = SaleLedgerSyncState.buildDayDeclarations(
        allRecords: allSales,
        currentBusinessDate: businessDateString,
      );
      final allTimeBreakdown = <String, double>{};
      double allTimeTotalRevenue = 0;
      int allTimeOrderCount = 0;
      for (final sale in allSales) {
        final isCancelled = sale['isCancelled'] == true;
        final restoredToOrder = sale['restoredToOrder'] == true;
        if (DatabaseService.saleIsAdvanceReceipt(sale)) {
          final amount = (sale['totalAmount'] as num?)?.toDouble() ?? 0.0;
          allTimeBreakdown['advance-received'] =
              (allTimeBreakdown['advance-received'] ?? 0) + amount;
          continue;
        }
        final totalAmount = DatabaseService.saleGrossOf(sale);
        if (!DatabaseService.saleCountsAsRevenue(sale)) {
          // Internal closures get their own bucket and stay out of revenue —
          // they used to be added to the all-time total, which is exactly the
          // leak the daily and Z figures were careful to avoid.
          if (!isCancelled && !restoredToOrder && sale['isFiscal'] == false) {
            allTimeBreakdown['non-fiscal'] =
                (allTimeBreakdown['non-fiscal'] ?? 0) + totalAmount;
          }
          continue;
        }
        allTimeTotalRevenue += totalAmount;
        allTimeOrderCount += 1;
        final breakdown = PaymentUtils.extractBreakdown(sale);
        breakdown.forEach((key, amount) {
          allTimeBreakdown[key] = (allTimeBreakdown[key] ?? 0) + amount;
        });
      }
      final roundedAllTimeBreakdown = <String, double>{};
      allTimeBreakdown.forEach((key, value) {
        roundedAllTimeBreakdown[key] = double.parse(value.toStringAsFixed(2));
      });
      final allTimeItems = <String, Map<String, double>>{};
      for (final sale in allSales) {
        if (!DatabaseService.saleCountsAsRevenue(sale)) continue;
        final rawItems = (sale['items'] as List?) ?? const [];
        for (final rawItem in rawItems) {
          if (rawItem is! Map) continue;
          final item = Map<String, dynamic>.from(rawItem);
          final name = (item['itemName'] as String?)?.trim();
          if (name == null || name.isEmpty) continue;
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final unitPrice =
              (item['unitPrice'] as num?)?.toDouble() ??
              (item['price'] as num?)?.toDouble() ??
              0.0;
          final revenue = qty * unitPrice;
          final current = allTimeItems[name] ?? {'qty': 0, 'revenue': 0};
          current['qty'] = (current['qty'] ?? 0) + qty;
          current['revenue'] = (current['revenue'] ?? 0) + revenue;
          allTimeItems[name] = current;
        }
      }
      final topItems =
          allTimeItems.entries
              .map(
                (entry) => {
                  'name': entry.key,
                  'qty': (entry.value['qty'] ?? 0).round(),
                  'revenue': double.parse(
                    (entry.value['revenue'] ?? 0).toStringAsFixed(2),
                  ),
                },
              )
              .toList()
            ..sort((a, b) {
              final revenueCmp = ((b['revenue'] as num?) ?? 0).compareTo(
                (a['revenue'] as num?) ?? 0,
              );
              if (revenueCmp != 0) return revenueCmp;
              return ((b['qty'] as num?) ?? 0).compareTo(
                (a['qty'] as num?) ?? 0,
              );
            });
      final allTimeCashRevenue = roundedAllTimeBreakdown['cash'] ?? 0.0;
      final allTimeCardRevenue = roundedAllTimeBreakdown.entries.fold<double>(
        0,
        (sum, entry) => entry.key.startsWith('card') ? sum + entry.value : sum,
      );
      final salesAllTimeSummary = {
        'totalRevenue': double.parse(allTimeTotalRevenue.toStringAsFixed(2)),
        'orderCount': allTimeOrderCount,
        'cashRevenue': double.parse(allTimeCashRevenue.toStringAsFixed(2)),
        'cardRevenue': double.parse(allTimeCardRevenue.toStringAsFixed(2)),
        'paymentBreakdown': roundedAllTimeBreakdown,
        'topItems': topItems.take(20).toList(),
      };

      timing.mark('sales');

      // 2.3 Prepare per-day sales history from exactly the same Sale predicate
      // as every other revenue total. Raw Orders are not revenue evidence.
      final salesHistoryByDate = ManagerSalesHistoryBuilder.build(
        sales: allSales,
        expenseTotalForDate: DatabaseService.getExpenseTotalForDate,
      );

      timing.mark('reports');

      // 3. Sync Menu
      // The reconciliation flag is safe only when the snapshot is complete.
      // Repair any legacy/restored id-less nodes before we claim authority.
      await MenuRepository.ensureStableMenuIds();
      final menu = DatabaseService.getAllMenuCategories()
          .map(
            (cat) => {
              if (cat.id != null) 'id': cat.id,
              'slug': cat.slug,
              'nameKa': cat.translationsKa['name'] ?? '',
              'nameEn': cat.translationsEn['name'] ?? '',
              'sendToKitchen': cat.sendToKitchen,
              'items':
                  cat.items
                      ?.map(
                        (it) => {
                          // Identity first: Cloud matches the mirror row on
                          // this, so a rename updates the product instead of
                          // creating a second one under the new name.
                          if (it.id != null) 'id': it.id,
                          'nameKa': it.translationsKa['name'] ?? '',
                          'nameEn': it.translationsEn['name'] ?? '',
                          'price': it.price ?? 0.0,
                          'sendToKitchen': it.sendToKitchen,
                          'variants':
                              it.variants
                                  ?.map(
                                    (v) => {
                                      if (v.id != null) 'id': v.id,
                                      'size': v.size,
                                      'price': v.price,
                                    },
                                  )
                                  .toList() ??
                              [],
                        },
                      )
                      .toList() ??
                  [],
              'subcategories':
                  cat.subcategories
                      ?.map(
                        (sub) => {
                          if (sub.id != null) 'id': sub.id,
                          'slug': sub.slug,
                          'nameKa': sub.translationsKa['name'] ?? '',
                          'nameEn': sub.translationsEn['name'] ?? '',
                          'items': sub.items
                              .map(
                                (it) => {
                                  if (it.id != null) 'id': it.id,
                                  'nameKa': it.translationsKa['name'] ?? '',
                                  'nameEn': it.translationsEn['name'] ?? '',
                                  'price': it.price ?? 0.0,
                                  'sendToKitchen': it.sendToKitchen,
                                  'variants':
                                      it.variants
                                          ?.map(
                                            (v) => {
                                              if (v.id != null) 'id': v.id,
                                              'size': v.size,
                                              'price': v.price,
                                            },
                                          )
                                          .toList() ??
                                      [],
                                },
                              )
                              .toList(),
                        },
                      )
                      .toList() ??
                  [],
            },
          )
          .toList();

      timing.mark('menu');

      // 4. Sync Staff — identity and role every time, a PIN only when the
      // backend has not acknowledged the one this member currently has.
      //
      // Sending every PIN on every snapshot made the server re-run bcrypt cost
      // 12 over credentials it already held, which dominated ingest. What is
      // still required is unchanged: a member the server has never seen, and
      // any PIN that actually changed, arrive with their PIN.
      await StaffCredentialSyncState.open();
      final staffSelection = StaffCredentialSyncState.selectStaff(
        DatabaseService.getAllUsers(),
      );
      final staffList = staffSelection.entries;

      timing.mark('staff');

      // 5. Sync QuickOrderDrafts (Counted Menus)
      final quickOrders = DatabaseService.getQuickOrderDrafts()
          .map(
            (q) => {
              'id': q.id,
              'displayName': q.displayName,
              'subtotal': q.subtotal,
              'serviceFeeAmount': q.serviceFeeAmount,
              'total': q.total,
              'includeServiceFee': q.includeServiceFee,
              'serviceFeeRate': q.serviceFeeRate,
              'createdAt': q.createdAt.toIso8601String(),
              'createdBy': q.createdBy,
              'items': q.items
                  .map(
                    (it) => {
                      'itemName': it.itemName,
                      'quantity': it.quantity,
                      'unitPrice': it.unitPrice,
                      'comment': it.comment,
                    },
                  )
                  .toList(),
            },
          )
          .toList();

      timing.mark('quick');

      // 6. Prepare Payload
      //
      // Expenses and reservations are built here rather than inside the map
      // literal so each has a measurable cost of its own; the values and the
      // order they are read in are unchanged.
      final expenseRecords = DatabaseService.getAllExpenseRecords()
          .where((e) => (e['id'] as String?)?.trim().isNotEmpty == true)
          .map(
            (e) => {
              'id': (e['id'] as String).trim(),
              'description': (e['description'] as String?) ?? '',
              'amount': (e['amount'] as num?)?.toDouble() ?? 0.0,
              'category': (e['category'] as String?) ?? '',
              'paymentType': (e['paymentType'] as String?) ?? 'cash',
              if (e['createdAt'] != null) 'createdAt': e['createdAt'],
              if (e['date'] != null) 'businessDate': e['date'],
            },
          )
          .toList();
      timing.mark('expenses');

      // Cloud holds bookings, not the reservation box. Every order-creation
      // path also writes a row here — walk-in, takeaway, and package through
      // the walk-in default — and none of Cloud's consumers want them: the
      // Manager list and the website availability rules both discard them on
      // read today. Sending them only to have them filtered is what makes this
      // the most expensive phase of a sync that changed no booking at all.
      //
      // The rows stay in Hive untouched; this narrows the projection, not the
      // history.
      final reservationProjection = ReservationClassification.projectForCloud(
        allReservations,
      );
      final reservationPayload = reservationProjection.bookings
          .map(DatabaseService.serializeReservationForSync)
          .toList();
      debugPrint(reservationProjection.summaryLine);
      timing.mark('reservations');

      final payload = {
        'tables': tables,
        'orders': todayOrders,
        if (touchedOrderHints.isNotEmpty)
          'touchedOrderHints': touchedOrderHints,
        if (touchedTableHints.isNotEmpty)
          'touchedTableHints': touchedTableHints,
        if (touchedReservationHints.isNotEmpty)
          'touchedReservationHints': touchedReservationHints,
        'menu': menu,
        // Signals that every persisted menu node has a stable id and this is a
        // complete authoritative projection, so Cloud may reconcile omissions.
        'menuIdentityVersion': 1,
        // Real expense records, not an empty list beside a derived profit
        // figure. Each carries its POS-side id so re-sending the same record
        // updates it instead of adding a second one.
        'expenses': expenseRecords,
        'staff': staffList,
        // Every advance booking this POS holds — not every row in its
        // reservation box; see the projection above.
        //
        // Cloud used to ask for these over the LAN, one request at a time, from
        // whichever backend needed them — which meant a manager's reservation
        // list and the public website's availability page both waited on this
        // machine being awake. Since Step 6C they read a Cloud mirror instead,
        // and this is what fills it. The POS is still the one that owns them.
        'reservations': reservationPayload,
        'quickOrders': quickOrders,
        'syncedAt': DateTime.now().toIso8601String(),
        // Send current business date so the backend knows which calendar day
        // the POS considers "today" (independent of wall-clock midnight).
        'businessDate': businessDateString,
        'dailySalesTotal': double.parse(
          DatabaseService.getDailySalesTotal().toStringAsFixed(2),
        ),
        'salesSummary': salesSummary,
        'salesAllTimeSummary': salesAllTimeSummary,
        'salesHistoryByDate': salesHistoryByDate,
        // Genuine retained Sales only. This bounded, revision-ACKed backlog is
        // an asynchronous mirror; failure never participates in table close.
        'saleLedger': saleLedger,
        'saleLedgerDays': saleLedgerDays,
        'openTablesPayable': double.parse(openTablesPayable.toStringAsFixed(2)),
        'settings': {
          'serviceFeePercent': DatabaseService.getServiceFeePercentage(),
          'serviceFeeEnabled': DatabaseService.isServiceFeeEnabledByDefault(),
        },
        if (PosCallbackConfig.baseUrl != null)
          'posCallbackUrl': PosCallbackConfig.baseUrl,
        if (PosCallbackConfig.connectionKey != null &&
            PosCallbackConfig.connectionKey!.isNotEmpty)
          'posConnectionKey': PosCallbackConfig.connectionKey,
      };

      debugPrint(
        '[ManagerSync][MoneyDebug] businessDate=$businessDateString '
        'xReportDaily=${DatabaseService.getDailySalesTotal().toStringAsFixed(2)} '
        'salesSummaryTotal=${salesSummary['totalRevenue']} '
        'openTablesPayable=${openTablesPayable.toStringAsFixed(2)} '
        'todayOrders=${todayOrders.length}',
      );

      // Debug: log reserved tables being sent
      final reservedTables = tables
          .where((t) => t['isReserved'] == true || t['activeOrderId'] != null)
          .toList();
      debugPrint(
        '[ManagerSync] Sending ${tables.length} tables, ${reservedTables.length} reserved, ${todayOrders.length} orders, ${staffList.length} staff (${staffSelection.pinCount} with a PIN).',
      );
      for (final t in reservedTables) {
        debugPrint(
          '[ManagerSync]  → ${t['tableNumber']}/${t['floor']}: isReserved=${t['isReserved']}, orderId=${t['activeOrderId']}',
        );
      }

      timing.mark('payload');

      // 5. Send to NestJS
      ConnectionStatusService.markAttempt();
      final body = await compute(_encodeManagerPayload, payload);
      timing.payloadBytes = body.length;
      timing.mark('encode');
      final response = await http.post(
        Uri.parse('$serverUrl/sync/manager-data'),
        headers: ApiConfig.posSyncHeaders,
        body: body,
      );
      timing.mark('http');

      if (response.statusCode != 201 && response.statusCode != 200) {
        debugPrint(
          'Manager Sync Failed (${response.statusCode}) → $serverUrl: ${response.body}',
        );
        ConnectionStatusService.markFailure(
          'Manager sync failed (${response.statusCode}): ${response.body}',
        );
      } else {
        debugPrint(
          '[ManagerSync] OK → $serverUrl '
          'callback=${payload['posCallbackUrl'] ?? "missing"}',
        );
        _pendingSinceMicros = null;
        await _acknowledgeStaffCredentials(staffSelection, response.body);
        final ledgerAckSupported =
            await SaleLedgerSyncState.acknowledgeResponse(response.body);
        await ConnectionStatusService.markSuccess();
        if (ledgerAckSupported && saleLedger.isNotEmpty) {
          // One follow-up full snapshot advances the next bounded batch and,
          // after the final ACK, lets closed-day completeness be proven.
          _markPendingLocalChange();
        }
      }

      // 6. Sync Audit Reports (fire-and-forget — best effort)
      _runAuditSyncTimed(timing, 'POS');
    } catch (e) {
      debugPrint(
        'Manager Sync Error (cannot reach $serverUrl — is NestJS running on port 3000?): $e',
      );
      ConnectionStatusService.markFailure(e);
      timing.log('POS/failed');
    }
  }

  /// Starts the audit push without waiting for it, and prints the one-line
  /// timing summary once it lands.
  ///
  /// The audit push has always been fire-and-forget — the snapshot does not
  /// depend on it and a slow audit must not hold the sync open — so this keeps
  /// it unawaited. Attaching the summary to its completion is only so the line
  /// can carry an audit figure; the caller still returns immediately.
  static void _runAuditSyncTimed(SyncTiming timing, String source) {
    unawaited(
      _syncAuditReports().whenComplete(() {
        timing.mark('audit');
        timing.log(source);
      }),
    );
  }

  /// How many audit reports one request may carry.
  ///
  /// A report carries its whole event list, so the bound that matters is the
  /// serialized size rather than the row count; 100 keeps a batch in the same
  /// order of magnitude as a manager-data push instead of building one request
  /// out of a restaurant's entire history.
  static const int auditSyncBatchSize = 100;

  /// The ceiling on an id-only reconciliation payload.
  ///
  /// Reconciliation is cheap because it carries ids and no contents, but it is
  /// still one list, so a POS holding more reports than this skips it rather
  /// than assembling a megabyte to answer a question nobody asked.
  static const int auditReconcileMaxReports = 20000;

  /// Guards audit sync against overlapping itself.
  ///
  /// It is started fire-and-forget from every manager-data push, and two passes
  /// in flight could acknowledge revisions out of order — an older ack landing
  /// last would mark a newer local edit as synced.
  static bool _auditSyncInFlight = false;

  /// Reconciliation runs once per process, after the backlog has drained.
  static bool _auditReconciledThisRun = false;

  /// Push audit reports the backend has not acknowledged.
  ///
  /// The POS used to send its entire audit history on every change, which meant
  /// one new order re-uploaded a thousand unchanged reports. What was missing
  /// was not a filter but a durable answer to "which of these does the server
  /// already have" — [AuditSyncState] is that answer, keyed by a content
  /// revision rather than a clock.
  ///
  /// A report is clean only once the backend has acknowledged the exact
  /// revision that was sent. A report edited while its previous revision was in
  /// flight therefore stays dirty and goes again, which is the race this has to
  /// get right.
  ///
  /// On the first run after upgrading, nothing is acknowledged yet, so the whole
  /// history is dirty and is uploaded once in bounded batches, checkpointing
  /// after each. That is deliberate: it reconciles against what the backend
  /// actually holds instead of assuming it. After it drains, only changed
  /// reports are sent.
  static Future<void> _syncAuditReports() async {
    if (_auditSyncInFlight) return;
    _auditSyncInFlight = true;
    try {
      await AuditSyncState.open();

      final selection = AuditSyncState.selectDirty(
        DatabaseService.getAuditReports(),
      );
      final dirty = selection.dirty;
      final knownReportIds = selection.knownReportIds;

      if (dirty.isEmpty) {
        await _reconcileAuditReportsOnce(knownReportIds);
        return;
      }

      final isBackfill = dirty.length > auditSyncBatchSize;
      var sent = 0;
      var acked = 0;
      var interrupted = false;

      for (
        var offset = 0;
        offset < dirty.length;
        offset += auditSyncBatchSize
      ) {
        final end = offset + auditSyncBatchSize;
        final batch = dirty.sublist(
          offset,
          end < dirty.length ? end : dirty.length,
        );
        final batchAcked = await _pushAuditBatch(batch);
        if (batchAcked == null) {
          // The backend is unavailable or rejected the batch. Everything not
          // acknowledged stays dirty, so the next push resumes here.
          interrupted = true;
          break;
        }
        sent += batch.length;
        acked += batchAcked;
        if (isBackfill) {
          debugPrint(
            '[ManagerSync] Audit backfill: acked=$acked remaining=${dirty.length - acked}',
          );
        }
      }

      final remaining = dirty.length - acked;
      if (!isBackfill) {
        debugPrint(
          '[ManagerSync] Audit sync: dirty=${dirty.length} sending=$sent '
          'acked=$acked remaining=$remaining'
          '${interrupted ? " (backend unavailable)" : ""}',
        );
        _debugAuditDirtyBreakdown(dirty);
      }

      if (remaining == 0) {
        await _reconcileAuditReportsOnce(knownReportIds);
      }
    } catch (e) {
      debugPrint('[ManagerSync] Audit sync error: $e');
    } finally {
      _auditSyncInFlight = false;
    }
  }

  /// How many dirty report ids one debug line will name.
  static const int _auditDirtyIdLogLimit = 12;

  /// Names what is dirty and why, in debug builds only.
  ///
  /// Counts alone cannot tell a busy evening from a report whose content will
  /// not settle: both show a steady `dirty=16`. Splitting new from changed and
  /// naming the ids does — the same ids reported as `changed` pass after pass
  /// means the producer is rewriting them, not the restaurant. Ids and nothing
  /// else: no customer names, staff names, items or amounts.
  static void _debugAuditDirtyBreakdown(List<DirtyAuditReport> dirty) {
    if (!kDebugMode || dirty.isEmpty) return;
    final fresh = dirty.where((entry) => entry.isNew).length;
    final ids = dirty
        .take(_auditDirtyIdLogLimit)
        .map((entry) {
          return '${entry.reportId}(${entry.isNew ? 'new' : 'changed'})';
        })
        .join(' ');
    final overflow = dirty.length - _auditDirtyIdLogLimit;
    debugPrint(
      '[ManagerSync] Audit dirty: new=$fresh changed=${dirty.length - fresh} '
      '$ids${overflow > 0 ? ' +$overflow more' : ''}',
    );
  }

  /// Sends one batch and records what the backend acknowledged.
  ///
  /// Returns the number of reports marked synced, or null when the request
  /// itself failed — the caller stops there rather than burning through the
  /// rest of the backlog against a backend that is not answering.
  static Future<int?> _pushAuditBatch(List<DirtyAuditReport> batch) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$serverUrl/sync/audit-reports'),
        headers: ApiConfig.posSyncHeaders,
        body: await compute(_encodeManagerPayload, <String, dynamic>{
          'reports': batch.map((entry) => entry.toPayload()).toList(),
        }),
      );
    } catch (e) {
      debugPrint('[ManagerSync] Audit sync transport error: $e');
      return null;
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint(
        '[ManagerSync] Audit sync failed: ${response.statusCode} ${response.body}',
      );
      return null;
    }

    Object? decoded;
    try {
      decoded = json.decode(response.body);
    } catch (_) {
      decoded = null;
    }
    final acknowledged = decoded is Map ? decoded['acknowledged'] : null;

    // A backend that predates revision acknowledgment answers 2xx with no
    // `acknowledged` list. Under the old contract a 2xx *was* the acknowledgment
    // for everything sent, so honour that rather than resending forever.
    if (acknowledged is! List) {
      for (final entry in batch) {
        await AuditSyncState.markAcknowledged(entry.reportId, entry.revision);
      }
      return batch.length;
    }

    final sentRevisions = <String, String>{
      for (final entry in batch) entry.reportId: entry.revision,
    };

    var count = 0;
    for (final raw in acknowledged) {
      if (raw is! Map) continue;
      final reportId = raw['reportId']?.toString().trim() ?? '';
      if (reportId.isEmpty) continue;
      final sentRevision = sentRevisions[reportId];
      // Not something this batch offered.
      if (sentRevision == null) continue;
      final ackedRevision = raw['revision']?.toString();
      // An acknowledgment of some other revision is not an acknowledgment of
      // this one. Recording the sent revision here — never the report's current
      // content — is what stops an ack for N marking N+1 clean.
      if (ackedRevision != null &&
          ackedRevision.isNotEmpty &&
          ackedRevision != sentRevision) {
        continue;
      }
      await AuditSyncState.markAcknowledged(reportId, sentRevision);
      count += 1;
    }
    return count;
  }

  /// Tell the backend which reports this POS still holds, so it can drop the
  /// ones it no longer should have.
  ///
  /// Carries ids and no contents, and runs once per process once the upload
  /// backlog is empty — the case it exists for is a restored backup, not an
  /// ordinary evening. An empty set is never sent: a POS whose audit box failed
  /// to open would otherwise ask the backend to delete a restaurant's history.
  static Future<void> _reconcileAuditReportsOnce(
    Set<String> knownReportIds,
  ) async {
    if (_auditReconciledThisRun) return;
    if (knownReportIds.isEmpty) return;
    if (knownReportIds.length > auditReconcileMaxReports) {
      debugPrint(
        '[ManagerSync] Audit reconcile skipped: ${knownReportIds.length} reports '
        'exceeds the $auditReconcileMaxReports id-list bound.',
      );
      _auditReconciledThisRun = true;
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$serverUrl/sync/audit-reports'),
        headers: ApiConfig.posSyncHeaders,
        body: await compute(_encodeManagerPayload, <String, dynamic>{
          'knownReportIds': knownReportIds.toList(),
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        _auditReconciledThisRun = true;
        await AuditSyncState.pruneUnknown(knownReportIds);
      }
    } catch (e) {
      debugPrint('[ManagerSync] Audit reconcile error: $e');
    }
  }

  static List<OrderItem> _orderItemsFromRaw(Map<String, dynamic> raw) {
    final items = (raw['items'] as List?) ?? const [];
    final result = <OrderItem>[];
    for (final it in items) {
      if (it is! Map) continue;
      final m = Map<String, dynamic>.from(it);
      final name = (m['name'] ?? '').toString();
      final price = (m['price'] as num?)?.toDouble() ?? 0.0;
      final qty = (m['quantity'] as num?)?.toInt() ?? 0;
      result.add(
        OrderItem(
          itemKey: name,
          itemName: name,
          unitPrice: price,
          quantity: qty,
          total: price * qty,
          menuItemId: m['menuItemId'] as String?,
          variantId: m['variantId'] as String?,
        ),
      );
    }
    return result;
  }

  static String? _mergeChangeSummaries(
    String? a,
    String? b, {
    bool preferServiceFee = false,
  }) {
    final lines = <String>[];
    for (final raw in [a, b]) {
      if (raw == null) continue;
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!lines.contains(trimmed)) lines.add(trimmed);
      }
    }
    if (lines.isEmpty) return null;
    if (preferServiceFee) {
      for (var i = lines.length - 1; i >= 0; i--) {
        final line = lines[i];
        if (line.contains('ჩართული') || line.contains('გამორთული')) {
          return line;
        }
      }
    }
    return lines.last;
  }

  static String _tableLabelForSyncOrder(Map<String, dynamic> raw) {
    final floor = (raw['floor'] ?? '').toString().toLowerCase();
    if (floor.contains('takeaway')) {
      return 'გატანა';
    }
    final nums = (raw['tableNumbers'] as List?) ?? const [];
    final parts = nums
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '-';
    }
    return parts.join(', ');
  }

  static void _enqueuePendingOrderHint({
    required int posOrderId,
    required String tableLabel,
    required String floor,
    required String changeSummary,
    required String changeKind,
  }) {
    _pendingOrderHints.removeWhere((h) => h['posOrderId'] == posOrderId);
    _pendingOrderHints.add({
      'posOrderId': posOrderId,
      'tableLabel': tableLabel,
      'floor': floor,
      'changeSummary': changeSummary,
      'changeKind': changeKind,
      'occurredAt': DatabaseService.getCurrentDateTime().toIso8601String(),
    });
  }

  static List<Map<String, dynamic>> _drainPendingOrderHints() {
    if (_pendingOrderHints.isEmpty) return const [];
    final drained = _pendingOrderHints
        .map((h) => Map<String, dynamic>.from(h))
        .toList();
    _pendingOrderHints.clear();
    return drained;
  }

  static List<Map<String, dynamic>> _mergeTouchedOrderHints(
    List<Map<String, dynamic>> computed,
    List<Map<String, dynamic>> pending,
  ) {
    if (pending.isEmpty) return computed;
    final byId = <int, Map<String, dynamic>>{};
    for (final h in computed) {
      final id = (h['posOrderId'] as num?)?.toInt();
      if (id != null) byId[id] = Map<String, dynamic>.from(h);
    }
    for (final h in pending) {
      final id = (h['posOrderId'] as num?)?.toInt();
      if (id == null) continue;
      final existing = byId[id];
      if (existing != null) {
        final mergedSummary = _mergeChangeSummaries(
          existing['changeSummary'] as String?,
          h['changeSummary'] as String?,
          preferServiceFee:
              (h['changeKind'] ?? existing['changeKind']) == 'service_fee',
        );
        byId[id] = {
          ...existing,
          ...h,
          if (mergedSummary != null) 'changeSummary': mergedSummary,
        };
      } else {
        byId[id] = Map<String, dynamic>.from(h);
      }
    }
    return byId.values.toList();
  }

  /// POS sync hints when order lines change (add / remove / qty / price).
  static List<Map<String, dynamic>> _computeTouchedOrderHints(
    List<Map<String, dynamic>> todayOrders,
  ) {
    final touched = <Map<String, dynamic>>[];
    final seen = <int>{};
    final occurredAt = DatabaseService.getCurrentDateTime().toIso8601String();

    if (!_orderFingerprintsBootstrapped) {
      for (final raw in todayOrders) {
        final id = (raw['posOrderId'] as num?)?.toInt();
        if (id == null) continue;
        seen.add(id);
        _lastOrderItemsByOrderId[id] = _orderItemsFromRaw(raw);
        _lastOrderBillingByOrderId[id] = _billingSnapshotFromRaw(raw);
      }
      _lastOrderItemsByOrderId.removeWhere((k, _) => !seen.contains(k));
      _lastOrderBillingByOrderId.removeWhere((k, _) => !seen.contains(k));
      _orderFingerprintsBootstrapped = true;
      return [];
    }

    for (final raw in todayOrders) {
      final id = (raw['posOrderId'] as num?)?.toInt();
      if (id == null) continue;
      seen.add(id);
      final nextItems = _orderItemsFromRaw(raw);
      final nextBilling = _billingSnapshotFromRaw(raw);
      final prevItems = _lastOrderItemsByOrderId[id];
      final prevBilling = _lastOrderBillingByOrderId[id];
      Map<String, dynamic>? hint;

      if (prevItems != null) {
        final diff = PosChangeHighlightService.computeOrderItemChanges(
          before: prevItems,
          after: nextItems,
        );
        if (diff.hasLineChanges) {
          hint = {
            'posOrderId': id,
            'occurredAt': occurredAt,
            'tableLabel': _tableLabelForSyncOrder(raw),
            'floor': (raw['floor'] ?? '').toString(),
            if (diff.highlightKeys.isNotEmpty)
              'highlightItemKeys': diff.highlightKeys.toList(),
            if (diff.summaryLines.isNotEmpty)
              'changeSummary': diff.summaryLines.join('\n'),
          };
        }
      }

      if (prevBilling != null) {
        final feeChanged =
            prevBilling.includeServiceFee != nextBilling.includeServiceFee;
        final totalChanged =
            (prevBilling.totalAmount - nextBilling.totalAmount).abs() > 0.009;
        if (feeChanged) {
          final feeSummary = nextBilling.includeServiceFee
              ? 'სერვისის საფასური ჩართულია'
              : 'სერვისის საფასური გამორთულია';
          if (hint != null) {
            hint['changeSummary'] =
                _mergeChangeSummaries(
                  hint['changeSummary'] as String?,
                  feeSummary,
                  preferServiceFee: true,
                ) ??
                feeSummary;
            hint['changeKind'] = 'service_fee';
          } else {
            hint = {
              'posOrderId': id,
              'occurredAt': occurredAt,
              'tableLabel': _tableLabelForSyncOrder(raw),
              'floor': (raw['floor'] ?? '').toString(),
              'changeSummary': feeSummary,
              'changeKind': 'service_fee',
            };
          }
        } else if (totalChanged && hint == null) {
          hint = {
            'posOrderId': id,
            'occurredAt': occurredAt,
            'tableLabel': _tableLabelForSyncOrder(raw),
            'floor': (raw['floor'] ?? '').toString(),
            'changeSummary': 'თანხა განახლდა',
            'changeKind': 'total',
          };
        }
      }

      if (hint != null) {
        touched.add(hint);
      }

      _lastOrderItemsByOrderId[id] = nextItems.map((i) => i.clone()).toList();
      _lastOrderBillingByOrderId[id] = nextBilling;
    }

    _lastOrderItemsByOrderId.removeWhere((k, _) => !seen.contains(k));
    _lastOrderBillingByOrderId.removeWhere((k, _) => !seen.contains(k));
    return touched;
  }

  static ({bool includeServiceFee, double totalAmount}) _billingSnapshotFromRaw(
    Map<String, dynamic> raw,
  ) {
    return (
      includeServiceFee: raw['includeServiceFee'] == true,
      totalAmount: (raw['totalAmount'] as num?)?.toDouble() ?? 0,
    );
  }

  static void _enqueuePendingTableHint({
    required String tableNumber,
    required String floor,
    required String changeType,
    int? orderId,
  }) {
    final occurredAt = DatabaseService.getCurrentDateTime().toIso8601String();
    _pendingTableHints.removeWhere(
      (h) =>
          h['tableNumber'] == tableNumber &&
          h['floor'] == floor &&
          h['changeType'] == changeType,
    );
    _pendingTableHints.add({
      'tableNumber': tableNumber,
      'floor': floor,
      'changeType': changeType,
      if (orderId != null) 'activeOrderId': orderId,
      'occurredAt': occurredAt,
    });
    final key = '${tableNumber}_$floor';
    _lastTableOccupiedByKey[key] = changeType == 'reserved';
  }

  /// Hive table map + active dine-in orders (source of truth when Hive lags).
  static List<Map<String, dynamic>> _buildTablesSyncPayload(
    List<Order> allOrders,
    DateTime businessDate,
  ) {
    final byKey = <String, Map<String, dynamic>>{};

    for (final table in DatabaseService.getAllTables()) {
      if (table.activeOrderId != null) {
        final order = allOrders
            .where((o) => o.orderId == table.activeOrderId)
            .firstOrNull;
        table.currentBill = order?.totalAmount ?? 0.0;
      } else {
        table.currentBill = 0.0;
      }
      final json = Map<String, dynamic>.from(table.toJson());
      final tableId = _canonicalTableIdForAlias(
        floor: table.floor,
        tableNumber: table.tableNumber,
      );
      if (tableId != null) {
        json['tableId'] = tableId;
      }
      byKey[_tableKeyForSync(json)] = json;
    }

    for (final order in allOrders) {
      if (!_isActiveDineInOrderForBusinessDate(order, businessDate)) {
        continue;
      }
      for (final rawNum in order.tableNumbers) {
        final tableNumber = _normalizeTableNumberForSync(
          rawNum.toString(),
          order.floor,
        );
        if (tableNumber == null || tableNumber.isEmpty) continue;
        final key = '${tableNumber}_${order.floor}';
        final merged = Map<String, dynamic>.from(
          byKey[key] ??
              {
                'tableNumber': tableNumber,
                'floor': order.floor,
                'isReserved': false,
                'currentBill': 0.0,
              },
        );
        final tableId = _canonicalTableIdForAlias(
          floor: order.floor,
          tableNumber: tableNumber,
        );
        if (tableId != null) {
          merged['tableId'] = tableId;
        }
        merged['isReserved'] = true;
        merged['activeOrderId'] = order.orderId;
        merged['currentBill'] = order.totalAmount;
        byKey[key] = merged;
      }
    }

    return byKey.values.toList();
  }

  static bool _isActiveDineInOrderForBusinessDate(
    Order order,
    DateTime businessDate,
  ) {
    final status = order.status.toLowerCase();
    if (status == 'closed' || status == 'cancelled' || status == 'paid') {
      return false;
    }
    final floor = order.floor.toLowerCase();
    if (floor.contains('takeaway') || floor.contains('take away')) {
      return false;
    }
    final created = order.createdAt;
    return created.year == businessDate.year &&
        created.month == businessDate.month &&
        created.day == businessDate.day;
  }

  static String? _normalizeTableNumberForSync(String raw, String floor) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('table ')) {
      return trimmed.substring(6).trim();
    }
    if (lower.startsWith('vip zone ')) {
      return trimmed.substring(9).trim();
    }
    final parsed = int.tryParse(trimmed);
    if (parsed != null && floor == 'second' && parsed > 10) {
      return (parsed - 10).toString();
    }
    return trimmed;
  }

  static String? _canonicalTableIdForAlias({
    required String floor,
    required String tableNumber,
  }) {
    final definition = DatabaseService.getRestaurantTableLayout()
        .tableForLegacy(floor: floor, tableNumber: tableNumber);
    final id = definition?.id;
    return id != null && table_identity.isCanonicalTableId(id) ? id : null;
  }

  static List<String>? _canonicalTableIdsForOrder(Order order) {
    if (order.tableNumbers.isEmpty) {
      return null;
    }
    final ids = <String>[];
    for (final raw in order.tableNumbers) {
      final tableNumber = _normalizeTableNumberForSync(raw, order.floor);
      if (tableNumber == null) {
        return null;
      }
      final id = _canonicalTableIdForAlias(
        floor: order.floor,
        tableNumber: tableNumber,
      );
      if (id == null) {
        return null;
      }
      ids.add(id);
    }
    return ids;
  }

  static List<Map<String, dynamic>> _collectTableHintsForSync(
    List<Map<String, dynamic>> tablesPayload,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    void addHint(Map<String, dynamic> hint) {
      final matchingTable = tablesPayload
          .where(
            (table) =>
                table['tableNumber'] == hint['tableNumber'] &&
                table['floor'] == hint['floor'],
          )
          .firstOrNull;
      if (matchingTable?['tableId'] case final String tableId) {
        hint['tableId'] = tableId;
      }
      final key =
          '${hint['tableNumber']}_${hint['floor']}_${hint['changeType']}';
      merged[key] = hint;
    }

    for (final hint in _pendingTableHints) {
      addHint(Map<String, dynamic>.from(hint));
    }
    _pendingTableHints.clear();

    for (final hint in _computeTouchedTableHints(tablesPayload)) {
      addHint(hint);
    }

    return merged.values.toList();
  }

  static void _bootstrapTableFingerprintsFromLocal() {
    _lastTableOccupiedByKey.clear();
    for (final table in DatabaseService.getAllTables()) {
      final raw = table.toJson();
      _lastTableOccupiedByKey[_tableKeyForSync(raw)] = _isTableOccupiedRaw(raw);
    }
    _tableFingerprintsBootstrapped = true;
  }

  static String _tableKeyForSync(Map<String, dynamic> raw) {
    return '${raw['tableNumber']}_${raw['floor']}';
  }

  static bool _isTableOccupiedRaw(Map<String, dynamic> raw) {
    return raw['isReserved'] == true || raw['activeOrderId'] != null;
  }

  /// Emits hints when a table becomes occupied or free (walk-in open / close).
  static List<Map<String, dynamic>> _computeTouchedTableHints(
    List<Map<String, dynamic>> tables,
  ) {
    final touched = <Map<String, dynamic>>[];
    final seen = <String>{};
    final occurredAt = DatabaseService.getCurrentDateTime().toIso8601String();

    if (!_tableFingerprintsBootstrapped) {
      _bootstrapTableFingerprintsFromLocal();
      return [];
    }

    for (final raw in tables) {
      final key = _tableKeyForSync(raw);
      seen.add(key);
      final nowOccupied = _isTableOccupiedRaw(raw);
      final wasOccupied = _lastTableOccupiedByKey[key] ?? false;
      if (nowOccupied != wasOccupied) {
        touched.add({
          if (raw['tableId'] != null) 'tableId': raw['tableId'],
          'tableNumber': raw['tableNumber'],
          'floor': raw['floor'],
          'changeType': nowOccupied ? 'reserved' : 'freed',
          if (raw['activeOrderId'] != null)
            'activeOrderId': raw['activeOrderId'],
          if (raw['currentBill'] != null) 'currentBill': raw['currentBill'],
          'occurredAt': occurredAt,
        });
      }
      _lastTableOccupiedByKey[key] = nowOccupied;
    }

    _lastTableOccupiedByKey.removeWhere((k, _) => !seen.contains(k));
    return touched;
  }

  /// Records which staff credentials the accepted snapshot acknowledged, and
  /// forgets any the backend says it still has no credential for.
  ///
  /// Runs only after the server accepted the push, so a failed sync leaves
  /// every credential it carried unacknowledged and the next one carries them
  /// again.
  static Future<void> _acknowledgeStaffCredentials(
    StaffSnapshotSelection selection,
    String responseBody,
  ) async {
    await StaffCredentialSyncState.markAccepted(selection.credentialsSent);
    await StaffCredentialSyncState.pruneUnknown(selection.knownUsernames);
    final needsPin = _staffNeedingPin(responseBody);
    if (needsPin.isNotEmpty) {
      debugPrint(
        '[ManagerSync] Backend holds no credential for ${needsPin.length} '
        'staff member(s); the next snapshot will carry their PINs.',
      );
      await StaffCredentialSyncState.forget(needsPin);
    }
  }

  /// The usernames the backend reported it could not create for want of a PIN.
  ///
  /// Absent from an older backend's response, which is silence rather than
  /// "none" — and silence is what the POS assumed before this existed.
  static List<String> _staffNeedingPin(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) return const <String>[];
      final raw = decoded['staffNeedingPin'];
      if (raw is! List) return const <String>[];
      return raw
          .whereType<String>()
          .map((username) => username.trim())
          .where((username) => username.isNotEmpty)
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }
}
