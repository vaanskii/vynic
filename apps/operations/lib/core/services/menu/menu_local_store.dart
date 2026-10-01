import 'package:vynic/core/database/local_data_admission.dart';
import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/services/menu/canonical_menu.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';

/// Detached read/modify draft. A writer must [commit] before reporting success.
/// No Hive-owned object is mutated before the durable intent exists.
class MenuDraft {
  MenuDraft._(Box<MenuCategoryDB> box, this._commit)
    : _rows = box.toMap().map((key, value) => MapEntry(key, _copy(value)));

  final Map<dynamic, MenuCategoryDB> _rows;
  final Future<void> Function(MenuDraft) _commit;
  Iterable<MenuCategoryDB> get values => _rows.values;
  MenuCategoryDB? getAt(int index) => _rows.values.elementAt(index);
  Future<void> commit() => _commit(this);
  Future<void> add(MenuCategoryDB category) async {
    final ints = _rows.keys.whereType<int>();
    final next = ints.fold(0, (int max, key) => key >= max ? key + 1 : max);
    _rows[next] = _copy(category);
    await commit();
  }

  Future<void> deleteAt(int index) async {
    _rows.remove(_rows.keys.elementAt(index));
    await commit();
  }

  static MenuItemDB _item(MenuItemDB item) => MenuItemDB(
    id: item.id,
    translationsEn: Map.of(item.translationsEn),
    translationsKa: Map.of(item.translationsKa),
    price: item.price,
    sendToKitchen: item.sendToKitchen,
    variants: item.variants
        ?.map((v) => MenuVariantDB(id: v.id, size: v.size, price: v.price))
        .toList(),
  );

  static MenuCategoryDB _copy(MenuCategoryDB category) => MenuCategoryDB(
    id: category.id,
    slug: category.slug,
    translationsEn: Map.of(category.translationsEn),
    translationsKa: Map.of(category.translationsKa),
    sendToKitchen: category.sendToKitchen,
    items: category.items?.map(_item).toList(),
    subcategories: category.subcategories
        ?.map(
          (s) => MenuSubcategoryDB(
            id: s.id,
            slug: s.slug,
            translationsEn: Map.of(s.translationsEn),
            translationsKa: Map.of(s.translationsKa),
            items: s.items.map(_item).toList(),
          ),
        )
        .toList(),
  );
}

class _MenuWriteScope {
  _MenuWriteScope(this.owner);
  final MenuLocalStore owner;
  bool active = true;
}

/// The one local Menu boundary, shared by repository, sync and restore writers.
///
/// A single flushed Hive row describes the entire commit before journal/state/
/// projection writes begin. Replay is idempotent (including mutation IDs and
/// same-entity rebases). Network calls must never run inside [run].
class MenuLocalStore {
  MenuLocalStore._(this.menuBox);
  static final _stores = Expando<MenuLocalStore>();
  static final Object _scope = Object();
  static final Object _externalScope = Object();

  static MenuLocalStore forBox(Box<MenuCategoryDB> box) =>
      _stores[box] ??= MenuLocalStore._(box);

  static MenuLocalStore attach({
    required Box<MenuCategoryDB> menuBox,
    required Box<String> stateBox,
    required Box<String> journalBox,
    required String? Function() venueId,
    String Function()? newMutationId,
  }) {
    final store = forBox(menuBox);
    store._stateBox = stateBox;
    store._journal = MenuMutationJournal(journalBox);
    store._venueId = venueId;
    store._newId = newMutationId ?? CanonicalMenu.newMutationId;
    return store;
  }

  // Additive local protocol; Hive adapters and journal entry format stay v9.
  static const protocolVersion = 1;
  static const commitKey = 'localCommit';
  static const versionKey = 'localProtocolVersion';
  static const generationKey = 'generation';
  static const stateKey = 'state';
  static const baselineKey = 'baseline';
  static const rebuildingKey = 'rebuilding';

  final Box<MenuCategoryDB> menuBox;
  Box<String>? _stateBox;
  MenuMutationJournal? _journal;
  String? Function()? _venueId;
  String Function() _newId = CanonicalMenu.newMutationId;
  Future<void> _tail = Future.value();
  final _projected = StreamController<void>.broadcast();
  Stream<void> get projected => _projected.stream;
  MenuMutationJournal get journal => _journal!;
  Box<String> get stateBox => _stateBox!;
  int get generation => int.parse(stateBox.get(generationKey) ?? '0');
  CanonicalMenu? get state {
    final raw = _stateBox?.get(stateKey);
    return raw == null ? null : CanonicalMenu.fromJsonString(raw);
  }

