import 'dart:async';

class _AdmissionScope {
  bool active = true;
}

/// Process-local snapshot admission. Network requests are outside this gate.
/// Existing local operations finish; new ones wait during the short snapshot.
abstract final class LocalDataAdmission {
  static final Object _scopeKey = Object();
  static final Set<Object> _active = {};
  static Completer<void>? _released;
  static Completer<void>? _drained;
  static String? failure;

  static bool get blocked => _released != null || failure != null;
  static bool get _inside {
    final scope = Zone.current[_scopeKey];
    return scope is _AdmissionScope && scope.active;
  }

  static Future<T> track<T>(Future<T> Function() action) async {
    if (!_inside) {
      if (failure != null) throw StateError(failure!);
      final released = _released;
      if (released != null) await released.future;
      if (failure != null) throw StateError(failure!);
    }
    final token = Object();
    final scope = _AdmissionScope();
    _active.add(token);
    try {
      return await runZoned(action, zoneValues: {_scopeKey: scope});
    } finally {
      scope.active = false;
      _active.remove(token);
      if (_active.isEmpty) _drained?.complete();
      if (_active.isEmpty) _drained = null;
    }
  }

  static Future<T> exclusive<T>(
    Future<T> Function() action, {
    Duration drainTimeout = const Duration(seconds: 2),
    bool recovery = false,
  }) async {
    if (_inside) throw StateError('Snapshot cannot run inside a local write');
    if (_released != null) throw StateError('Another backup/restore is active');
    if (!recovery && failure != null) throw StateError(failure!);
    final released = Completer<void>();
    _released = released;
    final scope = _AdmissionScope();
    try {
      if (_active.isNotEmpty) {
        _drained = Completer<void>();
        await _drained!.future.timeout(
          drainTimeout,
          onTimeout: () {
            throw StateError(
              'POS is busy; finish the local operation and retry',
            );
          },
        );
      }
      return await runZoned(action, zoneValues: {_scopeKey: scope});
    } finally {
      scope.active = false;
      _drained = null;
      _released = null;
      released.complete();
    }
  }
}
