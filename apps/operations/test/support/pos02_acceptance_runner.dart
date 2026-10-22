/// Standalone synthetic acceptance preparation; ordinary POS never imports it.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/models/receipt_header_layout.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/edge/edge_command_journal.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/printing/escpos_kitchen_renderer.dart';
import 'package:vynic/core/services/printing/escpos_receipt_renderer.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/printing/printer_transport.dart';
import 'package:vynic/core/services/sync/audit_sync_state.dart';
import 'package:vynic/core/services/sync/staff_credential_sync_state.dart';
import '../../tool/pos02_acceptance_ledger.dart';

class _NoHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Acceptance runner forbids HTTP and cloud bootstrap');
}

class AcceptanceFakeSocket implements PrinterWriteSocket {
  final writes = <List<int>>[];
  bool failAdd = false;
  bool failFlush = false;
  bool destroyed = false;
  @override
  void add(List<int> bytes) {
    writes.add(List<int>.of(bytes));
    if (failAdd) throw const SocketException('Synthetic partial write');
  }

  @override
  Future<void> flush() async {
    if (failFlush) throw const SocketException('Synthetic flush failure');
  }

  @override
  Future<void> close() async {}
  @override
  void destroy() => destroyed = true;
}

class _TcpSocket implements PrinterWriteSocket {
  _TcpSocket(this.socket);
  final Socket socket;
  @override
  void add(List<int> bytes) => socket.add(bytes);
  @override
  Future<void> flush() => socket.flush();
  @override
  Future<void> close() async {
    await socket.close();
  }

  @override
  void destroy() => socket.destroy();
}

class AcceptanceTransport {
  AcceptanceTransport(
    this.ledger,
    this.clock,
    this.connector, {
    required this.physical,
  });
  final AcceptanceLedger ledger;
  final DateTime Function() clock;
  final Future<PrinterWriteSocket> Function(String, int) connector;
  final bool physical;
  PrintJob? _job;
  bool _connected = false;
  bool _written = false;
  int connectionCalls = 0;

  void _budgetMode() {
    final reserved = ledger.events.where((e) => e['event'] == 'reserved');
    if (!ledger.isOpen ||
        reserved.length != 1 ||
        (reserved.single['detail'] as Map)['simulated'] != !physical ||
        physical && ledger.window.allowance != 1) {
      throw StateError(
        'Transport mode does not match the immutable reserved budget',
      );
    }
  }

  void arm(PrintJob job) {
    _budgetMode();
    ledger.window.requireCurrent(clock());
    if (_job != null ||
        !ledger.has('reserved') ||
        ledger.has('admitted') ||
        job.id != ledger.window.jobId ||
        job.host != ledger.window.host ||
        job.port != 9100 ||
        job.target.name != ledger.window.body['target'] ||
        job.attemptId != ledger.window.actionId ||
        !job.ready ||
        !latin1
            .decode(job.transmissionBytes)
            .contains('TEST / DO NOT PREPARE')) {
      throw StateError('Frozen job does not match reserved acceptance action');
    }
    ledger.append('admitted', clock(), {
      'jobId': job.id,
      'attemptId': job.attemptId,
      'payloadSha256': job.toMap()['payloadSha256'],
      'transmissionSha256': acceptanceHash(job.transmissionBytes),
    });
    _job = job;
  }

  void _current() {
    _budgetMode();
    ledger.window.requireCurrent(clock());
    final expected = _job;
    final actual = expected == null
        ? null
        : PrintJobRepository.read(expected.id);
    if (expected == null ||
        actual == null ||
        actual.state != PrintJobState.sending ||
        actual.attemptId != expected.attemptId ||
        actual.host != expected.host ||
        actual.port != expected.port ||
        actual.target != expected.target ||
        acceptanceHash(actual.transmissionBytes) !=
            acceptanceHash(expected.transmissionBytes)) {
      throw StateError('Only the exact frozen candidate attempt may write');
    }
  }

