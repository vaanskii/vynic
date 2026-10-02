import 'dart:async';

class _AdmissionScope {
  bool active = true;
}

/// Shared admission for local mutations, snapshots and business-day transitions.
/// Network requests are outside this gate. Admitted operations finish; new
/// operations wait before reading or changing business state.
abstract final class LocalDataAdmission {
  static final Object _scopeKey = Object();
  static final Set<Object> _active = {};
  static Completer<void>? _released;
  static Completer<void>? _drained;
  static String? failure;
  static String? exclusiveOperation;

  static bool get blocked => _released != null || failure != null;
  static bool get _inside {
    final scope = Zone.current[_scopeKey];
    return scope is _AdmissionScope && scope.active;
  }

  static Future<T> track<T>(Future<T> Function() action) async {
    if (!_inside) {
      if (failure != null) throw StateError(failure!);
      // Another exclusive operation can acquire the gate before this waiter
      // resumes. Recheck instead of admitting it under that second operation.
      while (_released != null) {
        await _released!.future;
      }
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
    String operation = 'backup/restore',
  }) async {
    if (_inside) throw StateError('Exclusive admission cannot nest in a write');
    if (_released != null)
      throw StateError('Another local transition is active');
    if (!recovery && failure != null) throw StateError(failure!);
    final released = Completer<void>();
    _released = released;
    exclusiveOperation = operation;
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
      exclusiveOperation = null;
      released.complete();
    }
  }
}
