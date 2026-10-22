import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';
import 'package:vynic/core/services/printing/print_identity_admission.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/windows_spooler_transport.dart';
import '../support/pos02_fixture.dart';
import '../support/menu01_fixture.dart' show menu01Venue;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('synthetic/print-credential-admission');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const replacementDevice = '30000000-0000-4000-8000-000000000003';
  final replacement = 'vynic-device-v1.$replacementDevice.${'t' * 40}';
  final reply = {'accepted': true, 'jobId': 42, 'bytesWritten': 3};
  late Directory root;
  late Pos02Fixture fixture;
  late WindowsSpoolerTransport transport;
  late List<MethodCall> calls;
  Completer<Map<String, dynamic>>? nativeCompletion;

  File getCredentialFile() => File('${root.path}/edge_device.json');
  Map<String, Object?> identity() => {
    'credential': EdgeDeviceCredentialStore.credential,
    'installationId': EdgeDeviceCredentialStore.installationId,
    'deviceId': EdgeDeviceCredentialStore.deviceId,
    'venueId': EdgeDeviceCredentialStore.venueId,
    'venueName': EdgeDeviceCredentialStore.venueName,
    'enrolledAt': EdgeDeviceCredentialStore.enrolledAt,
    'loaded': EdgeDeviceCredentialStore.isLoaded,
  };

  Future<void> change(String operation) async {
    switch (operation) {
      case 'load':
        await EdgeDeviceCredentialStore.load();
      case 'save':
        expect(await EdgeDeviceCredentialStore.save(replacement), true);
      case 'saveEnrollment':
        expect(
          await EdgeDeviceCredentialStore.saveEnrollment(
            rawCredential: replacement,
            venueId: menu01Venue,
            venueName: 'Synthetic replacement',
            enrolledAt: DateTime.utc(2026, 10, 6),
          ),
          true,
        );
      case 'clear':
        await EdgeDeviceCredentialStore.clear();
      default:
        throw StateError('Unknown test identity operation');
    }
  }

  Future<PrintTransmissionResult> submit() => transport.submit(
    queueName: 'Synthetic station',
    expectedDriverName: 'Synthetic ESC/POS driver',
    expectedPortName: 'USB-SYNTHETIC',
    bytes: const [0x1b, 0x40, 0],
    documentName: 'Synthetic identity-admission job',
  );

  setUp(() async {
    expect(PrintIdentityAdmission.activeSubmissions, 0);
    expect(PrintIdentityAdmission.identityTransitionActive, false);
    root = await Directory.systemTemp.createTemp('vynic_credential_admission_');
    fixture = Pos02Fixture();
    await fixture.open(root.path);
    await fixture.seed();
    UpdateReadiness.enabled = true;
    UpdateReadiness.startupReady = true;
    calls = [];
    nativeCompletion = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      expect(call.method, 'submitRaw');
      return nativeCompletion == null ? reply : nativeCompletion!.future;
    });
    transport = WindowsSpoolerTransport(
      channel: channel,
      isWindows: () => true,
      responseTimeout: const Duration(milliseconds: 10),
    );
    expect(EdgeDeviceCredentialStore.hasCredential, true);
    expect(getCredentialFile().existsSync(), true);
    expect(UpdateReadiness.blockedReason, isNull);
  });

  tearDown(() async {
    if (nativeCompletion != null && !nativeCompletion!.isCompleted) {
      nativeCompletion!.complete(reply);
    }
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(channel, null);
    expect(PrintIdentityAdmission.activeSubmissions, 0);
    expect(PrintIdentityAdmission.identityTransitionActive, false);
    UpdateReadiness.enabled = false;
    UpdateReadiness.startupReady = false;
    UpdateReadiness.frozen = false;
    await fixture.close();
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    await root.delete(recursive: true);
  });

  for (final lateOutcome in ['success', 'error']) {
    test(
      'stored credentials and updater stay held through timeout and late $lateOutcome',
      () async {
        final before = identity();
        final disk = getCredentialFile().readAsBytesSync();
        final provision = File('${root.path}/edge_device_provision.txt')
          ..writeAsStringSync(replacement, flush: true);
        final provisionBytes = provision.readAsBytesSync();
        nativeCompletion = Completer<Map<String, dynamic>>();
        final sending = submit();
        expect(PrintIdentityAdmission.activeSubmissions, 1);

        Future<void> expectHeld() async {
          for (final operation in ['load', 'save', 'saveEnrollment', 'clear']) {
            await expectLater(change(operation), throwsStateError);
            expect(identity(), before, reason: operation);
            expect(
              getCredentialFile().readAsBytesSync(),
              disk,
              reason: operation,
            );
            expect(
              provision.readAsBytesSync(),
              provisionBytes,
              reason: operation,
            );
          }
          expect(PrintIdentityAdmission.activeSubmissions, 1);
          expect(UpdateReadiness.evaluate().status, 'BLOCKED');
          expect(
            UpdateReadiness.blockedReason,
            UpdateReadiness.operationLabel('Print transmission'),
          );
          var updaterClosedData = false;
          expect(
            await UpdateReadiness.freeze(() async => updaterClosedData = true),
            UpdateReadiness.operationLabel('Print transmission'),
          );
          expect(updaterClosedData, false);
          expect(UpdateReadiness.frozen, false);
        }

        await expectHeld();
        final timeout = await sending;
        expect(timeout.state, PrintTransmissionState.uncertain);
        expect(calls, hasLength(1));
        await expectHeld();
        if (lateOutcome == 'success') {
          nativeCompletion!.complete(reply);
        } else {
          nativeCompletion!.completeError(
            PlatformException(
              code: 'vynic_spooler_error',
              message: 'Synthetic late native failure',
              details: {'stage': 'writePrinter', 'writeAttempted': true},
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);
        expect(PrintIdentityAdmission.activeSubmissions, 0);
        expect(UpdateReadiness.evaluate().status, 'READY');
        expect(identity(), before);
        expect(getCredentialFile().readAsBytesSync(), disk);
        expect(calls, hasLength(1));
        expect(timeout.state, PrintTransmissionState.uncertain);

        // Exercise the real formerly blocked operation after native settlement.
        await EdgeDeviceCredentialStore.load();
        expect(EdgeDeviceCredentialStore.credential, replacement);
        expect(EdgeDeviceCredentialStore.deviceId, replacementDevice);
        expect(provision.existsSync(), false);
        expect(getCredentialFile().readAsBytesSync(), isNot(disk));
        var updaterClosedData = false;
        expect(
          await UpdateReadiness.freeze(() async => updaterClosedData = true),
          isNull,
        );
        expect(updaterClosedData, true);
        UpdateReadiness.frozen = false;
      },
    );
  }

  for (final operation in ['load', 'save', 'saveEnrollment', 'clear']) {
    test(
      'real $operation begins identity transition before native admission',
      () async {
        final installationId = EdgeDeviceCredentialStore.installationId;
        final diskBefore = getCredentialFile().readAsBytesSync();
        if (operation == 'load') {
          final changed =
              jsonDecode(getCredentialFile().readAsStringSync()) as Map;
          changed['credential'] = replacement;
          getCredentialFile().writeAsStringSync(
            jsonEncode(changed),
            flush: true,
          );
        }
        final changing = change(operation);
        expect(PrintIdentityAdmission.identityTransitionActive, true);
        try {
          final blocked = await submit();
          expect(blocked.state, PrintTransmissionState.notSent);
          expect(calls, isEmpty);
          expect(PrintIdentityAdmission.activeSubmissions, 0);
        } finally {
          await changing;
        }
        expect(PrintIdentityAdmission.identityTransitionActive, false);
        expect(EdgeDeviceCredentialStore.installationId, installationId);
        final stored =
            jsonDecode(getCredentialFile().readAsStringSync()) as Map;
        if (operation == 'clear') {
          expect(EdgeDeviceCredentialStore.credential, isNull);
          expect(EdgeDeviceCredentialStore.deviceId, isNull);
          expect(EdgeDeviceCredentialStore.venueId, isNull);
          expect(stored.containsKey('credential'), false);
        } else {
          expect(EdgeDeviceCredentialStore.credential, replacement);
          expect(EdgeDeviceCredentialStore.deviceId, replacementDevice);
          expect(stored['credential'], replacement);
        }
        if (operation == 'saveEnrollment') {
          expect(EdgeDeviceCredentialStore.venueId, menu01Venue);
          expect(stored['venueId'], menu01Venue);
        }
        expect(getCredentialFile().readAsBytesSync(), isNot(diskBefore));
        expect((await submit()).state, PrintTransmissionState.sent);
        expect(calls, hasLength(1));
        expect(PrintIdentityAdmission.activeSubmissions, 0);
      },
    );
  }
}