  void _checkVenue(CanonicalMenu current) {
    final venue = _venueId?.call();
    if (venue != null && current.venueId != venue) {
      throw StateError('Stored Menu belongs to another Venue');
    }
  }

  List<MenuMutationEntry> entries(CanonicalMenu current) =>
      journal.all().where((e) => e.venueId == current.venueId).toList();

  CanonicalMenu projection(
    CanonicalMenu current, [
    Iterable<MenuMutationEntry>? entries,
  ]) {
    final next = current.copy();
    for (final e in entries ?? this.entries(current)) {
      if (!e.unresolved) continue;
      next.applyLocal(
        MenuKindWire.parse(e.entityType),
        e.operation,
        e.entityId,
        e.patch,
      );
    }
    return next;
  }

  Future<T> run<T>(Future<T> Function() task) =>
      LocalDataAdmission.track(() => _run(task));

  Future<T> _run<T>(Future<T> Function() task) {
    final result = _tail.then((_) {
      final scope = _MenuWriteScope(this);
      return runZoned(() async {
        try {
          await _recover();
          return await task();
        } finally {
          scope.active = false;
        }
      }, zoneValues: {_scope: scope});
    });
    _tail = result.then((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  bool get _isExternal {
    final scope = Zone.current[_scope];
    return scope is _MenuWriteScope &&
        scope.owner == this &&
        scope.active &&
        identical(Zone.current[_externalScope], scope);
  }

  void _requireScope() {
    final scope = Zone.current[_scope];
    if (scope is! _MenuWriteScope || scope.owner != this || !scope.active) {
      throw StateError('Menu commits must use the local queue');
    }
  }

  /// Startup migration/recovery happens before seeding or enabling the editor.
  Future<void> initialize() => run(() async {
    final current = state;
    if (current != null) {
      _checkVenue(current);
      await capture();
      if (stateBox.get(versionKey) == null) {
        await commit(current, expectedGeneration: generation);
      }
    }
  });

  Future<T> edit<T>(Future<T> Function(MenuDraft) write) =>
      _isExternal ? _edit(write) : run(() => _edit(write));

  Future<T> _edit<T>(Future<T> Function(MenuDraft) write) async {
    if (!_isExternal && state != null) await capture();
    final draft = MenuDraft._(menuBox, (draft) async {
      _requireScope();
      final current = state;
      if (current == null || _isExternal) {
        // Legacy compatibility and nested identity upgrades during restore.
        await menuBox.deleteAll(
          menuBox.keys.where((k) => !draft._rows.containsKey(k)).toList(),
        );
        await menuBox.putAll(draft._rows);
        await menuBox.flush();
        return;
      }
      _checkVenue(current);
      final changes = CanonicalMenu.diff(projection(current), draft.values);
      if (changes.isEmpty) return;
      final puts = _intents(current, changes);
      await commit(current, puts: puts, expectedGeneration: generation);
    });
    return write(draft);
  }

  List<MenuMutationEntry> _intents(
    CanonicalMenu current,
    List<MenuChange> changes,
  ) {
    var seq = journal.nextSeq;
    return [
      for (final change in changes)
        MenuMutationEntry(
          seq: seq++,
          mutationId: _newId(),
          venueId: current.venueId,
          entityType: change.kind.wire,
          operation: change.operation,
          entityId: change.entityId,
          expectedRevision: current.nodes[change.entityId]?.revision ?? 0,
          patch: change.patch,
          status: MenuMutationStatus.pending,
          createdAt: DateTime.now().toUtc(),
        ),
    ];
  }

  /// Compatibility capture for pre-upgrade/direct-write fixtures. Diff against
  /// canonical + durable journal, so a stale baseline cannot mint duplicate IDs.
  Future<int> capture() async {
    _requireScope();
    final current = state;
    if (current == null) return 0;
    _checkVenue(current);
    final changes = CanonicalMenu.diff(projection(current), menuBox.values);
    if (changes.isEmpty) return 0;
    await commit(
      current,
      puts: _intents(current, changes),
      expectedGeneration: generation,
    );
    return changes.length;
  }

  /// Called inside [run]. The generation check refuses a staged stale view;
  /// sync must merge responses with live state/journal after its network await.
  Future<void> commit(
    CanonicalMenu current, {
    List<MenuMutationEntry> puts = const [],
    List<MenuMutationEntry> removes = const [],
    required int expectedGeneration,
  }) async {
    _requireScope();
    _checkVenue(current);
    if (stateBox.get(commitKey) != null) {
      throw StateError('Menu recovery must finish before another commit');
    }
    if (expectedGeneration != generation)
      throw StateError('Stale Menu generation');
    final merged = {for (final e in journal.all()) e.seq: e};
    for (final e in removes) {
      merged.remove(e.seq);
    }
    for (final e in puts) {
      merged[e.seq] = e;
    }
    final ordered = merged.values.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    final frame = <String, dynamic>{
      'version': protocolVersion,
      'baseGeneration': generation,
      'generation': generation + 1,
      'canonical': current.toJsonString(),
      'projection': projection(
        current,
        ordered.where((e) => e.venueId == current.venueId),
      ).toJsonString(),
      'puts': puts.map((e) => e.toJson()).toList(),
      'removes': removes.map((e) => e.seq).toList(),
    };
    await stateBox.put(commitKey, jsonEncode(frame));
    await stateBox.flush(); // recovery authority before any destructive write
    await _apply(frame);
  }

  Future<void> _recover() async {
    if (_stateBox == null) return;
    final version = stateBox.get(versionKey);
    if (version != null && version != '$protocolVersion') {
      throw StateError('Unsupported local Menu protocol $version');
    }
    final raw = stateBox.get(commitKey);
    if (raw != null) {
      final frame = jsonDecode(raw) as Map<String, dynamic>;
      await _apply(frame);
    } else if (stateBox.get(rebuildingKey) != null && state != null) {
      // Existing-format interrupted projection, before this protocol existed.
      await commit(state!, expectedGeneration: generation);
    }
  }

  Future<void> _apply(Map<String, dynamic> frame) async {
    if (frame['version'] != protocolVersion) {
      throw StateError('Unsupported local Menu commit version');
    }
    final nextGeneration = frame['generation'] as int;
    if (generation != frame['baseGeneration'] && generation != nextGeneration) {
      throw StateError('Out-of-order local Menu recovery');
    }
    final canonical = CanonicalMenu.fromJsonString(
      frame['canonical'] as String,
    );
    _checkVenue(canonical);
    // Replacements overwrite the SAME sequence key. Never remove old first.
    for (final raw in frame['puts'] as List) {
      await journal.save(
        MenuMutationEntry.fromJson(Map<String, dynamic>.from(raw as Map)),
      );
    }
    for (final seq in frame['removes'] as List) {
      await journal.box.delete(MenuMutationJournal.key(seq as int));
    }
    await journal.box.flush();
    await stateBox.put(stateKey, canonical.toJsonString());
    await stateBox.put(generationKey, '$nextGeneration');
    await stateBox.put(versionKey, '$protocolVersion');
    await stateBox.flush();
    await _writeProjection(
      CanonicalMenu.fromJsonString(frame['projection'] as String),
    );
    await stateBox.delete(commitKey);
    await stateBox.flush();
  }

  Future<void> _writeProjection(CanonicalMenu projection) async {
    final hive = projection.toHive();
    String shape(Iterable<MenuCategoryDB> rows) => jsonEncode(
      CanonicalMenu.readHive(
        rows,
      ).map((k, v) => MapEntry(k, [v.kind.wire, v.fields, v.position])),
    );
    final changed = shape(menuBox.values) != shape(hive);
    if (changed) {
      await stateBox.put(rebuildingKey, '1');
      await stateBox.flush();
      await menuBox.clear();
      await menuBox.addAll(hive);
      await menuBox.flush();
    }
    await stateBox.put(baselineKey, projection.toJsonString());
    await stateBox.delete(rebuildingKey);
    await stateBox.flush();
    if (changed) _projected.add(null);
  }

  /// Restore/wipe share the local queue, and leave recovery authority BEFORE
  /// touching the projection. Restored rows retain the existing external-write
  /// semantics: canonical + unresolved intent wins, not the backup projection.
  Future<T> external<T>(Future<T> Function() write) => run(() async {
    final current = state;
    if (current == null) {
      return runZoned(
        write,
        zoneValues: {_externalScope: Zone.current[_scope]},
      );
    }
    await capture();
    final frame = <String, dynamic>{
      'version': protocolVersion,
      'baseGeneration': generation,
      'generation': generation + 1,
      'canonical': current.toJsonString(),
      'projection': projection(current).toJsonString(),
      'puts': <Object>[],
      'removes': <int>[],
    };
    await stateBox.put(commitKey, jsonEncode(frame));
    await stateBox.flush();
    try {
      return await runZoned(
        write,
        zoneValues: {_externalScope: Zone.current[_scope]},
      );
    } finally {
      await _apply(frame);
    }
  });

  Future<void> close() => _projected.close();
}
