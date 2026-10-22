/// Standalone POS-02 preparation harness. Normal product entrypoints never import it.
library;

import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
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
import 'package:vynic/core/services/printing/printer_transport.dart';
import 'package:vynic/core/services/sync/audit_sync_state.dart';
import 'package:vynic/core/services/sync/staff_credential_sync_state.dart';

enum PreviewOutcome { sent, connectionFailure, partialWrite }

class PreviewNoHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('POS02 preview forbids outbound HTTP');
}

class PreviewTransport {
  PreviewTransport({
    this.physicalHost,
    this.port = 9100,
    DateTime Function()? clock,
    Future<PrinterWriteSocket> Function(String, int)? physicalConnector,
  }) : _clock = clock ?? DateTime.now,
       _physicalConnector = physicalConnector ?? _connectTcp {
    if (port < 1 || port > 65535) throw ArgumentError('Invalid test port');
    if (physicalHost != null && !_privateIPv4(physicalHost!)) {
      throw ArgumentError(
        'Opt-in test endpoint must be one literal private IPv4',
      );
    }
  }

  static const fakeHost = 'synthetic.invalid';
  final String? physicalHost;
  final int port;
  final DateTime Function() _clock;
  final Future<PrinterWriteSocket> Function(String, int) _physicalConnector;
  PreviewOutcome outcome = PreviewOutcome.sent;
  final simulatedWrites = <List<int>>[];
  int physicalConnections = 0;
  String? _job;
  DateTime? _expires;
  bool _consumed = false;

  static bool _privateIPv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4 ||
        parts.any((s) => !RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(s)))
      return false;
    final n = parts.map(int.parse).toList();
    if (n.any((v) => v > 255)) return false;
    return n[0] == 10 ||
        n[0] == 192 && n[1] == 168 ||
        n[0] == 172 && n[1] >= 16 && n[1] <= 31;
  }

  bool get _permitted =>
      _job != null && !_consumed && _clock().isBefore(_expires!);

  void armOneLabeledJob(
    String job, {
    required bool currentWindowApproved,
    DateTime? approvedAt,
  }) {
    if (physicalHost == null ||
        !currentWindowApproved ||
        !RegExp(r'^pos02-preview-[a-z0-9-]+$').hasMatch(job)) {
      throw StateError(
        'A specific opt-in endpoint and fresh approved test window are required',
      );
    }
    final now = _clock();
    final approval = approvedAt ?? now;
    if (approval.isAfter(now) ||
        !now.isBefore(approval.add(const Duration(seconds: 60)))) {
      throw StateError('The approved test window has expired');
    }
    _job = job;
    _expires = approval.add(const Duration(seconds: 60));
    _consumed = false;
  }

  void requireCurrentJob(String job) {
    if (!_permitted || _job != job)
      throw StateError('The labeled job authorization expired');
  }

  void disarm() {
    _job = null;
    _expires = null;
    _consumed = false;
  }

  Future<PrinterWriteSocket> connect(String host, int requestedPort) async {
    if (host == fakeHost && requestedPort == 9100) {
      if (outcome == PreviewOutcome.connectionFailure)
        throw const SocketException('Simulated no-byte connection failure');
      return _FakeSocket(this);
    }
    if (host != physicalHost || requestedPort != port || !_permitted) {
      throw StateError(
        'Preview denied an unarmed or different printer endpoint',
      );
    }
    physicalConnections++;
    final socket = await _physicalConnector(host, requestedPort);
    if (!_permitted) {
      socket.destroy();
      throw StateError('Test authorization expired during connection');
    }
    return _LabeledSocket(this, socket);
  }

  void _consume(List<int> bytes) {
    final text = latin1.decode(bytes);
    if (!_permitted ||
        !text.contains('JOB $_job\n') ||
        !text.contains('TEST / DO NOT PREPARE')) {
      throw StateError(
        'Only the explicitly requested labeled test job may write',
      );
    }
    _consumed =
        true; // Before add, including a possible partial-write exception.
  }

  static Future<PrinterWriteSocket> _connectTcp(String host, int port) async =>
      _TcpSocket(
        await Socket.connect(host, port, timeout: const Duration(seconds: 5)),
      );
}

class _FakeSocket implements PrinterWriteSocket {
  _FakeSocket(this.owner);
  final PreviewTransport owner;
  @override
  void add(List<int> bytes) {
    owner.simulatedWrites.add(List.of(bytes));
    if (owner.outcome == PreviewOutcome.partialWrite)
      throw const SocketException('Simulated partial write; paper is unknown');
  }

  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  void destroy() {}
}

class _LabeledSocket implements PrinterWriteSocket {
  _LabeledSocket(this.owner, this.socket);
  final PreviewTransport owner;
  final PrinterWriteSocket socket;
  @override
  void add(List<int> bytes) {
    owner._consume(bytes);
    socket.add(bytes);
  }

  @override
  Future<void> flush() => socket.flush();
  @override
  Future<void> close() => socket.close();
  @override
  void destroy() => socket.destroy();
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

class Pos02PreviewSession {
  Pos02PreviewSession._(
    this.directory,
    this.transport,
    this._previousHttp,
    this._previousConnect,
    this._previousDelay,
    this._render,
  );
  final Directory directory;
  final PreviewTransport transport;
  final HttpOverrides? _previousHttp;
  final Future<PrinterWriteSocket> Function(String, int)? _previousConnect;
  final Future<void> Function(Duration)? _previousDelay;
  final Future<List<int>> Function(PrintQueueTarget) _render;
  bool _busy = false;

