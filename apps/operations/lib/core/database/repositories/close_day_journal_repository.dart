import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';

import '../database_core.dart';
import 'business_day_repository.dart';

enum CloseDayPhase {
  intent,
  staleTablesReleased,
  reservationsFinalized,
  historyRemembered,
  dateAdvanced,
  totalReset,
  ordersArchived,
  tablesReleased,
  audited,
  completed,
}

/// Additive primitive metadata, without a Hive adapter/schema change. The
/// immutable plan and phase receipt travel in complete format-2 backups.
class CloseDayIntent {
  CloseDayIntent(Map<String, dynamic> value) : data = Map.of(value);

  final Map<String, dynamic> data;
  String get id => data['transitionId'] as String;
  String get fromDate => data['fromDate'] as String;
  String get toDate => data['toDate'] as String;
  String get businessDate => fromDate.split('T')[0];
  CloseDayPhase get phase =>
      CloseDayPhase.values.byName(data['phase'] as String);
  bool get pending => phase != CloseDayPhase.completed;
  List<Map<String, dynamic>> rows(String field) => (data[field] as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  CloseDayIntent at(CloseDayPhase phase) =>
      CloseDayIntent({...data, 'phase': phase.name}..remove('sha256'));

  Map<String, dynamic> toMap() {
    final raw = Map<String, dynamic>.of(data)..remove('sha256');
    return {...raw, 'sha256': PosBackupFormat.digest(raw)};
  }

  factory CloseDayIntent.fromMap(Object? value) {
    if (value is! Map) throw const FormatException('Invalid Close Day journal');
    final raw = Map<String, dynamic>.from(value);
    final unsigned = Map<String, dynamic>.of(raw)..remove('sha256');
    if (raw['version'] != 1 ||
        raw['sha256'] != PosBackupFormat.digest(unsigned)) {
      throw const FormatException('Unsupported or damaged Close Day journal');
    }
    final id = raw['transitionId'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(id)) {
      throw const FormatException('Invalid Close Day transition identity');
    }
    final from = DateTime.parse(raw['fromDate'] as String);
    final to = DateTime.parse(raw['toDate'] as String);
    if (to != BusinessDayRepository.nextCalendarDate(from) ||
        raw['actorId'] is! String ||
        raw['actorName'] is! String ||
        raw['source'] is! String ||
        !AuditSource.values.any(
          (source) => source.wireValue == raw['source'],
        ) ||
        (raw['actorId'] as String).trim().isEmpty ||
        (raw['actorName'] as String).trim().isEmpty ||
        !CloseDayPhase.values.any((phase) => phase.name == raw['phase'])) {
      throw const FormatException('Invalid Close Day dates/phase/actor');
    }
    DateTime.parse(raw['startedAt'] as String);
    final identities = <String>{};
    for (final field in ['reservations', 'orders', 'tables']) {
      if (raw[field] is! List)
        throw FormatException('Missing Close Day $field');
      final keys = <Object>{};
      for (final value in raw[field] as List) {
        if (value is! Map ||
            !(value['key'] is String || value['key'] is int) ||
            !keys.add(value['key'] as Object)) {
          throw FormatException('Invalid Close Day $field target');
        }
        if (field == 'orders' &&
            (value['orderId'] is! int || value['orderUuid'] is! String)) {
          throw const FormatException('Invalid Close Day Order identity');
        }
        if (field == 'tables' &&
            (value['tableNumber'] is! String ||
                value['floor'] is! String ||
                value['stale'] is! bool ||
                value['activeOrderId'] != null &&
                    value['activeOrderId'] is! int ||
                value['reservationId'] != null &&
                    value['reservationId'] is! String)) {
          throw const FormatException('Invalid Close Day Table identity');
        }
        if (field == 'reservations') {
          if (value['reservationId'] is! String ||
              value['previousStatus'] is! String ||
              value['nextStatus'] is! String ||
              value['linkedOrderId'] != null &&
                  value['linkedOrderId'] is! int) {
            throw const FormatException(
              'Invalid Close Day Reservation identity',
            );
          }
          final audit = value['audit'];
          if (audit != null) {
            final event = _audit(audit, id, identities);
            if (![
                  ReservationAuditAction.complete,
                  ReservationAuditAction.noShow,
                ].contains(event.action) ||
                event.entityType != GlobalAuditEntity.reservation ||
                event.entityId != value['reservationId'] ||
                event.id !=
                    const Uuid().v5(
                      id,
                      'reservation:${value['reservationId']}',
                    ) ||
                event.userId != 'system' ||
                event.data['source'] != AuditSource.system.wireValue ||
                event.data['businessDate'] !=
                    raw['fromDate'].toString().split('T')[0] ||
                event.data['status'] != value['nextStatus'] ||
                event.action == ReservationAuditAction.complete &&
                    value['nextStatus'] != 'completed' ||
                event.action == ReservationAuditAction.noShow &&
                    value['nextStatus'] != 'no-show' ||
                event.data['previousStatus'] != value['previousStatus'] ||
                event.data['newStatus'] != value['nextStatus']) {
              throw const FormatException(
                'Invalid Close Day Reservation audit',
              );
            }
          }
        }
      }
    }
    final completion = _audit(raw['audit'], id, identities);
    if (completion.action != GlobalAuditAction.closeDayCompleted ||
        completion.id != const Uuid().v5(id, 'completed') ||
        completion.userId != raw['actorId'] ||
        completion.data['actorId'] != raw['actorId'] ||
        completion.data['actorName'] != raw['actorName'] ||
        completion.data['source'] != raw['source'] ||
        completion.entityType != GlobalAuditEntity.closeDay ||
        completion.entityId != raw['fromDate'].toString().split('T')[0] ||
        completion.data['businessDateClosed'] != completion.entityId ||
        completion.data['nextBusinessDate'] !=
            raw['toDate'].toString().split('T')[0]) {
      throw const FormatException('Invalid Close Day completion audit');
    }
    final reservations = (raw['reservations'] as List).cast<Map>();
    if (completion.data['ordersArchived'] != (raw['orders'] as List).length ||
        completion.data['tablesFreed'] !=
            (raw['tables'] as List)
                .cast<Map>()
                .where((row) => row['stale'] == false)
                .length ||
        completion.data['reservationsCompleted'] !=
            reservations
                .where(
                  (row) =>
                      row['audit'] != null && row['nextStatus'] == 'completed',
                )
                .length ||
        completion.data['reservationsNoShow'] !=
            reservations
                .where(
                  (row) =>
                      row['audit'] != null && row['nextStatus'] == 'no-show',
                )
                .length) {
      throw const FormatException(
        'Close Day audit counts disagree with its plan',
      );
    }
    return CloseDayIntent(raw);
  }

  static AuditEventLog _audit(Object? raw, String id, Set<String> identities) {
    if (raw is! Map) throw const FormatException('Invalid Close Day audit');
    final event = AuditEventLog.fromMap(Map<String, dynamic>.from(raw));
    if (!identities.add(event.id) || event.data['transitionId'] != id) {
      throw const FormatException('Invalid Close Day audit identity');
    }
    return event;
  }
}

abstract final class CloseDayJournalRepository {
  static const key = 'closeDayTransitionV1';

  static CloseDayIntent? read() {
    final raw = DatabaseCore.metaBox!.get(key);
    return raw == null ? null : CloseDayIntent.fromMap(raw);
  }

  static Future<void> write(CloseDayIntent intent) async {
    final raw = intent.toMap();
    CloseDayIntent.fromMap(raw); // Never persist a plan startup cannot replay.
    await DatabaseCore.metaBox!.put(key, raw);
    await DatabaseCore.metaBox!.flush();
  }
}
