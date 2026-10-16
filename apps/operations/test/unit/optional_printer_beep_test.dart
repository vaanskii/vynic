import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/optional_printer_beep.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';

void main() {
  PrinterCapabilityProfile compatible() =>
      PrinterCapabilityProfile.genericEscposRaster(
        beep: const PrinterBeepSettings(
          capability: PrinterBeepCapability.epsonEscA97Pattern,
          enabled: true,
        ),
      );

  final sent = const PrintTransmissionResult(
    PrintTransmissionState.sent,
    'Fake transport accepted bytes, no hardware used',
  );

  test(
    'disabled, unknown, unsupported and incompatible profiles make no calls',
    () async {
      final generic = PrinterCapabilityProfile.genericEscposRaster();
      final profiles = [
        generic,
        PrinterCapabilityProfile.genericEscposRaster(
          beep: const PrinterBeepSettings(
            capability: PrinterBeepCapability.epsonEscA97Pattern,
          ),
        ),
        for (final capability in [
          PrinterBeepCapability.unknown,
          PrinterBeepCapability.unsupported,
        ])
          PrinterCapabilityProfile.genericEscposRaster(
            beep: PrinterBeepSettings(capability: capability, enabled: true),
          ),
        PrinterCapabilityProfile.decode({
          ...generic.toMap(),
          'beep': {'capability': 'otherVendorBeep', 'enabled': true},
        }),
        PrinterCapabilityProfile.decode({
          ...generic.toMap(),
          'beep': {
            'capability': 'epsonEscA97Pattern',
            'enabled': true,
            'command': [0x07],
          },
        }),
        PrinterCapabilityProfile(
          paperWidthMm: 80,
          rasterWidthDots: 576,
          language: PrinterCommandLanguage.windowsDriverRendered,
          cutter: PrinterCutter.none,
          beep: compatible().beep,
        ),
      ];
      for (final profile in profiles) {
        final result = await OptionalPrinterBeep.submit(
          attemptId: 'attempt-original',
          profile: profile,
          reserve: (_) async => throw StateError('must not reserve'),
          send: (_) async => throw StateError('must not send'),
        );
        expect(result.state, PrinterBeepState.skipped);
        expect(result.attemptId, 'attempt-original');
        expect(result.detail, isNotEmpty);
      }
    },
  );

  test(
    'waits for durable reservation before one bounded known command',
    () async {
      final committed = Completer<bool>();
      var reservations = 0, sends = 0;
      final pending = OptionalPrinterBeep.submit(
        attemptId: 'attempt-original',
        profile: compatible(),
        reserve: (attempt) {
          expect(attempt, 'attempt-original');
          reservations++;
          return committed.future;
        },
        send: (command) async {
          sends++;
          expect(committed.isCompleted, true);
          expect(command, [0x1b, 0x28, 0x41, 0x03, 0x00, 0x61, 0x01, 0x01]);
          expect(() => command.add(0x07), throwsUnsupportedError);
          return sent;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(reservations, 1);
      expect(sends, 0);
      committed.complete(true);
      final result = await pending;
      expect(sends, 1);
      expect(result.state, PrinterBeepState.submitted);
      expect(result.toMap(), {
        'state': 'submitted',
        'attemptId': 'attempt-original',
        'detail': sent.detail,
      });
    },
  );

  test('denied reservation produces notSent with no sender call', () async {
    final result = await OptionalPrinterBeep.submit(
      attemptId: 'attempt-original',
      profile: compatible(),
      reserve: (_) async => false,
      send: (_) async => throw StateError('must not send'),
    );
    expect(result.state, PrinterBeepState.notSent);
    expect(result.detail, contains('no replay'));
  });

  test(
    'invalid stable identity is refused before persistence or sender',
    () async {
      for (final attempt in ['', 'contains spaces', 'x' * 121, 'control\n']) {
        final result = await OptionalPrinterBeep.submit(
          attemptId: attempt,
          profile: compatible(),
          reserve: (_) async => throw StateError('must not reserve'),
          send: (_) async => throw StateError('must not send'),
        );
        expect(result.state, PrinterBeepState.failed);
        expect(result.detail, contains('invalid attempt ID'));
      }
    },
  );

  test('reservation failure is separate and cannot reach the sender', () async {
    final result = await OptionalPrinterBeep.submit(
      attemptId: 'attempt-original',
      profile: compatible(),
      reserve: (_) async => throw StateError('durable flush failed'),
      send: (_) async => throw StateError('must not send'),
    );
    expect(result.state, PrinterBeepState.failed);
    expect(result.detail, contains('durable flush failed'));
  });

  for (final state in PrintTransmissionState.values) {
    test('$state is an independent beep outcome and never replayed', () async {
      final spent = <String>{};
      var sends = 0;
      Future<PrinterBeepResult> submit() => OptionalPrinterBeep.submit(
        attemptId: 'attempt-original',
        profile: compatible(),
        reserve: (attempt) async => spent.add(attempt),
        send: (_) async {
          sends++;
          return PrintTransmissionResult(state, 'FAKE $state');
        },
      );
      final result = await submit();
      expect(result.state, switch (state) {
        PrintTransmissionState.sent => PrinterBeepState.submitted,
        PrintTransmissionState.notSent => PrinterBeepState.notSent,
        PrintTransmissionState.uncertain => PrinterBeepState.uncertain,
      });
      expect(result.detail, 'FAKE $state');
      expect(spent, {'attempt-original'});
      final relaunch = await submit();
      expect(relaunch.state, PrinterBeepState.notSent);
      expect(sends, 1);
    });
  }

  test(
    'throw after send retains reservation and allows only a new reprint identity',
    () async {
      final spent = <String>{};
      var sends = 0;
      Future<PrinterBeepResult> submit(String attempt) =>
          OptionalPrinterBeep.submit(
            attemptId: attempt,
            profile: compatible(),
            reserve: (id) async => spent.add(id),
            send: (_) async {
              sends++;
              if (sends == 1) throw StateError('failure after possible write');
              return sent;
            },
          );
      final result = await submit('attempt-original');
      expect(result.state, PrinterBeepState.uncertain);
      expect(result.detail, contains('failure after possible write'));
      expect(
        (await submit('attempt-original')).state,
        PrinterBeepState.notSent,
      );
      expect(sends, 1);
      final reprint = await submit('attempt-explicit-reprint');
      expect(reprint.state, PrinterBeepState.submitted);
      expect(reprint.attemptId, 'attempt-explicit-reprint');
      expect(sends, 2);
    },
  );

  test(
    'flush error after reservation remains spent across a new invocation',
    () async {
      final spent = <String>{};
      var sends = 0;
      Future<PrinterBeepResult> submit() => OptionalPrinterBeep.submit(
        attemptId: 'attempt-original',
        profile: compatible(),
        reserve: (id) async {
          if (!spent.add(id)) return false;
          throw StateError('reservation saved but flush response lost');
        },
        send: (_) async {
          sends++;
          return sent;
        },
      );
      expect((await submit()).state, PrinterBeepState.failed);
      expect((await submit()).state, PrinterBeepState.notSent);
      expect(sends, 0);
    },
  );

  test(
    'concurrent same-attempt calls send once under atomic reservation',
    () async {
      final spent = <String>{};
      final gate = Completer<void>();
      var sends = 0;
      Future<PrinterBeepResult> submit() => OptionalPrinterBeep.submit(
        attemptId: 'attempt-original',
        profile: compatible(),
        reserve: (id) async {
          if (!spent.add(id)) return false;
          await gate.future;
          return true;
        },
        send: (_) async {
          sends++;
          return sent;
        },
      );
      final first = submit(), second = submit();
      expect((await second).state, PrinterBeepState.notSent);
      expect(sends, 0);
      gate.complete();
      expect((await first).state, PrinterBeepState.submitted);
      expect(sends, 1);
    },
  );

  test(
    'reservation timeout never sends after a late durable completion',
    () async {
      final flushed = Completer<bool>();
      final spent = <String>{};
      var sends = 0;
      Future<PrinterBeepResult> submit() => OptionalPrinterBeep.submit(
        attemptId: 'attempt-original',
        profile: compatible(),
        operationTimeout: const Duration(milliseconds: 10),
        reserve: (id) async {
          if (!spent.add(id)) return false;
          return flushed.future;
        },
        send: (_) async {
          sends++;
          return sent;
        },
      );
      final timedOut = await submit();
      expect(timedOut.state, PrinterBeepState.failed);
      expect(timedOut.detail, contains('TimeoutException'));
      expect(sends, 0);
      flushed.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(sends, 0);
      expect((await submit()).state, PrinterBeepState.notSent);
      expect(sends, 0);
    },
  );

  test(
    'send timeout stays uncertain and does not recycle reservation',
    () async {
      final nativeCompletion = Completer<PrintTransmissionResult>();
      final spent = <String>{};
      var sends = 0;
      var nativeAdmissionHeld = false;
      Future<PrinterBeepResult> submit() => OptionalPrinterBeep.submit(
        attemptId: 'attempt-original',
        profile: compatible(),
        operationTimeout: const Duration(milliseconds: 10),
        reserve: (id) async => spent.add(id),
        send: (_) async {
          sends++;
          nativeAdmissionHeld = true;
          try {
            return await nativeCompletion.future;
          } finally {
            nativeAdmissionHeld = false;
          }
        },
      );
      final timedOut = await submit();
      expect(timedOut.state, PrinterBeepState.uncertain);
      expect(timedOut.detail, contains('TimeoutException'));
      expect(nativeAdmissionHeld, true);
      expect((await submit()).state, PrinterBeepState.notSent);
      expect(sends, 1);
      nativeCompletion.complete(sent);
      await Future<void>.delayed(Duration.zero);
      expect(nativeAdmissionHeld, false);
      expect(timedOut.state, PrinterBeepState.uncertain);
      expect(sends, 1);
    },
  );

  test('invalid timeout fails before durable reservation', () async {
    final result = await OptionalPrinterBeep.submit(
      attemptId: 'attempt-original',
      profile: compatible(),
      operationTimeout: Duration.zero,
      reserve: (_) async => throw StateError('must not reserve'),
      send: (_) async => throw StateError('must not send'),
    );
    expect(result.state, PrinterBeepState.failed);
    expect(result.detail, contains('invalid timeout'));
  });
}
