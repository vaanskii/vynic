import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';

/// In-memory Cloud with the server contract of MenuCatalogService
/// (apps/backend/src/menu-catalog): per-node revisions, applied-once mutation
/// ids per Venue, explicit conflicts, tombstones and changes-since.
class FakeMenuCloud {
  FakeMenuCloud(this.venueId, {this.authority = 'CLOUD'});
  final String venueId;
  final String authority;
  int sequence = 0;
  final nodes = <String, Map<String, Object?>>{};
  final kinds = <String, String>{};
  final tombstones = <String, Map<String, Object?>>{};
  final accepted = <String, Map<String, dynamic>>{};
  int applied = 0;

  static const _lists = {
    'CATEGORY': 'categories',
    'SUBCATEGORY': 'subcategories',
    'ITEM': 'items',
    'VARIANT': 'variants',
  };

  Map<String, dynamic> _snapshot(bool Function(Map<String, Object?>) where) {
    final out = <String, dynamic>{
      'version': 2,
      'venueId': venueId,
      'authority': authority,
      'sequence': sequence,
      for (final list in _lists.values) list: <Map<String, Object?>>[],
    };
    for (final e in nodes.entries) {
      if (!where(e.value)) continue;
      (out[_lists[kinds[e.key]]!] as List).add({'id': e.key, ...e.value});
    }
    return jsonDecode(jsonEncode(out)) as Map<String, dynamic>;
  }

  MenuTransportResult catalog() =>
      MenuTransportResult(200, _snapshot((_) => true));

  MenuTransportResult changes(int since) {
    if (since > sequence) {
      return const MenuTransportResult(409, {'code': 'RESYNC_REQUIRED'});
    }
    final body = _snapshot((n) => (n['changeSeq'] as int) > since)
      ..['since'] = since
      ..['tombstones'] = [
        for (final e in tombstones.entries)
          if ((e.value['seq'] as int) > since) {'entityId': e.key, ...e.value},
      ];
    return MenuTransportResult(200, body);
  }

