import 'dart:convert';

import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

import 'domain.dart';
import 'planning_view.dart';

class OperationalOrderOutcome {
  OperationalOrderOutcome({
    required this.kind,
    required Map<String, dynamic> order,
  }) : order = planningFreeze(order);
  final String kind;
  final Map<String, dynamic> order;
  int get orderNumber => order['orderId'];
  String get orderId => order['orderUuid'];
  Map<String, dynamic> toMap() => {
    'type': 'ORDINARY_ORDER_MUTATION',
    'kind': kind,
    'orderId': orderId,
    'orderNumber': orderNumber,
    'order': order,
  };
}

class OperationalAdaptedPlan {
  OperationalAdaptedPlan({
    required this.intent,
    required this.outcome,
    required Map<String, dynamic> journal,
  }) : journal = planningFreeze(journal);
  final ProofIntent intent;
  final OperationalOrderOutcome outcome;
  final Map<String, dynamic> journal;
}

/// An exhaustive, detached conversion. No client/store/transport is accepted by
/// this API, so unsupported mappings cannot prepare or publish partial writes.
abstract final class OperationalIntentAdapter {
  static OperationalAdaptedPlan adapt({
    required OperationalPlanningView view,
    required Map<String, dynamic> journal,
  }) {
    try {
      final raw = OrderTransferIntent.cloneMap(journal);
      final body = raw;
      planningRequire(
        body['effects'] is List,
        OperationalPlanningFailureCode.invalidPlan,
        'Missing journal effects',
      );
      for (final effect in body['effects'] as List) {
        planningRequire(
          effect is Map &&
              const {
                'orders',
                'tables',
                'settings',
                'auditReport',
                'auditEvent',
                'reservation',
                'sales',
              }.contains(effect['store']),
          OperationalPlanningFailureCode.unsupported,
          'Unmapped journal store',
        );
        if (effect['store'] == 'settings')
          planningRequire(
            effect['key'] == 'lastOrderId',
            OperationalPlanningFailureCode.unsupported,
            'Unmapped settings mutation',
          );
        if (effect['store'] == 'orders') {
          planningRequire(
            effect['after'] is Map,
            OperationalPlanningFailureCode.invalidPlan,
            'Missing Order image',
          );
          planningOrderImageInputs(Map<String, dynamic>.from(effect['after']));
          if (effect['before'] != null)
            planningOrderImageInputs(
              Map<String, dynamic>.from(effect['before']),
            );
        }
        if (effect['store'] == 'auditEvent') {
          final audit = effect['after'];
          planningRequire(
            audit is Map &&
                audit['id'] is String &&
                audit['createdAt'] is String &&
                DateTime.tryParse(audit['createdAt']) != null,
            OperationalPlanningFailureCode.invalidPlan,
            'Immutable audit lacks frozen identity/time',
          );
        }
        if (effect['store'] == 'sales') {
          final sale = effect['after'];
          planningRequire(
            sale is Map &&
                sale['recordType'] == 'sale' &&
                sale['isCancelled'] == true &&
                sale['isFiscal'] == false &&
                sale['finalTransaction'] is Map &&
                sale['finalTransaction']['type'] == 'cancelled_order',
            OperationalPlanningFailureCode.unsupported,
            'Only validated cancelled SALE is mapped',
          );
        }
      }
      final intent = OrderTableMutationIntent.decode(
        raw,
        serviceFeeRate: view.serviceFeeRate,
      );
      planningRequire(
        intent.id == view.context.requestId &&
            intent.next == 0 &&
            intent.body['phase'] == 'intent' &&
            intent.businessDate == view.businessDate &&
            intent.request['actor'] == view.context.actorId,
        OperationalPlanningFailureCode.staleView,
        'Frozen request/actor/Day or journal phase changed',
      );
      view.authorize(intent.kind);
      planningRequire(
        OrderTransferIntent.sameImage(
          intent.request['proofPlanning'],
          view.provenance(),
        ),
        OperationalPlanningFailureCode.staleView,
        'Original planning provenance changed or is missing',
      );
      final order = OrderTransferIntent.orderImage(intent.outcome['order']);
      planningRequire(
        (intent.kind == 'create' ? order.createdAt : order.updatedAt) ==
            view.context.occurredAt,
        OperationalPlanningFailureCode.staleView,
        'Lifecycle time differs from frozen operator time',
      );
      if (intent.kind == 'create') {
        planningRequire(
          intent.request['package'] == null &&
              intent.request['reservationId'] == null &&
              intent.request['forPackage'] != true &&
              order.status == 'pending',
          OperationalPlanningFailureCode.unsupported,
          'Package/activation creation is a separate planner',
        );
        final takeaway = order.floor == 'takeaway';
        final selected = takeaway
            ? false
            : intent.request['includeServiceFee'] ??
                  view.business(view.policyKey)['defaultIncludeServiceFee'];
        planningRequire(
          order.includeServiceFee == selected &&
              (!takeaway || !intent.request.containsKey('includeServiceFee')) &&
              order.discountAmount == 0 &&
              order.manualAdjustmentAmount == 0 &&
              order.advanceAmount == 0 &&
              order.advanceReceiptId == null &&
              order.advanceCollectedOn == null &&
              order.closureId == null &&
              order.closedAt == null &&
              order.paymentMethod == null &&
              order.customServiceFeePercentage == null &&
              order.openedByUserId ==
                  (takeaway ? null : view.context.actorId) &&
              intent.request['source'] == view.context.source.wireValue,
          OperationalPlanningFailureCode.invalidPlan,
          'Ordinary create contains unfrozen fee/financial state',
        );
        final recomputed = OrderTransferIntent.orderImage(
          intent.outcome['order'],
        )..recalculateTotal(serviceFeeRate: view.serviceFeeRate);
        planningRequire(
          OrderTransferIntent.sameImage(
            OrderTableMutationRepository.image(recomputed),
            intent.outcome['order'],
          ),
          OperationalPlanningFailureCode.staleView,
          'Created total differs from frozen policy/model calculation',
        );
      } else if (intent.kind == 'cancel') {
        planningRequire(
          intent.request['source'] == view.context.source.wireValue &&
              intent.request['actorName'] == view.context.actorName,
          OperationalPlanningFailureCode.staleView,
          'Cancellation actor/source changed',
        );
      } else {
        planningRequire(
          view.context.source.wireValue == 'POS',
          OperationalPlanningFailureCode.unsupported,
          'Existing movement audit is POS-only',
        );
      }
      planningRequire(
        order.orderUuid == view.identities.order(order.orderId).key.id,
        OperationalPlanningFailureCode.ambiguousIdentity,
        'Order number and UUID disagree',
      );
      final reads = OperationalPlanningReads(view);
      if (intent.kind == 'cancel') {
        final approver = (intent.request['approvedBy'] as String?)?.trim();
        planningRequire(
          view.business(view.policyKey)['cancelRequiresApproval'] != true ||
              approver?.isNotEmpty == true,
          OperationalPlanningFailureCode.unsupported,
          'Cancellation policy requires an approver',
        );
        if (approver?.isNotEmpty == true) {
          final staff = reads.business(
            view.identities.named(ProofEntityKind.staff, approver!).key,
          );
          planningRequire(
            staff['username'] == approver &&
                staff['enabled'] == true &&
                staff['permissions'] is List &&
                (staff['permissions'] as List).contains('approveCancel'),
            OperationalPlanningFailureCode.unsupported,
            'Approver lacks frozen authority',
          );
        }
      }
      final writableIdentities = {
        for (final e in intent.effects)
          if (e['store'] != 'settings' && e['store'] != 'auditEvent')
            view.identities.legacy(e['store'], e['key']).key.value,
      };
      final orders = <dynamic, Order>{};
      for (final row in reads.scan(ProofEntityKind.order)) {
        final identity = view.identities.identity(row.key);
        final image = reads.business(row.key);
        _orderIdentity(view, identity, image);
        orders[identity.legacyKey] = OrderTransferIntent.orderImage(image);
      }
      final tables = <dynamic, TableModel>{};
      for (final row in reads.scan(ProofEntityKind.table)) {
        final identity = view.identities.identity(row.key);
        final image = reads.business(row.key);
        planningRequire(
          identity.tableRef == '${image['floor']}/${image['tableNumber']}',
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Table label and stable mapping disagree',
        );
        tables[identity.legacyKey] = TableModel.fromJson(Map.of(image));
      }
      // These overloads receive BOTH detached collections, never their live defaults.
      final issues = OrderTableMutationRepository.integrityReport(
        orders: orders.values,
        tables: tables.values,
      );
      planningRequire(
        issues.isEmpty,
        OperationalPlanningFailureCode.ownershipConflict,
        'Detached Order/Table projection needs repair',
      );
      OrderTableMutationRepository.validateFinalOwnership(
        intent,
        orders: orders,
        tables: tables,
      );
      // Full scans are intentional. Control CAS fences absent/phantom bookings
      // and cancellation Sales, and retains the original operator revisions.
      final bookings = reads.scan(ProofEntityKind.reservation);
      if (intent.kind == 'cancel') {
        final cancelled = reads.scan(ProofEntityKind.sale).where((row) {
          final sale = view.business(row.key), tx = sale['finalTransaction'];
          return sale['orderId'] == order.orderId &&
              sale['isCancelled'] == true &&
              (tx is Map && tx['type'] == 'cancelled_order' ||
                  sale['paymentMethod'] == 'cancelled');
        }).toList();
        final planned = intent.effects.singleWhere(
          (e) => e['store'] == 'sales',
        );
        planningRequire(
          cancelled.length <= 1,
          OperationalPlanningFailureCode.ownershipConflict,
          'Cancellation Sales are ambiguous',
        );
        if (cancelled.isNotEmpty)
          planningRequire(
            view.identities.legacy('sales', planned['key']).key.value ==
                    cancelled.single.key.value &&
                OrderTransferIntent.sameImage(
                  planned['before'],
                  view.business(cancelled.single.key),
                ) &&
                OrderTransferIntent.sameImage(
                  planned['after'],
                  view.business(cancelled.single.key),
                ),
            OperationalPlanningFailureCode.staleView,
            'Existing cancellation Sale must retain its identity/history',
          );
        final report = intent.effects.singleWhere(
          (e) => e['store'] == 'auditReport',
        )['before'];
        planningRequire(
          !(cancelled.isNotEmpty && report is Map && report['locked'] == true),
          OperationalPlanningFailureCode.recoveryRequired,
          'Legacy cancellation prefix requires fenced recovery',
        );
      }
      if (intent.kind != 'create') {
        final allLinked = bookings.where((row) {
          final b = view.business(row.key);
          return b['linkedOrderId'] == order.orderId &&
              ReservationClassification.kindOfFields(
                isTakeAway: b['isTakeAway'] == true,
                notes: b['notes'],
                customerName: b['customerName'],
              ).belongsInCloudProjection;
        }).toList();
        planningRequire(
          allLinked.length <= 1,
          OperationalPlanningFailureCode.ownershipConflict,
          'Linked booking identity is ambiguous regardless of status',
        );
        final linked = allLinked
            .where(
              (row) =>
                  intent.kind != 'cancel' ||
                  view.business(row.key)['status'] != 'cancelled',
            )
            .map((row) => row.key.value)
            .toSet();
        final planned = intent.effects
            .where((e) => e['store'] == 'reservation')
            .map(
              (e) => view.identities.legacy('reservation', e['key']).key.value,
            )
            .toSet();
        planningRequire(
          linked.length == planned.length && linked.containsAll(planned),
          OperationalPlanningFailureCode.ownershipConflict,
          'Linked booking effect omitted or ambiguous',
        );
      }
      final writes = <ProofWrite>[];
      final effects = <ProofEffect>[];
      final control = OrderTransferIntent.cloneMap(
        view.business(view.controlKey),
      );
      var allocatorSeen = false;
      for (final effect in intent.effects) {
        final store = effect['store'] as String;
        if (store == 'settings') {
          planningRequire(
            !allocatorSeen &&
                intent.kind == 'create' &&
                effect['before'] == view.lastOrderId &&
                effect['after'] == view.lastOrderId + 1 &&
                order.orderId == view.lastOrderId + 1,
            OperationalPlanningFailureCode.staleView,
            'Allocator differs from frozen control',
          );
          allocatorSeen = true;
          control['lastOrderId'] = effect['after'];
          continue;
        }
        if (store == 'auditEvent') {
          planningRequire(
            effect['before'] == null,
            OperationalPlanningFailureCode.invalidPlan,
            'Immutable audit cannot replace prior history',
          );
          final id = view.identities.effect(effect['key'] as String);
          planningRequire(
            !view.retainedEffectIds.contains(id),
            OperationalPlanningFailureCode.staleView,
            'Immutable audit identity already retained',
          );
          final business = OrderTransferIntent.cloneMap(effect['after'] as Map);
          planningRequire(
            business['createdAt'] == view.context.occurredAt.toIso8601String(),
            OperationalPlanningFailureCode.staleView,
            'Immutable audit time was not frozen',
          );
          final refs = _References(view, reads, writableIdentities)
            ..visit(business);
          effects.add(
            ProofEffect(
              id: id,
              kind: ProofEffectKind.audit,
              payload: utf8.encode(
                jsonEncode({
                  'version': 1,
                  'venueId': view.binding.venueId,
                  'requestId': intent.id,
                  'identity': id,
                  'business': business,
                  'references': refs.toMap(),
                }),
              ),
            ),
          );
          continue;
        }
        final identity = view.identities.legacy(store, effect['key'] as Object);
        final expected = view.entity(identity.key);
        final before = expected == null ? null : reads.business(identity.key);
        reads.read(identity.key, allowAbsent: true);
        planningRequire(
          OrderTransferIntent.sameImage(before, effect['before']) &&
              expected?.tombstone != true &&
              effect['after'] is Map,
          OperationalPlanningFailureCode.staleView,
          'Effect preimage differs from frozen view',
        );
        final after = OrderTransferIntent.cloneMap(effect['after'] as Map);
        if (store == 'orders') _orderIdentity(view, identity, after);
        if (store == 'tables') {
          final prior = TableModel.fromJson(
            Map<String, dynamic>.from(effect['before']),
          );
          final next = TableModel.fromJson(after);
          planningRequire(
            identity.tableRef == '${next.floor}/${next.tableNumber}' &&
                OrderTransferIntent.sameImage(
                  OrderTableMutationRepository.tableImage(prior),
                  effect['before'],
                ),
            OperationalPlanningFailureCode.ambiguousIdentity,
            'Table business image and identity disagree',
          );
          if (intent.kind == 'create')
            planningRequire(
              !prior.isReserved && prior.activeOrderId == null,
              OperationalPlanningFailureCode.ownershipConflict,
              'New physical table is busy',
            );
          if (intent.kind == 'move')
            planningRequire(
              next.activeOrderId == order.orderId
                  ? (prior.activeOrderId == null ||
                            prior.activeOrderId == order.orderId) &&
                        (!prior.isReserved ||
                            prior.activeOrderId == order.orderId)
                  : prior.activeOrderId == order.orderId,
              OperationalPlanningFailureCode.ownershipConflict,
              'Movement source/destination ownership changed',
            );
        }
        if (store == 'auditReport')
          planningRequire(
            after['reportId'] == identity.legacyKey &&
                identity.legacyKey ==
                    AuditRepository.buildAuditReportKey(order.orderId),
            OperationalPlanningFailureCode.ambiguousIdentity,
            'Report identity changed',
          );
        if (store == 'auditReport')
          planningRequire(
            OrderTransferIntent.sameImage(
              AuditReport.fromMap(after).toMap(),
              after,
            ),
            OperationalPlanningFailureCode.invalidPlan,
            'Unmapped mutable audit report fields',
          );
        if (store == 'reservation')
          planningRequire(
            after['id'] == identity.legacyId,
            OperationalPlanningFailureCode.ambiguousIdentity,
            'Reservation stable mapping changed',
          );
        if (store == 'sales')
          planningRequire(
            after['posSaleId'] == identity.legacyId,
            OperationalPlanningFailureCode.ambiguousIdentity,
            'Cancelled Sale stable mapping changed',
          );
        final refs = _References(view, reads, writableIdentities)..visit(after);
        writes.add(
          ProofWrite(
            key: identity.key,
            expectedRevision: expected?.revision ?? 0,
            tombstone: false,
            document: OperationalPlanningView.encodeDocument(
              binding: view.binding,
              key: identity.key,
              business: after,
              references: refs.values,
            ),
          ),
        );
      }
      planningRequire(
        allocatorSeen == (intent.kind == 'create'),
        OperationalPlanningFailureCode.invalidPlan,
        'Missing or unexpected allocator mutation',
      );
      // Every operation, including move/cancel, increments the control revision.
      writes.add(
        ProofWrite(
          key: view.controlKey,
          expectedRevision: view.entity(view.controlKey)!.revision,
          tombstone: false,
          document: OperationalPlanningView.encodeDocument(
            binding: view.binding,
            key: view.controlKey,
            business: control,
            references: {
              'currentDayId': [view.dayKey],
            },
          ),
        ),
      );
      planningRequire(
        writes.length <= ProofBounds.writes &&
            reads.values.length <= ProofBounds.reads &&
            effects.length <= ProofBounds.requestEffects &&
            view.retainedEffectIds.length + effects.length <=
                ProofBounds.effects,
        OperationalPlanningFailureCode.capacity,
        'Complete operation exceeds atomic proof capacity',
      );
      final outcome = OperationalOrderOutcome(
        kind: intent.kind,
        order: intent.outcome['order'],
      );
      final proof = ProofIntent(
        binding: view.binding,
        requestId: intent.id,
        reads: reads.values,
        writes: writes,
        effects: effects,
        applicationData: utf8.encode(jsonEncode(outcome.toMap())),
      );
      return OperationalAdaptedPlan(
        intent: proof,
        outcome: outcome,
        journal: intent.toMap(),
      );
    } on OperationalPlanningFailure {
      rethrow;
    } on OrderMutationConflict catch (error) {
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.ownershipConflict,
        error.message.toString(),
      );
    } on FormatException catch (error) {
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.invalidPlan,
        error.message,
      );
    } on ArgumentError catch (error) {
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.invalidPlan,
        error.message.toString(),
      );
    } on TypeError catch (error) {
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.invalidPlan,
        error.toString(),
      );
    }
  }

  static void _orderIdentity(
    OperationalPlanningView view,
    OperationalIdentity identity,
    Map<String, dynamic> image,
  ) {
    planningRequire(
      identity.key.kind == ProofEntityKind.order &&
          image['orderUuid'] == identity.key.id &&
          image['orderId'] == identity.orderNumber &&
          view.identities.order(image['orderId']).key.value ==
              identity.key.value,
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Order stable identity changed',
    );
    final lineIds = <String>{};
    for (final line in [
      ...image['items'] as List,
      ...image['packageItems'] as List,
    ]) {
      planningRequire(
        line is Map &&
            line['lineUuid'] is String &&
            proofUuid(line['lineUuid']) &&
            lineIds.add(line['lineUuid']),
        OperationalPlanningFailureCode.ambiguousIdentity,
        'Unfrozen line identity',
      );
    }
  }
}

