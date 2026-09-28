import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';

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

/// Local-first canonical Menu engine for one POS (docs/CANONICAL_MENU_SYNC.md).
///
/// The operational Hive menu is a projection of (canonical Cloud state ⊕ this
/// POS's unresolved journal). Local edits land in the operational menu first
/// (instant, offline) and are captured into the journal by diffing against the
/// projection last written — never against a newer Cloud state, so a catch-up
/// can never be mistaken for a local edit. The network only ever runs after
/// the local commit, and its failures never touch local operation.
class PosMenuSync {
  PosMenuSync({
    required this.stateBox,
    required Box<String> journalBox,
    required this.menuBox,
    required this.transport,
    required this.venueId,
    String Function()? newMutationId,
  }) : journal = MenuMutationJournal(journalBox),
       _newId = newMutationId ?? CanonicalMenu.newMutationId;

  final Box<String> stateBox;
  final MenuMutationJournal journal;
  final Box<MenuCategoryDB> menuBox;
  final MenuSyncTransport transport;
  final String? Function() venueId;
  final String Function() _newId;
  final _Serial _serial = _Serial();
  final StreamController<void> _projected = StreamController<void>.broadcast();

  /// Fires after the operational menu was rewritten from canonical state.
  Stream<void> get projected => _projected.stream;

  static const _state = 'state';
  static const _baseline = 'baseline';
  static const _mode = 'mode';
  static const _rebuilding = 'rebuilding';

  CanonicalMenu? get state {
    final raw = stateBox.get(_state);
    return raw == null ? null : CanonicalMenu.fromJsonString(raw);
  }

  MenuSyncMode get mode {
    final current = state;
    if (current != null) {
      return current.venueId == venueId()
          ? MenuSyncMode.canonical
          : MenuSyncMode.venueMismatch;
    }
    final stored = stateBox.get(_mode);
    return switch (stored) {
      'legacy' => MenuSyncMode.legacy,
      'adoptionBlocked' => MenuSyncMode.adoptionBlocked,
      _ => MenuSyncMode.unknown,
    };
  }

  bool get isCanonical => mode == MenuSyncMode.canonical;

  List<MenuMutationEntry> _mine() {
    final venue = venueId();
    return journal.unresolved().where((e) => e.venueId == venue).toList();
  }

  List<MenuMutationEntry> get unresolved => _mine();

  CanonicalMenu _projection(CanonicalMenu base) {
    final projection = base.copy();
    for (final entry in _mine()) {
      // A rejected create/move never reached Cloud; it stays local until the
      // operator discards it, so nothing typed locally silently disappears.
      projection.applyLocal(
        MenuKindWire.parse(entry.entityType),
        entry.operation,
        entry.entityId,
        entry.patch,
      );
    }
    return projection;
  }

  CanonicalMenu? _storedBaseline() {
    final raw = stateBox.get(_baseline);
    return raw == null ? null : CanonicalMenu.fromJsonString(raw);
  }

  // ------------------------------------------------------------ capture

  /// Journals local operator edits made since the last projection.
  Future<int> captureLocalEdits() => _serial.run(_capture);

  Future<int> _capture() async {
    final current = state;
    if (current == null || current.venueId != venueId()) return 0;
    // An interrupted projection write is not an operator edit.
    if (stateBox.get(_rebuilding) != null) {
      await _write(_projection(current));
      return 0;
    }
    final baseline = _storedBaseline() ?? _projection(current);
    final changes = CanonicalMenu.diff(baseline, menuBox.values);
    for (final change in changes) {
      await journal.append(
        mutationId: _newId(),
        venueId: current.venueId,
        entityType: change.kind.wire,
        operation: change.operation,
        entityId: change.entityId,
        expectedRevision: current.nodes[change.entityId]?.revision ?? 0,
        patch: change.patch,
      );
      baseline.applyLocal(
        change.kind,
        change.operation,
        change.entityId,
        change.patch,
      );
    }
    if (changes.isNotEmpty) {
      await stateBox.put(_baseline, baseline.toJsonString());
      await stateBox.flush();
    }
    return changes.length;
  }

  // ---------------------------------------------------------- projection

