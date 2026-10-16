import 'dart:convert';

import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_ref.dart';

import 'domain.dart';
import 'manager_items_planner.dart';
import 'planning_view.dart';

class OperationalManagerItemsPlan {
  OperationalManagerItemsPlan({required this.intent, required this.draft});
  final ProofIntent intent;
  final OperationalManagerItemsDraft draft;
}

/// Manager business subset only. No startup, production boxes, command ingress,
/// print queues or transport are attached. A future authority boundary must
/// capture authenticated Manager origin/Staff; a caller's source tag is not that
/// admission proof. POS publication here is always refused.
abstract final class OperationalManagerItemsAdapter {
  static OperationalManagerItemsPlan adapt({
    required OperationalPlanningView view,
    required OperationalManagerItemsDraft draft,
  }) {
    try {
      planningRequire(
        view.context.source == AuditSource.manager,
        OperationalPlanningFailureCode.unsupported,
        'POS modification tickets are not covered by this Manager adapter',
      );
      view.authorize(managerItemsPermission);
      final body = proofMap(draft.body, {
        'version',
        'operation',
        'requestId',
        'provenance',
        'command',
        'beforeOrder',
        'afterOrder',
        'reportKey',
        'beforeReport',
        'afterReport',
        'events',
      });
      planningRequire(
        body['version'] == 1 &&
            body['operation'] == managerItemsOperation &&
            body['requestId'] == view.context.requestId &&
            OrderTransferIntent.sameImage(
              body['provenance'],
              view.provenance(),
            ),
        OperationalPlanningFailureCode.staleView,
        'Original request/binding/cursor/policy/Staff provenance changed',
      );
      final command = OperationalManagerItemsCommand.fromMap(body['command']);
      final expected = OperationalManagerItemsPlanner.draft(
        view: view,
        command: command,
      );
      planningRequire(
        OrderTransferIntent.sameImage(body, expected.body),
        OperationalPlanningFailureCode.invalidPlan,
        'Draft differs from regenerated complete business/report outcome',
      );
      final reads = OperationalPlanningReads(view);
      final orders = <Order>[], tables = <TableModel>[];
      for (final row in reads.scan(ProofEntityKind.order)) {
        final image = view.business(row.key);
        planningOrderImageInputs(image);
        final order = OrderTransferIntent.orderImage(image);
        final identity = view.identities.identity(row.key);
        planningRequire(
          order.orderUuid == row.key.id &&
              order.orderId == identity.orderNumber &&
              view.identities.order(order.orderId).key.value == row.key.value,
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Scanned Order differs from canonical identity',
        );
        orders.add(order);
      }
      for (final row in reads.scan(ProofEntityKind.table)) {
        final image = view.business(row.key);
        final table = TableModel.fromJson(Map.of(image));
        planningRequire(
          view.identities
                      .table('${table.floor}/${table.tableNumber}')
                      .key
                      .value ==
                  row.key.value &&
              OrderTransferIntent.sameImage(
                image,
                OrderTableMutationRepository.tableImage(table),
              ),
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Scanned Table differs from its stable lossless image',
        );
        tables.add(table);
        _validateLinks(view, row.key, _ModelLinks(view, reads).table(image));
      }
      final afterOrder = OrderTransferIntent.orderImage(body['afterOrder']);
      final virtual = [
        for (final order in orders)
          order.orderUuid == afterOrder.orderUuid ? afterOrder : order,
      ];
      planningRequire(
        OrderTableMutationRepository.integrityReport(
              orders: orders,
              tables: tables,
            ).isEmpty &&
            OrderTableMutationRepository.integrityReport(
              orders: virtual,
              tables: tables,
            ).isEmpty,
        OperationalPlanningFailureCode.ownershipConflict,
        'Original or proposed Order/Table ownership requires repair',
      );
      final reportKey = ProofKey.fromFrame(body['reportKey']);
      reads.read(command.orderKey);
      reads.read(reportKey);
      final orderLinks = _ModelLinks(
        view,
        reads,
      ).order(Map<String, dynamic>.from(body['beforeOrder']));
      final reportLinks = _ModelLinks(
        view,
        reads,
      ).report(reportKey, Map<String, dynamic>.from(body['beforeReport']));
      _validateLinks(view, command.orderKey, orderLinks);
      _validateLinks(view, reportKey, reportLinks);
      final afterReportLinks = _ModelLinks(
        view,
        reads,
      ).report(reportKey, Map<String, dynamic>.from(body['afterReport']));
      final controlLinks = <String, List<ProofKey>>{
        'currentDayId': [view.dayKey],
      };
      _validateLinks(view, view.controlKey, controlLinks);
      final effectId = view.identities.effect(
        '${view.context.requestId}:manager-items',
      );
      planningRequire(
        !view.retainedEffectIds.contains(effectId),
        OperationalPlanningFailureCode.staleView,
        'Immutable audit identity was already committed',
      );
      // This receipt retains the exact newly appended report events. Consumers
      // keep it as evidence, never append it again to the committed postimage.
      final payload = utf8.encode(
        jsonEncode({
          'version': 1,
          'operation': managerItemsOperation,
          'venueId': view.binding.venueId,
          'requestId': view.context.requestId,
          'source': AuditSource.manager.wireValue,
          'actorId': view.context.actorId,
          'occurredAt': view.context.occurredAt.toIso8601String(),
          'orderKey': command.orderKey.toFrame(),
          'reportKey': reportKey.toFrame(),
          'events': body['events'],
        }),
      );
      planningRequire(
        payload.length <= ProofBounds.effectBytes &&
            view.retainedEffectIds.length < ProofBounds.effects,
        OperationalPlanningFailureCode.capacity,
        'Complete immutable audit capacity exceeded',
      );
      final writes = [
        _write(
          view,
          command.orderKey,
          Map<String, dynamic>.from(body['afterOrder']),
          orderLinks,
        ),
        _write(
          view,
          reportKey,
          Map<String, dynamic>.from(body['afterReport']),
          afterReportLinks,
        ),
        // No allocation is changed, but every shared mutation CAS-writes the
        // original control revision to fence collection scans and absent rows.
        _write(
          view,
          view.controlKey,
          view.business(view.controlKey),
          controlLinks,
        ),
      ]..sort((a, b) => a.key.value.compareTo(b.key.value));
      final dependencies = reads.values.toList()
        ..sort((a, b) => a.key.value.compareTo(b.key.value));
      planningRequire(
        dependencies.length <= ProofBounds.reads,
        OperationalPlanningFailureCode.capacity,
        'Complete read dependencies exceed atomic count; cannot truncate',
      );
      final applicationData = utf8.encode(
        jsonEncode({
          'type': managerItemsOperation,
          'orderKey': command.orderKey.toFrame(),
          'orderNumber': afterOrder.orderId,
          'order': body['afterOrder'],
        }),
      );
      planningRequire(
        applicationData.length <= ProofBounds.applicationBytes,
        OperationalPlanningFailureCode.capacity,
        'Exact caller result bound',
      );
      final intent = ProofIntent(
        binding: view.binding,
        requestId: view.context.requestId,
        reads: dependencies,
        writes: writes,
        effects: [
          ProofEffect(
            id: effectId,
            kind: ProofEffectKind.audit,
            payload: payload,
          ),
        ],
        applicationData: applicationData,
      );
      return OperationalManagerItemsPlan(intent: intent, draft: expected);
    } on OperationalPlanningFailure {
      rethrow;
    } on FormatException catch (error) {
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.invalidPlan,
        error.message,
      );
    } on ArgumentError catch (error) {
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.invalidPlan,
        error.toString(),
      );
    } on TypeError catch (error) {
      throw OperationalPlanningFailure(
        OperationalPlanningFailureCode.invalidPlan,
        error.toString(),
      );
    }
  }

  static ProofWrite _write(
    OperationalPlanningView view,
    ProofKey key,
    Map<String, dynamic> business,
    Map<String, List<ProofKey>> references,
  ) {
    final revision = view.entity(key)!.revision;
    final document = OperationalPlanningView.encodeDocument(
      binding: view.binding,
      key: key,
      business: business,
      references: references,
    );
    planningRequire(
      revision < proofMaxInt64 && document.length <= ProofBounds.documentBytes,
      OperationalPlanningFailureCode.capacity,
      'Complete document/revision exceeds atomic bound',
    );
    return ProofWrite(
      key: key,
      expectedRevision: revision,
      tombstone: false,
      document: document,
    );
  }

  static void _validateLinks(
    OperationalPlanningView view,
    ProofKey key,
    Map<String, List<ProofKey>> expected,
  ) {
    final encoded = jsonDecode(utf8.decode(view.entity(key)!.document));
    final actual = Map<String, dynamic>.from(encoded['references']);
    final complete = {
      for (final entry in expected.entries)
        entry.key:
            (entry.value.toList()..sort((a, b) => a.value.compareTo(b.value)))
                .map((key) => key.toFrame())
                .toList(),
    };
    planningRequire(
      OrderTransferIntent.sameImage(actual, complete),
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Missing, extra or changed canonical foreign link in ${key.value}',
    );
  }
}