class _References {
  _References(this.view, this.reads, this.writableIdentities);
  final OperationalPlanningView view;
  final OperationalPlanningReads reads;
  final Set<String> writableIdentities;
  final Map<String, Map<String, ProofKey>> _refs = {};
  Map<String, List<ProofKey>> get values => {
    for (final e in _refs.entries) e.key: e.value.values.toList(),
  };
  Map<String, dynamic> toMap() => {
    for (final e in values.entries)
      e.key: e.value.map((k) => k.toFrame()).toList(),
  };
  void _add(String path, OperationalIdentity identity) {
    // A new Order/report/Sale is explicitly absent in this same frozen view.
    reads.read(
      identity.key,
      allowAbsent: writableIdentities.contains(identity.key.value),
    );
    _refs.putIfAbsent(path, () => {})[identity.key.value] = identity.key;
  }

  void visit(dynamic raw, [String path = '']) {
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) visit(raw[i], '$path/$i');
      return;
    }
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    final auditData = map['data'];
    if (auditData is String) visit(jsonDecode(auditData), '$path/data');
    for (final e in map.entries) {
      final name = e.key, value = e.value, at = '$path/$name';
      if (value == null || value == '') continue;
      if (const {
        'orderId',
        'linkedOrderId',
        'fromOrderId',
        'toOrderId',
        'transferredToOrderId',
        'activeOrderId',
      }.contains(name)) {
        planningRequire(
          value is int,
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Non-numeric legacy Order reference',
        );
        _add(at, view.identities.order(value));
      } else if (const {
        'createdBy',
        'openedById',
        'openedByUserId',
        'closedById',
        'userId',
        'waiterId',
        'actorId',
        'approvedBy',
        'approvedById',
        'reservedBy',
      }.contains(name)) {
        planningRequire(
          value is String,
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Staff reference',
        );
        _add(at, view.identities.named(ProofEntityKind.staff, value));
      } else if (const {
        'reservationId',
        'packageId',
        'posSaleId',
        'closureId',
        'advanceReceiptId',
      }.contains(name)) {
        final kind = switch (name) {
          'reservationId' => ProofEntityKind.reservation,
          'packageId' => ProofEntityKind.package,
          'posSaleId' => ProofEntityKind.sale,
          'closureId' => ProofEntityKind.closure,
          _ => ProofEntityKind.advance,
        };
        _add(at, view.identities.named(kind, value as String));
      } else if (name == 'reportId') {
        _add(at, view.identities.legacy('auditReport', value as Object));
      } else if (name == 'entityId') {
        final kind = map['entityType'];
        if (kind == GlobalAuditEntity.order) {
          final number = int.tryParse(value as String);
          planningRequire(
            number != null,
            OperationalPlanningFailureCode.ambiguousIdentity,
            'Audit Order identity',
          );
          _add(at, view.identities.order(number!));
        } else if (kind == GlobalAuditEntity.reservation) {
          _add(
            at,
            view.identities.named(ProofEntityKind.reservation, value as String),
          );
        } else
          throw OperationalPlanningFailure(
            OperationalPlanningFailureCode.unsupported,
            'Unmapped immutable audit subject',
          );
      } else if (name == 'tableRefs' && value is List) {
        for (final ref in value) {
          final table = TableRef.tryDecode(ref as String);
          planningRequire(
            table != null,
            OperationalPlanningFailureCode.ambiguousIdentity,
            'Invalid table reference',
          );
          if (table!.floor == 'takeaway') {
            final number = int.tryParse(
              table.tableNumber.replaceFirst(RegExp(r'^TA-'), ''),
            );
            planningRequire(
              number != null && table.tableNumber == 'TA-$number',
              OperationalPlanningFailureCode.ambiguousIdentity,
              'Invalid virtual takeaway owner',
            );
            _add('$at/virtualOrder', view.identities.order(number!));
          } else {
            _add(at, view.identities.table(ref));
          }
        }
      } else if (const {
            'tableNumbers',
            'fromTables',
            'toTables',
          }.contains(name) &&
          value is List) {
        final floor = name == 'fromTables'
            ? map['fromFloor']
            : name == 'toTables'
            ? map['toFloor']
            : map['floor'];
        if (floor != null && floor != 'takeaway') {
          for (final ref in value)
            _add(at, view.identities.table('$floor/$ref'));
        } else if (name == 'tableNumbers' &&
            map.containsKey('reservationDate') &&
            (map['tableRefs'] as List?)?.isNotEmpty != true) {
          for (final code in value) {
            planningRequire(
              code is int,
              OperationalPlanningFailureCode.ambiguousIdentity,
              'Legacy booking table code',
            );
            _add(
              at,
              view.identities.table(
                ReservationTableAvailability.refFromLegacyCode(code).encode(),
              ),
            );
          }
        }
      }
      if (name != 'data' || value is! String) visit(value, at);
    }
  }
}
