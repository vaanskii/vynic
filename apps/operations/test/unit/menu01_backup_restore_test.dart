import 'dart:typed_data';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import '../support/menu01_fixture.dart';
import 'menu02_durability_test.dart' show FaultBox;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String source;
  late String destination;
  late HttpOverrides? previous;
  Future<File> backup({String? password}) => BackupRepository.createDataBackup(
    targetFilePath:
        '${root.path}/backup-${DateTime.now().microsecondsSinceEpoch}.json',
    password: password,
  );
  Future<void> fresh(File file, {String? password}) async {
    await closeMenu01();
    await openMenu01(destination);
    await BackupRepository.restoreDataBackupFromFile(
      file,
      backupBeforeRestore: false,
      password: password,
    );
    await closeMenu01();
    await openMenu01(destination);
  }

  setUp(() async {
    previous = HttpOverrides.current;
    HttpOverrides.global = Menu01NoHttp();
    root = await Directory.systemTemp.createTemp('vynic-menu01-unit-');
    source = '${root.path}/source';
    destination = '${root.path}/fresh';
    await Directory(source).create();
    await Directory(destination).create();
    await openMenu01(source);
    await seedMenu01();
  });
  tearDown(() async {
    await closeMenu01();
    LocalDataAdmission.failure = null;
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = null;
    HttpOverrides.global = previous;
    await root.delete(recursive: true);
  });
  test(
    'A/B/C/E/F/G stable/pending/conflict/closure/outbound/acknowledged edit survive fresh restore',
    () async {
      final ids = MenuLocalStore.forBox(
        DatabaseCore.menuBox!,
      ).journal.all().map((e) => e.mutationId).toList();
      final file = await backup();
      final raw = await PosBackupFormat.decode(await file.readAsString());
      PosBackupFormat.validate(raw);
      expect(raw['manifest'], hasLength(17));
      expect(
        (raw['settingsAll'] as Map).containsKey('posIngestConnectionKey'),
        false,
      );
      await fresh(file);
      final result = await verifyMenu01Recovery();
      expect(result['menuPrice'], 12);
      expect(result['conflictPrice'], 22);
      expect(result['menuMutationIds'], ids);
      expect(result['capturedOrderPrice'], 7);
      expect(result['salePrice'], 7);
      expect(result['closurePhase'], 'completed');
      expect(result['recoveryActions'], isEmpty);
      expect(result['hasCredential'], false);
      expect(result['uncertainCommand'], 'interrupted');
      expect(result['pendingSales'], 1);
      expect(DatabaseCore.settingsBox!.get('posIngestConnectionKey'), isNull);
      expect(DatabaseCore.settingsBox!.get('developerTerminalId'), isNull);
      expect(DatabaseCore.settingsBox!.get('deviceRuntimeConfig'), isNull);
    },
  );
  test(
    'repeated restore does not rewind recovered work or duplicate rows/IDs',
    () async {
      final file = await backup();
      await fresh(file);
      await verifyMenu01Recovery();
      final before = DatabaseCore.salesBox!.toMap();
      final generation = MenuLocalStore.forBox(
        DatabaseCore.menuBox!,
      ).generation;
      await BackupRepository.restoreDataBackupFromFile(
        file,
        backupBeforeRestore: false,
      );
      expect(DatabaseCore.salesBox!.toMap(), before);
      expect(
        MenuLocalStore.forBox(DatabaseCore.menuBox!).generation,
        generation,
      );
      expect((await verifyMenu01Recovery())['recoveryActions'], isEmpty);
    },
  );
  test(
    'D backup waits for active Menu WAL and preserves successful edit',
    () async {
      final original = DatabaseCore.menuBox!;
      final box = FaultBox<MenuCategoryDB>(original);
      DatabaseCore.menuBox = box;
      final local = MenuLocalStore.attach(
        menuBox: box,
        stateBox: DatabaseCore.menuCanonicalBox!,
        journalBox: DatabaseCore.menuJournalBox!,
        venueId: () => menu01Venue,
      );
      final reached = Completer<void>();
      final release = Completer<void>();
      box.fault = (point) async {
        if (point == 'clear:after') {
          reached.complete();
          await release.future;
        }
      };
      final edit = MenuRepository.updateItemInCategory(
        categoryIndex: 0,
        itemIndex: 0,
        nameEn: 'Item',
        nameKa: 'Item',
        price: 13,
      );
      await reached.future;
      expect(local.stateBox.containsKey(MenuLocalStore.commitKey), true);
      var finished = false;
      final taking = backup().then((file) {
        finished = true;
        return file;
      });
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      box.fault = null;
      release.complete();
      expect(await edit, true);
      final file = await taking;
      await fresh(file);
      expect(DatabaseCore.menuBox!.values.first.items!.first.price, 13);
      expect(
        MenuLocalStore.forBox(
          DatabaseCore.menuBox!,
        ).journal.all().where((e) => e.sendable),
        hasLength(2),
      );
    },
  );
  test(
    'snapshot barrier blocks new writes and drains prior multi-box operation',
    () async {
      final reached = Completer<void>();
      final release = Completer<void>();
      final prior = LocalDataAdmission.track(() async {
        reached.complete();
        await release.future;
        await DatabaseCore.settingsBox!.put('finishedBeforeSnapshot', true);
      });
      await reached.future;
      final taking = backup();
      var laterFinished = false;
      final later = LocalDataAdmission.track(() async {
        laterFinished = true;
        await DatabaseCore.settingsBox!.put('afterSnapshot', true);
      });
      release.complete();
      await prior;
      final file = await taking;
      await later;
      final payload = await PosBackupFormat.decode(await file.readAsString());
      expect(payload['settingsAll']['finishedBeforeSnapshot'], true);
      expect(payload['settingsAll'].containsKey('afterSnapshot'), false);
      expect(laterFinished, true);
    },
  );
  test('busy barrier fails explicitly and resumes admission', () async {
    final release = Completer<void>();
    final active = LocalDataAdmission.track(() => release.future);
    await expectLater(
      LocalDataAdmission.exclusive(() async {}, drainTimeout: Duration.zero),
      throwsStateError,
    );
    release.complete();
    await active;
    expect(LocalDataAdmission.blocked, false);
    await backup();
  });
  for (final damage in [
    'truncate',
    'invalid-json',
    'encoding',
    'checksum',
    'future-format',
    'missing-store',
    'menu-version',
    'nested-menu-version',
    'wrong-venue',
    'bad-row',
    'missing-captured-price',
  ]) {
    test('rejects $damage before changing any good local store', () async {
      final file = await backup();
      final payload = await PosBackupFormat.decode(await file.readAsString());
      String text;
      switch (damage) {
        case 'truncate':
          text = (await file.readAsString()).substring(0, 20);
          break;
        case 'invalid-json':
          text = 'not json';
          break;
        case 'encoding':
          text = '\uFFFD';
          break;
        default:
          payload.remove('integrity');
          if (damage == 'checksum') {
            payload['createdAt'] = '2026-10-01T11:00:00Z';
            payload['integrity'] = {'algorithm': 'SHA-256', 'sha256': 'wrong'};
          } else {
            if (damage == 'future-format') payload['formatVersion'] = 999;
            if (damage == 'missing-store')
              payload['stores'].remove('closureJournal');
            if (damage == 'menu-version')
              payload['menuLocalProtocolVersion'] = 999;
            if (damage == 'nested-menu-version') {
              final row = (payload['stores']['menuCanonical'] as List)
                  .firstWhere((e) => e['key'] == 'localProtocolVersion');
              row['value'] = '999';
            }
            if (damage == 'wrong-venue') payload['venue']['id'] = 'venue-b';
            if (damage == 'bad-row')
              payload['stores']['orders'][0]['value'] = 'bad model';
            if (damage == 'missing-captured-price') {
              final row = payload['stores']['orders'][0];
              final model = PosBackupFormat.decodeValue(row['value']) as Map;
              (model['items'][0] as Map).remove('unitPrice');
              row['value'] = PosBackupFormat.encodeValue(model);
            }
            // Re-sign every remaining store to reach schema validation too.
            payload['manifest'] = [
              for (final name in (payload['stores'] as Map).keys)
                {
                  'store': name,
                  'rows': payload['stores'][name].length,
                  'sha256': PosBackupFormat.digest(payload['stores'][name]),
                },
            ];
            payload['integrity'] = {
              'algorithm': 'SHA-256',
              'sha256': PosBackupFormat.digest(payload),
            };
          }
          text = jsonEncode(payload);
      }
      final sales = DatabaseCore.salesBox!.toMap();
      final journal = DatabaseCore.menuJournalBox!.toMap();
      await expectLater(
        BackupRepository.restoreDataBackupFromJson(
          text,
          backupBeforeRestore: false,
        ),
        throwsA(anything),
      );
      expect(DatabaseCore.salesBox!.toMap(), sales);
      expect(DatabaseCore.menuJournalBox!.toMap(), journal);
      expect(
        File('$source/${BackupRepository.restoreMarkerName}').existsSync(),
        false,
      );
    });
  }
  test(
    'wrong enrollment fails closed; source credential is never cloned',
    () async {
      final file = await backup();
      await closeMenu01();
      await openMenu01(destination);
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential:
            'vynic-device-v1.30000000-0000-4000-8000-000000000001.${'b' * 40}',
        venueId: 'venue-b',
        venueName: 'B',
      );
      await expectLater(
        BackupRepository.restoreDataBackupFromFile(
          file,
          backupBeforeRestore: false,
        ),
        throwsStateError,
      );
      expect(DatabaseCore.salesBox!.isEmpty, true);
    },
  );
  test(
    'restored Venue binding blocks mismatched/unknown Device context',
    () async {
      final file = await backup();
      await fresh(file);
      final foreignCredential =
          'vynic-device-v1.30000000-0000-4000-8000-000000000001.${'b' * 40}';
      await expectLater(
        EdgeDeviceCredentialStore.saveEnrollment(
          rawCredential: foreignCredential,
          venueId: 'venue-b',
          venueName: 'B',
        ),
        throwsStateError,
      );
      expect(EdgeDeviceCredentialStore.hasCredential, false);
      // Older clients could persist this invalid pairing. Keep proving the
      // outbound guard as well as the new enrollment-time refusal.
      await File('$destination/edge_device.json').writeAsString(
        jsonEncode({
          'installationId': 'synthetic-restore-installation',
          'credential': foreignCredential,
          'venueId': 'venue-b',
        }),
      );
      EdgeDeviceCredentialStore.resetForTest();
      await EdgeDeviceCredentialStore.load();
      expect(() => EdgeDeviceCredentialStore.credential, throwsStateError);
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential:
            'vynic-device-v1.30000000-0000-4000-8000-000000000001.${'a' * 40}',
        venueId: menu01Venue,
        venueName: 'A',
      );
      expect(EdgeDeviceCredentialStore.credential, isNotNull);
    },
  );
  test(
    'encrypted portable backup protects PINs and authenticates password/content',
    () async {
      final file = await backup(password: menu01Password);
      final text = await file.readAsString();
      expect(text.contains('852963'), false);
      expect(text.contains('pinCode'), false);
      expect(text.contains('SYNTHETIC_CALLBACK_SECRET'), false);
      await expectLater(
        BackupRepository.restoreDataBackupFromJson(
          text,
          password: 'wrong-password-value',
          backupBeforeRestore: false,
        ),
        throwsFormatException,
      );
      final tampered = jsonDecode(text) as Map<String, dynamic>;
      final cipher = tampered['ciphertext'] as String;
      tampered['ciphertext'] =
          '${cipher.startsWith('A') ? 'B' : 'A'}${cipher.substring(1)}';
      await expectLater(
        BackupRepository.restoreDataBackupFromJson(
          jsonEncode(tampered),
          password: menu01Password,
          backupBeforeRestore: false,
        ),
        throwsFormatException,
      );
      await fresh(file, password: menu01Password);
      expect((await verifyMenu01Recovery())['staffPinPresent'], true);
    },
  );
  for (final store in [
    'meta',
    'users',
    'orders',
    'sales',
    'closureJournal',
    'menuCanonical',
    'menuMutationJournal',
    'settings',
  ]) {
    test(
      'interrupted $store restore freezes writes and startup replay completes',
      () async {
        final file = await backup();
        await closeMenu01();
        await openMenu01(destination);
        final boxMapping = <String, dynamic>{
          'meta': DatabaseCore.metaBox,
          'users': DatabaseCore.userBox,
          'orders': DatabaseCore.orderBox,
          'sales': DatabaseCore.salesBox,
          'closureJournal': DatabaseCore.closureJournalBox,
          'menuCanonical': DatabaseCore.menuCanonicalBox,
          'menuMutationJournal': DatabaseCore.menuJournalBox,
          'settings': DatabaseCore.settingsBox,
        };
        // Typed delegates are selected explicitly for Hive's generic checks.
        if (store == 'orders') {
          final b = FaultBox(DatabaseCore.orderBox!);
          b.fault = (p) async {
            if (p == 'clear:after')
              throw FileSystemException('synthetic disk failure');
          };
          DatabaseCore.orderBox = b;
        } else if (store == 'users') {
          final b = FaultBox(DatabaseCore.userBox!);
          b.fault = (p) async {
            if (p == 'clear:after')
              throw FileSystemException('synthetic disk failure');
          };
          DatabaseCore.userBox = b;
        } else if (store == 'menuCanonical' || store == 'menuMutationJournal') {
          final b = FaultBox<String>(boxMapping[store]);
          b.fault = (p) async {
            if (p == 'clear:after')
              throw FileSystemException('synthetic disk failure');
          };
          if (store == 'menuCanonical')
            DatabaseCore.menuCanonicalBox = b;
          else
            DatabaseCore.menuJournalBox = b;
        } else {
          final b = FaultBox<dynamic>(boxMapping[store]);
          b.fault = (p) async {
            if (p == 'clear:after')
              throw FileSystemException('synthetic disk failure');
          };
          switch (store) {
            case 'meta':
              DatabaseCore.metaBox = b;
            case 'sales':
              DatabaseCore.salesBox = b;
            case 'closureJournal':
              DatabaseCore.closureJournalBox = b;
            case 'settings':
              DatabaseCore.settingsBox = b;
          }
        }
        await expectLater(
          BackupRepository.restoreDataBackupFromFile(
            file,
            backupBeforeRestore: false,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          File(
            '$destination/${BackupRepository.restoreMarkerName}',
          ).existsSync(),
          true,
        );
        await expectLater(
          LocalDataAdmission.track(() async {}),
          throwsStateError,
        );
        await closeMenu01();
        await openMenu01(destination);
        expect(
          File(
            '$destination/${BackupRepository.restoreMarkerName}',
          ).existsSync(),
          false,
        );
        expect((await verifyMenu01Recovery())['closurePhase'], 'completed');
      },
    );
  }
  test(
    'legacy import requires disclosure and cannot invent missing intent',
    () async {
      final file = await backup();
      final raw = await PosBackupFormat.decode(await file.readAsString());
      for (final key in [
        'formatVersion',
        'stores',
        'manifest',
        'integrity',
        'product',
        'compatibility',
        'menuLocalProtocolVersion',
        'hiveSchemaVersion',
      ]) {
        raw.remove(key);
      }
      await closeMenu01();
      await openMenu01(destination);
      await expectLater(
        BackupRepository.restoreDataBackupFromJson(
          jsonEncode(raw),
          backupBeforeRestore: false,
        ),
        throwsFormatException,
      );
      await BackupRepository.restoreDataBackupFromJson(
        jsonEncode(raw),
        backupBeforeRestore: false,
        allowLegacyIncomplete: true,
      );
      expect(DatabaseCore.settingsBox!.get('restoreLegacyIncomplete'), true);
      expect(DatabaseCore.menuJournalBox!.isEmpty, true);
      expect(DatabaseCore.closureJournalBox!.isEmpty, true);
    },
  );
  test(
    'all durable value types and saved draft name survive without repricing',
    () async {
      final date = DateTime.utc(2026, 10, 1, 12);
      await DatabaseCore.settingsBox!.put('typedSetting', {
        3: date,
        'bytes': Uint8List.fromList([0, 1, 255]),
      });
      await DatabaseCore.quickOrderBox!.put(
        'draft-key',
        QuickOrderDraft(
          id: 'stable-draft',
          items: [],
          subtotal: 1,
          serviceFeeAmount: 0,
          total: 1,
          includeServiceFee: false,
          serviceFeeRate: 0,
          createdAt: date,
          createdBy: 'manager',
          displayName: 'Saved guest cart',
        ),
      );
      // Preserve a captured total even if the destination's pricing resolver differs.
      final order = DatabaseCore.orderBox!.get(9)!;
      order.totalAmount = 19.23;
      // This backup codec fixture holds an intentionally historical captured image.
      await DatabaseCore.orderBox!.put(9, order);
      final file = await backup();
      await fresh(file);
      expect(
        DatabaseCore.quickOrderBox!.get('draft-key')!.displayName,
        'Saved guest cart',
      );
      expect(DatabaseCore.settingsBox!.get('typedSetting'), {
        3: date,
        'bytes': Uint8List.fromList([0, 1, 255]),
      });
      expect(DatabaseCore.orderBox!.get(9)!.totalAmount, 19.23);
    },
  );
  test(
    'safety snapshot and restore share admission; latest acknowledged data has a copy',
    () async {
      final file = await backup();
      await DatabaseCore.settingsBox!.put('acknowledgedAfterOldBackup', true);
      await BackupRepository.restoreDataBackupFromFile(file);
      final copies = await Directory(
        '$source/backups',
      ).list().where((f) => f.path.endsWith('.json')).toList();
      expect(copies, hasLength(1));
      final safety = await PosBackupFormat.decode(
        await File(copies.single.path).readAsString(),
      );
      expect(safety['settingsAll']['acknowledgedAfterOldBackup'], true);
      expect(
        DatabaseCore.settingsBox!.get('acknowledgedAfterOldBackup'),
        isNull,
      );
    },
  );
  test(
    'damaged restore marker leaves startup and write admission closed',
    () async {
      final file = await backup();
      await closeMenu01();
      await openMenu01(destination);
      final box = FaultBox(DatabaseCore.salesBox!);
      DatabaseCore.salesBox = box;
      box.fault = (point) async {
        if (point == 'clear:after')
          throw FileSystemException('synthetic fault');
      };
      await expectLater(
        BackupRepository.restoreDataBackupFromFile(
          file,
          backupBeforeRestore: false,
        ),
        throwsA(isA<FileSystemException>()),
      );
      final marker = File('$destination/${BackupRepository.restoreMarkerName}');
      final raw =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      raw['actorId'] = 'changed';
      await marker.writeAsString(jsonEncode(raw), flush: true);
      await closeMenu01();
      await expectLater(openMenu01(destination), throwsFormatException);
      await expectLater(
        LocalDataAdmission.track(() async {}),
        throwsStateError,
      );
      expect(marker.existsSync(), true);
    },
  );
  test('legacy import upgrade retains incomplete-history quarantine', () async {
    final raw = {
      'meta': {'db_version': 9},
      'users': [
        {'username': 'old', 'pinCode': '123456', 'role': 'manager'},
      ],
      'orders': [
        {
          'orderId': 1,
          'items': [
            {
              'itemKey': 'old',
              'itemName': 'Old',
              'unitPrice': 3,
              'quantity': 1,
              'total': 3,
            },
          ],
        },
      ],
    };
    await closeMenu01();
    await openMenu01(destination);
    await BackupRepository.restoreDataBackupFromJson(
      jsonEncode(raw),
      backupBeforeRestore: false,
      allowLegacyIncomplete: true,
    );
    final uuid = DatabaseCore.orderBox!.values.single.orderUuid;
    final line = DatabaseCore.orderBox!.values.single.items.single.lineUuid;
    final upgraded = await backup();
    expect(
      (await PosBackupFormat.decode(
        await upgraded.readAsString(),
      ))['recoveryCompleteness'],
      'legacy-history-incomplete',
    );
    await closeMenu01();
    await Directory(destination).delete(recursive: true);
    await Directory(destination).create();
    await openMenu01(destination);
    await BackupRepository.restoreDataBackupFromJson(
      jsonEncode(raw),
      backupBeforeRestore: false,
      allowLegacyIncomplete: true,
    );
    expect(DatabaseCore.orderBox!.values.single.orderUuid, uuid);
    expect(DatabaseCore.orderBox!.values.single.items.single.lineUuid, line);
    await BackupRepository.restoreDataBackupFromFile(
      upgraded,
      backupBeforeRestore: false,
    );
    expect(DatabaseCore.settingsBox!.get('restoreLegacyIncomplete'), true);
  });
  test(
    'backup opening a closed command journal never prunes present recovery rows',
    () async {
      final box = Hive.box<Map>(EdgeCommandJournal.boxName);
      for (var i = 0; i < 5001; i++) {
        await box.put('pending-$i', {
          'commandId': 'pending-$i',
          'idempotencyKey': 'key-$i',
          'type': 'NOOP',
          'status': 'interrupted',
          'firstSeenAt': DateTime.now().toUtc().toIso8601String(),
          'runId': 'prior-run',
        });
      }
      final count = box.length;
      await EdgeCommandJournal.close();
      final file = await backup();
      final data = await PosBackupFormat.decode(await file.readAsString());
      expect(data['stores'][EdgeCommandJournal.boxName], hasLength(count));
      expect(EdgeCommandJournal.snapshot(), hasLength(count));
    },
  );
  test(
    'backup disk failure preserves existing file and releases gate',
    () async {
      final path = Directory('${root.path}/is-directory.json');
      await path.create();
      await expectLater(
        BackupRepository.createDataBackup(targetFilePath: path.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(path.existsSync(), true);
      expect(LocalDataAdmission.blocked, false);
    },
  );
  test('representative synthetic backup/restore performance', () async {
    await closeMenu01();
    await Directory(source).delete(recursive: true);
    await Directory(source).create();
    await openMenu01(source);
    await seedMenu01(itemCount: 500, salesCount: 1000);
    final file = await backup();
    final bm = BackupRepository.lastBackupMetrics;
    await fresh(file);
    final rm = BackupRepository.lastRestoreMetrics;
    expect((await verifyMenu01Recovery())['sales'], 1000);
    // ignore: avoid_print
    print(
      'MENU01_PERFORMANCE ${jsonEncode({'items': 500, 'sales': 1000, 'backup': bm, 'restore': rm})}',
    );
  });
}
