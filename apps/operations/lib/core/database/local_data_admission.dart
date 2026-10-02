import 'dart:async';
import 'dart:developer' as developer;

class _AdmissionScope {
  _AdmissionScope({this.recovery = false});
  bool active = true;
  final bool recovery;
}

class _MutationScope {
  bool active = true;
  final List<void Function()> after = [];
}

/// Shared admission for local mutations, snapshots and business-day transitions.
/// Network requests are outside this gate. Admitted operations finish; new
/// operations wait before reading or changing business state.
abstract final class LocalDataAdmission {
  static final Object _scopeKey = Object();
  static final Object _mutationKey = Object();
  static final Set<Object> _active = {};
  static Completer<void>? _released;
  static Completer<void>? _drained;
  static Completer<void>? _mutationReleased;
  static String? failure;
  static String? exclusiveOperation;

  static bool get blocked => _released != null || failure != null;
  static bool get insideMutation {
    final scope = Zone.current[_mutationKey];
    return scope is _MutationScope && scope.active;
  }

  /// Serializes complete logical mutations in this operational process. It is
  /// reentrant for awaited repository/model calls. View/dialog/network waits
  /// use [track] instead. Exclusive transitions still drain admitted writers.
  static Future<T> mutate<T>(Future<T> Function() action) => track(() async {
    if (insideMutation) return action();
    while (_mutationReleased != null) {
      await _mutationReleased!.future;
    }
    final admission = Zone.current[_scopeKey] as _AdmissionScope;
    if (failure != null && !admission.recovery) throw StateError(failure!);
    final released = Completer<void>();
    _mutationReleased = released;
    final scope = _MutationScope();
    try {
      return await runZoned(action, zoneValues: {_mutationKey: scope});
    } finally {
      scope.active = false;
      _mutationReleased = null;
      released.complete();
      for (final callback in scope.after) {
        _outside(callback);
      }
    }
  });

  /// A sync listener may start an unawaited network request and later write an
  /// ACK. It must never inherit a still-active mutation/admission owner.
  static void afterMutation(void Function() callback) {
    final scope = Zone.current[_mutationKey];
    if (scope is _MutationScope && scope.active) {
      scope.after.add(callback);
    } else {
      _outside(callback);
    }
  }

  static void _outside(void Function() callback) {
    runZoned(() {
      try {
        callback();
      } catch (error, stack) {
        developer.log(
          'Post-mutation notification failed',
          error: error,
          stackTrace: stack,
          name: 'LocalDataAdmission',
        );
      }
    }, zoneValues: {_mutationKey: null, _scopeKey: null});
  }

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
    final previous = Zone.current[_scopeKey];
    final scope = _AdmissionScope(
      recovery:
          previous is _AdmissionScope && previous.active && previous.recovery,
    );
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
    final scope = _AdmissionScope(recovery: recovery);
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
