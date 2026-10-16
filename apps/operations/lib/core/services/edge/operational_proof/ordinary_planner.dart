import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/services/audit/order_audit_details.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

import 'domain.dart';
import 'intent_adapter.dart';
import 'planning_view.dart';

class OperationalCreateCommand {
  OperationalCreateCommand({
    required this.orderKey,
    required this.floor,
    required List<String> tables,
    required List<Map<String, dynamic>> items,
    required this.menuRevision,
    required this.menuFingerprint,
    this.includeServiceFee,
    this.customerName = '',
    this.customerPhone = '',
    this.pickupTime = '',
    this.notes,
  }) : tables = List.unmodifiable(tables),
       items = List.unmodifiable(items.map(planningFreeze));
  final ProofKey orderKey;
  final String floor, menuFingerprint, customerName, customerPhone, pickupTime;
  final List<String> tables;
  final List<Map<String, dynamic>> items;
  final int menuRevision;
  final bool? includeServiceFee;
  final String? notes;
}

/// Detached ordinary walk-in/takeaway creation, physical movement and business
/// cancellation. Business images pass the existing ownership journal validator.
/// No method reads Hive, generates IDs, calls the clock, commits or prints.
abstract final class OrdinaryOperationalPlanner {
  static OperationalAdaptedPlan create(
    OperationalPlanningView view,
    OperationalCreateCommand command,
  ) {
    view.authorize('create');
    final context = view.context, policy = view.business(view.policyKey);
    planningRequire(
      command.menuRevision == policy['menuRevision'] &&
          command.menuFingerprint == policy['menuFingerprint'],
      OperationalPlanningFailureCode.staleView,
      'Operator item/catalog revision differs from admitted policy',
    );
    planningRequire(
      command.orderKey.kind == ProofEntityKind.order &&
          view.entity(command.orderKey) == null,
      OperationalPlanningFailureCode.staleView,
      'New Order identity is not absent',
    );
    final identity = view.identities.identity(command.orderKey),
        number = view.lastOrderId + 1;
    planningRequire(
      identity.orderNumber == number,
      OperationalPlanningFailureCode.ambiguousIdentity,
      'New order number must be control.lastOrderId+1',
    );
    final takeaway = command.floor == 'takeaway';
    planningRequire(
      !takeaway || command.includeServiceFee != true,
      OperationalPlanningFailureCode.unsupported,
      'Takeaway creation has no service fee',
    );
    final tables = takeaway ? ['TA-$number'] : command.tables.toSet().toList();
    planningRequire(
      takeaway || tables.isNotEmpty,
      OperationalPlanningFailureCode.invalidPlan,
      'Select physical tables',
    );
    final order = Order(
      orderUuid: command.orderKey.id,
      orderId: number,
      floor: command.floor,
      tableNumbers: tables,
      items: _lines(command.items),
      totalAmount: 0,
      createdAt: context.occurredAt,
      createdBy: context.actorId,
      openedByUserId: takeaway ? null : context.actorId,
      status: 'pending',
      includeServiceFee: takeaway
          ? false
          : command.includeServiceFee ?? policy['defaultIncludeServiceFee'],
      customerName: takeaway ? command.customerName : '',
      customerPhone: takeaway ? command.customerPhone : '',
      pickupTime: takeaway ? command.pickupTime : '',
    );
    order.recalculateTotal(serviceFeeRate: view.serviceFeeRate);
    planningRequire(
      order.createdAt.toIso8601String().split('T').first == view.businessDate,
      OperationalPlanningFailureCode.staleView,
      'Frozen creation time differs from Day',
    );
    final request = <String, dynamic>{
      'kind': takeaway ? 'takeaway' : 'dineIn',
      if (!takeaway) 'floor': command.floor,
      if (!takeaway) 'tables': tables,
      'actor': context.actorId,
      'items': order.items
          .map(OrderTableMutationRepository.itemRequest)
          .toList(),
      if (!takeaway) 'includeServiceFee': command.includeServiceFee,
      'source': context.source.wireValue,
      if (!takeaway) ...{
        'forPackage': false,
        'reservationId': null,
        'customerName': null,
      },
      if (takeaway) ...{
        'customerName': command.customerName,
        'customerPhone': command.customerPhone,
        'pickupTime': command.pickupTime,
        'notes': command.notes,
      },
      'expectedBusinessDate': view.businessDate,
    };
    final effects = <Map<String, dynamic>>[
      _effect(
        'orders',
        identity.legacyKey,
        null,
        OrderTableMutationRepository.image(order),
      ),
      _effect('settings', 'lastOrderId', view.lastOrderId, number),
    ];
    if (!takeaway)
      for (final label in tables) {
        final row = view.identities.table('${command.floor}/$label'),
            before = view.business(row.key);
        final table = TableModel.fromJson(Map.of(before));
        planningRequire(
          !table.isReserved && table.activeOrderId == null,
          OperationalPlanningFailureCode.ownershipConflict,
          'Physical destination is busy',
        );
        table
          ..isReserved = true
          ..activeOrderId = number
          ..reservedBy = context.actorId
          ..reservedAt = context.occurredAt
          ..reservationId = null;
        effects.add(
          _effect(
            'tables',
            row.legacyKey,
            before,
            OrderTableMutationRepository.tableImage(table),
          ),
        );
      }
    final reportKey = AuditRepository.buildAuditReportKey(number);
    final reportIdentity = view.identities.legacy('auditReport', reportKey);
    planningRequire(
      view.entity(reportIdentity.key) == null,
      OperationalPlanningFailureCode.staleView,
      'New Order already has an audit report',
    );
    final events = <AuditEvent>[
      AuditEvent(
        type: takeaway
            ? AuditEventType.createTakeaway
            : AuditEventType.createWalkIn,
        itemName: OrderAuditDetails.orderItemName,
        previousQty: 0,
        newQty: 0,
        waiterId: context.actorId,
        waiterName: context.actorId,
        timestamp: context.occurredAt,
        details: {
          ..._details(view, order, takeaway ? 'TAKEAWAY' : 'WALK_IN'),
          if (!takeaway) 'includeServiceFee': order.includeServiceFee,
          if (takeaway) ...{
            if (command.customerName.trim().isNotEmpty)
              'customerName': command.customerName.trim(),
            if (command.customerPhone.trim().isNotEmpty &&
                command.customerPhone.trim() != '-')
              'customerPhone': command.customerPhone.trim(),
            if (command.pickupTime.trim().isNotEmpty)
              'pickupTime': command.pickupTime.trim(),
          },
        },
      ),
      for (final item in order.items)
        AuditEvent(
          type: AuditEventType.addItem,
          itemName: item.itemName,
          previousQty: 0,
          newQty: item.quantity,
          waiterId: context.actorId,
          waiterName: context.actorId,
          timestamp: context.occurredAt,
          details: {
            if (item.menuItemId != null) 'menuItemId': item.menuItemId,
            if (item.variantId != null) 'variantId': item.variantId,
          },
        ),
    ];
    final report = AuditReport(
      reportId: reportKey,
      orderId: number,
      tableNumbers: tables,
      floor: order.floor,
      openedById: context.actorId,
      openedByName: context.actorId,
      openedAt: context.occurredAt,
      status: AuditReportStatus.open,
      locked: false,
      updatedAt: context.occurredAt,
      events: [
        for (var i = 0; i < events.length; i++) events[i].copyWith(sequence: i),
      ],
    );
    effects.add(_effect('auditReport', reportKey, null, report.toMap()));
    final global = AuditEventLog(
      id: '${context.requestId}:created',
      action: takeaway ? 'TAKEAWAY_ORDER_CREATED' : 'ORDER_CREATED',
      userId: context.actorId,
      entityType: GlobalAuditEntity.order,
      entityId: '$number',
      createdAt: context.occurredAt,
      deviceType: 'pos',
      data: {
        'requestId': context.requestId,
        'orderId': number,
        'tableNumbers': tables,
        'floor': order.floor,
        'total': order.totalAmount,
      },
    );
    effects.add(_effect('auditEvent', global.id, null, global.toMap()));
    return _finish(view, 'create', request, order, effects);
  }

