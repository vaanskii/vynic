import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/services/sync/sync_events.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';
import 'business_day_repository.dart';
import 'order_table_mutation_repository.dart';
import 'order_transfer_journal_repository.dart';
import 'settings_repository.dart';
import 'table_repository.dart';

/// Repair belongs to the existing ownership journal namespace. Older readers
/// reject its new kind before startup/defaults or backup replacement, including
/// completed receipts. Rolling back requires an explicitly compatible reader.
abstract final class TableRepairRepository {
  static const kind = 'tableRepair';
  static const prefix = 'orderTableMutationV1:';
  static String key(String id) => '$prefix${sha256.convert(utf8.encode(id))}';
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool isRecord(Object? storedKey, Object? value) {
    if (storedKey is! String ||
        !storedKey.startsWith(prefix) ||
        value is! Map ||
        value['kind'] != kind)
      return false;
    decode(storedKey, value);
    return true;
  }

  static Map<String, dynamic> request(Map<String, dynamic> payload) {
    final value = <String, dynamic>{
      for (final name in [
        'tableId',
        'tableNumber',
        'floor',
        'expectedIsReserved',
        'expectedActiveOrderId',
        'actorStaffId',
        'actorUsername',
      ])
        name: payload[name],
    };
    for (final name in ['tableId', 'actorStaffId']) {
      if (value[name] is! String || !_uuid.hasMatch(value[name] as String))
        throw const FormatException('Invalid repair identity');
    }
    for (final name in ['tableNumber', 'floor', 'actorUsername']) {
      if (value[name] is! String ||
          (value[name] as String).trim().isEmpty ||
          (value[name] as String).length > 128)
        throw const FormatException('Invalid repair reference/actor');
    }
    if (value['expectedIsReserved'] is! bool ||
        value['expectedActiveOrderId'] != null &&
            (value['expectedActiveOrderId'] is! int ||
                value['expectedActiveOrderId'] < 1))
      throw const FormatException('Invalid observed repair state');
    return value;
  }

