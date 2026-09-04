import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/package.dart';

import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'package:vynic/core/services/audit/audit_order_diff_service.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/order_audit_details.dart';
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

  /// Opens a table Order.
  ///
  /// The report's first event is the creation itself: `CREATE_WALKIN` for an
  /// ordinary table (or a Package carrier when [forPackage]), or
  /// `ACTIVATE_RESERVATION` when [activatesReservationId] names the genuine
  /// booking being seated. The initial `ADD_ITEM` rows follow it at the same
  /// instant. [source] says which channel opened it; the actor is [createdBy].
  static Future<Order> createOrder({
    required List<String> tableNumbers,
    required String floor,
    required String createdBy,
    required List<OrderItem> items,
    bool? includeServiceFee,
    AuditSource source = AuditSource.pos,
    bool forPackage = false,
    String? activatesReservationId,
    String? reservationCustomerName,
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
        entityType: GlobalAuditEntity.order,
        entityId: '$orderId',
        data: {
          'orderId': orderId,
          'tableNumbers': tableNumbers,
          'total': order.totalAmount,
          'floor': floor,
        },
      ),
    );

    final isActivation =
        activatesReservationId != null && activatesReservationId.isNotEmpty;
    final creationEvent = AuditEvent(
      type: isActivation
          ? AuditEventType.activateReservation
          : AuditEventType.createWalkIn,
      itemName: OrderAuditDetails.orderItemName,
      previousQty: 0,
      newQty: 0,
      waiterId: createdBy,
      waiterName: createdBy,
      timestamp: order.createdAt,
      details: <String, dynamic>{
        ...OrderAuditDetails.base(
          order: order,
          orderKind: isActivation
              ? OrderAuditDetails.reservation
              : forPackage
              ? OrderAuditDetails.package
              : OrderAuditDetails.walkIn,
          source: source,
          actorId: createdBy,
        ),
        if (isActivation) 'reservationId': activatesReservationId,
        if (isActivation &&
            reservationCustomerName != null &&
            reservationCustomerName.trim().isNotEmpty)
          'customerName': reservationCustomerName.trim(),
        'includeServiceFee': shouldIncludeServiceFee,
      },
    );
    await _appendCreationAudit(
      order: order,
      creationEvent: creationEvent,
      actor: createdBy,
    );

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
    AuditSource source = AuditSource.pos,
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
      customerName: customerName,
      customerPhone: customerPhone,
      pickupTime: pickupTime,
    );
    order.recalculateTotal();

    await DatabaseCore.orderBox!.add(order);

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
        entityType: GlobalAuditEntity.order,
        entityId: '$orderId',
        data: {
          'orderId': orderId,
          'customerName': customerName,
          'total': order.totalAmount,
        },
      ),
    );

    // The report exists from the first moment, not from the first later edit.
    await _appendCreationAudit(
      order: order,
      creationEvent: _takeawayCreationEvent(
        order: order,
        source: source,
        actor: createdBy,
      ),
      actor: createdBy,
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
    AuditSource source = AuditSource.manager,
  }) async {
    final existing = getOrder(posOrderId);
    if (existing != null) {
      await _auditManagerItemReplacement(
        order: existing,
        updatedItems: items,
        actor: waiterName,
        source: source,
      );
      existing.items = items;
      existing.customerName = customerName;
      existing.pickupTime = pickupTime;
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
      customerName: customerName,
      pickupTime: pickupTime,
    );
    if (totalAmount == null) {
      order.recalculateTotal();
    }

    await DatabaseCore.orderBox!.add(order);
    final lastId = (DatabaseCore.settingsBox?.get('lastOrderId') as int?) ?? 0;
    if (posOrderId > lastId) {
      await DatabaseCore.settingsBox?.put('lastOrderId', posOrderId);
    }

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': posOrderId, 'takeAway': true, 'source': 'mobile'},
      ),
    );

    await _appendCreationAudit(
      order: order,
      creationEvent: _takeawayCreationEvent(
        order: order,
        source: source,
        actor: waiterName,
      ),
      actor: waiterName,
    );

    return order;
  }

  /// Mobile/cloud dine-in (walk-in) order with a fixed `posOrderId`.
  /// Reserves the chosen tables without manufacturing a Reservation record.
  static Future<Order?> upsertMobileDineInOrder({
    required int posOrderId,
    required List<String> tableNumbers,
    required String floor,
    required String waiterName,
    required List<OrderItem> items,
    int guestCount = 0,
    double? totalAmount,
    AuditSource source = AuditSource.manager,
  }) async {
    final existing = getOrder(posOrderId);
    if (existing != null) {
      await _auditManagerItemReplacement(
        order: existing,
        updatedItems: items,
        actor: waiterName,
        source: source,
      );
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

    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'created',
        payload: {'orderId': posOrderId, 'source': 'mobile'},
      ),
    );

    await _appendCreationAudit(
      order: order,
      creationEvent: AuditEvent(
        type: AuditEventType.createWalkIn,
        itemName: OrderAuditDetails.orderItemName,
        previousQty: 0,
        newQty: 0,
        waiterId: waiterName,
        waiterName: waiterName,
        timestamp: order.createdAt,
        details: <String, dynamic>{
          ...OrderAuditDetails.base(
            order: order,
            orderKind: OrderAuditDetails.walkIn,
            source: source,
            actorId: waiterName,
          ),
          if (guestCount > 0) 'guestCount': guestCount,
          'includeServiceFee': order.includeServiceFee,
        },
      ),
      actor: waiterName,
    );

    return order;
  }

  static Future<Order> createOrderForPackage({
    required Package package,
    required List<String> tableNumbers,
    required String floor,
    required int guestCount,
    required String createdBy,
    AuditSource source = AuditSource.pos,
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
      source: source,
      forPackage: true,
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

    // The package is what the guests are being sold; the report says so
    // rather than showing an empty Order that silently became `confirmed`.
    await _appendCreationAudit(
      order: order,
      creationEvent: AuditEvent(
        type: AuditEventType.applyPackage,
        itemName: package.name,
        previousQty: 0,
        newQty: 0,
        waiterId: createdBy,
        waiterName: createdBy,
        timestamp: OrderAuditDetails.strictlyAfter(
          order.createdAt,
          order.updatedAt ?? order.createdAt,
        ),
        details: <String, dynamic>{
          ...OrderAuditDetails.base(
            order: order,
            orderKind: OrderAuditDetails.package,
            source: source,
            actorId: createdBy,
          ),
          'packageId': package.packageId,
          'packageName': package.name,
          'packageGuestCount': guestCount,
          'packageUnitPrice': package.pricePerPerson,
          'packagePrice': order.packagePrice,
          'packageItems': packageItems
              .map(
                (item) => <String, dynamic>{
                  'itemName': item.itemName,
                  'quantity': item.quantity,
                  'unitPrice': item.unitPrice,
                },
              )
              .toList(growable: false),
        },
      ),
      actor: createdBy,
    );

    await updateOrderStatus(
      orderId: order.orderId,
      status: OrderStatus.confirmed.storageValue,
    );

    return order;
  }

  static AuditEvent _takeawayCreationEvent({
    required Order order,
    required AuditSource source,
    required String actor,
  }) {
    return AuditEvent(
      type: AuditEventType.createTakeaway,
      itemName: OrderAuditDetails.orderItemName,
      previousQty: 0,
      newQty: 0,
      waiterId: actor,
      waiterName: actor,
      timestamp: order.createdAt,
      details: <String, dynamic>{
        ...OrderAuditDetails.base(
          order: order,
          orderKind: OrderAuditDetails.takeaway,
          source: source,
          actorId: actor,
        ),
        if (order.customerName.trim().isNotEmpty)
          'customerName': order.customerName.trim(),
        if (order.customerPhone.trim().isNotEmpty &&
            order.customerPhone.trim() != '-')
          'customerPhone': order.customerPhone.trim(),
        if (order.pickupTime.trim().isNotEmpty)
          'pickupTime': order.pickupTime.trim(),
      },
    );
  }

  /// Writes the creation event followed by one `ADD_ITEM` per initial line,
  /// all at the Order's own creation time.
  ///
  /// A report locked by an earlier life of the same id (a repair delete
  /// followed by a Manager re-send) cannot take the event; the Order still
  /// exists and creation is not rolled back over its trail.
  static Future<void> _appendCreationAudit({
    required Order order,
    required AuditEvent creationEvent,
    required String actor,
  }) async {
    final initialEvents = order.items
        .map(
          (item) => AuditEvent(
            type: AuditEventType.addItem,
            itemName: item.itemName,
            previousQty: 0,
            newQty: item.quantity,
            waiterId: actor,
            waiterName: actor,
            timestamp: order.createdAt,
          ),
        )
        .toList();
    try {
      await AuditRepository.appendOrderAuditEvents(
        orderId: order.orderId,
        events: [creationEvent, ...initialEvents],
      );
    } on StateError catch (e) {
      if (!e.toString().toLowerCase().contains('locked')) rethrow;
      debugPrint(
        '[Audit] Report for order ${order.orderId} is locked; '
        'creation event not recorded',
      );
    }
  }

  /// The item audit for a Manager upsert that lands on an Order that already
  /// exists.
  ///
  /// A Manager upsert replaces the Order's whole item collection, so what the
  /// operator actually did — added a line, cut a quantity, removed a line —
  /// is only visible as the difference against what is stored. Without this,
  /// a Manager edit changed the check and left nothing on the report, while
  /// the same edit made at the POS wrote `ADD_ITEM` / `REDUCE_QTY` /
  /// `DELETE_ITEM`.
  ///
  /// Diffed against storage, so a redelivered identical payload produces no
  /// events at all — which is what makes at-least-once delivery safe here.
  /// Reuses [AuditOrderDiffService], the same diff `ORDER_UPDATE` already
  /// uses; there is deliberately no second implementation of these rules.
  static Future<void> _auditManagerItemReplacement({
    required Order order,
    required List<OrderItem> updatedItems,
    required String actor,
    required AuditSource source,
  }) async {
    final events = AuditOrderDiffService.buildEvents(
      previousItems: order.items,
      updatedItems: updatedItems,
      performerId: actor,
      performerName: actor,
      timestamp: BusinessDayRepository.getCurrentDateTime(),
    );
    if (events.isEmpty) return;
    try {
      await AuditRepository.appendOrderAuditEvents(
        orderId: order.orderId,
        events: [
          for (final event in events)
            event.copyWith(
              details: <String, dynamic>{
                ...?event.details,
                AuditSource.detailsKey: source.wireValue,
                'actorId': actor,
                'actorName': actor,
              },
            ),
        ],
      );
    } on StateError catch (e) {
      // A closed Order's report is locked. The Order itself is not rolled
      // back over an event that cannot be filed.
      if (!e.toString().toLowerCase().contains('locked')) rethrow;
      debugPrint(
        '[Audit] Report for order ${order.orderId} is locked; '
        'Manager item changes not recorded',
      );
    }
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

  /// Low-level status assignment.
  ///
  /// Cancellation is not a status write: it is `CancelOrderTransaction.run`,
  /// which also leaves the typed audit event and the cancelled Sale record.
  /// Every operational cancel path uses that; this setter remains for kitchen
  /// confirmation and for callers that already hold the durable history.
  ///
  /// The last line of defence against an unreadable status reaching storage:
  /// a value [OrderStatus.fromStorage] cannot parse is refused outright, and
  /// what is written is the canonical [OrderStatus.storageValue] rather than
  /// the caller's spelling, so `paid` and `canceled` cannot enter as new rows.
  /// Remote callers are additionally narrowed by `RemoteOrderStatusRule`
  /// before they ever reach here.
  static Future<void> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    final parsed = OrderStatus.fromStorage(status);
    if (parsed == OrderStatus.unknown) {
      throw ArgumentError.value(
        status,
        'status',
        'not an order status this system stores',
      );
    }
    final canonical = parsed.storageValue;
    final order = getOrder(orderId);
    if (order != null) {
      order.updateStatus(canonical);
      await order.save();

      // A settled order no longer holds its tables. Previously spelled
      // `paid || cancelled`; `paid` now normalizes to `closed`, and no
      // production caller reaches this with `closed` — closing owns its own
      // table release inside `CloseTableTransaction`.
      if (parsed.isTerminal) {
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
        payload: {'orderId': orderId, 'status': canonical},
      ),
    );
  }

  /// Physically removes an Order row. Repair only.
  ///
  /// This is not cancellation and no operational screen or command reaches
  /// it: a waiter, manager or administrator cancelling an Order goes through
  /// `CancelOrderTransaction`, which keeps the Order, its audit report and a
  /// non-revenue cancelled Sale as history. Close Day deletes already-closed
  /// rows directly because their Sale is the durable record.
  ///
  /// The per-Order audit report is deliberately left in place — deleting the
  /// row is a repair of corrupt data, not a licence to erase what happened —
  /// and the removal itself is written to the append-only action log.
  static Future<bool> hardDeleteOrderForRepair({
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
        await ReservationRepository.cancelReservationByOrderId(
          orderId,
          actorId: deletedBy,
          source: AuditSource.developer,
          reason: 'Order hard-deleted for repair',
        );
      }

      final snapshot = <String, dynamic>{
        'orderId': orderId,
        'tableNumbers': List<String>.from(order.tableNumbers),
        'floor': order.floor,
        'status': order.status,
        'totalAmount': order.totalAmount,
        'createdBy': order.createdBy,
        'createdAt': order.createdAt.toIso8601String(),
      };

      // Delete the order record itself
      await order.delete();

      unawaited(
        AuditEventService.logEvent(
          action: 'ORDER_HARD_DELETED',
          userId: deletedBy,
          entityType: GlobalAuditEntity.order,
          entityId: '$orderId',
          data: snapshot,
        ),
      );

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
}
