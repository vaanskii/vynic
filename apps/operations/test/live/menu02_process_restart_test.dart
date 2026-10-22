import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';

import '../unit/canonical_menu_sync_test.dart' show FakeMenuCloud;
import '../unit/menu02_durability_test.dart'
    show FaultBox, PausedLink, Menu02NoHttp;

/// Two-process native Flutter proof, orchestrated by tool/prove_menu02_restart.py.
/// The writer is SIGKILLed while a real Hive projection is empty; no close runs.
void main() {
  final path = Platform.environment['MENU02_PROCESS_DIRECTORY'];
  final stage = Platform.environment['MENU02_PROCESS_STAGE'];
  if (path == null || stage == null) {
    test(
      'MENU02 process proof requires the isolated orchestrator',
      () {},
      skip:
          'run python3 tool/prove_menu02_restart.py --flutter <isolated SDK> --output <proof.json>',
    );
    return;
  }
  if (!path.startsWith('/private/tmp/vynic_menu02_process_')) {
    throw StateError('Process proof accepts only its disposable directory');
  }
  const venue = 'menu02-process-synthetic';
  const cat = '30000000-0000-4000-8000-000000000001';
  const item = '30000000-0000-4000-8000-000000000002';
  const other = '30000000-0000-4000-8000-000000000003';

  test('MENU02 native process $stage', () async {
    HttpOverrides.global = Menu02NoHttp();
    Hive.registerAdapter(MenuCategoryDBAdapter());
    Hive.registerAdapter(MenuSubcategoryDBAdapter());
    Hive.registerAdapter(MenuItemDBAdapter());
    Hive.registerAdapter(MenuVariantDBAdapter());
    final state = await Hive.openBox<String>('process_state', path: path);
    final journal = await Hive.openBox<String>('process_journal', path: path);
    final menu = FaultBox(
      await Hive.openBox<MenuCategoryDB>('process_menu', path: path),
    );
    DatabaseCore.menuBox = menu;
    DatabaseCore.auditLogBox = await Hive.openBox('process_audit', path: path);
    final cloud = FakeMenuCloud(venue)
      ..ownerEdit('CATEGORY', cat, {
        'slug': 'synthetic',
        'nameEn': 'Synthetic',
        'nameKa': 'Synthetic',
      })
      ..ownerEdit('ITEM', item, {
        'categoryId': cat,
        'nameEn': 'Item',
        'nameKa': 'Item',
        'price': 10.0,
      })
      ..ownerEdit('ITEM', other, {
        'categoryId': cat,
        'nameEn': 'Other',
        'nameKa': 'Other',
        'price': 20.0,
        'sortOrder': 1,
      });
    final link = PausedLink(cloud);
    final engine = PosMenuSync(
      stateBox: state,
      journalBox: journal,
      menuBox: menu,
      transport: link,
      venueId: () => venue,
    );
    if (stage == 'writer') {
      await engine.bootstrap();
      cloud.ownerEdit('ITEM', other, {'price': 24.0});
      link.pausePull();
      final pulling = engine.syncOnce();
      await link.entered!.future;
      expect(
        await MenuRepository.updateItemInCategory(
          categoryIndex: 0,
          itemIndex: 0,
          nameEn: 'Item',
          nameKa: 'Item',
          price: 12,
        ),
        isTrue,
      );
      final mutationId = engine.unresolved.single.mutationId;
      menu.fault = (checkpoint) async {
        if (checkpoint != 'clear:after') return;
        await menu.inner.flush();
        expect(menu.isEmpty, isTrue);
        expect(state.get(MenuLocalStore.commitKey), isNotNull);
        await File('$path/ready.tmp').writeAsString(
          jsonEncode({
            'pid': pid,
            'checkpoint': checkpoint,
            'mutationId': mutationId,
            'acknowledgedLocalPrice': 12,
            'projectionEmptyAtKill': true,
          }),
          flush: true,
        );
        await File('$path/ready.tmp').rename('$path/ready.json');
        await Completer<void>().future; // parent kills this exact process
      };
      link.release!.complete();
      await pulling;
      fail('The orchestrator must kill the writer at its signaled checkpoint');
    } else if (stage == 'reader') {
      link.online = false;
      final before = jsonDecode(await File('$path/ready.json').readAsString());
      expect(
        menu.isEmpty,
        isTrue,
        reason: 'actual empty Hive projection survived the kill',
      );
      expect(state.get(MenuLocalStore.commitKey), isNotNull);
      await engine.local.initialize();
      expect(menu.values.single.items!.first.price, 12);
      expect(menu.values.single.items!.last.price, 24);
      expect(engine.unresolved, hasLength(1));
      expect(engine.unresolved.single.mutationId, before['mutationId']);
      expect(await engine.captureLocalEdits(), 0);
      expect(state.get(MenuLocalStore.commitKey), isNull);
      expect(state.get(MenuLocalStore.rebuildingKey), isNull);
      await File('$path/result.json').writeAsString(
        jsonEncode({
          'status': 'PASS',
          'writerPid': before['pid'],
          'readerPid': pid,
          'mutationId': engine.unresolved.single.mutationId,
          'pendingEntries': engine.unresolved.length,
          'localPrice': menu.values.single.items!.first.price,
          'otherCloudPrice': menu.values.single.items!.last.price,
          'journalStatus': engine.unresolved.single.status.name,
          'cloudReachableDuringRecovery': false,
          'walCleared': true,
          'projectionMarkerCleared': true,
          'duplicateCaptureCount': 0,
        }),
        flush: true,
      );
      await engine.close();
      await Hive.close();
    } else {
      throw StateError('Unknown process proof stage');
    }
  });
}
