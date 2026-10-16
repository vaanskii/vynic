import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/printers/admin_printers_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/printers/printer_agent_status_card.dart';
import 'package:vynic/core/services/printing/printer_agent_profile.dart';
import 'package:vynic/core/services/printing/printer_agent_runtime_profile.dart';
import 'package:vynic/core/services/security/developer_access.dart';

import '../support/pos02_developer_fixture.dart';
import '../support/pos02_fixture.dart';
import '../support/printer_agent_status_fixture.dart';

String _fixturePath(Directory directory, String child) =>
    File.fromUri(directory.uri.resolve(child)).path;

/// Observes calls without replacing the profile loader or TLS client.
class _ActualHealthObservation implements PrinterAgentRuntimeHealthSource {
  _ActualHealthObservation(this.runtime);
  final PrinterAgentRuntimeProfile runtime;
  int calls = 0;
  late Future<PrinterAgentHealth> lastCall;
  @override
  bool get isConfigured => runtime.isConfigured;
  @override
  PrinterAgentRuntimeBinding get currentBinding => runtime.currentBinding;
  @override
  Future<PrinterAgentHealth> health() {
    calls++;
    return lastCall = runtime.health();
  }
}

void main() {
  late Directory root;
  late Pos02Fixture fixture;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_agent_status_widget_');
    fixture = Pos02Fixture();
    await fixture.open(root.path);
    await fixture.seed();
    await unlockSyntheticPrinterDeveloper();
  });
  tearDown(() async {
    DeveloperAccess.resetForTest();
    DeveloperAccess.publicKeyOverride = null;
    await fixture.close();
    await root.delete(recursive: true);
  });

  Widget surface(PrinterAgentRuntimeHealthSource source) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PrinterAgentStatusCard(source: source),
      ),
    ),
  );
  Future<void> refresh(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('printer-agent-refresh')));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('default factory stays neutral and never probes or prints', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PrinterAgentStatusCard())),
    );
    expect(
      find.text('ახალი აგენტის პროფილი ჯერ არ არის მითითებული.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('printer-agent-refresh')), findsNothing);
    expect(
      find.textContaining('მიმდინარე პრინტერების მუშაობა უცვლელია'),
      findsOneWidget,
    );
    expect(fixture.connections, 0);
  });

  testWidgets(
    'configured card requires manual refresh and keeps physical held',
    (tester) async {
      final source = FakeAgentHealthSource(result: () async => agentHealth());
      await tester.pumpWidget(surface(source));
      await tester.pump(const Duration(seconds: 2));
      expect(source.healthCalls, 0);
      expect(find.text('სტატუსი ჯერ არ შემოწმებულა.'), findsOneWidget);
      await refresh(tester);
      expect(source.healthCalls, 1);
      expect(find.text('აგენტი ხელმისაწვდომია'), findsOneWidget);
      expect(find.text('ადგილობრივი რიგი'), findsOneWidget);
      expect(find.text('ფიზიკური ბეჭდვა შეჩერებულია'), findsOneWidget);
      expect(
        find.textContaining('ახალი რიგიდან ბეჭდვა არ გააქტიურებულა'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 30));
      expect(source.healthCalls, 1);
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared queue uncertainty is visible without raw hold text or resend',
    (tester) async {
      final source = FakeAgentHealthSource(
        result: () async => agentHealth(
          pins: agentPins(scope: PrinterAgentScope.venueShared),
          queueHeld: true,
          holdReason: 'NEVER_RENDER_SECRET_OR_CREDENTIAL_PATH',
        ),
      );
      await tester.pumpWidget(surface(source));
      await refresh(tester);
      expect(find.text('რესტორნის საერთო რიგი'), findsOneWidget);
      expect(find.textContaining('1 პრინტერი'), findsOneWidget);
      expect(
        find.textContaining('ავტომატურად არ გადაიგზავნება'),
        findsOneWidget,
      );
      expect(find.textContaining('NEVER_RENDER'), findsNothing);
      expect(fixture.connections, 0);
    },
  );

  for (final state in PrinterAgentLifecycle.values) {
    testWidgets('lifecycle ${state.name} remains physically held', (
      tester,
    ) async {
      final source = FakeAgentHealthSource(
        result: () async => agentHealth(
          state: state,
          ready: state == PrinterAgentLifecycle.running,
        ),
      );
      await tester.pumpWidget(surface(source));
      await refresh(tester);
      expect(find.text('ფიზიკური ბეჭდვა შეჩერებულია'), findsOneWidget);
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final failure in PrinterAgentFailure.values) {
    testWidgets('typed ${failure.name} stays visible until manual retry', (
      tester,
    ) async {
      final source = FakeAgentHealthSource(
        result: () async => throw PrinterAgentException(failure),
      );
      await tester.pumpWidget(surface(source));
      await refresh(tester);
      expect(source.healthCalls, 1);
      expect(find.text('აგენტი ხელმისაწვდომია'), findsNothing);
      expect(
        find.byKey(const ValueKey('printer-agent-refresh')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(source.healthCalls, 1);
      await refresh(tester);
      expect(source.healthCalls, 2);
      expect(fixture.connections, 0);
    });
  }

  testWidgets(
    'unknown exception is a typed visible failure without secret text',
    (tester) async {
      final source = FakeAgentHealthSource(
        result: () async => throw StateError('SECRET_KEY_MATERIAL'),
      );
      await tester.pumpWidget(surface(source));
      await refresh(tester);
      expect(find.textContaining('აგენტი ვერ უკავშირდება'), findsOneWidget);
      expect(find.textContaining('SECRET_KEY_MATERIAL'), findsNothing);
      expect(fixture.connections, 0);
    },
  );

  testWidgets('missing installation refuses health before any call', (
    tester,
  ) async {
    final source = FakeAgentHealthSource(
      binding: const PrinterAgentRuntimeBinding(
        deviceId: agentDevice,
        venueId: agentVenue,
        deviceInstallationId: null,
        loaded: true,
        enrolled: true,
      ),
      result: () async => agentHealth(),
    );
    await tester.pumpWidget(surface(source));
    await refresh(tester);
    expect(source.healthCalls, 0);
    expect(find.textContaining('ინსტალაციის იდენტობა აკლია'), findsOneWidget);
  });

  for (final field in ['device', 'venue']) {
    testWidgets('foreign $field response never becomes available', (
      tester,
    ) async {
      final source = FakeAgentHealthSource(
        result: () async => agentHealth(
          pins: agentPins(
            device: field == 'device' ? agentOther : agentDevice,
            venue: field == 'venue' ? agentOther : agentVenue,
            installation: field == 'installation'
                ? agentOther
                : agentInstallation,
          ),
        ),
      );
      await tester.pumpWidget(surface(source));
      await refresh(tester);
      expect(find.text('აგენტი ხელმისაწვდომია'), findsNothing);
      expect(find.textContaining('არ ემთხვევა'), findsOneWidget);
      expect(fixture.connections, 0);
    });
  }

  testWidgets('identity change during await rejects old response', (
    tester,
  ) async {
    final response = Completer<PrinterAgentHealth>();
    final source = FakeAgentHealthSource(result: () => response.future);
    await tester.pumpWidget(surface(source));
    await tester.tap(find.byKey(const ValueKey('printer-agent-refresh')));
    await tester.pump();
    source.binding = const PrinterAgentRuntimeBinding(
      deviceId: agentOther,
      venueId: agentVenue,
      deviceInstallationId: agentDeviceInstallation,
      loaded: true,
      enrolled: true,
    );
    response.complete(agentHealth());
    await tester.pumpAndSettle();
    expect(find.text('აგენტი ხელმისაწვდომია'), findsNothing);
    expect(find.textContaining('არ ემთხვევა'), findsOneWidget);
    expect(fixture.connections, 0);
  });

  testWidgets(
    'cached response is historical and disappears on later binding change',
    (tester) async {
      final source = FakeAgentHealthSource(result: () async => agentHealth());
      await tester.pumpWidget(surface(source));
      await refresh(tester);
      expect(
        find.byKey(const ValueKey('printer-agent-checked-at')),
        findsOneWidget,
      );
      source.binding = const PrinterAgentRuntimeBinding(
        deviceId: agentOther,
        venueId: agentVenue,
        deviceInstallationId: agentDeviceInstallation,
        loaded: true,
        enrolled: true,
      );
      await tester.pumpWidget(surface(source));
      expect(find.text('აგენტი ხელმისაწვდომია'), findsNothing);
      expect(find.textContaining('არ ემთხვევა'), findsOneWidget);
      expect(source.healthCalls, 1);
    },
  );

  testWidgets('restoration hold suppresses cached health without a new probe', (
    tester,
  ) async {
    final source = FakeAgentHealthSource(result: () async => agentHealth());
    await tester.pumpWidget(surface(source));
    await refresh(tester);
    source.binding = const PrinterAgentRuntimeBinding(
      deviceId: agentDevice,
      venueId: agentVenue,
      deviceInstallationId: agentDeviceInstallation,
      loaded: true,
      enrolled: true,
      restorationHeld: true,
    );
    await tester.pumpWidget(surface(source));
    expect(find.text('აგენტი ხელმისაწვდომია'), findsNothing);
    expect(find.textContaining('აღდგენილი მონაცემების მიბმა'), findsOneWidget);
    expect(source.healthCalls, 1);
  });

  testWidgets(
    'changed POS installation suppresses cached distinct Go installation',
    (tester) async {
      final source = FakeAgentHealthSource(result: () async => agentHealth());
      expect(agentDeviceInstallation, isNot(agentInstallation));
      await tester.pumpWidget(surface(source));
      await refresh(tester);
      expect(find.text('აგენტი ხელმისაწვდომია'), findsOneWidget);
      source.binding = const PrinterAgentRuntimeBinding(
        deviceId: agentDevice,
        venueId: agentVenue,
        deviceInstallationId: agentOther,
        loaded: true,
        enrolled: true,
      );
      await tester.pumpWidget(surface(source));
      expect(find.text('აგენტი ხელმისაწვდომია'), findsNothing);
      expect(find.textContaining('არ ემთხვევა'), findsOneWidget);
      expect(source.healthCalls, 1);
    },
  );

  testWidgets(
    'replacement profile invalidates pending result without probing new profile',
    (tester) async {
      final response = Completer<PrinterAgentHealth>();
      final old = FakeAgentHealthSource(result: () => response.future);
      final next = FakeAgentHealthSource(
        result: () async => agentHealth(pins: agentPins(configRevision: 2)),
      );
      await tester.pumpWidget(surface(old));
      await tester.tap(find.byKey(const ValueKey('printer-agent-refresh')));
      await tester.pump();
      await tester.pumpWidget(surface(next));
      response.complete(agentHealth());
      await tester.pumpAndSettle();
      expect(find.text('სტატუსი ჯერ არ შემოწმებულა.'), findsOneWidget);
      expect(next.healthCalls, 0);
      await refresh(tester);
      expect(next.healthCalls, 1);
      expect(find.text('აგენტი ხელმისაწვდომია'), findsOneWidget);
    },
  );

  testWidgets('repeated refresh while pending creates one request', (
    tester,
  ) async {
    final response = Completer<PrinterAgentHealth>();
    final source = FakeAgentHealthSource(result: () => response.future);
    await tester.pumpWidget(surface(source));
    final call = tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('printer-agent-refresh')),
        )
        .onPressed!;
    call();
    call();
    await tester.pump();
    expect(source.healthCalls, 1);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('printer-agent-refresh')),
          )
          .onPressed,
      isNull,
    );
    response.complete(agentHealth());
    await tester.pumpAndSettle();
  });

  testWidgets('diagnostics-only token cannot see or call health', (
    tester,
  ) async {
    await tester.runAsync(
      () =>
          unlockSyntheticPrinterDeveloper(scopes: [DeveloperScope.diagnostics]),
    );
    final source = FakeAgentHealthSource(result: () async => agentHealth());
    await tester.pumpWidget(surface(source));
    expect(
      find.byKey(const ValueKey('printer-agent-status-card')),
      findsNothing,
    );
    expect(source.healthCalls, 0);
  });

  testWidgets(
    'revoked token refuses captured button and invalidates pending result',
    (tester) async {
      final response = Completer<PrinterAgentHealth>();
      final source = FakeAgentHealthSource(result: () => response.future);
      await tester.pumpWidget(surface(source));
      final button = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('printer-agent-refresh')),
          )
          .onPressed!;
      button();
      await tester.pump();
      DeveloperAccess.lock();
      button();
      response.complete(agentHealth());
      await tester.pumpAndSettle();
      expect(source.healthCalls, 1);
      expect(
        find.byKey(const ValueKey('printer-agent-status-card')),
        findsNothing,
      );
      await tester.runAsync(() => unlockSyntheticPrinterDeveloper());
      await tester.pumpAndSettle();
      expect(find.text('სტატუსი ჯერ არ შემოწმებულა.'), findsOneWidget);
      expect(fixture.connections, 0);
    },
  );

  for (final width in [320.0, 640.0, 1024.0, 1280.0]) {
    testWidgets('held status fits width $width at enlarged text scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = FakeAgentHealthSource(
        result: () async => agentHealth(queueHeld: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 768),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: PrinterAgentStatusCard(source: source),
              ),
            ),
          ),
        ),
      );
      await refresh(tester);
      expect(tester.takeException(), isNull);
      expect(fixture.connections, 0);
    });
  }

  testWidgets(
    'shared developer printer pane attaches actual neutral factory without existing actions',
    (tester) async {
      final kitchen = TextEditingController(),
          receipt = TextEditingController(),
          port = TextEditingController(text: '9100');
      addTearDown(kitchen.dispose);
      addTearDown(receipt.dispose);
      addTearDown(port.dispose);
      var writes = 0, tests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminPrintersSection(
              kitchenPrinterController: kitchen,
              receiptPrinterController: receipt,
              printerPortController: port,
              isSavingPrinterSettings: false,
              isTestingPrinters: false,
              onSavePrinterSettings: () async {
                writes++;
              },
              onTestPrinterConnections: () async {
                tests++;
              },
            ),
          ),
        ),
      );
      expect(find.byType(PrinterAgentStatusCard), findsOneWidget);
      expect(find.text('სამზარეულო'), findsOneWidget);
      expect(find.text('ჩეკი'), findsOneWidget);
      expect(writes, 0);
      expect(tests, 0);
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  final goFixture = Platform.environment['VYNIC_PRINTER_AGENT_GO_FIXTURE'];
  testWidgets(
    'manual card uses real profile and mTLS health then shows actual offline failure',
    (tester) async {
      late Directory agentRoot;
      late Process child;
      late Future<String> output;
      late Future<String> errors;
      late _ActualHealthObservation observed;
      var started = false;
      var stopped = false;
      Future<void> stopChild() async {
        if (!started || stopped) return;
        stopped = true;
        await File(
          _fixturePath(agentRoot, 'stop'),
        ).writeAsString('synthetic UI proof');
        final exit = await child.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            child.kill();
            throw StateError('Owned synthetic health fixture failed to stop');
          },
        );
        expect(exit, 0, reason: await errors);
        expect(await output, contains('PASS'));
      }

      try {
        await tester.runAsync(() async {
          agentRoot = await Directory(_fixturePath(root, 'agent')).create();
          child = await Process.start(
            goFixture!,
            ['-test.run=^TestPrinterAgentProcess\$', '-test.v'],
            environment: {'VYNIC_PRINTER_AGENT_FIXTURE_DIR': agentRoot.path},
          );
          started = true;
          output = child.stdout.transform(utf8.decoder).join();
          errors = child.stderr.transform(utf8.decoder).join();
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (!await File(_fixturePath(agentRoot, 'ready')).exists()) {
            if (DateTime.now().isAfter(deadline)) {
              child.kill();
              throw StateError('Owned synthetic health fixture was not ready');
            }
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          final raw =
              jsonDecode(
                    await File(
                      _fixturePath(agentRoot, 'profile.json'),
                    ).readAsString(),
                  )
                  as Map<String, dynamic>;
          final pins = PrinterAgentPins.fromJson(
            raw['pins'] as Map<String, dynamic>,
          );
          expect(
            raw['currentDeviceInstallationId'],
            isNot(pins.installationId),
          );
          // Synthetic enrollment getter only; the real readonly loader and
          // actual pinned mTLS client remain intact. This grants no admission.
          final binding = PrinterAgentRuntimeBinding(
            deviceId: pins.deviceId,
            venueId: pins.venueId,
            deviceInstallationId: raw['currentDeviceInstallationId'] as String,
            loaded: true,
            enrolled: true,
          );
          observed = _ActualHealthObservation(
            PrinterAgentRuntimeProfile(
              profilePath: _fixturePath(agentRoot, 'profile.json'),
              bindingReader: () => binding,
            ),
          );
        });
        await tester.pumpWidget(surface(observed));
        await tester.pump(const Duration(seconds: 2));
        expect(observed.calls, 0);
        expect(find.text('სტატუსი ჯერ არ შემოწმებულა.'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('printer-agent-refresh')));
          final health = await observed.lastCall.timeout(
            const Duration(seconds: 10),
          );
          expect(health.physicalHeld, isTrue);
          expect(health.admissionHeld, isTrue);
          expect(health.activeAdmissions, 0);
        });
        await tester.pumpAndSettle();
        expect(find.text('აგენტი ხელმისაწვდომია'), findsOneWidget);
        expect(find.text('ფიზიკური ბეჭდვა შეჩერებულია'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('printer-agent-checked-at')),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 30));
        expect(observed.calls, 1);
        await tester.runAsync(stopChild);
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('printer-agent-refresh')));
          await expectLater(
            observed.lastCall,
            throwsA(
              isA<PrinterAgentException>().having(
                (e) => e.reason,
                'reason',
                PrinterAgentFailure.unavailable,
              ),
            ),
          );
        });
        await tester.pumpAndSettle();
        expect(observed.calls, 2);
        expect(find.textContaining('აგენტი ვერ უკავშირდება'), findsOneWidget);
        expect(find.text('აგენტი ხელმისაწვდომია'), findsNothing);
        expect(fixture.connections, 0);
        expect(tester.takeException(), isNull);
        debugPrint(
          'Actual manual UI → readonly profile → pinned mTLS health '
          'PASS; controlled offline failure PASS; child asserts zero '
          'jobs/receipts/claims/attempts/beeps. Synthetic enrollment only.',
        );
      } finally {
        await tester.runAsync(stopChild);
      }
    },
    skip: goFixture == null || goFixture.isEmpty,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