  Future<void> _write(CanonicalMenu projection) async {
    final hive = projection.toHive();
    final now = jsonEncode(
      CanonicalMenu.readHive(
        menuBox.values,
      ).map((k, v) => MapEntry(k, [v.kind.wire, v.fields, v.position])),
    );
    final next = jsonEncode(
      CanonicalMenu.readHive(
        hive,
      ).map((k, v) => MapEntry(k, [v.kind.wire, v.fields, v.position])),
    );
    if (now != next) {
      await stateBox.put(_rebuilding, '1');
      await stateBox.flush();
      await menuBox.clear();
      await menuBox.addAll(hive);
      await menuBox.flush();
    }
    await stateBox.put(_baseline, projection.toJsonString());
    await stateBox.delete(_rebuilding);
    await stateBox.flush();
    if (now != next) _projected.add(null);
  }

  /// Captures outstanding local edits, then rewrites the operational menu.
  Future<void> rebuildProjection() => _serial.run(() async {
    final current = state;
    if (current == null || current.venueId != venueId()) return;
    await _capture();
    await _write(_projection(current));
  });

  /// The operational menu was replaced by something that is not an operator
  /// edit (backup restore): re-project instead of journaling the difference.
  Future<void> reprojectDiscardingExternal() => _serial.run(() async {
    final current = state;
    if (current == null || current.venueId != venueId()) return;
    await _write(_projection(current));
  });

  // ----------------------------------------------------------- bootstrap

  /// Imports the Venue's canonical Menu into durable local state.
  ///
  /// A fresh POS (empty operational menu) is projected directly. A POS that
  /// already holds exactly the same catalog is adopted. Any other local menu
  /// is left untouched ([MenuSyncMode.adoptionBlocked]) until [adopt] is
  /// explicitly requested; an established POS Venue stays [legacy].
  Future<MenuSyncMode> bootstrap({bool adopt = false}) => _serial.run(() async {
    final current = mode;
    if (current == MenuSyncMode.canonical ||
        current == MenuSyncMode.venueMismatch) {
      return current;
    }
    final venue = venueId();
    if (venue == null) return MenuSyncMode.unknown;
    final response = await transport.catalog();
    if (!response.ok || response.body == null) return current;
    final body = response.body!;
    if (body['authority'] != 'CLOUD') {
      await stateBox.put(_mode, 'legacy');
      await stateBox.flush();
      return MenuSyncMode.legacy;
    }
    final snapshot = CanonicalMenu.fromSnapshot(body);
    if (snapshot.venueId != venue) {
      throw StateError('Canonical menu belongs to another Venue');
    }
    final local = menuBox.values.toList();
    if (local.isNotEmpty && !adopt) {
      final same =
          jsonEncode(_shape(local)) == jsonEncode(_shape(snapshot.toHive()));
      if (!same) {
        await stateBox.put(_mode, 'adoptionBlocked');
        await stateBox.flush();
        return MenuSyncMode.adoptionBlocked;
      }
    }
    await stateBox.put(_state, snapshot.toJsonString());
    await stateBox.delete(_mode);
    await stateBox.flush();
    // The previous local menu (if explicitly adopted over) is not an edit.
    await _write(_projection(snapshot));
    return MenuSyncMode.canonical;
  });

  static Map<String, Object?> _shape(Iterable<MenuCategoryDB> menu) =>
      CanonicalMenu.readHive(
        menu,
      ).map((k, v) => MapEntry(k, [v.kind.wire, v.fields]));

  // ---------------------------------------------------------------- sync

  bool _blocked(MenuMutationEntry entry, List<MenuMutationEntry> earlier) =>
      earlier.any(
        (e) =>
            e.entityId == entry.entityId &&
            (e.status == MenuMutationStatus.conflict ||
                e.status == MenuMutationStatus.rejected),
      );

