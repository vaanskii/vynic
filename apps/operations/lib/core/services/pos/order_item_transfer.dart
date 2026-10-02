/// Moving ordered items from one open order to another.
///
/// The case this exists for: a party orders take-away and then decides to sit
/// down, or half a table moves to another one. Until now the only way through
/// that was to cancel the order and key it in again, which loses the audit
/// trail, the open time, and — when a reservation is attached — the booking.
///
/// The arithmetic lives here rather than in the dialog because it is the part
/// that has to be right: two orders' money changes at once, and getting it
/// wrong is not a visual bug.
library;

import 'package:vynic/core/services/pos/update/update_readiness.dart';

import 'dart:developer' as developer;
import 'package:uuid/uuid.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';
import 'package:vynic/core/services/edge/orders_tables/shadow.dart';
import 'package:vynic/core/services/edge/orders_tables/pos_shadow_projection.dart';
import 'package:vynic/core/services/sync/sync_events.dart';

import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/takeaway_order.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/audit/order_audit_details.dart';
import 'package:vynic/core/services/database_service.dart';

/// Which line to take from, and how many of it.
///
/// The line is named by its index in [Order.items] rather than by `itemKey`,
/// because an order merged from the mobile app can carry the same key twice
/// with different comments and those are genuinely different lines.
typedef OrderItemMove = ({int index, int quantity});

/// Why a transfer was refused.
///
/// A typed reason rather than a thrown string or a silent `false`: the dialog
/// has to tell the operator which of these happened, and a caller that ignores
/// the result should not be able to do so by accident.
enum OrderTransferError {
  /// Source and destination are the same order.
  sameOrder,

  /// The source is paid, closed or cancelled — its items are history.
  sourceFinalized,

  /// The destination is paid, closed or cancelled; items moved onto it would
  /// never be billed.
  destinationFinalized,

  /// No line had a quantity above zero.
  nothingSelected,

  /// A move named a line that is not there, or asked for more of it than the
  /// order holds.
  quantityOutOfRange,
  staleSource,
  staleDestination,
  identityConflict,
  businessDateChanged,
  auditLocked,
  tableOwnership,
  transferIdConflict,
  busy,
  recoveryRequired,
  persistenceFailure,
}

/// One line as it was actually moved.
class OrderTransferLine {
  const OrderTransferLine({
    required this.itemName,
    required this.quantity,
    required this.amount,
    this.comment,
    this.menuItemId,
    this.variantId,
  });

  final String itemName;
  final int quantity;

  /// The money that moved with it, in GEL.
  final double amount;
  final String? comment;
  final String? menuItemId;
  final String? variantId;
}

/// What a transfer did, or why it did nothing.
class OrderTransferResult {
  const OrderTransferResult._({
    this.error,
    this.moved = const [],
    this.sourceLeftEmpty = false,
    this.transferId,
  });

  const OrderTransferResult.failed(OrderTransferError reason)
    : this._(error: reason);

  const OrderTransferResult.applied({
    required List<OrderTransferLine> moved,
    required bool sourceLeftEmpty,
    String? transferId,
  }) : this._(
         moved: moved,
         sourceLeftEmpty: sourceLeftEmpty,
         transferId: transferId,
       );

  final OrderTransferError? error;
  final String? transferId;
  final List<OrderTransferLine> moved;

  /// The source has no items left. Not an error — a whole party moving is the
  /// ordinary case — but the caller is expected to say so out loud, because an
  /// open table with an empty bill on it looks like a mistake.
  final bool sourceLeftEmpty;

  bool get ok => error == null;

  int get totalQuantity => moved.fold(0, (sum, line) => sum + line.quantity);

  double get totalAmount => double.parse(
    moved.fold(0.0, (sum, line) => sum + line.amount).toStringAsFixed(2),
  );
}