  MenuTransportResult mutate(Map<String, Object?> raw) {
    final m = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    final id = m['mutationId'] as String;
    final content = jsonEncode({...m}..remove('mutationId'));
    final prior = accepted[id];
    if (prior != null) {
      if (prior['_content'] != content) {
        return const MenuTransportResult(409, {'code': 'MUTATION_ID_REUSED'});
      }
      return MenuTransportResult(
        200,
        {...prior, 'duplicate': true}..remove('_content'),
      );
    }
    final entityId = m['entityId'] as String;
    final kind = m['entityType'] as String;
    final expected = m['expectedRevision'] as int;
    final current = nodes[entityId];
    MenuTransportResult conflict(int rev, bool deleted) =>
        MenuTransportResult(409, {
          'code': 'REVISION_CONFLICT',
          'conflict': {
            'entityType': kind,
            'entityId': entityId,
            'expectedRevision': expected,
            'currentRevision': rev,
            'deleted': deleted,
            'current': current == null ? null : {'id': entityId, ...current},
            'pending': m['patch'],
          },
        });
    Map<String, dynamic> result;
    if (m['operation'] == 'DELETE') {
      if (current == null) {
        result = {
          'revision': tombstones[entityId]?['revision'] ?? 0,
          'deleted': true,
          'entity': null,
          'sequence': sequence,
        };
      } else {
        if (current['revision'] != expected)
          return conflict(current['revision'] as int, false);
        sequence++;
        void bury(String nodeId, String nodeKind) {
          tombstones[nodeId] = {
            'entityType': nodeKind,
            'seq': sequence,
            'revision': (nodes[nodeId]!['revision'] as int) + 1,
          };
          nodes.remove(nodeId);
        }

        if (kind == 'ITEM') {
          for (final v
              in nodes.entries
                  .where((e) => e.value['menuItemId'] == entityId)
                  .map((e) => e.key)
                  .toList()) {
            bury(v, 'VARIANT');
          }
        }
        final rev = (current['revision'] as int) + 1;
        bury(entityId, kind);
        applied++;
        result = {
          'revision': rev,
          'deleted': true,
          'entity': null,
          'sequence': sequence,
        };
      }
    } else if (current == null) {
      if (tombstones.containsKey(entityId))
        return conflict(tombstones[entityId]!['revision'] as int, true);
      if (expected != 0) return conflict(0, false);
      final patch = Map<String, Object?>.from(m['patch'] as Map);
      final parent =
          patch['categoryId'] ?? patch['subcategoryId'] ?? patch['menuItemId'];
      if (parent != null && !nodes.containsKey(parent)) {
        return const MenuTransportResult(409, {'code': 'PARENT_MISSING'});
      }
      sequence++;
      nodes[entityId] = {
        if (kind == 'ITEM') ...{
          'enabled': true,
          'sendToKitchen': true,
          'categoryId': null,
          'subcategoryId': null,
          'sortOrder': 0,
        },
        if (kind == 'CATEGORY') ...{
          'sendToKitchen': true,
          'sortOrder': 0,
          'slug': entityId,
        },
        if (kind == 'SUBCATEGORY') ...{'sortOrder': 0, 'slug': entityId},
        ...patch,
        'revision': 1,
        'changeSeq': sequence,
      };
      kinds[entityId] = kind;
      applied++;
      result = {
        'revision': 1,
        'deleted': false,
        'entity': {'id': entityId, ...nodes[entityId]!},
        'sequence': sequence,
      };
    } else {
      if (current['revision'] != expected)
        return conflict(current['revision'] as int, false);
      final patch = Map<String, Object?>.from(m['patch'] as Map);
      final changed = patch.entries.any((e) => current[e.key] != e.value);
      if (changed) {
        sequence++;
        if (kind == 'ITEM' && patch.containsKey('categoryId'))
          current['subcategoryId'] = null;
        if (kind == 'ITEM' && patch.containsKey('subcategoryId'))
          current['categoryId'] = null;
        current
          ..addAll(patch)
          ..['revision'] = (current['revision'] as int) + 1
          ..['changeSeq'] = sequence;
        applied++;
      }
      result = {
        'revision': current['revision'],
        'deleted': false,
        'entity': {'id': entityId, ...current},
        'sequence': sequence,
      };
    }
    final full = <String, dynamic>{
      'status': 'ACCEPTED',
      'duplicate': false,
      'mutationId': id,
      'entityType': kind,
      'entityId': entityId,
      ...result,
    };
    accepted[id] = {...full, '_content': content};
    return MenuTransportResult(
      200,
      jsonDecode(jsonEncode(full)) as Map<String, dynamic>,
    );
  }

  /// A Dashboard (owner) edit, as the Cloud editor would submit it.
  void ownerEdit(String kind, String entityId, Map<String, Object?> patch) {
    final res = mutate({
      'mutationId': const Uuid().v4(),
      'entityType': kind,
      'operation': 'UPSERT',
      'entityId': entityId,
      'expectedRevision': nodes[entityId]?['revision'] ?? 0,
      'patch': patch,
    });
    expect(res.status, 200);
  }
}

/// Network between one POS and the fake Cloud; can go offline or lose replies.
class FakeLink implements MenuSyncTransport {
  FakeLink(this.cloud);
  final FakeMenuCloud cloud;
  bool online = true;
  bool loseNextReply = false;
  int mutations = 0;

  @override
  Future<MenuTransportResult> catalog() async =>
      online ? cloud.catalog() : const MenuTransportResult(0);
  @override
  Future<MenuTransportResult> changes(int since) async =>
      online ? cloud.changes(since) : const MenuTransportResult(0);
  @override
  Future<MenuTransportResult> mutate(Map<String, Object?> m) async {
    if (!online) return const MenuTransportResult(0);
    mutations++;
    final result = cloud.mutate(m);
    if (loseNextReply) {
      loseNextReply = false;
      return const MenuTransportResult(0); // applied in Cloud, reply lost
    }
    return result;
  }
}

