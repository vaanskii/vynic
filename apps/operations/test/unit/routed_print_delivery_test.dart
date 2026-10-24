import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/pos_backup_format.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/printing/local_printer_catalog.dart';
import 'package:vynic/core/services/printing/optional_printer_beep.dart';
import 'package:vynic/core/services/printing/print_identity_admission.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';
import 'package:vynic/core/services/printing/windows_spooler_transport.dart';

import '../support/menu01_fixture.dart';
import '../support/pos02_fixture.dart';

const _channel = MethodChannel('vynic/synthetic_routed_print_delivery');
const _jobId = 'synthetic-routed-delivery';
const _printerId = 'synthetic-windows-kitchen';
const _foreignOwner = '20000000-0000-4000-8000-000000000099';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late Pos02Fixture fixture;
  late List<MethodCall> nativeCalls;
  late Future<dynamic> Function(MethodCall) nativeReply;

  PrinterDestination windows({String owner = menu01Device}) =>
      PrinterDestination.windowsSpooler(
        ownerDeviceId: owner,
        queueName: 'Synthetic Georgian RAW queue',
        driverName: 'Synthetic ESC/POS RAW driver',
        portName: 'USB-synthetic-001',
      );

  PrinterCapabilityProfile profile({bool beep = false}) =>
      PrinterCapabilityProfile.genericEscposRaster(
        paperWidthMm: 58,
        rasterWidthDots: 384,
        cutter: PrinterCutter.partial,
        beep: PrinterBeepSettings(
          enabled: beep,
          capability: PrinterBeepCapability.epsonEscA97Pattern,
        ),
      );

  PrintJob routedJob({
    String id = _jobId,
    String? venueId = menu01Venue,
    String owner = menu01Device,
    bool beep = false,
    List<int>? bytes,
  }) => PrintJob.create(
    id: id,
    target: PrintQueueTarget.kitchen,
    destination: windows(owner: owner),
    printerId: _printerId,
    routeRevision: 7,
    capabilityProfile: profile(beep: beep),
    label: 'Synthetic frozen Windows kitchen ticket',
    bytes: bytes ?? [0x1b, 0x40, 1, 2, 3, 0x1d, 0x56, 1],
    venueId: venueId,
  );

  Map<String, dynamic> accepted(MethodCall call) {
    expect(call.method, 'submitRaw');
    final arguments = call.arguments as Map;
    return {
      'accepted': true,
      'jobId': 41,
      'bytesWritten': (arguments['bytes'] as Uint8List).length,
    };
  }

  Future<String> backup() async => (await BackupRepository.createDataBackup(
    targetFilePath: '${root.path}/routed-backup.json',
  )).readAsString();

  String seal(Map<String, dynamic> payload) {
    payload.remove('integrity');
    PosBackupFormat.seal(payload);
    return jsonEncode(payload);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_routed_print_');
    fixture = Pos02Fixture();
    await fixture.open('${root.path}/source');
    await fixture.seed();
    PrintJobRepository.optionalSignalFailure = null;
    nativeCalls = [];
    nativeReply = (call) async => accepted(call);
    messenger.setMockMethodCallHandler(_channel, (call) async {
      nativeCalls.add(call);
      return nativeReply(call);
    });
    PrintQueue.spoolerOverride = WindowsSpoolerTransport(
      channel: _channel,
      isWindows: () => true,
    );
  });

  tearDown(() async {
    fixture.fault = null;
    await fixture.close();
    PrintQueue.spoolerOverride = null;
    PrintJobRepository.optionalSignalFailure = null;
    messenger.setMockMethodCallHandler(_channel, null);
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    expect(PrintIdentityAdmission.activeSubmissions, 0);
    await root.delete(recursive: true);
  });

  test(
    'v2 requires Venue and freezes owner, queue descriptors and profile',
    () {
      expect(() => routedJob(venueId: null), throwsFormatException);
      expect(() => routedJob(venueId: ''), throwsFormatException);
      final bytes = <int>[1, 2, 3];
      final job = routedJob(bytes: bytes);
      final expected = job.toMap();
      bytes[0] = 99;
      final mutable = job.toMap();
      mutable['destination']['ownerDeviceId'] = _foreignOwner;
      mutable['destination']['queueName'] = 'Changed queue';
      mutable['destination']['driverName'] = 'Changed driver';
      mutable['destination']['portName'] = 'Changed port';
      mutable['capabilityProfile']['rasterWidthDots'] = 576;
      expect(job.toMap(), expected);
      expect(job.protocolVersion, PrintJob.routedProtocol);
      expect(job.venueId, menu01Venue);
      expect(job.destination.toMap(), windows().toMap());
      expect(job.capabilityProfile.toMap(), profile().toMap());
      expect(base64Decode(job.toMap()['payload']), [1, 2, 3]);
      expect(job.toMap().containsKey('host'), false);
      expect(job.toMap().containsKey('port'), false);
    },
  );

  test(
    'stable v2 job ID refuses changed destination, revision and profile',
    () async {
      final job = routedJob();
      await PrintJobRepository.enqueue(job);
      final frozen = PrintJobRepository.read(job.id)!.toMap();
      for (final changed in [
        'ownerDeviceId',
        'queueName',
        'driverName',
        'portName',
        'printerId',
        'routeRevision',
        'capabilityProfile',
      ]) {
        final body = job.toMap();
        if (body['destination'].containsKey(changed)) {
          body['destination'][changed] = changed == 'ownerDeviceId'
              ? _foreignOwner
              : 'Changed synthetic descriptor';
        } else if (changed == 'printerId') {
          body['printerId'] = 'different-synthetic-printer';
        } else if (changed == 'routeRevision') {
          body['routeRevision'] = 8;
        } else {
          body['capabilityProfile']['rasterWidthDots'] = 576;
        }
        await expectLater(
          PrintJobRepository.enqueue(PrintJob.decode(body)),
          throwsStateError,
          reason: changed,
        );
        expect(PrintJobRepository.read(job.id)!.toMap(), frozen);
      }
      expect((await PrintJobRepository.enqueue(job)).toMap(), frozen);
      expect(PrintJobRepository.all(), hasLength(1));
      expect(nativeCalls, isEmpty);
      expect(fixture.connections, 0);
    },
  );

  test(
    'same-owner Windows delivery flushes sending and uses frozen bytes without TCP',
    () async {
      final job = routedJob();
      await PrintQueue.enqueue(job);
      // Editing the catalog describes future jobs only; this accepted job keeps
      // its original route revision, descriptors, rendered bytes and profile.
      await DatabaseCore.settingsBox!.put(
        LocalPrinterCatalog.routesSettingKey,
        [
          {
            'protocol': 1,
            'id': _printerId,
            'name': 'Changed synthetic route',
            'role': PrinterRole.kitchen.name,
            'revision': 8,
            'destination': PrinterDestination.windowsSpooler(
              ownerDeviceId: menu01Device,
              queueName: 'Future queue',
              driverName: 'Future driver',
              portName: 'USB-future',
            ).toMap(),
            'capabilityProfile': PrinterCapabilityProfile.genericEscposRaster(
              cutter: PrinterCutter.full,
            ).toMap(),
          },
        ],
      );
      nativeReply = (call) async {
        final durable = PrintJobRepository.read(job.id)!;
        expect(durable.state, PrintJobState.sending);
        final sending = fixture.trace.lastIndexOf('meta.put:sending:after');
        expect(sending, greaterThanOrEqualTo(0));
        expect(
          fixture.trace.lastIndexOf('meta.flush:after'),
          greaterThan(sending),
        );
        expect(call.arguments, {
          'queueName': job.destination.queueName,
          'expectedDriverName': job.destination.driverName,
          'expectedPortName': job.destination.portName,
          'documentName': 'Vynic JOB ${job.id}',
          'bytes': Uint8List.fromList(job.transmissionBytes),
        });
        expect((call.arguments as Map)['bytes'], [
          0x1b,
          0x40,
          ...base64Decode(job.toMap()['payload'] as String),
        ]);
        expect(
          durable.capabilityProfile.toMap(),
          job.capabilityProfile.toMap(),
        );
        expect(durable.routeRevision, 7);
        return accepted(call);
      };
      await fixture.dispatch();
      final delivered = PrintJobRepository.read(job.id)!;
      expect(delivered.state, PrintJobState.sent);
      expect(delivered.detail, contains('not confirmed'));
      expect(
        delivered.audit.where((event) => event['action'] == 'confirmed'),
        isEmpty,
      );
      expect(nativeCalls, hasLength(1));
      expect(fixture.connections, 0);
      expect(fixture.transmitted, isEmpty);
      await fixture.dispatch();
      expect(nativeCalls, hasLength(1));
    },
  );

  test(
    'foreign Windows owner is held before channel or TCP submission',
    () async {
      final job = routedJob(owner: _foreignOwner);
      await PrintQueue.enqueue(job);
      await fixture.dispatch();
      final held = PrintJobRepository.read(job.id)!;
      expect(held.state, PrintJobState.uncertain);
      expect(held.detail, contains('automatic delivery held'));
      expect(
        held.audit.where((event) => event['action'] == 'sending'),
        isEmpty,
      );
      expect(nativeCalls, isEmpty);
      expect(fixture.connections, 0);
      expect(fixture.transmitted, isEmpty);
      await fixture.dispatch();
      expect(nativeCalls, isEmpty);
    },
  );

  test(
    'v1 legacy TCP contract, payload and delivery remain unchanged',
    () async {
      final job = fixture.job(id: 'synthetic-legacy-route');
      final original = job.toMap();
      expect(job.protocolVersion, PrintJob.protocol);
      expect(job.destination.kind, PrinterTransportKind.tcp);
      expect(original['host'], 'synthetic.invalid');
      expect(original['port'], 9100);
      expect(original.containsKey('destination'), false);
      expect(original.containsKey('capabilityProfile'), false);
      expect(PrintJob.decode(original).toMap(), original);
      expect(PrintJob.decode({...original}..remove('venueId')).venueId, isNull);
      await PrintQueue.enqueue(job);
      await fixture.dispatch();
      final delivered = PrintJobRepository.read(job.id)!;
      expect(delivered.state, PrintJobState.sent);
      expect(fixture.connections, 1);
      expect(fixture.transmitted.single, job.transmissionBytes);
      expect(nativeCalls, isEmpty);
      expect(delivered.latest.containsKey('beep'), false);
      for (final field in [
        'protocol',
        'target',
        'host',
        'port',
        'label',
        'venueId',
        'payload',
        'payloadSha256',
      ]) {
        expect(delivered.toMap()[field], original[field]);
      }
    },
  );

  test(
    'backup duplicate v1/v2 logical job ID is rejected before any replacement',
    () async {
      final legacy = fixture.job(id: _jobId);
      await PrintQueue.enqueue(legacy);
      final payload = await PosBackupFormat.decode(await backup());
      final routed = routedJob(id: legacy.id);
      (payload['stores']['meta'] as List).add({
        'key': PosBackupFormat.encodeValue(
          PrintJobRepository.key(routed.id, protocol: routed.protocolVersion),
        ),
        'value': PosBackupFormat.encodeValue(routed.toMap()),
      });
      final sealed = seal(payload);
      PosBackupFormat.validate(await PosBackupFormat.decode(sealed));
      await DatabaseCore.metaBox!.put('destination-sentinel', {'keep': true});
      await DatabaseCore.settingsBox!.put('destinationSentinel', 'preserve');
      final beforeMeta = DatabaseCore.metaBox!.toMap();
      final beforeSettings = DatabaseCore.settingsBox!.toMap();
      final beforeOrders = {
        for (final entry in DatabaseCore.orderBox!.toMap().entries)
          entry.key: entry.value.toJson(),
      };
      await expectLater(
        BackupRepository.restoreDataBackupFromJson(
          sealed,
          backupBeforeRestore: false,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Conflicting print job identities'),
          ),
        ),
      );
      expect(DatabaseCore.metaBox!.toMap(), beforeMeta);
      expect(DatabaseCore.settingsBox!.toMap(), beforeSettings);
      expect({
        for (final entry in DatabaseCore.orderBox!.toMap().entries)
          entry.key: entry.value.toJson(),
      }, beforeOrders);
      expect(PrintJobRepository.all().single.toMap(), legacy.toMap());
      expect(nativeCalls, isEmpty);
      expect(fixture.connections, 0);
    },
  );

  test(
    'restored queued v2 job retains its frozen route and stays held after reenrollment',
    () async {
      final job = routedJob();
      await PrintQueue.enqueue(job);
      final payload = await backup();
      await fixture.close();
      await fixture.open('${root.path}/fresh');
      await BackupRepository.restoreDataBackupFromJson(
        payload,
        backupBeforeRestore: false,
      );
      final restored = PrintJobRepository.read(job.id)!;
      expect(restored.protocolVersion, PrintJob.routedProtocol);
      expect(restored.state, PrintJobState.uncertain);
      expect(restored.detail, contains('backup'));
      expect(restored.destination.toMap(), job.destination.toMap());
      expect(restored.capabilityProfile.toMap(), job.capabilityProfile.toMap());
      expect(restored.routeRevision, job.routeRevision);
      expect(restored.toMap()['payload'], job.toMap()['payload']);
      expect(restored.audit.take(job.audit.length), job.audit);
      expect(
        await EdgeDeviceCredentialStore.saveEnrollment(
          rawCredential: 'vynic-device-v1.$menu01Device.${'s' * 40}',
          venueId: menu01Venue,
          venueName: 'Synthetic matching owner after restore',
        ),
        true,
      );
      await fixture.dispatch();
      expect(PrintJobRepository.read(job.id)!.state, PrintJobState.uncertain);
      expect(nativeCalls, isEmpty);
      expect(fixture.connections, 0);
      expect(fixture.transmitted, isEmpty);
      final stable = PrintJobRepository.read(job.id)!.toMap();
      await BackupRepository.restoreDataBackupFromJson(
        payload,
        backupBeforeRestore: false,
      );
      expect(PrintJobRepository.read(job.id)!.toMap(), stable);
      expect(DatabaseCore.dbVersion, 9);
    },
  );

  test(
    'beep reservation is durable and never replayed across reopen',
    () async {
      final job = routedJob(beep: true);
      await PrintJobRepository.enqueue(job);
      expect(
        await PrintJobRepository.reserveBeep(job.id, job.attemptId),
        false,
      );
      await PrintJobRepository.transition(
        job.id,
        job.attemptId,
        PrintJobState.queued,
        PrintJobState.sending,
      );
      await PrintJobRepository.transition(
        job.id,
        job.attemptId,
        PrintJobState.sending,
        PrintJobState.sent,
        detail: 'Primary synthetic RAW delivery accepted',
      );
      expect(await PrintJobRepository.reserveBeep(job.id, job.attemptId), true);
      final reserved = PrintJobRepository.read(job.id)!;
      expect(reserved.latest['beep']['state'], 'reserved');
      final frozenReservation = reserved.toMap();
      final exposedAttempt = reserved.latest;
      exposedAttempt['beep']['state'] = 'failed';
      exposedAttempt['beep']['detail'] = 'Caller-owned mutation';
      expect(reserved.latest['beep']['state'], 'reserved');
      expect(reserved.toMap(), frozenReservation);
      expect(
        await PrintJobRepository.reserveBeep(job.id, job.attemptId),
        false,
      );
      await fixture.close();
      await fixture.open('${root.path}/source');
      expect(PrintJobRepository.read(job.id)!.toMap(), reserved.toMap());
      expect(
        await PrintJobRepository.reserveBeep(job.id, job.attemptId),
        false,
      );
      await fixture.dispatch();
      expect(nativeCalls, isEmpty);
      expect(fixture.connections, 0);
      const detail = 'Synthetic optional signal failed independently';
      final outcome = PrinterBeepResult(
        state: PrinterBeepState.failed,
        attemptId: job.attemptId,
        detail: detail,
      );
      await PrintJobRepository.settleBeep(job.id, outcome);
      final settled = PrintJobRepository.read(job.id)!;
      expect(settled.state, PrintJobState.sent);
      expect(settled.latest['beep']['state'], 'failed');
      expect(settled.latest['beep']['detail'], detail);
      expect(settled.toMap()['payload'], job.toMap()['payload']);
      expect(settled.attempts, hasLength(1));
      await expectLater(
        PrintJobRepository.settleBeep(job.id, outcome),
        throwsStateError,
      );
      expect(
        await PrintJobRepository.reserveBeep(job.id, job.attemptId),
        false,
      );
      expect(PrintJobRepository.failure, isNull);
      expect(nativeCalls, isEmpty);
    },
  );

  test(
    'optional beep uncertainty cannot change a sent primary or create a copy',
    () async {
      final job = routedJob(beep: true);
      final completed = <bool>[];
      nativeReply = (call) async {
        final stored = PrintJobRepository.read(job.id)!;
        if (nativeCalls.length == 1) {
          expect(stored.state, PrintJobState.sending);
          expect((call.arguments as Map)['bytes'], job.transmissionBytes);
          return accepted(call);
        }
        expect(stored.state, PrintJobState.sent);
        expect(stored.latest['beep']['state'], 'reserved');
        final put = fixture.trace.lastIndexOf('meta.put:sent:after');
        expect(fixture.trace.lastIndexOf('meta.flush:after'), greaterThan(put));
        expect(
          (call.arguments as Map)['documentName'],
          'Vynic signal ${job.attemptId}',
        );
        expect((call.arguments as Map)['bytes'], isNot(job.transmissionBytes));
        throw PlatformException(
          code: 'vynic_spooler_error',
          message: 'Synthetic optional signal uncertainty',
          details: {'stage': 'writePrinter', 'writeAttempted': true},
        );
      };
      await PrintQueue.enqueue(job, onComplete: completed.add);
      await fixture.dispatch();
      final settled = PrintJobRepository.read(job.id)!;
      expect(completed, [true]);
      expect(settled.state, PrintJobState.sent);
      expect(settled.latest['beep']['state'], 'uncertain');
      expect(settled.latest['beep']['detail'], contains('writePrinter'));
      expect(settled.detail, contains('not confirmed'));
      expect(settled.attempts, hasLength(1));
      expect(PrintJobRepository.failure, isNull);
      expect(nativeCalls, hasLength(2));
      expect(fixture.connections, 0);
      await fixture.dispatch();
      await fixture.close();
      await fixture.open('${root.path}/source');
      await fixture.dispatch();
      expect(nativeCalls, hasLength(2));
      expect(PrintJobRepository.read(job.id)!.state, PrintJobState.sent);
    },
  );

  test(
    'late beep outcome stays on its original attempt after deliberate reprint',
    () async {
      final job = routedJob(beep: true);
      final signalEntered = Completer<void>();
      final signalReply = Completer<Map<String, dynamic>>();
      nativeReply = (call) async {
        if (nativeCalls.length == 1) return accepted(call);
        expect(PrintJobRepository.read(job.id)!.state, PrintJobState.sent);
        expect(
          PrintJobRepository.read(job.id)!.latest['beep']['state'],
          'reserved',
        );
        signalEntered.complete();
        return signalReply.future;
      };
      await PrintQueue.enqueue(job);
      final delivering = fixture.dispatch();
      try {
        await signalEntered.future.timeout(const Duration(seconds: 3));
        await PrintJobRepository.reprint(
          job.id,
          job.attemptId,
          'synthetic-deliberate-reprint',
          'synthetic-operator',
          'Synthetic paper review requested a labeled copy',
        );
      } finally {
        PrintQueue.stop();
        if (!signalReply.isCompleted) {
          signalReply.complete({
            'accepted': true,
            'jobId': 42,
            'bytesWritten': 8,
          });
        }
        await delivering;
      }
      final settled = PrintJobRepository.read(job.id)!;
      expect(settled.attempts, hasLength(2));
      expect(settled.state, PrintJobState.reprint);
      expect(settled.attemptId, 'synthetic-deliberate-reprint');
      expect(settled.attempts.first['id'], job.attemptId);
      expect(settled.attempts.first['state'], PrintJobState.sent.name);
      expect(settled.attempts.first['beep']['state'], 'submitted');
      expect(settled.latest.containsKey('beep'), false);
      expect(settled.toMap()['payload'], job.toMap()['payload']);
      expect(
        await PrintJobRepository.reserveBeep(job.id, job.attemptId),
        false,
      );
      expect(PrintJobRepository.failure, isNull);
      expect(PrintJobRepository.optionalSignalFailure, isNull);
      expect(nativeCalls, hasLength(2));
      expect(fixture.connections, 0);
    },
  );

  test(
    'beep reservation persistence failure preserves primary success and prevents sound',
    () async {
      final job = routedJob(beep: true);
      final completed = <bool>[];
      fixture.fault = (point, _) async {
        if (point == 'meta.put:sent:before' &&
            PrintJobRepository.read(job.id)?.state == PrintJobState.sent) {
          throw StateError(
            'Synthetic optional reservation persistence failure',
          );
        }
      };
      await PrintQueue.enqueue(job, onComplete: completed.add);
      await fixture.dispatch();
      final delivered = PrintJobRepository.read(job.id)!;
      expect(completed, [true]);
      expect(delivered.state, PrintJobState.sent);
      expect(delivered.attempts, hasLength(1));
      expect(delivered.latest.containsKey('beep'), false);
      expect(PrintJobRepository.failure, isNull);
      expect(
        PrintJobRepository.optionalSignalFailure,
        contains('Optional printer signal audit failed'),
      );
      expect(nativeCalls, hasLength(1));
      expect(fixture.connections, 0);
      fixture.fault = null;
      await fixture.dispatch();
      expect(nativeCalls, hasLength(1));
    },
  );
}
