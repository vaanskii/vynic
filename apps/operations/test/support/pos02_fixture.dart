import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/order_confirmation_print.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import 'package:vynic/core/services/printing/printer_transport.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'menu01_fixture.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';

class Pos02Box extends UpdateTrackedBox<dynamic> {
  Pos02Box(super.inner, this.boundary);
  final Future<void> Function(String) boundary;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    final state = value is Map && value['attempts'] is List
        ? value['attempts'].last['state']
        : 'other';
    await boundary('meta.put:$state:before');
    await super.put(key, value);
    await boundary('meta.put:$state:after');
  }

  @override
  Future<void> flush() async {
    await boundary('meta.flush:before');
    await super.flush();
    await boundary('meta.flush:after');
  }
}

class Pos02OrderBox extends UpdateTrackedBox<Order> {
  Pos02OrderBox(super.inner, this.boundary);
  final Future<void> Function(String) boundary;
  @override
  Future<void> put(dynamic key, Order value) async {
    await boundary('orders.put:${value.status}:before');
    await super.put(key, value);
    await boundary('orders.put:${value.status}:after');
  }
}

class Pos02Fixture {
  String? directory;
  HttpOverrides? previousHttp;
  String mode = 'sent';
  final trace = <String>[];
  final transmitted = <List<int>>[];
  int connections = 0;
  bool acknowledged = false;
  Future<void> Function(String point, int index)? fault;
  Completer<void>? flushBarrier;
  static const jobId = 'synthetic-pos02-job';
  static const copyId = 'synthetic-pos02-copy';

  Future<void> boundary(String point) async {
    trace.add(point);
    await fault?.call(point, trace.length);
  }

  Future<void> open(String path, {bool instrument = true}) async {
    directory = path;
    await Directory(path).create(recursive: true);
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = Menu01NoHttp();
    PrintQueue.stop();
    await PrintQueue.idle;
    PrinterService.renderBytesOverride = null;
    PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
    UpdateReadiness.enabled = false;
    UpdateReadiness.frozen = false;
    UpdateReadiness.failure = null;
    await openMenu01(path);
    PrinterTransport.delayOverride = (_) async {};
    PrinterTransport.connectOverride = (host, port) async {
      if (host != 'synthetic.invalid' || port != 9100)
        throw StateError('Only owned synthetic printer transport is allowed');
      connections++;
      await boundary('transport.connect');
      if (mode == 'connect-error')
        throw const SocketException('synthetic connection refused');
      return Pos02Socket(this);
    };
    if (instrument) {
      DatabaseCore.metaBox = Pos02Box(DatabaseCore.metaBox!, boundary);
      DatabaseCore.orderBox = Pos02OrderBox(DatabaseCore.orderBox!, boundary);
    }
  }

  Future<void> seed() async {
    await seedMenu01(itemCount: 1, salesCount: 0);
    await DatabaseCore.settingsBox!.putAll({
      'printerKitchenIp': 'synthetic.invalid',
      'printerReceiptIp': 'synthetic.invalid',
    });
    final manager = User(
      username: 'synthetic-operator',
      pinCode: '1234',
      role: 'manager',
    );
    await DatabaseCore.userBox!.put(manager.username, manager);
    PosSession.start(manager);
    PrintReconciliation.policy = PrintReconciliationPolicy.administrators;
    trace.clear();
  }

  PrintJob job({
    String id = jobId,
    PrintQueueTarget target = PrintQueueTarget.kitchen,
    List<int>? bytes,
  }) => PrintJob.create(
    id: id,
    target: target,
    host: 'synthetic.invalid',
    port: 9100,
    label: 'Kitchen / synthetic ticket',
    bytes:
        bytes ??
        [0x1b, 0x40, ...ascii.encode('SYNTHETIC ONLY\n'), 0x1d, 0x56, 0],
    venueId: menu01Venue,
  );
  Future<void> dispatch() async {
    PrintQueue.start();
    await PrintQueue.idle;
  }

