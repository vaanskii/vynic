import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/services/audit/audit_order_diff_service.dart';

import 'domain.dart';
import 'planning_view.dart';

const managerItemsOperation = 'MANAGER_RETAINED_ITEM_REPLACEMENT';
const managerItemsPermission = 'editManagerItems';
const managerItemsMaxLines = 1000;

/// A retained line is addressed by both its compatibility key and original UUID.
/// Price, metadata, fee, status and ownership are deliberately not command fields.
class OperationalRetainedItemQuantity {
  OperationalRetainedItemQuantity({
    required this.itemKey,
    required this.lineUuid,
    required this.quantity,
  }) {
    planningRequire(
      itemKey.isNotEmpty &&
          itemKey.length <= 256 &&
          proofUuid(lineUuid) &&
          quantity > 0 &&
          quantity <= proofMaxInt64,
      OperationalPlanningFailureCode.invalidPlan,
      'Explicit retained line identity and positive quantity required',
    );
  }
  final String itemKey, lineUuid;
  final int quantity;
  Map<String, dynamic> toMap() => {
    'itemKey': itemKey,
    'lineUuid': lineUuid,
    'quantity': '$quantity',
  };
  factory OperationalRetainedItemQuantity.fromMap(dynamic raw) {
    final map = proofMap(raw, {'itemKey', 'lineUuid', 'quantity'});
    return OperationalRetainedItemQuantity(
      itemKey: map['itemKey'],
      lineUuid: map['lineUuid'],
      quantity: proofDecimal(map['quantity']),
    );
  }
}

class OperationalManagerItemsCommand {
  OperationalManagerItemsCommand({
    required this.orderKey,
    required this.menuRevision,
    required this.menuFingerprint,
    required List<OperationalRetainedItemQuantity> retainedItems,
  }) : retainedItems = List.unmodifiable(retainedItems) {
    planningRequire(
      orderKey.kind == ProofEntityKind.order &&
          menuRevision >= 0 &&
          menuRevision <= proofMaxInt64 &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(menuFingerprint),
      OperationalPlanningFailureCode.invalidPlan,
      'Typed Order and frozen menu provenance required',
    );
    planningRequire(
      this.retainedItems.length <= managerItemsMaxLines,
      OperationalPlanningFailureCode.capacity,
      'Retained item count exceeds atomic bound',
    );
    planningRequire(
      this.retainedItems.map((i) => i.itemKey).toSet().length ==
              this.retainedItems.length &&
          this.retainedItems.map((i) => i.lineUuid).toSet().length ==
              this.retainedItems.length,
      OperationalPlanningFailureCode.ambiguousIdentity,
      'Duplicate retained item key or UUID',
    );
  }
  final ProofKey orderKey;
  final int menuRevision;
  final String menuFingerprint;
  final List<OperationalRetainedItemQuantity> retainedItems;
  Map<String, dynamic> toMap() => {
    'operation': managerItemsOperation,
    'orderKey': orderKey.toFrame(),
    'menuRevision': '$menuRevision',
    'menuFingerprint': menuFingerprint,
    'retainedItems': retainedItems.map((i) => i.toMap()).toList(),
  };
  factory OperationalManagerItemsCommand.fromMap(dynamic raw) {
    final map = proofMap(raw, {
      'operation',
      'orderKey',
      'menuRevision',
      'menuFingerprint',
      'retainedItems',
    });
    planningRequire(
      map['operation'] == managerItemsOperation,
      OperationalPlanningFailureCode.unsupported,
      'Unsupported item operation',
    );
    return OperationalManagerItemsCommand(
      orderKey: ProofKey.fromFrame(map['orderKey']),
      menuRevision: proofDecimal(map['menuRevision']),
      menuFingerprint: map['menuFingerprint'],
      retainedItems: proofList(
        map['retainedItems'],
        OperationalRetainedItemQuantity.fromMap,
      ),
    );
  }
}

/// Pure reviewable business draft; it has no persistence or transport method.
class OperationalManagerItemsDraft {
  OperationalManagerItemsDraft.fromMap(Map<String, dynamic> map)
    : body = planningFreeze(map);
  final Map<String, dynamic> body;
  Map<String, dynamic> toMap() => OrderTransferIntent.cloneMap(body);
}

