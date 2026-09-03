import 'package:flutter/foundation.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/services/audit/audit_order_diff_service.dart';
import 'package:vynic/core/services/audit/money_audit.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/notifications/manager_notification_inbox.dart';
import 'package:vynic/core/services/pos/pos_change_highlight_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/sync/pos_live_refresh.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';
import 'package:vynic/core/utils/home_reservations_helper.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

/// What applying one Cloud-originated operation did.
///
/// Deliberately transport-shaped rather than HTTP-shaped: the same outcome has
/// to become a status code for the legacy LAN ingest server and an
/// [EdgeCommandResult] for the pull transport, and neither may be the one the
/// other is translated from.
@immutable
class PosCommandOutcome {
  const PosCommandOutcome._({
    required this.ok,
    required this.code,
    this.detail,
    this.data = const <String, dynamic>{},
    this.badRequest = false,
    this.notFound = false,
    this.conflict = false,
  });

  const PosCommandOutcome.success({
    String code = 'ok',
    Map<String, dynamic> data = const <String, dynamic>{},
  }) : this._(ok: true, code: code, data: data);

  /// The payload could not be read. Repeating it will not help.
  const PosCommandOutcome.invalid(String code, {String? detail})
    : this._(ok: false, code: code, detail: detail, badRequest: true);

  /// The thing being addressed is not here.
  const PosCommandOutcome.missing(String code, {String? detail})
    : this._(ok: false, code: code, detail: detail, notFound: true);

  /// Local state refuses the change.
  const PosCommandOutcome.conflicting(String code, {String? detail})
    : this._(ok: false, code: code, detail: detail, conflict: true);

  /// Something went wrong applying it.
  const PosCommandOutcome.failed(String code, {String? detail})
    : this._(ok: false, code: code, detail: detail);

  final bool ok;

  /// A short machine-readable outcome, e.g. `order_not_found`.
  final String code;
  final String? detail;

  /// Anything the caller returns to whoever asked. Never secrets.
  final Map<String, dynamic> data;

  final bool badRequest;
  final bool notFound;
  final bool conflict;

  /// The HTTP status the legacy LAN ingest server answers with.
  int get httpStatus {
    if (ok) return 200;
    if (badRequest) return 400;
    if (notFound) return 404;
    if (conflict) return 409;
    return 500;
  }
}

/// Everything Cloud can ask this POS to do, and the only place it is done.
///
/// Two transports reach these operations. The legacy LAN callback server dials
/// in from the backend; the Edge command transport pulls work out of Cloud with
/// a Device credential. During the migration both are live, and the one thing
/// that must not happen is the two of them drifting into slightly different
/// restaurant behaviour — an order cancelled one way and a different way
/// depending on which network path the request took.
///
/// So the behaviour lives here once, and both transports are adapters over it.
/// [PosIngestServer] turns a [PosCommandOutcome] into a status code; the Edge
/// handlers turn it into a command result.
///
/// ## Idempotency
///
/// Edge delivery is at-least-once, so every operation here is written to
/// converge: the payload says what the final state should be rather than how to
/// change it, and an operation whose goal state already holds reports success
/// instead of a conflict. Where convergence was not naturally available — a
/// reservation whose id the POS used to invent, an expense that used to be
/// appended — Cloud now supplies the identity and the write is an upsert.
///
/// The three print operations are the exception and are marked as such in the
/// contract: paper is a side effect the world keeps. Their protection is the
/// Edge execution journal, not convergence.
class PosCommandApplier {
  PosCommandApplier._();

  /// Who a Cloud-originated change is attributed to when nothing says.
  static const String defaultActor = 'mobile_manager';

  // ── Orders ─────────────────────────────────────────────────────────────────

