@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';

/// Live proof against a REAL backend (apps/backend/scripts/serve-canonical-menu-local.ts).
/// Skipped unless CANONICAL_MENU_LIVE_FIXTURE and CANONICAL_MENU_LIVE_DIR are set.
/// CANONICAL_MENU_LIVE_PHASE: `online` | `outage` (backend stopped) | `reconnect`.
/// Each terminal keeps its own on-disk Hive store across phases/processes.
final env = Platform.environment;
final fixturePath = env['CANONICAL_MENU_LIVE_FIXTURE'];
final dataDir = env['CANONICAL_MENU_LIVE_DIR'];
final phase = env['CANONICAL_MENU_LIVE_PHASE'] ?? 'online';

class LiveTerminal {
  LiveTerminal(this.name, this.credential, this.baseUrl, this.venueId);
  final String name;
  final String credential;
  final String baseUrl;
  final String venueId;
  bool online = true;
  late Box<String> state, journal;
  late Box<MenuCategoryDB> menu;
  late PosMenuSync sync;

  Future<LiveTerminal> open() async {
    final dir = Directory('$dataDir/$name')..createSync(recursive: true);
    state = await Hive.openBox<String>('${name}_state', path: dir.path);
    journal = await Hive.openBox<String>('${name}_journal', path: dir.path);
    menu = await Hive.openBox<MenuCategoryDB>('${name}_menu', path: dir.path);
    sync = PosMenuSync(
      stateBox: state,
      journalBox: journal,
      menuBox: menu,
      // Offline = the network path to Cloud is gone (a dead local port).
      transport: HttpMenuSyncTransport(
        baseUrl: () => online ? baseUrl : 'http://127.0.0.1:9',
        credential: () => credential,
        timeout: const Duration(seconds: 3),
      ),
      venueId: () => venueId,
    );
    return this;
  }

  MenuItemDB item(String id) => [
    for (final c in menu.values) ...?c.items,
    for (final c in menu.values)
      for (final s in c.subcategories ?? const <MenuSubcategoryDB>[])
        ...s.items,
  ].firstWhere((i) => i.id == id);

  bool has(String id) => CanonicalMenu.readHive(menu.values).containsKey(id);

  Future<void> setPrice(String id, double price) async {
    for (final c in menu.values) {
      for (final i in [
        ...?c.items,
        for (final s in c.subcategories ?? const <MenuSubcategoryDB>[])
          ...s.items,
      ]) {
        if (i.id == id) {
          i.price = price;
          await c.save();
        }
      }
    }
    await sync.captureLocalEdits();
  }

  List<MenuMutationEntry> get entries => MenuMutationJournal(journal).all();
}