  Map<String, dynamic> get remotePayload => {
    'posOrderId': 100,
    'requestId': 'synthetic-remote-create',
    'waiterName': 'synthetic-operator',
    'customerName': 'Synthetic customer',
    'totalAmount': 3.0,
    'items': [
      {
        'itemKey': 'synthetic',
        'itemName': 'Synthetic food',
        'quantity': 1,
        'unitPrice': 3.0,
        'total': 3.0,
      },
    ],
  };
  Future<void> action(String scenario) async {
    if (scenario == 'localconfirm') {
      final order = DatabaseService.getOrder(100)!;
      expect(
        await OrderConfirmationPrint.confirm(
          order: order,
          lines: ['1x Synthetic food'],
          tableLabel: 'Synthetic takeaway',
        ),
        true,
      );
    } else if (scenario == 'remotecreate') {
      final outcome = await PosCommandApplier.upsertTakeawayOrder(
        remotePayload,
      );
      expect(outcome.ok, true);
      expect(outcome.data['printJobQueued'], true);
    } else if (scenario == 'reprint') {
      await PrintReconciliation.reprint(
        PrintJobRepository.read(jobId)!,
        'synthetic deliberate copy',
        copyId,
      );
    } else if (scenario == 'confirm') {
      await PrintReconciliation.confirm(
        PrintJobRepository.read(jobId)!,
        'synthetic paper observation',
        'synthetic-confirm',
      );
    } else {
      await PrintQueue.enqueue(job());
    }
    acknowledged = true;
    await dispatch();
  }

  Future<void> prepare(String scenario) async {
    await seed();
    if (scenario == 'localconfirm') {
      await DatabaseCore.orderBox!.put(
        'synthetic-pending',
        Order(
          orderId: 100,
          tableNumbers: [],
          floor: 'take-away',
          items: [
            OrderItem(
              itemKey: 'synthetic',
              itemName: 'Synthetic food',
              unitPrice: 3,
              quantity: 1,
              total: 3,
            ),
          ],
          status: 'pending',
          totalAmount: 3,
          includeServiceFee: false,
          createdAt: DateTime.utc(2026, 10, 1),
          createdBy: 'synthetic-operator',
        ),
      );
    }
    if (scenario == 'reprint' || scenario == 'confirm') {
      await PrintQueue.enqueue(job());
      await dispatch();
      PrintQueue.stop();
    }
    mode = scenario == 'uncertain' ? 'flush-error' : 'sent';
    trace.clear();
  }

  int get persistedWriteCount {
    final file = File('$directory/transmitted.jsonl');
    return file.existsSync() ? file.readAsLinesSync().length : 0;
  }

  Future<void> close() async {
    PrintQueue.stop();
    if (flushBarrier != null && !flushBarrier!.isCompleted)
      flushBarrier!.complete();
    flushBarrier = null;
    await PrintQueue.idle;
    PrinterTransport.connectOverride = null;
    PrinterTransport.delayOverride = null;
    PrinterService.renderBytesOverride = null;
    PosSession.clear();
    await closeMenu01();
    HttpOverrides.global = previousHttp;
  }
}

class Pos02Socket implements PrinterWriteSocket {
  Pos02Socket(this.fixture);
  final Pos02Fixture fixture;
  @override
  void add(List<int> bytes) {
    fixture.transmitted.add(List.of(bytes));
    File('${fixture.directory}/transmitted.jsonl').writeAsStringSync(
      '${jsonEncode(bytes)}\n',
      mode: FileMode.append,
      flush: true,
    );
    if (fixture.mode == 'add-error')
      throw const SocketException('synthetic partial add');
  }

  @override
  Future<void> flush() async {
    await fixture.boundary('transport.after-add');
    await fixture.flushBarrier?.future;
    if (fixture.mode == 'flush-error')
      throw const SocketException('synthetic cable/power loss after write');
  }

  @override
  Future<void> close() async {
    await fixture.boundary('transport.after-flush');
    if (fixture.mode == 'close-error')
      throw const SocketException('synthetic close failure');
  }

  @override
  void destroy() {}
}