/// One POS terminal with its OWN Hive files (no shared store).
class Terminal {
  Terminal(this.name, this.dir, this.link, this.venueId);
  final String name;
  final Directory dir;
  final FakeLink link;
  final String venueId;
  late Box<String> state;
  late Box<String> journal;
  late Box<MenuCategoryDB> menu;
  late PosMenuSync sync;

  Future<Terminal> open() async {
    state = await Hive.openBox<String>('${name}_state', path: dir.path);
    journal = await Hive.openBox<String>('${name}_journal', path: dir.path);
    menu = await Hive.openBox<MenuCategoryDB>('${name}_menu', path: dir.path);
    sync = PosMenuSync(
      stateBox: state,
      journalBox: journal,
      menuBox: menu,
      transport: link,
      venueId: () => venueId,
    );
    return this;
  }

  /// Simulates app/Windows restart: close every box, reopen from disk.
  Future<void> restart() async {
    await sync.close();
    await state.close();
    await journal.close();
    await menu.close();
    await open();
  }

  MenuItemDB item(String id) => [
    for (final c in menu.values) ...?c.items,
    for (final c in menu.values)
      for (final s in c.subcategories ?? const <MenuSubcategoryDB>[])
        ...s.items,
  ].firstWhere((i) => i.id == id);

  bool has(String id) => CanonicalMenu.readHive(menu.values).containsKey(id);

