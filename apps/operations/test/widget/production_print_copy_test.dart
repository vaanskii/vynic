import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/print_jobs.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/print_job_repository.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/auth/pos_session.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/services/printing/local_printer_catalog.dart';
import 'package:vynic/core/services/printing/print_job.dart';
import 'package:vynic/core/services/printing/print_queue.dart';
import 'package:vynic/core/services/printing/print_reconciliation.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';
import 'package:vynic/core/services/printing/windows_spooler_transport.dart';
import 'package:vynic/core/ui/widgets/vynic_responsive_dialog.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import '../support/pos02_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('synthetic/production-print-copy');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late Pos02Fixture fixture;
  late List<MethodCall> calls;

  Widget surface() => const PosLocale(
    language: 'en',
    child: MaterialApp(home: Scaffold(body: PrintJobsDialog())),
  );

  PrinterRoute route(PrintQueueTarget target, {int revision = 1}) =>
      PrinterRoute.decode({
        'protocol': 1,
        'id': 'synthetic-${target.name}-route',
        'name': 'Synthetic ${target.name} station',
        'role': target.name,
        'revision': revision,
        'destination': PrinterDestination.windowsSpooler(
          ownerDeviceId: EdgeDeviceCredentialStore.deviceId!,
          queueName: 'Synthetic ${target.name} queue $revision',
          driverName: 'Synthetic ESC/POS driver $revision',
          portName: 'USB-SYNTHETIC-$revision',
        ).toMap(),
        'capabilityProfile': PrinterCapabilityProfile.genericEscposRaster(
          paperWidthMm: revision == 1 ? 58 : 80,
          rasterWidthDots: revision == 1 ? 384 : 576,
          cutter: revision == 1 ? PrinterCutter.partial : PrinterCutter.full,
        ).toMap(),
      });

  Future<PrintJob> prepare(WidgetTester tester, PrintQueueTarget target) async {
    await tester.runAsync(() async {
      final initial = route(target);
      await DatabaseCore.settingsBox!.put(
        LocalPrinterCatalog.routesSettingKey,
        [initial.toMap()],
      );
      await PrintQueue.enqueue(
        PrintJob.create(
          id: 'synthetic-${target.name}-job',
          target: target,
          destination: initial.destination,
          printerId: initial.id,
          routeRevision: initial.revision,
          capabilityProfile: initial.capabilityProfile,
          label: '${target.name} / Synthetic production ticket',
          bytes: [
            ...ascii.encode('SYNTHETIC ${target.name} TICKET\n'),
            0x1d,
            0x56,
            0x01,
          ],
          venueId: EdgeDeviceCredentialStore.venueId,
        ),
      );
      await fixture.dispatch();
      PrintQueue.stop();
    });
    final job = PrintJobRepository.read('synthetic-${target.name}-job')!;
    expect(job.protocolVersion, PrintJob.routedProtocol);
    expect(job.state, PrintJobState.sent);
    expect(calls, hasLength(1));
    return job;
  }

  Future<void> openCopy(WidgetTester tester, PrintJob job) async {
    await tester.pumpWidget(surface());
    await tester.tap(find.byKey(ValueKey('print-reprint-${job.id}')));
    await tester.pumpAndSettle();
    expect(find.text('გაშვება'), findsOneWidget);
    expect(find.text('გაუქმება'), findsOneWidget);
    expect(find.byType(PosOnScreenTextField), findsNothing);
    expect(find.widgetWithText(FilledButton, 'გაშვება'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'გაუქმება'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(VynicResponsiveDialog),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      ),
      findsNWidgets(2),
    );
  }

  Future<void> advance(WidgetTester tester) async {
    for (var n = 0; n < 8; n++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File('assets/fonts/NotoSansGeorgian.ttf').readAsBytesSync();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.view(font.buffer)))).load();
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_production_copy_');
    fixture = Pos02Fixture();
    await fixture.open(root.path);
    await fixture.seed();
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      expect(call.method, 'submitRaw');
      return {
        'accepted': true,
        'jobId': calls.length,
        'bytesWritten': (call.arguments as Map)['bytes'].length,
      };
    });
    PrintQueue.spoolerOverride = WindowsSpoolerTransport(
      channel: channel,
      isWindows: () => true,
    );
    PrintReconciliation.policy = PrintReconciliationPolicy.unconfigured;
  });
  tearDown(() async {
    await fixture.close();
    PrintQueue.spoolerOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  for (final target in [PrintQueueTarget.bar, PrintQueueTarget.additional]) {
    testWidgets(
      '${target.name} Cancel preserves the job and exact journal bytes',
      (tester) async {
        final job = await prepare(tester, target);
        final before = job.toMap();
        final journal = File(DatabaseCore.metaBox!.path!);
        await tester.runAsync(() => DatabaseCore.metaBox!.flush());
        final disk = journal.readAsBytesSync();
        await openCopy(tester, job);
        await tester.tap(find.text('გაუქმება'));
        await tester.pumpAndSettle();
        expect(PrintJobRepository.read(job.id)!.toMap(), before);
        expect(journal.readAsBytesSync(), disk);
        expect(calls, hasLength(1));
        expect(fixture.transmitted, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${target.name} Run double submit records fresh staff and one frozen labeled copy',
      (tester) async {
        final original = await prepare(tester, target);
        final before = original.toMap();
        await openCopy(tester, original);
        final waiter = User(
          username: 'synthetic-fresh-printing-staff',
          pinCode: '2345',
          role: 'waiter',
        );
        await tester.runAsync(() async {
          await DatabaseCore.userBox!.put(waiter.username, waiter);
          PosSession.switchTo(waiter);
          await DatabaseCore.settingsBox!.put(
            LocalPrinterCatalog.routesSettingKey,
            [route(target, revision: 2).toMap()],
          );
        });
        final submit = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('print-action-submit')),
            )
            .onPressed!;
        await tester.runAsync(() async {
          submit();
          submit();
        });
        await advance(tester);
        await tester.pumpAndSettle();
        final queued = PrintJobRepository.read(original.id)!;
        expect(queued.state, PrintJobState.reprint);
        expect(queued.attempts, hasLength(2));
        final copied = queued.audit
            .where((event) => event['action'] == 'reprint')
            .single;
        expect(copied['actorId'], waiter.username);
        expect(
          copied['reason'],
          PrintReconciliation.productionCopyReason(target),
        );
        expect(copied['attemptId'], queued.attemptId);
        expect(queued.attemptId, isNot(original.attemptId));
        expect(queued.destination.toMap(), before['destination']);
        expect(queued.capabilityProfile.toMap(), before['capabilityProfile']);
        expect(queued.routeRevision, 1);
        expect(queued.toMap()['payloadSha256'], before['payloadSha256']);
        expect(queued.toMap()['payload'], before['payload']);
        expect(calls, hasLength(1));

        await tester.runAsync(() async {
          await fixture.dispatch();
          PrintQueue.stop();
        });
        await tester.pumpAndSettle();
        final sent = PrintJobRepository.read(original.id)!;
        expect(sent.state, PrintJobState.sent);
        expect(sent.attempts, hasLength(2));
        expect(
          sent.audit.where((event) => event['action'] == 'reprint'),
          hasLength(1),
        );
        expect(calls, hasLength(2));
        final arguments = calls.last.arguments as Map;
        expect(arguments['queueName'], original.destination.queueName);
        expect(
          arguments['expectedDriverName'],
          original.destination.driverName,
        );
        expect(arguments['expectedPortName'], original.destination.portName);
        expect(arguments['bytes'], sent.transmissionBytes);
        expect(
          latin1.decode(List<int>.from(arguments['bytes'])),
          contains('COPY\n'),
        );
        expect(sent.destination.toMap(), before['destination']);
        expect(sent.capabilityProfile.toMap(), before['capabilityProfile']);
        expect(sent.capabilityProfile.paperWidthMm, 58);
        expect(sent.capabilityProfile.rasterWidthDots, 384);
        expect(sent.capabilityProfile.cutter, PrinterCutter.partial);
        expect(fixture.transmitted, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${target.name} Run rechecks a removed staff record at submission',
      (tester) async {
        final job = await prepare(tester, target);
        final waiter = User(
          username: 'synthetic-removed-printing-staff',
          pinCode: '3456',
          role: 'waiter',
        );
        await tester.runAsync(() async {
          await DatabaseCore.userBox!.put(waiter.username, waiter);
          PosSession.switchTo(waiter);
        });
        await openCopy(tester, job);
        await tester.runAsync(
          () => DatabaseCore.userBox!.delete(waiter.username),
        );
        await tester.runAsync(() async {
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('print-action-submit')),
              )
              .onPressed!();
        });
        await advance(tester);
        expect(
          find.text('Action failed — refresh the print jobs list.'),
          findsOneWidget,
        );
        expect(PrintJobRepository.read(job.id)!.toMap(), job.toMap());
        expect(calls, hasLength(1));
        await tester.tap(find.text('გაუქმება'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unconfigured receipt policy leaves routed copies and paper checks disabled',
    (tester) async {
      final job = await prepare(tester, PrintQueueTarget.receipt);
      await tester.pumpWidget(surface());
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(ValueKey('print-reprint-${job.id}')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(ValueKey('print-confirm-${job.id}')))
            .onPressed,
        isNull,
      );
      expect(
        find.text('Operator reconciliation policy is not configured.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('print-action-submit')), findsNothing);
      expect(PrintJobRepository.read(job.id)!.toMap(), job.toMap());
      expect(calls, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