  /// Replace an order's lines, total and service-fee flag.
  ///
  /// Convergent: the payload is the order's new content, so a second delivery
  /// writes the same values. The audit diff is taken against what is stored, so
  /// a replay produces no events, and [MoneyAudit] already declines to record a
  /// service-fee change that did not move.
  static Future<PosCommandOutcome> updateOrder(Map<String, dynamic> p) async {
    final posOrderId = _int(p['posOrderId']);
    if (posOrderId == null) {
      return const PosCommandOutcome.invalid('posOrderId_required');
    }
    final order = DatabaseService.getOrder(posOrderId);
    if (order == null) {
      return const PosCommandOutcome.missing('order_not_found');
    }

    final beforeItems = order.items.map((i) => i.clone()).toList();
    final newItems = parseOrderItems(p['items']);

    final diff = PosChangeHighlightService.computeOrderItemChanges(
      before: beforeItems,
      after: newItems,
    );

    final prevTotal = order.totalAmount;
    final prevServiceFee = order.includeServiceFee;

    final performerName = _actor(p['updatedBy'] ?? p['waiterName']);
    final ts = DatabaseService.getCurrentDateTime();
    final auditEvents = AuditOrderDiffService.buildEvents(
      previousItems: beforeItems,
      updatedItems: newItems,
      performerId: performerName,
      performerName: performerName,
      timestamp: ts,
    );
    if (auditEvents.isNotEmpty) {
      await DatabaseService.appendOrderAuditEvents(
        orderId: posOrderId,
        events: auditEvents,
      );
    }

    order.items = newItems;
    final totalAmount = _double(p['totalAmount']);
    if (totalAmount != null) order.totalAmount = totalAmount;
    if (p['includeServiceFee'] is bool) {
      order.includeServiceFee = p['includeServiceFee'] as bool;
    }
    order.updatedAt = ts;
    order.recalculateTotal();
    await DatabaseService.updateOrder(order);

    // The Manager app reaches the order through here, so this is where a
    // manager-side service-fee change becomes a fact. The actor is the name the
    // client identified itself with.
    await MoneyAudit.orderServiceFeeChanged(
      actorId: performerName,
      orderId: posOrderId,
      previousIncluded: prevServiceFee,
      newIncluded: order.includeServiceFee,
      previousTotal: prevTotal,
      newTotal: order.totalAmount,
    );

    final message = orderChangeMessage(
      posOrderId: posOrderId,
      diff: diff,
      totalChanged: (order.totalAmount - prevTotal).abs() > 0.009,
      serviceFeeToggled:
          p['includeServiceFee'] is bool &&
          order.includeServiceFee != prevServiceFee,
      tableNumbers: order.tableNumbers,
      floor: order.floor,
    );
    final tableLabel = order.tableNumbers.isNotEmpty
        ? order.tableNumbers.join(', ')
        : null;
    _notify(
      message: message,
      meta: {
        'posOrderId': posOrderId,
        if (tableLabel != null) 'tableLabel': tableLabel,
        if (order.floor.isNotEmpty) 'floor': order.floor,
        if (diff.highlightKeys.isNotEmpty)
          'highlightItemKeys': diff.highlightKeys.toList(),
      },
    );
    scheduleCloudSync();
    return const PosCommandOutcome.success();
  }

  /// Remove an order and release the tables it held.
  ///
  /// Convergent: the goal state is "this order is gone". An order already
  /// absent satisfies it, so a redelivery succeeds rather than reporting a
  /// missing order — which would turn a duplicate into a false failure.
  static Future<PosCommandOutcome> cancelOrder(
    Map<String, dynamic> p, {
    bool treatMissingAsDone = false,
  }) async {
    final posOrderId = _int(p['posOrderId']);
    if (posOrderId == null) {
      return const PosCommandOutcome.invalid('posOrderId_required');
    }
    // Capture the tables before the order (and its cleanup) removes them.
    final existing = DatabaseService.getOrder(posOrderId);
    final tableSeg = existing != null
        ? formatTablesSegment(existing.tableNumbers, existing.floor)
        : '';
    final ok = await DatabaseService.deleteOrderAndCleanup(
      orderId: posOrderId,
      deletedBy: defaultActor,
    );
    if (!ok) {
      if (!treatMissingAsDone) {
        return const PosCommandOutcome.missing('order_not_found');
      }
      return const PosCommandOutcome.success(code: 'already_absent');
    }
    _notify(
      message: tableSeg.isNotEmpty
          ? 'შეკვეთა #$posOrderId გაუქმდა — $tableSeg'
          : 'შეკვეთა #$posOrderId წაიშალა',
      meta: {
        'posOrderId': posOrderId,
        if (tableSeg.isNotEmpty)
          'tableLabel': existing!.tableNumbers.join(', '),
      },
    );
    scheduleCloudSync();
    return const PosCommandOutcome.success();
  }

