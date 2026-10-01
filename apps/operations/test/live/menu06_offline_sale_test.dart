import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/sale_consumption_sync_service.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';
import '../support/menu01_fixture.dart' show openMenu01, closeMenu01;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment,
      root = env['MENU06_HIVE_DIR'],
      fixturePath = env['MENU06_HTTP_FIXTURE'],
      stage = env['MENU06_POS_STAGE'];
  test(
    'MENU06 native offline Sale / retirement / restart / portable restore',
    () async {
      HttpOverrides.global =
          null; // This isolated proof intentionally uses real HTTP.
      if (!root!.startsWith('/private/tmp/vynic_menu06_process_'))
        throw StateError('Owned Hive path required');
      final fixture =
              jsonDecode(File(fixturePath!).readAsStringSync())
                  as Map<String, dynamic>,
          venue = Map<String, dynamic>.from(
            (fixture['venues'] as List).first as Map,
          ),
          product = fixture['product'] as Map;
      final itemId = product['itemId'] as String,
          variantId = product['variantId'] as String,
          base = fixture['baseUrl'] as String,
          credential = venue['credential'] as String;
      Future<void> write(String name, Map<String, dynamic> value) async {
        final f = File('$root/$name.tmp');
        await f.writeAsString(jsonEncode(value), flush: true);
        await f.rename('$root/$name.json');
      }

      PosMenuSync menuSync() => PosMenuSync(
        stateBox: DatabaseCore.menuCanonicalBox!,
        journalBox: DatabaseCore.menuJournalBox!,
        menuBox: DatabaseCore.menuBox!,
        transport: HttpMenuSyncTransport(
          baseUrl: () => base,
          credential: () => credential,
        ),
        venueId: () => venue['venueId'] as String,
      );
      Map sale() =>
          Map.from(DatabaseCore.salesBox!.values.whereType<Map>().single);
      String captured(Map row) {
        final copy = Map.from(row)..remove('inventoryConsumptionAck');
        return jsonEncode(copy);
      }

      Future<void> price(PosMenuSync sync, double value) =>
          sync.local.edit((draft) async {
            for (final c in draft.values) {
              for (final s in c.subcategories ?? []) {
                for (final i in s.items) {
                  if (i.id == itemId) i.price = value;
                }
              }
            }
            await draft.commit();
          });
      const password = 'synthetic-menu06-backup-only';
      if (stage == 'writer') {
        await Directory('$root/source').create();
        await openMenu01('$root/source');
        await EdgeDeviceCredentialStore.saveEnrollment(
          rawCredential: credential,
          venueId: venue['venueId'] as String,
          venueName: 'Synthetic MENU06',
        );
        await DatabaseCore.settingsBox!.putAll({
          'currentDate': '2026-10-01T00:00:00.000',
          'serviceFeeEnabled': false,
          'serviceFeePercent': 0.0,
        });
        final sync = menuSync();
        expect(await sync.bootstrap(), MenuSyncMode.canonical);
        final r = await http.get(
          Uri.parse('$base/edge/inventory/catalog?version=5'),
          headers: {'X-POS-Sync-Key': credential},
        );
        expect(r.statusCode, 200);
        await InventoryRepository.replaceCatalog(
          jsonDecode(r.body) as Map<String, dynamic>,
        );
        final key = await SalesRepository.saveSaleRecord(
          orderId: 606,
          tableNumbers: ['6'],
          floor: 'first',
          items: [
            OrderItem(
              itemKey: 'captured',
              itemName: 'Captured offline dish',
              unitPrice: 7,
              quantity: 10,
              total: 70,
              menuItemId: itemId,
              variantId: variantId,
            ),
          ],
          totalAmount: 70,
          paymentMethod: 'cash',
          createdBy: 'synthetic-manager',
          createdAt: DateTime.utc(2026, 10, 1, 9),
          closedAt: DateTime.utc(2026, 10, 1, 10),
          includeServiceFee: false,
          isFiscal: true,
          captureConsumption: true,
          closureId: '60600000-0000-4000-8000-000000000001',
          businessDate: '2026-10-01',
        );
        expect(key, isNotNull);
        expect(SaleConsumptionSyncService.pending(), hasLength(1));
        final row = sale(),
            line =
                ((row['inventoryConsumption'] as Map)['lines'] as List).single
                    as Map;
        expect(line['status'], 'MAPPED');
        expect(
          (line['components'] as List).single['totalBaseQuantity'],
          '2.000000',
        );
        await price(sync, 12);
        await price(sync, 13);
        await BackupRepository.createDataBackup(
          targetFilePath: '$root/before-retirement.json',
          password: password,
        );
        for (final box in [
          DatabaseCore.salesBox!,
          DatabaseCore.menuBox!,
          DatabaseCore.menuCanonicalBox!,
          DatabaseCore.menuJournalBox!,
          DatabaseCore.inventoryBox!,
        ])
          await box.flush();
        await write('writer', {
          'pid': pid,
          'sale': row,
          'saleSha256': sha256.convert(utf8.encode(captured(row))).toString(),
          'mutationIds': sync.unresolved.map((e) => e.mutationId).toList(),
          'recipeId': line['recipeId'],
          'pendingConsumption': true,
          'checkpoint': 'offline close durable; no outbound consumption',
        });
        await Completer<void>().future;
      } else {
        final writer =
            jsonDecode(File('$root/writer.json').readAsStringSync()) as Map;
        await openMenu01('$root/source');
        final sync = menuSync();
        expect(captured(sale()), jsonEncode(writer['sale']));
        expect(await sync.syncOnce(), isTrue);
        expect(
          CanonicalMenu.readHive(
            DatabaseCore.menuBox!.values,
          ).containsKey(itemId),
          false,
        );
        expect(
          sync.unresolved.map((e) => e.mutationId).toList(),
          writer['mutationIds'],
        );
        expect(sync.conflicts.single.conflict!['deleted'], true);
        expect(sync.unresolved, hasLength(2));
        expect(SaleConsumptionSyncService.pending(), hasLength(1));
        await BackupRepository.createDataBackup(
          targetFilePath: '$root/after-retirement.json',
          password: password,
        );
        await closeMenu01();
        await Directory('$root/fresh').create();
        await openMenu01('$root/fresh');
        expect(DatabaseCore.salesBox!.isEmpty, true);
        await BackupRepository.restoreDataBackupFromFile(
          File('$root/after-retirement.json'),
          password: password,
          backupBeforeRestore: false,
        );
        await closeMenu01();
        await openMenu01('$root/fresh');
        expect(EdgeDeviceCredentialStore.hasCredential, false);
        expect(
          CanonicalMenu.readHive(
            DatabaseCore.menuBox!.values,
          ).containsKey(itemId),
          false,
        );
        expect(captured(sale()), jsonEncode(writer['sale']));
        expect(
          InventoryRepository.getRecipes().map((r) => r.recipeId),
          contains(writer['recipeId']),
        );
        final effects = SaleConsumptionSyncService(
          baseUrl: () => base,
          credential: () => credential,
        );
        await effects.syncOnce();
        expect(sale()['inventoryConsumptionAck'], 1);
        expect(captured(sale()), jsonEncode(writer['sale']));
        final key = DatabaseCore.salesBox!.keys.single;
        await DatabaseCore.salesBox!.put(key, {
          ...sale(),
          'inventoryConsumptionAck': 0,
        });
        await effects.syncOnce();
        expect(sale()['inventoryConsumptionAck'], 1);
        expect(captured(sale()), jsonEncode(writer['sale']));
        effects.close();
        final afterHash = sha256
            .convert(utf8.encode(captured(sale())))
            .toString();
        expect(afterHash, writer['saleSha256']);
        await closeMenu01();
        await Directory('$root/old-fresh').create();
        await openMenu01('$root/old-fresh');
        await BackupRepository.restoreDataBackupFromFile(
          File('$root/before-retirement.json'),
          password: password,
          backupBeforeRestore: false,
        );
        expect(EdgeDeviceCredentialStore.hasCredential, false);
        expect(await menuSync().syncOnce(), isTrue);
        expect(
          CanonicalMenu.readHive(
            DatabaseCore.menuBox!.values,
          ).containsKey(itemId),
          false,
        );
        final retry = SaleConsumptionSyncService(
          baseUrl: () => base,
          credential: () => credential,
        );
        await retry.syncOnce();
        expect(sale()['inventoryConsumptionAck'], 1);
        expect(captured(sale()), jsonEncode(writer['sale']));
        retry.close();
        await write('reader', {
          'pid': pid,
          'writerPid': writer['pid'],
          'saleSha256': afterHash,
          'saleUnchanged': true,
          'postRetirementBackupImmediatelyInactive': true,
          'oldBackupInactiveAfterCatchup': true,
          'backupClonedCredential': false,
          'retainedRecipeId': writer['recipeId'],
          'mutationIds': MenuLocalStore.forBox(
            DatabaseCore.menuBox!,
          ).journal.unresolved().map((e) => e.mutationId).toList(),
          'pendingSuccessorsPreserved': true,
          'newOrderingSelectionAbsent': true,
          'consumptionAck': sale()['inventoryConsumptionAck'],
          'sale': sale(),
        });
        await closeMenu01();
      }
    },
    skip: root == null || fixturePath == null || stage == null
        ? 'Use the isolated MENU06 proof runner'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
