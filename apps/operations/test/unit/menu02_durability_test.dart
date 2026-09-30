import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/menu_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/menu/pos_menu_sync_service.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';

import 'canonical_menu_sync_test.dart' show FakeLink, FakeMenuCloud;

/// Audit delivery is outside this proof. Block every actual HTTP client;
/// canonical transport is the deterministic fake Cloud below.
class Menu02NoHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('MENU02 proof permits no outbound HTTP');
}

class PausedLink extends FakeLink {
  PausedLink(super.cloud);
  Completer<void>? entered;
  Completer<void>? release;
  Completer<void>? mutationEntered;
  Completer<void>? mutationRelease;
  Map<String, Object?>? sent;
  void pauseMutation() {
    mutationEntered = Completer<void>();
    mutationRelease = Completer<void>();
  }

  @override
  Future<MenuTransportResult> mutate(Map<String, Object?> mutation) async {
    sent = Map.of(mutation);
    final response = await super.mutate(mutation);
    if (mutationRelease != null) {
      mutationEntered!.complete();
      await mutationRelease!.future;
      mutationRelease = null;
    }
    return response;
  }

  void pausePull() {
    entered = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<MenuTransportResult> changes(int since) async {
    final response = await super.changes(since);
    if (release != null) {
      entered!.complete();
      await release!.future;
      release = null;
    }
    return response;
  }
}

/// Real Hive delegate; faults interrupt I/O without changing production code.
class FaultBox<T> extends UpdateTrackedBox<T> {
  FaultBox(super.inner);
  Future<void> Function(String checkpoint)? fault;
  Future<R> _io<R>(String point, Future<R> Function() operation) async {
    await fault?.call('$point:before');
    final result = await operation();
    await fault?.call('$point:after');
    return result;
  }