  Future<PrinterWriteSocket> connect(String host, int port) async {
    _current();
    if (_connected ||
        ledger.has('connect') ||
        host != ledger.window.host ||
        port != 9100) {
      throw StateError(
        'One connect attempt per window; no reconnect or fallback',
      );
    }
    _connected = true;
    ledger.append('connect', clock()); // Spent even if the connector throws.
    _current(); // A durable flush can cross expiry; recheck before connector.
    connectionCalls++;
    final socket = await connector(host, port);
    try {
      _current(); // Expiry during connect must not reach Socket.add.
      return _GuardedSocket(this, socket);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  void write(List<int> bytes) {
    _current();
    if (_written ||
        ledger.has('write') ||
        acceptanceHash(bytes) != acceptanceHash(_job!.transmissionBytes)) {
      throw StateError('One exact write per window; no resend');
    }
    _written =
        true; // Before ledger I/O or underlying add, including exceptions.
    ledger.append('write', clock(), {
      'transmissionSha256': acceptanceHash(bytes),
    });
    _current(); // A durable flush can cross expiry; keep the allowance spent.
  }
}

class _GuardedSocket implements PrinterWriteSocket {
  _GuardedSocket(this.owner, this.socket);
  final AcceptanceTransport owner;
  final PrinterWriteSocket socket;
  @override
  void add(List<int> bytes) {
    owner.write(bytes);
    owner._current(); // Immediately before the underlying Socket.add.
    socket.add(bytes);
  }

  @override
  Future<void> flush() => socket.flush();
  @override
  Future<void> close() => socket.close();
  @override
  void destroy() => socket.destroy();
}

class Pos02AcceptanceSession {
  static const _boxNames = [
    DatabaseCore.metaBoxName,
    DatabaseCore.userBoxName,
    DatabaseCore.tableBoxName,
    DatabaseCore.orderBoxName,
    DatabaseCore.packageBoxName,
    DatabaseCore.menuBoxName,
    DatabaseCore.settingsBoxName,
    DatabaseCore.salesBoxName,
    DatabaseCore.expenseBoxName,
    DatabaseCore.auditLogBoxName,
    DatabaseCore.errorLogBoxName,
    DatabaseCore.reservationBoxName,
    DatabaseCore.quickOrderBoxName,
    DatabaseCore.closureJournalBoxName,
    DatabaseCore.inventoryBoxName,
    DatabaseCore.menuCanonicalBoxName,
    DatabaseCore.menuJournalBoxName,
    EdgeCommandJournal.boxName,
    AuditSyncState.boxName,
    StaffCredentialSyncState.boxName,
  ];
  Pos02AcceptanceSession._(
    this.ledger,
    this.simulated,
    this.clock,
    this._render,
    this.transport,
    this.fakeSocket,
  );
  final AcceptanceLedger ledger;
  final bool simulated;
  final DateTime Function() clock;
  final Future<List<int>> Function(PrintQueueTarget)? _render;
  final AcceptanceTransport transport;
  final AcceptanceFakeSocket fakeSocket;
  final _previousHttp = HttpOverrides.current;
  final _previousConnect = PrinterTransport.connectOverride;
  final _previousDelay = PrinterTransport.delayOverride;
  final _previousRender = PrinterService.renderBytesOverride;
  final _previousPolicy = PrintReconciliation.policy;
  bool _busy = false;

  static Future<Pos02AcceptanceSession> open({
    required Directory root,
    required AcceptanceWindow window,
    bool executePhysical = false,
    DateTime Function()? clock,
    Future<PrinterWriteSocket> Function(String, int)? connectorForTest,
    Future<List<int>> Function(PrintQueueTarget)? renderForTest,
  }) async {
    if (_boxNames.any(Hive.isBoxOpen) || PosSession.user != null) {
      throw StateError(
        'Runner cannot attach to any already-open POS storage/session',
      );
    }
    if (executePhysical && renderForTest != null) {
      throw StateError('Physical runner requires the candidate renderers');
    }
    final ledger = AcceptanceLedger.open(root, window);
    final now = clock ?? DateTime.now;
    final fake = AcceptanceFakeSocket();
    final connector =
        connectorForTest ??
        (executePhysical
            ? (String host, int port) async => _TcpSocket(
                await Socket.connect(
                  host,
                  port,
                  timeout: const Duration(seconds: 5),
                ),
              )
            : (String host, int port) async => fake);
    final session = Pos02AcceptanceSession._(
      ledger,
      !executePhysical,
      now,
      renderForTest,
      AcceptanceTransport(ledger, now, connector, physical: executePhysical),
      fake,
    );
    PrintQueue.stop();
    await PrintQueue.idle;
    HttpOverrides.global = _NoHttp();
    PrinterTransport.connectOverride = session.transport.connect;
    PrinterTransport.delayOverride = (_) async {};
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = '${ledger.root.path}/hive';
    LocalDataAdmission.failure = null;
    PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
    try {
      // No façade init, enrollment, real data-path resolver or sync workers.
      Directory('${ledger.root.path}/hive').createSync();
      await DatabaseCore.open(managedDataDirectory: '${ledger.root.path}/hive');
      final ownedHive = Directory(
        '${ledger.root.path}/hive',
      ).resolveSymbolicLinksSync();
      for (final box in <Box?>[
        DatabaseCore.metaBox,
        DatabaseCore.userBox,
        DatabaseCore.tableBox,
        DatabaseCore.orderBox,
        DatabaseCore.packageBox,
        DatabaseCore.menuBox,
        DatabaseCore.settingsBox,
        DatabaseCore.salesBox,
        DatabaseCore.expenseBox,
        DatabaseCore.auditLogBox,
        DatabaseCore.errorLogBox,
        DatabaseCore.reservationBox,
        DatabaseCore.quickOrderBox,
        DatabaseCore.closureJournalBox,
        DatabaseCore.inventoryBox,
        DatabaseCore.menuCanonicalBox,
        DatabaseCore.menuJournalBox,
      ]) {
        final path = box?.path;
        if (path == null ||
            !File(path).resolveSymbolicLinksSync().startsWith(
              '$ownedHive${Platform.pathSeparator}',
            )) {
          throw StateError(
            'Opened Hive box is outside owned acceptance storage: ${box?.name}',
          );
        }
      }
      for (final job in PrintJobRepository.all().where((j) => j.ready)) {
        await PrintJobRepository.transition(
          job.id,
          job.attemptId,
          job.state,
          PrintJobState.uncertain,
          detail:
              'Acceptance restart holds admitted work; allowance never replays',
        );
      }
      if (DatabaseCore.orderBox!.isNotEmpty ||
          DatabaseCore.salesBox!.isNotEmpty ||
          EdgeDeviceCredentialStore.venueId != null) {
        throw StateError('Acceptance storage must contain only synthetic data');
      }
      await DatabaseCore.settingsBox!.putAll({
        'printerKitchenIp': window.host,
        'printerReceiptIp': window.host,
        'defaultLanguage': 'ka',
      });
      final user = User(
        username: 'pos02-synthetic-operator',
        pinCode: '1234',
        role: 'waiter',
      );
      await DatabaseCore.userBox!.put(user.username, user);
      PosSession.start(user);
      return session; // Queue remains stopped until exact admission is armed.
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  Future<PrintJob?> submit({required bool go}) async {
    if (_busy) throw StateError('Acceptance action already in progress');
    _busy = true;
    try {
      if (ledger.has('reserved') || ledger.has('cancelled')) {
        // Stable repeats never dispatch, admit a copy, or refund the allowance.
        return PrintJobRepository.read(ledger.window.jobId);
      }
      if (!go) {
        ledger.append('cancelled', clock());
        return null;
      }
      ledger.reserve(clock(), simulated: simulated);
      final window = ledger.window;
      if (window.copy) {
        final original = PrintJobRepository.read(window.jobId);
        if (original == null ||
            original.target != PrintQueueTarget.kitchen ||
            original.host != window.host ||
            !latin1
                .decode(original.transmissionBytes)
                .contains('TEST / DO NOT PREPARE')) {
          throw StateError('Only a frozen synthetic Kitchen job can be copied');
        }
        await PrintReconciliation.reprint(
          original,
          PrintReconciliation.kitchenCopyReason,
          window.actionId,
        );
      } else {
        final target = PrintQueueTarget.values.byName(window.body['target']);
        PrinterService.renderBytesOverride = () async {
          final bytes = await (_render?.call(target) ?? _sample(target));
          window.requireCurrent(
            clock(),
          ); // After render, before Hive admission.
          if (bytes.isEmpty) throw StateError('Synthetic rendering failed');
          return [
            0x1b,
            0x40,
            ...ascii.encode('*** TEST / DO NOT PREPARE ***\n'),
            ...bytes,
          ];
        };
        final admitted = target == PrintQueueTarget.kitchen
            ? await PrinterService.printKitchenCheckInBackground(
                items: _items,
                tableNumber: 'TEST ONLY',
                orderNumber: 'POS02 TEST',
                waiterName: 'pos02-synthetic-operator',
                jobId: window.jobId,
              )
            : await PrinterService.printReceiptInBackground(
                items: _items,
                total: 1,
                subtotal: 1,
                tableNumber: 'TEST ONLY',
                orderNumber: 'POS02 TEST',
                paymentMethod: 'TEST',
                jobId: window.jobId,
              );
        if (!admitted)
          throw StateError(
            'Candidate service refused admission; allowance spent',
          );
      }
      final job = PrintJobRepository.read(window.jobId);
      if (job == null || PrintJobRepository.failure != null) {
        throw StateError(
          'Candidate durable admission failed: ${PrintJobRepository.failure}',
        );
      }
      transport.arm(job);
      PrintQueue.start();
      await PrintQueue.idle;
      final result = PrintJobRepository.read(job.id)!;
      if (PrintJobRepository.failure != null) {
        throw StateError(
          'Candidate worker failed: ${PrintJobRepository.failure}',
        );
      }
      ledger.append('completed', clock(), {'state': result.state.name});
      return result;
    } finally {
      PrintQueue.stop();
      PrinterService.renderBytesOverride = _previousRender;
      _busy = false;
    }
  }

  static const _items = [
    'TEST / DO NOT PREPARE',
    '1x სატესტო პროდუქტი / Synthetic item',
    'NO CUSTOMER ORDER',
  ];
  static Future<List<int>> _sample(PrintQueueTarget target) =>
      target == PrintQueueTarget.kitchen
      ? EscposKitchenRenderer.generateBytes(
          items: _items,
          tableNumber: 'TEST ONLY',
          orderNumber: 'POS02 TEST',
          waiterName: 'pos02-synthetic-operator',
          resolveOperatorDisplayName: (name, {required isEnglish}) => name,
        )
      : EscposReceiptRenderer.generateBytes(
          items: _items,
          total: 1,
          subtotal: 1,
          tableNumber: 'TEST ONLY',
          orderNumber: 'POS02 TEST',
          paymentMethod: 'TEST',
          language: 'ka',
          venue: (
            name: 'TEST / DO NOT PREPARE',
            address: 'SYNTHETIC ONLY',
            phone: '',
          ),
          layout: const ReceiptHeaderLayout(),
          loadReceiptLogoImage: () async => null,
          getReceiptLogoContentRect: (_) async => Rect.zero,
        );

  void recordObservation({
    required int slips,
    required String operator,
    required String evidence,
    required String note,
  }) {
    if (!ledger.has('reserved') ||
        slips < 0 ||
        slips > 20 ||
        [
          operator,
          evidence,
          note,
        ].any((v) => v.trim().isEmpty || v.length > 500)) {
      throw ArgumentError(
        'Record the observed slip count and external evidence',
      );
    }
    ledger.append('observation', clock(), {
      'slips': slips,
      'operator': operator,
      'evidence': evidence,
      'note': note,
    });
    // An observation is evidence, never product paper confirmation or a print.
  }

  Future<void> close() async {
    PrintQueue.stop();
    await PrintQueue.idle;
    try {
      await EdgeCommandJournal.close();
      await AuditSyncState.close();
      await StaffCredentialSyncState.close();
      await Hive.close();
    } finally {
      PosSession.clear();
      EdgeDeviceCredentialStore.resetForTest();
      EdgeDeviceCredentialStore.directoryOverride = null;
      HttpOverrides.global = _previousHttp;
      PrinterTransport.connectOverride = _previousConnect;
      PrinterTransport.delayOverride = _previousDelay;
      PrinterService.renderBytesOverride = _previousRender;
      PrintReconciliation.policy = _previousPolicy;
      ledger.close();
    }
  }
}
