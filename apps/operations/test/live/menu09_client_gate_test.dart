import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/edge_enrollment_client.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_client_compatibility.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';
import '../support/menu01_fixture.dart' show openMenu01, closeMenu01;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'MENU09 native admission, offline durability, restart and fresh-machine gate',
    () async {
      HttpOverrides.global = null;
      final root = Platform.environment['MENU09_HIVE_DIR']!;
      if (!root.startsWith('/private/tmp/vynic_menu09_process_'))
        throw StateError('Owned Hive directory required');
      final f =
          jsonDecode(
                File(
                  Platform.environment['MENU09_HTTP_FIXTURE']!,
                ).readAsStringSync(),
              )
              as Map;
      final v = (f['venues'] as List).first as Map;
      final base = f['baseUrl'] as String, itemId = f['itemId'] as String;
      const old = <String, Object?>{
        'version': 1,
        'capabilities': [],
        'appVersion': 'exact-old-protocol-fixture',
        'buildNumber': 1,
      };
      const password = 'synthetic-menu09-backup-only';
      Future<EdgeEnrollmentResult> enroll(
        int index, {
        bool incompatible = false,
      }) async {
        final c = EdgeEnrollmentClient();
        try {
          return await c.enroll(
            baseUrl: base,
            code: (f['codes'] as List)[index] as String,
            installationId: EdgeDeviceCredentialStore.installationId!,
            platform: 'MACOS',
            menuClient: incompatible ? old : null,
          );
        } finally {
          c.close();
        }
      }

      Future<void> save(EdgeEnrollmentResult r) async {
        expect(
          await EdgeDeviceCredentialStore.saveEnrollment(
            rawCredential: r.credential!,
            venueId: r.venueId!,
            venueName: r.venueName!,
          ),
          true,
        );
      }

      PosMenuSync engine({
        bool incompatible = false,
        String? credential,
        bool offline = false,
      }) => PosMenuSync(
        stateBox: DatabaseCore.menuCanonicalBox!,
        journalBox: DatabaseCore.menuJournalBox!,
        menuBox: DatabaseCore.menuBox!,
        transport: HttpMenuSyncTransport(
          baseUrl: () => offline ? 'http://127.0.0.1:1' : base,
          credential: () => credential ?? EdgeDeviceCredentialStore.credential,
          menuClient: incompatible ? old : null,
        ),
        venueId: () => v['venueId'] as String,
      );
      String saleHash() => sha256
          .convert(
            utf8.encode(jsonEncode(DatabaseCore.salesBox!.values.toList())),
          )
          .toString();
      Future<void> write(String label, Map<String, Object?> data) async {
        await File(
          '$root/$label.json',
        ).writeAsString(jsonEncode(data), flush: true);
      }

      if (Platform.environment['MENU09_POS_STAGE'] == 'writer') {
        await Directory('$root/source').create();
        await openMenu01('$root/source');
        final r = await enroll(0);
        expect(r.isEnrolled, true);
        await save(r);
        final sync = engine();
        expect(await sync.bootstrap(), MenuSyncMode.canonical);
        expect(await sync.syncOnce(), true);
        // Cloud is disconnected after admission: a local edit and Sale still
        // commit durably; no compatibility request is on either write path.
        final disconnected = engine(offline: true);
        await disconnected.local.edit((draft) async {
          for (final c in draft.values) {
            for (final i in c.items ?? []) {
              if (i.id == itemId) i.price = 15.0;
            }
          }
          await draft.commit();
        });
        expect(await disconnected.syncOnce(), false);
        final sale = await SalesRepository.saveSaleRecord(
          orderId: 909,
          tableNumbers: ['9'],
          floor: 'synthetic',
          items: [
            OrderItem(
              itemKey: 'captured',
              itemName: 'Captured offline',
              unitPrice: 7,
              quantity: 1,
              total: 7,
              menuItemId: itemId,
            ),
          ],
          totalAmount: 7,
          paymentMethod: 'cash',
          createdBy: 'synthetic',
          createdAt: DateTime.utc(2026, 10, 2),
          closedAt: DateTime.utc(2026, 10, 2, 1),
          includeServiceFee: false,
          isFiscal: true,
          closureId: '90900000-0000-4000-8000-000000000001',
          businessDate: '2026-10-02',
        );
        expect(sale, isNotNull);
        await BackupRepository.createDataBackup(
          targetFilePath: '$root/restaurant.json',
          password: password,
        );
        await write('writer', {
          'pid': pid,
          'deviceId': EdgeDeviceCredentialStore.deviceId,
          'saleHash': saleHash(),
          'mutationIds': sync.unresolved.map((e) => e.mutationId).toList(),
          'offlineEditAndSale': true,
        });
        await closeMenu01();
      } else {
        final w =
            jsonDecode(File('$root/writer.json').readAsStringSync()) as Map;
        await openMenu01('$root/source');
        final sync = engine();
        expect(await sync.syncOnce(), true);
        expect(saleHash(), w['saleHash']);
        final normalRestart =
            EdgeDeviceCredentialStore.deviceId == w['deviceId'];
        await closeMenu01();
        await Directory('$root/fresh').create();
        await openMenu01('$root/fresh');
        await BackupRepository.restoreDataBackupFromFile(
          File('$root/restaurant.json'),
          password: password,
          backupBeforeRestore: false,
        );
        expect(EdgeDeviceCredentialStore.hasCredential, false);
        expect(DatabaseCore.settingsBox!.get('deviceRuntimeConfig'), isNull);
        expect(saleHash(), w['saleHash']);
        final restored = engine();
        final ids = restored.unresolved.map((e) => e.mutationId).toList();
        expect(ids, w['mutationIds']);
        final bad = await enroll(1, incompatible: true);
        expect(bad.outcome, EdgeEnrollmentOutcome.updateRequired);
        expect(EdgeDeviceCredentialStore.hasCredential, false);
        final oldTransport = HttpMenuSyncTransport(
          baseUrl: () => base,
          credential: () => v['credential'] as String,
          menuClient: old,
        );
        final refusal = await oldTransport.catalog();
        expect(refusal.status, 426);
        expect(MenuClientCompatibility.updateRequired.value, isNotNull);
        final blocked = engine(
          incompatible: true,
          credential: v['credential'] as String,
        );
        expect(await blocked.syncOnce(), false);
        expect(blocked.unresolved.map((e) => e.mutationId).toList(), ids);
        expect(saleHash(), w['saleHash']);
        final current = await enroll(1);
        expect(current.isEnrolled, true);
        await save(current);
        expect(EdgeDeviceCredentialStore.deviceId, isNot(w['deviceId']));
        expect(await restored.syncOnce(), true);
        expect(MenuClientCompatibility.updateRequired.value, isNull);
        final cloud = await http.get(
          Uri.parse('$base/edge/menu/catalog'),
          headers: {
            'X-POS-Sync-Key': current.credential!,
            ...MenuClientCompatibility.headers,
          },
        );
        expect(cloud.statusCode, 200);
        final nodes = CanonicalMenu.fromSnapshot(
          jsonDecode(cloud.body) as Map<String, dynamic>,
        );
        expect(nodes.nodes[itemId]!.fields['price'], 15);
        await write('reader', {
          'pid': pid,
          'normalRestart': normalRestart,
          'saleHash': saleHash(),
          'restoredMutationIds': ids,
          'sourceDeviceId': w['deviceId'],
          'freshDeviceId': EdgeDeviceCredentialStore.deviceId,
          'unsupportedEnrollmentStatus': bad.outcome.name,
          'oldCatalogStatus': refusal.status,
          'freshEnrollmentRequired': true,
          'cloudPrice': 15,
          'noLocalDataLoss': true,
        });
        await closeMenu01();
        oldTransport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