/// Typed Order/Table/report links only. It preserves and revalidates original
/// links; it does not walk an arbitrary JSON graph or infer an identity.
class _ModelLinks {
  _ModelLinks(this.view, this.reads);
  final OperationalPlanningView view;
  final OperationalPlanningReads reads;
  final _links = <String, Map<String, ProofKey>>{};
  static const _staff = {
    'createdBy',
    'openedById',
    'openedByUserId',
    'closedById',
    'waiterId',
    'actorId',
    'userId',
    'reservedBy',
    'approvedBy',
    'approvedById',
  };
  static const _orders = {
    'orderId',
    'linkedOrderId',
    'fromOrderId',
    'toOrderId',
    'activeOrderId',
    'transferredToOrderId',
  };
  static const _named = {
    'packageId': ProofEntityKind.package,
    'reservationId': ProofEntityKind.reservation,
    'posSaleId': ProofEntityKind.sale,
    'closureId': ProofEntityKind.closure,
    'advanceReceiptId': ProofEntityKind.advance,
  };
  Map<String, List<ProofKey>> get values => {
    for (final e in _links.entries) e.key: e.value.values.toList(),
  };
  void _add(String path, OperationalIdentity identity) {
    reads.read(identity.key);
    _links.putIfAbsent(path, () => {})[identity.key.value] = identity.key;
  }

