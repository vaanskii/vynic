import 'package:hive/hive.dart';
import 'update_readiness.dart';

/// Covers writes which bypass a repository (including legacy model.save()).
mixin UpdateTrackedHiveObject on HiveObject {
  Future<void> _persist(Future<void> Function() action) async {
    try {
      await UpdateReadiness.track('Hive model write', action);
    } catch (e) {
      if (UpdateReadiness.enabled && !UpdateReadiness.frozen)
        UpdateReadiness.failure = e.toString();
      rethrow;
    }
  }

  @override
  Future<void> save() => _persist(super.save);
  @override
  Future<void> delete() => _persist(super.delete);
}

class UpdateTrackedBox<E> implements Box<E> {
  UpdateTrackedBox(this.inner);
  final Box<E> inner;
  Future<T> _write<T>(Future<T> Function() f) async {
    try {
      return await UpdateReadiness.track('Hive write', f);
    } catch (e) {
      if (UpdateReadiness.enabled && !UpdateReadiness.frozen)
        UpdateReadiness.failure = e.toString();
      rethrow;
    }
  }

  @override
  String get name => inner.name;
  @override
  bool get isOpen => inner.isOpen;
  @override
  String? get path => inner.path;
  @override
  bool get lazy => inner.lazy;
  @override
  Iterable<dynamic> get keys => inner.keys;
  @override
  Iterable<E> get values => inner.values;
  @override
  int get length => inner.length;
  @override
  bool get isEmpty => inner.isEmpty;
  @override
  bool get isNotEmpty => inner.isNotEmpty;
  @override
  dynamic keyAt(int index) => inner.keyAt(index);
  @override
  Stream<BoxEvent> watch({dynamic key}) => inner.watch(key: key);
  @override
  bool containsKey(dynamic key) => inner.containsKey(key);
  @override
  E? get(dynamic key, {E? defaultValue}) =>
      inner.get(key, defaultValue: defaultValue);
  @override
  E? getAt(int index) => inner.getAt(index);
  @override
  Iterable<E> valuesBetween({dynamic startKey, dynamic endKey}) =>
      inner.valuesBetween(startKey: startKey, endKey: endKey);
  @override
  Map<dynamic, E> toMap() => inner.toMap();
  @override
  Future<void> put(dynamic key, E value) => _write(() => inner.put(key, value));
  @override
  Future<void> putAt(int index, E value) =>
      _write(() => inner.putAt(index, value));
  @override
  Future<void> putAll(Map<dynamic, E> entries) =>
      _write(() => inner.putAll(entries));
  @override
  Future<int> add(E value) => _write(() => inner.add(value));
  @override
  Future<Iterable<int>> addAll(Iterable<E> values) =>
      _write(() => inner.addAll(values));
  @override
  Future<void> delete(dynamic key) => _write(() => inner.delete(key));
  @override
  Future<void> deleteAt(int index) => _write(() => inner.deleteAt(index));
  @override
  Future<void> deleteAll(Iterable<dynamic> keys) =>
      _write(() => inner.deleteAll(keys));
  @override
  Future<void> compact() => _write(inner.compact);
  @override
  Future<int> clear() => _write(inner.clear);
  @override
  Future<void> deleteFromDisk() => _write(inner.deleteFromDisk);
  @override
  Future<void> close() => inner.close();
  @override
  Future<void> flush() => inner.flush();
}
