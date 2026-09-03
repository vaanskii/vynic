import 'dart:async';
import 'dart:developer' as developer;

import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/contracts/table_identity.dart' as contract;
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';
import 'package:uuid/uuid.dart';

import 'package:vynic/core/services/sync/sync_events.dart';
import 'business_day_repository.dart';
import '../database_core.dart';
import 'error_log_repository.dart';
import 'reservation_repository.dart';
import 'order_repository.dart';
import 'settings_repository.dart';

/// Floor plan and live table state: layout, reserve/free, stale-lock
/// analysis, and table-identifier normalization.
class TableRepository {
  TableRepository._();

  static bool _reportedCorruptLayout = false;
  static const Uuid _uuid = Uuid();

  static RestaurantTableLayout getRestaurantTableLayout() {
    try {
      return SettingsRepository.getActiveTableLayout() ??
          RestaurantTableLayouts.current;
    } catch (error, stackTrace) {
      // A corrupted saved layout must not brick every table screen: fall
      // back to the built-in layout. Reported once per session — this read
      // path is hot and the broken value stays broken until re-saved.
      if (!_reportedCorruptLayout) {
        _reportedCorruptLayout = true;
        developer.log(
          'Saved table layout is corrupted, falling back to default: $error',
          name: 'TableRepository',
          error: error,
          stackTrace: stackTrace,
        );
        unawaited(
          ErrorLogRepository.logError(
            title: 'Saved table layout is corrupted',
            error: error,
            stackTrace: stackTrace,
            context: 'get_restaurant_table_layout',
          ),
        );
      }
      return RestaurantTableLayouts.current;
    }
  }

  /// Live tables (reserved or with an active order) that the given layout
  /// no longer contains. Saving such a layout would strand their orders.
  static List<TableModel> occupiedTablesMissingFromLayout(
    RestaurantTableLayout layout,
  ) {
    if (DatabaseCore.tableBox == null) {
      return const [];
    }
    return [
      for (final table in DatabaseCore.tableBox!.values)
        if ((table.isReserved || table.activeOrderId != null) &&
            layout.tableForLegacy(
                  floor: table.floor,
                  tableNumber: table.tableNumber,
                ) ==
                null)
          table,
    ];
  }

  static Future<void> saveActiveRestaurantTableLayout(
    RestaurantTableLayout layout,
  ) async {
    final currentLayout = getRestaurantTableLayout();
    final canonicalLayout = layout.withCanonicalTableIds(
      generateId: (table) {
        final existing = currentLayout.tableForLegacy(
          floor: table.legacyFloor,
          tableNumber: table.legacyTableNumber,
        );
        return existing != null && contract.isCanonicalTableId(existing.id)
            ? existing.id
            : _uuid.v4();
      },
    );
    final occupied = occupiedTablesMissingFromLayout(canonicalLayout);
    if (occupied.isNotEmpty) {
      final labels = occupied
          .map((table) => '${table.floor}/${table.tableNumber}')
          .join(', ');
      throw StateError(
        'Layout removes occupied tables: $labels. '
        'Close or move their orders first.',
      );
    }
    await SettingsRepository.saveActiveTableLayout(canonicalLayout);
    await ensureTableLayoutConsistency();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.tables,
        action: 'layout_changed',
        payload: {'layoutId': layout.id, 'layoutName': layout.name},
      ),
    );
  }

  /// Persists UUIDs for every existing physical table exactly once.
  ///
  /// The active layout already owns stable table definitions and visual
  /// objects refer to those definitions by ID. Upgrading that existing ID is
  /// therefore additive: Hive table state, orders and reservations keep using
  /// their floor/number aliases while sync gains an immutable UUID.
  static Future<void> ensureCanonicalTableIdentity() async {
    final layout = getRestaurantTableLayout();
    final canonicalLayout = layout.withCanonicalTableIds(
      generateId: (_) => _uuid.v4(),
    );
    if (identical(layout, canonicalLayout)) {
      return;
    }
    await SettingsRepository.saveActiveTableLayout(canonicalLayout);
  }

  static Future<void> clearActiveRestaurantTableLayout() async {
    final previous = getRestaurantTableLayout();
    await SettingsRepository.clearActiveTableLayout();
    final reset = getRestaurantTableLayout().withCanonicalTableIds(
      generateId: (table) {
        final existing = previous.tableForLegacy(
          floor: table.legacyFloor,
          tableNumber: table.legacyTableNumber,
        );
        return existing != null && contract.isCanonicalTableId(existing.id)
            ? existing.id
            : _uuid.v4();
      },
    );
    await SettingsRepository.saveActiveTableLayout(reset);
    await ensureTableLayoutConsistency();
    final layout = getRestaurantTableLayout();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.tables,
        action: 'layout_reset',
        payload: {'layoutId': layout.id, 'layoutName': layout.name},
      ),
    );
  }

  static Map<String, List<String>> getTableLayout() {
    final layout = getRestaurantTableLayout().legacyTableLayout();
    return {
      for (final entry in layout.entries) entry.key: [...entry.value],
    };
  }

  static List<String> getAllTableNumbers() {
    return getRestaurantTableLayout().tables
        .map((table) => table.legacyTableNumber)
        .toList();
  }

  // Initialize default tables
  static Future<void> initializeTables() async {
    for (final tableDefinition in getRestaurantTableLayout().tables) {
      final table = TableModel(
        tableNumber: tableDefinition.legacyTableNumber,
        floor: tableDefinition.legacyFloor,
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
    for (final entry in getTableLayout().entries) {
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
        if (table.isReserved || table.activeOrderId != null) {
          // Never drop a live table, even if the layout no longer has it —
          // its order/reservation would be stranded. It gets cleaned up on
          // a later pass once freed.
          developer.log(
            'Keeping occupied table ${table.floor}/${table.tableNumber} '
            'that is missing from the active layout',
            name: 'TableRepository',
          );
          continue;
        }
        invalidKeys.add(key);
      }
    }

    if (invalidKeys.isNotEmpty) {
      await DatabaseCore.tableBox!.deleteAll(invalidKeys);
    }

    for (final entry in getTableLayout().entries) {
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
    return getRestaurantTableLayout().tableForLegacy(
          floor: floor,
          tableNumber: tableNumber,
        ) !=
        null;
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

      final tableRef = ReservationTableAvailability.refOfTableModel(table);
      if (!ReservationTableAvailability.tableRefsOf(
        reservation,
      ).contains(tableRef)) {
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
