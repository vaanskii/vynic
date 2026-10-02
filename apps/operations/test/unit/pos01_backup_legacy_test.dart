import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/close_day_journal_repository.dart';
import 'package:vynic/core/database/transactions/close_day_transaction.dart';
import 'package:vynic/core/models/order.dart';
import '../support/pos01_fixture.dart';

/// Writes actual historical Hive bytes: the stable UUID field29 is absent.
/// Production generated adapters are untouched; current OrderAdapter reads it.
class Pos01LegacyOrderAdapter extends OrderAdapter {
  @override
  void write(BinaryWriter writer, Order order) {
    final fields = <int, dynamic>{
      0: order.orderId,
      1: order.tableNumbers,
      2: order.floor,
      3: order.items,
      4: order.totalAmount,
      5: order.createdAt,
      6: order.createdBy,
      7: order.status,
      8: order.updatedAt,
      9: order.includeServiceFee,
    };
    writer.writeByte(fields.length);
    for (final entry in fields.entries) {
      writer.writeByte(entry.key);
      writer.write(entry.value);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Pos01Fixture fixture;
  late HttpOverrides? previous;
  setUp(() async {
    previous = HttpOverrides.current;
    root = await Directory.systemTemp.createTemp('vynic-pos01-compat-');
    fixture = Pos01Fixture();
    await fixture.open(root.path);
    await fixture.seed();
  });
  tearDown(() async {
    await fixture.close();
    HttpOverrides.global = previous;
    Hive.registerAdapter(OrderAdapter(), override: true);
    await root.delete(recursive: true);
  });
  Future<String> backup() async => (await BackupRepository.createDataBackup(
    targetFilePath: '${root.path}/portable.json',
  )).readAsString();
  Future<void> fresh(String payload) async {
    await fixture.close();
    final destination = '${root.path}/fresh';
    await Directory(destination).create();
    await fixture.open(destination);
    await BackupRepository.restoreDataBackupFromJson(
      payload,
      backupBeforeRestore: false,
    );
  }

  test(
    'completed journal survives format2 fresh restore with same transition/audits',
    () async {
      expect(await CloseDayTransaction.run(actorId: 'operator'), true);
      final id = CloseDayJournalRepository.read()!.id;
      final payload = await backup();
      await fresh(payload);
      fixture.verify(transitionId: id);
      final before = DatabaseCore.auditLogBox!.length;
      await BackupRepository.restoreDataBackupFromJson(
        payload,
        backupBeforeRestore: false,
      );
      expect(DatabaseCore.auditLogBox!.length, before);
      fixture.verify(transitionId: id);
      expect(DatabaseCore.dbVersion, 9);
    },
  );

  test(
    'a complete snapshot containing a pending intent replays before restore admission',
    () async {
      final envelope = await PosBackupFormat.decode(await backup());
      Map? pending;
      fixture.fault = (point, _) async {
        if (point == 'meta.put:closeDayTransitionV1:intent:after') {
          pending = Map.of(
            DatabaseCore.metaBox!.get(CloseDayJournalRepository.key) as Map,
          );
          throw const FileSystemException('synthetic intent interruption');
        }
      };
      expect(await CloseDayTransaction.run(actorId: 'operator'), false);
      expect(LocalDataAdmission.failure, isNotNull);
      // Construct the portable image of this exact stable pre-effect boundary.
      // Runtime admission remains blocked; no guard is disabled to export it.
      (envelope['stores']['meta'] as List).add({
        'key': CloseDayJournalRepository.key,
        'value': PosBackupFormat.encodeValue(pending),
      });
      envelope.remove('integrity');
      PosBackupFormat.seal(envelope);
      PosBackupFormat.validate(envelope);
      await fresh(jsonEncode(envelope));
      fixture.verify(transitionId: pending!['transitionId'] as String);
      expect(LocalDataAdmission.blocked, false);
    },
  );

  test(
    'journal-less format2 backup remains readable and does not invent a day close',
    () async {
      final payload = await backup();
      await fresh(payload);
      expect(CloseDayJournalRepository.read(), isNull);
      expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 70.0);
      expect(
        DatabaseCore.settingsBox!.get('currentDate'),
        startsWith('2026-10-01'),
      );
    },
  );

  test(
    'corrupted or unknown journal is rejected before backup replacement',
    () async {
      final envelope = await PosBackupFormat.decode(await backup());
      (envelope['stores']['meta'] as List).add({
        'key': CloseDayJournalRepository.key,
        'value': PosBackupFormat.encodeValue({
          'version': 99,
          'phase': 'completed',
        }),
      });
      envelope.remove('integrity');
      PosBackupFormat.seal(envelope);
      PosBackupFormat.validate(envelope);
      final before = DatabaseCore.orderBox!.keys.toList();
      await expectLater(
        BackupRepository.restoreDataBackupFromJson(
          jsonEncode(envelope),
          backupBeforeRestore: false,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'journal validation reason',
            contains('Close Day journal'),
          ),
        ),
      );
      expect(DatabaseCore.orderBox!.keys.toList(), before);
      expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 70.0);
    },
  );

  test(
    'damaged startup journal stops before Menu recovery/migrations and business admission',
    () async {
      await DatabaseCore.metaBox!.put(CloseDayJournalRepository.key, {
        'version': 99,
      });
      await DatabaseCore.metaBox!.flush();
      await fixture.close();
      await expectLater(fixture.open(root.path), throwsFormatException);
      expect(LocalDataAdmission.failure, contains('Close Day recovery failed'));
      await expectLater(
        LocalDataAdmission.track(() async {}),
        throwsStateError,
      );
      expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 70.0);
    },
  );

  test(
    'true legacy missing UUID bytes stabilize before intent and recover after reopen',
    () async {
      await fixture.close();
      Hive.registerAdapter(Pos01LegacyOrderAdapter(), override: true);
      Hive.init(root.path);
      final old = await Hive.openBox<Order>(DatabaseCore.orderBoxName);
      await old.put(
        'legacy-closed',
        Order(
          orderId: 12,
          tableNumbers: ['12'],
          floor: 'first',
          items: [],
          totalAmount: 0,
          createdAt: DateTime.parse('2026-10-01'),
          createdBy: 'synthetic-legacy',
          status: 'closed',
          includeServiceFee: false,
        ),
      );
      await old.flush();
      await Hive.close();
      Hive.registerAdapter(OrderAdapter(), override: true);
      await fixture.open(root.path);
      final ephemeral = DatabaseCore.orderBox!.get('legacy-closed')!.orderUuid;
      await fixture.close();
      await fixture.open(root.path);
      // Proves the source bytes really lack field29, rather than a mocked model.
      expect(
        DatabaseCore.orderBox!.get('legacy-closed')!.orderUuid,
        isNot(ephemeral),
      );
      fixture.fault = (point, _) async {
        if (point == 'settings.put:currentDate:after')
          throw const FileSystemException('synthetic date crash');
      };
      expect(await CloseDayTransaction.run(actorId: 'operator'), false);
      final intent = CloseDayJournalRepository.read()!;
      final legacyId = intent
          .rows('orders')
          .singleWhere((row) => row['key'] == 'legacy-closed')['orderUuid'];
      expect(DatabaseCore.orderBox!.get('legacy-closed')!.orderUuid, legacyId);
      await fixture.close();
      await fixture.open(root.path);
      expect(CloseDayJournalRepository.read()!.id, intent.id);
      expect(CloseDayJournalRepository.read()!.phase, CloseDayPhase.completed);
      expect(DatabaseCore.orderBox!.get('legacy-closed'), isNull);
      expect(
        DatabaseCore.settingsBox!.get('currentDate'),
        startsWith('2026-10-02'),
      );
      expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 0.0);
    },
  );
}