abstract final class OperationalManagerItemsPlanner {
  static OperationalManagerItemsDraft draft({
    required OperationalPlanningView view,
    required OperationalManagerItemsCommand command,
  }) {
    try {
      planningRequire(
        view.context.source == AuditSource.manager,
        OperationalPlanningFailureCode.unsupported,
        'POS item modifications require complete frozen PRINT effects',
      );
      view.authorize(managerItemsPermission);
      planningRequire(
        command.menuRevision == view.business(view.policyKey)['menuRevision'] &&
            command.menuFingerprint ==
                view.business(view.policyKey)['menuFingerprint'],
        OperationalPlanningFailureCode.staleView,
        'Frozen catalog provenance differs from policy',
      );
      final identity = view.identities.identity(command.orderKey);
      final before = view.business(command.orderKey);
      planningOrderImageInputs(before);
      final order = OrderTransferIntent.orderImage(before);
      planningRequire(
        identity.orderNumber == order.orderId &&
            order.orderUuid == command.orderKey.id &&
            view.identities.order(order.orderId).key.value ==
                command.orderKey.value,
        OperationalPlanningFailureCode.ambiguousIdentity,
        'Canonical Order identity differs from its business image',
      );
      planningRequire(
        {
              OrderStatus.pending,
              OrderStatus.confirmed,
            }.contains(order.statusEnum) &&
            order.closedAt == null &&
            order.closureId == null &&
            order.paymentMethod == null,
        OperationalPlanningFailureCode.unsupported,
        'Only ordinary unsettled pending/confirmed Orders are editable',
      );
      planningRequire(
        order.items.length <= managerItemsMaxLines,
        OperationalPlanningFailureCode.capacity,
        'Original line count bound',
      );
      final originals = {for (final line in order.items) line.itemKey: line};
      planningRequire(
        originals.length == order.items.length,
        OperationalPlanningFailureCode.ambiguousIdentity,
        'Legacy diff collapses duplicate itemKeys; this slice refuses them',
      );
      final replacement = <OrderItem>[];
      for (final requested in command.retainedItems) {
        final original = originals[requested.itemKey];
        planningRequire(
          original != null,
          OperationalPlanningFailureCode.unsupported,
          'New itemKeys require a validated frozen catalog quote',
        );
        planningRequire(
          original!.lineUuid == requested.lineUuid,
          OperationalPlanningFailureCode.ambiguousIdentity,
          'Retained line UUID changed',
        );
        // The existing model parser owns quantity*price. Supplying the frozen
        // UUID avoids its legacy implicit UUID factory; metadata comes only
        // from the captured preimage, never from a replacement price payload.
        final input = original.toJson()
          ..remove('total')
          ..['quantity'] = requested.quantity
          ..['price'] = original.unitPrice;
        final parsed = OrderItem.fromJson(input);
        planningRequire(
          parsed.total.isFinite,
          OperationalPlanningFailureCode.capacity,
          'Line arithmetic overflow',
        );
        replacement.add(parsed);
      }
      final events = AuditOrderDiffService.buildEvents(
        previousItems: order.items,
        updatedItems: replacement,
        performerId: view.context.actorId,
        performerName: view.context.actorId,
        timestamp: view.context.occurredAt,
      );
      planningRequire(
        events.isNotEmpty,
        OperationalPlanningFailureCode.unsupported,
        'No-op, metadata-only and reorder-only replacements are not admitted',
      );
      final reportIdentity = view.identities.legacy(
        'auditReport',
        AuditRepository.buildAuditReportKey(order.orderId),
      );
      final reportBefore = view.business(reportIdentity.key);
      final report = AuditReport.fromMap(reportBefore);
      planningRequire(
        OrderTransferIntent.sameImage(reportBefore, report.toMap()) &&
            report.reportId == reportIdentity.legacyKey &&
            report.orderId == order.orderId &&
            report.floor == order.floor &&
            OrderTransferIntent.sameImage(
              report.tableNumbers,
              order.tableNumbers,
            ),
        OperationalPlanningFailureCode.invalidPlan,
        'Audit report must be a lossless exact Order preimage',
      );
      planningRequire(
        !report.locked && report.status == AuditReportStatus.open,
        OperationalPlanningFailureCode.recoveryRequired,
        'Locked reports require their separate repair/lifecycle owner',
      );
      var next = 0;
      for (final event in report.events) {
        planningRequire(
          event.sequence != null &&
              event.sequence! >= next &&
              event.sequence! < proofMaxInt64,
          OperationalPlanningFailureCode.invalidPlan,
          'Report prefix has ambiguous or overflowing sequence',
        );
        next = event.sequence! + 1;
      }
      planningRequire(
        next <= proofMaxInt64 - events.length,
        OperationalPlanningFailureCode.capacity,
        'Audit sequence overflow',
      );
      final appended = [
        for (final event in events) event.copyWith(sequence: next++),
      ];
      final after = OrderTransferIntent.orderImage(before)
        ..items = replacement
        ..updatedAt = view.context.occurredAt;
      after.recalculateTotal(serviceFeeRate: view.serviceFeeRate);
      planningRequire(
        after.totalAmount.isFinite,
        OperationalPlanningFailureCode.capacity,
        'Order arithmetic overflow',
      );
      final afterImage = OrderTableMutationRepository.image(after);
      final stableBefore = OrderTransferIntent.cloneMap(before),
          stableAfter = OrderTransferIntent.cloneMap(afterImage);
      for (final field in ['items', 'updatedAt', 'totalAmount']) {
        stableBefore.remove(field);
        stableAfter.remove(field);
      }
      planningRequire(
        OrderTransferIntent.sameImage(stableBefore, stableAfter),
        OperationalPlanningFailureCode.unsupported,
        'Item replacement would alter financial/ownership/package state',
      );
      final reportAfter = report
          .copyWith(
            events: [...report.events, ...appended],
            updatedAt: view.context.occurredAt,
          )
          .toMap();
      return OperationalManagerItemsDraft.fromMap({
        'version': 1,
        'operation': managerItemsOperation,
        'requestId': view.context.requestId,
        'provenance': view.provenance(),
        'command': command.toMap(),
        'beforeOrder': before,
        'afterOrder': afterImage,
        'reportKey': reportIdentity.key.toFrame(),
        'beforeReport': reportBefore,
        'afterReport': reportAfter,
        'events': appended.map((e) => e.toMap()).toList(),
      });
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
}