  void _foreign(Map<String, dynamic> fields, String path) {
    for (final name in [..._staff, ..._orders, ..._named.keys]) {
      final value = fields[name];
      if (value == null || value == '') continue;
      if (_orders.contains(name)) {
        planningRequire(
          value is int,
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Invalid numeric Order reference',
        );
        _add('$path/$name', view.identities.order(value));
      } else if (_staff.contains(name)) {
        planningRequire(
          value is String,
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Invalid Staff link',
        );
        _add(
          '$path/$name',
          view.identities.named(ProofEntityKind.staff, value),
        );
      } else {
        planningRequire(
          value is String,
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Invalid named link',
        );
        _add('$path/$name', view.identities.named(_named[name]!, value));
      }
    }
  }

  void _tableNumbers(dynamic raw, String? floor, String path) {
    planningRequire(
      raw is List && floor != null,
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Missing physical floor',
    );
    if (floor == 'takeaway') return;
    for (final number in raw as List) {
      planningRequire(
        number is String,
        OperationalPlanningFailureCode.ambiguousIdentity,
        'Invalid Table label',
      );
      _add(path, view.identities.table('$floor/$number'));
    }
  }

  Map<String, List<ProofKey>> order(Map<String, dynamic> image) {
    _foreign(image, '');
    _tableNumbers(image['tableNumbers'], image['floor'], '/tableNumbers');
    if (image['floor'] == 'takeaway') {
      planningRequire(
        OrderTransferIntent.sameImage(image['tableNumbers'], [
          'TA-${image['orderId']}',
        ]),
        OperationalPlanningFailureCode.unsupported,
        'Legacy virtual takeaway labels require separate identity adoption',
      );
    }
    return values;
  }

