import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/closure_journal_repository.dart';
import 'package:vynic/core/services/auth/session_lock.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_transport_service.dart';
import 'package:vynic/core/services/edge/inventory_projection_sync_service.dart';
import 'package:vynic/core/services/edge/orders_tables/coordinator.dart';
import 'package:vynic/core/services/edge/runtime_config_sync.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';
import 'update/pos_updater.dart';
import 'update/update_readiness.dart';

/// User shutdown shares the updater's atomic operation admission barrier.
/// It never asks Edge to stop or install, and never deletes restaurant data.
class PosQuit {
  PosQuit({
    required this.stopServices,
    required this.flushAndClose,
    PosUpdater? updater,
  }) : updater = updater ?? PosUpdater.instance;

  static final instance = PosQuit(
    stopServices: () async {
      SessionLock.disarm();
      await Future.wait([
        PosUpdater.instance.stopForQuit(),
        EdgeTransportService.instance().shutdown(),
        InventoryProjectionSyncService.instance().shutdown(),
        RuntimeConfigSync.instance.shutdown(),
        ManagerSyncService.shutdown(),
      ]);
      PrinterService.dispose();
    },
    flushAndClose: () async {
      await PosUpdater.flushLocalState();
      await OrderTableCoordinator.shutdownConnections();
      await Hive.close();
    },
  );

  final PosUpdater updater;
  final Future<void> Function() stopServices;
  final Future<void> Function() flushAndClose;
  Future<String?>? _pending;
  bool _ownsBarrier = false;
  bool completed = false;
  bool get shutdownStarted => _ownsBarrier;

  /// Also enable tracking in Windows installations without updater config.
  static void enableWindowsTracking() {
    UpdateReadiness.enabled = true;
    UpdateReadiness.startupReady = DatabaseCore.dbVersion == 9;
  }

  String? get blockedReason {
    if (updater.installing ||
        updater.awaitingDecision ||
        updater.preparingInstall) {
      return 'განახლება მიმდინარეობს. დაელოდეთ დასრულებას.';
    }
    // Exiting probation looks like a crashed candidate to Go. Wait/refuse here;
    // never weaken health verification or require an Edge protocol upgrade.
    if (updater.probation)
      return 'გაშვების შემოწმება მიმდინარეობს. სცადეთ ცოტა ხანში.';
    final readiness = UpdateReadiness.blockedReason;
    if (readiness != null) return readiness;
    if (ClosureJournalRepository.pending().isNotEmpty ||
        EdgeCommandJournal.hasUnresolvedExecution) {
      return 'მიმდინარე ოპერაციის აღდგენა ჯერ არ დასრულებულა';
    }
    return OrderTableCoordinator.updateBlocker();
  }

  /// Null means cleanly closed; a reason means the process must stay alive.
  /// A failed cleanup keeps admission closed; retry resumes cleanup only.
  Future<String?> prepare() {
    if (completed) return Future.value(null);
    return _pending ??= _prepare().whenComplete(() => _pending = null);
  }

  Future<String?> _prepare() async {
    if (!_ownsBarrier) {
      final reason = blockedReason;
      if (reason != null) return reason;
      // No await between check and freeze: new tracked work cannot race quit.
      UpdateReadiness.frozen = true;
      _ownsBarrier = true;
    }
    try {
      await stopServices().timeout(const Duration(seconds: 45));
      await flushAndClose();
      completed = true;
      return null;
    } catch (error, stack) {
      debugPrint('POS clean shutdown failed: $error\n$stack');
      return 'დახურვა ვერ დასრულდა. სცადეთ ხელახლა.\n$error';
    }
  }
}
