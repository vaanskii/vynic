import '../transactions/cancel_order_transaction.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
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
import 'order_table_mutation_repository.dart';

/// Order lifecycle: creation (dine-in, takeaway, package, mobile upserts),
/// updates, deletion/cleanup, and item mutations.
class OrderRepository {
  OrderRepository._();

  static Map<String, dynamic> _packageRequest(Package p) => {
    'id': p.packageId,
    'name': p.name,
    'description': p.description,
    'pricePerPerson': p.pricePerPerson,
    'isActive': p.isActive,
    'allowedTables': List.of(p.allowedTables),
    'servingSize': p.servingSize,
    'items': [
      for (final i in p.items)
        {
          'itemKey': i.itemKey,
          'itemName': i.itemName,
          'quantity': i.quantity,
          'unitPrice': i.unitPrice,
          'menuItemId': i.menuItemId,
          'variantId': i.variantId,
        },
    ],
  };
  static Package _copyPackage(Package p) => Package(
    packageId: p.packageId,
    name: p.name,
    description: p.description,
    pricePerPerson: p.pricePerPerson,
    isActive: p.isActive,
    createdAt: p.createdAt,
    createdBy: p.createdBy,
    servingSize: p.servingSize,
    allowedTables: List.of(p.allowedTables),
    items: [
      for (final i in p.items)
        PackageItem(
          itemKey: i.itemKey,
          itemName: i.itemName,
          quantity: i.quantity,
          unitPrice: i.unitPrice,
          menuItemId: i.menuItemId,
          variantId: i.variantId,
        ),
    ],
  );

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
    String? requestId,
    String? expectedBusinessDate,
    Package? initialPackage,
    int packageGuestCount = 0,
  }) {
    final tables = tableNumbers
        .map(
          (t) => floor == 'takeaway'
              ? t.trim()
              : TableRepository.normalizeTableIdentifier(t, floor),
        )
        .whereType<String>()
        .toSet()
        .toList();
    final frozenItems = items.map((i) => i.clone()).toList();
    final date = expectedBusinessDate ?? OrderTableMutationRepository.dateKey;
    final request = <String, dynamic>{
      'kind': 'dineIn',
      'tables': tables,
      'floor': floor,
      'actor': createdBy,
      'items': frozenItems
          .map(OrderTableMutationRepository.itemRequest)
          .toList(),
      'includeServiceFee': includeServiceFee,
      'source': source.wireValue,
      'forPackage': forPackage,
      'reservationId': activatesReservationId,
      'customerName': reservationCustomerName,
      'expectedBusinessDate': expectedBusinessDate,
      if (initialPackage != null) 'package': _packageRequest(initialPackage),
      if (initialPackage != null) 'guestCount': packageGuestCount,
    };
    return UpdateReadiness.mutate('createOrder', () async {
      if (requestId != null) {
        final old = OrderTableMutationRepository.retry(requestId, request);
        if (old != null) return old;
      }
      if (date != OrderTableMutationRepository.dateKey) {
        throw OrderMutationConflict(
          'stale_date',
          'Business date changed before Order creation',
        );
      }
      final normalized = <String>[];
      for (final raw in tables) {
        final n = TableRepository.normalizeTableIdentifier(raw, floor);
        if (n != null && !normalized.contains(n)) normalized.add(n);
      }
      if (normalized.isEmpty) throw ArgumentError('Select at least one table');
      final order = Order(
        orderId: _getNextOrderId(),
        tableNumbers: normalized,
        floor: floor,
        items: frozenItems,
        totalAmount: 0,
        createdAt: OrderTableMutationRepository.now(),
        createdBy: createdBy,
        status: activatesReservationId == null && !forPackage
            ? OrderStatus.pending.storageValue
            : OrderStatus.confirmed.storageValue,
        includeServiceFee:
            includeServiceFee ?? SettingsRepository.defaultIncludeServiceFee(),
        openedByUserId: createdBy,
      );
      if (initialPackage != null) {
        order.packageId = initialPackage.packageId;
        order.packageName = initialPackage.name;
        order.packageUnitPrice = initialPackage.pricePerPerson;
        order.packageGuestCount = packageGuestCount;
        order.packagePrice = double.parse(
          (initialPackage.pricePerPerson * packageGuestCount).toStringAsFixed(
            2,
          ),
        );
        order.packageItems = initialPackage.items
            .map(
              (i) => OrderItem(
                itemKey: i.itemKey,
                itemName: i.itemName,
                unitPrice: i.unitPrice,
                quantity: i.quantity,
                total: double.parse(
                  (i.unitPrice * i.quantity).toStringAsFixed(2),
                ),
                menuItemId: i.menuItemId,
                variantId: i.variantId,
              ),
            )
            .toList();
      }
      order.recalculateTotal();
      final kind = activatesReservationId != null
          ? OrderAuditDetails.reservation
          : forPackage
          ? OrderAuditDetails.package
          : OrderAuditDetails.walkIn;
      final creation = AuditEvent(
        type: activatesReservationId != null
            ? AuditEventType.activateReservation
            : AuditEventType.createWalkIn,
        itemName: OrderAuditDetails.orderItemName,
        previousQty: 0,
        newQty: 0,
        waiterId: createdBy,
        waiterName: createdBy,
        timestamp: order.createdAt,
        details: {
          ...OrderAuditDetails.base(
            order: order,
            orderKind: kind,
            source: source,
            actorId: createdBy,
          ),
          'includeServiceFee': order.includeServiceFee,
          if (activatesReservationId != null)
            'reservationId': activatesReservationId,
          if (reservationCustomerName?.trim().isNotEmpty == true)
            'customerName': reservationCustomerName!.trim(),
        },
      );
      final extra = <AuditEvent>[];
      if (initialPackage != null) {
        extra.add(
          AuditEvent(
            type: AuditEventType.applyPackage,
            itemName: initialPackage.name,
            previousQty: 0,
            newQty: 0,
            waiterId: createdBy,
            waiterName: createdBy,
            timestamp: OrderAuditDetails.strictlyAfter(
              order.createdAt,
              order.createdAt,
            ),
            details: {
              ...OrderAuditDetails.base(
                order: order,
                orderKind: OrderAuditDetails.package,
                source: source,
                actorId: createdBy,
              ),
              'packageId': order.packageId,
              'packageName': order.packageName,
              'packageGuestCount': order.packageGuestCount,
              'packageUnitPrice': order.packageUnitPrice,
              'packagePrice': order.packagePrice,
              'packageItems': order.packageItems
                  .map((i) => i.toJson())
                  .toList(),
            },
          ),
        );
      }
      return OrderTableMutationRepository.create(
        request: request,
        order: order,
        creationEvent: creation,
        extraEvents: extra,
        requestId: requestId,
        activatesReservationId: activatesReservationId,
      );
    });
  }

  static Future<Order> createTakeAwayOrder({
    required String customerName,
    required String customerPhone,
    required String pickupTime,
    String? notes,
    required List<OrderItem> items,
    required String createdBy,
    AuditSource source = AuditSource.pos,
    String? requestId,
    String? expectedBusinessDate,
  }) {
    final frozenItems = items.map((i) => i.clone()).toList();
    final date = expectedBusinessDate ?? OrderTableMutationRepository.dateKey;
    final request = {
      'kind': 'takeaway',
      'customerName': customerName,
      'customerPhone': customerPhone,
      'pickupTime': pickupTime,
      'notes': notes,
      'items': frozenItems
          .map(OrderTableMutationRepository.itemRequest)
          .toList(),
      'actor': createdBy,
      'source': source.wireValue,
      'expectedBusinessDate': expectedBusinessDate,
    };
    return UpdateReadiness.mutate('createTakeAwayOrder', () async {
      if (requestId != null) {
        final old = OrderTableMutationRepository.retry(requestId, request);
        if (old != null) return old;
      }
      if (date != OrderTableMutationRepository.dateKey)
        throw OrderMutationConflict('stale_date', 'Business date changed');
      final id = _getNextOrderId();
      final order = Order(
        orderId: id,
        tableNumbers: ['TA-$id'],
        floor: 'takeaway',
        items: frozenItems,
        totalAmount: 0,
        createdAt: OrderTableMutationRepository.now(),
        createdBy: createdBy,
        status: OrderStatus.pending.storageValue,
        includeServiceFee: false,
        customerName: customerName,
        customerPhone: customerPhone,
        pickupTime: pickupTime,
      );
      order.recalculateTotal();
      return OrderTableMutationRepository.create(
        request: request,
        order: order,
        creationEvent: _takeawayCreationEvent(
          order: order,
          source: source,
          actor: createdBy,
        ),
        requestId: requestId,
      );
    });
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
    String? requestId,
    bool createOnly = false,
    String? expectedBusinessDate,
  }) => _mobileUpsert(
    posOrderId: posOrderId,
    tableNumbers: ['TA-$posOrderId'],
    floor: 'takeaway',
    waiterName: waiterName,
    items: items,
    totalAmount: totalAmount,
    source: source,
    requestId: requestId,
    createOnly: createOnly,
    expectedBusinessDate: expectedBusinessDate,
    customerName: customerName,
    pickupTime: pickupTime,
  );

  static Future<Order?> upsertMobileDineInOrder({
    required int posOrderId,
    required List<String> tableNumbers,
    required String floor,
    required String waiterName,
    required List<OrderItem> items,
    int guestCount = 0,
    double? totalAmount,
    AuditSource source = AuditSource.manager,
    String? requestId,
    bool createOnly = false,
    String? expectedBusinessDate,
  }) => _mobileUpsert(
    posOrderId: posOrderId,
    tableNumbers: tableNumbers,
    floor: floor,
    waiterName: waiterName,
    items: items,
    totalAmount: totalAmount,
    source: source,
    requestId: requestId,
    createOnly: createOnly,
    expectedBusinessDate: expectedBusinessDate,
    guestCount: guestCount,
  );

  static Future<Order?> _mobileUpsert({
    required int posOrderId,
    required List<String> tableNumbers,
    required String floor,
    required String waiterName,
    required List<OrderItem> items,
    double? totalAmount,
    required AuditSource source,
    String? requestId,
    bool createOnly = false,
    String? expectedBusinessDate,
    int guestCount = 0,
    String customerName = '',
    String pickupTime = '',
  }) {
    final frozenItems = items.map((i) => i.clone()).toList();
    final tables = tableNumbers
        .map(
          (t) => floor == 'takeaway'
              ? t.trim()
              : TableRepository.normalizeTableIdentifier(t, floor),
        )
        .whereType<String>()
        .toSet()
        .toList();
    final date = expectedBusinessDate ?? OrderTableMutationRepository.dateKey;
    final request = <String, dynamic>{
      'kind': 'mobileUpsert',
      if (createOnly) 'createOnly': true,
      if (expectedBusinessDate != null)
        'expectedBusinessDate': expectedBusinessDate,
      'posOrderId': posOrderId,
      'tables': tables,
      'floor': floor,
      'actor': waiterName,
      'source': source.wireValue,
      'items': frozenItems
          .map(OrderTableMutationRepository.itemRequest)
          .toList(),
      'totalAmount': totalAmount,
      'guestCount': guestCount,
      'customerName': customerName,
      'pickupTime': pickupTime,
    };
    // Capture the expected existing image before waiting for another owner.
    final expected = getOrder(posOrderId);
    return UpdateReadiness.mutate('upsertMobileDineInOrder', () async {
      if (requestId != null) {
        final old = OrderTableMutationRepository.retry(requestId, request);
        if (old != null) return old;
      }
      if (date != OrderTableMutationRepository.dateKey)
        throw OrderMutationConflict('stale_date', 'Business date changed');
      final existing = getOrder(posOrderId);
      if (existing != null) {
        if (createOnly)
          throw OrderMutationConflict(
            'order_id_conflict',
            'A local Order already owns this ID',
          );
        if (expected != null)
          OrderTableMutationRepository.requireFresh(expected);
        OrderTableMutationRepository.requireFresh(existing);
        if (existing.floor != floor ||
            !listEquals(existing.tableNumbers, tables)) {
          throw OrderMutationConflict(
            'request_conflict',
            'Upsert identity cannot change physical ownership',
          );
        }
        await _auditManagerItemReplacement(
          order: existing,
          updatedItems: frozenItems,
          actor: waiterName,
          source: source,
        );
        existing.items = frozenItems;
        if (floor == 'takeaway') {
          existing.customerName = customerName;
          existing.pickupTime = pickupTime;
        }
        if (totalAmount != null) {
          existing.totalAmount = totalAmount;
        } else {
          existing.recalculateTotal();
        }
        existing.updatedAt = OrderTableMutationRepository.now();
        await existing.save();
        return existing;
      }
      if (expected != null)
        throw OrderMutationConflict(
          'stale_order',
          'Expected Order disappeared',
        );
      final normalized = <String>[];
      for (final raw in tables) {
        final n = floor == 'takeaway'
            ? raw
            : TableRepository.normalizeTableIdentifier(raw, floor);
        if (n != null && !normalized.contains(n)) normalized.add(n);
      }
      if (normalized.isEmpty) return null;
      final order = Order(
        orderId: posOrderId,
        tableNumbers: normalized,
        floor: floor,
        items: frozenItems,
        totalAmount: totalAmount ?? 0,
        createdAt: OrderTableMutationRepository.now(),
        createdBy: waiterName,
        status: OrderStatus.confirmed.storageValue,
        includeServiceFee: false,
        openedByUserId: waiterName,
        customerName: customerName,
        pickupTime: pickupTime,
      );
      if (totalAmount == null) order.recalculateTotal();
      final event = floor == 'takeaway'
          ? _takeawayCreationEvent(
              order: order,
              source: source,
              actor: waiterName,
            )
          : AuditEvent(
              type: AuditEventType.createWalkIn,
              itemName: OrderAuditDetails.orderItemName,
              previousQty: 0,
              newQty: 0,
              waiterId: waiterName,
              waiterName: waiterName,
              timestamp: order.createdAt,
              details: {
                ...OrderAuditDetails.base(
                  order: order,
                  orderKind: OrderAuditDetails.walkIn,
                  source: source,
                  actorId: waiterName,
                ),
                'includeServiceFee': false,
                if (guestCount > 0) 'guestCount': guestCount,
              },
            );
      return OrderTableMutationRepository.create(
        request: request,
        order: order,
        creationEvent: event,
        requestId: requestId,
      );
    });
  }

  static Future<Order> createOrderForPackage({
    required Package package,
    required List<String> tableNumbers,
    required String floor,
    required int guestCount,
    required String createdBy,
    AuditSource source = AuditSource.pos,
    String? requestId,
    String? expectedBusinessDate,
  }) {
    final frozen = _copyPackage(package);
    final date = expectedBusinessDate ?? OrderTableMutationRepository.dateKey;
    final tables = tableNumbers
        .map(
          (t) => floor == 'takeaway'
              ? t.trim()
              : TableRepository.normalizeTableIdentifier(t, floor),
        )
        .whereType<String>()
        .toSet()
        .toList();
    return UpdateReadiness.mutate('createOrderForPackage', () async {
      if (guestCount <= 0)
        throw ArgumentError('Guest count must be greater than zero');
      if (!frozen.isActive)
        throw StateError('Activate the package before assigning it to tables');
      if (frozen.allowedTables.isNotEmpty &&
          tables.any((t) => !frozen.allowedTables.contains(t))) {
        throw StateError('Package is not available for selected tables');
      }
      return createOrder(
        tableNumbers: tables,
        floor: floor,
        createdBy: createdBy,
        items: [],
        source: source,
        forPackage: true,
        initialPackage: frozen,
        packageGuestCount: guestCount,
        requestId: requestId,
        expectedBusinessDate: date,
      );
    });
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
    final row = OrderTableMutationRepository.persisted(orderId);
    return row == null
        ? null
        : OrderTableMutationRepository.detached(row.$2, row.$1);
  }

  static List<Order> getAllOrders() => [
    for (final row in DatabaseCore.orderBox!.toMap().entries)
      OrderTableMutationRepository.detached(row.value, row.key),
  ];

  static bool isOrderStatusActive(String status) {
    final normalized = status.toLowerCase();
    return normalized != 'paid' &&
        normalized != 'cancelled' &&
        normalized != 'closed';
  }

  // Get active orders (not paid or cancelled)
  static List<Order> getActiveOrders() =>
      getAllOrders().where((o) => isOrderStatusActive(o.status)).toList();

  // Update order
  static Future<void> updateOrder(
    Order order, {
    bool? previousIncludeServiceFee,
  }) {
    final frozen = order.clone();
    frozen.mutationBaseline = order.mutationBaseline == null
        ? OrderTableMutationRepository.image(order)
        : Map.of(order.mutationBaseline!);
    return UpdateReadiness.mutate('updateOrder', () async {
      await _updateTrackedUpdateOrder(
        frozen,
        previousIncludeServiceFee: previousIncludeServiceFee,
      );
      order.mutationBaseline = frozen.mutationBaseline;
      order.mutationKey = frozen.mutationKey;
      order.totalAmount = frozen.totalAmount;
    });
  }

  static Future<void> _updateTrackedUpdateOrder(
    Order order, {
    bool? previousIncludeServiceFee,
  }) async {
    OrderTableMutationRepository.requireFresh(order);
    order.recalculateTotal();
    await order.save();
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'updated',
        payload: {
          'orderId': order.orderId,
          if (previousIncludeServiceFee != null &&
              previousIncludeServiceFee != order.includeServiceFee)
            'serviceFeeChanged': true,
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
  }) => UpdateReadiness.mutate(
    'updateOrderStatus',
    () => _updateTrackedUpdateOrderStatus(orderId: orderId, status: status),
  );

  static Future<void> _updateTrackedUpdateOrderStatus({
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
      if (parsed == OrderStatus.cancelled) {
        final outcome = await CancelOrderTransaction.run(
          orderId: orderId,
          actorId: order.createdBy,
          source: AuditSource.pos,
          expectedOrder: order,
        );
        if (![
          CancelOrderOutcome.cancelled,
          CancelOrderOutcome.alreadyCancelled,
        ].contains(outcome))
          throw OrderMutationConflict(
            'recovery_required',
            'Cancellation lifecycle did not complete',
          );
        return;
      }
      await order.updateStatus(canonical);

      // A settled order no longer holds its tables. Previously spelled
      // `paid || cancelled`; `paid` now normalizes to `closed`, and no
      // production caller reaches this with `closed` — closing owns its own
      // table release inside `CloseTableTransaction`.
      if (parsed.isTerminal) {
        for (final tableNumber in order.tableNumbers) {
          await TableRepository.freeTable(
            tableNumber: tableNumber,
            floor: order.floor,
            expectedOrderId: order.orderId,
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
  }) => UpdateReadiness.mutate(
    'hardDeleteOrderForRepair',
    () => _updateTrackedHardDeleteOrderForRepair(
      orderId: orderId,
      deletedBy: deletedBy,
      cancelLinkedReservation: cancelLinkedReservation,
    ),
  );

  static Future<bool> _updateTrackedHardDeleteOrderForRepair({
    required int orderId,
    required String deletedBy,
    bool cancelLinkedReservation = true,
  }) async {
    try {
      final order = getOrder(orderId);
      if (order == null) {
        return false;
      }

      OrderTableMutationRepository.requireConsistent(orderId: orderId);
      final stored = OrderTableMutationRepository.persisted(
        orderId,
        uuid: order.orderUuid,
      )!;
      await DatabaseCore.orderBox!.delete(stored.$1);
      await DatabaseCore.orderBox!.flush();

      // Free all tables associated with this order
      for (final tableNumber in order.tableNumbers) {
        await TableRepository.freeTable(
          tableNumber: tableNumber,
          floor: order.floor,
          expectedOrderId: order.orderId,
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
  }) => UpdateReadiness.mutate(
    'addItemToOrder',
    () => _updateTrackedAddItemToOrder(orderId: orderId, item: item),
  );

  static Future<void> _updateTrackedAddItemToOrder({
    required int orderId,
    required OrderItem item,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      await order.addItem(item);
      await updateOrder(order);
    }
  }

  // Remove item from order
  static Future<void> removeItemFromOrder({
    required int orderId,
    required String itemKey,
  }) => UpdateReadiness.mutate(
    'removeItemFromOrder',
    () => _updateTrackedRemoveItemFromOrder(orderId: orderId, itemKey: itemKey),
  );

  static Future<void> _updateTrackedRemoveItemFromOrder({
    required int orderId,
    required String itemKey,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      await order.removeItem(itemKey);
      await updateOrder(order);
    }
  }

  // Update item quantity in order
  static Future<void> updateOrderItemQuantity({
    required int orderId,
    required String itemKey,
    required int quantity,
  }) => UpdateReadiness.mutate(
    'updateOrderItemQuantity',
    () => _updateTrackedUpdateOrderItemQuantity(
      orderId: orderId,
      itemKey: itemKey,
      quantity: quantity,
    ),
  );

  static Future<void> _updateTrackedUpdateOrderItemQuantity({
    required int orderId,
    required String itemKey,
    required int quantity,
  }) async {
    final order = getOrder(orderId);
    if (order != null) {
      await order.updateItemQuantity(itemKey, quantity);
      await updateOrder(order);
    }
  }
}