  /// Local operator edit, committed to the operational menu first.
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
  late Directory root;
  const venue = 'venue-a';
  final ids = {
    'cat': const Uuid().v4(),
    'sub': const Uuid().v4(),
    'khinkali': const Uuid().v4(),
    'khachapuri': const Uuid().v4(),
    'wine': const Uuid().v4(),
    'glass': const Uuid().v4(),
  };
  late FakeMenuCloud cloud;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('vynic_canonical_menu');
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(5))
      Hive.registerAdapter(MenuCategoryDBAdapter());
    if (!Hive.isAdapterRegistered(6))
      Hive.registerAdapter(MenuSubcategoryDBAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MenuItemDBAdapter());
    if (!Hive.isAdapterRegistered(8))
      Hive.registerAdapter(MenuVariantDBAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  });
  tearDownAll(() async {
    await Hive.close();
    root.deleteSync(recursive: true);
  });

  var counter = 0;
  Future<Terminal> terminal(String name, [FakeMenuCloud? on]) async {
    final dir = Directory('${root.path}/${name}_${counter++}')..createSync();
    return Terminal(
      '$name${counter}',
      dir,
      FakeLink(on ?? cloud),
      venue,
    ).open();
  }

  setUp(() {
    // Website-only restaurant: the owner authored the whole Menu in Cloud.
    cloud = FakeMenuCloud(venue)
      ..ownerEdit('CATEGORY', ids['cat']!, {
        'nameKa': 'სამზარეულო',
        'nameEn': 'Kitchen',
        'slug': 'kitchen',
      })
      ..ownerEdit('SUBCATEGORY', ids['sub']!, {
        'categoryId': ids['cat'],
        'nameKa': 'ცხელი',
        'nameEn': 'Hot',
        'slug': 'hot',
      })
      ..ownerEdit('ITEM', ids['khinkali']!, {
        'subcategoryId': ids['sub'],
        'nameKa': 'ხინკალი',
        'nameEn': 'Khinkali',
        'price': 2.0,
      })
      ..ownerEdit('ITEM', ids['khachapuri']!, {
        'subcategoryId': ids['sub'],
        'nameKa': 'ხაჭაპური',
        'nameEn': 'Khachapuri',
        'price': 18.0,
        'sortOrder': 1,
      })
      ..ownerEdit('ITEM', ids['wine']!, {
        'categoryId': ids['cat'],
        'nameKa': 'ღვინო',
        'nameEn': 'Wine',
        'price': 0.0,
      })
      ..ownerEdit('VARIANT', ids['glass']!, {
        'menuItemId': ids['wine'],
        'size': 0.15,
        'price': 9.0,
      });
  });

  test(
    '2/3/16. fresh POS terminals import exact ids and revisions; no duplicates',
    () async {
      final a = await terminal('a');
      final b = await terminal('b');
      expect(await a.sync.bootstrap(), MenuSyncMode.canonical);
      expect(await b.sync.bootstrap(), MenuSyncMode.canonical);
      for (final t in [a, b]) {
        expect(t.item(ids['khinkali']!).price, 2.0);
        expect(t.item(ids['wine']!).variants!.single.id, ids['glass']);
        // Priced by size: the POS base price stays null.
        expect(t.item(ids['wine']!).price, isNull);
        expect(t.sync.state!.nodes[ids['khinkali']]!.revision, 1);
        expect(t.sync.state!.sequence, cloud.sequence);
        expect(t.entries, isEmpty, reason: 'importing is not an edit');
      }
      expect(
        jsonEncode(CanonicalMenu.readHive(a.menu.values).keys.toList()),
        jsonEncode(CanonicalMenu.readHive(b.menu.values).keys.toList()),
      );
      expect(cloud.nodes, hasLength(6));
    },
  );

  test(
    '4/5/6/7. offline: menu loads, local edit is instant, survives restart, syncs later',
    () async {
      final a = await terminal('a');
      await a.sync.bootstrap();
      a.link.online = false; // backend stopped for hours
      await a.restart();
      expect(a.sync.isCanonical, isTrue);
      expect(
        a.item(ids['khinkali']!).price,
        2.0,
        reason: 'local menu loads offline',
      );
      await a.setPrice(ids['khinkali']!, 2.2);
      expect(a.item(ids['khinkali']!).price, 2.2, reason: 'usable immediately');
      expect(await a.sync.syncOnce(), isFalse);
      expect(a.entries.single.status, MenuMutationStatus.failedRetryable);
      expect(
        a.item(ids['khinkali']!).price,
        2.2,
        reason: 'offline never reverts',
      );
      await a.restart(); // POS / Windows restart while offline
      expect(a.entries.single.expectedRevision, 1);
      expect(a.item(ids['khinkali']!).price, 2.2);
      a.link.online = true;
      expect(await a.sync.syncOnce(), isTrue);
      expect(cloud.nodes[ids['khinkali']]!['price'], 2.2);
      expect(cloud.nodes[ids['khinkali']]!['revision'], 2);
      expect(a.entries.single.status, MenuMutationStatus.synced);
      expect(a.sync.state!.nodes[ids['khinkali']]!.revision, 2);
    },
  );

  test('10. Dashboard edit reaches a connected POS through catch-up', () async {
    final a = await terminal('a');
    await a.sync.bootstrap();
    cloud.ownerEdit('ITEM', ids['khachapuri']!, {'price': 20.0});
    await a.sync.syncOnce();
    expect(a.item(ids['khachapuri']!).price, 20.0);
    expect(
      a.entries,
      isEmpty,
      reason: 'a Cloud change is never journaled as local',
    );
  });

  test(
    '12. two terminals edit different items concurrently: both accepted',
    () async {
      final a = await terminal('a');
      final b = await terminal('b');
      await a.sync.bootstrap();
      await b.sync.bootstrap();
      await a.setPrice(ids['khinkali']!, 2.2);
      await b.setPrice(ids['khachapuri']!, 19.5);
      await a.sync.syncOnce();
      await b.sync.syncOnce();
      await a.sync.syncOnce();
      for (final t in [a, b]) {
        expect(t.item(ids['khinkali']!).price, 2.2);
        expect(t.item(ids['khachapuri']!).price, 19.5);
        expect(t.sync.conflicts, isEmpty);
      }
    },
  );

  test(
    '13/18. same item from the same base: one accepted, one explicit conflict, nothing lost',
    () async {
      final a = await terminal('a');
      final b = await terminal('b');
      await a.sync.bootstrap();
      await b.sync.bootstrap();
      a.link.online = false;
      b.link.online = false;
      await a.setPrice(
        ids['khinkali']!,
        2.2,
      ); // both offline, cannot coordinate
      await b.setPrice(ids['khinkali']!, 2.1);
      a.link.online = true;
      b.link.online = true;
      await a.sync.syncOnce();
      await b.sync.syncOnce();
      expect(
        cloud.nodes[ids['khinkali']]!['price'],
        2.2,
        reason: 'no silent overwrite',
      );
      final conflict = b.sync.conflicts.single;
      expect(conflict.status, MenuMutationStatus.conflict);
      expect(conflict.conflict!['current']['price'], 2.2);
      expect(conflict.patch['price'], 2.1);
      expect(
        b.item(ids['khinkali']!).price,
        2.1,
        reason: 'the pending change stays local until resolved',
      );
      await b.restart();
      expect(
        b.sync.conflicts.single.mutationId,
        conflict.mutationId,
        reason: 'conflict is durable',
      );
      // Re-apply mine: explicit, against the current revision.
      await b.sync.reapply(conflict.mutationId);
      await b.sync.syncOnce();
      expect(cloud.nodes[ids['khinkali']]!['price'], 2.1);
      expect(b.sync.conflicts, isEmpty);
      await a.sync.syncOnce();
      expect(a.item(ids['khinkali']!).price, 2.1);
    },
  );

  test(
    'use current discards my pending change and shows the Cloud value',
    () async {
      final a = await terminal('a');
      final b = await terminal('b');
      await a.sync.bootstrap();
      await b.sync.bootstrap();
      await a.setPrice(ids['khinkali']!, 2.2);
      await a.sync.syncOnce();
      await b.setPrice(ids['khinkali']!, 2.1);
      await b.sync.syncOnce();
      await b.sync.useCurrent(b.sync.conflicts.single.mutationId);
      expect(b.item(ids['khinkali']!).price, 2.2);
      expect(b.sync.unresolved, isEmpty);
      expect(cloud.nodes[ids['khinkali']]!['price'], 2.2);
    },
  );

  test(
    '14. a lost reply is retried with the same mutation id and applied once',
    () async {
      final a = await terminal('a');
      await a.sync.bootstrap();
      await a.setPrice(ids['khinkali']!, 2.4);
      a.link.loseNextReply = true;
      expect(await a.sync.syncOnce(), isFalse);
      final applied = cloud.applied;
      expect(await a.sync.syncOnce(), isTrue);
      expect(
        cloud.applied,
        applied,
        reason: 'retry is a replay, not a second change',
      );
      expect(cloud.nodes[ids['khinkali']]!['revision'], 2);
      expect(a.entries.single.status, MenuMutationStatus.synced);
    },
  );

  test(
    '15. a terminal that missed a deletion catches the tombstone after reconnect',
    () async {
      final a = await terminal('a');
      final c = await terminal('c');
      await a.sync.bootstrap();
      await c.sync.bootstrap();
      c.link.online = false;
      // Delete the wine (and its glass) on POS A, the way the Admin UI does.
      for (final category in a.menu.values) {
        category.items?.removeWhere((i) => i.id == ids['wine']);
        await category.save();
      }
      await a.sync.captureLocalEdits();
      expect(a.entries.map((e) => [e.entityType, e.operation]).toList(), [
        ['ITEM', 'DELETE'],
      ]);
      await a.sync.syncOnce();
      expect(cloud.tombstones.keys, containsAll([ids['wine'], ids['glass']]));
      expect(c.has(ids['wine']!), isTrue);
      c.link.online = true;
      await c.restart();
      await c.sync.syncOnce();
      expect(c.has(ids['wine']!), isFalse);
      expect(c.has(ids['glass']!), isFalse);
      expect(
        c.entries,
        isEmpty,
        reason: 'a deletion learned from Cloud is not a local delete',
      );
    },
  );

  test('3 and 10 terminals: one protocol, one converged catalog', () async {
    final terminals = [for (var i = 0; i < 10; i++) await terminal('t$i')];
    for (final t in terminals) {
      await t.sync.bootstrap();
      t.link.online = false;
    }
    // All ten edit the same product while none can reach Cloud or each other.
    for (final (i, t) in terminals.indexed) {
      await t.setPrice(ids['khachapuri']!, 20.0 + i);
    }
    for (final t in terminals) {
      t.link.online = true;
      await t.sync.syncOnce();
    }
    expect(terminals.expand((t) => t.sync.conflicts), hasLength(9));
    for (final t in terminals.skip(1)) {
      await t.sync.useCurrent(t.sync.conflicts.single.mutationId);
    }
    for (final t in terminals) {
      await t.sync.syncOnce();
    }
    final shapes = {
      for (final t in terminals)
        jsonEncode(
          CanonicalMenu.readHive(
            t.menu.values,
          ).map((k, v) => MapEntry(k, v.fields)),
        ),
    };
    expect(shapes, hasLength(1));
    expect(cloud.nodes[ids['khachapuri']]!['price'], 20.0);
  });

  test(
    'a POS create syncs parent-first and a Dashboard-disabled product stays disabled',
    () async {
      final a = await terminal('a');
      await a.sync.bootstrap();
      final category = a.menu.values.first;
      final newItem = MenuItemDB.create(
        translationsEn: {'name': 'Lobiani'},
        translationsKa: {'name': 'ლობიანი'},
        price: 9,
      );
      category.items!.add(newItem);
      await category.save();
      await a.sync.captureLocalEdits();
      await a.sync.syncOnce();
      expect(cloud.nodes[newItem.id]!['categoryId'], ids['cat']);
      expect(
        cloud.nodes[newItem.id]!['sortOrder'],
        1,
        reason: 'after the existing wine',
      );
      cloud.ownerEdit('ITEM', ids['khinkali']!, {'enabled': false});
      await a.sync.syncOnce();
      expect(
        a.has(ids['khinkali']!),
        isFalse,
        reason: 'disabled products are not sellable',
      );
      await a.setPrice(ids['khachapuri']!, 21);
      await a.sync.syncOnce();
      expect(cloud.nodes[ids['khinkali']]!['enabled'], isFalse);
      expect(a.entries.every((e) => !e.patch.containsKey('enabled')), isTrue);
    },
  );

  test(
    'an interrupted projection write is never journaled as deletes',
    () async {
      final a = await terminal('a');
      await a.sync.bootstrap();
      // Crash between clearing and refilling the operational menu.
      await a.state.put('rebuilding', '1');
      await a.menu.clear();
      await a.restart();
      await a.sync.captureLocalEdits();
      expect(a.entries, isEmpty);
      expect(a.item(ids['khinkali']!).price, 2.0);
    },
  );

  test(
    'a POS with a different local menu is not overwritten without an explicit adopt',
    () async {
      final a = await terminal('a');
      await a.menu.add(
        MenuCategoryDB.create(
          slug: 'local',
          translationsEn: {'name': 'Local'},
          translationsKa: {'name': 'ლოკალური'},
          items: [],
        ),
      );
      expect(await a.sync.bootstrap(), MenuSyncMode.adoptionBlocked);
      expect(a.menu.values.single.slug, 'local');
      expect(await a.sync.bootstrap(adopt: true), MenuSyncMode.canonical);
      expect(a.has(ids['khinkali']!), isTrue);
      expect(a.entries, isEmpty);
    },
  );

  test(
    '24. an established POS Venue stays legacy: nothing replaced, nothing journaled',
    () async {
      final legacyCloud = FakeMenuCloud(venue, authority: 'POS');
      final a = await terminal('a', legacyCloud);
      await a.menu.add(
        MenuCategoryDB.create(
          slug: 'vankisi',
          translationsEn: {'name': 'Beer'},
          translationsKa: {'name': 'ლუდი'},
          items: [],
        ),
      );
      expect(await a.sync.bootstrap(), MenuSyncMode.legacy);
      expect(a.sync.isCanonical, isFalse);
      expect(a.menu.values.single.slug, 'vankisi');
      await a.sync.captureLocalEdits();
      expect(await a.sync.syncOnce(), isFalse);
      expect(a.entries, isEmpty);
    },
  );

  test(
    'the real POS Admin write path is journaled after the local commit',
    () async {
      final a = await terminal('a');
      await a.sync.bootstrap();
      DatabaseCore.menuBox = a.menu;
      DatabaseCore.settingsBox = await Hive.openBox(
        'admin_settings',
        path: a.dir.path,
      );
      DatabaseCore.auditLogBox = await Hive.openBox(
        'admin_audit',
        path: a.dir.path,
      );
      await DatabaseCore.settingsBox!.put(
        'currentDate',
        '2026-09-28T00:00:00.000',
      );
      a.link.online = false;
      final ok = await MenuRepository.addItemToCategory(
        categoryIndex: 0,
        nameEn: 'Churchkhela',
        nameKa: 'ჩურჩხელა',
        price: 4,
        actorId: 'nino',
      );
      expect(ok, isTrue);
      await a.sync.captureLocalEdits();
      final created = a.entries.single;
      expect(created.operation, 'UPSERT');
      expect(created.patch['nameEn'], 'Churchkhela');
      a.link.online = true;
      await a.sync.syncOnce();
      expect(cloud.nodes[created.entityId]!['price'], 4.0);
      DatabaseCore.menuBox = null;
      DatabaseCore.settingsBox = null;
      DatabaseCore.auditLogBox = null;
    },
  );

  test(
    '21/22. open and historical lines keep captured prices; new lines use the new price',
    () async {
      final a = await terminal('a');
      await a.sync.bootstrap();
      final lines = await Hive.openBox<OrderItem>(
        '${a.name}_lines',
        path: a.dir.path,
      );
      OrderItem lineFrom(MenuItemDB item) => OrderItem(
        itemKey: item.getName('en'),
        itemName: item.getName('ka'),
        unitPrice: item.price!,
        quantity: 2,
        total: item.price! * 2,
        menuItemId: item.id,
      );
      await lines.put('open', lineFrom(a.item(ids['khinkali']!)));
      cloud.ownerEdit('ITEM', ids['khinkali']!, {
        'price': 2.5,
        'nameKa': 'ხინკალი ქალაქური',
      });
      await a.sync.syncOnce();
      expect(a.item(ids['khinkali']!).price, 2.5);
      expect(lines.get('open')!.unitPrice, 2.0, reason: 'no silent repricing');
      expect(lines.get('open')!.itemName, 'ხინკალი');
      await lines.put('new', lineFrom(a.item(ids['khinkali']!)));
      expect(lines.get('new')!.unitPrice, 2.5);
      // Deleting the product later never rewrites or orphans its history.
      cloud.mutate({
        'mutationId': const Uuid().v4(),
        'entityType': 'ITEM',
        'operation': 'DELETE',
        'entityId': ids['khinkali'],
        'expectedRevision': cloud.nodes[ids['khinkali']]!['revision'],
      });
      await a.sync.syncOnce();
      expect(a.has(ids['khinkali']!), isFalse);
      expect(lines.get('open')!.unitPrice, 2.0);
      expect(lines.get('open')!.menuItemId, ids['khinkali']);
    },
  );
}