  /// Pushes pending mutations in order, then catches up from Cloud, then
  /// re-projects. Returns false when Cloud was unreachable (nothing is lost).
  Future<bool> syncOnce() => _serial.run(() async {
    final stored = state;
    if (stored == null || stored.venueId != venueId()) return false;
    var current = stored;
    await _capture();
    var reachable = true;
    final entries = _mine();
    for (final (index, entry) in entries.indexed) {
      if (!entry.sendable) continue;
      if (_blocked(entry, entries.sublist(0, index))) continue;
      final response = await transport.mutate(entry.toWire());
      if (response.ok && response.body != null) {
        current.applyAccepted(response.body!);
        final revision = (response.body!['revision'] as num).toInt();
        final base = entry.expectedRevision;
        entry
          ..status = MenuMutationStatus.synced
          ..lastError = null;
        await journal.save(entry);
        // Later local edits of the same node were built on this one.
        for (final later in entries.skip(index + 1)) {
          if (later.entityId == entry.entityId &&
              later.expectedRevision == base &&
              later.unresolved) {
            later.expectedRevision = revision;
            await journal.save(later);
          }
        }
        await stateBox.put(_state, current.toJsonString());
        continue;
      }
      if (response.status == 409 && response.code == 'REVISION_CONFLICT') {
        final conflict = Map<String, dynamic>.from(
          response.body!['conflict'] as Map,
        );
        entry
          ..status = MenuMutationStatus.conflict
          ..conflict = conflict
          ..lastError = 'REVISION_CONFLICT';
        await journal.save(entry);
        final node = conflict['current'];
        if (node is Map) {
          current.applyAccepted({
            'entityId': entry.entityId,
            'entityType': entry.entityType,
            'entity': node,
          });
        } else if (conflict['deleted'] == true) {
          current.applyAccepted({
            'entityId': entry.entityId,
            'entityType': entry.entityType,
            'deleted': true,
          });
        }
        await stateBox.put(_state, current.toJsonString());
        continue;
      }
      if (response.status == 400 ||
          response.status == 404 ||
          (response.status == 409 && response.code != 'LEGACY_POS_MENU')) {
        entry
          ..status = MenuMutationStatus.rejected
          ..lastError = response.code ?? 'HTTP_${response.status}';
        await journal.save(entry);
        continue;
      }
      // Offline, 5xx, auth: keep order, retry later.
      entry
        ..status = MenuMutationStatus.failedRetryable
        ..attempts += 1
        ..lastError = response.status == 0
            ? 'UNREACHABLE'
            : 'HTTP_${response.status}';
      await journal.save(entry);
      reachable = false;
      break;
    }
    if (reachable) {
      final changes = await transport.changes(current.sequence);
      if (changes.ok && changes.body != null) {
        current.applyChanges(changes.body!);
      } else if (changes.status == 409 && changes.code == 'RESYNC_REQUIRED') {
        final snapshot = await transport.catalog();
        if (snapshot.ok && snapshot.body != null) {
          current = CanonicalMenu.fromSnapshot(snapshot.body!);
        } else {
          reachable = false;
        }
      } else {
        reachable = false;
      }
      await stateBox.put(_state, current.toJsonString());
    }
    await stateBox.flush();
    await journal.compact();
    await _write(_projection(current));
    return reachable;
  });

  // ---------------------------------------------------------- resolution

  List<MenuMutationEntry> get conflicts => _mine()
      .where(
        (e) =>
            e.status == MenuMutationStatus.conflict ||
            e.status == MenuMutationStatus.rejected,
      )
      .toList();

  /// "Use current": discard my pending change(s) to this node.
  Future<void> useCurrent(String mutationId) => _serial.run(() async {
    final entries = _mine();
    final target = entries.where((e) => e.mutationId == mutationId).firstOrNull;
    if (target == null) return;
    for (final entry in entries.where(
      (e) => e.entityId == target.entityId && e.seq >= target.seq,
    )) {
      await journal.remove(entry);
    }
    final current = state;
    if (current != null) await _write(_projection(current));
  });

  /// "Re-apply my change" against the current Cloud revision (explicit, audited).
  Future<void> reapply(String mutationId) => _serial.run(() async {
    final entries = _mine();
    final target = entries.where((e) => e.mutationId == mutationId).firstOrNull;
    final conflict = target?.conflict;
    if (target == null ||
        target.status != MenuMutationStatus.conflict ||
        conflict == null ||
        conflict['deleted'] == true) {
      return;
    }
    final revision = (conflict['currentRevision'] as num).toInt();
    final base = target.expectedRevision;
    await journal.remove(target);
    await journal.box.put(
      target.seq.toString().padLeft(12, '0'),
      jsonEncode({
        ...target.toJson(),
        'mutationId': _newId(),
        'expectedRevision': revision,
        'status': MenuMutationStatus.pending.name,
        'conflict': null,
        'lastError': null,
        'resolution': 'REAPPLY',
      }),
    );
    for (final later in entries.where(
      (e) =>
          e.entityId == target.entityId &&
          e.seq > target.seq &&
          e.expectedRevision == base,
    )) {
      later.expectedRevision = revision;
      await journal.save(later);
    }
    await journal.box.flush();
  });

  Future<void> close() => _projected.close();
}