  @override
  Future<void> put(dynamic key, T value) =>
      _io('put:$key', () => super.put(key, value));
  @override
  Future<void> delete(dynamic key) =>
      _io('delete:$key', () => super.delete(key));
  @override
  Future<void> putAll(Map<dynamic, T> values) =>
      _io('putAll', () => super.putAll(values));
  @override
  Future<int> clear() => _io('clear', super.clear);
  @override
  Future<Iterable<int>> addAll(Iterable<T> values) =>
      _io('addAll', () => super.addAll(values));
  @override
  Future<void> flush() => _io('flush', super.flush);
}

void main() {
  late Directory dir;
  late FaultBox<MenuCategoryDB> menu;
  late FaultBox<String> state;
  late Box<String> rawJournal;
  late FaultBox<String> journal;
  late FakeMenuCloud cloud;
  late PausedLink link;
  late PosMenuSync sync;
  const venue = 'menu02-synthetic-venue';
  const cat = '10000000-0000-4000-8000-000000000001';
  const item = '10000000-0000-4000-8000-000000000002';
  const other = '10000000-0000-4000-8000-000000000003';

  Future<void> open() async {
    state = FaultBox(
      await Hive.openBox<String>('menu02_state', path: dir.path),
    );
    rawJournal = await Hive.openBox<String>('menu02_journal', path: dir.path);
    journal = FaultBox(rawJournal);
    menu = FaultBox(
      await Hive.openBox<MenuCategoryDB>('menu02_menu', path: dir.path),
    );
    DatabaseCore.auditLogBox = await Hive.openBox(
      'menu02_audit',
      path: dir.path,
    );
    DatabaseCore.menuBox = menu;
    DatabaseCore.menuCanonicalBox = state;
    DatabaseCore.menuJournalBox = journal;
    sync = PosMenuSync(
      stateBox: state,
      journalBox: journal,
      menuBox: menu,
      transport: link,
      venueId: () => venue,
    );
  }

  Future<void> restart() async {
    await sync.close();
    await menu.close();
    await state.close();
    await rawJournal.close();
    await open();
    await sync.rebuildProjection();
  }

  Future<bool> price(double value) => MenuRepository.updateItemInCategory(
    categoryIndex: 0,
    itemIndex: 0,
    nameEn: 'Synthetic item',
    nameKa: 'Synthetic item',
    price: value,
  );

  setUpAll(() {
    HttpOverrides.global = Menu02NoHttp();
    if (!Hive.isAdapterRegistered(5))
      Hive.registerAdapter(MenuCategoryDBAdapter());
    if (!Hive.isAdapterRegistered(6))
      Hive.registerAdapter(MenuSubcategoryDBAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MenuItemDBAdapter());
    if (!Hive.isAdapterRegistered(8))
      Hive.registerAdapter(MenuVariantDBAdapter());
  });
  tearDownAll(() {
    HttpOverrides.global = null;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic_menu02_');
    cloud = FakeMenuCloud(venue)
      ..ownerEdit('CATEGORY', cat, {
        'slug': 'synthetic',
        'nameEn': 'Synthetic',
        'nameKa': 'Synthetic',
      })
      ..ownerEdit('ITEM', item, {
        'categoryId': cat,
        'nameEn': 'Synthetic item',
        'nameKa': 'Synthetic item',
        'price': 10.0,
      })
      ..ownerEdit('ITEM', other, {
        'categoryId': cat,
        'nameEn': 'Other',
        'nameKa': 'Other',
        'price': 20.0,
        'sortOrder': 1,
      });
    link = PausedLink(cloud);
    await open();
    await sync.bootstrap();
  });
  tearDown(() async {
    await sync.close();
    await Hive.close();
    DatabaseCore.auditLogBox = null;
    DatabaseCore.menuBox = null;
    DatabaseCore.menuCanonicalBox = null;
    DatabaseCore.menuJournalBox = null;
    await dir.delete(recursive: true);
  });

  test(
    'MENU02 original race: acknowledged repository edit survives paused pull',
    () async {
      link.pausePull();
      final pulling = sync.syncOnce();
      await link.entered!.future;
      expect(await price(12), isTrue);
      final capture = sync.captureLocalEdits();
      link.release!.complete();
      await pulling;
      await capture;
      expect(menu.values.single.items!.first.price, 12);
      expect(sync.unresolved.single.patch['price'], 12);
      await restart();
      expect(menu.values.single.items!.first.price, 12);
    },
  );

  test(
    'MENU02 original reapply gap: replacement failure retains durable intent',
    () async {
      expect(await price(12), isTrue);
      await sync.captureLocalEdits();
      cloud.ownerEdit('ITEM', item, {'price': 11.0});
      await sync.syncOnce();
      final oldId = sync.conflicts.single.mutationId;
      journal.fault = (point) async {
        if (point.endsWith(':before'))
          throw StateError('simulated process death');
      };
      await expectLater(sync.reapply(oldId), throwsStateError);
      journal.fault = null;
      await restart();
      expect(sync.unresolved, hasLength(1));
      expect(sync.unresolved.single.patch['price'], 12);
      expect(menu.values.single.items!.first.price, 12);
    },
  );
  for (final point in [
    ('A', 'state', 'put:localCommit:before'),
    ('B', 'state', 'put:localCommit:after'),
    ('B', 'state', 'flush:after'),
    ('B', 'journal', 'put:000000000001:before'),
    ('C', 'journal', 'put:000000000001:after'),
    ('C', 'journal', 'flush:after'),
    ('C', 'state', 'put:state:before'),
    ('C', 'state', 'put:state:after'),
    ('C', 'state', 'put:generation:after'),
    ('C', 'state', 'put:localProtocolVersion:after'),
    ('E', 'state', 'put:rebuilding:after'),
    ('E', 'menu', 'clear:before'),
    ('E', 'menu', 'clear:after'),
    ('E', 'menu', 'addAll:before'),
    ('E', 'menu', 'addAll:after'),
    ('E', 'menu', 'flush:after'),
    ('E', 'state', 'put:baseline:before'),
    ('E', 'state', 'put:baseline:after'),
    ('E', 'state', 'delete:rebuilding:after'),
    ('E', 'state', 'delete:localCommit:before'),
    ('E', 'state', 'delete:localCommit:after'),
  ]) {
    test('MENU02 ${point.$1}: ${point.$2} ${point.$3} restart', () async {
      var fired = false;
      Future<void> crash(String checkpoint) async {
        if (!fired && checkpoint == point.$3) {
          fired = true;
          throw StateError('simulated process death at $checkpoint');
        }
      }

      switch (point.$2) {
        case 'state':
          state.fault = crash;
        case 'journal':
          journal.fault = crash;
        case 'menu':
          menu.fault = crash;
      }
      expect(
        await price(12),
        isFalse,
        reason: 'no false UI success on storage failure',
      );
      expect(fired, isTrue);
      state.fault = null;
      journal.fault = null;
      menu.fault = null;
      final frame = state.get(MenuLocalStore.commitKey);
      final beforeIds = frame == null
          ? sync.unresolved.map((e) => e.mutationId).toList()
          : (jsonDecode(frame)['puts'] as List)
                .map((e) => e['mutationId'])
                .toList();
      await restart();
      if (point.$1 == 'A') {
        expect(menu.values.single.items!.first.price, 10);
        expect(sync.unresolved, isEmpty);
      } else {
        expect(menu.values.single.items!.first.price, 12);
        expect(sync.unresolved, hasLength(1));
        expect(sync.unresolved.map((e) => e.mutationId), beforeIds);
        await restart();
        expect(await sync.captureLocalEdits(), 0);
        expect(sync.unresolved.map((e) => e.mutationId), beforeIds);
      }
    });
  }

  test(
    'MENU02 D: edit completes during mutation ACK wait and rebases',
    () async {
      await price(12);
      link.pauseMutation();
      final syncing = sync.syncOnce();
      await link.mutationEntered!.future;
      final sentId = link.sent!['mutationId'];
      expect(await price(14), isTrue);
      expect(
        link.mutationRelease!.isCompleted,
        isFalse,
        reason: 'no network wait',
      );
      expect(sync.unresolved, hasLength(2));
      link.mutationRelease!.complete();
      await syncing;
      expect(menu.values.single.items!.first.price, 14);
      expect(sync.journal.all().first.mutationId, sentId);
      expect(sync.unresolved.single.expectedRevision, 2);
      final laterId = sync.unresolved.single.mutationId;
      await restart();
      await sync.syncOnce();
      expect(cloud.nodes[item]!['price'], 14);
      expect(sync.journal.all().last.mutationId, laterId);
      expect(sync.conflicts, isEmpty);
    },
  );

  test(
    'MENU02 F: lost ACK plus restart retries exact durable ID once',
    () async {
      await price(12);
      final id = sync.unresolved.single.mutationId;
      link.loseNextReply = true;
      expect(await sync.syncOnce(), isFalse);
      final applied = cloud.applied;
      await restart();
      expect(sync.unresolved.single.mutationId, id);
      await sync.syncOnce();
      expect(cloud.applied, applied);
      expect(sync.journal.all().single.mutationId, id);
      expect(sync.journal.all().single.status, MenuMutationStatus.synced);
    },
  );

  for (final conflict in [false, true]) {
    test(
      'MENU02 G/C: ${conflict ? "conflict" : "accepted ACK"} before state-write interruption',
      () async {
        await price(12);
        if (conflict) cloud.ownerEdit('ITEM', item, {'price': 11.0});
        final id = sync.unresolved.single.mutationId;
        state.fault = (point) async {
          if (point == 'put:state:before')
            throw StateError('state interruption');
        };
        await expectLater(sync.syncOnce(), throwsStateError);
        state.fault = null;
        await restart();
        expect(sync.journal.all().single.mutationId, id);
        expect(
          sync.journal.all().single.status,
          conflict ? MenuMutationStatus.conflict : MenuMutationStatus.synced,
        );
        expect(menu.values.single.items!.first.price, 12);
        if (conflict)
          expect(sync.conflicts.single.conflict!['current']['price'], 11);
        else
          expect(sync.state!.nodes[item]!.fields['price'], 12);
      },
    );
  }

  for (final point in ['put:000000000001:after', 'put:000000000002:before']) {
    test(
      'MENU02 H: reapply $point retains replacement and successor rebases',
      () async {
        await price(12);
        await price(14);
        cloud.ownerEdit('ITEM', item, {'price': 11.0});
        await sync.syncOnce();
        final old = sync.conflicts.single;
        journal.fault = (checkpoint) async {
          if (checkpoint == point) throw StateError('replacement interruption');
        };
        await expectLater(sync.reapply(old.mutationId), throwsStateError);
        final frame = jsonDecode(state.get(MenuLocalStore.commitKey)!);
        final replacementId = frame['puts'][0]['mutationId'];
        journal.fault = null;
        await restart();
        expect(sync.unresolved, hasLength(2));
        expect(sync.unresolved.first.mutationId, replacementId);
        expect(replacementId, isNot(old.mutationId));
        expect(sync.unresolved.every((e) => e.expectedRevision == 2), isTrue);
        expect(menu.values.single.items!.first.price, 14);
        await sync.syncOnce();
        expect(cloud.nodes[item]!['price'], 14);
        expect(sync.conflicts, isEmpty);
      },
    );
  }

  test(
    'MENU02 I: interrupted use-current cannot accidentally reapply a successor',
    () async {
      await price(12);
      await price(14);
      cloud.ownerEdit('ITEM', item, {'price': 11.0});
      await sync.syncOnce();
      final conflict = sync.conflicts.single.mutationId;
      journal.fault = (point) async {
        if (point == 'delete:000000000001:after')
          throw StateError('discard interruption');
      };
      await expectLater(sync.useCurrent(conflict), throwsStateError);
      journal.fault = null;
      await restart();
      expect(sync.unresolved, isEmpty);
      expect(menu.values.single.items!.first.price, 11);
      expect(await sync.captureLocalEdits(), 0);
      await sync.syncOnce();
      expect(cloud.nodes[item]!['price'], 11);
    },
  );

  test(
    'MENU02 J: rapid same-entity writes stay ordered across restart and rebase',
    () async {
      final results = await Future.wait([
        for (var i = 1; i <= 12; i++) price(10.0 + i),
      ]);
      expect(results.every((ok) => ok), isTrue);
      final ids = sync.unresolved.map((e) => e.mutationId).toList();
      expect(ids.toSet(), hasLength(12));
      expect(
        sync.unresolved.map((e) => e.seq),
        List.generate(12, (i) => i + 1),
      );
      expect(menu.values.single.items!.first.price, 22);
      await restart();
      await sync.syncOnce();
      expect(cloud.nodes[item]!['price'], 22);
      expect(sync.conflicts, isEmpty);
      expect(sync.journal.all().map((e) => e.mutationId), ids);
    },
  );

  test(
    'MENU02 K: independent entities do not create a global revision conflict',
    () async {
      expect(
        await Future.wait([
          price(12),
          MenuRepository.updateItemInCategory(
            categoryIndex: 0,
            itemIndex: 1,
            nameEn: 'Other',
            nameKa: 'Other',
            price: 24,
          ),
        ]),
        [true, true],
      );
      await sync.syncOnce();
      expect(sync.conflicts, isEmpty);
      expect(cloud.nodes[item]!['price'], 12);
      expect(cloud.nodes[other]!['price'], 24);
    },
  );

  test('MENU02 stale projection generation is refused', () async {
    final oldState = sync.state!;
    final generation = sync.local.generation;
    await price(12);
    await expectLater(
      sync.local.run(
        () => sync.local.commit(oldState, expectedGeneration: generation),
      ),
      throwsStateError,
    );
    expect(menu.values.single.items!.first.price, 12);
    expect(sync.unresolved, hasLength(1));
  });

  test(
    'MENU02 external restore shares queue; nested migration journals no restored rows',
    () async {
      await price(12);
      final id = sync.unresolved.single.mutationId;
      final entered = Completer<void>();
      final release = Completer<void>();
      final restoring = PosMenuSyncService.instance.externalMenuWrite(() async {
        await menu.clear();
        await menu.add(
          MenuCategoryDB(
            slug: 'old-backup',
            translationsEn: {},
            translationsKa: {},
            items: [
              MenuItemDB(translationsEn: {}, translationsKa: {}, price: 99),
            ],
          ),
        );
        expect(await MenuRepository.ensureStableMenuIds(), 2);
        entered.complete();
        await release.future;
      });
      await entered.future;
      final queued = price(14);
      release.complete();
      await restoring;
      expect(await queued, isTrue);
      expect(sync.unresolved.first.mutationId, id);
      expect(sync.unresolved, hasLength(2));
      expect(menu.values.single.items!.first.price, 14);
      expect(menu.values.single.id, cat);
    },
  );

  test(
    'MENU02 existing-format pending fixture migrates without duplicate IDs',
    () async {
      await price(12);
      final old =
          jsonDecode(
                File(
                  'test/fixtures/menu02_legacy_journal.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      await journal.put('000000000001', jsonEncode(old));
      await journal.flush();
      final id = old['mutationId'];
      await state.delete(MenuLocalStore.versionKey);
      await state.delete(MenuLocalStore.generationKey);
      await state.put(MenuLocalStore.baselineKey, sync.state!.toJsonString());
      await state.flush();
      await restart();
      await sync.local.initialize();
      expect(sync.unresolved.single.mutationId, id);
      expect(await sync.captureLocalEdits(), 0);
      expect(
        state.get(MenuLocalStore.versionKey),
        '${MenuLocalStore.protocolVersion}',
      );
      expect(menu.values.single.items!.first.price, 12);
    },
  );

  test(
    'MENU02 callback queued by restore cannot retain external write privileges',
    () async {
      final release = Completer<void>();
      late Future<bool> delayedEdit;
      await sync.local.external(() async {
        delayedEdit = release.future.then((_) => price(12));
      });
      release.complete();
      expect(await delayedEdit, isTrue);
      expect(sync.unresolved.single.patch['price'], 12);
      expect(menu.values.single.items!.first.price, 12);
    },
  );

  test(
    'MENU02 journal cleanup retains unresolved and 50 accepted diagnostics',
    () async {
      await sync.journal.append(
        mutationId: 'pending',
        venueId: venue,
        entityType: 'ITEM',
        operation: 'UPSERT',
        entityId: item,
        expectedRevision: 1,
        patch: {'price': 12},
      );
      for (var i = 0; i < 60; i++) {
        final entry = await sync.journal.append(
          mutationId: 'synced-$i',
          venueId: venue,
          entityType: 'ITEM',
          operation: 'UPSERT',
          entityId: other,
          expectedRevision: i + 1,
          patch: {'price': 20},
        );
        entry.status = MenuMutationStatus.synced;
        await sync.journal.save(entry);
      }
      await sync.journal.compact();
      expect(sync.journal.all(), hasLength(51));
      expect(sync.unresolved.single.mutationId, 'pending');
    },
  );
  test(
    'MENU02 all Admin node writers commit durable intent before success',
    () async {
      expect(
        await MenuRepository.addCategory(
          slug: 'new',
          nameEn: 'New',
          nameKa: 'New',
        ),
        isTrue,
      );
      final catId = menu.values.last.id;
      expect(
        await MenuRepository.updateCategory(
          index: 1,
          slug: 'renamed',
          nameEn: 'Renamed',
          nameKa: 'Renamed',
        ),
        isTrue,
      );
      expect(menu.values.last.id, catId);
      expect(
        await MenuRepository.addSubcategory(
          categoryIndex: 1,
          slug: 'sub',
          nameEn: 'Sub',
          nameKa: 'Sub',
        ),
        isTrue,
      );
      expect(
        await MenuRepository.addItemToSubcategory(
          categoryIndex: 1,
          subcategoryIndex: 0,
          nameEn: 'Variant item',
          nameKa: 'Variant item',
          variants: [MenuVariantDB.create(size: 1, price: 5)],
        ),
        isTrue,
      );
      final variant =
          menu.values.last.subcategories!.first.items.single.variants!.single;
      expect(
        await MenuRepository.updateItemInSubcategory(
          categoryIndex: 1,
          subcategoryIndex: 0,
          itemIndex: 0,
          nameEn: 'Updated',
          nameKa: 'Updated',
          variants: [MenuVariantDB(id: variant.id, size: 2, price: 6)],
        ),
        isTrue,
      );
      expect(
        await MenuRepository.updateSubcategory(
          categoryIndex: 1,
          subcategoryIndex: 0,
          slug: 'sub-renamed',
          nameEn: 'Sub renamed',
          nameKa: 'Sub renamed',
        ),
        isTrue,
      );
      expect(
        await MenuRepository.deleteItemFromSubcategory(
          categoryIndex: 1,
          subcategoryIndex: 0,
          itemIndex: 0,
        ),
        isTrue,
      );
      expect(
        await MenuRepository.deleteSubcategory(
          categoryIndex: 1,
          subcategoryIndex: 0,
        ),
        isTrue,
      );
      expect(
        await MenuRepository.addItemToCategory(
          categoryIndex: 1,
          nameEn: 'Direct',
          nameKa: 'Direct',
          price: 3,
        ),
        isTrue,
      );
      expect(
        await MenuRepository.deleteItemFromCategory(
          categoryIndex: 1,
          itemIndex: 0,
        ),
        isTrue,
      );
      expect(await MenuRepository.deleteCategory(1), isTrue);
      expect(sync.unresolved.map((e) => e.entityType).toSet(), {
        'CATEGORY',
        'SUBCATEGORY',
        'ITEM',
        'VARIANT',
      });
      final ids = sync.unresolved.map((e) => e.mutationId).toList();
      await restart();
      expect(sync.unresolved.map((e) => e.mutationId), ids);
      expect(sync.unresolved.last.operation, 'DELETE');
    },
  );

  test(
    'MENU02 bootstrap interrupted before canonical state persists recovers import',
    () async {
      await menu.clear();
      await state.clear();
      await journal.clear();
      state.fault = (point) async {
        if (point == 'put:state:before')
          throw StateError('bootstrap interrupted');
      };
      await expectLater(sync.bootstrap(), throwsStateError);
      state.fault = null;
      await restart();
      expect(sync.isCanonical, isTrue);
      expect(menu.values.single.items!.first.price, 10);
      expect(sync.unresolved, isEmpty);
    },
  );

  test('MENU02 rejects a future local protocol before editing', () async {
    await state.put(MenuLocalStore.versionKey, '999');
    await state.flush();
    await expectLater(sync.local.initialize(), throwsStateError);
    expect(menu.values.single.items!.first.price, 10);
    expect(sync.unresolved, isEmpty);
  });

  test('MENU02 offline latency and full projection rebuild, 500 items', () async {
    for (var i = 2; i < 500; i++) {
      cloud.ownerEdit(
        'ITEM',
        '20000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
        {
          'categoryId': cat,
          'nameEn': 'Synthetic $i',
          'nameKa': 'Synthetic $i',
          'price': 20.0,
          'sortOrder': i,
        },
      );
    }
    await sync.syncOnce();
    link.online = false;
    final networkAttempts = link.mutations;
    final samples = <int>[];
    for (var i = 1; i <= 20; i++) {
      final clock = Stopwatch()..start();
      expect(await price(10.0 + i / 100), isTrue);
      clock.stop();
      samples.add(clock.elapsedMicroseconds);
    }
    expect(link.mutations, networkAttempts);
    expect(sync.unresolved, hasLength(20));
    await state.put(MenuLocalStore.rebuildingKey, '1');
    await state.flush();
    await menu.clear();
    await menu.flush();
    final rebuild = Stopwatch()..start();
    await sync.local.initialize();
    rebuild.stop();
    expect(menu.values.single.items, hasLength(500));
    expect(menu.values.single.items!.first.price, 10.2);
    expect(sync.unresolved, hasLength(20));
    samples.sort();
    // ignore: avoid_print -- structured performance evidence from the test runner
    print(
      '[MENU02_PERF] ${jsonEncode({'items': 500, 'samples': samples.length, 'localEditP50Ms': samples[10] / 1000, 'localEditP95Ms': samples[18] / 1000, 'localEditMaxMs': samples.last / 1000, 'fullProjectionRebuildMs': rebuild.elapsedMicroseconds / 1000, 'pendingEntries': sync.unresolved.length, 'menuNetworkAttemptsDuringEdits': link.mutations - networkAttempts})}',
    );
  });
}
