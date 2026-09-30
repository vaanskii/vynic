import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';

/// One HTTP exchange with the canonical Menu API. `status == 0` = unreachable.
class MenuTransportResult {
  const MenuTransportResult(this.status, [this.body]);
  final int status;
  final Map<String, dynamic>? body;
  bool get ok => status >= 200 && status < 300;
  String? get code => body?['code'] as String?;
}

abstract class MenuSyncTransport {
  Future<MenuTransportResult> catalog();
  Future<MenuTransportResult> changes(int since);
  Future<MenuTransportResult> mutate(Map<String, Object?> mutation);
}

/// Device-authenticated transport (Device -> Venue; no tenant selector sent).
class HttpMenuSyncTransport implements MenuSyncTransport {
  HttpMenuSyncTransport({
    required this.baseUrl,
    required this.credential,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _http = client ?? http.Client();

  final String Function() baseUrl;
  final String? Function() credential;
  final http.Client _http;
  final Duration timeout;

  Future<MenuTransportResult> _send(
    Future<http.Response> Function() call,
  ) async {
    try {
      final response = await call().timeout(timeout);
      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      } catch (_) {
        body = null;
      }
      return MenuTransportResult(response.statusCode, body);
    } catch (_) {
      return const MenuTransportResult(0);
    }
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'X-POS-Sync-Key': credential() ?? '',
  };

  @override
  Future<MenuTransportResult> catalog() => _send(
    () => _http.get(
      Uri.parse('${baseUrl()}/edge/menu/catalog'),
      headers: _headers,
    ),
  );

  @override
  Future<MenuTransportResult> changes(int since) => _send(
    () => _http.get(
      Uri.parse('${baseUrl()}/edge/menu/changes?since=$since'),
      headers: _headers,
    ),
  );

  @override
  Future<MenuTransportResult> mutate(Map<String, Object?> mutation) => _send(
    () => _http.post(
      Uri.parse('${baseUrl()}/edge/menu/mutations'),
      headers: _headers,
      body: jsonEncode(mutation),
    ),
  );

  void close() => _http.close();
}

enum MenuSyncMode {
  /// Not yet determined (e.g. never reached Cloud); the local menu is used as is.
  unknown,

  /// Established POS Venue in compatibility mode: the local menu stays the
  /// author and reaches Cloud through the legacy full snapshot.
  legacy,

  /// Canonical Cloud Menu with this POS as a local-first projection + editor.
  canonical,

  /// Cloud is canonical but this POS already holds a DIFFERENT local menu.
  /// Nothing is replaced until an operator explicitly adopts the Cloud menu.
  adoptionBlocked,

  /// The stored canonical state belongs to another Venue (re-enrollment).
  venueMismatch,
}

class _Serial {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// Local-first canonical Menu engine. All local writes use MenuLocalStore;
/// this separate network queue never blocks an operator's durable local edit.
class PosMenuSync {
  PosMenuSync({
    required this.stateBox,
    required Box<String> journalBox,
    required this.menuBox,
    required this.transport,
    required this.venueId,
    String Function()? newMutationId,
  }) : local = MenuLocalStore.attach(
         menuBox: menuBox,
         stateBox: stateBox,
         journalBox: journalBox,
         venueId: venueId,
         newMutationId: newMutationId,
       ),
       _newId = newMutationId ?? CanonicalMenu.newMutationId;

  final Box<String> stateBox;
  final Box<MenuCategoryDB> menuBox;
  final MenuSyncTransport transport;
  final String? Function() venueId;
  final String Function() _newId;
  final MenuLocalStore local;
  final _Serial _network = _Serial();
  MenuMutationJournal get journal => local.journal;
  Stream<void> get projected => local.projected;
  CanonicalMenu? get state => local.state;

  MenuSyncMode get mode {
    final current = state;
    if (current != null) {
      return current.venueId == venueId()
          ? MenuSyncMode.canonical
          : MenuSyncMode.venueMismatch;
    }
    return switch (stateBox.get('mode')) {
      'legacy' => MenuSyncMode.legacy,
      'adoptionBlocked' => MenuSyncMode.adoptionBlocked,
      _ => MenuSyncMode.unknown,
    };
  }