  /// Set an order's status. Convergent by assignment.
  static Future<PosCommandOutcome> updateOrderStatus(
    Map<String, dynamic> p,
  ) async {
    final posOrderId = _int(p['posOrderId']);
    final status = _string(p['status']);
    if (posOrderId == null || status.isEmpty) {
      return const PosCommandOutcome.invalid('posOrderId_and_status_required');
    }
    // Capture tables before the status change frees them (paid/cancelled).
    final existing = DatabaseService.getOrder(posOrderId);
    final tableSeg = existing != null
        ? formatTablesSegment(existing.tableNumbers, existing.floor)
        : '';
    await DatabaseService.updateOrderStatus(
      orderId: posOrderId,
      status: status,
    );
    final isCancelled = status.toLowerCase() == 'cancelled';
    final String message;
    if (isCancelled) {
      message = tableSeg.isNotEmpty
          ? 'შეკვეთა #$posOrderId გაუქმდა — $tableSeg'
          : 'შეკვეთა #$posOrderId გაუქმდა';
    } else {
      message = tableSeg.isNotEmpty
          ? 'შეკვეთა #$posOrderId — სტატუსი: $status ($tableSeg)'
          : 'შეკვეთა #$posOrderId — სტატუსი: $status';
    }
    _notify(
      message: message,
      meta: {
        'posOrderId': posOrderId,
        'status': status,
        if (tableSeg.isNotEmpty)
          'tableLabel': existing!.tableNumbers.join(', '),
      },
    );
    scheduleCloudSync();
    return const PosCommandOutcome.success();
  }

  /// Create or update a Cloud-originated takeaway order.
  ///
  /// Convergent: `posOrderId` is allocated by Cloud and the write is an upsert,
  /// so a redelivery updates the one order. The kitchen check is sent only when
  /// the order was not already here, which is what stops a replay reprinting it.
  static Future<PosCommandOutcome> upsertTakeawayOrder(
    Map<String, dynamic> p,
  ) async {
    final posOrderId = _int(p['posOrderId']);
    if (posOrderId == null) {
      return const PosCommandOutcome.invalid('posOrderId_required');
    }

    final items = parseOrderItems(p['items']);
    final isNew = DatabaseService.getOrder(posOrderId) == null;
    final waiterName = _actor(p['waiterName']);

    final order = await DatabaseService.upsertMobileTakeawayOrder(
      posOrderId: posOrderId,
      customerName: _string(p['customerName']),
      pickupTime: _string(p['pickupTime']),
      waiterName: waiterName,
      items: items,
      totalAmount: _double(p['totalAmount']),
    );
    if (order == null) {
      return const PosCommandOutcome.failed('create_failed');
    }
    if (isNew) {
      sendKitchenCheck(
        items: items,
        orderLabel: 'გატანა #${order.orderId}',
        waiterName: waiterName,
      );
    }

    final customer = _string(p['customerName']);
    final pickup = _string(p['pickupTime']);
    final detailSeg = [
      if (customer.isNotEmpty) customer,
      if (pickup.isNotEmpty) 'აღება: $pickup',
    ].join(' • ');
    _notify(
      message: detailSeg.isNotEmpty
          ? 'ახალი გატანა #${order.orderId} — $detailSeg'
          : 'ახალი გატანა #${order.orderId}',
      meta: {'posOrderId': order.orderId, ..._highlightMeta(items)},
    );
    scheduleCloudSync();
    return PosCommandOutcome.success(
      data: <String, dynamic>{'posOrderId': order.orderId},
    );
  }

  /// Create or update a Cloud-originated walk-in dine-in order.
  ///
  /// Convergent for the same reason as [upsertTakeawayOrder].
  static Future<PosCommandOutcome> upsertDineInOrder(
    Map<String, dynamic> p,
  ) async {
    final posOrderId = _int(p['posOrderId']);
    if (posOrderId == null) {
      return const PosCommandOutcome.invalid('posOrderId_required');
    }
    final tableNumbers = _stringList(p['tableNumbers']);
    if (tableNumbers.isEmpty) {
      return const PosCommandOutcome.invalid('tableNumbers_required');
    }

    final floor = _string(p['floor'], fallback: 'first');
    final items = parseOrderItems(p['items']);
    final isNew = DatabaseService.getOrder(posOrderId) == null;
    final waiterName = _actor(p['waiterName']);

    final order = await DatabaseService.upsertMobileDineInOrder(
      posOrderId: posOrderId,
      tableNumbers: tableNumbers,
      floor: floor,
      waiterName: waiterName,
      items: items,
      guestCount: _int(p['guestCount']) ?? 0,
      totalAmount: _double(p['totalAmount']),
    );
    if (order == null) {
      return const PosCommandOutcome.failed('create_failed');
    }
    if (isNew) {
      sendKitchenCheck(
        items: items,
        orderLabel: 'Walk-in #${order.orderId}',
        waiterName: waiterName,
        tableLabel: tableNumbers.join(', '),
      );
    }

    final tableSeg = formatTablesSegment(tableNumbers, floor);
    _notify(
      message: tableSeg.isNotEmpty
          ? 'ახალი walk-in #${order.orderId} — $tableSeg'
          : 'ახალი walk-in #${order.orderId}',
      meta: {
        'posOrderId': order.orderId,
        'walkIn': true,
        if (tableSeg.isNotEmpty) 'tableLabel': tableNumbers.join(', '),
        if (order.floor.isNotEmpty) 'floor': order.floor,
        ..._highlightMeta(items),
      },
    );
    scheduleCloudSync();
    return PosCommandOutcome.success(
      data: <String, dynamic>{'posOrderId': order.orderId},
    );
  }