abstract final class OrderItemTransfer {
  /// Moves [moves] from [source] to [destination], in memory.
  ///
  /// Both orders are mutated and their totals recomputed; nothing is written to
  /// disk. [apply] is the version that persists and audits — this one is split
  /// out so the arithmetic can be checked without a database.
  static OrderTransferResult move({
    required Order source,
    required Order destination,
    required List<OrderItemMove> moves,
  }) {
    if (identical(source, destination) ||
        source.orderId == destination.orderId) {
      return const OrderTransferResult.failed(OrderTransferError.sameOrder);
    }
    if (_isFinalized(source.status)) {
      return const OrderTransferResult.failed(
        OrderTransferError.sourceFinalized,
      );
    }
    if (_isFinalized(destination.status)) {
      return const OrderTransferResult.failed(
        OrderTransferError.destinationFinalized,
      );
    }

    final wanted = moves.where((m) => m.quantity > 0).toList();
    if (wanted.isEmpty) {
      return const OrderTransferResult.failed(
        OrderTransferError.nothingSelected,
      );
    }

    // Validate everything before mutating anything. A half-applied move would
    // leave two orders disagreeing about how many khinkali exist.
    final byIndex = <int, int>{};
    for (final move in wanted) {
      if (move.index < 0 || move.index >= source.items.length) {
        return const OrderTransferResult.failed(
          OrderTransferError.quantityOutOfRange,
        );
      }
      final running = (byIndex[move.index] ?? 0) + move.quantity;
      if (running > source.items[move.index].quantity) {
        return const OrderTransferResult.failed(
          OrderTransferError.quantityOutOfRange,
        );
      }
      byIndex[move.index] = running;
    }

    final moved = <OrderTransferLine>[];

    // Descending, so removing an emptied line cannot shift an index we have
    // not reached yet.
    final indexes = byIndex.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final index in indexes) {
      final line = source.items[index];
      final quantity = byIndex[index]!;

      // Split the line's existing total rather than recomputing it from
      // `unitPrice * quantity`. They are usually the same, but where they are
      // not — a price keyed in by hand, a rounding from an older build — the
      // money is what is on the bill, and the two halves must still add up to
      // it exactly.
      final movedAmount = double.parse(
        (line.total * quantity / line.quantity).toStringAsFixed(2),
      );
      final remainingAmount = double.parse(
        (line.total - movedAmount).toStringAsFixed(2),
      );

      _merge(
        destination: destination,
        line: line,
        quantity: quantity,
        amount: movedAmount,
      );

      moved.add(
        OrderTransferLine(
          itemName: line.itemName,
          quantity: quantity,
          amount: movedAmount,
          comment: line.comment,
          menuItemId: line.menuItemId,
          variantId: line.variantId,
        ),
      );

      if (quantity == line.quantity) {
        source.items.removeAt(index);
      } else {
        line.quantity -= quantity;
        line.total = remainingAmount;
      }
    }

    source.recalculateTotal();
    destination.recalculateTotal();

