import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/hive_migration_service.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import 'package:vynic/core/models/order.dart';
import '../support/pos05_fixture.dart';
import 'pos03_backup_legacy_test.dart'
    show Pos03LegacyOrderAdapter, Pos03LegacyItemAdapter;

/// Real legacy bytes omit field 8, the line UUID, without adapter edits.
class LegacyReservationLineWriter extends OrderItemAdapter {
  @override
  void write(BinaryWriter w, OrderItem i) {
    final fields = [
      i.itemKey,
      i.itemName,
      i.unitPrice,
      i.quantity,
      i.total,
      i.comment,
      i.menuItemId,
      i.variantId,
    ];
    w.writeByte(fields.length);
    for (var n = 0; n < fields.length; n++) {
      w.writeByte(n);
      w.write(fields[n]);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Pos05Fixture fixture;
  late HttpOverrides? prior;
  setUp(() async {
    prior = HttpOverrides.current;
    root = await Directory.systemTemp.createTemp('vynic-pos05-compat-');
    fixture = Pos05Fixture();
    await fixture.open(root.path);
  });
  tearDown(() async {
    await fixture.close();
    HttpOverrides.global = prior;
    Hive.registerAdapter(OrderItemAdapter(), override: true);
    Hive.registerAdapter(OrderAdapter(), override: true);
    await root.delete(recursive: true);
  });
  Future<String> backup() async => (await BackupRepository.createDataBackup(
    targetFilePath: '${root.path}/portable.json',
  )).readAsString();
  Future<void> restoreFresh(String payload) async {
    await fixture.close();
    final target = '${root.path}/fresh';
    await Directory(target).create();
    await fixture.open(target);
    await BackupRepository.restoreDataBackupFromJson(
      payload,
      backupBeforeRestore: false,
    );
  }

  String seal(Map<String, dynamic> envelope) {
    envelope.remove('integrity');
    PosBackupFormat.seal(envelope);
    PosBackupFormat.validate(envelope);
    return jsonEncode(envelope);
  }

  for (final scenario in [
    'create',
    'takeaway',
    'package',
    'activation',
    'move',
    'cancel',
  ]) {
    test(
      '$scenario completed format2 receipt preserves exact identity and audit on restore/retry',
      () async {
        await fixture.prepare(scenario);
        await fixture.action();
        fixture.check();
        final payload = await backup();
        await restoreFresh(payload);
        fixture.check();
        final before = fixture.persisted();
        await fixture.action();
        expect(fixture.persisted(), before);
        expect(DatabaseCore.dbVersion, 9);
      },
    );
    test(
      '$scenario pending format2 receipt replays before restore admission',
      () async {
        await fixture.prepare(scenario);
        final envelope = await PosBackupFormat.decode(await backup());
        Map<String, dynamic>? intent;
        fixture.fault = (point, _) async {
          if (point == 'meta.put:intent:after') {
            intent = OrderTransferIntent.cloneMap(
              DatabaseCore.metaBox!.get(
                    OrderTableMutationRepository.key(fixture.id),
                  )
                  as Map,
            );
            throw const FileSystemException('synthetic interruption');
          }
        };
        await expectLater(fixture.action(), throwsA(anything));
        expect(LocalDataAdmission.failure, isNotNull);
        expect(intent, isNotNull);
        (envelope['stores']['meta'] as List).add({
          'key': OrderTableMutationRepository.key(fixture.id),
          'value': PosBackupFormat.encodeValue(intent),
        });
        await restoreFresh(seal(envelope));
        fixture.check();
        expect(LocalDataAdmission.failure, isNull);
      },
    );
  }
  test(
    'completed create receipt cannot overwrite later edits after restore',
    () async {
      await fixture.prepare('create');
      final original = await fixture.action();
      final changed = OrderRepository.getOrder(original!.orderId)!;
      changed.items.single.quantity = 8;
      changed.items.single.total = 20.03;
      await OrderRepository.updateOrder(changed);
      await restoreFresh(await backup());
      await fixture.action();
      expect(
        OrderRepository.getOrder(original.orderId)!.items.single.quantity,
        8,
      );
      expect(
        OrderRepository.getOrder(original.orderId)!.items.single.total,
        20.03,
      );
    },
  );
  for (final corruption in [
    'version',
    'sales',
    'counter',
    'report',
    'reservation',
    'cancelTender',
    'cancelReport',
  ]) {
    test(
      'digest-valid $corruption plan is rejected before any store replacement',
      () async {
        final scenario = corruption.startsWith('cancel')
            ? 'cancel'
            : corruption == 'reservation'
            ? 'activation'
            : 'create';
        await fixture.prepare(scenario);
        await fixture.action();
        final envelope = await PosBackupFormat.decode(await backup());
        final entry = (envelope['stores']['meta'] as List).singleWhere(
          (e) => e['key'] == OrderTableMutationRepository.key(fixture.id),
        );
        final raw = OrderTransferIntent.cloneMap(
          PosBackupFormat.decodeValue(entry['value']) as Map,
        )..remove('digest');
        final effects = (raw['effects'] as List).cast<Map<String, dynamic>>();
        switch (corruption) {
          case 'version':
            raw['version'] = 99;
          case 'sales':
            effects.add({
              'store': 'sales',
              'key': 'unrelated',
              'before': null,
              'after': {'orderId': 999},
            });
          case 'counter':
            effects.singleWhere((e) => e['store'] == 'settings')['key'] =
                'currentDate';
          case 'report':
            effects.singleWhere(
              (e) => e['store'] == 'auditReport',
            )['after']['openedById'] = 'someone-else';
          case 'reservation':
            effects.singleWhere(
              (e) => e['store'] == 'reservation',
            )['after']['linkedOrderId'] = 999;
          case 'cancelTender':
            effects.singleWhere(
              (e) => e['store'] == 'sales',
            )['after']['paymentBreakdown'] = {
              'cash': 50,
            };
          case 'cancelReport':
            effects.singleWhere(
              (e) => e['store'] == 'auditReport',
            )['after']['openedById'] = 'someone-else';
        }
        raw['digest'] = PosBackupFormat.digest(raw);
        entry['value'] = PosBackupFormat.encodeValue(raw);
        final before = fixture.persisted();
        await expectLater(
          BackupRepository.restoreDataBackupFromJson(
            seal(envelope),
            backupBeforeRestore: false,
          ),
          throwsA(isA<FormatException>()),
        );
        expect(fixture.persisted(), before);
        expect(LocalDataAdmission.failure, isNull);
      },
    );
  }
  test(
    'true legacy Reservation line IDs bootstrap durably at schema9 before activation',
    () async {
      await fixture.prepare('activation');
      await DatabaseCore.metaBox!.delete('reservationLineIdentitiesV1');
      Hive.registerAdapter(LegacyReservationLineWriter(), override: true);
      final booking = DatabaseCore.reservationBox!.get('booking')!;
      await DatabaseCore.reservationBox!.put('booking', booking);
      await DatabaseCore.reservationBox!.flush();
      await fixture.close();
      Hive.registerAdapter(OrderItemAdapter(), override: true);
      await fixture.open(root.path);
      final first = DatabaseCore.reservationBox!
          .get('booking')!
          .preOrderItems!
          .single
          .lineUuid;
      expect(first, isNotEmpty);
      expect(DatabaseCore.metaBox!.get('reservationLineIdentitiesV1'), true);
      await fixture.close();
      await fixture.open(root.path);
      expect(
        DatabaseCore.reservationBox!
            .get('booking')!
            .preOrderItems!
            .single
            .lineUuid,
        first,
      );
      await fixture.action();
      fixture.check();
      expect(OrderRepository.getOrder(1)!.items.single.lineUuid, first);
    },
  );
  test(
    'identity bootstrap interruption flushes accepted fields and retry preserves IDs',
    () async {
      await fixture.prepare('activation');
      await DatabaseCore.metaBox!.delete('reservationLineIdentitiesV1');
      final id = DatabaseCore.reservationBox!
          .get('booking')!
          .preOrderItems!
          .single
          .lineUuid;
      fixture.trace.clear();
      fixture.fault = (p, _) async {
        if (p == 'meta.put:reservationLineIdentitiesV1:before')
          throw const FileSystemException('identity receipt fault');
      };
      await expectLater(
        HiveMigrationService.persistReservationLineIdentities(
          DatabaseCore.metaBox!,
          DatabaseCore.reservationBox!,
        ),
        throwsA(isA<FileSystemException>()),
      );
      await fixture.close();
      await fixture.open(root.path);
      expect(
        DatabaseCore.reservationBox!
            .get('booking')!
            .preOrderItems!
            .single
            .lineUuid,
        id,
      );
      expect(DatabaseCore.metaBox!.get('reservationLineIdentitiesV1'), true);
    },
  );
  test(
    'true schema8 Order bytes migrate stable identities before first ownership intent and interrupted move',
    () async {
      await fixture.prepare('move');
      Hive.registerAdapter(Pos03LegacyOrderAdapter(), override: true);
      Hive.registerAdapter(Pos03LegacyItemAdapter(), override: true);
      for (final entry in DatabaseCore.orderBox!.toMap().entries)
        await DatabaseCore.orderBox!.put(entry.key, entry.value);
      await DatabaseCore.orderBox!.flush();
      await DatabaseCore.metaBox!.put(HiveMigrationService.dbVersionKey, 8);
      await DatabaseCore.metaBox!.flush();
      await fixture.close();
      Hive.registerAdapter(OrderAdapter(), override: true);
      Hive.registerAdapter(OrderItemAdapter(), override: true);
      await fixture.open(root.path);
      expect(DatabaseCore.dbVersion, 9);
      final source = OrderRepository.getOrder(1)!;
      final uuid = source.orderUuid;
      final line = source.items.single.lineUuid;
      expect(uuid, isNotEmpty);
      expect(line, isNotEmpty);
      fixture.original = OrderTableMutationRepository.image(source);
      fixture.fault = (point, _) async {
        if (point == 'orders.put:source:before')
          throw const FileSystemException('first ownership row interruption');
      };
      await expectLater(
        fixture.action(),
        throwsA(isA<OrderMutationConflict>()),
      );
      await fixture.close();
      await fixture.open(root.path);
      fixture.check();
      expect(OrderRepository.getOrder(1)!.orderUuid, uuid);
      expect(OrderRepository.getOrder(1)!.items.single.lineUuid, line);
      final before = fixture.persisted();
      await fixture.action();
      expect(fixture.persisted(), before);
    },
  );
  test(
    'malformed pending startup journal refuses all writers preserving business images',
    () async {
      await fixture.prepare('create');
      final before = fixture.persisted();
      await DatabaseCore.metaBox!.put(
        OrderTableMutationRepository.key('corrupt'),
        {'version': 99},
      );
      await DatabaseCore.metaBox!.flush();
      await fixture.close();
      await expectLater(
        fixture.open(root.path),
        throwsA(isA<FormatException>()),
      );
      expect(LocalDataAdmission.failure, contains('Order/table recovery'));
      await expectLater(
        LocalDataAdmission.mutate(() async {}),
        throwsStateError,
      );
      expect(DatabaseCore.orderBox!.isEmpty, true);
      expect(before, contains('historical'));
    },
  );
}