  Map<String, List<ProofKey>> table(Map<String, dynamic> image) {
    _foreign(image, '');
    return values;
  }

  Map<String, List<ProofKey>> report(ProofKey key, Map<String, dynamic> image) {
    _foreign(image, '');
    _add('/reportId', view.identities.legacy('auditReport', image['reportId']));
    planningRequire(
      view.identities.legacy('auditReport', image['reportId']).key.value ==
          key.value,
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Report identity changed',
    );
    _tableNumbers(image['tableNumbers'], image['floor'], '/tableNumbers');
    final events = image['events'] as List;
    for (var i = 0; i < events.length; i++) {
      final event = Map<String, dynamic>.from(events[i]);
      _foreign(event, '/events/$i');
      final details = event['details'];
      if (details == null) continue;
      final fields = Map<String, dynamic>.from(details);
      const scalarMetadata = {
        'menuItemId',
        'variantId',
        'itemKey',
        'lineUuid',
        'orderUuid',
        'orderKind',
        'source',
        'actorName',
        'businessDate',
        'requestId',
        'includeServiceFee',
        'customerName',
        'customerPhone',
        'pickupTime',
        'floor',
        'fromFloor',
        'toFloor',
        'action',
        'reason',
        'approvedByName',
        'packageName',
        'guestCount',
        'packageGuestCount',
        'packageUnitPrice',
        'pricePerPerson',
        'packagePrice',
        'grossAmount',
        'direction',
      };
      final allowed = {
        ...scalarMetadata,
        ..._staff,
        ..._orders,
        ..._named.keys,
        'tableNumbers',
        'tableRefs',
        'fromTables',
        'toTables',
      };
      planningRequire(
        fields.keys.every(allowed.contains) &&
            fields.entries
                .where((e) => scalarMetadata.contains(e.key))
                .every((e) => e.value is! Map && e.value is! List),
        OperationalPlanningFailureCode.unsupported,
        'Report detail schema requires a separately reviewed link mapping',
      );
      final path = '/events/$i/details';
      _foreign(fields, path);
      if (fields['orderUuid'] != null) {
        final owner = fields['orderId'] ?? image['orderId'];
        planningRequire(
          owner is int &&
              fields['orderUuid'] == view.identities.order(owner).key.id,
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Report detail Order UUID contradicts its canonical identity',
        );
      }
      if (fields['lineUuid'] != null) {
        planningRequire(
          fields['lineUuid'] is String && proofUuid(fields['lineUuid']),
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Report detail line identity is not a frozen UUID',
        );
      }
      for (final name in ['tableNumbers', 'fromTables', 'toTables']) {
        if (!fields.containsKey(name)) continue;
        final floor = name == 'fromTables'
            ? fields['fromFloor']
            : name == 'toTables'
            ? fields['toFloor']
            : fields['floor'];
        _tableNumbers(fields[name], floor, '$path/$name');
      }
      if (fields['tableRefs'] != null) {
        for (final raw in fields['tableRefs'] as List) {
          final table = raw is String ? TableRef.tryDecode(raw) : null;
          planningRequire(
            table != null,
            OperationalPlanningFailureCode.ambiguousIdentity,
            'Invalid Table ref',
          );
          if (table!.floor == 'takeaway') {
            final owner = fields['orderId'] ?? image['orderId'];
            planningRequire(
              table.tableNumber == 'TA-$owner',
              OperationalPlanningFailureCode.ambiguousIdentity,
              'Virtual takeaway Order identity changed',
            );
            _add('$path/tableRefs/virtualOrder', view.identities.order(owner));
          } else {
            _add('$path/tableRefs', view.identities.table(table.encode()));
          }
        }
      }
    }
    return values;
  }
}