  static Map<String, dynamic> decode(String storedKey, Object? raw) {
    if (raw is! Map) throw const FormatException('Missing repair intent');
    final v = OrderTransferIntent.cloneMap(raw);
    final digest = v.remove('digest');
    if (digest != PosBackupFormat.digest(v) ||
        v['kind'] != kind ||
        v['version'] != 1 ||
        v['requestId'] is! String ||
        !_uuid.hasMatch(v['requestId']) ||
        storedKey != key(v['requestId']) ||
        v['request'] is! Map ||
        v['fingerprint'] != PosBackupFormat.digest(v['request']) ||
        !['intent', 'table', 'audit', 'completed'].contains(v['phase']) ||
        v['before'] is! Map ||
        v['after'] is! Map ||
        v['audit'] is! Map ||
        v['tableKey'] is! int && v['tableKey'] is! String ||
        v['businessDate'] is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v['businessDate']))
      throw const FormatException(
        'Invalid repair intent identity/digest/phase',
      );
    final r = request(Map<String, dynamic>.from(v['request']));
    if (!OrderTransferIntent.sameImage(r, v['request']))
      throw const FormatException('Unexpected repair request fields');
    final before = TableModel.fromJson(Map<String, dynamic>.from(v['before']));
    final after = TableModel.fromJson(Map<String, dynamic>.from(v['after']));
    if (!OrderTransferIntent.sameImage(
          v['before'],
          OrderTableMutationRepository.tableImage(before),
        ) ||
        !OrderTransferIntent.sameImage(
          v['after'],
          OrderTableMutationRepository.tableImage(after),
        ) ||
        before.floor != r['floor'] ||
        before.tableNumber != r['tableNumber'] ||
        before.isReserved != r['expectedIsReserved'] ||
        before.activeOrderId != r['expectedActiveOrderId'])
      throw const FormatException('Repair request/table identity differs');
    final goal = TableModel.fromJson(Map<String, dynamic>.from(v['before']))
      ..free();
    if (!OrderTransferIntent.sameImage(
      v['after'],
      OrderTableMutationRepository.tableImage(goal),
    ))
      throw const FormatException('Repair changed unrelated table fields');
    final event = AuditEventLog.fromMap(Map<String, dynamic>.from(v['audit']));
    final expected = audit(
      v['requestId'],
      r,
      v['before'],
      v['after'],
      event.createdAt,
    );
    if (!OrderTransferIntent.sameImage(expected.toMap(), v['audit']))
      throw const FormatException('Repair audit differs from intent');
    return v;
  }

  static AuditEventLog audit(
    String id,
    Map<String, dynamic> r,
    Object before,
    Object after,
    DateTime time,
  ) => AuditEventLog(
    id: id,
    action: 'TABLE_REPAIRED',
    userId: r['actorStaffId'],
    entityType: 'TABLE',
    entityId: r['tableId'],
    deviceType: 'pos',
    createdAt: time,
    data: {
      'requestId': id,
      'actorUsername': r['actorUsername'],
      'reason': 'manager_ghost_table_repair',
      'floor': r['floor'],
      'tableNumber': r['tableNumber'],
      'before': before,
      'after': after,
    },
  );

  static void guard(
    Map<String, dynamic> r,
    TableModel table,
    Iterable<Order> orders,
    Iterable<Reservation> reservations,
  ) {
    for (final order in orders) {
      if (order.statusEnum.isTerminal) continue;
      if (order.orderId == table.activeOrderId ||
          order.floor == table.floor &&
              order.tableNumbers.any(
                (n) =>
                    n == table.tableNumber ||
                    TableRepository.normalizeTableIdentifier(n, table.floor) ==
                        table.tableNumber,
              ))
        throw OrderMutationConflict(
          'table_busy',
          'A live Order owns this table',
        );
    }
    for (final reservation in reservations) {
      if (reservation.statusEnum.isFinal) continue;
      final refs = reservation.tableRefs;
      if (refs != null && refs.any((s) => TableRef.tryDecode(s) == null))
        throw OrderMutationConflict(
          'repair_required',
          'Invalid live Reservation identity',
        );
      if (reservation.id == table.reservationId ||
          !reservation.isTakeAway &&
              ReservationTableAvailability.tableRefsOf(reservation).any(
                (ref) =>
                    ref.floor == table.floor &&
                    ref.tableNumber == table.tableNumber,
              ))
        throw OrderMutationConflict(
          'table_busy',
          'A live Reservation owns this table',
        );
    }
  }

  static void validateCurrent(
    Map<String, dynamic> v,
    Map<dynamic, TableModel> tables,
    Iterable<Order> orders,
    Iterable<Reservation> reservations,
  ) {
    final r = Map<String, dynamic>.from(v['request']);
    final rows = tables.entries
        .where(
          (e) =>
              e.value.floor == r['floor'] &&
              e.value.tableNumber == r['tableNumber'],
        )
        .toList();
    if (rows.length != 1 || rows.single.key != v['tableKey'])
      throw const FormatException('Repair table missing/ambiguous');
    final current = OrderTableMutationRepository.tableImage(rows.single.value);
    if (!OrderTransferIntent.sameImage(current, v['after']) &&
        (v['phase'] != 'intent' ||
            !OrderTransferIntent.sameImage(current, v['before'])))
      throw const FormatException('Repair table changed during recovery');
    guard(r, rows.single.value, orders, reservations);
  }

  static void validateAudit(Map<String, dynamic> v, Object? stored) {
    final required = v['phase'] == 'audit' || v['phase'] == 'completed';
    if (stored == null) {
      if (required)
        throw const FormatException('Repair completion audit is missing');
      return;
    }
    final actual = AuditEventLog.fromMap(
      Map<String, dynamic>.from(stored as Map),
    ).toMap()..remove('synced');
    final expected = Map<String, dynamic>.from(v['audit'])..remove('synced');
    if (!OrderTransferIntent.sameImage(actual, expected))
      throw const FormatException('Repair persisted audit differs');
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
    if (BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate()) !=
        v['businessDate'])
      throw const FormatException('Repair recovery business date changed');
    final tables = DatabaseCore.tableBox!.toMap();
    validateCurrent(
      v,
      tables,
      DatabaseCore.orderBox!.values,
      DatabaseCore.reservationBox!.values,
    );
    final layout = SettingsRepository.getActiveTableLayout();
    final r = v['request'] as Map;
    final definitions = layout?.tables
        .where(
          (t) =>
              t.legacyFloor == r['floor'] &&
              t.legacyTableNumber == r['tableNumber'],
        )
        .toList();
    if (definitions == null ||
        definitions.length != 1 ||
        definitions.single.id != r['tableId'])
      throw OrderMutationConflict(
        'canonical_table_identity_required',
        'Physical table identity changed',
      );
    if (v['phase'] == 'intent') {
      await DatabaseCore.tableBox!.put(
        v['tableKey'],
        TableModel.fromJson(Map<String, dynamic>.from(v['after'])),
      );
      await DatabaseCore.tableBox!.flush();
      v['phase'] = 'table';
      await write(v);
    }
    if (v['phase'] == 'table') {
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
        type: SyncEventType.tables,
        action: 'freed',
        payload: {'tableNumber': r['tableNumber'], 'floor': r['floor']},
      ),
    );
  }

  static Future<PosCommandOutcome> repair(
    Map<String, dynamic> payload,
  ) => UpdateReadiness.mutate('repairTable', () async {
    final r = request(payload);
    final id = payload['_mutationRequestId'];
    if (id is! String || !_uuid.hasMatch(id))
      return const PosCommandOutcome.invalid('invalid_repair_request');
    final stored = DatabaseCore.metaBox!.get(key(id));
    if (stored != null) {
      final v = decode(key(id), stored);
      if (v['fingerprint'] != PosBackupFormat.digest(r))
        return const PosCommandOutcome.conflicting('request_conflict');
      await finish(v);
      return const PosCommandOutcome.success(code: 'table_repaired');
    }
    final rows = DatabaseCore.tableBox!
        .toMap()
        .entries
        .where(
          (e) =>
              e.value.floor == r['floor'] &&
              e.value.tableNumber == r['tableNumber'],
        )
        .toList();
    if (rows.isEmpty) return const PosCommandOutcome.missing('table_not_found');
    if (rows.length != 1)
      return const PosCommandOutcome.conflicting('repair_required');
    final table = rows.single.value;
    guard(
      r,
      table,
      DatabaseCore.orderBox!.values,
      DatabaseCore.reservationBox!.values,
    );
    if (table.isReserved != r['expectedIsReserved'] ||
        table.activeOrderId != r['expectedActiveOrderId'])
      return const PosCommandOutcome.conflicting('stale_table');
    final before = OrderTableMutationRepository.tableImage(table);
    final after = OrderTableMutationRepository.tableImage(
      TableModel.fromJson(before)..free(),
    );
    final v = <String, dynamic>{
      'version': 1,
      'kind': kind,
      'requestId': id,
      'request': r,
      'fingerprint': PosBackupFormat.digest(r),
      'businessDate': BusinessDayRepository.dateKey(
        BusinessDayRepository.getCurrentDate(),
      ),
      'tableKey': rows.single.key,
      'before': before,
      'after': after,
      'audit': audit(id, r, before, after, DateTime.now()).toMap(),
      'phase': 'intent',
    };
    // Identity must be checked before the first durable intent as well.
    final layout = SettingsRepository.getActiveTableLayout();
    final defs = layout?.tables
        .where(
          (t) =>
              t.legacyFloor == r['floor'] &&
              t.legacyTableNumber == r['tableNumber'],
        )
        .toList();
    if (defs == null || defs.length != 1 || defs.single.id != r['tableId'])
      return const PosCommandOutcome.conflicting(
        'canonical_table_identity_required',
      );
    try {
      await write(v);
      await finish(v);
    } catch (error) {
      LocalDataAdmission.failure = 'Table repair recovery: $error';
      rethrow;
    }
    return const PosCommandOutcome.success(code: 'table_repaired');
  });

  static Future<void> recoverPending({bool underExclusive = false}) async {
    Future<void> recover() async {
      try {
        final records = DatabaseCore.metaBox!
            .toMap()
            .entries
            .where((e) => isRecord(e.key, e.value))
            .map((e) => decode(e.key as String, e.value))
            .toList();
        for (final v in records)
          validateAudit(v, DatabaseCore.auditLogBox!.get(v['requestId']));
        final pending = records
            .where((v) => v['phase'] != 'completed')
            .toList();
        if (pending.length > 1)
          throw StateError('Multiple pending table repairs');
        for (final v in pending) await finish(v);
        if (LocalDataAdmission.failure?.startsWith('Table repair recovery:') ==
            true)
          LocalDataAdmission.failure = null;
      } catch (error) {
        LocalDataAdmission.failure = 'Table repair recovery: $error';
        rethrow;
      }
    }

    if (underExclusive) return recover();
    await LocalDataAdmission.exclusive(
      recover,
      recovery: true,
      operation: 'repairTable',
    );
  }

  static int validateBackup(Map<String, Map<dynamic, dynamic>> stores) {
    var pending = 0;
    for (final e in stores['meta']!.entries) {
      if (!isRecord(e.key, e.value)) continue;
      final v = decode(e.key as String, e.value);
      validateAudit(v, stores['auditLog']![v['requestId']]);
      if (v['phase'] == 'completed') continue;
      final rawLayout = stores['settings']!['activeTableLayoutJson'];
      final layoutData = rawLayout is String
          ? jsonDecode(rawLayout)
          : rawLayout;
      if (layoutData is! Map)
        throw const FormatException('Repair backup layout is missing');
      final layout = RestaurantTableLayout.fromJson(
        Map<String, dynamic>.from(layoutData),
      );
      final r = v['request'] as Map;
      final definitions = layout.tables
          .where(
            (t) =>
                t.legacyFloor == r['floor'] &&
                t.legacyTableNumber == r['tableNumber'],
          )
          .toList();
      if (definitions.length != 1 || definitions.single.id != r['tableId'])
        throw const FormatException('Repair backup canonical identity differs');
      if (++pending > 1)
        throw const FormatException('Multiple pending table repairs');
      validateCurrent(
        v,
        stores['tables']!.cast<dynamic, TableModel>(),
        stores['orders']!.values.cast<Order>(),
        stores['reservations']!.values.cast<Reservation>(),
      );
      if (BusinessDayRepository.dateKey(
            DateTime.parse(stores['settings']!['currentDate'] as String),
          ) !=
          v['businessDate'])
        throw const FormatException('Repair backup date mismatch');
    }
    return pending;
  }
}
