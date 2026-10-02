import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/close_day_journal_repository.dart';
import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/services/audit/audit_event_service.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'dart:developer' as developer;

import 'package:vynic/core/models/reservation_classification.dart';
import 'package:vynic/core/models/reservation_status.dart';

import '../database_core.dart';
import '../repositories/business_day_repository.dart';
import '../repositories/sales_repository.dart';
import '../repositories/table_repository.dart';

/// Closes the business day.
///
/// Multi-step flow (all-or-nothing from the operator's point of view):
/// guards (no active orders or live table locks) →
/// finalize reservations → remember the operated date → advance the business
/// date → reset the daily sales total → purge closed orders → free tables.
class CloseDayTransaction {
  CloseDayTransaction._();

  /// Moves every genuine booking dated on or before [currentDateString] to
  /// its terminal state: `completed` when it was seated, `no-show` otherwise.
  ///
  /// Each transition is written to the Reservation timeline as the system's
  /// own action — nobody pressed a button on a specific booking, Close Day
  /// did — so the actor is `system` and the source `SYSTEM`. Bookings already
  /// final only lose a dangling Order link and write nothing.
  static Future<({int completed, int noShow})> finalizeReservationsForDay(
    String currentDateString,
  ) => UpdateReadiness.track(
    'finalizeReservationsForDay',
    () => _updateTrackedFinalizeReservationsForDay(currentDateString),
  );

  static Future<({int completed, int noShow})>
  _updateTrackedFinalizeReservationsForDay(String currentDateString) async {
    var completedReservations = 0;
    var noShowReservations = 0;
    for (final reservation in DatabaseCore.reservationBox!.values) {
      if (!ReservationClassification.isRealAdvanceBooking(reservation)) {
        continue;
      }
      final resDateString = reservation.reservationDate.toIso8601String().split(
        'T',
      )[0];
      if (resDateString.compareTo(currentDateString) > 0) {
        continue; // future booking — leave untouched
      }
      if (reservation.statusEnum.isFinal) {
        if (reservation.linkedOrderId != null) {
          // Its order is deleted below — do not keep a dangling id.
          reservation.linkedOrderId = null;
          await reservation.save();
        }
        continue;
      }
      final wasActivated =
          reservation.linkedOrderId != null ||
          reservation.statusEnum == ReservationStatus.inProgress;
      final previousStatus = reservation.status;
      final linkedOrderId = reservation.linkedOrderId;
      reservation.statusEnum = wasActivated
          ? ReservationStatus.completed
          : ReservationStatus.noShow;
      reservation.linkedOrderId = null;
      await reservation.save();
      await ReservationAudit.log(
        action: wasActivated
            ? ReservationAuditAction.complete
            : ReservationAuditAction.noShow,
        reservation: reservation,
        actorId: 'system',
        source: AuditSource.system,
        previousStatus: previousStatus,
        newStatus: reservation.status,
        reason: 'Close Day',
        extra: {if (linkedOrderId != null) 'orderId': linkedOrderId},
      );
      if (wasActivated) {
        completedReservations++;
      } else {
        noShowReservations++;
      }
    }
    return (completed: completedReservations, noShow: noShowReservations);
  }

  /// A stale UI confirmation must never close a subsequently opened day.
  /// Without an explicit date, capture it before waiting for admission.
  static String? lastFailureReason;