void main() {
  if (fixturePath == null || dataDir == null) {
    test('live canonical Menu proof', () {}, skip: 'no live fixture');
    return;
  }
  final fixture =
      jsonDecode(File(fixturePath!).readAsStringSync()) as Map<String, dynamic>;
  final base = fixture['baseUrl'] as String;
  final venue = fixture['venueId'] as String;
  final ids = Map<String, String>.from(fixture['ids'] as Map);
  final credentials = List<String>.from(fixture['credentials'] as List);
  final owner = {
    'Authorization': 'Bearer ${fixture['ownerToken']}',
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> dashboardTree() async =>
      jsonDecode(
            (await http.get(
              Uri.parse('$base/customer/venues/$venue/catalog'),
              headers: owner,
            )).body,
          )
          as Map<String, dynamic>;
  Map<String, dynamic> findItem(Map<String, dynamic> tree, String id) {
    for (final c in tree['categories'] as List) {
      for (final i in [
        ...c['items'] as List,
        for (final s in c['subcategories'] as List) ...s['items'] as List,
      ]) {
        if (i['id'] == id) return Map<String, dynamic>.from(i as Map);
      }
    }
    throw StateError('not found');
  }

  late List<LiveTerminal> pos;
  setUpAll(() async {
    Hive.init(dataDir!);
    if (!Hive.isAdapterRegistered(5))
      Hive.registerAdapter(MenuCategoryDBAdapter());
    if (!Hive.isAdapterRegistered(6))
      Hive.registerAdapter(MenuSubcategoryDBAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MenuItemDBAdapter());
    if (!Hive.isAdapterRegistered(8))
      Hive.registerAdapter(MenuVariantDBAdapter());
    pos = [
      for (final (i, name) in ['posA', 'posB', 'posC'].indexed)
        await LiveTerminal(name, credentials[i], base, venue).open(),
    ];
  });
  tearDownAll(() => Hive.close());

  if (phase == 'online') {
    test(
      'Website-only Menu -> three fresh POS terminals, then multi-POS rules',
      () async {
        for (final t in pos) {
          expect(await t.sync.bootstrap(), MenuSyncMode.canonical);
          expect(t.item(ids['khinkali']!).price, 2.0);
          expect(t.item(ids['wine']!).variants!.single.id, ids['glass']);
          expect(t.entries, isEmpty);
        }
        final before = await dashboardTree();
        // A and B edit different items concurrently: both accepted.
        await pos[0].setPrice(ids['khinkali']!, 2.2);
        final bVariant = pos[1].item(ids['wine']!);
        bVariant.variants!.single.price = 9.5;
        await pos[1].menu.values
            .firstWhere((c) => (c.items ?? []).contains(bVariant))
            .save();
        await pos[1].sync.captureLocalEdits();
        await Future.wait([pos[0].sync.syncOnce(), pos[1].sync.syncOnce()]);
        final tree = await dashboardTree();
        expect(findItem(tree, ids['khinkali']!)['price'], 2.2);
        expect(
          (findItem(tree, ids['wine']!)['variants'] as List).single['price'],
          9.5,
        );
        // A and B edit the SAME item from the same base: one wins, one conflicts.
        await pos[0].sync.syncOnce();
        await pos[1].sync.syncOnce();
        await pos[0].setPrice(ids['khinkali']!, 2.4);
        await pos[1].setPrice(ids['khinkali']!, 2.3);
        await pos[0].sync.syncOnce();
        await pos[1].sync.syncOnce();
        expect(findItem(await dashboardTree(), ids['khinkali']!)['price'], 2.4);
        final conflict = pos[1].sync.conflicts.single;
        expect(conflict.conflict!['current']['price'], 2.4);
        expect(
          pos[1].item(ids['khinkali']!).price,
          2.3,
          reason: 'pending change kept until resolved',
        );
        await pos[1].sync.useCurrent(conflict.mutationId);
        expect(pos[1].item(ids['khinkali']!).price, 2.4);
        // C is offline while A deletes the wine; C catches the tombstone later.
        pos[2].online = false;
        final wineCategory = pos[0].menu.values.firstWhere(
          (c) => (c.items ?? []).any((i) => i.id == ids['wine']),
        );
        wineCategory.items!.removeWhere((i) => i.id == ids['wine']);
        await wineCategory.save();
        await pos[0].sync.captureLocalEdits();
        await pos[0].sync.syncOnce();
        expect(await pos[2].sync.syncOnce(), isFalse);
        expect(pos[2].has(ids['wine']!), isTrue);
        pos[2].online = true;
        await pos[2].sync.syncOnce();
        expect(pos[2].has(ids['wine']!), isFalse);
        expect(pos[2].has(ids['glass']!), isFalse);
        // Dashboard edit reaches connected terminals.
        final khinkali = findItem(await dashboardTree(), ids['khinkali']!);
        final res = await http.post(
          Uri.parse('$base/customer/venues/$venue/catalog/mutations'),
          headers: owner,
          body: jsonEncode({
            'mutationId': const Uuid().v4(),
            'entityType': 'ITEM',
            'operation': 'UPSERT',
            'entityId': ids['khinkali'],
            'expectedRevision': khinkali['revision'],
            'patch': {'nameEn': 'Khinkali (Kalakuri)'},
          }),
        );
        expect(res.statusCode, 200);
        for (final t in pos) {
          await t.sync.syncOnce();
          expect(t.item(ids['khinkali']!).getName('en'), 'Khinkali (Kalakuri)');
        }
        expect(
          (await dashboardTree())['sequence'],
          greaterThan(before['sequence'] as int),
        );
        // Same catalog on all three terminals.
        final shapes = {
          for (final t in pos)
            jsonEncode(
              CanonicalMenu.readHive(
                t.menu.values,
              ).map((k, v) => MapEntry(k, v.fields)),
            ),
        };
        expect(shapes, hasLength(1));
      },
    );
  }

  if (phase == 'outage') {
    test(
      'backend STOPPED: POS starts, loads Menu, edits locally, keeps pending',
      () async {
        final a = pos[0];
        expect(a.sync.isCanonical, isTrue);
        expect(a.item(ids['khinkali']!).getName('en'), 'Khinkali (Kalakuri)');
        await a.setPrice(ids['khinkali']!, 3.1);
        expect(a.item(ids['khinkali']!).price, 3.1);
        expect(await a.sync.syncOnce(), isFalse, reason: 'Cloud is down');
        final pending = a.entries.where((e) => e.unresolved).toList();
        expect(pending.single.patch['price'], 3.1);
        expect(pending.single.status, MenuMutationStatus.failedRetryable);
        expect(a.item(ids['khinkali']!).price, 3.1);
      },
    );
  }

  if (phase == 'reconnect') {
    test(
      'backend restarted: the pending edit survives restart and reaches Cloud',
      () async {
        final a = pos[0];
        expect(
          a.item(ids['khinkali']!).price,
          3.1,
          reason: 'survived process restart',
        );
        expect(a.entries.where((e) => e.unresolved), hasLength(1));
        expect(await a.sync.syncOnce(), isTrue);
        expect(a.entries.where((e) => e.unresolved), isEmpty);
        expect(findItem(await dashboardTree(), ids['khinkali']!)['price'], 3.1);
        await pos[1].sync.syncOnce();
        expect(pos[1].item(ids['khinkali']!).price, 3.1);
      },
    );
  }
}