  static Future<Pos02PreviewSession> open({
    PreviewTransport? transport,
    Future<List<int>> Function(PrintQueueTarget)? renderOverride,
  }) async {
    if (DatabaseCore.metaBox?.isOpen ?? false)
      throw StateError('Preview cannot attach to an already-open POS database');
    final directory = await Directory.systemTemp.createTemp(
      'vynic_pos02_preview_',
    );
    final guard = transport ?? PreviewTransport();
    final session = Pos02PreviewSession._(
      directory,
      guard,
      HttpOverrides.current,
      PrinterTransport.connectOverride,
      PrinterTransport.delayOverride,
      renderOverride ?? _renderSample,
    );
    PrintQueue.stop();
    await PrintQueue.idle;
    HttpOverrides.global = PreviewNoHttp();
    PrinterTransport.connectOverride = guard.connect;
    PrinterTransport.delayOverride = (_) async {};
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = directory.path;
    LocalDataAdmission.failure = null;
    PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
    try {
      // Storage-only bootstrap: the façade init starts audit-sync timers.
      await DatabaseCore.open(managedDataDirectory: directory.path);
      await DatabaseCore.settingsBox!.putAll({
        'printerKitchenIp': PreviewTransport.fakeHost,
        'printerReceiptIp': PreviewTransport.fakeHost,
        'defaultLanguage': 'en',
      });
      final user = User(
        username: 'synthetic-preview',
        pinCode: '1234',
        role: 'manager',
      );
      await DatabaseCore.userBox!.put(user.username, user);
      PosSession.start(user);
      if (PrintJobRepository.all().isNotEmpty ||
          DatabaseCore.orderBox!.isNotEmpty ||
          DatabaseCore.salesBox!.isNotEmpty) {
        throw StateError(
          'Preview did not start with fresh empty synthetic data',
        );
      }
      return session; // Queue stays stopped; normal startup/sync workers are not called.
    } catch (_) {
      await session.close(removeData: true);
      rethrow;
    }
  }

  Future<PrintJob> sendSample(
    PrintQueueTarget target, {
    bool physical = false,
    bool currentWindowApproved = false,
    DateTime? approvedAt,
  }) async {
    if (target != PrintQueueTarget.kitchen &&
        target != PrintQueueTarget.receipt) {
      throw ArgumentError.value(
        target,
        'target',
        'Preview supports kitchen and receipt samples only',
      );
    }
    if (_busy) throw StateError('Wait for the current synthetic job');
    _busy = true;
    final id = 'pos02-preview-${const Uuid().v4()}';
    try {
      final host = physical
          ? transport.physicalHost
          : PreviewTransport.fakeHost;
      if (physical)
        transport.armOneLabeledJob(
          id,
          currentWindowApproved: currentWindowApproved,
          approvedAt: approvedAt,
        );
      final rendered = await _render(target);
      if (rendered.isEmpty) throw StateError('Sample rendering failed');
      if (physical) transport.requireCurrentJob(id);
      final job = PrintJob.create(
        id: id,
        target: target,
        host: host!,
        port: physical ? transport.port : 9100,
        label: 'POS02 PREVIEW / TEST ONLY',
        venueId: EdgeDeviceCredentialStore.venueId,
        bytes: [
          0x1b,
          0x40,
          ...ascii.encode('*** TEST / DO NOT PREPARE ***\n'),
          ...rendered,
        ],
      );
      await PrintQueue.enqueue(job);
      PrintQueue.start(); // Explicit user submission only, after durable admission.
      await PrintQueue.idle;
      final result = PrintJobRepository.read(id);
      if (result == null || PrintJobRepository.failure != null)
        throw StateError(
          'Preview print dispatch failed: ${PrintJobRepository.failure}',
        );
      return result;
    } finally {
      PrintQueue.stop();
      transport.disarm();
      _busy = false;
    }
  }

  static Future<List<int>> _renderSample(PrintQueueTarget target) =>
      target == PrintQueueTarget.kitchen
      ? EscposKitchenRenderer.generateBytes(
          items: [
            'TEST / DO NOT PREPARE',
            '1x სატესტო პროდუქტი / Synthetic item',
            'NO CUSTOMER ORDER',
          ],
          tableNumber: 'TEST ONLY',
          orderNumber: 'PREVIEW',
          waiterName: 'synthetic-preview',
          resolveOperatorDisplayName: (name, {required isEnglish}) => name,
        )
      : EscposReceiptRenderer.generateBytes(
          items: [
            'TEST / DO NOT PREPARE',
            'სატესტო პროდუქტი / Synthetic item - 1.00',
          ],
          total: 1,
          subtotal: 1,
          tableNumber: 'TEST ONLY',
          orderNumber: 'PREVIEW',
          language: 'ka',
          venue: (
            name: 'TEST / DO NOT PREPARE',
            address: 'POS02 SYNTHETIC ONLY',
            phone: '',
          ),
          layout: const ReceiptHeaderLayout(),
          loadReceiptLogoImage: () async => null,
          getReceiptLogoContentRect: (_) async => Rect.zero,
        );

  Future<void> close({bool removeData = false}) async {
    PrintQueue.stop();
    await PrintQueue.idle;
    transport.disarm();
    await EdgeCommandJournal.close();
    await AuditSyncState.close();
    await StaffCredentialSyncState.close();
    await Hive.close();
    PosSession.clear();
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = null;
    HttpOverrides.global = _previousHttp;
    PrinterTransport.connectOverride = _previousConnect;
    PrinterTransport.delayOverride = _previousDelay;
    if (removeData && await directory.exists())
      await directory.delete(recursive: true);
  }
}