  static OperationalAdaptedPlan move(
    OperationalPlanningView view, {
    required ProofKey orderKey,
    required String floor,
    required List<String> tables,
  }) {
    view.authorize('move');
    planningRequire(
      view.context.source == AuditSource.pos,
      OperationalPlanningFailureCode.unsupported,
      'Existing physical movement audit is POS-only',
    );
    final before = view.business(orderKey),
        order = OrderTransferIntent.orderImage(before);
    planningRequire(
      !order.statusEnum.isTerminal &&
          order.floor != 'takeaway' &&
          floor != 'takeaway' &&
          tables.isNotEmpty,
      OperationalPlanningFailureCode.unsupported,
      'Physical movement needs a live physical Order',
    );
    final target = tables.toSet().toList(),
        after = OrderTransferIntent.orderImage(before)
          ..tableNumbers = target
          ..floor = floor
          ..updatedAt = view.context.occurredAt;
    final effects = <Map<String, dynamic>>[
      _effect(
        'orders',
        view.identities.identity(orderKey).legacyKey,
        before,
        OrderTableMutationRepository.image(after),
      ),
    ];
    for (final ref in {
      for (final t in order.tableNumbers) '${order.floor}/$t',
      for (final t in target) '$floor/$t',
    }) {
      final row = view.identities.table(ref),
          image = view.business(row.key),
          table = TableModel.fromJson(Map.of(image));
      final owns = table.floor == floor && target.contains(table.tableNumber);
      planningRequire(
        owns
            ? (table.activeOrderId == null ||
                      table.activeOrderId == order.orderId) &&
                  (!table.isReserved || table.activeOrderId == order.orderId)
            : table.activeOrderId == order.orderId,
        OperationalPlanningFailureCode.ownershipConflict,
        'Movement source/destination ownership changed',
      );
      if (owns)
        table
          ..isReserved = true
          ..activeOrderId = order.orderId
          ..reservedBy = view.context.actorId
          ..reservedAt = view.context.occurredAt;
      else
        table.free();
      effects.add(
        _effect(
          'tables',
          row.legacyKey,
          image,
          OrderTableMutationRepository.tableImage(table),
        ),
      );
    }
    final reportIdentity = view.identities.legacy(
      'auditReport',
      AuditRepository.buildAuditReportKey(order.orderId),
    );
    final reportBefore = view.business(reportIdentity.key),
        prior = AuditReport.fromMap(reportBefore);
    planningRequire(
      !prior.locked,
      OperationalPlanningFailureCode.recoveryRequired,
      'Move needs an open report',
    );
    final event = AuditEvent(
      type: AuditEventType.custom,
      itemName: 'ORDER',
      previousQty: 0,
      newQty: 0,
      waiterId: view.context.actorId,
      waiterName: view.context.actorId,
      timestamp: view.context.occurredAt,
      sequence: _sequence(prior),
      details: {
        'action': 'TABLE_CHANGED',
        'requestId': view.context.requestId,
        'fromTables': order.tableNumbers,
        'fromFloor': order.floor,
        'toTables': target,
        'toFloor': floor,
        ..._details(view, after, 'WALK_IN'),
      },
    );
    final report = prior.copyWith(
      events: [...prior.events, event],
      updatedAt: view.context.occurredAt,
      tableNumbers: target,
      floor: floor,
    );
    effects.add(
      _effect(
        'auditReport',
        reportIdentity.legacyKey,
        reportBefore,
        report.toMap(),
      ),
    );
    final linked = _linked(view, order.orderId);
    planningRequire(
      linked.length <= 1,
      OperationalPlanningFailureCode.ownershipConflict,
      'Linked booking is ambiguous',
    );
    for (final booking in linked) {
      final b = view.business(booking.key), a = OrderTransferIntent.cloneMap(b);
      final refs = [
        for (final t in target) TableRef(floor: floor, tableNumber: t),
      ];
      a['tableRefs'] = refs.map((r) => r.encode()).toList();
      a['tableNumbers'] = ReservationTableAvailability.legacyCodesOf(refs);
      effects.add(_effect('reservation', booking.legacyKey, b, a));
    }
    return _finish(
      view,
      'move',
      {
        'order': before,
        'tableNumbers': List.of(tables),
        'floor': floor,
        'actor': view.context.actorId,
      },
      after,
      effects,
    );
  }