  static Future<bool> run({
    String actorId = 'unknown',
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? expectedBusinessDate,
  }) {
    final expected =
        expectedBusinessDate ??
        BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate());
    return _runAdmitted(expected, actorId, actorName, source);
  }

  static Future<bool> _runAdmitted(
    String expected,
    String actorId,
    String? actorName,
    AuditSource source,
  ) async {
    lastFailureReason = null;
    try {
      return await LocalDataAdmission.exclusive(
        () => UpdateReadiness.track('closeDay', () async {
          try {
            final prior = CloseDayJournalRepository.read();
            if (prior?.pending ?? false) {
              // An explicit retry may resume only the day originally requested.
              if (expected != prior!.businessDate) {
                throw StateError(
                  'A previous Close Day requires startup recovery',
                );
              }
              await _finish(prior);
              return true;
            }
            final current = BusinessDayRepository.getCurrentDate();
            final currentKey = BusinessDayRepository.dateKey(current);
            if (currentKey != expected) {
              lastFailureReason =
                  'სამუშაო დღე უკვე შეიცვალა; განაახლეთ მონაცემები';
              return false;
            }
            final active = DatabaseCore.orderBox!.values
                .where(
                  (order) =>
                      order.status != 'closed' &&
                      order.status != 'cancelled' &&
                      BusinessDayRepository.dateKey(order.createdAt) ==
                          currentKey,
                )
                .toList();
            if (active.isNotEmpty) {
              lastFailureReason = 'დახურეთ ყველა აქტიური შეკვეთა';
              await GlobalAudit.closeDayBlocked(
                businessDate: currentKey,
                blockedBy: 'ACTIVE_ORDERS',
                blockers: [
                  for (final order in active)
                    {
                      'orderId': order.orderId,
                      'tableNumbers': order.tableNumbers,
                      'floor': order.floor,
                      'status': order.status,
                      'createdBy': order.createdBy,
                    },
                ],
                actorId: actorId,
                actorName: actorName,
                source: source,
              );
              return false;
            }
            final diagnostics = TableRepository.getReservedTableDiagnostics();
            final reserved = diagnostics
                .where((table) => table['shouldRelease'] != true)
                .toList();
            if (reserved.isNotEmpty) {
              // Preserve the existing repair on blocked closes. It is idempotent
              // and performed while all business writers are excluded.
              await TableRepository.releaseStaleReservedTables();
              lastFailureReason =
                  'გაათავისუფლეთ აქტიური დარეზერვებული მაგიდები';
              await GlobalAudit.closeDayBlocked(
                businessDate: currentKey,
                blockedBy: 'RESERVED_TABLES',
                blockers: reserved,
                actorId: actorId,
                actorName: actorName,
                source: source,
              );
              return false;
            }
            // Adapter defaults may mint Order UUIDs while reading old records.
            // Persist them before the intent can reference those identities.
            for (final key in DatabaseCore.orderBox!.keys.toList()) {
              final order = DatabaseCore.orderBox!.get(key)!;
              if (order.status == 'closed') {
                await DatabaseCore.orderBox!.put(key, order);
                await DatabaseCore.orderBox!.flush();
              }
            }
            final intent = _capture(
              current,
              actorId,
              actorName,
              source,
              diagnostics,
            );
            await CloseDayJournalRepository.write(intent);
            await _finish(intent);
            return true;
          } catch (error) {
            _latchRecoveryFailure(error);
            rethrow;
          }
        }),
        operation: 'closeDay',
      );
    } catch (error, stack) {
      // Once an intent may exist, the process remains closed to writers. A
      // storage/validation failure cannot be reported as an ordinary blocker.
      lastFailureReason = LocalDataAdmission.failure != null
          ? 'დღის დახურვა შეწყდა; გადატვირთეთ პროგრამა აღდგენისათვის'
          : 'დღის დახურვა ვერ შესრულდა; სცადეთ ხელახლა';
      if (UpdateReadiness.enabled && LocalDataAdmission.failure != null) {
        UpdateReadiness.failure = LocalDataAdmission.failure;
      }
      developer.log('Close Day failed', error: error, stackTrace: stack);
      return false;
    }
  }

  static void _latchRecoveryFailure(Object error) {
    if (!(DatabaseCore.metaBox?.containsKey(CloseDayJournalRepository.key) ??
        false))
      return;
    try {
      if (CloseDayJournalRepository.read()?.pending ?? false) {
        LocalDataAdmission.failure = 'Close Day recovery required: $error';
      }
    } catch (_) {
      LocalDataAdmission.failure =
          'Close Day journal requires recovery: $error';
    }
  }

  static CloseDayIntent _capture(
    DateTime current,
    String actorId,
    String? actorName,
    AuditSource source,
    List<Map<String, dynamic>> diagnostics,
  ) {
    const uuid = Uuid();
    final id = uuid.v4();
    final started = DateTime.now();
    final day = BusinessDayRepository.dateKey(current);
    final next = BusinessDayRepository.nextCalendarDate(current);
    final actor = actorId.trim().isEmpty ? 'unknown' : actorId.trim();
    final name = actorName?.trim().isNotEmpty == true
        ? actorName!.trim()
        : actor;
    final reservations = <Map<String, dynamic>>[];
    var completed = 0;
    var noShow = 0;
    for (final key in DatabaseCore.reservationBox!.keys) {
      final reservation = DatabaseCore.reservationBox!.get(key)!;
      if (!ReservationClassification.isRealAdvanceBooking(reservation) ||
          BusinessDayRepository.dateKey(
                reservation.reservationDate,
              ).compareTo(day) >
              0)
        continue;
      final previous = reservation.status;
      final linked = reservation.linkedOrderId;
      final finalStatus = reservation.statusEnum.isFinal;
      if (finalStatus && linked == null) continue;
      final activated =
          linked != null ||
          reservation.statusEnum == ReservationStatus.inProgress;
      final status = finalStatus
          ? previous
          : activated
          ? ReservationStatus.completed.storageValue
          : ReservationStatus.noShow.storageValue;
      final audit = finalStatus
          ? null
          : AuditEventLog(
              id: uuid.v5(id, 'reservation:${reservation.id}'),
              action: activated
                  ? ReservationAuditAction.complete
                  : ReservationAuditAction.noShow,
              userId: 'system',
              entityType: GlobalAuditEntity.reservation,
              entityId: reservation.id,
              createdAt: started,
              deviceType: _deviceType,
              data: {
                ...(ReservationAudit.snapshot(reservation)
                  ..remove('linkedOrderId')),
                'status': status,
                'previousStatus': previous,
                'newStatus': status,
                'source': AuditSource.system.wireValue,
                'actorId': 'system',
                'actorName': 'system',
                'businessDate': day,
                'reason': 'Close Day',
                'transitionId': id,
                if (linked != null) 'orderId': linked,
              },
            ).toMap();
      if (!finalStatus) activated ? completed++ : noShow++;
      reservations.add({
        'key': key,
        'reservationId': reservation.id,
        'previousStatus': previous,
        'nextStatus': status,
        'linkedOrderId': linked,
        'audit': audit,
      });
    }
    final orders = [
      for (final key in DatabaseCore.orderBox!.keys)
        if (DatabaseCore.orderBox!.get(key)!.status == 'closed')
          {
            'key': key,
            'orderId': DatabaseCore.orderBox!.get(key)!.orderId,
            'orderUuid': DatabaseCore.orderBox!.get(key)!.orderUuid,
          },
    ];
    final tables = [
      for (final key in DatabaseCore.tableBox!.keys)
        if (DatabaseCore.tableBox!.get(key)!.isReserved ||
            DatabaseCore.tableBox!.get(key)!.reservationId != null)
          {
            'key': key,
            'tableNumber': DatabaseCore.tableBox!.get(key)!.tableNumber,
            'floor': DatabaseCore.tableBox!.get(key)!.floor,
            'activeOrderId': DatabaseCore.tableBox!.get(key)!.activeOrderId,
            'reservationId': DatabaseCore.tableBox!.get(key)!.reservationId,
            'stale': diagnostics.any(
              (row) =>
                  row['shouldRelease'] == true &&
                  row['tableNumber'] ==
                      DatabaseCore.tableBox!.get(key)!.tableNumber &&
                  row['floor'] == DatabaseCore.tableBox!.get(key)!.floor,
            ),
          },
    ];
    return CloseDayIntent({
      'version': 1,
      'transitionId': id,
      'phase': CloseDayPhase.intent.name,
      'fromDate': current.toIso8601String(),
      'toDate': next.toIso8601String(),
      'actorId': actor,
      'actorName': name,
      'source': source.wireValue,
      'startedAt': started.toIso8601String(),
      'reservations': reservations,
      'orders': orders,
      'tables': tables,
      'audit': AuditEventLog(
        id: uuid.v5(id, 'completed'),
        action: GlobalAuditAction.closeDayCompleted,
        userId: actor,
        entityType: GlobalAuditEntity.closeDay,
        entityId: day,
        createdAt: started,
        deviceType: _deviceType,
        data: {
          'actorId': actor, 'actorName': name, 'source': source.wireValue,
          // Existing completion events are filed under the newly opened day.
          'businessDate': BusinessDayRepository.dateKey(next),
          'businessDateClosed': day,
          'nextBusinessDate': BusinessDayRepository.dateKey(next),
          'reservationsCompleted': completed, 'reservationsNoShow': noShow,
          'ordersArchived': orders.length,
          'tablesFreed': tables.where((row) => row['stale'] != true).length,
          'transitionId': id,
        },
      ).toMap(),
    });
  }

  static String get _deviceType => kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.windows
      ? 'windows'
      : 'mobile';

  /// Startup calls this before Menu recovery, migrations, defaults or workers.
  /// A failed replay throws and holds admission until a successful restart.
  static Future<void> recoverPending() async {
    final raw = DatabaseCore.metaBox?.get(CloseDayJournalRepository.key);
    if (raw == null) return; // Legacy Hive has no transition to invent.
    LocalDataAdmission.failure = 'Close Day requires startup recovery';
    try {
      await LocalDataAdmission.exclusive(
        recoverUnderAdmission,
        recovery: true,
        operation: 'closeDay',
      );
      LocalDataAdmission.failure = null;
      if (UpdateReadiness.failure?.startsWith('Close Day') ?? false)
        UpdateReadiness.failure = null;
      lastFailureReason = null;
    } catch (error) {
      LocalDataAdmission.failure = 'Close Day recovery failed: $error';
      rethrow;
    }
  }

  /// Also used by restore, which already owns exclusive local admission.
  static Future<void> recoverUnderAdmission() async {
    final intent = CloseDayJournalRepository.read();
    if (intent?.pending ?? false) await _finish(intent!);
  }

  static Future<void> _finish(CloseDayIntent intent) async {
    final current = BusinessDayRepository.getCurrentDate().toIso8601String();
    if (current != intent.fromDate && current != intent.toDate) {
      throw StateError('Business date disagrees with pending Close Day');
    }
    // Never delete or free an entity that changed identity after the intent.
    for (final row in intent.rows('orders')) {
      final order = DatabaseCore.orderBox!.get(row['key']);
      if (order != null &&
          (order.status != 'closed' ||
              order.orderId != row['orderId'] ||
              order.orderUuid != row['orderUuid'])) {
        throw StateError('Order changed during pending Close Day');
      }
    }
    for (final row in intent.rows('tables')) {
      final table = DatabaseCore.tableBox!.get(row['key']);
      if (table == null ||
          table.tableNumber != row['tableNumber'] ||
          table.floor != row['floor'] ||
          table.activeOrderId != null &&
              table.activeOrderId != row['activeOrderId'] ||
          table.reservationId != null &&
              table.reservationId != row['reservationId']) {
        throw StateError('Table changed during pending Close Day');
      }
    }
    Future<void> phase(
      CloseDayPhase next,
      Future<void> Function() effects,
    ) async {
      if (intent.phase.index >= next.index) return;
      await effects();
      intent = intent.at(next);
      await CloseDayJournalRepository.write(intent);
    }

    Future<void> releaseTables(bool stale) async {
      for (final row
          in intent.rows('tables').where((row) => row['stale'] == stale)) {
        final table = DatabaseCore.tableBox!.get(row['key'])!;
        table.free();
        await DatabaseCore.tableBox!.put(row['key'], table);
        await DatabaseCore.tableBox!.flush();
      }
    }

    await phase(CloseDayPhase.staleTablesReleased, () => releaseTables(true));
    await phase(CloseDayPhase.reservationsFinalized, () async {
      for (final row in intent.rows('reservations')) {
        final reservation = DatabaseCore.reservationBox!.get(row['key']);
        if (reservation == null ||
            reservation.id != row['reservationId'] ||
            reservation.status != row['previousStatus'] &&
                reservation.status != row['nextStatus'] ||
            reservation.linkedOrderId != null &&
                reservation.linkedOrderId != row['linkedOrderId']) {
          throw StateError('Reservation changed during pending Close Day');
        }
        reservation.status = row['nextStatus'] as String;
        reservation.linkedOrderId = null;
        await DatabaseCore.reservationBox!.put(row['key'], reservation);
        await DatabaseCore.reservationBox!.flush();
        if (row['audit'] != null) {
          await AuditEventService.appendDurableOnce(
            AuditEventLog.fromMap(
              Map<String, dynamic>.from(row['audit'] as Map),
            ),
          );
        }
      }
    });
    await phase(CloseDayPhase.historyRemembered, () async {
      await BusinessDayRepository.rememberOperatedBusinessDate(
        DateTime.parse(intent.fromDate),
      );
      await DatabaseCore.settingsBox!.flush();
    });
    await phase(CloseDayPhase.dateAdvanced, () async {
      await DatabaseCore.settingsBox!.put('currentDate', intent.toDate);
      await DatabaseCore.settingsBox!.flush();
    });
    await phase(CloseDayPhase.totalReset, () async {
      await SalesRepository.resetDailySalesTotal();
      await DatabaseCore.settingsBox!.flush();
    });
    await phase(CloseDayPhase.ordersArchived, () async {
      for (final row in intent.rows('orders')) {
        await DatabaseCore.orderBox!.delete(row['key']);
        await DatabaseCore.orderBox!.flush();
      }
    });
    await phase(CloseDayPhase.tablesReleased, () => releaseTables(false));
    await phase(
      CloseDayPhase.audited,
      () => AuditEventService.appendDurableOnce(
        AuditEventLog.fromMap(
          Map<String, dynamic>.from(intent.data['audit'] as Map),
        ),
      ),
    );
    await phase(CloseDayPhase.completed, () async {});
  }
}
