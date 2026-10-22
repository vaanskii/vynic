import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';

class Menu03RecordedHttp implements MenuSyncTransport {
  Menu03RecordedHttp(this.http, {required this.drop});
  final HttpMenuSyncTransport http;
  bool drop;
  final responses = <Map<String, dynamic>>[];
  final requests = <Map<String, Object?>>[];
  final cursors = <int>[];
  @override
  Future<MenuTransportResult> catalog() => http.catalog();
  @override
  Future<MenuTransportResult> changes(int since) {
    cursors.add(since);
    return http.changes(since);
  }

  @override
  Future<MenuTransportResult> mutate(Map<String, Object?> body) async {
    requests.add(Map.of(body));
    final response = await http.mutate(body);
    expect(response.status, 200);
    responses.add(response.body!);
    if (drop) {
      drop = false;
      return const MenuTransportResult(
        0,
      ); // Real HTTP committed; consumer loses ACK.
    }
    return response;
  }
}

void main() {
  final env = Platform.environment;
  final path = env['MENU03_HIVE_DIR'];
  final fixturePath = env['MENU03_HTTP_FIXTURE'];
  final stage = env['MENU03_POS_STAGE'];
  if (path == null || fixturePath == null || stage == null) {
    test(
      'MENU03 real HTTP process proof',
      () {},
      skip: 'run prove-menu03.py with --flutter',
    );
    return;
  }
  if (!path.startsWith('/private/tmp/vynic_menu03_process_'))
    throw StateError('Disposable Hive directory required');
  test('MENU03 native $stage', () async {
    final fixture =
        jsonDecode(File(fixturePath).readAsStringSync())
            as Map<String, dynamic>;
    final venue = Map<String, dynamic>.from(
      (fixture['venues'] as List).first as Map,
    );
    final ids = Map<String, String>.from(fixture['ids'] as Map);
    Hive.registerAdapter(MenuCategoryDBAdapter());
    Hive.registerAdapter(MenuSubcategoryDBAdapter());
    Hive.registerAdapter(MenuItemDBAdapter());
    Hive.registerAdapter(MenuVariantDBAdapter());
    final state = await Hive.openBox<String>('menu03_state', path: path);
    final journal = await Hive.openBox<String>('menu03_journal', path: path);
    final menu = await Hive.openBox<MenuCategoryDB>('menu03_menu', path: path);
    final http = HttpMenuSyncTransport(
      baseUrl: () => fixture['baseUrl'] as String,
      credential: () => venue['credential'] as String,
    );
    final link = Menu03RecordedHttp(http, drop: stage == 'writer');
    final sync = PosMenuSync(
      stateBox: state,
      journalBox: journal,
      menuBox: menu,
      transport: link,
      venueId: () => venue['venueId'] as String,
    );
    Future<void> price(String id, double value) => sync.local.edit((
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
    double readPrice(String id) => [
      for (final c in menu.values) ...?c.items,
      for (final c in menu.values)
        for (final s in c.subcategories ?? <MenuSubcategoryDB>[]) ...s.items,
    ].firstWhere((i) => i.id == id).price!;
    final writerFile = File('$path/writer.json');
    if (stage == 'writer') {
      expect(await sync.bootstrap(), MenuSyncMode.canonical);
      final cursor = sync.state!.sequence;
      await price(ids['item']!, 12);
      await price(ids['other']!, 21);
      final originalIds = sync.journal.all().map((e) => e.mutationId).toList();
      expect(await sync.syncOnce(), isFalse);
      expect(sync.unresolved, hasLength(2));
      expect(sync.unresolved.first.status, MenuMutationStatus.failedRetryable);
      expect(sync.unresolved.last.status, MenuMutationStatus.pending);
      expect(link.responses.single['revision'], 2);
      await menu.flush();
      await state.flush();
      await journal.flush();
      await writerFile.writeAsString(
        jsonEncode({
          'writerPid': pid,
          'cursor': cursor,
          'mutationIds': originalIds,
          'request': link.requests.single,
          'original': link.responses.single,
          'localPrices': [readPrice(ids['item']!), readPrice(ids['other']!)],
          'checkpoint': 'committed M1 / lost ACK / journal flushed',
        }),
        flush: true,
      );
      await Completer<void>()
          .future; // Orchestrator sends SIGKILL; no Hive.close.
    } else {
      final saved =
          jsonDecode(writerFile.readAsStringSync()) as Map<String, dynamic>;
      expect(pid, isNot(saved['writerPid']));
      await sync.rebuildProjection();
      expect(sync.journal.all().map((e) => e.mutationId), saved['mutationIds']);
      expect(readPrice(ids['item']!), 12);
      expect(readPrice(ids['other']!), 21);
      expect(await sync.syncOnce(), isTrue);
      final ack = link.responses.first;
      final original = Map<String, dynamic>.from(saved['original'] as Map)
        ..remove('duplicate');
      expect(Map<String, dynamic>.from(ack)..remove('duplicate'), original);
      expect(ack['duplicate'], isTrue);
      expect(ack['revision'], 2);
      expect((ack['entity'] as Map)['price'], 12);
      expect(sync.unresolved, isEmpty);
      expect(sync.conflicts, isEmpty);
      expect(readPrice(ids['item']!), 13);
      expect(readPrice(ids['other']!), 21);
      expect(link.cursors.first, saved['cursor']);
      final count = link.requests.length;
      expect(await sync.syncOnce(), isTrue);
      expect(link.requests.length, count);
      await File('$path/reader.json').writeAsString(
        jsonEncode({
          'readerPid': pid,
          'writerPid': saved['writerPid'],
          'originalIds': saved['mutationIds'],
          'requests': link.requests,
          'responses': link.responses,
          'cursors': link.cursors,
          'finalSequence': sync.state!.sequence,
          'finalPrices': [readPrice(ids['item']!), readPrice(ids['other']!)],
          'unresolved': sync.unresolved.length,
          'conflicts': sync.conflicts.length,
          'journalStatuses': sync.journal
              .all()
              .map((e) => e.status.name)
              .toList(),
          'repeatSyncMutationCount': link.requests.length,
        }),
        flush: true,
      );
      await sync.close();
      http.close();
      await Hive.close();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
