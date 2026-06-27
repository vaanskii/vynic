import 'package:flutter/foundation.dart';
import 'package:vynic/core/services/database_service.dart';

enum BackendConnectionState { idle, syncing, connected, offline }

class ConnectionStatusService {
  ConnectionStatusService._();

  static final ValueNotifier<BackendConnectionState> backendState =
      ValueNotifier<BackendConnectionState>(BackendConnectionState.idle);
  static final ValueNotifier<DateTime?> lastAttemptAt =
      ValueNotifier<DateTime?>(null);
  static final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier<DateTime?>(
    null,
  );
  static final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  static final ValueNotifier<bool> hasPendingLocalChanges = ValueNotifier<bool>(
    false,
  );

  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    lastSyncedAt.value = DatabaseService.getLastManagerSyncAt();
    if (lastSyncedAt.value != null) {
      backendState.value = BackendConnectionState.connected;
    }
  }

  static void markPendingLocalChange() {
    hasPendingLocalChanges.value = true;
  }

  static void markAttempt() {
    initialize();
    lastAttemptAt.value = DateTime.now();
    backendState.value = BackendConnectionState.syncing;
  }

  static Future<void> markSuccess({bool clearPendingChanges = true}) async {
    initialize();
    final now = DateTime.now();
    lastAttemptAt.value = now;
    lastSyncedAt.value = now;
    lastError.value = null;
    backendState.value = BackendConnectionState.connected;
    if (clearPendingChanges) {
      hasPendingLocalChanges.value = false;
    }
    await DatabaseService.saveLastManagerSyncAt(now);
  }

  static void markConnectionTestSuccess() {
    initialize();
    lastAttemptAt.value = DateTime.now();
    lastError.value = null;
    backendState.value = BackendConnectionState.connected;
  }

  static void markBackendReachable() {
    initialize();
    if (backendState.value != BackendConnectionState.syncing) {
      backendState.value = BackendConnectionState.connected;
    }
  }

  static void markFailure(Object error) {
    initialize();
    lastAttemptAt.value = DateTime.now();
    lastError.value = error.toString();
    backendState.value = BackendConnectionState.offline;
  }

  static void markBackendUnreachable(Object error) {
    initialize();
    lastError.value = error.toString();
    if (backendState.value != BackendConnectionState.syncing) {
      backendState.value = BackendConnectionState.offline;
    }
  }
}
