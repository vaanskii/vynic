import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/menu/menu_mutation_journal.dart';
import 'package:vynic/core/services/menu/menu_local_store.dart';
import 'package:vynic/core/services/menu/pos_menu_sync.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/sync/sync_events.dart';

/// What the POS shows about its canonical Menu (no network state in the UI path).
@immutable
class MenuSyncStatus {
  const MenuSyncStatus({
    this.mode = MenuSyncMode.unknown,
    this.pending = 0,
    this.attention = const [],
    this.lastSyncAt,
    this.reachable = true,
  });
  final MenuSyncMode mode;

  /// Local edits not yet accepted by Cloud (normal while offline).
  final int pending;

  /// Conflicts/rejections the operator must decide.
  final List<MenuMutationEntry> attention;
  final DateTime? lastSyncAt;
  final bool reachable;
}

/// Runs the local-first canonical Menu engine for this POS
/// (docs/CANONICAL_MENU_SYNC.md). Everything here is asynchronous and
/// best-effort: repository success already includes durable local intent, and an
/// unreachable Cloud only delays global convergence.
class PosMenuSyncService {
  PosMenuSyncService._();
  static final PosMenuSyncService instance = PosMenuSyncService._();

  final ValueNotifier<MenuSyncStatus> status = ValueNotifier(
    const MenuSyncStatus(),
  );

  PosMenuSync? _engine;
  HttpMenuSyncTransport? _transport;
  StreamSubscription<SyncEvent>? _events;
  StreamSubscription<void>? _projected;
  Timer? _timer;
  Timer? _debounce;
  bool _running = false;
  bool _syncing = false;
  bool _suspended = false;
  DateTime? _lastBootstrapAttempt;

  static const projectedAction = 'canonical_projected';
  static const syncInterval = Duration(seconds: 20);
  static const legacyRecheck = Duration(minutes: 10);

  /// A typed snapshot refusal means the server mode changed. Reconcile through
  /// existing explicit adoption, preserving a differing local Menu.
  Future<void> refreshAuthority() async {
    _lastBootstrapAttempt = null;
    await tick();
  }

  /// True when this POS uses the canonical Menu; its full snapshot then omits
  /// the menu (the Cloud would ignore it anyway).
  static bool get isCanonical => instance._engine?.isCanonical ?? false;

  PosMenuSync? _build() {
    final state = DatabaseCore.menuCanonicalBox;
    final journal = DatabaseCore.menuJournalBox;
    final menu = DatabaseCore.menuBox;
    if (state == null || journal == null || menu == null) return null;
    _transport ??= HttpMenuSyncTransport(
      baseUrl: () => ApiConfig.baseUrl,
      credential: () => EdgeDeviceCredentialStore.credential,
    );
    return PosMenuSync(
      stateBox: state,
      journalBox: journal,
      menuBox: menu,
      transport: _transport!,
      venueId: () => EdgeDeviceCredentialStore.venueId,
    );
  }

  Future<void> start() async {
    if (_running) return;
    if (!EdgeDeviceCredentialStore.isLoaded) {
      await EdgeDeviceCredentialStore.load();
    }
    if (!EdgeDeviceCredentialStore.hasCredential) return;
    _engine ??= _build();
    if (_engine == null) return;
    if (_engine!.mode != MenuSyncMode.venueMismatch) {
      await _engine!.local.initialize();
    }
    _running = true;
    _projected = _engine!.projected.listen((_) {
      SyncHub.notify(
        SyncEvent(type: SyncEventType.menu, action: projectedAction),
      );
    });
    _events = SyncHub.events.listen((event) {
      if (event.type != SyncEventType.menu ||
          event.action == projectedAction ||
          _suspended) {
        return;
      }
      unawaited(_afterLocalEdit());
    });
    _publish();
    unawaited(tick());
    _timer = Timer.periodic(syncInterval, (_) => unawaited(tick()));
  }

  Future<void> _afterLocalEdit() async {
    final engine = _engine;
    if (engine == null || !engine.isCanonical) return;
    // Repository writes already committed intent and projection together.
    _publish();
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () => unawaited(tick()));
  }

  /// One bootstrap/sync round; never throws into the caller.
  Future<void> tick() async {
    final engine = _engine;
    if (engine == null || _syncing || _suspended) return;
    _syncing = true;
    try {
      var mode = engine.mode;
      final now = DateTime.now();
      final recheck =
          _lastBootstrapAttempt == null ||
          mode == MenuSyncMode.unknown ||
          (mode == MenuSyncMode.legacy &&
              now.difference(_lastBootstrapAttempt!) > legacyRecheck);
      if (mode != MenuSyncMode.canonical &&
          mode != MenuSyncMode.venueMismatch &&
          mode != MenuSyncMode.adoptionBlocked &&
          recheck) {
        _lastBootstrapAttempt = now;
        mode = await engine.bootstrap();
      }
      if (mode == MenuSyncMode.canonical) {
        final reachable = await engine.syncOnce();
        _publish(reachable: reachable, synced: reachable ? now : null);
        return;
      }
      _publish();
    } catch (error) {
      debugPrint('[MenuSync] $error');
      _publish(reachable: false);
    } finally {
      _syncing = false;
    }
  }

  void _publish({bool? reachable, DateTime? synced}) {
    final engine = _engine;
    if (engine == null) return;
    final unresolved = engine.isCanonical
        ? engine.unresolved
        : const <MenuMutationEntry>[];
    status.value = MenuSyncStatus(
      mode: engine.mode,
      pending: unresolved.where((e) => e.sendable).length,
      attention: engine.isCanonical ? engine.conflicts : const [],
      lastSyncAt: synced ?? status.value.lastSyncAt,
      reachable: reachable ?? status.value.reachable,
    );
  }

  /// Operator choice for a conflict/rejection: keep the Cloud value.
  Future<void> useCurrent(String mutationId) async {
    await _engine?.useCurrent(mutationId);
    _publish();
    unawaited(tick());
  }

  /// Operator choice for a conflict: re-apply my change on the current revision.
  Future<void> reapply(String mutationId) async {
    await _engine?.reapply(mutationId);
    _publish();
    unawaited(tick());
  }

  /// Explicitly replaces a different local menu with the Venue's Cloud menu.
  Future<MenuSyncMode> adoptCloudMenu() async {
    final engine = _engine;
    if (engine == null) return MenuSyncMode.unknown;
    final mode = await engine.bootstrap(adopt: true);
    _publish();
    if (mode == MenuSyncMode.canonical) unawaited(tick());
    return mode;
  }

  /// Wraps a non-operator replacement of the operational menu (backup
  /// restore). In canonical mode the restored rows are not edits: capture is
  /// suspended and the menu is re-projected from canonical state afterwards.
  Future<T> externalMenuWrite<T>(Future<T> Function() write) async {
    final menu = DatabaseCore.menuBox;
    if (menu == null) return write();
    _suspended = true;
    try {
      return await MenuLocalStore.forBox(menu).external(write);
    } finally {
      _suspended = false;
      _publish();
    }
  }

  Future<void> shutdown() async {
    _running = false;
    _timer?.cancel();
    _debounce?.cancel();
    await _events?.cancel();
    await _projected?.cancel();
    while (_syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    // Capture anything typed just before Quit so it is journaled durably.
    final engine = _engine;
    if (engine != null && engine.isCanonical) {
      await engine.captureLocalEdits();
    }
    _transport?.close();
  }
}
