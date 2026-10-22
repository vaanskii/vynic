import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/print_identity_admission.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/windows_spooler_transport.dart';

class _ThrowingMethodChannel extends MethodChannel {
  _ThrowingMethodChannel(this.failure) : super('synthetic/synchronous-failure');

  final Object failure;
  int calls = 0;

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) {
    calls++;
    throw failure;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vynic/windows_spooler');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late WindowsSpoolerTransport transport;
  late List<MethodCall> calls;

  void respond(Future<dynamic> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  Future<PrintTransmissionResult> submit({
    String queue = 'Synthetic receipt',
    String driver = 'Synthetic ESC/POS driver',
    String port = 'USB001',
    String document = 'JOB synthetic-1',
    List<int> bytes = const [0x1b, 0x40, 0x00],
    bool Function()? maySubmit,
  }) => transport.submit(
    queueName: queue,
    expectedDriverName: driver,
    expectedPortName: port,
    documentName: document,
    bytes: bytes,
    maySubmit: maySubmit,
  );

  setUp(() {
    expect(PrintIdentityAdmission.activeSubmissions, 0);
    expect(PrintIdentityAdmission.identityTransitionActive, isFalse);
    calls = [];
    transport = WindowsSpoolerTransport(
      channel: channel,
      isWindows: () => true,
    );
    respond((_) async => {'accepted': true, 'jobId': 42, 'bytesWritten': 3});
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await Future<void>.delayed(Duration.zero);
    expect(PrintIdentityAdmission.activeSubmissions, 0);
    expect(PrintIdentityAdmission.identityTransitionActive, isFalse);
  });

  test('inventory is read-only and preserves exact descriptors', () async {
    respond(
      (_) async => [
        {
          'name': ' Synthetic ბ queue ',
          'driver': 'Class driver',
          'port': 'USB002',
        },
        {
          'name': 'Microsoft Print to PDF',
          'driver': 'Virtual driver',
          'port': 'PORTPROMPT:',
        },
      ],
    );
    final queues = await transport.listQueues();
    expect(queues.map((q) => q.name), [
      ' Synthetic ბ queue ',
      'Microsoft Print to PDF',
    ]);
    expect(queues.first.driver, 'Class driver');
    expect(queues.first.port, 'USB002');
    expect(calls.single.method, 'listQueues');
    expect(calls.single.arguments, isNull);
    expect(() => queues.clear(), throwsUnsupportedError);
  });

  test(
    'RAW acceptance means sent with no claim of paper confirmation',
    () async {
      final result = await submit(queue: 'Synthetic ; \$(unused)');
      expect(result.state, PrintTransmissionState.sent);
      expect(result.detail, contains('paper output is not confirmed'));
      expect(calls.single.method, 'submitRaw');
      expect(calls.single.arguments, {
        'queueName': 'Synthetic ; \$(unused)',
        'expectedDriverName': 'Synthetic ESC/POS driver',
        'expectedPortName': 'USB001',
        'documentName': 'JOB synthetic-1',
        'bytes': Uint8List.fromList([0x1b, 0x40, 0]),
      });
    },
  );

  test('freezes caller bytes before any asynchronous reply', () async {
    final gate = Completer<Map<String, dynamic>>();
    respond((_) => gate.future);
    final bytes = [0x1b, 0x40, 0];
    final sending = submit(bytes: bytes);
    bytes[0] = 99;
    await Future<void>.delayed(Duration.zero);
    expect((calls.single.arguments as Map)['bytes'], [0x1b, 0x40, 0]);
    gate.complete({'accepted': true, 'jobId': 4, 'bytesWritten': 3});
    expect((await sending).sent, isTrue);
  });

  for (final stage in [
    'validate',
    'enumerate',
    'selectQueue',
    'openPrinter',
    'inspectPrinter',
    'dispatch',
  ]) {
    test('$stage failure before StartDoc is notSent without a retry', () async {
      respond(
        (_) async => throw PlatformException(
          code: 'vynic_spooler_error',
          message: 'Synthetic pre-submission failure',
          details: {'stage': stage, 'writeAttempted': false, 'windowsError': 5},
        ),
      );
      final result = await submit();
      expect(result.state, PrintTransmissionState.notSent);
      expect(result.detail, contains(stage));
      expect(result.detail, contains('Windows error 5'));
      expect(calls, hasLength(1));
    });
  }

  for (final stage in [
    'startDocPrinter',
    'startPagePrinter',
    'writePrinter',
    'endPagePrinter',
    'endDocPrinter',
    'closePrinter',
    'shutdown',
    'nativeException',
  ]) {
    test('$stage attempted failure is uncertain without a retry', () async {
      respond(
        (_) async => throw PlatformException(
          code: 'vynic_spooler_error',
          message: 'Synthetic uncertain failure',
          details: {
            'stage': stage,
            'writeAttempted': true,
            'windowsError': 1726,
          },
        ),
      );
      final result = await submit();
      expect(result.state, PrintTransmissionState.uncertain);
      expect(result.detail, contains('labeled reprint'));
      expect(calls, hasLength(1));
    });
  }

  test(
    'a post-StartDoc stage cannot falsely claim no write was attempted',
    () async {
      respond(
        (_) async => throw PlatformException(
          code: 'vynic_spooler_error',
          details: {'stage': 'startDocPrinter', 'writeAttempted': false},
        ),
      );
      expect((await submit()).state, PrintTransmissionState.uncertain);
    },
  );

  test('unknown or incomplete channel errors are uncertain', () async {
    for (final failure in [
      PlatformException(code: 'vynic_spooler_error'),
      PlatformException(
        code: 'vynic_spooler_error',
        details: {'stage': 'openPrinter'},
      ),
      PlatformException(
        code: 'vynic_spooler_error',
        details: {'stage': 'unknown', 'writeAttempted': false},
      ),
      PlatformException(
        code: 'different_adapter',
        details: {'stage': 'openPrinter', 'writeAttempted': false},
      ),
    ]) {
      respond((_) async => throw failure);
      expect((await submit()).state, PrintTransmissionState.uncertain);
    }
    expect(calls, hasLength(4));
  });

  test('incomplete success replies cannot claim spool acceptance', () async {
    for (final reply in [
      null,
      false,
      {'accepted': true},
      {'accepted': true, 'jobId': 0, 'bytesWritten': 3},
      {'accepted': true, 'jobId': 42, 'bytesWritten': 2},
      {'accepted': false, 'jobId': 42, 'bytesWritten': 3},
    ]) {
      respond((_) async => reply);
      expect((await submit()).state, PrintTransmissionState.uncertain);
    }
    expect(calls, hasLength(6));
  });

  test('response timeout is uncertain and never repeats submission', () async {
    final lateReply = Completer<Map<String, dynamic>>();
    transport = WindowsSpoolerTransport(
      channel: channel,
      isWindows: () => true,
      responseTimeout: const Duration(milliseconds: 5),
    );
    respond((_) => lateReply.future);
    expect((await submit()).state, PrintTransmissionState.uncertain);
    expect(calls, hasLength(1));
    expect(PrintIdentityAdmission.activeSubmissions, 1);
    var changedIdentity = false;
    await expectLater(
      PrintIdentityAdmission.changeIdentity(() async => changedIdentity = true),
      throwsStateError,
    );
    expect(changedIdentity, isFalse);
    expect(PrintIdentityAdmission.activeSubmissions, 1);
    lateReply.complete({'accepted': true, 'jobId': 42, 'bytesWritten': 3});
    await Future<void>.delayed(Duration.zero);
    expect(PrintIdentityAdmission.activeSubmissions, 0);
    await PrintIdentityAdmission.changeIdentity(
      () async => changedIdentity = true,
    );
    expect(changedIdentity, isTrue);
  });

  test(
    'a late native error releases the timeout lease without an unhandled error',
    () async {
      final lateReply = Completer<Map<String, dynamic>>();
      transport = WindowsSpoolerTransport(
        channel: channel,
        isWindows: () => true,
        responseTimeout: const Duration(milliseconds: 5),
      );
      respond((_) => lateReply.future);
      expect((await submit()).state, PrintTransmissionState.uncertain);
      expect(PrintIdentityAdmission.activeSubmissions, 1);
      lateReply.completeError(
        PlatformException(
          code: 'vynic_spooler_error',
          details: {'stage': 'writePrinter', 'writeAttempted': true},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(PrintIdentityAdmission.activeSubmissions, 0);
      expect(calls, hasLength(1));
      await PrintIdentityAdmission.changeIdentity(() async {});
    },
  );

  test(
    'active identity transition blocks admission before the channel call',
    () async {
      final transitionGate = Completer<void>();
      final transition = PrintIdentityAdmission.changeIdentity(
        () => transitionGate.future,
      );
      expect(PrintIdentityAdmission.identityTransitionActive, isTrue);
      try {
        expect((await submit()).state, PrintTransmissionState.notSent);
        expect(calls, isEmpty);
        expect(PrintIdentityAdmission.activeSubmissions, 0);
      } finally {
        transitionGate.complete();
        await transition;
      }
      expect(PrintIdentityAdmission.identityTransitionActive, isFalse);
    },
  );

  test(
    'changed ownership guard refuses admission before the channel call',
    () async {
      var stillOwned = true;
      var guardCalls = 0;
      bool guard() {
        guardCalls++;
        return stillOwned;
      }

      stillOwned = false;
      final result = await submit(maySubmit: guard);
      expect(result.state, PrintTransmissionState.notSent);
      expect(guardCalls, 1);
      expect(calls, isEmpty);
      expect(PrintIdentityAdmission.activeSubmissions, 0);
    },
  );

  test(
    'throwing ownership guard refuses admission without acquiring a lease',
    () async {
      final result = await submit(
        maySubmit: () => throw StateError('Synthetic changed owner'),
      );
      expect(result.state, PrintTransmissionState.notSent);
      expect(calls, isEmpty);
      expect(PrintIdentityAdmission.activeSubmissions, 0);
    },
  );

  test(
    'guard and channel invocation share synchronous identity admission',
    () async {
      final nativeGate = Completer<Map<String, dynamic>>();
      var guardSawNoLease = false;
      respond((_) {
        expect(PrintIdentityAdmission.activeSubmissions, 1);
        return nativeGate.future;
      });
      final sending = submit(
        maySubmit: () {
          guardSawNoLease = PrintIdentityAdmission.activeSubmissions == 0;
          return true;
        },
      );
      expect(guardSawNoLease, isTrue);
      expect(PrintIdentityAdmission.activeSubmissions, 1);
      nativeGate.complete({'accepted': true, 'jobId': 42, 'bytesWritten': 3});
      expect((await sending).state, PrintTransmissionState.sent);
      expect(PrintIdentityAdmission.activeSubmissions, 0);
    },
  );

  test(
    'native prewrite failure releases admission when original call settles',
    () async {
      final nativeGate = Completer<Map<String, dynamic>>();
      respond((_) => nativeGate.future);
      final sending = submit();
      expect(PrintIdentityAdmission.activeSubmissions, 1);
      await expectLater(
        PrintIdentityAdmission.changeIdentity(() async {}),
        throwsStateError,
      );
      nativeGate.completeError(
        PlatformException(
          code: 'vynic_spooler_error',
          details: {'stage': 'openPrinter', 'writeAttempted': false},
        ),
      );
      expect((await sending).state, PrintTransmissionState.notSent);
      expect(PrintIdentityAdmission.activeSubmissions, 0);
      await PrintIdentityAdmission.changeIdentity(() async {});
      expect(calls, hasLength(1));
    },
  );

  test(
    'synchronous invocation failures release admission exactly once',
    () async {
      for (final failure in [
        StateError('Synthetic synchronous invocation failure'),
        MissingPluginException('Synthetic synchronous missing adapter'),
      ]) {
        final throwingChannel = _ThrowingMethodChannel(failure);
        transport = WindowsSpoolerTransport(
          channel: throwingChannel,
          isWindows: () => true,
        );
        final result = await submit();
        expect(
          result.state,
          failure is MissingPluginException
              ? PrintTransmissionState.notSent
              : PrintTransmissionState.uncertain,
        );
        expect(throwingChannel.calls, 1);
        expect(PrintIdentityAdmission.activeSubmissions, 0);
        await PrintIdentityAdmission.changeIdentity(() async {});
      }
    },
  );

  test('missing native adapter is notSent', () async {
    respond(
      (_) async =>
          throw MissingPluginException('Synthetic unavailable adapter'),
    );
    expect((await submit()).state, PrintTransmissionState.notSent);
    expect(calls, hasLength(1));
  });

  test(
    'unsupported platforms reject both paths before invoking the channel',
    () async {
      transport = WindowsSpoolerTransport(
        channel: channel,
        isWindows: () => false,
      );
      expect((await submit()).state, PrintTransmissionState.notSent);
      await expectLater(transport.listQueues(), throwsUnsupportedError);
      expect(calls, isEmpty);
    },
  );

  test(
    'invalid configuration and bytes reject before invoking the channel',
    () async {
      final results = await Future.wait([
        submit(queue: ''),
        submit(queue: '  '),
        submit(queue: 'name\u0000other'),
        submit(queue: 'name\nother'),
        submit(queue: 'q' * 256),
        submit(driver: ''),
        submit(driver: 'd' * 1025),
        submit(port: ''),
        submit(port: 'port\r'),
        submit(port: 'p' * 1025),
        submit(document: ''),
        submit(document: 'd' * 256),
        submit(bytes: []),
        submit(bytes: [-1]),
        submit(bytes: [256]),
        submit(
          bytes: List<int>.filled(
            WindowsSpoolerTransport.maxTransmissionBytes + 1,
            0,
          ),
        ),
      ]);
      expect(
        results.every((r) => r.state == PrintTransmissionState.notSent),
        isTrue,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'invalid timeout rejects submission before invoking the channel',
    () async {
      transport = WindowsSpoolerTransport(
        channel: channel,
        isWindows: () => true,
        responseTimeout: Duration.zero,
      );
      expect((await submit()).state, PrintTransmissionState.notSent);
      expect(calls, isEmpty);
    },
  );

  test('inventory failures remain typed and visible', () async {
    respond(
      (_) async => throw PlatformException(
        code: 'vynic_spooler_error',
        message: 'Synthetic spooler service failure',
        details: {
          'stage': 'enumerate',
          'writeAttempted': false,
          'windowsError': 1722,
        },
      ),
    );
    await expectLater(
      transport.listQueues(),
      throwsA(
        isA<WindowsSpoolerException>()
            .having((e) => e.stage, 'stage', 'enumerate')
            .having((e) => e.writeAttempted, 'writeAttempted', false)
            .having((e) => e.windowsError, 'windowsError', 1722),
      ),
    );
    expect(calls.single.method, 'listQueues');
  });

  test(
    'malformed or duplicate inventory rows are not silently dropped',
    () async {
      for (final reply in [
        null,
        [
          {'name': 'one'},
        ],
        [
          {'name': 'a\u0000b', 'driver': 'd', 'port': 'p'},
        ],
        [
          {'name': 'one', 'driver': 'd', 'port': 'p'},
          {'name': 'one', 'driver': 'd', 'port': 'p'},
        ],
      ]) {
        respond((_) async => reply);
        await expectLater(transport.listQueues(), throwsFormatException);
      }
    },
  );
}