  // ── Printing ───────────────────────────────────────────────────────────────

  /// Print an order's customer pre-bill on the receipt printer.
  ///
  /// The POS is the only print host: a Manager client never touches a printer,
  /// and Cloud never opens a connection to one. The order is read from local
  /// Hive, which is what the restaurant actually has.
  ///
  /// Not convergent, and not pretended to be. Its protection against a repeated
  /// delivery is the Edge execution journal.
  static Future<PosCommandOutcome> printOrderCheck(
    Map<String, dynamic> p,
  ) async {
    final posOrderId = _int(p['posOrderId']);
    if (posOrderId == null) {
      return const PosCommandOutcome.invalid('posOrderId_required');
    }
    final order = DatabaseService.getOrder(posOrderId);
    if (order == null) {
      return const PosCommandOutcome.missing('order_not_found');
    }

    final isTakeAway = order.floor.toLowerCase().contains('takeaway');
    final receiptLines = <String>[];

    if (order.packageItems.isNotEmpty) {
      final packageLabel =
          (order.packageName != null && order.packageName!.trim().isNotEmpty)
          ? order.packageName!.trim()
          : 'პაკეტი';
      final packageTotalRaw = order.getPackageSubtotal();
      final packageTotal = packageTotalRaw > 0
          ? packageTotalRaw
          : order.packagePrice;

      receiptLines.add('[$packageLabel]');
      final summary = StringBuffer();
      if (order.packageGuestCount > 0) {
        summary.write('${order.packageGuestCount}x ');
      }
      summary.write(packageLabel);
      if (packageTotal > 0) {
        summary.write(' - ${packageTotal.toStringAsFixed(2)} GEL');
      }
      receiptLines.add(summary.toString());

      for (final packageItem in order.packageItems) {
        receiptLines.add(
          '  ⮑ ${packageItem.quantity}x ${packageItem.itemName}',
        );
      }
      if (order.items.isNotEmpty) {
        receiptLines.add('---');
      }
    }

    if (order.items.isNotEmpty) {
      if (order.packageItems.isNotEmpty) {
        receiptLines.add('[დამატებითი]');
      }
      receiptLines.addAll(
        order.items.map(
          (item) =>
              '${item.quantity}x ${item.itemName} - '
              '${item.total.toStringAsFixed(2)} GEL',
        ),
      );
    }

    final itemsWithWaiter = <String>[
      'ოფიციანტი: ${order.createdBy}',
      '---',
      ...receiptLines,
    ];

    final packageSubtotal = order.getPackageSubtotal();
    final additionalSubtotal = order.getAdditionalItemsSubtotal();
    final discountAmount = order.discountAmount > 0
        ? order.discountAmount
        : null;
    final manualAdjustment = order.manualAdjustmentAmount.abs() >= 0.01
        ? order.manualAdjustmentAmount
        : null;

    PrinterService.printReceiptInBackground(
      items: itemsWithWaiter,
      total: order.totalAmount,
      subtotal: order.getItemsSubtotal(),
      serviceFee: order.getServiceFee(),
      includeServiceFee: order.includeServiceFee,
      tableNumber: isTakeAway ? null : order.tableNumbers.join(', '),
      orderNumber: order.orderId.toString(),
      language: 'ka',
      packageSubtotal: packageSubtotal > 0 ? packageSubtotal : null,
      additionalSubtotal: additionalSubtotal > 0 ? additionalSubtotal : null,
      discountAmount: discountAmount,
      manualAdjustment: manualAdjustment,
      receiptType: isTakeAway ? 'take_away' : 'client',
    );

    return const PosCommandOutcome.success();
  }

