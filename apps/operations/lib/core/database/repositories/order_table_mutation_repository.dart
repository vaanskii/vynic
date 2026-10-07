import 'order_edit_repository.dart';
import 'table_repair_repository.dart';
import 'package:vynic/core/services/edge/orders_tables/shadow.dart';
import 'package:vynic/core/services/edge/orders_tables/pos_shadow_projection.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';
import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/order_audit_details.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import '../database_core.dart';
import '../local_data_admission.dart';
import 'audit_repository.dart';
import 'backup_repository.dart';
import 'business_day_repository.dart';
import 'order_transfer_journal_repository.dart';
import '../pos_backup_format.dart';

class OrderMutationConflict extends StateError {
  OrderMutationConflict(this.code, String message, {this.issues = const []})
    : super(message);
  final String code;
  final List<Map<String, dynamic>> issues;
  String get userMessage => switch (code) {
    'table_busy' => 'მაგიდა უკვე დაკავებულია — განაახლეთ შეკვეთა',
    'stale_order' ||
    'stale_date' => 'შეკვეთა შეიცვალა — განაახლეთ და გაიმეორეთ მოქმედება',
    'repair_required' =>
      'მაგიდის კავშირი არათანმიმდევრულია — საჭიროა შემოწმება',
    'request_conflict' => 'მოთხოვნის იდენტიფიკატორი სხვა მოქმედებას ეკუთვნის',
    'recovery_required' => 'ოპერაცია აღსადგენია — გადატვირთეთ POS',
    _ => 'მოქმედება უარყოფილია — განაახლეთ შეკვეთა',
  };
}

/// Primitive, additive meta protocol. Existing fiscal/transfer/day journals own
/// their transitions. This journal owns create, physical table movement and cancellation.
class OrderTableMutationIntent {
  OrderTableMutationIntent(this.body);
  final Map<String, dynamic> body;
  String get id => body['requestId'] as String;
  String get kind => body['kind'] as String;
  String get businessDate => body['businessDate'] as String;
  String get fingerprint => body['fingerprint'] as String;
  Map<String, dynamic> get request => body['request'] as Map<String, dynamic>;
  Map<String, dynamic> get outcome => body['outcome'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get effects =>
      (body['effects'] as List).cast<Map<String, dynamic>>();
  int get next => body['nextEffect'] as int;
  bool get pending => body['phase'] != 'completed';
  Map<String, dynamic> toMap() => {
    ...body,
    'digest': PosBackupFormat.digest(body),
  };
  static OrderTableMutationIntent decode(Object? value) {
    if (value is! Map) throw const FormatException('Missing ownership journal');
    final raw = OrderTransferIntent.cloneMap(value);
    final digest = raw.remove('digest');
    if (digest is! String ||
        digest != PosBackupFormat.digest(raw) ||
        raw['version'] != 1 ||
        raw['requestId'] is! String ||
        (raw['requestId'] as String).isEmpty ||
        (raw['requestId'] as String).length > 256 ||
        !['create', 'move', 'cancel'].contains(raw['kind']) ||
        raw['request'] is! Map ||
        raw['fingerprint'] != PosBackupFormat.digest(raw['request']) ||
        raw['businessDate'] is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw['businessDate']) ||
        raw['effects'] is! List ||
        raw['outcome'] is! Map ||
        raw['nextEffect'] is! int) {
      throw const FormatException(
        'Invalid ownership journal identity/version/digest',
      );
    }
    final intent = OrderTableMutationIntent(raw);
    if (intent.effects.isEmpty ||
        intent.next < 0 ||
        intent.next > intent.effects.length ||
        raw['phase'] !=
            (intent.next == intent.effects.length
                ? 'completed'
                : intent.next == 0
                ? 'intent'
                : 'effect${intent.next}')) {
      throw const FormatException('Invalid ownership journal phase');
    }
    final seen = <String>{};
    for (final e in intent.effects) {
      if (![
            'orders',
            'tables',
            'settings',
            'auditReport',
            'auditEvent',
            'reservation',
            'sales',
          ].contains(e['store']) ||
          e['key'] is! String && e['key'] is! int ||
          !seen.add(jsonEncode([e['store'], e['key']])) ||
          !e.containsKey('before') ||
          !e.containsKey('after'))
        throw const FormatException('Invalid ownership effect');
      if (e['store'] == 'orders') OrderTransferIntent.orderImage(e['after']);
      if (e['store'] == 'auditEvent') {
        final event = AuditEventLog.fromMap(e['after'] as Map<String, dynamic>);
        if (event.id != e['key'] || event.data['requestId'] != intent.id) {
          throw const FormatException('Ownership audit identity mismatch');
        }
      }
    }
    final rows = intent.effects.where((e) => e['store'] == 'orders').toList();
    if (rows.length != 1)
      throw const FormatException('Invalid ownership Order effects');
    final row = rows.single;
    final after = OrderTransferIntent.orderImage(row['after']);
    if ((intent.kind == 'cancel'
            ? after.status != 'cancelled'
            : after.statusEnum.isTerminal) ||
        after.orderId != intent.outcome['orderId'] ||
        after.orderUuid != intent.outcome['orderUuid'] ||
        !OrderTransferIntent.sameImage(intent.outcome['order'], row['after'])) {
      throw const FormatException('Ownership outcome/Order mismatch');
    }
    if (intent.kind == 'create' && row['before'] != null ||
        intent.kind != 'create' &&
            (row['before'] is! Map ||
                !OrderTransferIntent.sameImage(
                  row['before'],
                  intent.request['order'],
                ))) {
      throw const FormatException('Ownership request/before mismatch');
    }
    if (intent.kind == 'move') {
      final before = OrderTransferIntent.orderImage(row['before']);
      final expected = OrderTransferIntent.snapshot(before)
        ..['floor'] = after.floor
        ..['tableNumbers'] = after.tableNumbers
        ..['updatedAt'] = after.updatedAt?.toIso8601String();
      if (!OrderTransferIntent.sameImage(expected, row['after'])) {
        throw const FormatException(
          'Table move changed unrelated Order fields',
        );
      }
    }
    final target = {
      if (!after.statusEnum.isTerminal && after.floor != 'takeaway')
        for (final t in after.tableNumbers) '${after.floor}|$t',
    };
    final occupied = <String>{};
    for (final e in intent.effects.where((e) => e['store'] == 'tables')) {
      final t = TableModel.fromJson(e['after'] as Map<String, dynamic>);
      final prior = TableModel.fromJson(e['before'] as Map<String, dynamic>);
      if (!OrderTransferIntent.sameImage(
            e['after'],
            OrderTableMutationRepository.tableImage(t),
          ) ||
          t.tableNumber != prior.tableNumber ||
          t.floor != prior.floor ||
          t.edgeRevision != prior.edgeRevision ||
          prior.activeOrderId != null && prior.activeOrderId != after.orderId) {
        throw const FormatException('Ownership table identity/owner mismatch');
      }
      if (t.activeOrderId == after.orderId && t.isReserved) {
        occupied.add('${t.floor}|${t.tableNumber}');
      } else if (t.activeOrderId != null ||
          t.isReserved ||
          t.reservationId != null ||
          !['move', 'cancel'].contains(intent.kind)) {
        throw const FormatException('Invalid ownership table target');
      }
    }
    if (!setEquals(target, occupied))
      throw const FormatException('Ownership target tables disagree');
    final reports = intent.effects
        .where((e) => e['store'] == 'auditReport')
        .toList();
    if (reports.length != 1)
      throw const FormatException('Missing ownership audit');
    final report = AuditReport.fromMap(reports.single['after'] as Map);
    if (report.orderId != after.orderId ||
        (intent.kind == 'cancel'
            ? !report.locked || report.status != AuditReportStatus.cancelled
            : report.locked || report.status != AuditReportStatus.open) ||
        reports.single['key'] !=
            AuditRepository.buildAuditReportKey(after.orderId) ||
        intent.kind == 'create' &&
            (report.events.isEmpty ||
                ![
                  AuditEventType.createWalkIn,
                  AuditEventType.createTakeaway,
                  AuditEventType.activateReservation,
                ].contains(report.events.first.type)) ||
        intent.kind == 'move' &&
            report.events
                    .where(
                      (e) =>
                          e.details?['requestId'] == intent.id &&
                          e.details?['action'] == 'TABLE_CHANGED',
                    )
                    .length !=
                1) {
      throw const FormatException('Invalid ownership creation/move audit');
    }
    OrderTableMutationRepository.validatePlan(intent);
    return intent;
  }
}

