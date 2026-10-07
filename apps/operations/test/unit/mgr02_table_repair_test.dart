import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/table_repair_repository.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import '../support/pos03_fixture.dart';

const mgr02RequestId = 'c2000000-0000-4000-8000-000000000001';
const mgr02ActorId = 'c2000000-0000-4000-8000-000000000002';

Future<Map<String, dynamic>> seedMgr02() async {
  await DatabaseCore.orderBox!.clear();
  await DatabaseCore.reservationBox!.clear();
  await DatabaseCore.auditLogBox!.clear();
  final layout = RestaurantTableLayouts.current.withCanonicalTableIds(
    generateId: (_) => const Uuid().v4(),
  );
  await DatabaseCore.settingsBox!.put(
    'activeTableLayoutJson',
    jsonEncode(layout.toJson()),
  );
  final table = DatabaseCore.tableBox!.toMap().entries.singleWhere(
    (e) => e.value.floor == 'first' && e.value.tableNumber == '7',
  );
  await DatabaseCore.tableBox!.put(
    table.key,
    TableModel(
      tableNumber: '7',
      floor: 'first',
      isReserved: true,
      activeOrderId: 999,
    ),
  );
  return {
    'tableId': layout.tableForLegacy(floor: 'first', tableNumber: '7')!.id,
    'tableNumber': '7',
    'floor': 'first',
    'expectedIsReserved': true,
    'expectedActiveOrderId': 999,
    'actorStaffId': mgr02ActorId,
    'actorUsername': 'Synthetic manager',
    '_mutationRequestId': mgr02RequestId,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Pos03Fixture fixture;
  late Map<String, dynamic> payload;
  TableModel table() => DatabaseCore.tableBox!.values.singleWhere(
    (t) => t.floor == 'first' && t.tableNumber == '7',
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr02-unit-');
    fixture = Pos03Fixture();
    await fixture.open(dir.path);
    await fixture.seed();
    payload = await seedMgr02();
    fixture.trace.clear();
  });
  tearDown(() async {
    fixture.fault = null;
    await fixture.close();
    LocalDataAdmission.failure = null;
    await dir.delete(recursive: true);
  });
  test(
    'ghost repair has one durable table effect, audit and retained result',
    () async {
      expect((await TableRepairRepository.repair(payload)).ok, isTrue);
      expect(table().activeOrderId, isNull);
      expect(table().isReserved, isFalse);
      expect(DatabaseCore.orderBox!.values, isEmpty);
      expect(DatabaseCore.auditLogBox!.length, 1);
      final sealed = DatabaseCore.metaBox!.get(
        TableRepairRepository.key(mgr02RequestId),
      );
      expect(
        TableRepairRepository.decode(
          TableRepairRepository.key(mgr02RequestId),
          sealed,
        )['phase'],
        'completed',
      );
      expect(OrderTableMutationRepository.records(), isEmpty);
      await fixture.close();
      await fixture.open(dir.path);
      await TableRepairRepository.recoverPending();
      expect(DatabaseCore.auditLogBox!.length, 1);
    },
  );
  test(
    'completed replay never releases later occupancy or duplicates audit',
    () async {
      await TableRepairRepository.repair(payload);
      final k = DatabaseCore.tableBox!
          .toMap()
          .entries
          .singleWhere((e) => e.value.tableNumber == '7')
          .key;
      await DatabaseCore.tableBox!.put(
        k,
        TableModel(
          tableNumber: '7',
          floor: 'first',
          isReserved: true,
          activeOrderId: 222,
        ),
      );
      expect((await TableRepairRepository.repair(payload)).ok, isTrue);
      expect(table().activeOrderId, 222);
      expect(DatabaseCore.auditLogBox!.length, 1);
    },
  );
  test(
    'same command with another payload conflicts without mutation',
    () async {
      await TableRepairRepository.repair(payload);
      expect(
        (await TableRepairRepository.repair({
          ...payload,
          'actorUsername': 'Changed',
        })).code,
        'request_conflict',
      );
    },
  );
  test(
    'stale observed table and wrong canonical UUID fail before intent',
    () async {
      expect(
        (await TableRepairRepository.repair({
          ...payload,
          'expectedActiveOrderId': 123,
        })).code,
        'stale_table',
      );
      expect(
        (await TableRepairRepository.repair({
          ...payload,
          'tableId': const Uuid().v4(),
        })).code,
        'canonical_table_identity_required',
      );
      expect(
        DatabaseCore.metaBox!.get(TableRepairRepository.key(mgr02RequestId)),
        isNull,
      );
      expect(table().activeOrderId, 999);
    },
  );
  test(
    'missing and duplicate local physical rows are explicit failures',
    () async {
      expect(
        (await TableRepairRepository.repair({
          ...payload,
          'tableNumber': 'missing',
        })).code,
        'table_not_found',
      );
      await DatabaseCore.tableBox!.add(
        TableModel(tableNumber: '7', floor: 'first'),
      );
      expect(
        (await TableRepairRepository.repair(payload)).code,
        'repair_required',
      );
    },
  );
  for (final status in ['confirmed', 'pending', 'unknown_future_state']) {
    for (final direct in [true, false]) {
      test(
        '$status ${direct ? 'direct' : 'indirect alias'} Order cannot be repaired',
        () async {
          final order = fixture.originalSource!;
          order.orderId = direct ? 999 : 333;
          order.tableNumbers = [direct ? '8' : 'Table 7'];
          order.status = status;
          await DatabaseCore.orderBox!.put('synthetic-owner', order);
          await expectLater(
            TableRepairRepository.repair(payload),
            throwsA(isA<OrderMutationConflict>()),
          );
          expect(table().activeOrderId, 999);
          expect(DatabaseCore.auditLogBox!.isEmpty, isTrue);
        },
      );
    }
  }
  for (final status in ['pending', 'confirmed', 'new_unknown_status']) {
    test(
      'nonfinal $status Reservation owns table despite old date and absent backlink',
      () async {
        await DatabaseCore.reservationBox!.add(
          Reservation(
            id: 'reservation',
            customerName: 'Synthetic',
            customerPhone: 'none',
            tableNumbers: [7],
            reservationDate: DateTime(2000),
            reservationTime: '12:00',
            numberOfGuests: 1,
            createdAt: DateTime(2000),
            createdBy: 'test',
            status: status,
          ),
        );
        await expectLater(
          TableRepairRepository.repair(payload),
          throwsA(isA<OrderMutationConflict>()),
        );
        expect(table().isReserved, isTrue);
      },
    );
  }
  for (final point in [
    'meta.put:transfer:intent:after',
    'tables.flush:after',
    'audit.flush:after',
    'meta.put:transfer:completed:after',
  ]) {
    test(
      'interruption at $point reopens and finishes exactly one repair',
      () async {
        var hit = false;
        fixture.fault = (p, _) async {
          if (!hit && p == point) {
            hit = true;
            throw StateError('Synthetic interruption');
          }
        };
        await expectLater(
          TableRepairRepository.repair(payload),
          throwsStateError,
        );
        expect(hit, isTrue);
        fixture.fault = null;
        await fixture.close();
        await fixture.open(dir.path);
        await TableRepairRepository.recoverPending();
        expect(table().isReserved, isFalse);
        expect(DatabaseCore.auditLogBox!.length, 1);
        expect((await TableRepairRepository.repair(payload)).ok, isTrue);
      },
    );
  }
  test(
    'completed repair backup and fresh restore retain receipt and audit',
    () async {
      await TableRepairRepository.repair(payload);
      final file = await BackupRepository.createDataBackup(
        targetFilePath: '${dir.path}/backup.json',
        password: 'Synthetic password only',
      );
      await fixture.close();
      final fresh = await Directory('${dir.path}/fresh').create();
      await fixture.open(fresh.path);
      await BackupRepository.restoreDataBackupFromFile(
        file,
        password: 'Synthetic password only',
        backupBeforeRestore: false,
      );
      await TableRepairRepository.recoverPending();
      expect((await TableRepairRepository.repair(payload)).ok, isTrue);
      expect(DatabaseCore.auditLogBox!.length, greaterThanOrEqualTo(1));
      expect(table().activeOrderId, isNull);
    },
  );
  Future<void> haltAt(String point) async {
    fixture.fault = (p, _) async {
      if (p == point) throw StateError('Synthetic interruption');
    };
    await expectLater(TableRepairRepository.repair(payload), throwsStateError);
    fixture.fault = null;
    LocalDataAdmission.failure = null;
  }

  Future<Map<String, dynamic>> snapshot() async {
    final file = await BackupRepository.createDataBackup(
      targetFilePath: '${dir.path}/pending.json',
      password: 'Synthetic password only',
    );
    return PosBackupFormat.decode(
      await file.readAsString(),
      password: 'Synthetic password only',
    );
  }

  String reseal(Map<String, dynamic> envelope) {
    envelope.remove('integrity');
    PosBackupFormat.seal(envelope);
    return jsonEncode(envelope);
  }

  test(
    'public pending restore finishes repair before returning without manual recovery',
    () async {
      await haltAt('meta.put:transfer:intent:after');
      final envelope = await snapshot();
      await fixture.close();
      final fresh = await Directory('${dir.path}/pending-fresh').create();
      await fixture.open(fresh.path);
      await BackupRepository.restoreDataBackupFromJson(
        reseal(envelope),
        backupBeforeRestore: false,
      );
      expect(table().isReserved, isFalse);
      final raw = DatabaseCore.metaBox!.get(
        TableRepairRepository.key(mgr02RequestId),
      );
      expect(raw['phase'], 'completed');
      expect(DatabaseCore.auditLogBox!.get(mgr02RequestId), isNotNull);
    },
  );
  for (final hostile in [
    'table_phase_before_image',
    'missing_audit',
    'wrong_canonical_identity',
  ]) {
    test(
      'hostile pending backup $hostile rejects before destination replacement',
      () async {
        await haltAt(
          hostile == 'missing_audit'
              ? 'meta.put:transfer:audit:after'
              : 'meta.put:transfer:intent:after',
        );
        final envelope = await snapshot();
        final stores = envelope['stores'] as Map;
        final row = (stores['meta'] as List).cast<Map>().singleWhere(
          (r) => r['key'] == TableRepairRepository.key(mgr02RequestId),
        );
        final record = Map<String, dynamic>.from(
          PosBackupFormat.decodeValue(row['value']) as Map,
        );
        if (hostile == 'table_phase_before_image') {
          record.remove('digest');
          record['phase'] = 'table';
          record['digest'] = PosBackupFormat.digest(record);
          row['value'] = PosBackupFormat.encodeValue(record);
        } else if (hostile == 'missing_audit') {
          (stores['auditLog'] as List).removeWhere(
            (r) => r['key'] == mgr02RequestId,
          );
        } else {
          final setting = (stores['settings'] as List).cast<Map>().singleWhere(
            (r) => r['key'] == 'activeTableLayoutJson',
          );
          final layout =
              jsonDecode(
                    PosBackupFormat.decodeValue(setting['value']) as String,
                  )
                  as Map;
          final data = jsonEncode(
            layout,
          ).replaceAll(payload['tableId'] as String, const Uuid().v4());
          setting['value'] = PosBackupFormat.encodeValue(data);
        }
        await DatabaseCore.settingsBox!.put('destination_sentinel', 'retain');
        await expectLater(
          BackupRepository.restoreDataBackupFromJson(
            reseal(envelope),
            backupBeforeRestore: false,
          ),
          throwsA(isA<FormatException>()),
        );
        expect(DatabaseCore.settingsBox!.get('destination_sentinel'), 'retain');
      },
    );
  }
  test('missing completed audit blocks retained replay and startup', () async {
    await TableRepairRepository.repair(payload);
    await DatabaseCore.auditLogBox!.delete(mgr02RequestId);
    await expectLater(
      TableRepairRepository.repair(payload),
      throwsFormatException,
    );
    await expectLater(
      TableRepairRepository.recoverPending(),
      throwsFormatException,
    );
  });
  test('pending repair cannot cross business date', () async {
    await haltAt('meta.put:transfer:intent:after');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '2026-10-02T00:00:00.000',
    );
    await expectLater(
      TableRepairRepository.recoverPending(),
      throwsFormatException,
    );
    expect(table().activeOrderId, 999);
  });
  test('tampered goal with recomputed digest is rejected', () async {
    await TableRepairRepository.repair(payload);
    final k = TableRepairRepository.key(mgr02RequestId);
    final raw =
        jsonDecode(jsonEncode(DatabaseCore.metaBox!.get(k)))
            as Map<String, dynamic>;
    raw.remove('digest');
    (raw['after'] as Map)['edgeRevision'] = 999;
    raw['digest'] = PosBackupFormat.digest(raw);
    // Digest is calculated over body without digest, even for hostile input.
    final body = {...raw}..remove('digest');
    raw['digest'] = PosBackupFormat.digest(body);
    expect(() => TableRepairRepository.decode(k, raw), throwsFormatException);
  });
}