  /// Print a reservation's kitchen check, reusing the exact formatting the POS
  /// uses when a reservation is created locally.
  static Future<PosCommandOutcome> printReservationCheck(
    Map<String, dynamic> p,
  ) async {
    final reservationId = _string(p['reservationId']);
    if (reservationId.isEmpty) {
      return const PosCommandOutcome.invalid('reservationId_required');
    }
    final reservation = DatabaseService.findReservationById(reservationId);
    if (reservation == null) {
      return const PosCommandOutcome.missing('reservation_not_found');
    }

    final kitchenItems = HomeReservationsHelper.buildKitchenCheckLines(
      reservation,
    );
    if (kitchenItems.isEmpty) {
      // No kitchen-bound items (e.g. no pre-order) — nothing to print, and
      // that is a success rather than a failure.
      return const PosCommandOutcome.success(
        code: 'nothing_to_print',
        data: <String, dynamic>{'printed': false},
      );
    }

    final requestedBy = _string(
      p['requestedBy'],
      fallback: reservation.createdBy,
    );
    final reservationTables = ReservationTableAvailability.tableRefsOf(
      reservation,
    );
    PrinterService.printKitchenCheckInBackground(
      items: kitchenItems,
      tableNumber: reservationTables.isNotEmpty
          ? reservationTables.map((ref) => ref.tableNumber).join(', ')
          : null,
      orderNumber: HomeReservationsHelper.buildKitchenOrderLabel(reservation),
      waiterName: requestedBy.isNotEmpty ? requestedBy : defaultActor,
      createdAt: HomeReservationsHelper.buildKitchenTime(reservation),
    );

    return const PosCommandOutcome.success(
      data: <String, dynamic>{'printed': true},
    );
  }

  /// Print a counted-menu draft from the payload itself.
  ///
  /// Counted menus live in Cloud rather than POS Hive — a Manager creates them
  /// there and the POS has never seen one — so the whole draft travels in the
  /// command rather than being looked up.
  static Future<PosCommandOutcome> printCountedMenu(
    Map<String, dynamic> p,
  ) async {
    final rawItems = (p['items'] as List?) ?? const [];
    if (rawItems.isEmpty) {
      return const PosCommandOutcome.invalid('items_required');
    }

    final lines = <String>['---'];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final name = _string(map['itemName'] ?? map['name']);
      final qty = _int(map['quantity']) ?? 1;
      final unitPrice = _double(map['unitPrice'] ?? map['price']) ?? 0.0;
      final total = _double(map['total']) ?? unitPrice * qty;
      lines.add('${qty}x $name - ${total.toStringAsFixed(2)} GEL');
      final comment = _string(map['comment']);
      if (comment.isNotEmpty) {
        lines.add('  ⮑ $comment');
      }
    }

    final subtotal = _double(p['subtotal']) ?? 0.0;
    final serviceFeeAmount = _double(p['serviceFeeAmount']) ?? 0.0;
    final total = _double(p['total']) ?? subtotal;
    final includeServiceFee =
        p['includeServiceFee'] == true && serviceFeeAmount > 0;
    final receiptTotal = includeServiceFee ? total : subtotal;
    final language = _string(p['language'], fallback: 'ka') == 'en'
        ? 'en'
        : 'ka';

    PrinterService.printReceiptInBackground(
      items: lines,
      total: receiptTotal,
      subtotal: subtotal,
      serviceFee: includeServiceFee ? serviceFeeAmount : null,
      includeServiceFee: includeServiceFee,
      language: language,
      receiptType: 'menu_count',
    );