  bool get isCanonical => mode == MenuSyncMode.canonical;
  List<MenuMutationEntry> get unresolved =>
      journal.unresolved().where((e) => e.venueId == venueId()).toList();
  List<MenuMutationEntry> get conflicts => unresolved
      .where(
        (e) =>
            e.status == MenuMutationStatus.conflict ||
            e.status == MenuMutationStatus.rejected,
      )
      .toList();

  Future<int> captureLocalEdits() => local.run(local.capture);
  Future<void> rebuildProjection() => local.run(() async {
    if (!isCanonical) return;
    await local.capture();
    await local.commit(state!, expectedGeneration: local.generation);
  });
  Future<void> reprojectDiscardingExternal() => local.run(() async {
    if (isCanonical) {
      await local.commit(state!, expectedGeneration: local.generation);
    }
  });

  /// Fresh installs import; existing differing menus require explicit adoption.
  /// Check the LIVE local menu after the request; never adopt a stale snapshot
  /// of the local menu taken before a network wait.
  Future<MenuSyncMode> bootstrap({bool adopt = false}) =>
      _network.run(() async {
        final before = mode;
        if (before == MenuSyncMode.venueMismatch) return before;
        if (before == MenuSyncMode.canonical) {
          await local.initialize();
          return before;
        }
        final venue = venueId();
        if (venue == null) return MenuSyncMode.unknown;
        final response = await transport.catalog();
        if (!response.ok || response.body == null) return before;
        return local.run(() async {
          if (venueId() != venue)
            throw StateError('Menu identity changed during bootstrap');
          if (isCanonical) return mode;
          final body = response.body!;
          if (body['authority'] != 'CLOUD') {
            await stateBox.put('mode', 'legacy');
            await stateBox.flush();
            return MenuSyncMode.legacy;
          }
          final snapshot = CanonicalMenu.fromSnapshot(body);
          if (snapshot.venueId != venue)
            throw StateError('Canonical menu belongs to another Venue');
          final localMenu = menuBox.values.toList();
          if (localMenu.isNotEmpty &&
              !adopt &&
              jsonEncode(_shape(localMenu)) !=
                  jsonEncode(_shape(snapshot.toHive()))) {
            await stateBox.put('mode', 'adoptionBlocked');
            await stateBox.flush();
            return MenuSyncMode.adoptionBlocked;
          }
          await local.commit(snapshot, expectedGeneration: local.generation);
          await stateBox.delete('mode');
          await stateBox.flush();
          return MenuSyncMode.canonical;
        });
      });

  static Map<String, Object?> _shape(Iterable<MenuCategoryDB> menu) =>
      CanonicalMenu.readHive(
        menu,
      ).map((k, v) => MapEntry(k, [v.kind.wire, v.fields]));

  bool _blocked(MenuMutationEntry entry, List<MenuMutationEntry> entries) =>
      entries.any(
        (e) =>
            e.seq < entry.seq &&
            e.entityId == entry.entityId &&
            (e.status == MenuMutationStatus.conflict ||
                e.status == MenuMutationStatus.rejected),
      );