  static OperationalAdaptedPlan cancel(
    OperationalPlanningView view, {
    required ProofKey orderKey,
    String? reason,
    String? approvedBy,
  }) {
    view.authorize('cancel');
    final before = view.business(orderKey),
        order = OrderTransferIntent.orderImage(before),
        context = view.context;
    planningRequire(
      !order.statusEnum.isTerminal,
      OperationalPlanningFailureCode.unsupported,
      'Terminal Order cancellation needs its existing lifecycle outcome',
    );
    final approver = approvedBy?.trim();
    if (approver?.isNotEmpty == true) {
      final approverKey = view.identities
          .named(ProofEntityKind.staff, approver!)
          .key;
      final staff = view.business(approverKey);
      planningRequire(
        staff['enabled'] == true &&
            (staff['permissions'] as List).contains('approveCancel'),
        OperationalPlanningFailureCode.unsupported,
        'Approver lacks frozen authority',
      );
    }
    planningRequire(
      view.business(view.policyKey)['cancelRequiresApproval'] != true ||
          approver?.isNotEmpty == true,
      OperationalPlanningFailureCode.unsupported,
      'Cancellation policy requires an approver',
    );
    final reportIdentity = view.identities.legacy(
      'auditReport',
      AuditRepository.buildAuditReportKey(order.orderId),
    );
    final reportBefore = view.entity(reportIdentity.key) == null
        ? null
        : view.business(reportIdentity.key);
    final prior = reportBefore == null
        ? null
        : AuditReport.fromMap(reportBefore);
    final sales = view
        .kind(ProofEntityKind.sale)
        .where((e) => !e.tombstone)
        .where((e) {
          final s = view.business(e.key), tx = s['finalTransaction'];
          return s['orderId'] == order.orderId &&
              s['isCancelled'] == true &&
              (tx is Map && tx['type'] == 'cancelled_order' ||
                  s['paymentMethod'] == 'cancelled');
        })
        .toList();
    planningRequire(
      sales.length <= 1,
      OperationalPlanningFailureCode.ownershipConflict,
      'Cancellation Sales are ambiguous',
    );
    final legacyPrefix =
        sales.isNotEmpty &&
        prior?.locked == true &&
        prior?.status == AuditReportStatus.cancelled &&
        prior!.events.any((e) => e.type == AuditEventType.cancelTable);
    planningRequire(
      !legacyPrefix,
      OperationalPlanningFailureCode.recoveryRequired,
      'Legacy cancellation prefix requires fenced recovery',
    );
    planningRequire(
      prior?.locked != true,
      OperationalPlanningFailureCode.recoveryRequired,
      'Report is locked by another lifecycle',
    );
    final linked = _linked(view, order.orderId);
    planningRequire(
      linked.length <= 1,
      OperationalPlanningFailureCode.ownershipConflict,
      'Cancellation booking link is ambiguous',
    );
    final kind = order.floor == 'takeaway'
        ? 'TAKEAWAY'
        : order.packageId?.isNotEmpty == true
        ? 'PACKAGE'
        : linked.isNotEmpty
        ? 'RESERVATION'
        : 'WALK_IN';
    final note = [
      if (reason?.trim().isNotEmpty == true) reason!.trim(),
      if (approver?.isNotEmpty == true) 'Approved by $approver',
    ];
    final event = AuditEvent(
      type: AuditEventType.cancelTable,
      itemName: 'ORDER',
      previousQty: order.items.fold<int>(0, (n, i) => n + i.quantity),
      newQty: 0,
      waiterId: context.actorId,
      waiterName: context.actorName,
      timestamp: context.occurredAt,
      note: note.isEmpty ? null : note.join(' • '),
      details: {
        ..._details(view, order, kind, actorName: context.actorName),
        'orderUuid': order.orderUuid,
        'requestId': context.requestId,
        'grossAmount': order.grossAmount,
        if (linked.isNotEmpty)
          'reservationId': view.business(linked.single.key)['id'],
        if (reason?.trim().isNotEmpty == true) 'reason': reason!.trim(),
        if (approver?.isNotEmpty == true) ...{
          'approvedBy': approver,
          'approvedById': approver,
          'approvedByName': approver,
        },
      },
    );
    final base =
        prior ??
        AuditReport(
          reportId: reportIdentity.legacyKey as String,
          orderId: order.orderId,
          tableNumbers: order.tableNumbers,
          floor: order.floor,
          openedById: order.createdBy,
          openedByName: order.createdBy,
          openedAt: order.createdAt,
          status: AuditReportStatus.open,
          locked: false,
          updatedAt: order.createdAt,
          events: const [],
        );
    final report = base.copyWith(
      events: [
        ...base.events,
        event.copyWith(sequence: _sequence(base)),
      ],
      status: AuditReportStatus.cancelled,
      locked: true,
      closedAt: context.occurredAt,
      closedById: approver?.isNotEmpty == true ? approver : context.actorId,
      closedByName: approver?.isNotEmpty == true ? approver : context.actorName,
      updatedAt: context.occurredAt,
    );
    final saleIdentity = sales.isEmpty
        ? view.identities.legacy('sales', '${context.requestId}:cancelled-sale')
        : view.identities.identity(sales.single.key);
    final savedSale = sales.isEmpty ? null : view.business(saleIdentity.key);
    final sale =
        savedSale ??
        OrderTableMutationRepository.cancellationSaleImage(
          order,
          context.occurredAt,
          reason?.trim(),
          posSaleId: saleIdentity.legacyId ?? '',
          businessDate: view.businessDate,
          serviceFeeRate: view.serviceFeeRate,
        );
    final effects = <Map<String, dynamic>>[
      _effect(
        'auditReport',
        reportIdentity.legacyKey,
        reportBefore,
        report.toMap(),
      ),
      _effect('sales', saleIdentity.legacyKey, savedSale, sale),
    ];
    if (linked.isNotEmpty &&
        view.business(linked.single.key)['status'] != 'cancelled') {
      final row = linked.single,
          b = view.business(row.key),
          a = OrderTransferIntent.cloneMap(b)..['status'] = 'cancelled';
      effects.add(_effect('reservation', row.legacyKey, b, a));
      final audit = AuditEventLog(
        id: '${context.requestId}:reservation',
        action: ReservationAuditAction.cancel,
        userId: context.actorId,
        entityType: GlobalAuditEntity.reservation,
        entityId: b['id'],
        createdAt: context.occurredAt,
        deviceType: 'pos',
        data: {
          ...ReservationAudit.snapshot(_reservation(b)),
          'requestId': context.requestId,
          'orderId': order.orderId,
          'previousStatus': b['status'],
          'newStatus': 'cancelled',
          'status': 'cancelled',
          'actorId': context.actorId,
          'actorName': context.actorName,
          'source': context.source.wireValue,
          'businessDate': view.businessDate,
          'reason': reason?.trim() ?? 'Order cancelled',
        },
      );
      effects.add(_effect('auditEvent', audit.id, null, audit.toMap()));
    }
    if (order.floor != 'takeaway')
      for (final label in order.tableNumbers) {
        final row = view.identities.table('${order.floor}/$label'),
            b = view.business(row.key),
            table = TableModel.fromJson(Map.of(b));
        planningRequire(
          table.activeOrderId == order.orderId,
          OperationalPlanningFailureCode.ownershipConflict,
          'Cancellation table owner is ambiguous',
        );
        table.free();
        effects.add(
          _effect(
            'tables',
            row.legacyKey,
            b,
            OrderTableMutationRepository.tableImage(table),
          ),
        );
      }
    final after = OrderTransferIntent.orderImage(before)
      ..status = 'cancelled'
      ..updatedAt = context.occurredAt;
    effects.add(
      _effect(
        'orders',
        view.identities.identity(orderKey).legacyKey,
        before,
        OrderTableMutationRepository.image(after),
      ),
    );
    return _finish(
      view,
      'cancel',
      {
        'order': before,
        'actor': context.actorId,
        'actorName': context.actorName,
        'source': context.source.wireValue,
        'reason': reason?.trim(),
        'approvedBy': approver,
      },
      after,
      effects,
    );
  }

