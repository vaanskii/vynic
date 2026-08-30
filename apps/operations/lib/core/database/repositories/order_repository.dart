import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table_ref.dart';

import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import 'audit_repository.dart';
import 'business_day_repository.dart';
import '../database_core.dart';
import 'reservation_repository.dart';
import 'settings_repository.dart';
import 'table_repository.dart';

/// Order lifecycle: creation (dine-in, takeaway, package, mobile upserts),
/// updates, deletion/cleanup, and item mutations.
class OrderRepository {
  OrderRepository._();

  // Get next order ID
  static int _getNextOrderId() {
    final stored = DatabaseCore.settingsBox?.get('lastOrderId') as int?;
    var maxExisting = 0;
    if (DatabaseCore.orderBox != null && DatabaseCore.orderBox!.isNotEmpty) {
      maxExisting = DatabaseCore.orderBox!.values
          .map((o) => o.orderId)
          .reduce((a, b) => a > b ? a : b);
    }
    final base = [stored ?? 0, maxExisting].reduce((a, b) => a > b ? a : b);
    return base + 1;
  }

  // Create a new order
  static Future<Order> createOrder({
    required List<String> tableNumbers,
    required String floor,
    required String createdBy,
    required List<OrderItem> items,
    bool? includeServiceFee,
    bool createReservationRecord = true,
  }) async {
    final normalizedTables = <String>[];
    final seenTables = <String>{};
    for (final raw in tableNumbers) {
      final normalized = TableRepository.normalizeTableIdentifier(raw, floor);
      if (normalized == null) {
        continue;
      }
      if (seenTables.add(normalized)) {
        normalizedTables.add(normalized);
      }
    }

    if (normalizedTables.isEmpty) {
      throw ArgumentError('Select at least one table');
    }

    for (final tableNumber in normalizedTables) {
      final table = TableRepository.getTable(tableNumber, floor);
      if (table != null && table.isReserved) {
        final details = StringBuffer(
          'Table $tableNumber on $floor floor is busy',
        );
        if (table.activeOrderId != null) {
          details.write(' (order #${table.activeOrderId})');
        } else if (table.reservationId != null) {
          details.write(' (reservation ${table.reservationId})');
        }
        throw StateError(details.toString());
      }
    }

    final orderTableNumbers = List<String>.from(normalizedTables);
    final orderId = _getNextOrderId();
    final shouldIncludeServiceFee =
        includeServiceFee ?? SettingsRepository.defaultIncludeServiceFee();
    final order = Order(
      orderId: orderId,
      tableNumbers: orderTableNumbers,
      floor: floor,
      items: items,
      totalAmount: 0,
      createdAt: BusinessDayRepository.getCurrentDateTime(),
      createdBy: createdBy,
      status: OrderStatus.pending.storageValue,
      includeServiceFee: shouldIncludeServiceFee,
      openedByUserId: createdBy, // Set owner when table is created
    );
    order.recalculateTotal();

    await DatabaseCore.orderBox!.add(order);
    await DatabaseCore.settingsBox?.put('lastOrderId', orderId);

    // Reserve tables
    for (final tableNumber in orderTableNumbers) {
      await TableRepository.reserveTable(
        tableNumber: tableNumber,
        floor: floor,
        username: createdBy,
        orderId: orderId,
        reservationId: null,
      );
    }

    if (createReservationRecord) {
      final tableRefs = _walkInTableRefs(orderTableNumbers, floor);

      final currentDate = BusinessDayRepository.getCurrentDate();
      final currentTime = BusinessDayRepository.getCurrentDateTime();
      final timeString =
          '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}';

      await ReservationRepository.createReservation(
        customerName: 'Walk-in',
        customerPhone: '-',
        tableRefs: tableRefs,
        reservationDate: currentDate,
        reservationTime: timeString,
        numberOfGuests: 0,
        notes: 'Order #$orderId',
        createdBy: createdBy,
        linkedOrderId: orderId,
      );
    }

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': orderId},
      ),
    );

    debugPrint('[Audit] Logging ORDER_CREATED for order $orderId');
    unawaited(
      AuditEventService.logEvent(
        action: 'ORDER_CREATED',
        userId: createdBy,
        data: {
          'orderId': orderId,
          'tableNumbers': tableNumbers,
          'total': order.totalAmount,
          'floor': floor,
        },
      ),
    );

    final creationTimestamp = order.createdAt;
    final initialEvents = order.items
        .map(
          (item) => AuditEvent(
            type: AuditEventType.addItem,
            itemName: item.itemName,
            previousQty: 0,
            newQty: item.quantity,
            waiterId: order.createdBy,
            waiterName: order.createdBy,
            timestamp: creationTimestamp,
          ),
        )
        .toList();

    if (initialEvents.isNotEmpty) {
      await AuditRepository.appendOrderAuditEvents(
        orderId: orderId,
        events: initialEvents,
      );
    } else {
      await AuditRepository.ensureAuditReport(
        orderId: orderId,
        orderSnapshot: order,
      );
    }

    await AuditRepository.finalizeConflictingOpenAuditReports(
      currentOrderId: orderId,
      floor: floor,
      tableNumbers: orderTableNumbers,
      closedBy: createdBy,
    );

    return order;
  }

  static Future<Order> createTakeAwayOrder({
    required String customerName,
    required String customerPhone,
    required String pickupTime,
    String? notes,
    required List<OrderItem> items,
    required String createdBy,
  }) async {
    final orderId = _getNextOrderId();
    final order = Order(
      orderId: orderId,
      tableNumbers: ['TA-$orderId'],
      floor: 'takeaway',
      items: items,
      totalAmount: 0,
      createdAt: BusinessDayRepository.getCurrentDateTime(),
      createdBy: createdBy,
      status: OrderStatus.pending.storageValue,
      includeServiceFee: false,
    );
    order.recalculateTotal();

    await DatabaseCore.orderBox!.add(order);

    final today = BusinessDayRepository.getCurrentDate();
    final totalGuests = items.fold<int>(0, (sum, item) => sum + item.quantity);

    await ReservationRepository.createReservation(
      customerName: customerName,
      customerPhone: customerPhone,
      tableNumbers: const [],
      reservationDate: today,
      reservationTime: pickupTime,
      numberOfGuests: totalGuests,
      notes: notes?.isNotEmpty == true
          ? '${notes!.trim()} (Order #$orderId)'
          : 'Take-away Order #$orderId',
      createdBy: createdBy,
      preOrderItems: items,
      isTakeAway: true,
      linkedOrderId: orderId,
      status: ReservationStatus.confirmed.storageValue,
    );

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': orderId, 'takeAway': true},
      ),
    );

    unawaited(
      AuditEventService.logEvent(
        action: 'TAKEAWAY_ORDER_CREATED',
        userId: createdBy,
        data: {
          'orderId': orderId,
          'customerName': customerName,
          'total': order.totalAmount,
        },
      ),
    );

    return order;
  }

  /// Mobile/cloud takeaway with a fixed `posOrderId` from the backend counter.
  static Future<Order?> upsertMobileTakeawayOrder({
    required int posOrderId,
    required String customerName,
    required String pickupTime,
    required String waiterName,
    required List<OrderItem> items,
    double? totalAmount,
  }) async {
    final existing = getOrder(posOrderId);
    if (existing != null) {
      existing.items = items;
      if (totalAmount != null) {
        existing.totalAmount = totalAmount;
      } else {
        existing.recalculateTotal();
      }
      existing.updatedAt = BusinessDayRepository.getCurrentDateTime();
      await existing.save();
      return existing;
    }

    final order = Order(
      orderId: posOrderId,
      tableNumbers: ['TA-$posOrderId'],
      floor: 'takeaway',
      items: items,
      totalAmount: totalAmount ?? 0,
      createdAt: BusinessDayRepository.getCurrentDateTime(),
      createdBy: waiterName,
      // Mobile-originated takeaway orders are auto-confirmed (skip manual
      // "შეკვეთის დადასტურება" step on POS) so the kitchen check fires immediately.
      status: OrderStatus.confirmed.storageValue,
      includeServiceFee: false,
    );
    if (totalAmount == null) {
      order.recalculateTotal();
    }

    await DatabaseCore.orderBox!.add(order);
    final lastId = (DatabaseCore.settingsBox?.get('lastOrderId') as int?) ?? 0;
    if (posOrderId > lastId) {
      await DatabaseCore.settingsBox?.put('lastOrderId', posOrderId);
    }

    final guestCount = items.fold<int>(0, (sum, item) => sum + item.quantity);
    await ReservationRepository.createReservation(
      customerName: customerName.isNotEmpty ? customerName : 'Takeaway',
      customerPhone: '-',
      tableNumbers: const [],
      reservationDate: BusinessDayRepository.getCurrentDate(),
      reservationTime: pickupTime,
      numberOfGuests: guestCount > 0 ? guestCount : 1,
      notes: 'Take-away Order #$posOrderId (mobile)',
      createdBy: waiterName,
      preOrderItems: items,
      isTakeAway: true,
      linkedOrderId: posOrderId,
      status: ReservationStatus.confirmed.storageValue,
    );

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': posOrderId, 'takeAway': true, 'source': 'mobile'},
      ),
    );

    return order;
  }

  /// Mobile/cloud dine-in (walk-in) order with a fixed `posOrderId`. Reserves
  /// the chosen tables and records a walk-in reservation, mirroring a POS
  /// walk-in created locally.
  static Future<Order?> upsertMobileDineInOrder({
    required int posOrderId,
    required List<String> tableNumbers,
    required String floor,
    required String waiterName,
    required List<OrderItem> items,
    int guestCount = 0,
    double? totalAmount,
  }) async {
    final existing = getOrder(posOrderId);
    if (existing != null) {
      existing.items = items;
      if (totalAmount != null) {
        existing.totalAmount = totalAmount;
      } else {
        existing.recalculateTotal();
      }
      existing.updatedAt = BusinessDayRepository.getCurrentDateTime();
      await existing.save();
      return existing;
    }

    final normalizedTables = <String>[];
    final seenTables = <String>{};
    for (final raw in tableNumbers) {
      final normalized = TableRepository.normalizeTableIdentifier(raw, floor);
      if (normalized == null) continue;
      if (seenTables.add(normalized)) {
        normalizedTables.add(normalized);
      }
    }
    if (normalizedTables.isEmpty) {
      return null;
    }

    final order = Order(
      orderId: posOrderId,
      tableNumbers: normalizedTables,
      floor: floor,
      items: items,
      totalAmount: totalAmount ?? 0,
      createdAt: BusinessDayRepository.getCurrentDateTime(),
      createdBy: waiterName,
      // Mobile-originated walk-in orders are auto-confirmed (skip manual
      // "შეკვეთის დადასტურება" step on POS) so the kitchen check fires immediately.
      status: OrderStatus.confirmed.storageValue,
      includeServiceFee: false,
      openedByUserId: waiterName,
    );
    if (totalAmount == null) {
      order.recalculateTotal();
    }

    await DatabaseCore.orderBox!.add(order);
    final lastId = (DatabaseCore.settingsBox?.get('lastOrderId') as int?) ?? 0;
    if (posOrderId > lastId) {
      await DatabaseCore.settingsBox?.put('lastOrderId', posOrderId);
    }

    for (final tableNumber in normalizedTables) {
      await TableRepository.reserveTable(
        tableNumber: tableNumber,
        floor: floor,
        username: waiterName,
        orderId: posOrderId,
        reservationId: null,
      );
    }

    final tableRefs = _walkInTableRefs(normalizedTables, floor);
    final currentTime = BusinessDayRepository.getCurrentDateTime();
    final timeString =
        '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}';
    await ReservationRepository.createReservation(
      customerName: 'Walk-in',
      customerPhone: '-',
      tableRefs: tableRefs,
      reservationDate: BusinessDayRepository.getCurrentDate(),
      reservationTime: timeString,
      numberOfGuests: guestCount,
      notes: 'Order #$posOrderId',
      createdBy: waiterName,
      preOrderItems: items,
      linkedOrderId: posOrderId,
      status: ReservationStatus.confirmed.storageValue,
    );

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': posOrderId, 'source': 'mobile'},
      ),
    );

    return order;
  }

  static Future<Order> createOrderForPackage({
    required Package package,
    required List<String> tableNumbers,
    required String floor,
    required int guestCount,
    required String createdBy,
  }) async {
    if (guestCount <= 0) {
      throw ArgumentError('Guest count must be greater than zero');
    }

    final uniqueTables = <String>[];
    for (final raw in tableNumbers) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (!uniqueTables.contains(trimmed)) {
        uniqueTables.add(trimmed);
      }
    }

    if (uniqueTables.isEmpty) {
      throw ArgumentError('Select at least one table');
    }

    if (!package.isActive) {
      throw StateError('Activate the package before assigning it to tables');
    }

    if (package.allowedTables.isNotEmpty) {
      final disallowed = uniqueTables
          .where((table) => !package.allowedTables.contains(table))
          .toList();
      if (disallowed.isNotEmpty) {
        throw StateError(
          'Package is not available for tables ${disallowed.join(", ")}',
        );
      }
    }

    final conflictedTables = <String>{};
    for (final order in DatabaseCore.orderBox!.values) {
      if (!isOrderStatusActive(order.status)) {
        continue;
      }
      if (order.floor != floor) {
        continue;
      }
      if (order.tableNumbers.any(uniqueTables.contains)) {
        conflictedTables.addAll(
          order.tableNumbers.where(uniqueTables.contains),
        );
      }
    }

    if (conflictedTables.isNotEmpty) {
      final sorted = conflictedTables.toList()..sort();
      final suffix = sorted.length > 1 ? 's' : '';
      final verb = sorted.length > 1 ? 'have' : 'has';
      throw StateError(
        'Table$suffix ${sorted.join(", ")} already $verb an active order',
      );
    }

    final includeServiceForPackage =
        SettingsRepository.defaultIncludeServiceFee();

    final order = await createOrder(
      tableNumbers: uniqueTables,
      floor: floor,
      createdBy: createdBy,
      items: <OrderItem>[],
      includeServiceFee: includeServiceForPackage,
    );

    final packageItems = package.items
        .map(
          (item) => OrderItem(
            itemKey: item.itemKey,
            itemName: item.itemName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            total: double.parse(
              (item.unitPrice * item.quantity).toStringAsFixed(2),
            ),
          ),
        )
        .toList();

    order.packageId = package.packageId;
    order.packageName = package.name;
    order.packageUnitPrice = package.pricePerPerson;
    order.packageGuestCount = guestCount;
    order.packageItems = packageItems;
    order.packagePrice = double.parse(
      (package.pricePerPerson * guestCount).toStringAsFixed(2),
    );
    order.includeServiceFee = includeServiceForPackage;
    order.updatedAt = BusinessDayRepository.getCurrentDateTime();

    await updateOrder(order);
    await updateOrderStatus(
      orderId: order.orderId,
      status: OrderStatus.confirmed.storageValue,
    );

    return order;
  }

  // Get order by ID
  static Order? getOrder(int orderId) {
    try {
      return DatabaseCore.orderBox!.values.firstWhere(
        (order) => order.orderId == orderId,
      );
    } catch (e) {
      return null;
    }
  }

  // Get all orders
  static List<Order> getAllOrders() {
    return DatabaseCore.orderBox!.values.toList();
  }

  static bool isOrderStatusActive(String status) {
    final normalized = status.toLowerCase();
    return normalized != 'paid' &&
        normalized != 'cancelled' &&
        normalized != 'closed';
  }

  // Get active orders (not paid or cancelled)
  static List<Order> getActiveOrders() {
    return DatabaseCore.orderBox!.values.where((order) {
      return isOrderStatusActive(order.status);
    }).toList();
  }

  // Update order
  static Future<void> updateOrder(
    Order order, {
    bool? previousIncludeServiceFee,
  }) async {
    order.recalculateTotal();

    Order? original;
    if (order.isInBox) {
      original = order;
    } else {
      try {
        original = DatabaseCore.orderBox!.values.firstWhere(
          (o) => o.orderId == order.orderId,
        );
      } catch (e) {
        // If not found, we can't update
        return;
      }
    }

    final prevIncludeServiceFee =
        previousIncludeServiceFee ?? original.includeServiceFee;

    if (original != order) {
      original.items = order.items;
      original.totalAmount = order.totalAmount;
      original.includeServiceFee = order.includeServiceFee;
      original.discountAmount = order.discountAmount;
      original.manualAdjustmentAmount = order.manualAdjustmentAmount;
      original.updatedAt = order.updatedAt;
      original.status = order.status;
      original.paymentMethod = order.paymentMethod;
      original.closedAt = order.closedAt;
      original.packageId = order.packageId;
      original.packageName = order.packageName;
      original.packagePrice = order.packagePrice;
      original.packageItems = order.packageItems;
      original.packageUnitPrice = order.packageUnitPrice;
      original.packageGuestCount = order.packageGuestCount;
    }

    await original.save();
    final serviceFeeChanged =
        original.includeServiceFee != prevIncludeServiceFee;
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'updated',
        payload: {
          'orderId': order.orderId,
          if (serviceFeeChanged) 'serviceFeeChanged': true,
        },
      ),
    );
  }

  // Update order status
  static Future<void> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      order.updateStatus(status);
      await order.save();

      // If order is paid or cancelled, free the tables
      if (status == 'paid' || status == 'cancelled') {
        for (final tableNumber in order.tableNumbers) {
          await TableRepository.freeTable(
            tableNumber: tableNumber,
            floor: order.floor,
          );
        }
      }
    }
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'status_changed',
        payload: {'orderId': orderId, 'status': status},
      ),
    );
  }

  // Hard delete an order (admin only) and release all related resources
  static Future<bool> deleteOrderAndCleanup({
    required int orderId,
    required String deletedBy,
    bool cancelLinkedReservation = true,
  }) async {
    try {
      final order = getOrder(orderId);
      if (order == null) {
        return false;
      }

      // Free all tables associated with this order
      for (final tableNumber in order.tableNumbers) {
        await TableRepository.freeTable(
          tableNumber: tableNumber,
          floor: order.floor,
        );
      }

      // Cancel any linked reservation so it does not block day-close
      if (cancelLinkedReservation) {
        await ReservationRepository.cancelReservationByOrderId(orderId);
      }

      // Remove audit report snapshot if it exists
      final auditKey = AuditRepository.buildAuditReportKey(orderId);
      if (DatabaseCore.auditLogBox != null &&
          DatabaseCore.auditLogBox!.containsKey(auditKey)) {
        await DatabaseCore.auditLogBox!.delete(auditKey);
      }

      // Delete the order record itself
      await order.delete();

      SyncHub.notify(
        SyncEvent(
          type: SyncEventType.orders,
          action: 'deleted',
          payload: {'orderId': orderId, 'deletedBy': deletedBy},
        ),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  // Bulk delete all open orders for a specific date. Used by admin to fix stuck day-close.
  static Future<int> deleteOpenOrdersForDate({
    required DateTime date,
    required String deletedBy,
    bool includeTakeAway = true,
  }) async {
    final targetKey = date.toIso8601String().split('T')[0];
    final allOrders = getAllOrders();

    int deletedCount = 0;

    for (final order in allOrders) {
      final status = order.status.toLowerCase();
      if (status == 'closed' || status == 'cancelled') {
        continue;
      }

      final orderKey = order.createdAt.toIso8601String().split('T')[0];
      if (orderKey != targetKey) {
        continue;
      }

      if (!includeTakeAway) {
        final floor = order.floor.toLowerCase();
        final isTakeAway =
            floor == 'takeaway' ||
            floor == 'take-away' ||
            floor.contains('take away');
        if (isTakeAway) {
          continue;
        }
      }

      final success = await deleteOrderAndCleanup(
        orderId: order.orderId,
        deletedBy: deletedBy,
      );
      if (success) {
        deletedCount++;
      }
    }

    return deletedCount;
  }

  // Add item to order
  static Future<void> addItemToOrder({
    required int orderId,
    required OrderItem item,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      order.addItem(item);
      await updateOrder(order);
    }
  }

  // Remove item from order
  static Future<void> removeItemFromOrder({
    required int orderId,
    required String itemKey,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      order.removeItem(itemKey);
      await updateOrder(order);
    }
  }

  // Update item quantity in order
  static Future<void> updateOrderItemQuantity({
    required int orderId,
    required String itemKey,
    required int quantity,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      order.updateItemQuantity(itemKey, quantity);
      await updateOrder(order);
    }
  }

  /// Table refs for a walk-in's linked reservation record. Order table
  /// entries are either display labels ('Table N' = first floor,
  /// 'VIP Zone N' = second floor) or bare numbers on [floor]; non-numeric
  /// entries (e.g. takeaway 'TA-...') carry no table.
  static List<TableRef> _walkInTableRefs(
    List<String> tableNames,
    String floor,
  ) {
    final refs = <TableRef>[];
    for (final tableName in tableNames) {
      if (tableName.startsWith('Table ')) {
        final number = tableName.replaceAll('Table ', '').trim();
        if (int.tryParse(number) != null) {
          refs.add(TableRef(floor: 'first', tableNumber: number));
        }
      } else if (tableName.startsWith('VIP Zone ')) {
        final number = tableName.replaceAll('VIP Zone ', '').trim();
        if (int.tryParse(number) != null) {
          refs.add(TableRef(floor: 'second', tableNumber: number));
        }
      } else {
        final number = tableName.trim();
        if (int.tryParse(number) != null) {
          refs.add(TableRef(floor: floor, tableNumber: number));
        }
      }
    }
    return refs;
  }
}
