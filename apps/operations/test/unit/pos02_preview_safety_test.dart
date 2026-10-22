import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import 'package:vynic/core/services/printing/printer_transport.dart';
import '../support/pos02_preview_harness.dart';
import '../../tool/pos02_preview.dart';

class _RecordedSocket implements PrinterWriteSocket {
  final writes = <List<int>>[];
  bool destroyed = false;
  bool failAdd = false;
  @override
  void add(List<int> bytes) {
    writes.add(List.of(bytes));
    if (failAdd) throw const SocketException('synthetic partial write');
  }

  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  void destroy() {
    destroyed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final binding =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  Pos02PreviewSession? session;
  setUp(() {
    binding.setMockMethodCallHandler(
      pathProvider,
      (call) async => throw StateError(
        'Preview must never resolve ordinary application data',
      ),
    );
  });
  tearDown(() async {
    await session?.close(removeData: true);
    session = null;
    binding.setMockMethodCallHandler(pathProvider, null);
  });
  Future<Pos02PreviewSession> open() async =>
      session = await Pos02PreviewSession.open(
        renderOverride: (_) async => ascii.encode('SYNTHETIC SAMPLE\n'),
      );

  test(
    'fresh managed storage never resolves normal paths or starts printing',
    () async {
      final a = await open();
      expect(DatabaseService.getDataDirectoryPath(), a.directory.path);
      expect(a.directory.path, contains('vynic_pos02_preview_'));
      expect(PrintJobRepository.all(), isEmpty);
      expect(a.transport.simulatedWrites, isEmpty);
      expect(a.transport.physicalConnections, 0);
      expect(
        PrintReconciliation.policy,
        PrintReconciliationPolicy.unconfigured,
      );
      expect(PrintReconciliation.allowed, false);
      expect(DatabaseCore.orderBox!.isEmpty, true);
      expect(DatabaseCore.salesBox!.isEmpty, true);
      expect(() => HttpClient(), throwsStateError);
    },
  );

  test(
    'relaunch creates another root and never resumes previous synthetic jobs',
    () async {
      final first = await open();
      await first.sendSample(PrintQueueTarget.kitchen);
      final firstPath = first.directory.path;
      await first.close(removeData: true);
      session = null;
      final second = await open();
      expect(second.directory.path, isNot(firstPath));
      expect(PrintJobRepository.all(), isEmpty);
      expect(second.transport.simulatedWrites, isEmpty);
      expect(second.transport.physicalConnections, 0);
    },
  );

  test('cannot attach to a database already open in this process', () async {
    await open();
    await expectLater(Pos02PreviewSession.open(), throwsStateError);
  });

  test(
    'default sample renderers produce marked kitchen and receipt rasters locally',
    () async {
      final a = session = await Pos02PreviewSession.open();
      for (final target in [
        PrintQueueTarget.kitchen,
        PrintQueueTarget.receipt,
      ]) {
        final job = await a.sendSample(target);
        expect(job.state, PrintJobState.sent);
        expect(job.transmissionBytes.length, greaterThan(1000));
        expect(
          latin1.decode(job.transmissionBytes),
          contains('TEST / DO NOT PREPARE'),
        );
      }
      expect(a.transport.simulatedWrites, hasLength(2));
      expect(a.transport.physicalConnections, 0);
    },
  );

  test(
    'unconfigured production stations are refused before preview rendering or admission',
    () async {
      var renders = 0;
      final a = session = await Pos02PreviewSession.open(
        renderOverride: (_) async {
          renders++;
          return ascii.encode('SYNTHETIC SAMPLE\n');
        },
      );
      for (final target in [
        PrintQueueTarget.bar,
        PrintQueueTarget.additional,
      ]) {
        await expectLater(a.sendSample(target), throwsArgumentError);
        await expectLater(
          a.sendSample(target, physical: true),
          throwsArgumentError,
        );
      }
      expect(renders, 0);
      expect(PrintJobRepository.all(), isEmpty);
      expect(a.transport.simulatedWrites, isEmpty);
      expect(a.transport.physicalConnections, 0);
    },
  );

  test('storage-only startup schedules no normal audit sync timers', () async {
    final syncTimers = <Duration>[];
    await runZoned(
      open,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration == const Duration(seconds: 10)) syncTimers.add(duration);
          return parent.createTimer(zone, duration, callback);
        },
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          if (duration == const Duration(minutes: 2)) syncTimers.add(duration);
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      ),
    );
    expect(syncTimers, isEmpty);
  });

  test(
    'slow rendering expires approval before admission or physical connection',
    () async {
      var now = DateTime(2026, 10, 2);
      final render = Completer<List<int>>();
      final guard = PreviewTransport(
        physicalHost: '10.10.10.5',
        clock: () => now,
        physicalConnector: (_, _) async => _RecordedSocket(),
      );
      final a = session = await Pos02PreviewSession.open(
        transport: guard,
        renderOverride: (_) => render.future,
      );
      final submitted = a.sendSample(
        PrintQueueTarget.kitchen,
        physical: true,
        currentWindowApproved: true,
        approvedAt: now,
      );
      now = now.add(const Duration(seconds: 61));
      render.complete(ascii.encode('SYNTHETIC SAMPLE\n'));
      await expectLater(submitted, throwsStateError);
      expect(PrintJobRepository.all(), isEmpty);
      expect(guard.physicalConnections, 0);
    },
  );

  test(
    'explicit fake sample uses durable production worker and labeled bytes',
    () async {
      final a = await open();
      final job = await a.sendSample(PrintQueueTarget.receipt);
      expect(job.state, PrintJobState.sent);
      expect(job.host, PreviewTransport.fakeHost);
      expect(job.target, PrintQueueTarget.receipt);
      expect(a.transport.simulatedWrites, hasLength(1));
      final text = latin1.decode(a.transport.simulatedWrites.single);
      expect(text, contains('JOB ${job.id}\n'));
      expect(text, contains('TEST / DO NOT PREPARE'));
      expect(a.transport.physicalConnections, 0);
    },
  );

  test(
    'fake partial write remains uncertain without automatic retry',
    () async {
      final a = await open();
      a.transport.outcome = PreviewOutcome.partialWrite;
      final job = await a.sendSample(PrintQueueTarget.kitchen);
      expect(job.state, PrintJobState.uncertain);
      expect(a.transport.simulatedWrites, hasLength(1));
      expect(a.transport.physicalConnections, 0);
    },
  );

  test('fake connection failure writes zero bytes', () async {
    final a = await open();
    a.transport.outcome = PreviewOutcome.connectionFailure;
    final job = await a.sendSample(PrintQueueTarget.kitchen);
    expect(job.state, PrintJobState.failed);
    expect(a.transport.simulatedWrites, isEmpty);
    expect(a.transport.physicalConnections, 0);
  });

  test('missing physical opt-in never falls back to network', () async {
    final a = await open();
    await expectLater(
      a.sendSample(
        PrintQueueTarget.kitchen,
        physical: true,
        currentWindowApproved: true,
      ),
      throwsStateError,
    );
    expect(PrintJobRepository.all(), isEmpty);
    expect(a.transport.physicalConnections, 0);
  });

  test(
    'configured endpoint starts disarmed and rejects other endpoints',
    () async {
      var calls = 0;
      final guard = PreviewTransport(
        physicalHost: '10.10.10.5',
        physicalConnector: (_, _) async {
          calls++;
          return _RecordedSocket();
        },
      );
      await expectLater(guard.connect('10.10.10.5', 9100), throwsStateError);
      expect(
        () => guard.armOneLabeledJob(
          'pos02-preview-job',
          currentWindowApproved: false,
        ),
        throwsStateError,
      );
      guard.armOneLabeledJob('pos02-preview-job', currentWindowApproved: true);
      await expectLater(guard.connect('10.10.10.6', 9100), throwsStateError);
      await expectLater(guard.connect('10.10.10.5', 9101), throwsStateError);
      expect(calls, 0);
    },
  );

  test(
    'one explicitly approved labeled job consumes its permit before add',
    () async {
      final raw = _RecordedSocket()..failAdd = true;
      final guard = PreviewTransport(
        physicalHost: '10.10.10.5',
        physicalConnector: (_, _) async => raw,
      );
      guard.armOneLabeledJob('pos02-preview-job', currentWindowApproved: true);
      final socket = await guard.connect('10.10.10.5', 9100);
      expect(
        () => socket.add(
          ascii.encode('JOB pos02-preview-job\nTEST / DO NOT PREPARE\n'),
        ),
        throwsA(isA<SocketException>()),
      );
      await expectLater(guard.connect('10.10.10.5', 9100), throwsStateError);
      expect(raw.writes, hasLength(1));
    },
  );

  test(
    'incorrect job identity or missing TEST marking writes no bytes',
    () async {
      final raw = _RecordedSocket();
      final guard = PreviewTransport(
        physicalHost: '10.10.10.5',
        physicalConnector: (_, _) async => raw,
      );
      guard.armOneLabeledJob('pos02-preview-job', currentWindowApproved: true);
      final socket = await guard.connect('10.10.10.5', 9100);
      expect(
        () =>
            socket.add(ascii.encode('JOB different\nTEST / DO NOT PREPARE\n')),
        throwsStateError,
      );
      expect(
        () =>
            socket.add(ascii.encode('JOB pos02-preview-job\nordinary order\n')),
        throwsStateError,
      );
      expect(raw.writes, isEmpty);
    },
  );

  test(
    'expired authorization never connects and expiry during connect closes socket',
    () async {
      var now = DateTime(2026, 10, 2);
      final raw = _RecordedSocket();
      var calls = 0;
      final guard = PreviewTransport(
        physicalHost: '10.10.10.5',
        clock: () => now,
        physicalConnector: (_, _) async {
          calls++;
          now = now.add(const Duration(seconds: 61));
          return raw;
        },
      );
      guard.armOneLabeledJob('pos02-preview-job', currentWindowApproved: true);
      await expectLater(guard.connect('10.10.10.5', 9100), throwsStateError);
      expect(raw.destroyed, true);
      expect(raw.writes, isEmpty);
      await expectLater(guard.connect('10.10.10.5', 9100), throwsStateError);
      expect(calls, 1);
    },
  );

  test(
    'public DNS, loopback and invalid addresses cannot become opt-in endpoints',
    () {
      for (final host in [
        'printer.example',
        '8.8.8.8',
        '127.0.0.1',
        '10.10.10.256',
        '10.10.010.5',
      ]) {
        expect(() => PreviewTransport(physicalHost: host), throwsArgumentError);
      }
    },
  );

  testWidgets(
    'preview opens with physical action disabled and performs only explicit simulation',
    (tester) async {
      final a = (await tester.runAsync(open))!;
      await tester.pumpWidget(Pos02PreviewApp(session: a));
      await tester.pumpAndSettle();
      final physical = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('preview-physical')),
      );
      expect(physical.onPressed, isNull);
      expect(PrintJobRepository.all(), isEmpty);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('preview-simulate')));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (PrintJobRepository.all().isEmpty ||
            PrintJobRepository.all().last.ready ||
            PrintJobRepository.all().last.state == PrintJobState.sending) {
          if (DateTime.now().isAfter(deadline))
            throw StateError('Synthetic preview did not settle');
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(PrintJobRepository.all(), hasLength(1));
      expect(a.transport.physicalConnections, 0);
      expect(a.transport.simulatedWrites, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'physical opt-in cancel and repeated approval cannot add unintended jobs',
    (tester) async {
      final raw = _RecordedSocket();
      var renderCalls = 0;
      final a = (await tester.runAsync(
        () async => session = await Pos02PreviewSession.open(
          transport: PreviewTransport(
            physicalHost: '10.10.10.5',
            physicalConnector: (_, _) async => raw,
          ),
          renderOverride: (_) async {
            renderCalls++;
            throw StateError('Synthetic render refusal');
          },
        ),
      ))!;
      await tester.pumpWidget(Pos02PreviewApp(session: a));
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('preview-physical'));
      final openDialog = tester.widget<OutlinedButton>(action).onPressed!;
      openDialog();
      openDialog();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(a.transport.physicalConnections, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(PrintJobRepository.all(), isEmpty);
      await tester.tap(action);
      await tester.pumpAndSettle();
      final approve = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approved now — one TEST page'),
          )
          .onPressed!;
      approve();
      approve();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(renderCalls, 1);
      expect(PrintJobRepository.all(), isEmpty);
      expect(raw.writes, isEmpty);
      expect(a.transport.physicalConnections, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
