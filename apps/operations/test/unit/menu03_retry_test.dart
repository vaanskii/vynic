import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';

import 'canonical_menu_sync_test.dart' show FakeLink, FakeMenuCloud, Terminal;

class RetryLink extends FakeLink {
  RetryLink(super.cloud);
  bool legacy = false;
  int catalogs = 0;
  Completer<void>? entered, release;
  @override
  Future<MenuTransportResult> catalog() async {
    catalogs++;
    return super.catalog();
  }

  @override
  Future<MenuTransportResult> mutate(Map<String, Object?> m) async {
    if (legacy) {
      return const MenuTransportResult(409, {
        'code': 'MUTATION_RESULT_UNAVAILABLE',
        'resyncRequired': true,
      });
    }
    final response = await super.mutate(m);
    if (release != null) {
      entered!.complete();
      await release!.future;
      release = null;
    }
    return response;
  }
}

void main() {
  const venue = 'menu03-synthetic';
  const cat = '40000000-0000-4000-8000-000000000001';
  const item = '40000000-0000-4000-8000-000000000002';
  const other = '40000000-0000-4000-8000-000000000003';
  late Directory dir;
  late FakeMenuCloud cloud;
  late RetryLink link;
  late Terminal terminal;

  Future<void> price(String id, double value) => terminal.sync.local.edit((
    draft,
  ) async {
    for (final c in draft.values) {
      for (final i in [
        ...?c.items,
        for (final s in c.subcategories ?? <MenuSubcategoryDB>[]) ...s.items,
      ]) {
        if (i.id == id) i.price = value;
      }
    }
    await draft.commit();
  });
  setUpAll(() {
    if (!Hive.isAdapterRegistered(5))
      Hive.registerAdapter(MenuCategoryDBAdapter());
    if (!Hive.isAdapterRegistered(6))
      Hive.registerAdapter(MenuSubcategoryDBAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MenuItemDBAdapter());
    if (!Hive.isAdapterRegistered(8))
      Hive.registerAdapter(MenuVariantDBAdapter());
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic_menu03_unit_');
    cloud = FakeMenuCloud(venue)
      ..ownerEdit('CATEGORY', cat, {
        'slug': 'menu03',
        'nameKa': 'Synthetic',
        'nameEn': 'Synthetic',
      })
      ..ownerEdit('ITEM', item, {
        'categoryId': cat,
        'nameKa': 'Item',
        'nameEn': 'Item',
        'price': 10.0,
      })
      ..ownerEdit('ITEM', other, {
        'categoryId': cat,
        'nameKa': 'Other',
        'nameEn': 'Other',
        'price': 20.0,
      });
    link = RetryLink(cloud);
    terminal = await Terminal('menu03', dir, link, venue).open();
    await terminal.sync.bootstrap();
  });
  tearDown(() async {
    await terminal.sync.close();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test(
    'lost ACK + disk reopen + later Cloud edit converges with pending independent edit',
    () async {
      await price(item, 12);
      await price(other, 21);
      final ids = terminal.entries.map((e) => e.mutationId).toList();
      link.loseNextReply = true;
      expect(await terminal.sync.syncOnce(), isFalse);
      final original = jsonDecode(jsonEncode(cloud.accepted[ids.first])) as Map;
      cloud.ownerEdit('ITEM', item, {'price': 13.0});
      await terminal.restart();
      expect(terminal.entries.map((e) => e.mutationId), ids);
      expect(await terminal.sync.syncOnce(), isTrue);
      expect(terminal.sync.unresolved, isEmpty);
      expect(terminal.sync.conflicts, isEmpty);
      expect(terminal.item(item).price, 13);
      expect(terminal.item(other).price, 21);
      expect(terminal.sync.state!.sequence, cloud.sequence);
      expect(cloud.accepted[ids.first], original);
      final applied = cloud.applied;
      expect(await terminal.sync.syncOnce(), isTrue);
      expect(cloud.applied, applied);
    },
  );

  test(
    'same-entity successor created during retry remains pending; real concurrent edit stays an explicit conflict',
    () async {
      await price(item, 12);
      link.loseNextReply = true;
      expect(await terminal.sync.syncOnce(), isFalse);
      final originalId = terminal.entries.single.mutationId;
      cloud.ownerEdit('ITEM', item, {'price': 13.0});
      await terminal.restart();
      link.entered = Completer<void>();
      link.release = Completer<void>();
      final retry = terminal.sync.syncOnce();
      await link.entered!.future;
      await price(item, 14);
      final successorId = terminal.entries.last.mutationId;
      link.release!.complete();
      expect(await retry, isTrue);
      expect(terminal.entries.first.mutationId, originalId);
      expect(terminal.entries.first.status, MenuMutationStatus.synced);
      expect(terminal.sync.unresolved.single.mutationId, successorId);
      expect(
        terminal.sync.unresolved.single.status,
        MenuMutationStatus.pending,
      );
      expect(terminal.sync.unresolved.single.expectedRevision, 2);
      expect(terminal.item(item).price, 14);
      expect(await terminal.sync.syncOnce(), isTrue);
      expect(terminal.sync.conflicts.single.mutationId, successorId);
      expect(terminal.sync.conflicts.single.conflict!['currentRevision'], 3);
      await terminal.sync.useCurrent(successorId);
      expect(terminal.item(item).price, 13);
    },
  );

  test(
    'historical UPSERT ACK cannot resurrect a later deletion already covered by feed',
    () {
      final current = CanonicalMenu(venueId: venue, sequence: 10);
      current.applyAccepted({
        'entityId': item,
        'entityType': 'ITEM',
        'sequence': 4,
        'revision': 2,
        'deleted': false,
        'entity': {'id': item, 'revision': 2, 'price': 12},
      });
      expect(current.nodes.containsKey(item), isFalse);
      expect(current.sequence, 10);
    },
  );

  test(
    'historical missing DELETE cannot remove a subsequently created node',
    () {
      final current = CanonicalMenu.fromSnapshot(cloud.catalog().body!);
      current.applyAccepted({
        'entityId': item,
        'entityType': 'ITEM',
        'sequence': 0,
        'revision': 0,
        'deleted': true,
        'entity': null,
      });
      expect(current.nodes[item]!.fields['price'], 10);
      expect(current.sequence, cloud.sequence);
    },
  );

  test(
    'legacy accepted-without-result forces full resync and retains original IDs for explicit review',
    () async {
      await price(item, 12);
      await price(item, 14);
      final ids = terminal.entries.map((e) => e.mutationId).toList();
      cloud.ownerEdit('ITEM', item, {'price': 13.0});
      link.legacy = true;
      final before = link.catalogs;
      expect(await terminal.sync.syncOnce(), isTrue);
      expect(link.catalogs, before + 1);
      expect(terminal.sync.state!.nodes[item]!.fields['price'], 13);
      expect(terminal.sync.unresolved.map((e) => e.mutationId), ids);
      expect(terminal.entries.first.lastError, 'MUTATION_RESULT_UNAVAILABLE');
      expect(terminal.entries.last.status, MenuMutationStatus.pending);
      expect(terminal.item(item).price, 14);
      await terminal.restart();
      expect(terminal.sync.unresolved.map((e) => e.mutationId), ids);
    },
  );
}