abstract final class OrderTableMutationRepository {
  static const prefix = 'orderTableMutationV1:';
  static String key(String id) => '$prefix${sha256.convert(utf8.encode(id))}';
  static String get dateKey =>
      BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate());
  static Map<String, dynamic> image(Order o) => OrderTransferIntent.snapshot(o);
  static Map<String, dynamic> tableImage(TableModel t) {
    final value = OrderTransferIntent.cloneMap(t.toJson())
      ..remove('currentBill');
    if (t.reservedAt != null)
      value['reservedAt'] = DateTime.fromMillisecondsSinceEpoch(
        t.reservedAt!.millisecondsSinceEpoch,
        isUtc: t.reservedAt!.isUtc,
      ).toIso8601String();
    return value;
  }

  static Map<String, dynamic> reservationImage(Reservation r) {
    final value = OrderTransferIntent.cloneMap(
      BackupRepository.serializeReservationForSync(r),
    );
    for (final key in ['reservationDate', 'createdAt']) {
      final d = DateTime.parse(value[key] as String);
      value[key] = DateTime.fromMillisecondsSinceEpoch(
        d.millisecondsSinceEpoch,
        isUtc: d.isUtc,
      ).toIso8601String();
    }
    return value;
  }

  static void validatePlan(OrderTableMutationIntent intent) {
    if (intent.kind == 'cancel') {
      validateCancellation(intent);
      return;
    }
    if (intent.effects.any((e) => e['store'] == 'sales'))
      throw const FormatException('Creation/move cannot write Sales');
    final order = OrderTransferIntent.orderImage(intent.outcome['order']);
    final request = intent.request;
    final actor = request['actor'];
    if (actor is! String ||
        actor.isEmpty ||
        intent.kind == 'create' && order.createdBy != actor) {
      throw const FormatException('Ownership actor differs from request');
    }
    final settings = intent.effects
        .where((e) => e['store'] == 'settings')
        .toList();
    if (settings.length != (intent.kind == 'create' ? 1 : 0))
      throw const FormatException('Invalid ownership settings effect count');
    for (final e in settings) {
      if (e['key'] != 'lastOrderId' ||
          e['after'] is! int ||
          e['before'] != null && e['before'] is! int ||
          e['after'] !=
              ((e['before'] as int? ?? 0) > order.orderId
                  ? e['before']
                  : order.orderId)) {
        throw const FormatException(
          'Ownership sequence counter is not monotonic lastOrderId',
        );
      }
    }
    final targetRefs = [
      for (final t in order.tableNumbers)
        TableRef(floor: order.floor, tableNumber: t),
    ];
    final reportEffect = intent.effects.singleWhere(
      (e) => e['store'] == 'auditReport',
    );
    final report = AuditReport.fromMap(reportEffect['after'] as Map);
    if (intent.kind == 'create') {
      if (reportEffect['before'] != null ||
          request['items'] is! List ||
          !OrderTransferIntent.sameImage(
            request['items'],
            order.items.map(itemRequest).toList(),
          ) ||
          request['posOrderId'] != null &&
              request['posOrderId'] != order.orderId ||
          (request['floor'] ??
                  (request['kind'] == 'takeaway' ? 'takeaway' : null)) !=
              order.floor ||
          !(request['kind'] == 'takeaway' &&
                  listEquals(order.tableNumbers, ['TA-${order.orderId}'])) &&
              !OrderTransferIntent.sameImage(
                (request['tables'] as List).toSet().toList(),
                order.tableNumbers,
              ) ||
          BusinessDayRepository.dateKey(order.createdAt) !=
              intent.businessDate) {
        throw const FormatException(
          'Created Order differs from immutable ownership request',
        );
      }
      final activation = request['reservationId'];
      final type = activation != null
          ? AuditEventType.activateReservation
          : order.floor == 'takeaway'
          ? AuditEventType.createTakeaway
          : AuditEventType.createWalkIn;
      final extra = request['package'] == null ? 0 : 1;
      if (report.events.length != order.items.length + 1 + extra ||
          report.events.first.type != type ||
          report.openedAt != order.createdAt ||
          report.openedById != actor ||
          report.floor != order.floor ||
          !listEquals(report.tableNumbers, order.tableNumbers)) {
        throw const FormatException(
          'Ownership creation report has wrong origin/events',
        );
      }
      for (var i = 0; i < report.events.length; i++) {
        final e = report.events[i];
        if (e.sequence != i ||
            e.waiterId != actor ||
            e.waiterName != actor ||
            i <= order.items.length && e.timestamp != order.createdAt) {
          throw const FormatException(
            'Ownership creation audit sequence/actor/time mismatch',
          );
        }
        if (i > 0 && i <= order.items.length) {
          final item = order.items[i - 1];
          if (e.type != AuditEventType.addItem ||
              e.itemName != item.itemName ||
              e.previousQty != 0 ||
              e.newQty != item.quantity ||
              e.details?['menuItemId'] != item.menuItemId ||
              e.details?['variantId'] != item.variantId) {
            throw const FormatException(
              'Ownership initial line audit differs from frozen item',
            );
          }
        }
      }
      final first = report.events.first;
      if (first.details?['source'] != request['source'] ||
          first.details?['actorId'] != actor ||
          first.details?['businessDate'] != intent.businessDate ||
          first.details?['reservationId'] != activation) {
        throw const FormatException(
          'Ownership creation audit provenance mismatch',
        );
      }
      if (request['package'] case final Map package) {
        if (order.packageId != package['id'] ||
            order.packageName != package['name'] ||
            order.packageUnitPrice != package['pricePerPerson'] ||
            order.packageGuestCount != request['guestCount'] ||
            !OrderTransferIntent.sameImage(package['items'], [
              for (final i in order.packageItems)
                {
                  'itemKey': i.itemKey,
                  'itemName': i.itemName,
                  'quantity': i.quantity,
                  'unitPrice': i.unitPrice,
                  'menuItemId': i.menuItemId,
                  'variantId': i.variantId,
                },
            ]) ||
            report.events.last.type != AuditEventType.applyPackage ||
            report.events.last.details?['packageId'] != order.packageId ||
            report.events.last.details?['packageGuestCount'] !=
                order.packageGuestCount) {
          throw const FormatException(
            'Ownership package/audit image differs from request',
          );
        }
      } else if (order.packageId != null ||
          order.packageItems.isNotEmpty ||
          order.packagePrice != 0) {
        throw const FormatException('Unexpected ownership package data');
      }
    } else {
      final prior = AuditReport.fromMap(reportEffect['before'] as Map);
      final beforeOrder = OrderTransferIntent.orderImage(request['order']);
      if (prior.locked ||
          prior.orderId != order.orderId ||
          report.events.length != prior.events.length + 1 ||
          !OrderTransferIntent.sameImage(
            prior.events.map((e) => e.toMap()).toList(),
            report.events
                .take(prior.events.length)
                .map((e) => e.toMap())
                .toList(),
          ) ||
          !listEquals(
            (request['tableNumbers'] as List).toSet().toList(),
            order.tableNumbers,
          ) ||
          request['floor'] != order.floor)
        throw const FormatException(
          'Move changed retained audit/request prefix',
        );
      if (!OrderTransferIntent.sameImage(
        prior
            .copyWith(
              events: report.events,
              updatedAt: order.updatedAt,
              tableNumbers: order.tableNumbers,
              floor: order.floor,
            )
            .toMap(),
        report.toMap(),
      ))
        throw const FormatException('Move changed unrelated report metadata');
      final event = report.events.last;
      final nextSequence = prior.events.fold<int>(
        0,
        (n, e) => (e.sequence ?? -1) >= n ? e.sequence! + 1 : n,
      );
      if (event.type != AuditEventType.custom ||
          event.sequence != nextSequence ||
          event.waiterId != actor ||
          event.waiterName != actor ||
          event.timestamp != order.updatedAt ||
          event.details?['requestId'] != intent.id ||
          event.details?['action'] != 'TABLE_CHANGED' ||
          !OrderTransferIntent.sameImage(
            event.details?['fromTables'],
            beforeOrder.tableNumbers,
          ) ||
          event.details?['fromFloor'] != beforeOrder.floor ||
          !OrderTransferIntent.sameImage(
            event.details?['toTables'],
            order.tableNumbers,
          ) ||
          event.details?['toFloor'] != order.floor)
        throw const FormatException('Move audit differs from exact request');
    }
    final reservationEffects = intent.effects
        .where((e) => e['store'] == 'reservation')
        .toList();
    if (intent.kind == 'create' &&
        reservationEffects.length !=
            (request['reservationId'] == null ? 0 : 1)) {
      throw const FormatException(
        'Ownership activation Reservation count mismatch',
      );
    }
    for (final e in reservationEffects) {
      final before = OrderTransferIntent.cloneMap(e['before'] as Map);
      final after = OrderTransferIntent.cloneMap(e['after'] as Map);
      final expected = OrderTransferIntent.cloneMap(before);
      if (!ReservationClassification.kindOfFields(
            isTakeAway: before['isTakeAway'] == true,
            notes: before['notes'] as String?,
            customerName: before['customerName'] as String? ?? '',
          ).belongsInCloudProjection ||
          before['linkedOrderId'] != null &&
              before['linkedOrderId'] != order.orderId ||
          before['id'] is! String)
        throw const FormatException(
          'Ownership Reservation identity/link mismatch',
        );
      if (intent.kind == 'create') {
        if (before['id'] != request['reservationId'] ||
            before['linkedOrderId'] != null ||
            !['pending', 'preparing', 'confirmed'].contains(before['status'])) {
          throw const FormatException(
            'Ownership activation Reservation is not eligible',
          );
        }
        expected['linkedOrderId'] = order.orderId;
        expected['status'] = 'in-progress';
      } else {
        if (before['linkedOrderId'] != order.orderId)
          throw const FormatException('Move Reservation is not linked');
        expected['tableRefs'] = targetRefs.map((r) => r.encode()).toList();
        expected['tableNumbers'] = ReservationTableAvailability.legacyCodesOf(
          targetRefs,
        );
      }
      if (!OrderTransferIntent.sameImage(expected, after))
        throw const FormatException(
          'Ownership Reservation changed unrelated fields',
        );
    }
    final global = intent.effects
        .where((e) => e['store'] == 'auditEvent')
        .toList();
    if (global.length !=
        (intent.kind == 'create' ? 1 + reservationEffects.length : 0)) {
      throw const FormatException(
        'Ownership immutable audit effect count mismatch',
      );
    }
    for (final e in global) {
      if (e['before'] != null)
        throw const FormatException('Ownership audit identity already existed');
      final event = AuditEventLog.fromMap(e['after'] as Map<String, dynamic>);
      final booking = event.id == '${intent.id}:reservation';
      if (event.userId != actor ||
          (!booking && event.createdAt != order.createdAt) ||
          event.deviceType != 'pos' ||
          event.entityId !=
              (booking ? request['reservationId'] : '${order.orderId}') ||
          event.entityType !=
              (booking
                  ? GlobalAuditEntity.reservation
                  : GlobalAuditEntity.order) ||
          event.action !=
              (booking
                  ? ReservationAuditAction.update
                  : order.floor == 'takeaway'
                  ? 'TAKEAWAY_ORDER_CREATED'
                  : 'ORDER_CREATED') ||
          event.id != '${intent.id}:${booking ? 'reservation' : 'created'}' ||
          event.data['orderId'] != order.orderId ||
          booking &&
              (event.data['businessDate'] != intent.businessDate ||
                  event.data['previousStatus'] !=
                      reservationEffects.single['before']['status'] ||
                  event.data['newStatus'] !=
                      reservationEffects.single['after']['status'] ||
                  event.data['source'] != request['source'] ||
                  event.data['linkedOrderId'] != order.orderId ||
                  event.data['status'] !=
                      reservationEffects.single['after']['status']))
        throw const FormatException(
          'Ownership immutable audit differs from plan',
        );
    }
  }

  static void validateCancellation(OrderTableMutationIntent intent) {
    final rows = intent.effects;
    final orderEffect = rows.singleWhere((e) => e['store'] == 'orders');
    final before = OrderTransferIntent.orderImage(orderEffect['before']);
    final after = OrderTransferIntent.orderImage(orderEffect['after']);
    final request = intent.request;
    final actor = request['actor'];
    if (actor is! String ||
        actor.isEmpty ||
        before.statusEnum.isTerminal ||
        rows.last != orderEffect ||
        rows.any(
          (e) => ![
            'orders',
            'tables',
            'sales',
            'auditReport',
            'reservation',
            'auditEvent',
          ].contains(e['store']),
        ))
      throw const FormatException('Invalid cancellation ownership plan');
    final expectedOrder = image(before)
      ..['status'] = 'cancelled'
      ..['updatedAt'] = after.updatedAt?.toIso8601String();
    if (!OrderTransferIntent.sameImage(expectedOrder, image(after)))
      throw const FormatException(
        'Cancellation changed unrelated Order fields',
      );
    final tables = rows.where((e) => e['store'] == 'tables').toList();
    if (!setEquals(
      tables.map((e) {
        final t = TableModel.fromJson(e['before']);
        return '${t.floor}|${t.tableNumber}';
      }).toSet(),
      before.floor == 'takeaway'
          ? <String>{}
          : {for (final n in before.tableNumbers) '${before.floor}|$n'},
    ))
      throw const FormatException('Cancellation table effects incomplete');
    for (final e in tables) {
      final t = TableModel.fromJson(e['before']);
      final expected = tableImage(t..free());
      if (!OrderTransferIntent.sameImage(expected, e['after']))
        throw const FormatException('Cancellation table release differs');
    }
    final sales = rows.where((e) => e['store'] == 'sales').toList();
    if (sales.length != 1)
      throw const FormatException('Cancellation sale count differs');
    final sale = sales.single['after'] as Map;
    final saved = sales.single['before'];
    if (saved != null && !OrderTransferIntent.sameImage(saved, sale) ||
        sale['orderId'] != before.orderId ||
        sale['isCancelled'] != true ||
        sale['isFiscal'] != false ||
        sale['collectedNow'] != 0 ||
        sale['paymentMethod'] != 'cancelled' ||
        sale['finalTransaction']['type'] != 'cancelled_order' ||
        sale['totalAmount'] != before.totalAmount ||
        sale['grossSaleAmount'] != before.grossAmount ||
        sale['advanceApplied'] != before.effectiveAdvanceAmount ||
        !listEquals((sale['tableNumbers'] as List), before.tableNumbers) ||
        sale['floor'] != before.floor ||
        sale['createdAt'] != before.createdAt.toIso8601String() ||
        !OrderTransferIntent.sameImage(sale['items'], [
          for (final i in [...before.packageItems, ...before.items])
            {
              'itemName': i.itemName,
              'quantity': i.quantity,
              'unitPrice': i.unitPrice,
              'total': i.total,
              if (i.comment != null) 'comment': i.comment,
              if (i.menuItemId != null) 'menuItemId': i.menuItemId,
              if (i.variantId != null) 'variantId': i.variantId,
            },
        ]))
      throw const FormatException(
        'Cancellation Sale differs from frozen value/identity',
      );
    if (sale['paymentBreakdown'] != null ||
        sale['customPaymentLabel'] != null ||
        sale['advanceAmount'] != 0 ||
        sale['restoredToOrder'] != false ||
        sale['recordType'] != 'sale' ||
        sale['total'] != before.totalAmount ||
        sale['includeServiceFee'] != before.includeServiceFee ||
        sale['discountAmount'] != before.discountAmount ||
        sale['manualAdjustmentAmount'] != before.manualAdjustmentAmount ||
        sale['createdBy'] != before.createdBy ||
        sale['posSaleId'] is! String ||
        (sale['posSaleId'] as String).isEmpty ||
        sale['ledgerRevision'] is! int ||
        (sale['ledgerRevision'] as int) < 1 ||
        sale['finalTransaction']['orderId'] != before.orderId ||
        sale['finalTransaction']['isFiscal'] != false) {
      throw const FormatException(
        'Cancellation Sale tender/bookkeeping mismatch',
      );
    }
    if (saved == null) {
      final expectedSale = cancellationSaleImage(
        before,
        after.updatedAt!,
        request['reason'] as String?,
        posSaleId: sale['posSaleId'] as String,
        businessDate: intent.businessDate,
      );
      if (sales.single['key'] != '${intent.id}:cancelled-sale' ||
          !OrderTransferIntent.sameImage(expectedSale, sale))
        throw const FormatException(
          'Cancellation Sale metadata differs from plan',
        );
    }
    final reportEffect = rows.singleWhere((e) => e['store'] == 'auditReport');
    final report = AuditReport.fromMap(reportEffect['after']);
    final prior = reportEffect['before'] == null
        ? null
        : AuditReport.fromMap(reportEffect['before']);
    final prefixEvents = prior?.events ?? const <AuditEvent>[];
    final already =
        prior?.locked == true &&
        prior?.status == AuditReportStatus.cancelled &&
        prior!.events.any((e) => e.type == AuditEventType.cancelTable);
    if (prior?.locked == true && !already ||
        report.events.length != prefixEvents.length + (already ? 0 : 1) ||
        !OrderTransferIntent.sameImage(
          prefixEvents.map((e) => e.toMap()).toList(),
          report.events
              .take(prefixEvents.length)
              .map((e) => e.toMap())
              .toList(),
        ))
      throw const FormatException('Cancellation audit prefix/lock differs');
    if (report.events
            .where((e) => e.type == AuditEventType.cancelTable)
            .length !=
        1)
      throw const FormatException('Cancellation audit is ambiguous');
    if (already) {
      if (!OrderTransferIntent.sameImage(
        reportEffect['before'],
        reportEffect['after'],
      ))
        throw const FormatException(
          'Retried legacy cancellation report changed',
        );
    } else {
      final base =
          prior ??
          AuditReport(
            reportId: AuditRepository.buildAuditReportKey(before.orderId),
            orderId: before.orderId,
            tableNumbers: before.tableNumbers,
            floor: before.floor,
            openedById: before.createdBy,
            openedByName: before.createdBy,
            openedAt: before.createdAt,
            status: AuditReportStatus.open,
            locked: false,
            updatedAt: before.createdAt,
            events: const [],
          );
      final approver = (request['approvedBy'] as String?)?.trim();
      final name = request['actorName'] as String;
      final expected = base.copyWith(
        events: report.events,
        status: AuditReportStatus.cancelled,
        locked: true,
        closedAt: after.updatedAt,
        closedById: approver?.isNotEmpty == true ? approver : actor,
        closedByName: approver?.isNotEmpty == true ? approver : name,
        updatedAt: after.updatedAt,
      );
      if (!OrderTransferIntent.sameImage(expected.toMap(), report.toMap()))
        throw const FormatException('Cancellation report metadata changed');
    }
    final event = report.events.lastWhere(
      (e) => e.type == AuditEventType.cancelTable,
    );
    if (!already &&
        (event.waiterId != actor ||
            event.details?['requestId'] != intent.id ||
            event.details?['orderUuid'] != before.orderUuid ||
            event.timestamp != after.updatedAt ||
            event.details?['source'] != request['source'] ||
            event.details?['businessDate'] != intent.businessDate ||
            event.waiterName != request['actorName'] ||
            event.previousQty !=
                before.items.fold<int>(0, (n, i) => n + i.quantity) ||
            event.newQty != 0 ||
            event.details?['orderId'] != before.orderId ||
            event.details?['actorId'] != actor ||
            event.details?['actorName'] != request['actorName'] ||
            event.details?['grossAmount'] != before.grossAmount ||
            event.details?['floor'] != before.floor ||
            !listEquals(
              (event.details?['tableNumbers'] as List?) ?? [],
              before.tableNumbers,
            ) ||
            !listEquals((event.details?['tableRefs'] as List?) ?? [], [
              for (final t in before.tableNumbers) '${before.floor}/$t',
            ])))
      throw const FormatException(
        'Cancellation audit actor/identity/time differs',
      );
    final bookings = rows.where((e) => e['store'] == 'reservation').toList();
    final events = rows.where((e) => e['store'] == 'auditEvent').toList();
    if (bookings.length > 1 || events.length != bookings.length)
      throw const FormatException(
        'Cancellation Reservation audit count differs',
      );
    for (final e in bookings) {
      final b = OrderTransferIntent.cloneMap(e['before']);
      final a = OrderTransferIntent.cloneMap(e['after']);
      if (!ReservationClassification.kindOfFields(
            isTakeAway: b['isTakeAway'] == true,
            notes: b['notes'],
            customerName: b['customerName'],
          ).belongsInCloudProjection ||
          b['linkedOrderId'] != before.orderId ||
          b['status'] == 'cancelled' ||
          !OrderTransferIntent.sameImage(
            a,
            OrderTransferIntent.cloneMap(b)..['status'] = 'cancelled',
          ))
        throw const FormatException(
          'Cancellation Reservation link/status differs',
        );
      final audit = AuditEventLog.fromMap(events.single['after']);
      if (events.single['before'] != null ||
          audit.id != '${intent.id}:reservation' ||
          audit.action != ReservationAuditAction.cancel ||
          audit.entityType != GlobalAuditEntity.reservation ||
          audit.entityId != b['id'] ||
          audit.userId != actor ||
          audit.data['orderId'] != before.orderId ||
          audit.data['previousStatus'] != b['status'] ||
          audit.data['newStatus'] != 'cancelled' ||
          audit.data['businessDate'] != intent.businessDate ||
          audit.data['source'] != request['source'] ||
          audit.deviceType != 'pos' ||
          audit.data['actorId'] != actor ||
          audit.data['actorName'] != request['actorName'] ||
          audit.data['status'] != 'cancelled' ||
          audit.data['linkedOrderId'] != before.orderId ||
          audit.data['reservationId'] != b['id'] ||
          audit.data['customerName'] != b['customerName'] ||
          audit.data['customerPhone'] != b['customerPhone'] ||
          !OrderTransferIntent.sameImage(
            audit.data['tableRefs'],
            (b['tableRefs'] as List?)?.isNotEmpty == true
                ? b['tableRefs']
                : [
                    for (final code in b['tableNumbers'] as List)
                      ReservationTableAvailability.refFromLegacyCode(
                        code as int,
                      ).encode(),
                  ],
          ))
        throw const FormatException('Cancellation Reservation audit differs');
    }
  }

  static void validateFinalOwnership(
    OrderTableMutationIntent intent, {
    Map<dynamic, Order>? orders,
    Map<dynamic, TableModel>? tables,
  }) {
    final virtualOrders = Map<dynamic, Order>.from(
      orders ?? DatabaseCore.orderBox!.toMap(),
    );
    final virtualTables = Map<dynamic, TableModel>.from(
      tables ?? DatabaseCore.tableBox!.toMap(),
    );
    final refs = <String>{};
    for (final e in intent.effects) {
      if (e['store'] == 'orders')
        virtualOrders[e['key']] = OrderTransferIntent.orderImage(e['after']);
      if (e['store'] == 'tables') {
        final t = TableModel.fromJson(e['after'] as Map<String, dynamic>);
        virtualTables[e['key']] = t;
        refs.add('${t.floor}|${t.tableNumber}');
      }
    }
    final id = intent.outcome['orderId'];
    final issues =
        integrityReport(
              orders: virtualOrders.values,
              tables: virtualTables.values,
            )
            .where(
              (e) =>
                  refs.contains(e['tableRef']) ||
                  e['orderId'] == id ||
                  (e['orderIds'] as List?)?.contains(id) == true ||
                  e['activeOrderId'] == id,
            )
            .toList();
    if (issues.isNotEmpty)
      throw OrderMutationConflict(
        'repair_required',
        'Pending ownership final image is ambiguous',
        issues: issues,
      );
  }

  static Map<String, dynamic> cancellationSaleImage(
    Order order,
    DateTime timestamp,
    String? reason, {
    required String posSaleId,
    required String businessDate,
  }) {
    final subtotal = double.parse(
      (order.getPackageSubtotal() + order.getAdditionalItemsSubtotal())
          .toStringAsFixed(2),
    );
    return {
      'posSaleId': posSaleId,
      'ledgerRevision': 1,
      'ledgerUpdatedAt': timestamp.toIso8601String(),
      'orderId': order.orderId,
      'tableNumbers': List<String>.of(order.tableNumbers),
      'floor': order.floor,
      'items': [
        for (final i in [...order.packageItems, ...order.items])
          {
            'itemName': i.itemName,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            'total': i.total,
            if (i.comment != null) 'comment': i.comment,
            if (i.menuItemId != null) 'menuItemId': i.menuItemId,
            if (i.variantId != null) 'variantId': i.variantId,
          },
      ],
      'totalAmount': order.totalAmount,
      'total': order.totalAmount,
      'paymentMethod': 'cancelled',
      'paymentBreakdown': null,
      'customPaymentLabel': null,
      'createdBy': order.createdBy,
      'createdAt': order.createdAt.toIso8601String(),
      'closedAt': timestamp.toIso8601String(),
      'includeServiceFee': order.includeServiceFee,
      'discountAmount': order.discountAmount,
      'advanceAmount': 0.0,
      'subtotalAmount': subtotal,
      'manualAdjustmentAmount': order.manualAdjustmentAmount,
      'finalTransaction': {
        'type': 'cancelled_order',
        'orderId': order.orderId,
        'subtotal': subtotal,
        'serviceFee': double.parse(order.getServiceFee().toStringAsFixed(2)),
        'total': order.totalAmount,
        'comment': reason ?? '',
        'isFiscal': false,
      },
      'date': businessDate,
      'isCancelled': true,
      'cancelledAt': timestamp.toIso8601String(),
      'isFiscal': false,
      'restoredToOrder': false,
      'recordType': 'sale',
      'grossSaleAmount': order.grossAmount,
      'advanceApplied': order.effectiveAdvanceAmount,
      'collectedNow': 0.0,
    };
  }

  static DateTime now() {
    final date = BusinessDayRepository.getCurrentDateTime();
    return DateTime.fromMillisecondsSinceEpoch(
      date.millisecondsSinceEpoch,
      isUtc: date.isUtc,
    );
  }

  static List<Map<String, dynamic>> integrityReport({
    Iterable<Order>? orders,
    Iterable<TableModel>? tables,
  }) {
    final byId = <int, List<Order>>{};
    final owners = <String, List<Order>>{};
    final tableRows = <String, List<TableModel>>{};
    for (final o
        in orders ?? DatabaseCore.orderBox?.values ?? const <Order>[]) {
      byId.putIfAbsent(o.orderId, () => []).add(o);
      if (!o.statusEnum.isTerminal && o.floor != 'takeaway') {
        for (final t in o.tableNumbers.toSet())
          owners.putIfAbsent('${o.floor}|$t', () => []).add(o);
      }
    }
    for (final t
        in tables ?? DatabaseCore.tableBox?.values ?? const <TableModel>[]) {
      tableRows.putIfAbsent('${t.floor}|${t.tableNumber}', () => []).add(t);
    }
    final issues = <Map<String, dynamic>>[];
    for (final entry in byId.entries.where((e) => e.value.length > 1)) {
      issues.add({
        'code': 'duplicate_order_id',
        'orderId': entry.key,
        'orderUuids': entry.value.map((o) => o.orderUuid).toList(),
      });
    }
    for (final ref in {...owners.keys, ...tableRows.keys}) {
      final orders = owners[ref] ?? [];
      final rows = tableRows[ref] ?? [];
      if (rows.length > 1 || orders.length > 1) {
        issues.add({
          'code': 'ambiguous_table_ownership',
          'tableRef': ref,
          'orderIds': orders.map((o) => o.orderId).toList(),
          'tableRows': rows.length,
        });
      } else if (orders.isNotEmpty &&
          (rows.isEmpty ||
              !rows.single.isReserved ||
              rows.single.activeOrderId != orders.single.orderId)) {
        issues.add({
          'code': 'active_order_table_mismatch',
          'tableRef': ref,
          'orderIds': [orders.single.orderId],
          'activeOrderId': rows.isEmpty ? null : rows.single.activeOrderId,
        });
      } else if (orders.isEmpty &&
          rows.isNotEmpty &&
          rows.single.activeOrderId != null) {
        issues.add({
          'code': 'orphan_table_owner',
          'tableRef': ref,
          'activeOrderId': rows.single.activeOrderId,
        });
      }
    }
    return issues;
  }

  static void requireConsistent({Set<String>? refs, int? orderId}) {
    final issues = integrityReport()
        .where(
          (e) =>
              refs == null && orderId == null ||
              refs?.contains(e['tableRef']) == true ||
              e['orderId'] == orderId ||
              (e['orderIds'] as List?)?.contains(orderId) == true ||
              e['activeOrderId'] == orderId,
        )
        .toList();
    if (issues.isNotEmpty)
      throw OrderMutationConflict(
        'repair_required',
        'Existing Order/table relationships require explicit repair',
        issues: issues,
      );
  }

  static void assertRollbackSafe() {
    if (records().any((e) => e.pending))
      throw OrderMutationConflict(
        'recovery_required',
        'Recover ownership intent before rollback',
      );
    requireConsistent();
  }

  static TableModel detachedTable(TableModel row) =>
      TableModel.fromJson(tableImage(row))..mutationBaseline = tableImage(row);

  static Future<void> saveTable(TableModel draft) {
    final proposed = tableImage(draft);
    final expected = OrderTransferIntent.cloneMap(
      draft.mutationBaseline ?? proposed,
    );
    return UpdateReadiness.mutate('updateTable', () async {
      final entries = DatabaseCore.tableBox!
          .toMap()
          .entries
          .where(
            (e) =>
                e.value.floor == draft.floor &&
                e.value.tableNumber == draft.tableNumber,
          )
          .toList();
      if (entries.length != 1)
        throw OrderMutationConflict(
          'repair_required',
          'Physical table missing/ambiguous',
        );
      final row = entries.single;
      if (!OrderTransferIntent.sameImage(expected, tableImage(row.value)))
        throw OrderMutationConflict(
          'stale_order',
          'Table changed before update',
        );
      final after = TableModel.fromJson(proposed);
      final virtual = Map<dynamic, TableModel>.of(
        DatabaseCore.tableBox!.toMap(),
      )..[row.key] = after;
      final issues = integrityReport(tables: virtual.values)
          .where((e) => e['tableRef'] == '${after.floor}|${after.tableNumber}')
          .toList();
      if (issues.isNotEmpty)
        throw OrderMutationConflict(
          'repair_required',
          'Table update violates ownership',
          issues: issues,
        );
      await DatabaseCore.tableBox!.put(row.key, after);
      await DatabaseCore.tableBox!.flush();
      draft.mutationBaseline = tableImage(after);
    });
  }

  static Order capture(Order row) => OrderTransferIntent.orderImage(image(row))
    ..mutationBaseline = OrderTransferIntent.cloneMap(
      row.mutationBaseline ?? image(row),
    )
    ..mutationKey = row.mutationKey;

  static Order detached(Order row, Object key) {
    final order = BackupRepository.deserializeOrderSnapshot(image(row));
    return order
      ..mutationBaseline = image(row)
      ..mutationKey = key;
  }

  static (Object, Order)? persisted(int id, {String? uuid}) {
    final rows =
        DatabaseCore.orderBox
            ?.toMap()
            .entries
            .where((e) => e.value.orderId == id)
            .toList() ??
        [];
    if (rows.length > 1)
      throw OrderMutationConflict(
        'repair_required',
        'Order ID is ambiguous',
        issues: [
          {'code': 'duplicate_order_id', 'orderId': id},
        ],
      );
    if (rows.isEmpty) return null;
    if (uuid != null && rows.single.value.orderUuid != uuid)
      throw OrderMutationConflict(
        'stale_order',
        'Stored Order identity changed',
      );
    return (rows.single.key as Object, rows.single.value);
  }

  static Order requireFresh(Order o, {bool allowTerminal = false}) {
    final row = persisted(o.orderId, uuid: o.orderUuid);
    if (row == null ||
        !OrderTransferIntent.sameImage(
          image(row.$2),
          o.mutationBaseline ?? image(o),
        ) ||
        !allowTerminal && row.$2.statusEnum.isTerminal)
      throw OrderMutationConflict(
        'stale_order',
        'Order changed since it was read',
      );
    requireConsistent(orderId: o.orderId);
    return row.$2;
  }

  static Future<void> saveOrder(Order draft) {
    final requested = image(draft);
    final expected = OrderTransferIntent.cloneMap(
      draft.mutationBaseline ?? requested,
    );
    return UpdateReadiness.mutate('updateOrder', () async {
      final row = persisted(draft.orderId, uuid: draft.orderUuid);
      if (row == null ||
          !OrderTransferIntent.sameImage(image(row.$2), expected)) {
        throw OrderMutationConflict(
          'stale_order',
          'Order changed before its write',
        );
      }
      requireConsistent(orderId: draft.orderId);
      final after = OrderTransferIntent.orderImage(requested);
      if (after.floor != row.$2.floor ||
          !listEquals(after.tableNumbers, row.$2.tableNumbers)) {
        throw OrderMutationConflict(
          'ownership_change',
          'Move tables through the ownership coordinator',
        );
      }
      if (row.$2.statusEnum.isTerminal &&
          !OrderTransferIntent.sameImage(requested, expected)) {
        throw OrderMutationConflict(
          'stale_order',
          'Finalized Order cannot be edited',
        );
      }
      final virtual = Map<dynamic, Order>.of(DatabaseCore.orderBox!.toMap())
        ..[row.$1] = after;
      final refs = {for (final n in after.tableNumbers) '${after.floor}|$n'};
      final issues = integrityReport(orders: virtual.values)
          .where(
            (e) =>
                e['orderId'] == after.orderId ||
                e['activeOrderId'] == after.orderId ||
                (e['orderIds'] as List?)?.contains(after.orderId) == true ||
                refs.contains(e['tableRef']),
          )
          .toList();
      if (issues.isNotEmpty)
        throw OrderMutationConflict(
          'repair_required',
          'Order update violates table ownership',
          issues: issues,
        );
      await DatabaseCore.orderBox!.put(row.$1, after);
      await DatabaseCore.orderBox!.flush();
      draft.mutationBaseline = image(after);
      draft.mutationKey = row.$1;
    });
  }

  static List<OrderTableMutationIntent> records() {
    final box = DatabaseCore.metaBox;
    if (box == null || !box.isOpen) return [];
    return [
      for (final e in box.toMap().entries)
        if (e.key is String &&
            (e.key as String).startsWith(prefix) &&
            !TableRepairRepository.isRecord(e.key, e.value) &&
            !OrderEditRepository.isRecord(e.key, e.value))
          decode(e.key as String, e.value),
    ];
  }

  static OrderTableMutationIntent decode(String storedKey, Object? value) {
    final intent = OrderTableMutationIntent.decode(value);
    if (storedKey != key(intent.id))
      throw const FormatException('Ownership journal key mismatch');
    return intent;
  }

  static OrderTableMutationIntent? read(String id) {
    final box = DatabaseCore.metaBox;
    if (box == null || !box.isOpen) return null;
    final value = box.get(key(id));
    return value == null ? null : decode(key(id), value);
  }

  static Future<void> write(OrderTableMutationIntent intent) async {
    final value = intent.toMap();
    decode(key(intent.id), value);
    if (DatabaseCore.metaBox == null || !DatabaseCore.metaBox!.isOpen) {
      DatabaseCore.metaBox = await Hive.openBox(DatabaseCore.metaBoxName);
    }
    await DatabaseCore.metaBox!.put(key(intent.id), value);
    await DatabaseCore.metaBox!.flush();
  }

  static Object? persistedImage(
    String store,
    Object key, {
    Map<String, Map<dynamic, dynamic>>? stores,
  }) {
    final boxName = switch (store) {
      'reservation' => 'reservations',
      'auditReport' || 'auditEvent' => 'auditLog',
      _ => store,
    };
    final value = stores != null
        ? stores[boxName]![key]
        : switch (store) {
            'orders' => DatabaseCore.orderBox?.get(key),
            'tables' => DatabaseCore.tableBox?.get(key),
            'reservation' => DatabaseCore.reservationBox?.get(key),
            'sales' => DatabaseCore.salesBox?.get(key),
            'settings' => DatabaseCore.settingsBox?.get(key),
            'auditReport' || 'auditEvent' => DatabaseCore.auditLogBox?.get(key),
            _ => throw StateError('Unknown ownership store'),
          };
    if (value == null) return null;
    return switch (store) {
      'orders' => image(value as Order),
      'tables' => tableImage(value as TableModel),
      'reservation' => reservationImage(value as Reservation),
      'auditEvent' => (OrderTransferIntent.cloneMap(
        value as Map,
      )..['synced'] = 0),
      _ => value,
    };
  }

  static void validateCurrent(
    OrderTableMutationIntent intent,
    Object? Function(String, Object) readImage,
  ) {
    if (!intent.pending) return;
    for (var i = 0; i < intent.effects.length; i++) {
      final e = intent.effects[i];
      final actual = readImage(e['store'] as String, e['key'] as Object);
      final expected = i < intent.next ? e['after'] : e['before'];
      if (!OrderTransferIntent.sameImage(actual, expected) &&
          !(i == intent.next &&
              OrderTransferIntent.sameImage(actual, e['after']))) {
        throw StateError('Ownership persisted image disagrees with effect $i');
      }
    }
  }

  static Future<void> finish(OrderTableMutationIntent intent) async {
    if (!intent.pending) return;
    if (dateKey != intent.businessDate)
      throw StateError('Ownership business date changed');
    validateCurrent(intent, persistedImage);
    validateFinalOwnership(intent);
    for (var i = intent.next; i < intent.effects.length; i++) {
      final e = intent.effects[i];
      final store = e['store'] as String;
      final rowKey = e['key'] as Object;
      final after = e['after'];
      final already = OrderTransferIntent.sameImage(
        persistedImage(store, rowKey),
        after,
      );
      switch (store) {
        case 'sales':
          if (!already) await DatabaseCore.salesBox!.put(rowKey, after);
          await DatabaseCore.salesBox!.flush();
        case 'orders':
          if (!already)
            await DatabaseCore.orderBox!.put(
              rowKey,
              OrderTransferIntent.orderImage(after),
            );
          await DatabaseCore.orderBox!.flush();
        case 'tables':
          if (!already)
            await DatabaseCore.tableBox!.put(
              rowKey,
              TableModel.fromJson(after as Map<String, dynamic>),
            );
          await DatabaseCore.tableBox!.flush();
        case 'settings':
          if (!already) await DatabaseCore.settingsBox!.put(rowKey, after);
          await DatabaseCore.settingsBox!.flush();
        case 'auditReport':
          if (!already) await DatabaseCore.auditLogBox!.put(rowKey, after);
          await DatabaseCore.auditLogBox!.flush();
        case 'auditEvent':
          await AuditEventService.appendDurableOnce(
            AuditEventLog.fromMap(after as Map<String, dynamic>),
          );
        case 'reservation':
          final r = DatabaseCore.reservationBox!.get(rowKey)!;
          final proposed = after as Map<String, dynamic>;
          if (!already) {
            r.linkedOrderId = (proposed['linkedOrderId'] as num?)?.toInt();
            r.status = proposed['status'] as String;
            r.tableRefs = (proposed['tableRefs'] as List?)?.cast<String>();
            r.tableNumbers = (proposed['tableNumbers'] as List).cast<int>();
            await DatabaseCore.reservationBox!.put(rowKey, r);
          }
          await DatabaseCore.reservationBox!.flush();
      }
      intent.body['nextEffect'] = i + 1;
      intent.body['phase'] = i + 1 == intent.effects.length
          ? 'completed'
          : 'effect${i + 1}';
      await write(intent);
    }
  }

  static Future<void> recoverPending({bool underExclusive = false}) async {
    Future<void> recover() async {
      try {
        final pending = records().where((e) => e.pending).toList();
        if (pending.length > 1)
          throw StateError('Multiple pending ownership intents');
        for (final intent in pending) await finish(intent);
        if (LocalDataAdmission.failure?.startsWith('Order/table recovery:') ==
            true)
          LocalDataAdmission.failure = null;
      } catch (error) {
        LocalDataAdmission.failure = 'Order/table recovery: $error';
        rethrow;
      }
    }

    if (underExclusive) return recover();
    await LocalDataAdmission.exclusive(
      recover,
      recovery: true,
      operation: 'orderOwnership',
    );
  }

  static Map<String, dynamic> effect(
    String store,
    Object rowKey,
    Object? after,
  ) => {
    'store': store,
    'key': rowKey,
    'before': persistedImage(store, rowKey),
    'after': after,
  };
  static Future<Order> commit({
    required String id,
    required String kind,
    required Map<String, dynamic> request,
    required Order order,
    required List<Map<String, dynamic>> effects,
  }) async {
    final intent = OrderTableMutationIntent({
      'version': 1,
      'requestId': id,
      'kind': kind,
      'businessDate': dateKey,
      'request': OrderTransferIntent.cloneMap(request),
      'fingerprint': PosBackupFormat.digest(request),
      'phase': 'intent',
      'nextEffect': 0,
      'effects': effects,
      'outcome': {
        'orderId': order.orderId,
        'orderUuid': order.orderUuid,
        'order': image(order),
      },
    });
    // Validate the plan before marking an intent write as potentially durable.
    decode(key(id), intent.toMap());
    validateCurrent(intent, persistedImage);
    validateFinalOwnership(intent);
    try {
      await write(intent);
      await finish(intent);
    } catch (error) {
      // Inside the ordinary owner, before queued writers can resume.
      LocalDataAdmission.failure = 'Order/table recovery: $error';
      throw OrderMutationConflict(
        'recovery_required',
        'Ownership transition requires recovery: $error',
      );
    }
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: kind == 'create' ? 'created' : 'updated',
        payload: {'orderId': order.orderId, 'requestId': id},
      ),
    );
    SyncHub.notify(SyncEvent(type: SyncEventType.tables, action: 'updated'));
    AuditRepository.notifyAuditChanged();
    final row = persisted(order.orderId, uuid: order.orderUuid)!;
    if (OrderTableShadow.observer != null && kind != 'cancel') {
      try {
        final captured = kind == 'move'
            ? PosShadowProjection.moved(
                row.$2,
                (request['order']['tableNumbers'] as List).cast<String>(),
                request['order']['floor'] as String,
                proposed: false,
              )
            : PosShadowProjection.orders([row.$2]);
        LocalDataAdmission.afterMutation(
          () => OrderTableShadow.observe<void>(
            proposed: () => captured,
            actual: () => captured,
            operation: () async {},
          ),
        );
      } catch (error, stack) {
        developer.log(
          'Committed ownership diagnostic could not be captured',
          error: error,
          stackTrace: stack,
          name: 'order_table_mutation',
        );
      }
    }
    return detached(row.$2, row.$1);
  }

  static Order? retry(String id, Map<String, dynamic> request) {
    final old = read(id);
    if (old == null) return null;
    if (old.fingerprint != PosBackupFormat.digest(request)) {
      throw OrderMutationConflict(
        'request_conflict',
        'Request ID reused with another payload',
      );
    }
    if (old.pending)
      throw OrderMutationConflict(
        'recovery_required',
        'Recover pending request before retry',
      );
    // Completed images are outcomes, never replayed over subsequent edits.
    return OrderTransferIntent.orderImage(old.outcome['order']);
  }

  static Map<String, dynamic> itemRequest(OrderItem item) =>
      item.toJson()..remove('lineUuid');
  static Future<Order> create({
    required Map<String, dynamic> request,
    required Order order,
    required AuditEvent creationEvent,
    List<AuditEvent> extraEvents = const [],
    String? requestId,
    String? activatesReservationId,
  }) async {
    final id = requestId ?? const Uuid().v4();
    final old = retry(id, request);
    if (old != null) return old;
    final refs = {
      if (order.floor != 'takeaway')
        for (final t in order.tableNumbers) '${order.floor}|$t',
    };
    requireConsistent(refs: refs, orderId: order.orderId);
    if (persisted(order.orderId) != null)
      throw OrderMutationConflict(
        'request_conflict',
        'Order ID already exists',
      );
    var rowKey = 0;
    for (final k in DatabaseCore.orderBox!.keys.whereType<int>())
      if (k >= rowKey) rowKey = k + 1;
    final effects = [effect('orders', rowKey, image(order))];
    final lastId = DatabaseCore.settingsBox?.get('lastOrderId') as int? ?? 0;
    effects.add(
      effect(
        'settings',
        'lastOrderId',
        order.orderId > lastId ? order.orderId : lastId,
      ),
    );
    for (final ref in refs) {
      final rows = DatabaseCore.tableBox!
          .toMap()
          .entries
          .where((e) => '${e.value.floor}|${e.value.tableNumber}' == ref)
          .toList();
      if (rows.length != 1)
        throw OrderMutationConflict(
          'repair_required',
          'Physical table $ref missing/ambiguous',
        );
      final t = rows.single.value;
      if ((t.isReserved || t.activeOrderId != null) &&
          !(activatesReservationId != null &&
              t.activeOrderId == null &&
              t.reservationId == activatesReservationId)) {
        throw OrderMutationConflict(
          'table_busy',
          'Physical table $ref is busy',
        );
      }
      final after = TableModel.fromJson(tableImage(t))
        ..isReserved = true
        ..activeOrderId = order.orderId
        ..reservedBy = order.createdBy
        ..reservedAt = order.createdAt
        ..reservationId = activatesReservationId;
      effects.add(effect('tables', rows.single.key, tableImage(after)));
    }
    final reportKey = AuditRepository.buildAuditReportKey(order.orderId);
    if (DatabaseCore.auditLogBox!.containsKey(reportKey))
      throw OrderMutationConflict(
        'repair_required',
        'New Order ID already has an audit report',
      );
    final events = [
      creationEvent,
      for (final item in order.items)
        AuditEvent(
          type: AuditEventType.addItem,
          itemName: item.itemName,
          previousQty: 0,
          newQty: item.quantity,
          waiterId: order.createdBy,
          waiterName: order.createdBy,
          timestamp: order.createdAt,
          details: {
            if (item.menuItemId != null) 'menuItemId': item.menuItemId,
            if (item.variantId != null) 'variantId': item.variantId,
          },
        ),
      ...extraEvents,
    ];
    final report = AuditReport(
      reportId: reportKey,
      orderId: order.orderId,
      tableNumbers: List.of(order.tableNumbers),
      floor: order.floor,
      openedById: order.createdBy,
      openedByName: order.createdBy,
      openedAt: order.createdAt,
      status: AuditReportStatus.open,
      locked: false,
      updatedAt: extraEvents.isEmpty
          ? order.createdAt
          : extraEvents.last.timestamp,
      events: [
        for (var i = 0; i < events.length; i++) events[i].copyWith(sequence: i),
      ],
    );
    effects.add(effect('auditReport', reportKey, report.toMap()));
    final audit = AuditEventLog(
      id: '$id:created',
      action: order.floor == 'takeaway'
          ? 'TAKEAWAY_ORDER_CREATED'
          : 'ORDER_CREATED',
      userId: order.createdBy,
      entityType: GlobalAuditEntity.order,
      entityId: '${order.orderId}',
      createdAt: order.createdAt,
      deviceType: 'pos',
      data: {
        'requestId': id,
        'orderId': order.orderId,
        'tableNumbers': order.tableNumbers,
        'floor': order.floor,
        'total': order.totalAmount,
      },
    );
    effects.add(effect('auditEvent', audit.id, audit.toMap()));
    if (activatesReservationId != null) {
      final rows = DatabaseCore.reservationBox!
          .toMap()
          .entries
          .where((e) => e.value.id == activatesReservationId)
          .toList();
      if (rows.length != 1 ||
          !ReservationClassification.isRealAdvanceBooking(rows.single.value)) {
        throw OrderMutationConflict(
          'repair_required',
          'Activation Reservation missing/ambiguous',
        );
      }
      final r = rows.single.value;
      if (r.linkedOrderId != null)
        throw OrderMutationConflict(
          'stale_order',
          'Reservation already linked',
        );
      final after = reservationImage(r)
        ..['linkedOrderId'] = order.orderId
        ..['status'] = ReservationStatus.inProgress.storageValue;
      effects.add(effect('reservation', rows.single.key, after));
      final bookingAudit = AuditEventLog(
        id: '$id:reservation',
        action: ReservationAuditAction.update,
        userId: order.createdBy,
        entityType: GlobalAuditEntity.reservation,
        entityId: r.id,
        createdAt: DateTime.now(),
        deviceType: 'pos',
        data: {
          ...ReservationAudit.snapshot(r),
          'requestId': id,
          'businessDate': dateKey,
          'linkedOrderId': order.orderId,
          'status': after['status'],
          'previousStatus': r.status,
          'newStatus': after['status'],
          'actorId': order.createdBy,
          'actorName': order.createdBy,
          'source':
              creationEvent.details?['source'] ?? AuditSource.pos.wireValue,
          'reason': 'Activated',
          'orderId': order.orderId,
        },
      );
      effects.add(effect('auditEvent', bookingAudit.id, bookingAudit.toMap()));
    }
    return commit(
      id: id,
      kind: 'create',
      request: request,
      order: order,
      effects: effects,
    );
  }

  static Future<Order> move({
    required Order expected,
    required List<String> tableNumbers,
    required String floor,
    required String actor,
    String? requestId,
  }) {
    final request = {
      'order': image(expected),
      'tableNumbers': List.of(tableNumbers),
      'floor': floor,
      'actor': actor,
    };
    final frozen = BackupRepository.deserializeOrderSnapshot(image(expected))
      ..mutationBaseline = OrderTransferIntent.cloneMap(
        expected.mutationBaseline ?? image(expected),
      );
    final id = requestId ?? const Uuid().v4();
    return UpdateReadiness.mutate('changeTables', () async {
      final old = retry(id, request);
      if (old != null) return old;
      final current = requireFresh(frozen);
      if (current.floor == 'takeaway' ||
          floor == 'takeaway' ||
          tableNumbers.isEmpty) {
        throw ArgumentError('Physical table move requires physical tables');
      }
      final target = (request['tableNumbers'] as List<String>).toSet().toList();
      final refs = {
        for (final t in current.tableNumbers) '${current.floor}|$t',
        for (final t in target) '$floor|$t',
      };
      requireConsistent(refs: refs, orderId: current.orderId);
      final after = BackupRepository.deserializeOrderSnapshot(image(current))
        ..tableNumbers = target
        ..floor = floor
        ..updatedAt = now();
      final effects = [
        effect('orders', persisted(current.orderId)!.$1, image(after)),
      ];
      for (final ref in refs) {
        final rows = DatabaseCore.tableBox!
            .toMap()
            .entries
            .where((e) => '${e.value.floor}|${e.value.tableNumber}' == ref)
            .toList();
        if (rows.length != 1)
          throw OrderMutationConflict(
            'repair_required',
            'Physical table $ref missing/ambiguous',
          );
        final t = rows.single.value;
        final targetOwns = target.contains(t.tableNumber) && t.floor == floor;
        if (targetOwns &&
            (t.activeOrderId != null && t.activeOrderId != current.orderId ||
                t.isReserved && t.activeOrderId != current.orderId))
          throw OrderMutationConflict(
            'table_busy',
            'Move destination $ref busy',
          );
        if (!targetOwns && t.activeOrderId != current.orderId)
          throw OrderMutationConflict(
            'repair_required',
            'Source ownership changed',
          );
        final proposed = TableModel.fromJson(tableImage(t));
        if (targetOwns) {
          proposed.reserve(
            actor,
            current.orderId,
            reservationId: t.reservationId,
          );
          proposed.reservedAt = after.updatedAt;
        } else {
          proposed.free();
        }
        effects.add(effect('tables', rows.single.key, tableImage(proposed)));
      }
      final prior = AuditRepository.getAuditReport(current.orderId);
      if (prior == null || prior.locked)
        throw OrderMutationConflict(
          'repair_required',
          'Move needs an open Order audit',
        );
      var sequence = 0;
      for (final event in prior.events)
        if ((event.sequence ?? -1) >= sequence) sequence = event.sequence! + 1;
      final event = AuditEvent(
        type: AuditEventType.custom,
        itemName: OrderAuditDetails.orderItemName,
        previousQty: 0,
        newQty: 0,
        waiterId: actor,
        waiterName: actor,
        timestamp: after.updatedAt!,
        sequence: sequence,
        details: {
          'action': 'TABLE_CHANGED',
          'requestId': id,
          'fromTables': current.tableNumbers,
          'fromFloor': current.floor,
          'toTables': target,
          'toFloor': floor,
          ...OrderAuditDetails.base(
            order: after,
            orderKind: OrderAuditDetails.walkIn,
            source: AuditSource.pos,
            actorId: actor,
          ),
        },
      );
      final report = prior.copyWith(
        events: [...prior.events, event],
        updatedAt: after.updatedAt,
        tableNumbers: target,
        floor: floor,
      );
      effects.add(effect('auditReport', prior.reportId, report.toMap()));
      for (final row
          in DatabaseCore.reservationBox?.toMap().entries ??
              const <MapEntry<dynamic, Reservation>>[]) {
        final r = row.value;
        if (r.linkedOrderId != current.orderId ||
            !ReservationClassification.isRealAdvanceBooking(r))
          continue;
        final targetRefs = [
          for (final t in target) TableRef(floor: floor, tableNumber: t),
        ];
        final proposed = reservationImage(r)
          ..['tableNumbers'] = ReservationTableAvailability.legacyCodesOf(
            targetRefs,
          )
          ..['tableRefs'] = targetRefs.map((r) => r.encode()).toList();
        effects.add(effect('reservation', row.key, proposed));
      }
      return commit(
        id: id,
        kind: 'move',
        request: request,
        order: after,
        effects: effects,
      );
    });
  }
}
