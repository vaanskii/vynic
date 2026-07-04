import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';

import 'package:vynic/core/services/sync/sync_events.dart';
import 'business_day_repository.dart';
import '../database_core.dart';
import 'reservation_repository.dart';
import 'order_repository.dart';

/// Floor plan and live table state: layout, reserve/free, stale-lock
/// analysis, and table-identifier normalization.
class TableRepository {
  TableRepository._();

  static const List<String> _firstFloorTableNumbers = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
  ];

  static const List<String> _secondFloorTableNumbers = ['1', '2', '3', '4'];

  static const Map<String, List<String>> _tableLayout = {
    'first': _firstFloorTableNumbers,
    'second': _secondFloorTableNumbers,
  };

  static Map<String, List<String>> getTableLayout() {
    return {
      for (final entry in _tableLayout.entries)
        entry.key: List<String>.from(entry.value),
    };
  }

  static List<String> getAllTableNumbers() {
    return _tableLayout.values.expand((tables) => tables).toList();
  }

  // Initialize default tables
  static Future<void> initializeTables() async {
    for (final tableNumber in _firstFloorTableNumbers) {
      final table = TableModel(
        tableNumber: tableNumber,
        floor: 'first',
        isReserved: false,
      );
      await DatabaseCore.tableBox!.add(table);
    }

    for (final tableNumber in _secondFloorTableNumbers) {
      final table = TableModel(
        tableNumber: tableNumber,
        floor: 'second',
        isReserved: false,
      );
      await DatabaseCore.tableBox!.add(table);
    }
  }

  static Future<void> ensureTableLayoutConsistency() async {
    if (DatabaseCore.tableBox == null) {
      return;
    }

    final allowedByFloor = <String, Set<String>>{};
    for (final entry in _tableLayout.entries) {
      allowedByFloor[entry.key] = entry.value.toSet();
    }

    final invalidKeys = <dynamic>[];
    for (final key in DatabaseCore.tableBox!.keys) {
      final TableModel? table = DatabaseCore.tableBox!.get(key);
      if (table == null) {
        invalidKeys.add(key);
        continue;
      }

      final allowedSet = allowedByFloor[table.floor];
      final isAllowed =
          allowedSet != null && allowedSet.contains(table.tableNumber);
      if (!isAllowed) {
        invalidKeys.add(key);
      }
    }

    if (invalidKeys.isNotEmpty) {
      await DatabaseCore.tableBox!.deleteAll(invalidKeys);
    }

    for (final entry in _tableLayout.entries) {
      for (final tableNumber in entry.value) {
        if (getTable(tableNumber, entry.key) == null) {
          final table = TableModel(
            tableNumber: tableNumber,
            floor: entry.key,
            isReserved: false,
          );
          await DatabaseCore.tableBox!.add(table);
        }
      }
    }
  }

  // Get all tables
  static List<TableModel> getAllTables() {
    return DatabaseCore.tableBox!.values.toList();
  }

  // Get tables by floor
  static List<TableModel> getTablesByFloor(String floor) {
    return DatabaseCore.tableBox!.values
        .where((table) => table.floor == floor)
        .toList();
  }

  // Get table by number and floor
  static TableModel? getTable(String tableNumber, String floor) {
    try {
      return DatabaseCore.tableBox!.values.firstWhere(
        (table) => table.tableNumber == tableNumber && table.floor == floor,
      );
    } catch (e) {
      return null;
    }
  }

  static bool isTableConfigured({
    required String tableNumber,
    required String floor,
  }) {
    final layout = _tableLayout[floor];
    if (layout == null) {
      return false;
    }
    return layout.contains(tableNumber);
  }

  // Reserve a table
  static Future<void> reserveTable({
    required String tableNumber,
    required String floor,
    required String username,
    required int orderId,
    String? reservationId,
  }) async {
    final table = getTable(tableNumber, floor);
    if (table != null) {
      table.reserve(username, orderId, reservationId: reservationId);
      await table.save();
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.tables,
          action: 'reserved',
          payload: {
            'tableNumber': tableNumber,
            'floor': floor,
            'orderId': orderId,
            if (reservationId != null) 'reservationId': reservationId,
          },
        ),
      );
    }
  }

  // Reserve a table for a reservation (without an order)
  static Future<void> reserveTableForReservation({
    required String tableNumber,
    required String floor,
    required String username,
    required String reservationId,
  }) async {
    final table = getTable(tableNumber, floor);
    if (table != null) {
      table.reserveForReservation(username, reservationId);
      await table.save();
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.tables,
          action: 'reserved',
          payload: {
            'tableNumber': tableNumber,
            'floor': floor,
            'reservationId': reservationId,
          },
        ),
      );
    }
  }

  // Free a table
  static Future<void> freeTable({
    required String tableNumber,
    required String floor,
  }) async {
    final table = getTable(tableNumber, floor);
    if (table != null) {
      table.free();
      await table.save();
      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.tables,
          action: 'freed',
          payload: {'tableNumber': tableNumber, 'floor': floor},
        ),
      );
    }
  }

  static int? _resolveReservationTableNumber(TableModel table) {
    final parsed = int.tryParse(table.tableNumber.trim());
    if (parsed == null) {
      return null;
    }
    if (table.floor == 'second') {
      return parsed + 10;
    }
    return parsed;
  }

  static bool _orderContainsTable(Order order, TableModel table) {
    final identifiers = <String>{};
    final base = table.tableNumber.trim();
    if (base.isEmpty) {
      return false;
    }
    identifiers.add(base);
    identifiers.add('Table $base');
    if (table.floor == 'second') {
      identifiers.add('VIP Zone $base');
      final numeric = int.tryParse(base);
      if (numeric != null) {
        identifiers.add((numeric + 10).toString());
      }
    }
    for (final value in order.tableNumbers) {
      final normalized = value.trim();
      if (identifiers.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  static String? normalizeTableIdentifier(String rawValue, String floor) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('table ')) {
      final extracted = trimmed.substring(6).trim();
      return extracted.isEmpty ? null : extracted;
    }

    if (lower.startsWith('vip zone ')) {
      final extracted = trimmed.substring(9).trim();
      return extracted.isEmpty ? null : extracted;
    }

    final parsed = int.tryParse(trimmed);
    if (parsed != null && floor == 'second' && parsed > 10) {
      return (parsed - 10).toString();
    }

    return trimmed;
  }

  static Map<String, dynamic> _analyzeReservedTable(
    TableModel table,
    String todayKey,
  ) {
    final result = <String, dynamic>{
      'tableNumber': table.tableNumber,
      'floor': table.floor,
      'reservedBy': table.reservedBy,
      'reservedAt': table.reservedAt?.toIso8601String(),
      'activeOrderId': table.activeOrderId,
      'reservationId': table.reservationId,
      'shouldRelease': false,
      'reason': null,
    };

    final orderId = table.activeOrderId;
    bool hasActiveOrder = false;
    if (orderId != null) {
      final order = OrderRepository.getOrder(orderId);
      result['orderStatus'] = order?.status;
      result['orderCreatedAt'] = order?.createdAt.toIso8601String();
      if (order == null) {
        result['shouldRelease'] = true;
        result['reason'] = 'Order #$orderId missing';
        return result;
      }

      final status = order.status.toLowerCase();
      final orderDateKey = order.createdAt.toIso8601String().split('T')[0];
      final isActiveStatus =
          status != 'closed' && status != 'cancelled' && status != 'paid';
      final includesTable = _orderContainsTable(order, table);

      if (!isActiveStatus) {
        result['shouldRelease'] = true;
        result['reason'] = 'Order #$orderId is $status';
        return result;
      }

      if (orderDateKey != todayKey) {
        result['shouldRelease'] = true;
        result['reason'] = 'Order #$orderId is from $orderDateKey';
        return result;
      }

      if (!includesTable) {
        result['shouldRelease'] = true;
        result['reason'] = 'Order #$orderId no longer uses table';
        return result;
      }

      hasActiveOrder = true;
    }

    final reservationId = table.reservationId;
    if (reservationId != null) {
      final reservation = ReservationRepository.findReservationById(
        reservationId,
      );
      result['reservationStatus'] = reservation?.status;
      result['reservationDate'] = reservation?.reservationDate
          .toIso8601String();
      if (reservation == null) {
        if (!hasActiveOrder) {
          result['shouldRelease'] = true;
          result['reason'] = 'Reservation $reservationId missing';
        }
        return result;
      }

      if (hasActiveOrder) {
        return result;
      }

      final status = reservation.status.toLowerCase();
      final allowedStatuses = {'in-progress', 'confirmed', 'preparing'};
      if (!allowedStatuses.contains(status)) {
        result['shouldRelease'] = true;
        result['reason'] = 'Reservation $reservationId is $status';
        return result;
      }

      final resDateKey = reservation.reservationDate.toIso8601String().split(
        'T',
      )[0];
      if (resDateKey != todayKey) {
        result['shouldRelease'] = true;
        result['reason'] = 'Reservation $reservationId date $resDateKey';
        return result;
      }

      final normalizedTable = _resolveReservationTableNumber(table);
      if (normalizedTable == null ||
          !reservation.tableNumbers.contains(normalizedTable)) {
        result['shouldRelease'] = true;
        result['reason'] = 'Reservation $reservationId lost table link';
        return result;
      }

      return result;
    }

    if (!hasActiveOrder) {
      result['shouldRelease'] = true;
      result['reason'] = 'No active order or reservation';
    }

    return result;
  }

  static List<Map<String, dynamic>> getReservedTableDiagnostics() {
    if (DatabaseCore.tableBox == null) {
      return const [];
    }
    final todayKey = BusinessDayRepository.getCurrentDate()
        .toIso8601String()
        .split('T')[0];
    return DatabaseCore.tableBox!.values
        .where((table) => table.isReserved)
        .map((table) => _analyzeReservedTable(table, todayKey))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> releaseStaleReservedTables() async {
    if (DatabaseCore.tableBox == null) {
      return const [];
    }
    final todayKey = BusinessDayRepository.getCurrentDate()
        .toIso8601String()
        .split('T')[0];
    final reservedTables = DatabaseCore.tableBox!.values
        .where((table) => table.isReserved)
        .toList();
    final released = <Map<String, dynamic>>[];

    for (final table in reservedTables) {
      final analysis = _analyzeReservedTable(table, todayKey);
      if (analysis['shouldRelease'] == true) {
        released.add(analysis);
        await freeTable(tableNumber: table.tableNumber, floor: table.floor);
      }
    }

    return released;
  }

  static Future<void> syncTableReservationsForCurrentDate() async {
    if (DatabaseCore.tableBox == null || DatabaseCore.orderBox == null) {
      return;
    }

    final currentDateKey = BusinessDayRepository.getCurrentDate()
        .toIso8601String()
        .split('T')[0];

    // Step 1: clear table locks that do not belong to the selected business date.
    await releaseStaleReservedTables();

    // Step 2: ensure active orders of selected date are reflected on table map.
    final activeOrdersForDate = DatabaseCore.orderBox!.values.where((order) {
      if (!OrderRepository.isOrderStatusActive(order.status)) {
        return false;
      }
      final orderDateKey = order.createdAt.toIso8601String().split('T')[0];
      return orderDateKey == currentDateKey;
    });

    for (final order in activeOrdersForDate) {
      for (final rawTableNumber in order.tableNumbers) {
        final normalizedTableNumber = normalizeTableIdentifier(
          rawTableNumber,
          order.floor,
        );
        if (normalizedTableNumber == null || normalizedTableNumber.isEmpty) {
          continue;
        }

        if (!isTableConfigured(
          tableNumber: normalizedTableNumber,
          floor: order.floor,
        )) {
          continue;
        }

        final table = getTable(normalizedTableNumber, order.floor);
        if (table == null) {
          continue;
        }

        final occupiedByAnotherOrder =
            table.isReserved &&
            table.activeOrderId != null &&
            table.activeOrderId != order.orderId;
        if (occupiedByAnotherOrder) {
          continue;
        }

        final alreadyBoundToOrder =
            table.isReserved && table.activeOrderId == order.orderId;
        if (alreadyBoundToOrder) {
          continue;
        }

        await reserveTable(
          tableNumber: normalizedTableNumber,
          floor: order.floor,
          username: order.createdBy,
          orderId: order.orderId,
        );
      }
    }
  }
}
