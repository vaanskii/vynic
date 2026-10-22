import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_edit_projection.dart';
import 'package:vynic/core/services/audit/audit_order_diff_service.dart';
import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/services/sync/sync_events.dart';

/// Additive fail-closed sibling in the established operational WAL namespace.
/// The receipt outlives the transport journal and never replays a later edit.
abstract final class OrderEditRepository {
  static const kind = 'orderEdit';
  static final uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
  );
  static String key(String id) => OrderTableMutationRepository.key(id);
  static bool hasReceipt(String id) =>
      DatabaseCore.metaBox?.get(key(id)) != null;
  static bool isRecord(Object? k, Object? raw) {
    if (k is! String ||
        !k.startsWith(OrderTableMutationRepository.prefix) ||
        raw is! Map ||
        raw['kind'] != kind)
      return false;
    decode(k, raw);
    return true;
  }

  static List<Map<String, dynamic>> records() => [
    for (final e in DatabaseCore.metaBox!.toMap().entries)
      if (isRecord(e.key, e.value)) decode(e.key as String, e.value),
  ];
  static Map<String, dynamic> request(Map<String, dynamic> p) {
    final r = p['request'];
    if (r is! Map ||
        r['posOrderId'] is! int ||
        r['posOrderId'] <= 0 ||
        r['expectedFingerprint'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(r['expectedFingerprint']) ||
        r['includeServiceFee'] is! bool ||
        r['items'] is! List ||
        (r['items'] as List).length > 1000 ||
        r['customServiceFeePercentage'] != null &&
            (r['customServiceFeePercentage'] is! num ||
                !(r['customServiceFeePercentage'] as num).isFinite ||
                r['customServiceFeePercentage'] < 0 ||
                r['customServiceFeePercentage'] > 100) ||
        p['actorStaffId'] is! String ||
        !uuid.hasMatch(p['actorStaffId']) ||
        p['actorUsername'] is! String ||
        (p['actorUsername'] as String).trim().isEmpty ||
        p['businessDate'] is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p['businessDate']) ||
        p['baseline'] is! Map)
      throw const FormatException('Invalid Manager edit request');
    final baseline = OrderEditProjection.read(
      Map<String, dynamic>.from(p['baseline']),
    );
    if (baseline.orderId != r['posOrderId'] ||
        p['baseline']['fingerprint'] != r['expectedFingerprint'])
      throw const FormatException('Edit baseline identity differs');
    final lines = <String>{};
    final items = <Map<String, dynamic>>[];
    bool money(Object? v) =>
        v is num &&
        v.isFinite &&
        v >= 0 &&
        v <= 1000000000 &&
        (v * 100 - (v * 100).round()).abs() < 0.000001;
    for (final raw in r['items']) {
      if (raw is! Map ||
          raw['itemKey'] is! String ||
          (raw['itemKey'] as String).trim().isEmpty ||
          (raw['itemKey'] as String).length > 512 ||
          raw['itemName'] is! String ||
          (raw['itemName'] as String).trim().isEmpty ||
          (raw['itemName'] as String).length > 512 ||
          raw['lineUuid'] is! String ||
          (raw['lineUuid'] as String).trim().isEmpty ||
          (raw['lineUuid'] as String).length > 512 ||
          !lines.add(raw['lineUuid']) ||
          raw['quantity'] is! int ||
          raw['quantity'] <= 0 ||
          raw['quantity'] > 100000 ||
          !money(raw['unitPrice']) ||
          raw['unitPrice'] > 10000000 ||
          !money(raw['total']) ||
          raw['comment'] != null &&
              (raw['comment'] is! String ||
                  (raw['comment'] as String).length > 4096) ||
          [raw['menuItemId'], raw['variantId']].any(
            (v) =>
                v != null &&
                (v is! String || v.trim().isEmpty || v.length > 512),
          ))
        throw const FormatException('Invalid Manager edit items');
      items.add({
        'itemKey': raw['itemKey'],
        'itemName': raw['itemName'],
        'lineUuid': raw['lineUuid'],
        'unitPrice': (raw['unitPrice'] as num).toDouble(),
        'quantity': raw['quantity'],
        'total': (raw['total'] as num).toDouble(),
        'comment': raw['comment'],
        if (raw['menuItemId'] != null) 'menuItemId': raw['menuItemId'],
        if (raw['variantId'] != null) 'variantId': raw['variantId'],
      });
    }
    for (final item in items) {
      final matches = baseline.items
          .where(
            (b) =>
                b.lineUuid == item['lineUuid'] && b.itemKey == item['itemKey'],
          )
          .toList();
      final original = matches.length == 1 ? matches.single : null;
      final expected =
          original != null &&
              original.quantity == item['quantity'] &&
              original.unitPrice == item['unitPrice']
          ? original.total
          : ((item['quantity'] as int) * (item['unitPrice'] as double) * 100)
                    .round() /
                100;
      if (((item['total'] as double) - expected).abs() > 0.000001)
        throw const FormatException('Invalid line total');
    }
    return {
      'request': {
        'posOrderId': r['posOrderId'],
        'expectedFingerprint': r['expectedFingerprint'],
        'items': items,
        'includeServiceFee': r['includeServiceFee'],
        'customServiceFeePercentage': r['customServiceFeePercentage'] == null
            ? null
            : (r['customServiceFeePercentage'] as num).toDouble(),
      },
      'baseline': Map<String, dynamic>.from(p['baseline']),
      'businessDate': p['businessDate'],
      'actorStaffId': p['actorStaffId'],
      'actorUsername': p['actorUsername'],
    };
  }

  static Order proposed(Map<String, dynamic> r, DateTime at, double feeRate) {
    final order = OrderEditProjection.read(
      Map<String, dynamic>.from(r['baseline']),
    );
    final body = r['request'] as Map;
    order.items = [
      for (final v in body['items'])
        OrderItem.fromJson(Map<String, dynamic>.from(v)),
    ];
    order.includeServiceFee = body['includeServiceFee'];
    order.customServiceFeePercentage =
        (body['customServiceFeePercentage'] as num?)?.toDouble();
    order.updatedAt = DateTime.fromMillisecondsSinceEpoch(
      at.millisecondsSinceEpoch,
      isUtc: at.isUtc,
    );
    order.recalculateTotal(serviceFeeRate: feeRate);
    return order;
  }

  static Map<String, dynamic> event(
    String id,
    Map<String, dynamic> r,
    Order before,
    Order after,
  ) => AuditEventLog(
    id: id,
    action:
        before.includeServiceFee != after.includeServiceFee ||
            before.customServiceFeePercentage !=
                after.customServiceFeePercentage
        ? 'ORDER_SERVICE_FEE_CHANGED'
        : 'ORDER_EDITED',
    userId: r['actorStaffId'],
    entityType: 'ORDER',
    entityId: '${before.orderId}',
    deviceType: 'pos',
    createdAt: after.updatedAt,
    data: {
      'requestId': id,
      'actorUsername': r['actorUsername'],
      'orderUuid': before.orderUuid,
      'previousTotal': before.totalAmount,
      'newTotal': after.totalAmount,
      'previousIncluded': before.includeServiceFee,
      'newIncluded': after.includeServiceFee,
      'previousPercent': before.customServiceFeePercentage,
      'newPercent': after.customServiceFeePercentage,
      'edit': r['request'],
    },
  ).toMap();
  static Map<String, dynamic> report(
    String id,
    Map<String, dynamic> r,
    Order before,
    Order after,
    Object? raw,
  ) {
    final base = raw == null
        ? AuditReport(
            reportId: AuditRepository.buildAuditReportKey(before.orderId),
            orderId: before.orderId,
            tableNumbers: before.tableNumbers,
            floor: before.floor,
            openedById: before.createdBy,
            openedByName: before.createdBy,
            openedAt: before.createdAt,
            status: AuditReportStatus.open,
            events: [],
            updatedAt: before.createdAt,
          )
        : AuditReport.fromMap(Map<String, dynamic>.from(raw as Map));
    if (base.locked || base.orderId != before.orderId)
      throw const FormatException('Edit audit report locked/invalid');
    final events = AuditOrderDiffService.buildEvents(
      previousItems: [
        for (final item in before.items) item.clone()..itemKey = item.lineUuid!,
      ],
      updatedItems: [
        for (final item in after.items) item.clone()..itemKey = item.lineUuid!,
      ],
      performerId: r['actorStaffId'],
      performerName: r['actorUsername'],
      timestamp: after.updatedAt!,
    );
    events.add(
      AuditEvent(
        type: AuditEventType.adjustOrder,
        itemName: 'Manager edit',
        previousQty: 0,
        newQty: 0,
        waiterId: r['actorStaffId'],
        waiterName: r['actorUsername'],
        timestamp: after.updatedAt!,
        details: {
          'requestId': id,
          'source': 'MANAGER',
          'field': 'managerEdit',
          'previousTotal': before.totalAmount,
          'newTotal': after.totalAmount,
          'edit': r['request'],
        },
      ),
    );
    var sequence =
        base.events.fold<int>(
          -1,
          (n, e) => e.sequence != null && e.sequence! > n ? e.sequence! : n,
        ) +
        1;
    return base
        .copyWith(
          events: [
            ...base.events,
            for (final e in events) e.copyWith(sequence: sequence++),
          ],
          updatedAt: after.updatedAt,
        )
        .toMap();
  }

  static Map<String, dynamic> decode(String k, Object? raw) {
    if (raw is! Map) throw const FormatException('Missing edit intent');
    final v = OrderTransferIntent.cloneMap(raw);
    final digest = v.remove('digest');
    if (v['version'] != 1 ||
        v['kind'] != kind ||
        digest != PosBackupFormat.digest(v) ||
        v['requestId'] is! String ||
        !uuid.hasMatch(v['requestId']) ||
        k != key(v['requestId']) ||
        ![
          'intent',
          'order',
          'report',
          'audit',
          'completed',
        ].contains(v['phase']) ||
        v['orderKey'] is! int && v['orderKey'] is! String ||
        v['request'] is! Map ||
        v['before'] is! Map ||
        v['after'] is! Map ||
        v['feeRate'] is! num ||
        !(v['feeRate'] as num).isFinite ||
        v['feeRate'] < 0 ||
        v['feeRate'] > 1)
      throw const FormatException('Invalid edit intent identity/digest/phase');
    final r = request(Map<String, dynamic>.from(v['request']));
    if (!OrderTransferIntent.sameImage(r, v['request']) ||
        v['fingerprint'] != PosBackupFormat.digest(r))
      throw const FormatException('Edit request differs');
    final before = OrderEditProjection.read(
      Map<String, dynamic>.from(r['baseline']),
    );
    final after = BackupRepository.deserializeOrderSnapshot(
      Map<String, dynamic>.from(v['after']),
    );
    final expected = proposed(
      r,
      after.updatedAt!,
      (v['feeRate'] as num).toDouble(),
    );
    if (!OrderTransferIntent.sameImage(
          OrderTransferIntent.snapshot(before),
          v['before'],
        ) ||
        !OrderTransferIntent.sameImage(
          OrderTransferIntent.snapshot(expected),
          v['after'],
        ) ||
        before.statusEnum.isTerminal ||
        !OrderTransferIntent.sameImage(
          event(v['requestId'], r, before, after),
          v['audit'],
        ) ||
        !OrderTransferIntent.sameImage(
          report(v['requestId'], r, before, after, v['beforeReport']),
          v['afterReport'],
        ))
      throw const FormatException('Edit plan changes unrelated fields/audit');
    return v;
  }

  static void validateCurrent(
    Map<String, dynamic> v,
    Map<dynamic, Order> orders,
    Map<dynamic, dynamic> audit,
  ) {
    final row = orders[v['orderKey']];
    if (row == null) throw const FormatException('Edit order disappeared');
    final current = OrderTransferIntent.snapshot(row);
    if (!OrderTransferIntent.sameImage(current, v['after']) &&
        (v['phase'] != 'intent' ||
            !OrderTransferIntent.sameImage(current, v['before'])))
      throw const FormatException('Order changed during edit recovery');
    final reportKey = AuditRepository.buildAuditReportKey(row.orderId),
        rawReport = audit[reportKey];
    if (!OrderTransferIntent.sameImage(rawReport, v['afterReport']) &&
        (!['intent', 'order'].contains(v['phase']) ||
            !OrderTransferIntent.sameImage(rawReport, v['beforeReport'])))
      throw const FormatException('Edit audit report differs');
    validateAudit(v, audit[v['requestId']]);
  }

  static void validateAudit(Map<String, dynamic> v, Object? raw) {
    if (raw == null) {
      if (['audit', 'completed'].contains(v['phase']))
        throw const FormatException('Missing edit receipt audit');
      return;
    }
    final actual = OrderTransferIntent.cloneMap(raw as Map)..remove('synced');
    final expected = OrderTransferIntent.cloneMap(v['audit'] as Map)
      ..remove('synced');
    if (!OrderTransferIntent.sameImage(actual, expected))
      throw const FormatException('Edit receipt audit differs');
  }

  static Map<String, dynamic> resultProjection(Map<String, dynamic> v) =>
      OrderEditProjection.build(
        BackupRepository.deserializeOrderSnapshot(
          Map<String, dynamic>.from(v['after']),
        ),
        effectiveServiceFeePercent: (v['feeRate'] as num).toDouble() * 100,
      );
  static Map<String, dynamic> retainedResult(
    String id,
    Map<String, dynamic> payload,
  ) {
    final raw = DatabaseCore.metaBox!.get(key(id));
    if (raw == null)
      throw const FormatException('Missing durable edit receipt');
    final v = decode(key(id), raw);
    if (v['phase'] != 'completed' ||
        v['fingerprint'] != PosBackupFormat.digest(request(payload)))
      throw const FormatException(
        'Unresolved or different durable edit receipt',
      );
    validateAudit(v, DatabaseCore.auditLogBox!.get(id));
    return resultProjection(v);
  }

  static Future<void> write(Map<String, dynamic> v) async {
    final sealed = {...v, 'digest': PosBackupFormat.digest(v)};
    decode(key(v['requestId']), sealed);
    await DatabaseCore.metaBox!.put(key(v['requestId']), sealed);
    await DatabaseCore.metaBox!.flush();
  }

  static Future<void> finish(Map<String, dynamic> v) async {
    validateAudit(v, DatabaseCore.auditLogBox!.get(v['requestId']));
    if (v['phase'] == 'completed') return;
    if (OrderTableMutationRepository.dateKey != v['request']['businessDate'])
      throw const FormatException('Edit recovery date changed');
    validateCurrent(
      v,
      DatabaseCore.orderBox!.toMap(),
      DatabaseCore.auditLogBox!.toMap(),
    );
    OrderTableMutationRepository.requireConsistent(
      orderId: v['request']['request']['posOrderId'],
    );
    if (v['phase'] == 'intent') {
      await DatabaseCore.orderBox!.put(
        v['orderKey'],
        BackupRepository.deserializeOrderSnapshot(
          Map<String, dynamic>.from(v['after']),
        ),
      );
      await DatabaseCore.orderBox!.flush();
      v['phase'] = 'order';
      await write(v);
    }
    if (v['phase'] == 'order') {
      await DatabaseCore.auditLogBox!.put(
        AuditRepository.buildAuditReportKey(
          v['request']['request']['posOrderId'],
        ),
        v['afterReport'],
      );
      await DatabaseCore.auditLogBox!.flush();
      v['phase'] = 'report';
      await write(v);
    }
    if (v['phase'] == 'report') {
      await AuditEventService.appendDurableOnce(
        AuditEventLog.fromMap(Map<String, dynamic>.from(v['audit'])),
      );
      v['phase'] = 'audit';
      await write(v);
    }
    v['phase'] = 'completed';
    await write(v);
    SyncHub.notify(
      SyncEvent(
        type: SyncEventType.orders,
        action: 'updated',
        payload: {'orderId': v['request']['request']['posOrderId']},
      ),
    );
    AuditRepository.notifyAuditChanged();
  }

  static Future<PosCommandOutcome> apply(
    Map<String, dynamic> p,
  ) => UpdateReadiness.mutate('managerOrderEdit', () async {
    final Map<String, dynamic> r;
    try {
      r = request(p);
    } on FormatException {
      return const PosCommandOutcome.invalid('invalid_order_edit_request');
    }
    final id = p['_mutationRequestId'];
    if (id is! String || !uuid.hasMatch(id))
      return const PosCommandOutcome.invalid('invalid_order_edit_request');
    final stored = DatabaseCore.metaBox!.get(key(id));
    if (stored != null) {
      final v = decode(key(id), stored);
      if (v['fingerprint'] != PosBackupFormat.digest(r))
        return const PosCommandOutcome.conflicting('request_conflict');
      await finish(v);
      return PosCommandOutcome.success(
        code: 'order_edited',
        data: OrderEditProjection.build(
          BackupRepository.deserializeOrderSnapshot(
            Map<String, dynamic>.from(v['after']),
          ),
          effectiveServiceFeePercent: (v['feeRate'] as num).toDouble() * 100,
        ),
      );
    }
    if (OrderTableMutationRepository.dateKey != r['businessDate'])
      return const PosCommandOutcome.conflicting('stale_date');
    final row = OrderTableMutationRepository.persisted(
      r['request']['posOrderId'],
      uuid: r['baseline']['orderUuid'],
    );
    if (row == null) return const PosCommandOutcome.missing('order_not_found');
    if (row.$2.statusEnum.isTerminal)
      return const PosCommandOutcome.conflicting('closed_order');
    if (OrderEditProjection.build(row.$2)['fingerprint'] !=
        r['request']['expectedFingerprint'])
      return const PosCommandOutcome.conflicting('stale_order');
    OrderTableMutationRepository.requireFresh(
      OrderTableMutationRepository.detached(row.$2, row.$1),
    );
    if (r['request']['includeServiceFee'] &&
        !SettingsRepository.isServiceFeeAvailable())
      return const PosCommandOutcome.conflicting('service_fee_unavailable');
    final feeRate =
        ((r['request']['customServiceFeePercentage'] as num?)?.toDouble() ??
            SettingsRepository.getServiceFeePercentage()) /
        100;
    final after = proposed(
      r,
      BusinessDayRepository.getCurrentDateTime(),
      feeRate,
    );
    final beforeReport = DatabaseCore.auditLogBox!.get(
      AuditRepository.buildAuditReportKey(row.$2.orderId),
    );
    final v = <String, dynamic>{
      'version': 1,
      'kind': kind,
      'requestId': id,
      'request': r,
      'fingerprint': PosBackupFormat.digest(r),
      'orderKey': row.$1,
      'before': OrderTransferIntent.snapshot(row.$2),
      'after': OrderTransferIntent.snapshot(after),
      'feeRate': feeRate,
      'beforeReport': beforeReport,
      'afterReport': report(
        id,
        r,
        OrderEditProjection.read(Map<String, dynamic>.from(r['baseline'])),
        after,
        beforeReport,
      ),
      'audit': event(id, r, row.$2, after),
      'phase': 'intent',
    };
    decode(key(id), {...v, 'digest': PosBackupFormat.digest(v)});
    try {
      await write(v);
      await finish(v);
    } catch (e) {
      LocalDataAdmission.failure = 'Order edit recovery: $e';
      rethrow;
    }
    return PosCommandOutcome.success(
      code: 'order_edited',
      data: OrderEditProjection.build(
        after,
        effectiveServiceFeePercent: feeRate * 100,
      ),
    );
  });
  static Future<void> recoverPending({bool underExclusive = false}) async {
    Future<void> recover() async {
      try {
        final all = records();
        for (final v in all)
          validateAudit(v, DatabaseCore.auditLogBox!.get(v['requestId']));
        final pending = all.where((v) => v['phase'] != 'completed').toList();
        if (pending.length > 1)
          throw const FormatException('Multiple pending edits');
        for (final v in pending) await finish(v);
        if (LocalDataAdmission.failure?.startsWith('Order edit recovery:') ==
            true)
          LocalDataAdmission.failure = null;
      } catch (e) {
        LocalDataAdmission.failure = 'Order edit recovery: $e';
        rethrow;
      }
    }

    if (underExclusive) return recover();
    await LocalDataAdmission.exclusive(
      recover,
      recovery: true,
      operation: 'managerOrderEdit',
    );
  }

  static int validateBackup(Map<String, Map<dynamic, dynamic>> stores) {
    var pending = 0;
    for (final e in stores['meta']!.entries) {
      if (!isRecord(e.key, e.value)) continue;
      final v = decode(e.key as String, e.value);
      validateAudit(v, stores['auditLog']![v['requestId']]);
      if (v['phase'] == 'completed') continue;
      if (++pending > 1 ||
          BusinessDayRepository.dateKey(
                DateTime.parse(stores['settings']!['currentDate'] as String),
              ) !=
              v['request']['businessDate'])
        throw const FormatException('Edit backup recovery/date differs');
      validateCurrent(
        v,
        stores['orders']!.cast<dynamic, Order>(),
        stores['auditLog']!,
      );
    }
    for (final raw in stores['edge_command_journal']!.values) {
      if (raw is! Map ||
          raw['type'] != 'ORDER_EDIT' ||
          raw['status'] != 'succeeded')
        continue;
      final id = raw['commandId'];
      if (id is! String || stores['meta']![key(id)] == null)
        throw const FormatException(
          'Missing edit business receipt for transport result',
        );
      final v = decode(key(id), stores['meta']![key(id)]);
      if (v['phase'] != 'completed' ||
          raw['code'] != 'order_edited' ||
          !OrderTransferIntent.sameImage(
            resultProjection(v),
            raw['resultProjection'],
          ))
        throw const FormatException(
          'Edit transport result differs from durable receipt',
        );
    }
    return pending;
  }
}