    return OrderTransferResult.applied(
      // Rebuilt in the order the operator picked them, not the reverse order
      // the loop needed.
      moved: moved.reversed.toList(),
      sourceLeftEmpty: source.items.isEmpty && source.packageItems.isEmpty,
    );
  }

  /// One recoverable operation includes both moves and empty-source cleanup.
  /// A caller retaining the same ID and immutable payload gets the recorded
  /// result on retry, even if the Orders have subsequently been edited.
  static Future<OrderTransferResult> apply({
    required Order source,
    required Order destination,
    required List<OrderItemMove> moves,
    required User user,
    required String sourceLabel,
    required String destinationLabel,
    AuditSource auditSource = AuditSource.pos,
    String? transferId,
    String? expectedBusinessDate,
  }) {
    final request = <String, dynamic>{
      'kind': 'move',
      'sourceOrder': OrderTransferIntent.snapshot(source),
      'destinationOrder': OrderTransferIntent.snapshot(destination),
      'moves': [
        for (final move in moves)
          {'index': move.index, 'quantity': move.quantity},
      ],
      'actorId': user.username,
      'source': auditSource.wireValue,
      'sourceLabel': sourceLabel,
      'destinationLabel': destinationLabel,
      'businessDate':
          expectedBusinessDate ??
          BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate()),
    };
    return _run(
      OrderTransferIntent.cloneMap(request),
      transferId ?? const Uuid().v4(),
      useRecordedBusinessDateOnRetry: expectedBusinessDate == null,
    );
  }

  /// Compatibility entrypoint: fresh transfers already completed this work.
  /// A genuinely empty legacy Order uses the same journaled cleanup coordinator.
  static Future<void> releaseEmptiedOrder(
    Order order, {
    required User user,
    Order? destination,
    AuditSource auditSource = AuditSource.pos,
    String? transferId,
  }) async {
    final request = <String, dynamic>{
      'kind': 'releaseEmpty',
      'sourceOrder': OrderTransferIntent.snapshot(order),
      'destinationOrder': null,
      'moves': <Map<String, int>>[],
      'actorId': user.username,
      'source': auditSource.wireValue,
      'sourceLabel': '',
      'destinationLabel': '',
      'businessDate': BusinessDayRepository.dateKey(
        BusinessDayRepository.getCurrentDate(),
      ),
      if (destination != null) 'cleanupDestinationOrderId': destination.orderId,
    };
    final result = await _run(
      request,
      transferId ?? const Uuid().v4(),
      useRecordedBusinessDateOnRetry: true,
    );
    if (!result.ok)
      throw StateError(
        'Empty Order transfer cleanup refused: ${result.error!.name}',
      );
  }

  static Future<OrderTransferResult> _run(
    Map<String, dynamic> request,
    String id, {
    bool useRecordedBusinessDateOnRetry = false,
  }) async {
    try {
      if (!OrderTransferJournalRepository.validId(id)) {
        return const OrderTransferResult.failed(
          OrderTransferError.transferIdConflict,
        );
      }
      final result = await LocalDataAdmission.exclusive(
        () => UpdateReadiness.track('transferItems', () async {
          var ownsIntent = false;
          try {
            List<OrderTransferIntent> records;
            try {
              records = OrderTransferJournalRepository.records();
            } catch (error) {
              LocalDataAdmission.failure =
                  'Order transfer journal requires recovery: $error';
              rethrow;
            }
            final prior = records
                .where((record) => record.id == id)
                .firstOrNull;
            if (prior != null) {
              if (useRecordedBusinessDateOnRetry) {
                request['businessDate'] = prior.request['businessDate'];
              }
              if (prior.fingerprint != PosBackupFormat.digest(request)) {
                return const OrderTransferResult.failed(
                  OrderTransferError.transferIdConflict,
                );
              }
              if (prior.pending) {
                ownsIntent = true;
                await _finish(prior);
              }
              return _result(prior);
            }
            if (records.any((record) => record.pending)) {
              LocalDataAdmission.failure =
                  'Order transfer requires startup recovery';
              return const OrderTransferResult.failed(
                OrderTransferError.recoveryRequired,
              );
            }
            final sourceImage = request['sourceOrder'] as Map;
            final sourceEntry = _findOrder(
              sourceImage['orderId'] as int,
              sourceImage['orderUuid'] as String,
            );
            final source = sourceEntry.$2;
            if (request['kind'] == 'releaseEmpty' &&
                (_isFinalized(source.status) ||
                    source.items.isNotEmpty ||
                    source.packageItems.isNotEmpty)) {
              return const OrderTransferResult.applied(
                moved: [],
                sourceLeftEmpty: false,
              );
            }
            if (!OrderTransferIntent.sameImage(
              OrderTransferIntent.snapshot(source),
              sourceImage,
            )) {
              throw const _TransferRefusal(OrderTransferError.staleSource);
            }
            (Object, Order)? destinationEntry;
            if (request['destinationOrder'] != null) {
              final image = request['destinationOrder'] as Map;
              destinationEntry = _findOrder(
                image['orderId'] as int,
                image['orderUuid'] as String,
              );
              if (!OrderTransferIntent.sameImage(
                OrderTransferIntent.snapshot(destinationEntry.$2),
                image,
              )) {
                throw const _TransferRefusal(
                  OrderTransferError.staleDestination,
                );
              }
            }
            if (BusinessDayRepository.dateKey(
                  BusinessDayRepository.getCurrentDate(),
                ) !=
                request['businessDate']) {
              throw const _TransferRefusal(
                OrderTransferError.businessDateChanged,
              );
            }
            final draft = source.clone();
            final destination = destinationEntry?.$2.clone();
            final result = request['kind'] == 'releaseEmpty'
                ? const OrderTransferResult.applied(
                    moved: [],
                    sourceLeftEmpty: true,
                  )
                : move(
                    source: draft,
                    destination: destination!,
                    moves: [
                      for (final move in request['moves'] as List)
                        (
                          index: move['index'] as int,
                          quantity: move['quantity'] as int,
                        ),
                    ],
                  );
            if (!result.ok) return result;
            final intent = _capture(
              id,
              request,
              sourceEntry.$1,
              draft,
              destinationEntry?.$1,
              destination,
              result,
            );
            // Old adapters may mint Order/line identities on read. Persist the
            // unmodified loaded rows before a durable plan references them.
            for (final entry in [
              sourceEntry,
              if (destinationEntry != null) destinationEntry,
            ]) {
              await DatabaseCore.orderBox!.put(entry.$1, entry.$2);
              await DatabaseCore.orderBox!.flush();
            }
            ownsIntent =
                true; // Also latch an uncertain failed intent put/flush.
            await OrderTransferJournalRepository.write(intent);
            await _finish(intent);
            return _result(intent);
          } on _TransferRefusal catch (refusal) {
            return OrderTransferResult.failed(refusal.reason);
          } catch (error) {
            if (ownsIntent) {
              // Latch before exclusive.finally can release waiting writers, even
              // if the completed receipt's put succeeded but its flush failed.
              LocalDataAdmission.failure =
                  'Order transfer recovery required: $error';
            }
            rethrow;
          }
        }),
        operation: 'transferItems',
      );
      if (result.ok && result.transferId != null) {
        // Durable completion is already confirmed. A sync notification cannot
        // turn that result into a reported storage failure.
        try {
          AuditRepository.notifyAuditChanged();
        } catch (error, stack) {
          developer.log(
            'Completed transfer audit notification failed',
            name: 'order_item_transfer',
            error: error,
            stackTrace: stack,
          );
        }
        // The explicit development shadow compares committed ordinary-open
        // state outside local admission. Empty-source closure remains outside
        // its Phase 2A codec and is recorded as an unsupported diagnostic.
        if (request['destinationOrder'] != null &&
            OrderTableShadow.observer != null) {
          try {
            List<Order> current() => [
              _findOrder(
                (request['sourceOrder'] as Map)['orderId'] as int,
                (request['sourceOrder'] as Map)['orderUuid'] as String,
              ).$2,
              _findOrder(
                (request['destinationOrder'] as Map)['orderId'] as int,
                (request['destinationOrder'] as Map)['orderUuid'] as String,
              ).$2,
            ];
            await OrderTableShadow.observe(
              proposed: () => PosShadowProjection.orders(current()),
              actual: () => PosShadowProjection.orders(current()),
              operation: () async {},
            );
          } catch (error, stack) {
            developer.log(
              'Completed transfer shadow notification failed',
              name: 'order_item_transfer',
              error: error,
              stackTrace: stack,
            );
          }
        }
        SyncHub.notify(
          SyncEvent(
            type: SyncEventType.orders,
            action: 'items_transferred',
            payload: {
              'orderId': (request['sourceOrder'] as Map)['orderId'],
              'transferId': id,
            },
          ),
        );
        SyncHub.notify(
          SyncEvent(type: SyncEventType.tables, action: 'updated'),
        );
        SyncHub.notify(
          SyncEvent(type: SyncEventType.reservations, action: 'updated'),
        );
      }
      return result;
    } catch (error, stack) {
      developer.log(
        'Order item transfer failed',
        name: 'order_item_transfer',
        error: error,
        stackTrace: stack,
      );
      if (LocalDataAdmission.failure != null) {
        if (UpdateReadiness.enabled)
          UpdateReadiness.failure = LocalDataAdmission.failure;
        return const OrderTransferResult.failed(
          OrderTransferError.recoveryRequired,
        );
      }
      return OrderTransferResult.failed(
        error is StateError && error.toString().contains('transition is active')
            ? OrderTransferError.busy
            : OrderTransferError.persistenceFailure,
      );
    }
  }

  static (Object, Order) _findOrder(int orderId, String uuid) {
    final entries = [
      for (final key in DatabaseCore.orderBox!.keys)
        if (DatabaseCore.orderBox!.get(key)!.orderId == orderId)
          (key as Object, DatabaseCore.orderBox!.get(key)!),
    ];
    if (entries.length != 1 || entries.single.$2.orderUuid != uuid) {
      throw const _TransferRefusal(OrderTransferError.identityConflict);
    }
    return entries.single;
  }

  static OrderTransferIntent _capture(
    String id,
    Map<String, dynamic> request,
    Object sourceKey,
    Order draft,
    Object? destinationKey,
    Order? destination,
    OrderTransferResult result,
  ) {
    // Hive's native DateTime adapter stores milliseconds. Journal images must
    // compare identically after an actual process restart.
    final clock = DatabaseService.getCurrentDateTime();
    final now = DateTime.fromMillisecondsSinceEpoch(
      clock.millisecondsSinceEpoch,
      isUtc: clock.isUtc,
    );
    final actor = request['actorId'] as String;
    final auditSource = AuditSource.values.firstWhere(
      (s) => s.wireValue == request['source'],
    );
    final beforeSource = OrderTransferIntent.orderImage(request['sourceOrder']);
    final effects = <Map<String, dynamic>>[];
    void effect(
      String phase,
      String store,
      Object key,
      Object? before,
      Map<String, dynamic> after,
    ) {
      effects.add({
        'phase': phase,
        'store': store,
        'key': key,
        'before': before,
        'after': after,
      });
    }

    draft.updatedAt = now;
    if (destination != null) {
      destination.updatedAt = now;
      effect(
        'destinationWritten',
        'orders',
        destinationKey!,
        request['destinationOrder'],
        OrderTransferIntent.snapshot(destination),
      );
    }
    if (request['kind'] == 'move') {
      effect(
        'sourceWritten',
        'orders',
        sourceKey,
        request['sourceOrder'],
        OrderTransferIntent.snapshot(draft),
      );
    }
    AuditReport report(Order order) {
      final key = AuditRepository.buildAuditReportKey(order.orderId);
      final raw = DatabaseCore.auditLogBox!.get(key);
      final value = raw == null
          ? AuditReport(
              reportId: key,
              orderId: order.orderId,
              tableNumbers: List.of(order.tableNumbers),
              floor: order.floor,
              openedById: order.createdBy,
              openedByName: order.createdBy,
              openedAt: order.createdAt,
              status: AuditReportStatus.open,
              events: [],
              updatedAt: now,
            )
          : AuditReport.fromMap(raw as Map);
      if (value.locked || value.orderId != order.orderId) {
        throw const _TransferRefusal(OrderTransferError.auditLocked);
      }
      return value;
    }

    AuditReport append(
      AuditReport report,
      List<AuditEvent> events, {
      bool close = false,
    }) {
      final prior = report.orderedEvents;
      var next = prior.fold(
        0,
        (int n, e) =>
            e.sequence != null && e.sequence! >= n ? e.sequence! + 1 : n,
      );
      return report.copyWith(
        events: [
          ...prior,
          for (final event in events) event.copyWith(sequence: next++),
        ],
        updatedAt: now,
        status: close ? AuditReportStatus.closed : report.status,
        locked: close,
        closedAt: close ? now : report.closedAt,
        closedById: close ? actor : report.closedById,
        closedByName: close ? actor : report.closedByName,
      );
    }

    Map<String, dynamic> details(Order own) => {
      ...OrderAuditDetails.base(
        order: own,
        orderKind: _kindOf(own),
        source: auditSource,
        actorId: actor,
      ),
      'transferId': id,
      'fromOrderId': draft.orderId,
      'fromOrderUuid': draft.orderUuid,
      if (destination != null) 'toOrderId': destination.orderId,
      if (destination != null) 'toOrderUuid': destination.orderUuid,
      'fromTableRefs': OrderAuditDetails.tableRefs(draft),
      if (destination != null)
        'toTableRefs': OrderAuditDetails.tableRefs(destination),
    };
    List<AuditEvent> moveEvents(Order own, bool incoming) => [
      for (var i = 0; i < result.moved.length; i++)
        AuditEvent(
          type: AuditEventType.moveItems,
          itemName: result.moved[i].itemName,
          previousQty: incoming ? 0 : result.moved[i].quantity,
          newQty: incoming ? result.moved[i].quantity : 0,
          waiterId: actor,
          waiterName: actor,
          timestamp: now,
          note: incoming
              ? 'გადმოტანილია — ${request['sourceLabel']}'
              : 'გადატანილია — ${request['destinationLabel']}',
          details: {
            ...details(own),
            'direction': incoming ? 'IN' : 'OUT',
            'transferLine': i,
            'quantity': result.moved[i].quantity,
            'amount': result.moved[i].amount,
            'transferAmount': result.totalAmount,
            if (result.moved[i].comment?.trim().isNotEmpty == true)
              'comment': result.moved[i].comment!.trim(),
            if (result.moved[i].menuItemId != null)
              'menuItemId': result.moved[i].menuItemId,
            if (result.moved[i].variantId != null)
              'variantId': result.moved[i].variantId,
          },
        ),
    ];
    final sourceReport = report(beforeSource);
    final sourceAuditKey = AuditRepository.buildAuditReportKey(draft.orderId);
    final rawSourceAudit = DatabaseCore.auditLogBox!.get(sourceAuditKey);
    var sourceAfterMoves = sourceReport;
    if (destination != null) {
      final destinationReport = report(destination);
      final key = destinationReport.reportId;
      effect(
        'destinationAudited',
        'auditReport',
        key,
        DatabaseCore.auditLogBox!.get(key),
        append(destinationReport, moveEvents(destination, true)).toMap(),
      );
      sourceAfterMoves = append(sourceReport, moveEvents(draft, false));
      effect(
        'sourceAudited',
        'auditReport',
        sourceAuditKey,
        rawSourceAudit,
        sourceAfterMoves.toMap(),
      );
    }
    if (result.sourceLeftEmpty) {
      if (!isTakeawayOrder(draft)) {
        for (final key in DatabaseCore.tableBox!.keys) {
          final table = DatabaseCore.tableBox!.get(key)!;
          if (table.floor != draft.floor ||
              !draft.tableNumbers.contains(table.tableNumber))
            continue;
          if (table.activeOrderId != draft.orderId) {
            if (table.isReserved ||
                table.activeOrderId != null ||
                table.reservationId != null) {
              throw const _TransferRefusal(OrderTransferError.tableOwnership);
            }
            continue;
          }
          final before = _tableImage(table);
          final after = Map<String, dynamic>.from(before)
            ..addAll({
              'isReserved': false,
              'reservedAt': null,
              'reservedBy': null,
              'activeOrderId': null,
              'reservationId': null,
            });
          effect(
            'tableReleased:${effects.length}',
            'tables',
            key as Object,
            before,
            after,
          );
        }
      }
      for (final key in DatabaseCore.reservationBox!.keys) {
        final reservation = DatabaseCore.reservationBox!.get(key)!;
        if (!ReservationClassification.isRealAdvanceBooking(reservation) ||
            reservation.linkedOrderId != draft.orderId ||
            reservation.statusEnum.isFinal)
          continue;
        final before = _reservationImage(reservation);
        final after = {
          ...before,
          'status': ReservationStatus.completed.storageValue,
        };
        effect(
          'reservationCompleted:${effects.length}',
          'reservationState',
          key as Object,
          before,
          after,
        );
        final audit = AuditEventLog(
          id: const Uuid().v5(id, 'reservation:${reservation.id}'),
          action: ReservationAuditAction.complete,
          userId: actor,
          entityType: GlobalAuditEntity.reservation,
          entityId: reservation.id,
          createdAt: now,
          deviceType: 'windows',
          data: {
            ...ReservationAudit.snapshot(reservation),
            'status': 'completed',
            'previousStatus': reservation.status,
            'newStatus': 'completed',
            'source': auditSource.wireValue,
            'actorId': actor,
            'actorName': actor,
            'businessDate': request['businessDate'],
            'reason': 'Order emptied by transfer',
            'transferId': id,
          },
        );
        effect(
          'reservationAudited:${effects.length}',
          'auditEvent',
          audit.id,
          null,
          audit.toMap(),
        );
      }
      final before = request['kind'] == 'move'
          ? OrderTransferIntent.snapshot(draft)
          : request['sourceOrder'];
      draft.status = OrderStatus.closed.storageValue;
      draft.closedAt = now;
      draft.updatedAt = now;
      effect(
        'sourceClosed',
        'orders',
        sourceKey,
        before,
        OrderTransferIntent.snapshot(draft),
      );
      final targetId =
          destination?.orderId ?? request['cleanupDestinationOrderId'];
      final closing = AuditEvent(
        type: AuditEventType.transferClose,
        itemName: OrderAuditDetails.orderItemName,
        previousQty: 0,
        newQty: 0,
        waiterId: actor,
        waiterName: actor,
        timestamp: now,
        note: targetId != null
            ? 'ყველა პოზიცია გადატანილია — შეკვეთა #$targetId'
            : 'ყველა პოზიცია გადატანილია',
        details: {
          ...details(draft),
          'closeReason': 'EMPTIED_BY_TRANSFER',
          'isFiscal': false,
          'grossAmount': 0.0,
          'collectedNow': 0.0,
          if (targetId != null) 'transferredToOrderId': targetId,
          if (destination != null)
            'transferredToTableRefs': OrderAuditDetails.tableRefs(destination),
        },
      );
      effect(
        'closureAudited',
        'auditReport',
        sourceAuditKey,
        destination != null ? sourceAfterMoves.toMap() : rawSourceAudit,
        append(sourceAfterMoves, [closing], close: true).toMap(),
      );
    }
    return OrderTransferIntent({
      'version': 1,
      'transferId': id,
      'fingerprint': PosBackupFormat.digest(request),
      'request': request,
      'startedAt': now.toIso8601String(),
      'phase': 'intent',
      'nextEffect': 0,
      'effects': effects,
      'result': {
        'sourceLeftEmpty': result.sourceLeftEmpty,
        'moved': [
          for (final line in result.moved)
            {
              'itemName': line.itemName,
              'quantity': line.quantity,
              'amount': line.amount,
              'comment': line.comment,
              'menuItemId': line.menuItemId,
              'variantId': line.variantId,
            },
        ],
      },
    });
  }

  static Map<String, dynamic> _tableImage(TableModel table) {
    final value = table.toJson()..remove('currentBill');
    if (table.reservedAt != null) {
      value['reservedAt'] = DateTime.fromMillisecondsSinceEpoch(
        table.reservedAt!.millisecondsSinceEpoch,
        isUtc: table.reservedAt!.isUtc,
      ).toIso8601String();
    }
    return value;
  }

  static Map<String, dynamic> _reservationImage(Reservation value) => {
    'id': value.id,
    'status': value.status,
    'linkedOrderId': value.linkedOrderId,
  };
  static Object? persistedImage(
    String store,
    Object key, {
    Map<String, Map<dynamic, dynamic>>? stores,
  }) {
    final raw = stores != null
        ? stores[store == 'auditReport' || store == 'auditEvent'
              ? 'auditLog'
              : store == 'reservationState'
              ? 'reservations'
              : store]![key]
        : switch (store) {
            'orders' => DatabaseCore.orderBox!.get(key),
            'tables' => DatabaseCore.tableBox!.get(key),
            'reservationState' => DatabaseCore.reservationBox!.get(key),
            'auditReport' || 'auditEvent' => DatabaseCore.auditLogBox!.get(key),
            _ => throw StateError('Unknown transfer store'),
          };
    if (raw == null) return null;
    return switch (store) {
      'orders' => OrderTransferIntent.snapshot(raw as Order),
      'tables' => _tableImage(raw as TableModel),
      'reservationState' => _reservationImage(raw as Reservation),
      'auditEvent' => OrderTransferIntent.cloneMap(raw as Map)..['synced'] = 0,
      _ => OrderTransferIntent.cloneMap(raw as Map),
    };
  }

  static Future<void> _finish(OrderTransferIntent intent) async {
    if (!intent.pending) return;
    if (BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate()) !=
        intent.request['businessDate']) {
      throw StateError('Order transfer business date changed');
    }
    OrderTransferJournalRepository.validateCurrent(intent, persistedImage);
    final effects = intent.effects;
    for (var i = intent.nextEffect; i < effects.length; i++) {
      final effect = effects[i];
      final key = effect['key'] as Object;
      final after = OrderTransferIntent.cloneMap(effect['after'] as Map);
      if (!OrderTransferIntent.sameImage(
        persistedImage(effect['store'] as String, key),
        after,
      )) {
        switch (effect['store']) {
          case 'orders':
            await DatabaseCore.orderBox!.put(
              key,
              OrderTransferIntent.orderImage(after),
            );
            await DatabaseCore.orderBox!.flush();
          case 'tables':
            await DatabaseCore.tableBox!.put(key, TableModel.fromJson(after));
            await DatabaseCore.tableBox!.flush();
          case 'reservationState':
            final reservation = DatabaseCore.reservationBox!.get(key)!;
            if (!ReservationClassification.isRealAdvanceBooking(reservation)) {
              throw StateError(
                'Transfer target is no longer a genuine Reservation',
              );
            }
            reservation.status = after['status'] as String;
            await DatabaseCore.reservationBox!.put(key, reservation);
            await DatabaseCore.reservationBox!.flush();
          case 'auditReport':
            await DatabaseCore.auditLogBox!.put(key, after);
            await DatabaseCore.auditLogBox!.flush();
          case 'auditEvent':
            await AuditEventService.appendDurableOnce(
              AuditEventLog.fromMap(after),
            );
          default:
            throw StateError('Unknown transfer effect');
        }
      } else {
        // An uncertain put already has the intended image. Still confirm its
        // durability before advancing the phase receipt.
        switch (effect['store']) {
          case 'orders':
            await DatabaseCore.orderBox!.flush();
          case 'tables':
            await DatabaseCore.tableBox!.flush();
          case 'reservationState':
            await DatabaseCore.reservationBox!.flush();
          case 'auditReport' || 'auditEvent':
            await DatabaseCore.auditLogBox!.flush();
        }
      }
      intent = intent.receipt(i + 1);
      await OrderTransferJournalRepository.write(intent);
    }
    await OrderTransferJournalRepository.write(intent.complete);
  }

  static OrderTransferResult _result(OrderTransferIntent intent) {
    final result = intent.data['result'] as Map;
    return OrderTransferResult.applied(
      transferId: intent.id,
      sourceLeftEmpty: result['sourceLeftEmpty'] as bool,
      moved: [
        for (final line in result['moved'] as List)
          OrderTransferLine(
            itemName: line['itemName'] as String,
            quantity: line['quantity'] as int,
            amount: (line['amount'] as num).toDouble(),
            comment: line['comment'] as String?,
            menuItemId: line['menuItemId'] as String?,
            variantId: line['variantId'] as String?,
          ),
      ],
    );
  }

  /// Called before Menu/defaults/migrations, and under restore's existing gate.
  static Future<void> recoverUnderAdmission() async {
    final records = OrderTransferJournalRepository.records();
    if (records.where((record) => record.pending).length > 1) {
      throw const FormatException('Multiple pending Order transfers');
    }
    for (final intent in records) {
      if (intent.pending) await _finish(intent);
    }
  }

  static Future<void> recoverPending() async {
    if (!DatabaseCore.metaBox!.keys.any(
      (key) =>
          key is String &&
          key.startsWith(OrderTransferJournalRepository.prefix),
    ))
      return;
    LocalDataAdmission.failure = 'Order transfer requires startup recovery';
    try {
      await LocalDataAdmission.exclusive(
        recoverUnderAdmission,
        recovery: true,
        operation: 'transferItems',
      );
      LocalDataAdmission.failure = null;
      if (UpdateReadiness.failure?.startsWith('Order transfer') ?? false)
        UpdateReadiness.failure = null;
    } catch (error) {
      LocalDataAdmission.failure = 'Order transfer recovery failed: $error';
      rethrow;
    }
  }

  static String _kindOf(Order order) {
    if (order.packageId?.trim().isNotEmpty == true) {
      return OrderAuditDetails.package;
    }
    if (isTakeawayOrder(order)) return OrderAuditDetails.takeaway;
    return OrderAuditDetails.walkIn;
  }

  /// Adds [quantity] of [line] to [destination], stacking onto a line that is
  /// already the same thing.
  ///
  /// „The same thing" means the same item *and* the same comment. Merging on
  /// the key alone would silently drop one order's „ხახვის გარეშე".
  static void _merge({
    required Order destination,
    required OrderItem line,
    required int quantity,
    required double amount,
  }) {
    final comment = _normalizeComment(line.comment);
    for (final existing in destination.items) {
      if (existing.itemKey == line.itemKey &&
          existing.menuItemId == line.menuItemId &&
          existing.variantId == line.variantId &&
          _normalizeComment(existing.comment) == comment) {
        existing.quantity += quantity;
        existing.total = double.parse(
          (existing.total + amount).toStringAsFixed(2),
        );
        return;
      }
    }
    destination.items.add(
      OrderItem(
        // A full unmerged move keeps line identity; a split creates a new line.
        lineUuid: quantity == line.quantity ? line.lineUuid : null,
        itemKey: line.itemKey,
        itemName: line.itemName,
        unitPrice: line.unitPrice,
        quantity: quantity,
        total: amount,
        comment: line.comment,
        menuItemId: line.menuItemId,
        variantId: line.variantId,
      ),
    );
  }

  static String? _normalizeComment(String? comment) {
    final trimmed = comment?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static bool _isFinalized(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'paid' ||
        normalized == 'closed' ||
        normalized == 'cancelled';
  }
}

class _TransferRefusal implements Exception {
  const _TransferRefusal(this.reason);
  final OrderTransferError reason;
}
