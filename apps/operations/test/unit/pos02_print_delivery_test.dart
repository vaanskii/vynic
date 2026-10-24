import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/local_venue_binding.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import '../support/pos02_fixture.dart';
import '../support/menu01_fixture.dart';
import 'package:vynic/core/services/pos/order_confirmation_print.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Pos02Fixture f;

  Future<void> rejectForeignEnrollment() async {
    final identityFile = File('${root.path}/edge_device.json');
    final before = await identityFile.readAsBytes();
    final credential = EdgeDeviceCredentialStore.credential;
    final device = EdgeDeviceCredentialStore.deviceId;
    final installation = EdgeDeviceCredentialStore.installationId;
    await expectLater(
      EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: 'vynic-device-v1.$menu01Device.${'s' * 40}',
        venueId: 'synthetic-other-venue',
        venueName: 'Other synthetic restaurant',
      ),
      throwsA(isA<LocalVenueMismatch>()),
    );
    expect(await identityFile.readAsBytes(), before);
    expect(EdgeDeviceCredentialStore.venueId, menu01Venue);
    expect(EdgeDeviceCredentialStore.credential, credential);
    expect(EdgeDeviceCredentialStore.deviceId, device);
    expect(EdgeDeviceCredentialStore.installationId, installation);
    DatabaseCore.validateVenueBinding(menu01Venue);
  }

  Future<void> reloadForeignSyntheticIdentity() async {
    // Enrollment rejects this transition. To exercise the later print fence,
    // model an out-of-band identity-file replacement followed by a real reload.
    // Only this test's temporary identity file is touched; this is not a
    // supported migration path and does not remove any production guard.
    expect(EdgeDeviceCredentialStore.directoryOverride, root.path);
    final identityFile = File('${root.path}/edge_device.json');
    final identity = jsonDecode(await identityFile.readAsString()) as Map;
    identity['venueId'] = 'synthetic-other-venue';
    await identityFile.writeAsString(jsonEncode(identity), flush: true);
    await EdgeDeviceCredentialStore.load();
    expect(EdgeDeviceCredentialStore.venueId, 'synthetic-other-venue');
    expect(
      () => DatabaseCore.validateVenueBinding('synthetic-other-venue'),
      throwsA(isA<LocalVenueMismatch>()),
    );
  }

  Future<bool> renderDocument(String kind) => switch (kind) {
    'kitchen' => PrinterService.printKitchenCheckInBackground(
      items: ['Synthetic food'],
    ),
    'receipt' => PrinterService.printReceiptInBackground(
      items: ['Synthetic receipt'],
      total: 3,
    ),
    'report' => PrinterService.printTextReport(
      'Synthetic report',
      reportType: 'X',
    ),
    _ => throw ArgumentError.value(kind),
  };

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_pos02_unit_');
    f = Pos02Fixture();
    await f.open(root.path);
    await f.seed();
  });
  tearDown(() async {
    await f.close();
    await root.delete(recursive: true);
  });

  test(
    'original tickets contain only the frozen document, not diagnostics',
    () async {
      for (final target in [
        PrintQueueTarget.kitchen,
        PrintQueueTarget.receipt,
      ]) {
        final job = f.job(id: 'original-${target.name}', target: target);
        await PrintQueue.enqueue(job);
        await f.dispatch();
        PrintQueue.stop();
        expect(f.transmitted.last, [
          0x1b,
          0x40,
          ...base64Decode(job.toMap()['payload'] as String),
        ]);
        final stored = PrintJobRepository.read(job.id)!;
        expect(stored.id, job.id);
        expect(stored.attemptId, job.id);
        expect(stored.state, PrintJobState.sent);
        expect(stored.audit.last['attemptId'], job.id);
        expect(stored.detail, isNotEmpty);
      }
    },
  );

  test(
    'acknowledged admission is flushed and survives a new Hive session before sending',
    () async {
      final input = f.job();
      await PrintQueue.enqueue(input);
      expect(f.connections, 0);
      expect(f.trace, contains('meta.flush:after'));
      await f.close();
      await f.open(root.path);
      expect(PrintJobRepository.read(input.id)!.toMap(), input.toMap());
      await f.dispatch();
      expect(f.transmitted, hasLength(1));
      expect(PrintJobRepository.read(input.id)!.state, PrintJobState.sent);
      expect(
        PrintJobRepository.read(
          input.id,
        )!.audit.where((e) => e['action'] == 'confirmed'),
        isEmpty,
      );
    },
  );
  for (final mode in ['add-error', 'flush-error', 'close-error']) {
    test(
      '$mode after write is uncertain and never retried/fallen back',
      () async {
        f.mode = mode;
        await PrintQueue.enqueue(f.job());
        await f.dispatch();
        expect(f.connections, 1);
        expect(f.transmitted, hasLength(1));
        expect(
          PrintJobRepository.read(Pos02Fixture.jobId)!.state,
          PrintJobState.uncertain,
        );
        await f.dispatch();
        expect(f.transmitted, hasLength(1));
        await f.close();
        await f.open(root.path);
        await f.dispatch();
        expect(f.transmitted, hasLength(1));
      },
    );
  }
  test(
    'connection refusal retries only before bytes and ends visibly not sent',
    () async {
      f.mode = 'connect-error';
      await PrintQueue.enqueue(f.job());
      await f.dispatch();
      expect(f.connections, 3);
      expect(f.transmitted, isEmpty);
      final before = PrintJobRepository.read(Pos02Fixture.jobId)!;
      expect(before.state, PrintJobState.failed);
      f.mode = 'sent';
      await PrintReconciliation.retryNotSent(
        before,
        'synthetic connection restored',
        'retry-one',
      );
      await f.dispatch();
      expect(f.transmitted, hasLength(1));
      expect(f.transmitted.single, [
        0x1b,
        0x40,
        ...base64Decode(before.toMap()['payload'] as String),
      ]);
      expect(PrintJobRepository.read(before.id)!.attempts, hasLength(1));
      await PrintReconciliation.retryNotSent(
        before,
        'synthetic connection restored',
        'retry-one',
      );
      await f.dispatch();
      expect(f.transmitted, hasLength(1));
    },
  );
  test(
    'flushed sending marker precedes every byte and blocks quit during transport',
    () async {
      f.flushBarrier = Completer<void>();
      UpdateReadiness.enabled = true;
      UpdateReadiness.startupReady = true;
      await PrintQueue.enqueue(f.job());
      PrintQueue.start();
      while (f.transmitted.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        PrintJobRepository.read(Pos02Fixture.jobId)!.state,
        PrintJobState.sending,
      );
      expect(
        f.trace.indexOf('transport.connect'),
        greaterThan(f.trace.indexOf('meta.flush:after')),
      );
      expect(UpdateReadiness.blockedReason, contains('პრინტერზე'));
      f.flushBarrier!.complete();
      f.flushBarrier = null;
      await PrintQueue.idle;
      expect(UpdateReadiness.blockedReason, isNull);
    },
  );
  test(
    'sending on startup becomes uncertain without any duplicate transmission',
    () async {
      final job = await PrintQueue.enqueue(f.job());
      await PrintJobRepository.transition(
        job.id,
        job.attemptId,
        PrintJobState.queued,
        PrintJobState.sending,
      );
      await f.close();
      await f.open(root.path);
      await f.dispatch();
      expect(f.transmitted, isEmpty);
      expect(PrintJobRepository.read(job.id)!.state, PrintJobState.uncertain);
    },
  );
  test(
    'a reprint is one flushed audited attempt with frozen content and only a copy label',
    () async {
      final job = await PrintQueue.enqueue(f.job());
      await f.dispatch();
      PrintQueue.stop();
      final expected = PrintJobRepository.read(job.id)!;
      await PrintReconciliation.reprint(
        expected,
        'original missing after paper check',
        Pos02Fixture.copyId,
      );
      await PrintReconciliation.reprint(
        expected,
        'original missing after paper check',
        Pos02Fixture.copyId,
      );
      final copy = PrintJobRepository.read(job.id)!;
      expect(copy.attempts, hasLength(2));
      expect(copy.state, PrintJobState.reprint);
      expect(copy.toMap()['payloadSha256'], job.toMap()['payloadSha256']);
      final printed = ascii.decode(copy.transmissionBytes, allowInvalid: true);
      expect(printed, contains('COPY\n'));
      expect(printed, isNot(contains('Original may already have printed')));
      expect(printed, isNot(contains('JOB ')));
      expect(printed, isNot(contains(job.id)));
      expect(copy.transmissionBytes, [
        0x1b,
        0x40,
        ...ascii.encode('COPY\n'),
        ...base64Decode(job.toMap()['payload'] as String),
      ]);
      expect(copy.audit.where((e) => e['action'] == 'reprint'), hasLength(1));
      expect(copy.audit.last['actorId'], 'synthetic-operator');
      await f.dispatch();
      expect(f.transmitted, hasLength(2));
      await PrintReconciliation.reprint(
        expected,
        'original missing after paper check',
        Pos02Fixture.copyId,
      );
      await f.dispatch();
      expect(f.transmitted, hasLength(2));
    },
  );
  test(
    'uncertain output stays held until an explicit minimally labeled copy',
    () async {
      final original = f.job();
      f.mode = 'flush-error';
      await PrintQueue.enqueue(original);
      await f.dispatch();
      PrintQueue.stop();
      final uncertain = PrintJobRepository.read(original.id)!;
      expect(uncertain.state, PrintJobState.uncertain);
      expect(f.transmitted.single, [
        0x1b,
        0x40,
        ...base64Decode(original.toMap()['payload'] as String),
      ]);
      await expectLater(
        PrintReconciliation.retryNotSent(
          uncertain,
          'check printer',
          'unsafe-retry',
        ),
        throwsStateError,
      );
      await f.dispatch();
      PrintQueue.stop();
      expect(f.transmitted, hasLength(1));
      f.mode = 'sent';
      await PrintReconciliation.reprint(
        uncertain,
        'paper checked',
        'checked-copy',
      );
      await PrintReconciliation.reprint(
        uncertain,
        'paper checked',
        'checked-copy',
      );
      await f.dispatch();
      expect(f.transmitted, hasLength(2));
      expect(f.transmitted.last, [
        0x1b,
        0x40,
        ...ascii.encode('COPY\n'),
        ...base64Decode(original.toMap()['payload'] as String),
      ]);
      final stored = PrintJobRepository.read(original.id)!;
      expect(stored.attempts, hasLength(2));
      expect(stored.attempts.first['state'], 'uncertain');
      expect(
        stored.audit.where((event) => event['action'] == 'reprint'),
        hasLength(1),
      );
      expect(stored.latest['actorId'], 'synthetic-operator');
      expect(stored.latest['reason'], 'paper checked');
    },
  );
  test(
    'stale copy request, duplicate id with changed reason and empty reason are refused',
    () async {
      await PrintQueue.enqueue(f.job());
      await f.dispatch();
      PrintQueue.stop();
      final expected = PrintJobRepository.read(Pos02Fixture.jobId)!;
      await PrintReconciliation.reprint(
        expected,
        'synthetic checked missing',
        'copy-one',
      );
      await expectLater(
        PrintReconciliation.reprint(expected, 'another request', 'copy-two'),
        throwsStateError,
      );
      await expectLater(
        PrintReconciliation.reprint(expected, 'changed reason', 'copy-one'),
        throwsStateError,
      );
      await expectLater(
        PrintReconciliation.reprint(expected, ' ', 'copy-empty'),
        throwsArgumentError,
      );
    },
  );
  test(
    'paper confirmation is explicit, idempotent and never sends bytes',
    () async {
      await PrintQueue.enqueue(f.job());
      await f.dispatch();
      final expected = PrintJobRepository.read(Pos02Fixture.jobId)!;
      await PrintReconciliation.confirm(
        expected,
        'synthetic matching paper checked',
        'paper-one',
      );
      await PrintReconciliation.confirm(
        expected,
        'synthetic matching paper checked',
        'paper-one',
      );
      expect(f.transmitted, hasLength(1));
      final job = PrintJobRepository.read(expected.id)!;
      expect(job.state, PrintJobState.confirmed);
      expect(job.audit.where((e) => e['action'] == 'confirmed'), hasLength(1));
    },
  );
  test(
    'operator policy, logout and persisted role are enforced beyond disabled UI',
    () async {
      await PrintQueue.enqueue(f.job());
      await f.dispatch();
      final job = PrintJobRepository.read(Pos02Fixture.jobId)!;
      PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
      await expectLater(
        PrintReconciliation.confirm(job, 'synthetic check', 'action-one'),
        throwsStateError,
      );
      PrintReconciliation.policy = PrintReconciliationPolicy.administrators;
      await DatabaseCore.userBox!.put(
        'synthetic-operator',
        User(username: 'synthetic-operator', pinCode: '1234', role: 'waiter'),
      );
      await expectLater(
        PrintReconciliation.confirm(job, 'synthetic check', 'action-two'),
        throwsStateError,
      );
      PosSession.clear();
      await expectLater(
        PrintReconciliation.confirm(job, 'synthetic check', 'action-three'),
        throwsStateError,
      );
      expect(PrintJobRepository.read(job.id)!.state, PrintJobState.sent);
    },
  );
  test(
    'both destinations serialize even when configured to the same physical endpoint',
    () async {
      await PrintQueue.enqueue(f.job(id: 'one'));
      await PrintQueue.enqueue(
        f.job(id: 'two', target: PrintQueueTarget.receipt),
      );
      await f.dispatch();
      expect(f.transmitted, hasLength(2));
      expect(f.trace.where((e) => e == 'transport.connect'), hasLength(2));
      expect(
        PrintJobRepository.all().every((j) => j.state == PrintJobState.sent),
        isTrue,
      );
    },
  );
  test('failed durable admission does not send or report success', () async {
    f.fault = (point, _) async {
      if (point == 'meta.flush:before')
        throw const FileSystemException('synthetic flush failure');
    };
    await expectLater(
      PrintQueue.enqueue(f.job()),
      throwsA(isA<FileSystemException>()),
    );
    await f.dispatch();
    expect(f.transmitted, isEmpty);
    expect(PrintJobRepository.failure, contains('persistence failed'));
  });
  test(
    'exclusive backup admission holds new print jobs until released',
    () async {
      final barrier = Completer<void>();
      final admitted = Completer<void>();
      final exclusive = LocalDataAdmission.exclusive(() async {
        admitted.complete();
        await barrier.future;
      });
      await admitted.future;
      var stored = false;
      final pending = PrintQueue.enqueue(f.job()).then((_) => stored = true);
      await Future<void>.delayed(Duration.zero);
      expect(stored, isFalse);
      barrier.complete();
      await exclusive;
      await pending;
      expect(stored, isTrue);
      expect(PrintJobRepository.all(), hasLength(1));
    },
  );
  test(
    'background receipt admission awaits frozen rendering and Hive, not network',
    () async {
      final items = ['1x Synthetic meal - 5.00 GEL'];
      final accepted = PrinterService.printReceiptInBackground(
        items: items,
        total: 5,
        jobId: 'synthetic-rendered',
        language: 'en',
      );
      items.clear();
      expect(await accepted, isTrue);
      expect(f.connections, 0);
      final job = PrintJobRepository.read('synthetic-rendered')!;
      expect(job.target, PrintQueueTarget.receipt);
      expect(job.toMap()['payload'], isNotEmpty);
      await DatabaseCore.settingsBox!.put(
        'printerReceiptIp',
        'different.invalid',
      );
      await f.dispatch();
      expect(f.transmitted, hasLength(1));
      expect(job.host, 'synthetic.invalid');
    },
  );
  test('duplicate admission settles every callback with one write', () async {
    final results = <bool>[];
    await PrintQueue.enqueue(f.job(), onComplete: results.add);
    await PrintQueue.enqueue(f.job(), onComplete: results.add);
    await f.dispatch();
    expect(results, [true, true]);
    expect(f.transmitted, hasLength(1));
  });
  test(
    'final state flush failure settles waiters and never sends again',
    () async {
      final result = Completer<bool>();
      await PrintQueue.enqueue(f.job(), onComplete: result.complete);
      f.fault = (point, _) async {
        if (point == 'meta.flush:before' &&
            PrintJobRepository.read(Pos02Fixture.jobId)!.state ==
                PrintJobState.sent) {
          throw const FileSystemException('synthetic final flush failure');
        }
      };
      await f.dispatch();
      expect(await result.future.timeout(const Duration(seconds: 2)), false);
      expect(PrintJobRepository.failure, isNotNull);
      expect(f.transmitted, hasLength(1));
      await f.dispatch();
      expect(f.transmitted, hasLength(1));
    },
  );
  for (final checkpoint in ['meta.flush:before', 'transport.connect']) {
    test('Venue reload at $checkpoint holds bytes before add', () async {
      var changed = false;
      f.fault = (point, _) async {
        if (!changed &&
            point == checkpoint &&
            PrintJobRepository.read(Pos02Fixture.jobId)?.state ==
                PrintJobState.sending) {
          changed = true;
          await reloadForeignSyntheticIdentity();
        }
      };
      await PrintQueue.enqueue(f.job());
      await f.dispatch();
      expect(changed, true);
      expect(f.transmitted, isEmpty);
      expect(f.trace, isNot(contains('transport.after-add')));
      expect(f.connections, checkpoint == 'transport.connect' ? 1 : 0);
      expect(PrintJobRepository.failure, isNull);
      expect(PrintJobRepository.read(Pos02Fixture.jobId)!.venueId, menu01Venue);
      expect(
        PrintJobRepository.read(Pos02Fixture.jobId)!.state,
        PrintJobState.uncertain,
      );
      expect(
        PrintJobRepository.read(Pos02Fixture.jobId)!.detail,
        contains('held'),
      );
      await f.dispatch();
      expect(f.transmitted, isEmpty);
      expect(f.connections, checkpoint == 'transport.connect' ? 1 : 0);
    });
    test(
      'foreign enrollment at $checkpoint is rejected before identity changes',
      () async {
        var rejected = false;
        f.fault = (point, _) async {
          if (!rejected &&
              point == checkpoint &&
              PrintJobRepository.read(Pos02Fixture.jobId)?.state ==
                  PrintJobState.sending) {
            rejected = true;
            await rejectForeignEnrollment();
          }
        };
        final job = f.job();
        await PrintQueue.enqueue(job);
        await f.dispatch();
        expect(rejected, true);
        expect(PrintJobRepository.failure, isNull);
        expect(PrintJobRepository.read(job.id)!.state, PrintJobState.sent);
        expect(PrintJobRepository.read(job.id)!.venueId, menu01Venue);
        expect(f.transmitted, [job.transmissionBytes]);
        expect(f.connections, 1);
      },
    );
  }
  test('copy request replay after safe retry remains idempotent', () async {
    await PrintQueue.enqueue(f.job());
    await f.dispatch();
    PrintQueue.stop();
    final original = PrintJobRepository.read(Pos02Fixture.jobId)!;
    f.mode = 'connect-error';
    await PrintReconciliation.reprint(
      original,
      'synthetic deliberate copy',
      Pos02Fixture.copyId,
    );
    await f.dispatch();
    expect(PrintJobRepository.read(original.id)!.state, PrintJobState.failed);
    f.mode = 'sent';
    await PrintReconciliation.retryNotSent(
      PrintJobRepository.read(original.id)!,
      'synthetic reconnect',
      'retry-copy',
    );
    await f.dispatch();
    await PrintReconciliation.reprint(
      original,
      'synthetic deliberate copy',
      Pos02Fixture.copyId,
    );
    await f.dispatch();
    expect(f.transmitted, hasLength(2));
  });
  test(
    'stable copy identity rejects changed source, actor, reason and original-vs-copy',
    () async {
      PrintJob copy({
        String? source = 'sale/synthetic',
        String actor = 'synthetic-operator',
        String reason = 'synthetic copy',
      }) {
        final j = f.job();
        return PrintJob.create(
          id: j.id,
          target: j.target,
          host: j.host,
          port: j.port,
          label: j.label,
          bytes: base64Decode(j.toMap()['payload']),
          venueId: j.venueId,
          copyOf: source,
          copyActorId: source == null ? null : actor,
          copyReason: source == null ? null : reason,
        );
      }

      final j = copy();
      await PrintQueue.enqueue(j);
      await PrintQueue.enqueue(copy());
      for (final changed in [
        copy(source: null),
        copy(source: 'sale/different'),
        copy(actor: 'different-actor'),
        copy(reason: 'different reason'),
      ]) {
        await expectLater(PrintQueue.enqueue(changed), throwsStateError);
      }
      await f.dispatch();
      expect(f.transmitted, hasLength(1));
      expect(
        ascii.decode(
          f.transmitted.single.take(160).toList(),
          allowInvalid: true,
        ),
        contains('COPY\n'),
      );
      expect(j.audit.first['reason'], 'synthetic copy');
    },
  );
  test('forged confirmations and malformed audit history are refused', () {
    for (final mutation in [
      (Map<String, dynamic> b) {
        b['attempts'].last['state'] = 'confirmed';
      },
      (Map<String, dynamic> b) {
        b['audit'].add(Map<String, dynamic>.from(b['audit'].first));
      },
      (Map<String, dynamic> b) {
        b['attempts'].last['state'] = 'confirmed';
        b['audit'].add({
          'action': 'confirmed',
          'attemptId': b['id'],
          'at': b['createdAt'],
          'actorId': 'operator',
          'reason': 'checked',
        });
      },
      (Map<String, dynamic> b) {
        b['protocol'] = 99;
      },
      (Map<String, dynamic> b) {
        b['payloadSha256'] = 'wrong';
      },
    ]) {
      final b = f.job().toMap();
      mutation(b);
      expect(() => PrintJob.decode(b), throwsFormatException);
    }
  });

  test(
    'concurrent initial confirmations admit one frozen Order ticket',
    () async {
      final results = await Future.wait([
        PrinterService.printKitchenCheckInBackground(
          initialOrderUuid: 'synthetic-order-uuid',
          items: ['1x Synthetic food'],
          orderNumber: '100',
        ),
        PrinterService.printKitchenCheckInBackground(
          initialOrderUuid: 'synthetic-order-uuid',
          items: ['1x Synthetic food'],
          orderNumber: '100',
        ),
      ]);
      expect(results, [true, true]);
      expect(PrintJobRepository.all(), hasLength(1));
      final frozen = PrintJobRepository.all().single.toMap();
      await f.dispatch();
      expect(f.transmitted, hasLength(1));
      await PrinterService.printKitchenCheckInBackground(
        initialOrderUuid: 'synthetic-order-uuid',
        items: ['later Order contents'],
        orderNumber: '100',
      );
      await f.dispatch();
      expect(f.transmitted, hasLength(1));
      expect(
        PrintJobRepository.all().single.toMap()['payload'],
        frozen['payload'],
      );
    },
  );
  test(
    'remote creation receipt repairs crash gap between Order and initial print admission',
    () async {
      final p = f.remotePayload;
      final order = await DatabaseService.upsertMobileTakeawayOrder(
        posOrderId: p['posOrderId'] as int,
        requestId: p['requestId'] as String,
        waiterName: 'synthetic-operator',
        customerName: 'Synthetic customer',
        pickupTime: '',
        items: PosCommandApplier.parseOrderItems(p['items']),
        totalAmount: 3,
      );
      expect(order, isNotNull);
      expect(PrintJobRepository.all(), isEmpty);
      await f.close();
      await f.open(root.path);
      final response = await PosCommandApplier.upsertTakeawayOrder(p);
      expect(response.ok, true);
      expect(response.data['printJobQueued'], true);
      expect(PrintJobRepository.all(), hasLength(1));
      expect(
        PrintJobRepository.all().single.id,
        'kitchen-initial-${order!.orderUuid}',
      );
      await f.dispatch();
      final repeated = await PosCommandApplier.upsertTakeawayOrder(p);
      expect(repeated.data['printJobQueued'], true);
      await f.dispatch();
      expect(f.transmitted, hasLength(1));
      expect(
        DatabaseService.getAllOrders().where((o) => o.orderId == 100),
        hasLength(1),
      );
    },
  );
  for (final kind in ['kitchen', 'receipt', 'report']) {
    for (final foreignReload in [true, false]) {
      test(
        foreignReload
            ? '$kind freezes Venue and destination across deferred rendering and foreign reload'
            : '$kind rejects foreign enrollment while rendering and keeps its frozen destination',
        () async {
          final rendering = Completer<List<int>>();
          final renderStarted = Completer<void>();
          final raster = [0x1b, 0x40, ...ascii.encode('SYNTHETIC RASTER')];
          PrinterService.renderBytesOverride = () {
            renderStarted.complete();
            return rendering.future;
          };
          final sending = renderDocument(kind);
          Future<void>? destinationChange;
          try {
            await renderStarted.future.timeout(const Duration(seconds: 2));
            expect(PrintJobRepository.all(), isEmpty);
            expect(f.connections, 0);
            if (foreignReload) {
              await reloadForeignSyntheticIdentity();
            } else {
              await rejectForeignEnrollment();
            }
            // A later settings edit must not redirect the document already being
            // rendered, regardless of whether the identity transition succeeded.
            // Admission serializes ordinary settings writes with rendering.
            // Queue the edit without waiting on the render we still own.
            destinationChange = DatabaseCore.settingsBox!.putAll({
              'printerKitchenIp': 'future-printer.invalid',
              'printerReceiptIp': 'future-printer.invalid',
            });
          } finally {
            rendering.complete(raster);
            if (kind == 'report') PrintQueue.start();
          }
          await destinationChange.timeout(const Duration(seconds: 2));
          expect(
            await sending.timeout(const Duration(seconds: 2)),
            !foreignReload || kind != 'report',
          ); // reports await held delivery
          await f.dispatch();
          final job = PrintJobRepository.all().single;
          expect(job.venueId, menu01Venue);
          expect(job.host, 'synthetic.invalid');
          expect(job.port, 9100);
          expect(
            base64Decode(job.toMap()['payload'] as String),
            containsAllInOrder(raster),
          );
          expect(PrintJobRepository.failure, isNull);
          if (foreignReload) {
            expect(job.state, PrintJobState.uncertain);
            expect(job.detail, contains('held'));
            expect(f.transmitted, isEmpty);
            expect(f.connections, 0);
            await f.dispatch();
            expect(f.transmitted, isEmpty);
          } else {
            expect(job.state, PrintJobState.sent);
            expect(f.transmitted, [job.transmissionBytes]);
            expect(f.connections, 1);
          }
        },
      );
    }
    test(
      '$kind render failure cannot admit a blank ticket or return success',
      () async {
        PrinterService.renderBytesOverride = () =>
            Future<List<int>>.error(StateError('Synthetic renderer failed'));
        final accepted = kind == 'kitchen'
            ? await PrinterService.printKitchenCheckInBackground(
                items: ['Synthetic food'],
              )
            : kind == 'receipt'
            ? await PrinterService.printReceiptInBackground(
                items: ['Synthetic receipt'],
                total: 3,
              )
            : await PrinterService.printTextReport(
                'Synthetic report',
                reportType: 'X',
              );
        expect(accepted, false);
        expect(PrintJobRepository.all(), isEmpty);
        expect(f.transmitted, isEmpty);
      },
    );
  }
  for (final point in ['meta.put:queued:after', 'orders.put:confirmed:after']) {
    test(
      'local confirmation interruption at $point leaves recoverable original or held warning',
      () async {
        await f.prepare('localconfirm');
        var interrupted = false;
        f.fault = (p, _) async {
          if (!interrupted && p == point) {
            interrupted = true;
            throw const FileSystemException(
              'Synthetic confirmation interruption',
            );
          }
        };
        try {
          await f.action('localconfirm');
        } catch (_) {}
        expect(interrupted, true);
        // Close/reopen is supplemental here; the native harness proves SIGKILL without cleanup.
        f.fault = null;
        await f.close();
        await f.open(root.path);
        expect(PrintJobRepository.all(), hasLength(1));
        await f.dispatch();
        expect(
          PrintJobRepository.all().single.state,
          isIn([PrintJobState.uncertain, PrintJobState.sent]),
        );
        expect(f.transmitted.length, lessThanOrEqualTo(1));
      },
    );
  }
  test(
    'worker rechecks committed confirmation after waiting for its admission owner',
    () async {
      await f.prepare('localconfirm');
      final queued = Completer<void>(), release = Completer<void>();
      f.fault = (p, _) async {
        if (p == 'meta.flush:before' &&
            PrintJobRepository.all().any(
              (j) => j.id.startsWith('kitchen-initial-') && j.ready,
            )) {
          if (!queued.isCompleted) {
            queued.complete();
            await release.future;
          }
        }
      };
      final confirming = OrderConfirmationPrint.confirm(
        order: DatabaseService.getOrder(100)!,
        lines: ['1x Synthetic food'],
        tableLabel: 'Synthetic takeaway',
      );
      await queued.future;
      expect(DatabaseService.getOrder(100)!.status, 'pending');
      PrintQueue.start(); // outside the confirmation owner, like reinitialization
      await Future<void>.delayed(Duration.zero);
      release.complete();
      expect(await confirming, true);
      await f.dispatch();
      expect(PrintJobRepository.all().single.state, PrintJobState.sent);
      expect(f.transmitted, hasLength(1));
    },
  );
  test(
    'same-ID admission refuses a changed or removed confirmation predicate',
    () async {
      final guarded = f.job().toMap()
        ..['requiresConfirmedOrderUuid'] = 'synthetic-confirmed-order';
      await PrintQueue.enqueue(PrintJob.decode(guarded));
      for (final guard in [null, 'different-order']) {
        final altered = f.job().toMap();
        if (guard != null) altered['requiresConfirmedOrderUuid'] = guard;
        await expectLater(
          PrintQueue.enqueue(PrintJob.decode(altered)),
          throwsStateError,
        );
      }
      expect(f.transmitted, isEmpty);
    },
  );
  test(
    'an unbound frozen ticket is held when enrollment appears during rendering',
    () async {
      EdgeDeviceCredentialStore.resetForTest();
      final rendering = Completer<List<int>>();
      PrinterService.renderBytesOverride = () => rendering.future;
      final admission = PrinterService.printKitchenCheckInBackground(
        items: ['Synthetic unbound food'],
      );
      await Future<void>.delayed(Duration.zero);
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: 'vynic-device-v1.$menu01Device.${'s' * 40}',
        venueId: menu01Venue,
        venueName: 'Synthetic restaurant',
      );
      rendering.complete([0x1b, 0x40, ...ascii.encode('SYNTHETIC')]);
      expect(await admission, true);
      await f.dispatch();
      final job = PrintJobRepository.all().single;
      expect(job.venueId, isNull);
      expect(job.state, PrintJobState.uncertain);
      expect(f.transmitted, isEmpty);
      await expectLater(
        PrintReconciliation.reprint(job, 'synthetic copy', 'synthetic-copy'),
        throwsStateError,
      );
    },
  );
  test(
    'legacy copy APIs enforce policy and persist visible copy provenance',
    () async {
      PrinterService.renderBytesOverride = () async => [
        0x1b,
        0x40,
        ...ascii.encode('SYNTHETIC'),
      ];
      PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
      expect(
        await PrinterService.printReceiptInBackground(
          items: ['Synthetic sale'],
          total: 3,
          copyOf: 'sale/synthetic',
          copyReason: 'synthetic reason',
        ),
        false,
      );
      expect(PrintJobRepository.all(), isEmpty);
      PrintReconciliation.policy = PrintReconciliationPolicy.administrators;
      for (final target in ['receipt', 'kitchen']) {
        final accepted = target == 'receipt'
            ? await PrinterService.printReceiptInBackground(
                items: ['Synthetic sale'],
                total: 3,
                copyOf: 'sale/synthetic',
                copyReason: 'synthetic reason',
              )
            : await PrinterService.printKitchenCheckInBackground(
                items: ['Synthetic food'],
                copyOf: 'order/synthetic',
                copyReason: 'synthetic reason',
              );
        expect(accepted, true);
      }
      await f.dispatch();
      expect(f.transmitted, hasLength(2));
      for (final job in PrintJobRepository.all()) {
        expect(job.copyOf, isNotNull);
        expect(job.audit.first['actorId'], 'synthetic-operator');
        expect(
          job.audit.first['reason'],
          job.target == PrintQueueTarget.kitchen
              ? PrintReconciliation.kitchenCopyReason
              : 'synthetic reason',
        );
        expect(
          ascii.decode(job.transmissionBytes, allowInvalid: true),
          contains('COPY\n'),
        );
      }
    },
  );
}