  /// Each response merges with CURRENT durable state and CURRENT journal under
  /// the local queue. No projection or generation captured before HTTP is ever
  /// committed after HTTP. New edits therefore survive both mutate and pull.
  Future<bool> syncOnce() => _network.run(() async {
    final ids = await local.run(() async {
      if (!isCanonical) return <String>[];
      await local.capture();
      return unresolved.map((e) => e.mutationId).toList();
    });
    if (!isCanonical) return false;
    var reachable = true;
    for (final id in ids) {
      final entry = await local.run(() async {
        if (!isCanonical) return null;
        final entries = unresolved;
        final entry = entries.where((e) => e.mutationId == id).firstOrNull;
        return entry == null || !entry.sendable || _blocked(entry, entries)
            ? null
            : entry;
      });
      if (entry == null) continue;
      final response = await transport.mutate(entry.toWire());
      await local.run(() async {
        if (!isCanonical) throw StateError('Menu identity changed during sync');
        final current = state!;
        final entries = unresolved;
        // A resolution can replace/remove an entry while a response is pending.
        // The response must never resurrect that old intent.
        final live = entries.where((e) => e.mutationId == id).firstOrNull;
        final puts = <MenuMutationEntry>[];
        if (response.ok && response.body != null) {
          current.applyAccepted(response.body!);
          if (live != null) {
            final revision = (response.body!['revision'] as num).toInt();
            live
              ..status = MenuMutationStatus.synced
              ..lastError = null;
            puts.add(live);
            for (final later in entries.where(
              (e) =>
                  e.seq > live.seq &&
                  e.entityId == live.entityId &&
                  e.expectedRevision == entry.expectedRevision,
            )) {
              later.expectedRevision = revision;
              puts.add(later);
            }
          }
        } else if (response.status == 409 &&
            response.code == 'REVISION_CONFLICT') {
          final conflict = Map<String, dynamic>.from(
            response.body!['conflict'] as Map,
          );
          if (live != null) {
            live
              ..status = MenuMutationStatus.conflict
              ..conflict = conflict
              ..lastError = 'REVISION_CONFLICT';
            puts.add(live);
          }
          final node = conflict['current'];
          if (node is Map || conflict['deleted'] == true) {
            current.applyAccepted({
              'entityId': entry.entityId,
              'entityType': entry.entityType,
              'entity': node,
              'deleted': conflict['deleted'] == true,
            });
          }
        } else if (response.status == 400 ||
            response.status == 404 ||
            (response.status == 409 && response.code != 'LEGACY_POS_MENU')) {
          if (live != null) {
            live
              ..status = MenuMutationStatus.rejected
              ..lastError = response.code ?? 'HTTP_${response.status}';
            puts.add(live);
          }
        } else {
          if (live != null) {
            live
              ..status = MenuMutationStatus.failedRetryable
              ..attempts += 1
              ..lastError = response.status == 0
                  ? 'UNREACHABLE'
                  : 'HTTP_${response.status}';
            puts.add(live);
          }
          reachable = false;
        }
        await local.commit(
          current,
          puts: puts,
          expectedGeneration: local.generation,
        );
      });
      if (!reachable) break;
    }
    if (reachable) {
      final since = await local.run(() async => state!.sequence);
      var changes = await transport.changes(since);
      final resync = changes.status == 409 && changes.code == 'RESYNC_REQUIRED';
      if (resync) changes = await transport.catalog();
      await local.run(() async {
        if (!isCanonical) throw StateError('Menu identity changed during pull');
        var current = state!;
        if (changes.ok && changes.body != null) {
          if (resync) {
            current = CanonicalMenu.fromSnapshot(changes.body!);
          } else {
            current.applyChanges(changes.body!);
          }
          await local.commit(current, expectedGeneration: local.generation);
        } else {
          reachable = false;
        }
      });
    }
    await local.run(() => journal.compact());
    return reachable;
  });

  /// One recoverable discard includes the target and all same-entity successors.
  Future<void> useCurrent(String mutationId) => local.run(() async {
    if (!isCanonical) return;
    await local.capture();
    final entries = unresolved;
    final target = entries.where((e) => e.mutationId == mutationId).firstOrNull;
    if (target == null) return;
    await local.commit(
      state!,
      removes: entries
          .where((e) => e.entityId == target.entityId && e.seq >= target.seq)
          .toList(),
      expectedGeneration: local.generation,
    );
  });

  /// Durable replacement at the SAME sequence (no remove→put gap), together
  /// with every later rebase. Recovery retains the chosen replacement ID.
  Future<void> reapply(String mutationId) => local.run(() async {
    if (!isCanonical) return;
    await local.capture();
    final entries = unresolved;
    final target = entries.where((e) => e.mutationId == mutationId).firstOrNull;
    final conflict = target?.conflict;
    if (target == null ||
        target.status != MenuMutationStatus.conflict ||
        conflict == null ||
        conflict['deleted'] == true)
      return;
    final revision = (conflict['currentRevision'] as num).toInt();
    final replacement = MenuMutationEntry.fromJson({
      ...target.toJson(),
      'mutationId': _newId(),
      'expectedRevision': revision,
      'status': MenuMutationStatus.pending.name,
      'conflict': null,
      'lastError': null,
      'resolution': 'REAPPLY',
    });
    final puts = [replacement];
    for (final later in entries.where(
      (e) =>
          e.entityId == target.entityId &&
          e.seq > target.seq &&
          e.expectedRevision == target.expectedRevision,
    )) {
      later.expectedRevision = revision;
      puts.add(later);
    }
    await local.commit(
      state!,
      puts: puts,
      expectedGeneration: local.generation,
    );
  });

  Future<void> close() => local.close();
}
