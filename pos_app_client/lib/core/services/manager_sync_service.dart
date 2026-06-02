import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/api_config.dart';
import 'package:vynic/core/services/pos_callback_config.dart';
import 'package:vynic/core/services/sync_events.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/services/pos_change_highlight_service.dart';
import 'package:vynic/core/utils/payment_utils.dart';

class ManagerSyncService {
  static String get serverUrl => ApiConfig.baseUrl;

  static Timer? _syncTimer;
  static Timer? _debounceTimer;

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
  static Timer? _realtimeDebounceTimer;
  static Timer? _serviceFeeSyncTimer;

  static void initialize() {
    // Always wire Hive → cloud (hot restart used to skip this when timer existed).
    if (!_hooksRegistered) {
      _previousOnLocalChange = SyncHub.onLocalChange;
      SyncHub.onLocalChange = (SyncEvent event) {
        _previousOnLocalChange?.call(event);
        _onLocalHiveChange(event);
      };
      DatabaseService.registerAuditChangedCallback(_syncAuditReportsDebounced);
      DatabaseService.registerUsersChangedCallback(syncToManagerAppDebounced);
      _hooksRegistered = true;
    }

    _bootstrapTableFingerprintsFromLocal();

    if (_syncTimer != null) return;

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

    // Periodic failsafe (realtime path is SyncHub → debounced push above).
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      syncToManagerApp();
    });
  }

  static void _onLocalHiveChange(SyncEvent event) {
    if (event.type == SyncEventType.tables) {
      final payload = event.payload;
      final action = event.action;
      if (payload != null &&
          (action == 'reserved' || action == 'freed')) {
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
        if (order != null &&
            !order.floor.toLowerCase().contains('takeaway')) {
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
      reservationDate =
          reservation?.reservationDate.toIso8601String() ?? '';
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

    final walkIn = customerName.toLowerCase() == 'walk-in' ||
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

  static Timer? _auditDebounceTimer;

  static void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _auditDebounceTimer?.cancel();
    _auditDebounceTimer = null;
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
  }

  /// Pushes data to the cloud immediately, but debounced to avoid spamming.
  static void syncToManagerAppDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      syncToManagerApp();
    });
  }

  /// Lightweight push (tables + orders only) — fast path for mobile realtime.
  static void syncRealtimeToManagerAppDebounced() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(syncRealtimeToManagerApp());
    });
  }

  /// Service-fee toggles can fire many Hive updates; wait until settling before notify.
  static void _syncServiceFeeToManagerDebounced() {
    _serviceFeeSyncTimer?.cancel();
    _serviceFeeSyncTimer = Timer(const Duration(milliseconds: 1500), () {
      unawaited(syncRealtimeToManagerApp());
    });
  }

  static Future<void> syncRealtimeToManagerApp() async {
    _realtimeOnly = true;
    try {
      await syncToManagerApp();
    } finally {
      _realtimeOnly = false;
    }
  }

  /// Push only audit reports, debounced so rapid successive events become one call.
  static void _syncAuditReportsDebounced() {
    _auditDebounceTimer?.cancel();
    _auditDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_syncAuditReports());
    });
  }

  static Future<void> syncToManagerApp() async {
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
      final todayOrders = allOrders
          .where((o) {
            return o.createdAt.year == businessDate.year &&
                o.createdAt.month == businessDate.month &&
                o.createdAt.day == businessDate.day;
          })
          .map((o) {
            // For takeaway orders, join the linked reservation for customer details
            String customerName = '';
            String pickupTime = '';
            String? orderBusinessDate;
            if (o.floor == 'takeaway') {
              final reservation = allReservations
                  .where((r) => r.isTakeAway && r.linkedOrderId == o.orderId)
                  .firstOrNull;
              customerName = reservation?.customerName ?? '';
              pickupTime = reservation?.reservationTime ?? '';
              // Use reservation date as the authoritative business date for this order.
              // This matches exactly what Windows POS uses to filter takeaways.
              if (reservation != null) {
                final rd = reservation.reservationDate;
                orderBusinessDate =
                    '${rd.year.toString().padLeft(4, '0')}-'
                    '${rd.month.toString().padLeft(2, '0')}-'
                    '${rd.day.toString().padLeft(2, '0')}';
              }
            }
            return {
              'posOrderId': o.orderId,
              'status': o.status,
              'totalAmount': o.totalAmount,
              'paymentType': (o.paymentMethod ?? 'cash').toString().toLowerCase(),
              'waiterName': o.createdBy,
              'tableNumbers': o.tableNumbers.map((e) => e.toString()).toList(),
              'floor': o.floor,
              if (orderBusinessDate != null) 'businessDate': orderBusinessDate,
              'customerName': customerName,
              'pickupTime': pickupTime,
              'includeServiceFee': o.includeServiceFee,
              'discountAmount': o.discountAmount,
              'serviceFeePercent': (o.customServiceFeePercentage ?? 10.0),
              'items': o.items
                  .map(
                    (it) => {
                      'name': it.itemName,
                      'quantity': it.quantity,
                      'price': it.unitPrice,
                    },
                  )
                  .toList(),
            };
          })
          .toList();

      final tables = _buildTablesSyncPayload(allOrders, businessDate);
      final orderMaps =
          todayOrders.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final touchedOrderHints = _mergeTouchedOrderHints(
        _computeTouchedOrderHints(orderMaps),
        _drainPendingOrderHints(),
      );
      final touchedTableHints = _collectTableHintsForSync(
        tables.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
      final touchedReservationHints = _drainReservationHints();
      final reservedInPayload = tables.where(_isTableOccupiedRaw).length;

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
          'openTablesPayable':
              double.parse(openTablesPayable.toStringAsFixed(2)),
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
        final response = await http.post(
          Uri.parse('$serverUrl/sync/manager-data'),
          headers: ApiConfig.posSyncHeaders,
          body: json.encode(payload),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('[ManagerSync] Realtime OK (${response.statusCode})');
        } else {
          debugPrint(
            '[ManagerSync] Realtime failed (${response.statusCode}): ${response.body}',
          );
        }
        unawaited(_syncAuditReports());
        return;
      }

      // 2.1 Prepare Sales Summary from local closed-sales records.
      // This is the authoritative source for payment-method analytics.
      final todaysSales = DatabaseService.getSalesForDate(businessDateString);
      final paymentBreakdown = <String, double>{};
      final totalRevenue = DatabaseService.getDailySalesTotal();
      int fiscalOrderCount = 0;
      for (final sale in todaysSales) {
        final isCancelled = sale['isCancelled'] == true;
        final restoredToOrder = sale['restoredToOrder'] == true;
        if (isCancelled || restoredToOrder) {
          continue;
        }
        final totalAmount = (sale['totalAmount'] as num?)?.toDouble() ??
            (sale['total'] as num?)?.toDouble() ??
            0.0;
        final isFiscal = sale['isFiscal'] != false;
        if (!isFiscal) {
          paymentBreakdown['non-fiscal'] =
              (paymentBreakdown['non-fiscal'] ?? 0) + totalAmount;
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
      final allTimeBreakdown = <String, double>{};
      double allTimeTotalRevenue = 0;
      int allTimeOrderCount = 0;
      for (final sale in allSales) {
        final isCancelled = sale['isCancelled'] == true;
        final restoredToOrder = sale['restoredToOrder'] == true;
        if (isCancelled || restoredToOrder) {
          continue;
        }
        final totalAmount = (sale['totalAmount'] as num?)?.toDouble() ??
            (sale['total'] as num?)?.toDouble() ??
            0.0;
        allTimeTotalRevenue += totalAmount;
        allTimeOrderCount += 1;
        final isFiscal = sale['isFiscal'] != false;
        if (!isFiscal) {
          allTimeBreakdown['non-fiscal'] =
              (allTimeBreakdown['non-fiscal'] ?? 0) + totalAmount;
          continue;
        }
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
        final isCancelled = sale['isCancelled'] == true;
        final restoredToOrder = sale['restoredToOrder'] == true;
        if (isCancelled || restoredToOrder) continue;
        final rawItems = (sale['items'] as List?) ?? const [];
        for (final rawItem in rawItems) {
          if (rawItem is! Map) continue;
          final item = Map<String, dynamic>.from(rawItem);
          final name = (item['itemName'] as String?)?.trim();
          if (name == null || name.isEmpty) continue;
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final unitPrice = (item['unitPrice'] as num?)?.toDouble() ??
              (item['price'] as num?)?.toDouble() ??
              0.0;
          final revenue = qty * unitPrice;
          final current = allTimeItems[name] ?? {'qty': 0, 'revenue': 0};
          current['qty'] = (current['qty'] ?? 0) + qty;
          current['revenue'] = (current['revenue'] ?? 0) + revenue;
          allTimeItems[name] = current;
        }
      }
      final topItems = allTimeItems.entries
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
        ..sort(
          (a, b) {
            final revenueCmp = ((b['revenue'] as num?) ?? 0).compareTo(
              (a['revenue'] as num?) ?? 0,
            );
            if (revenueCmp != 0) return revenueCmp;
            return ((b['qty'] as num?) ?? 0).compareTo((a['qty'] as num?) ?? 0);
          },
        );
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

      // 2.3 Prepare per-day sales history (source of truth for mobile month filters).
      final salesHistoryByDate = <String, Map<String, dynamic>>{};
      for (final sale in allSales) {
        final date = (sale['date'] as String?)?.trim();
        if (date == null || date.isEmpty) continue;
        final bucket =
            salesHistoryByDate.putIfAbsent(date, () => {
                  'date': date,
                  'totalRevenue': 0.0,
                  'orderCount': 0,
                  'totalOrders': 0,
                  'cancelledOrders': 0,
                  'cashRevenue': 0.0,
                  'cardRevenue': 0.0,
                  'paymentBreakdown': <String, double>{},
                  'topItems': <Map<String, dynamic>>[],
                  'closedTables': <Map<String, dynamic>>[],
                });
        bucket['totalOrders'] = (bucket['totalOrders'] as int) + 1;

        final isCancelled = sale['isCancelled'] == true;
        final restoredToOrder = sale['restoredToOrder'] == true;
        if (isCancelled) {
          bucket['cancelledOrders'] = (bucket['cancelledOrders'] as int) + 1;
          continue;
        }
        if (restoredToOrder) {
          continue;
        }

        final totalAmount = (sale['totalAmount'] as num?)?.toDouble() ??
            (sale['total'] as num?)?.toDouble() ??
            0.0;
        bucket['totalRevenue'] =
            (bucket['totalRevenue'] as double) + totalAmount;
        bucket['orderCount'] = (bucket['orderCount'] as int) + 1;

        final rawTableNumbers = (sale['tableNumbers'] as List?) ?? const [];
        final tableValues = rawTableNumbers
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final fallbackTable = (sale['tableNumber'] as String?)?.trim() ?? '';
        final floor = (sale['floor'] as String?)?.trim() ?? 'first';
        final orderId = (sale['orderId'] as num?)?.toInt();
        final closedAt = (sale['closedAt'] as String?)?.trim() ?? '';
        final closedTables = (bucket['closedTables'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final label = tableValues.isNotEmpty
            ? tableValues.join(', ')
            : (fallbackTable.isNotEmpty ? fallbackTable : '#${orderId ?? 0}');
        final isFiscal = sale['isFiscal'] != false;
        final salePaymentBreakdown = <String, double>{};
        if (!isFiscal) {
          salePaymentBreakdown['non-fiscal'] = totalAmount;
        } else {
          final saleBreakdown = PaymentUtils.extractBreakdown(sale);
          saleBreakdown.forEach((key, amount) {
            salePaymentBreakdown[key] =
                (salePaymentBreakdown[key] ?? 0) + amount;
          });
        }
        final rawClosedItems = (sale['items'] as List?) ?? const [];
        final normalizedItems = rawClosedItems.whereType<Map>().map((rawItem) {
          final item = Map<String, dynamic>.from(rawItem);
          final qty = (item['quantity'] as num?)?.toInt() ?? 0;
          final unitPrice = (item['unitPrice'] as num?)?.toDouble() ??
              (item['price'] as num?)?.toDouble() ??
              0.0;
          return {
            'name': (item['itemName'] ?? item['name'] ?? '').toString(),
            'qty': qty,
            'unitPrice': double.parse(unitPrice.toStringAsFixed(2)),
            'total': double.parse((qty * unitPrice).toStringAsFixed(2)),
          };
        }).toList();
        closedTables.add({
          'orderId': orderId,
          'tableLabel': label,
          'tableNumbers': tableValues,
          'floor': floor,
          'isFiscal': isFiscal,
          'totalAmount': double.parse(totalAmount.toStringAsFixed(2)),
          'closedAt': closedAt,
          'paymentBreakdown': salePaymentBreakdown.map(
            (key, value) =>
                MapEntry(key, double.parse(value.toStringAsFixed(2))),
          ),
          'items': normalizedItems,
        });
        bucket['closedTables'] = closedTables;

        final paymentBreakdown =
            (bucket['paymentBreakdown'] as Map).cast<String, double>();
        if (!isFiscal) {
          paymentBreakdown['non-fiscal'] =
              (paymentBreakdown['non-fiscal'] ?? 0) + totalAmount;
        } else {
          final breakdown = PaymentUtils.extractBreakdown(sale);
          breakdown.forEach((key, amount) {
            paymentBreakdown[key] = (paymentBreakdown[key] ?? 0) + amount;
          });
        }

        final itemAgg = <String, Map<String, double>>{};
        final existingItems = (bucket['topItems'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        for (final it in existingItems) {
          final name = (it['name'] as String?) ?? '';
          if (name.isEmpty) continue;
          itemAgg[name] = {
            'qty': (it['qty'] as num?)?.toDouble() ?? 0,
            'revenue': (it['revenue'] as num?)?.toDouble() ?? 0,
          };
        }
        final rawItems = (sale['items'] as List?) ?? const [];
        for (final rawItem in rawItems) {
          if (rawItem is! Map) continue;
          final item = Map<String, dynamic>.from(rawItem);
          final name = (item['itemName'] as String?)?.trim();
          if (name == null || name.isEmpty) continue;
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final unitPrice = (item['unitPrice'] as num?)?.toDouble() ??
              (item['price'] as num?)?.toDouble() ??
              0.0;
          final revenue = qty * unitPrice;
          final cur = itemAgg[name] ?? {'qty': 0, 'revenue': 0};
          cur['qty'] = (cur['qty'] ?? 0) + qty;
          cur['revenue'] = (cur['revenue'] ?? 0) + revenue;
          itemAgg[name] = cur;
        }
        final sortedItems = itemAgg.entries
            .map(
              (entry) => {
                'name': entry.key,
                'qty': (entry.value['qty'] ?? 0).round(),
                'revenue':
                    double.parse((entry.value['revenue'] ?? 0).toStringAsFixed(2)),
              },
            )
            .toList()
          ..sort((a, b) => ((b['revenue'] as num?) ?? 0)
              .compareTo((a['revenue'] as num?) ?? 0));
        bucket['topItems'] = sortedItems.take(300).toList();
      }

      for (final entry in salesHistoryByDate.entries) {
        final b = entry.value;
        final pb = (b['paymentBreakdown'] as Map).cast<String, double>();
        pb.forEach((k, v) => pb[k] = double.parse(v.toStringAsFixed(2)));
        b['paymentBreakdown'] = pb;
        b['cashRevenue'] = pb['cash'] ?? 0.0;
        b['cardRevenue'] = pb.entries.fold<double>(
          0,
          (sum, e) => e.key.startsWith('card') ? sum + e.value : sum,
        );
        b['totalRevenue'] =
            double.parse((b['totalRevenue'] as double).toStringAsFixed(2));
        final expenseTotal = DatabaseService.getExpenseTotalForDate(entry.key);
        b['totalExpenses'] = double.parse(expenseTotal.toStringAsFixed(2));
        b['profit'] = double.parse(
          ((b['totalRevenue'] as double) - expenseTotal).toStringAsFixed(2),
        );
      }

      // 3. Sync Menu
      final menu = DatabaseService.getAllMenuCategories()
          .map(
            (cat) => {
              'slug': cat.slug,
              'nameKa': cat.translationsKa['name'] ?? '',
              'nameEn': cat.translationsEn['name'] ?? '',
              'sendToKitchen': cat.sendToKitchen,
              'items':
                  cat.items
                      ?.map(
                        (it) => {
                          'nameKa': it.translationsKa['name'] ?? '',
                          'nameEn': it.translationsEn['name'] ?? '',
                          'price': it.price ?? 0.0,
                          'sendToKitchen': it.sendToKitchen,
                          'variants':
                              it.variants
                                  ?.map(
                                    (v) => {'size': v.size, 'price': v.price},
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
                          'slug': sub.slug,
                          'nameKa': sub.translationsKa['name'] ?? '',
                          'nameEn': sub.translationsEn['name'] ?? '',
                          'items': sub.items
                              .map(
                                (it) => {
                                  'nameKa': it.translationsKa['name'] ?? '',
                                  'nameEn': it.translationsEn['name'] ?? '',
                                  'price': it.price ?? 0.0,
                                  'sendToKitchen': it.sendToKitchen,
                                  'variants':
                                      it.variants
                                          ?.map(
                                            (v) => {
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

      // 4. Sync Staff — PIN + role required for mobile login (server stores bcrypt hash).
      final allUsers = DatabaseService.getAllUsers();
      final staffList = allUsers
          .map(
            (u) => {
              'username': u.username,
              'pin': u.pinCode,
              'role': _staffRoleForSync(u.role),
            },
          )
          .toList();

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

      // 6. Prepare Payload

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
        'expenses': [],
        'staff': staffList,
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
        'openTablesPayable':
            double.parse(openTablesPayable.toStringAsFixed(2)),
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
        '[ManagerSync] Sending ${tables.length} tables, ${reservedTables.length} reserved, ${todayOrders.length} orders, ${staffList.length} staff.',
      );
      for (final t in reservedTables) {
        debugPrint(
          '[ManagerSync]  → ${t['tableNumber']}/${t['floor']}: isReserved=${t['isReserved']}, orderId=${t['activeOrderId']}',
        );
      }

      // 5. Send to NestJS
      final response = await http.post(
        Uri.parse('$serverUrl/sync/manager-data'),
        headers: ApiConfig.posSyncHeaders,
        body: json.encode(payload),
      );

      if (response.statusCode != 201 && response.statusCode != 200) {
        debugPrint(
          'Manager Sync Failed (${response.statusCode}) → $serverUrl: ${response.body}',
        );
      } else {
        debugPrint(
          '[ManagerSync] OK → $serverUrl '
          'callback=${payload['posCallbackUrl'] ?? "missing"}',
        );
      }

      // 6. Sync Audit Reports (fire-and-forget — best effort)
      unawaited(_syncAuditReports());
    } catch (e) {
      debugPrint(
        'Manager Sync Error (cannot reach $serverUrl — is NestJS running on port 3000?): $e',
      );
    }
  }

  /// Push Hive audit reports to the server.
  /// Windows POS is the source of truth, so we always push the full report set.
  /// This guarantees mobile month/history views exactly match Windows, even for
  /// older closed reports that were previously excluded by time-window filtering.
  static Future<void> _syncAuditReports() async {
    try {
      final allReports = DatabaseService.getAuditReports();

      debugPrint(
        '[ManagerSync] Syncing ${allReports.length} / ${allReports.length} audit reports.',
      );

      final payload = {
        'fullSync': true,
        'reports': allReports.map((r) => r.toMap()).toList(),
      };
      debugPrint(
        '[ManagerSync] Sending payload with ${allReports.length} reports to server...',
      );

      final response = await http.post(
        Uri.parse('$serverUrl/sync/audit-reports'),
        headers: ApiConfig.posSyncHeaders,
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        debugPrint(
          '[ManagerSync] Audit sync success: ${data['upserted']} reports updated.',
        );
      } else {
        debugPrint(
          '[ManagerSync] Audit sync failed: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[ManagerSync] Audit sync error: $e');
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
            hint['changeSummary'] = _mergeChangeSummaries(
              hint['changeSummary'] as String?,
              feeSummary,
              preferServiceFee: true,
            ) ?? feeSummary;
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

      _lastOrderItemsByOrderId[id] = nextItems
          .map((i) => i.clone())
          .toList();
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

  static List<Map<String, dynamic>> _collectTableHintsForSync(
    List<Map<String, dynamic>> tablesPayload,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    void addHint(Map<String, dynamic> hint) {
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
          'tableNumber': raw['tableNumber'],
          'floor': raw['floor'],
          'changeType': nowOccupied ? 'reserved' : 'freed',
          if (raw['activeOrderId'] != null) 'activeOrderId': raw['activeOrderId'],
          if (raw['currentBill'] != null) 'currentBill': raw['currentBill'],
          'occurredAt': occurredAt,
        });
      }
      _lastTableOccupiedByKey[key] = nowOccupied;
    }

    _lastTableOccupiedByKey.removeWhere((k, _) => !seen.contains(k));
    return touched;
  }

  /// Maps Hive user roles to backend [StaffRole] enum values.
  static String _staffRoleForSync(String role) {
    return StaffRole.toApi(role);
  }
}