    return const PosCommandOutcome.success();
  }

  // ── Reservations ───────────────────────────────────────────────────────────

  /// Create a reservation Cloud originated.
  ///
  /// Convergent because Cloud allocates `reservationId`. It used to be invented
  /// here, which made a redelivery a second booking — the one place in this file
  /// where identity had to move for at-least-once delivery to be survivable.
  /// A reservation already carrying that id is reported as created, because it
  /// was: by the delivery before this one.
  static Future<PosCommandOutcome> createReservation(
    Map<String, dynamic> p,
  ) async {
    try {
      final requestedId = _string(p['reservationId'] ?? p['id']);
      if (requestedId.isNotEmpty) {
        final existing = DatabaseService.getReservationById(requestedId);
        if (existing != null) {
          return PosCommandOutcome.success(
            code: 'already_exists',
            data: <String, dynamic>{'reservation': existing},
          );
        }
      }

      final id = await DatabaseService.createReservationFromJson(
        <String, dynamic>{...p, if (requestedId.isNotEmpty) 'id': requestedId},
      );
      final reservation = DatabaseService.getReservationById(id);
      final customerName = _string(
        reservation?['customerName'] ?? p['customerName'],
      );
      final isTakeAway = p['isTakeAway'] == true;
      final resTables = _stringList(p['tableNumbers']);
      final resTime = _string(p['reservationTime']);
      final tableSeg = isTakeAway
          ? 'გატანა'
          : formatTablesSegment(resTables, 'first');
      final detailSeg = [
        if (customerName.isNotEmpty) customerName,
        if (tableSeg.isNotEmpty) tableSeg,
        if (resTime.isNotEmpty) 'დრო: $resTime',
      ].join(' • ');
      _notify(
        message: detailSeg.isEmpty
            ? 'ახალი რეზერვაცია'
            : 'ახალი რეზერვაცია — $detailSeg',
        meta: {
          'reservationId': id,
          if (tableSeg.isNotEmpty && !isTakeAway)
            'tableLabel': resTables.join(', '),
        },
      );
      scheduleCloudSync();
      return PosCommandOutcome.success(
        data: <String, dynamic>{
          'reservation': reservation ?? {'id': id},
        },
      );
    } catch (e) {
      return PosCommandOutcome.invalid(
        'reservation_invalid',
        detail: e.toString(),
      );
    }
  }

  /// Set a reservation's status. Convergent by assignment.
  static Future<PosCommandOutcome> updateReservationStatus(
    Map<String, dynamic> p,
  ) async {
    final reservationId = _string(p['reservationId']);
    final status = _string(p['status']);
    if (reservationId.isEmpty || status.isEmpty) {
      return const PosCommandOutcome.invalid(
        'reservationId_and_status_required',
      );
    }
    await DatabaseService.updateReservationStatus(reservationId, status);
    _notify(
      message: 'რეზერვაცია — სტატუსი: $status',
      meta: {'reservationId': reservationId, 'status': status},
    );
    scheduleCloudSync();
    return const PosCommandOutcome.success();
  }

  /// Remove a reservation.
  ///
  /// Convergent: the goal state is "this reservation is gone", which an absent
  /// reservation already satisfies.
  static Future<PosCommandOutcome> deleteReservation(
    Map<String, dynamic> p,
  ) async {
    final reservationId = _string(p['reservationId']);
    if (reservationId.isEmpty) {
      return const PosCommandOutcome.invalid('reservationId_required');
    }
    await DatabaseService.deleteReservation(reservationId);
    scheduleCloudSync();
    return const PosCommandOutcome.success();
  }

  // ── Expenses ───────────────────────────────────────────────────────────────

  /// Record an expense the Manager entered.
  ///
  /// Convergent because Cloud allocates the id and the local write upserts on
  /// it. Appending was the old behaviour, and it meant one retried delivery
  /// showed up as two expenses in a restaurant's day.
  static Future<PosCommandOutcome> createExpense(Map<String, dynamic> p) async {
    final description = _string(p['description']);
    final amount = _double(p['amount']) ?? 0;
    if (description.isEmpty || amount <= 0) {
      return const PosCommandOutcome.invalid('invalid_expense');
    }
    final createdAtRaw = _string(p['createdAt']);
    final expense = await DatabaseService.saveExpenseRecord(
      description: description,
      amount: amount,
      category: _string(p['category'], fallback: 'სხვა'),
      paymentType: _string(p['paymentType'], fallback: 'cash'),
      createdAt: createdAtRaw.isNotEmpty
          ? DateTime.tryParse(createdAtRaw)
          : null,
      businessDate: p['businessDate'] as String?,
      sourceId: p['id'] as String?,
    );
    scheduleCloudSync();
    return PosCommandOutcome.success(
      data: <String, dynamic>{'expense': expense},
    );
  }

  // ── Staff ──────────────────────────────────────────────────────────────────

  /// Add a staff user.
  ///
  /// Convergent: the goal state is "this username exists with this role and
  /// PIN". Cloud has already refused a duplicate username before enqueueing, so
  /// a username that exists locally means this command has landed before —
  /// the role and PIN are reconciled and the outcome is success.
  static Future<PosCommandOutcome> createStaff(
    Map<String, dynamic> p, {
    bool treatExistingAsDone = false,
  }) async {
    final username = _string(p['username']);
    final pinCode = _string(p['pinCode'] ?? p['pin']);
    if (username.isEmpty || pinCode.isEmpty) {
      return const PosCommandOutcome.invalid('username_and_pin_required');
    }
    final role = StaffRole.normalizeClient(
      _string(p['role'], fallback: 'waiter'),
    );
    final ok = await DatabaseService.addUser(
      username: username,
      pinCode: pinCode,
      role: role,
    );
    if (ok) {
      scheduleCloudSync();
      return PosCommandOutcome.success(
        data: <String, dynamic>{
          'user': {'username': username, 'role': role},
        },
      );
    }

    if (!treatExistingAsDone) {
      return const PosCommandOutcome.conflicting('user_exists_or_pin_taken');
    }
    // Redelivery, or a user this command already created. Bring the record to
    // the state the command asked for and report it as done.
    if (DatabaseService.getUserByUsername(username) == null) {
      // The refusal was not "already exists" — a PIN belonging to someone else,
      // most likely. Repeating will not resolve it.
      return const PosCommandOutcome.conflicting('user_exists_or_pin_taken');
    }
    await DatabaseService.updateUserPinByUsername(
      username: username,
      pinCode: pinCode,
    );
    await DatabaseService.updateUserRoleByUsername(
      username: username,
      role: role,
    );
    scheduleCloudSync();
    return PosCommandOutcome.success(
      code: 'already_exists',
      data: <String, dynamic>{
        'user': {'username': username, 'role': role},
      },
    );
  }

  /// Set a staff user's PIN. Convergent by assignment.
  static Future<PosCommandOutcome> updateStaffPin(
    Map<String, dynamic> p,
  ) async {
    final username = _string(p['username']);
    final pinCode = _string(p['pinCode'] ?? p['pin']);
    if (username.isEmpty || pinCode.isEmpty) {
      return const PosCommandOutcome.invalid('username_and_pin_required');
    }
    final ok = await DatabaseService.updateUserPinByUsername(
      username: username,
      pinCode: pinCode,
    );
    if (!ok) return const PosCommandOutcome.missing('update_failed');
    scheduleCloudSync();
    return const PosCommandOutcome.success();
  }

  /// Set a staff user's role. Convergent by assignment.
  static Future<PosCommandOutcome> updateStaffRole(
    Map<String, dynamic> p,
  ) async {
    final username = _string(p['username']);
    final roleRaw = _string(p['role']);
    if (username.isEmpty || roleRaw.isEmpty) {
      return const PosCommandOutcome.invalid('username_and_role_required');
    }
    final role = StaffRole.normalizeClient(roleRaw);
    final ok = await DatabaseService.updateUserRoleByUsername(
      username: username,
      role: role,
    );
    if (!ok) return const PosCommandOutcome.conflicting('role_update_failed');
    scheduleCloudSync();
    return PosCommandOutcome.success(
      data: <String, dynamic>{
        'user': {'username': username, 'role': role},
      },
    );
  }

  /// Rename a staff user.
  ///
  /// Convergent: the goal state is "newUsername exists and oldUsername does
  /// not". A redelivery finds exactly that and succeeds without touching
  /// anything.
  static Future<PosCommandOutcome> renameStaff(
    Map<String, dynamic> p, {
    bool treatRenamedAsDone = false,
  }) async {
    final oldUsername = _string(p['oldUsername']);
    final newUsername = _string(p['newUsername'] ?? p['username']);
    if (oldUsername.isEmpty || newUsername.isEmpty) {
      return const PosCommandOutcome.invalid('old_and_new_username_required');
    }
    if (treatRenamedAsDone &&
        DatabaseService.getUserByUsername(oldUsername) == null &&
        DatabaseService.getUserByUsername(newUsername) != null) {
      return PosCommandOutcome.success(
        code: 'already_renamed',
        data: <String, dynamic>{
          'user': {'username': newUsername},
        },
      );
    }
    final ok = await DatabaseService.renameUserByUsername(
      oldUsername: oldUsername,
      newUsername: newUsername,
    );
    if (!ok) return const PosCommandOutcome.conflicting('rename_failed');
    scheduleCloudSync();
    return PosCommandOutcome.success(
      data: <String, dynamic>{
        'user': {'username': newUsername},
      },
    );
  }

  /// Remove a staff user.
  ///
  /// Convergent: the goal state is "this username is gone", which an absent
  /// user already satisfies.
  static Future<PosCommandOutcome> deleteStaff(
    Map<String, dynamic> p, {
    bool treatMissingAsDone = false,
  }) async {
    final username = _string(p['username']);
    if (username.isEmpty) {
      return const PosCommandOutcome.invalid('username_required');
    }
    if (treatMissingAsDone &&
        DatabaseService.getUserByUsername(username) == null) {
      return const PosCommandOutcome.success(code: 'already_absent');
    }
    final ok = await DatabaseService.deleteUserByUsername(username);
    if (!ok) return const PosCommandOutcome.conflicting('delete_failed');
    scheduleCloudSync();
    return const PosCommandOutcome.success();
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  /// Fire-and-forget kitchen check for a Cloud-originated walk-in or takeaway.
  ///
  /// Drinks-only orders and missing-printer setups are handled by
  /// [PrinterService] (no-op). Non-kitchen items are filtered downstream.
  @visibleForTesting
  static void sendKitchenCheck({
    required List<OrderItem> items,
    required String orderLabel,
    required String waiterName,
    String? tableLabel,
  }) {
    final lines = <String>[];
    for (final item in items) {
      var line = '${item.quantity}x ${item.itemName}';
      final comment = item.comment?.trim();
      if (comment != null && comment.isNotEmpty) {
        line += '\n  ⮑ $comment';
      }
      lines.add(line);
    }
    if (lines.isEmpty) return;
    PrinterService.printKitchenCheckInBackground(
      items: lines,
      tableNumber: tableLabel,
      orderNumber: orderLabel,
      waiterName: waiterName,
      createdAt: DateTime.now(),
    );
  }

  static void scheduleCloudSync() {
    ManagerSyncService.syncToManagerAppDebounced();
  }

  @visibleForTesting
  static List<OrderItem> parseOrderItems(dynamic itemsRaw) {
    final list = (itemsRaw as List?) ?? const [];
    final items = <OrderItem>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final name = _string(map['itemName'] ?? map['name']);
      final unitPrice = _double(map['unitPrice'] ?? map['price']) ?? 0.0;
      final qty = _int(map['quantity']) ?? 1;
      final itemKey = _string(map['itemKey'], fallback: name);
      items.add(
        OrderItem(
          itemKey: itemKey.isNotEmpty ? itemKey : name,
          itemName: name,
          unitPrice: unitPrice,
          quantity: qty,
          total: unitPrice * qty,
          comment: map['comment'] as String?,
        ),
      );
    }
    return items;
  }

  /// The word in front of a list of table numbers in a notification.
  ///
  /// „კუპე" used to be hardcoded for the second floor. Where a table has a
  /// name of its own the caller uses `TableNaming` instead of this; this is
  /// only the generic prefix for a bare list.
  static String _tableWordForFloor(String floor) {
    switch (floor.toLowerCase()) {
      case 'takeaway':
        return 'გატანა';
      default:
        return 'მაგიდა';
    }
  }

  /// Builds a "მაგიდა 5, 6" style segment from a list of table identifiers.
  ///
  /// Accepts raw numbers ("5") or POS-prefixed names ("Table 5", "VIP Zone 1").
  /// Takeaway pseudo-tables ("TA-90013") are skipped. Returns an empty string
  /// when there are no usable tables.
  @visibleForTesting
  static String formatTablesSegment(List<String> tables, String floor) {
    final clean = tables
        .map(
          (e) => e
              .toString()
              .trim()
              .replaceAll('Table ', '')
              .replaceAll('VIP Zone ', '')
              .trim(),
        )
        .where((e) => e.isNotEmpty && e != '0' && !e.startsWith('TA-'))
        .toList();
    if (clean.isEmpty) return '';
    return '${_tableWordForFloor(floor)} ${clean.join(', ')}';
  }

  /// The manager-facing message for an order content change.
  @visibleForTesting
  static String orderChangeMessage({
    required int posOrderId,
    required OrderItemChangeDiff diff,
    required bool totalChanged,
    required bool serviceFeeToggled,
    List<String> tableNumbers = const [],
    String floor = '',
  }) {
    if (diff.summaryLines.isNotEmpty) {
      final detail = diff.summaryLines.take(4).join('; ');
      final more = diff.summaryLines.length > 4
          ? ' (+${diff.summaryLines.length - 4})'
          : '';
      return 'შეკვეთა #$posOrderId — $detail$more';
    }
    if (serviceFeeToggled) {
      final tableSeg = formatTablesSegment(tableNumbers, floor);
      if (tableSeg.isNotEmpty) {
        return '$tableSeg — სერვისის საფასური განახლდა';
      }
      return 'შეკვეთა #$posOrderId — სერვისის საფასური განახლდა';
    }
    if (totalChanged) {
      return 'შეკვეთა #$posOrderId — თანხა განახლდა';
    }
    return 'შეკვეთა #$posOrderId განახლდა';
  }

  static Map<String, dynamic> _highlightMeta(List<OrderItem> items) {
    final keys = items
        .expand((i) => [i.itemKey, i.itemName])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return keys.isEmpty
        ? const <String, dynamic>{}
        : <String, dynamic>{'highlightItemKeys': keys.toList()};
  }

  static void _notify({required String message, Map<String, dynamic>? meta}) {
    PosLiveRefresh.bump();
    ManagerNotificationInbox.ingestLocal(
      title: 'სისტემა:',
      message: message,
      source: 'system',
      meta: meta,
    );
  }

  static int? _int(Object? raw) =>
      raw is num ? raw.toInt() : int.tryParse('$raw');

  static double? _double(Object? raw) =>
      raw is num ? raw.toDouble() : double.tryParse('$raw');

  static String _string(Object? raw, {String fallback = ''}) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  static String _actor(Object? raw) => _string(raw, fallback: defaultActor);

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