  static List<OrderItem> _lines(List<dynamic> items) {
    planningRequire(
      items.length <= 1024,
      OperationalPlanningFailureCode.capacity,
      'Frozen line capacity',
    );
    final ids = <String>{};
    for (final item in items)
      planningRequire(
        item is Map &&
            item['lineUuid'] is String &&
            proofUuid(item['lineUuid']) &&
            ids.add(item['lineUuid']) &&
            item['quantity'] is int &&
            item['quantity'] >= 0 &&
            item['unitPrice'] is num &&
            item['unitPrice'].isFinite &&
            item['total'] is num &&
            item['total'].isFinite,
        OperationalPlanningFailureCode.invalidPlan,
        'Each frozen line needs exact identity, quantity and value',
      );
    return [
      for (final item in items)
        OrderItem.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  static List<OperationalIdentity> _linked(
    OperationalPlanningView view,
    int number,
  ) => [
    for (final row in view.kind(ProofEntityKind.reservation))
      if (!row.tombstone &&
          view.business(row.key)['linkedOrderId'] == number &&
          ReservationClassification.kindOfFields(
            isTakeAway: view.business(row.key)['isTakeAway'] == true,
            notes: view.business(row.key)['notes'],
            customerName: view.business(row.key)['customerName'],
          ).belongsInCloudProjection)
        view.identities.identity(row.key),
  ];
  static Reservation _reservation(Map<String, dynamic> b) => Reservation(
    id: b['id'],
    customerName: b['customerName'],
    customerPhone: b['customerPhone'],
    tableNumbers: (b['tableNumbers'] as List).cast<int>(),
    tableRefs: (b['tableRefs'] as List?)?.cast<String>(),
    reservationDate: DateTime.parse(b['reservationDate']),
    reservationTime: b['reservationTime'],
    numberOfGuests: b['numberOfGuests'],
    notes: b['notes'],
    createdAt: DateTime.parse(b['createdAt']),
    createdBy: b['createdBy'],
    status: b['status'],
    isTakeAway: b['isTakeAway'],
    linkedOrderId: b['linkedOrderId'],
    preOrderItems: b['preOrderItems'] == null
        ? null
        : _lines(b['preOrderItems']),
  );
  static int _sequence(AuditReport report) => report.events.fold<int>(
    0,
    (n, e) => (e.sequence ?? -1) >= n ? e.sequence! + 1 : n,
  );
  static Map<String, dynamic> _details(
    OperationalPlanningView view,
    Order order,
    String kind, {
    String? actorName,
  }) => {
    'orderId': order.orderId,
    'orderKind': kind,
    'tableNumbers': List.of(order.tableNumbers),
    'tableRefs': OrderAuditDetails.tableRefs(order),
    'floor': order.floor,
    'source': view.context.source.wireValue,
    'actorId': view.context.actorId,
    'actorName': actorName ?? view.context.actorId,
    'businessDate': view.businessDate,
  };
  static Map<String, dynamic> _effect(
    String store,
    Object key,
    Object? before,
    Object? after,
  ) => {'store': store, 'key': key, 'before': before, 'after': after};
  static OperationalAdaptedPlan _finish(
    OperationalPlanningView view,
    String kind,
    Map<String, dynamic> request,
    Order order,
    List<Map<String, dynamic>> effects,
  ) {
    final frozenRequest = OrderTransferIntent.cloneMap(request)
      ..['proofPlanning'] = view.provenance();
    return OperationalIntentAdapter.adapt(
      view: view,
      journal: OrderTableMutationIntent({
        'version': 1,
        'requestId': view.context.requestId,
        'kind': kind,
        'businessDate': view.businessDate,
        'request': frozenRequest,
        'fingerprint': PosBackupFormat.digest(frozenRequest),
        'phase': 'intent',
        'nextEffect': 0,
        'effects': effects,
        'outcome': {
          'orderId': order.orderId,
          'orderUuid': order.orderUuid,
          'order': OrderTableMutationRepository.image(order),
        },
      }).toMap(),
    );
  }
}
