import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/printers/additional_printers_section.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/printing/local_printer_catalog.dart';
import 'package:vynic/core/services/printing/printer_destination.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';
import 'package:vynic/core/services/printing/windows_spooler_transport.dart';
import 'package:vynic/core/services/security/developer_access.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

import '../support/pos02_developer_fixture.dart';
import '../support/pos02_fixture.dart';

const _device = '00000000-0000-4000-8000-000000000011';
const _channel = MethodChannel('vynic/synthetic_route_configuration');

void main() {
  late Directory root;
  late Pos02Fixture fixture;
  late List<Map<String, String>> inventory;
  late List<String> nativeCalls;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_printer_route_widget_');
    fixture = Pos02Fixture();
    await fixture.open(root.path);
    await fixture.seed(venueId: 'synthetic-venue');
    await DatabaseCore.settingsBox!.delete('deviceRuntimeConfig');
    EdgeDeviceCredentialStore.resetForTest();
    EdgeDeviceCredentialStore.directoryOverride = root.path;
    await unlockSyntheticPrinterDeveloper();
    inventory = [
      {
        'name': 'Synthetic RAW',
        'driver': 'Synthetic ESC/POS',
        'port': 'USB001',
      },
    ];
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          nativeCalls.add(call.method);
          expect(call.method, 'listQueues');
          return inventory;
        });
    LocalPrinterCatalog.windowsTransportOverride = null;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    LocalPrinterCatalog.windowsTransportOverride = null;
    EdgeDeviceCredentialStore.directoryOverride = null;
    EdgeDeviceCredentialStore.resetForTest();
    DeveloperAccess.resetForTest();
    DeveloperAccess.publicKeyOverride = null;
    await fixture.close();
    await root.delete(recursive: true);
  });

  Widget surface() => const MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: AdditionalPrintersSection()),
    ),
  );

  Future<void> advance(WidgetTester tester) async {
    for (var count = 0; count < 8; count++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(surface());
    await tester.ensureVisible(find.byKey(const ValueKey('add-printer-route')));
    await tester.tap(find.byKey(const ValueKey('add-printer-route')));
    await tester.pumpAndSettle();
  }

  void enter(WidgetTester tester, String key, String value) {
    tester
            .widget<PosOnScreenTextField>(find.byKey(ValueKey(key)))
            .controller
            .text =
        value;
  }

  DropdownButton<T> dropdown<T>(WidgetTester tester, String key) =>
      tester.widget<DropdownButton<T>>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(DropdownButton<T>),
        ),
      );

  Future<void> selectOption(
    WidgetTester tester,
    String key,
    String label,
  ) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final save = tester
        .widget<FilledButton>(find.byKey(const ValueKey('printer-route-save')))
        .onPressed!;
    await tester.runAsync(() async => save());
    await advance(tester);
    await tester.pumpAndSettle();
  }

  Future<void> selectWindows(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('printer-route-transport')),
    );
    await tester.tap(find.byKey(const ValueKey('printer-route-transport')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Windows პრინტერის რიგი').last);
    await advance(tester);
    await tester.pumpAndSettle();
  }

  Future<void> prepareWindows() async {
    expect(
      await EdgeDeviceCredentialStore.saveEnrollment(
        rawCredential: 'vynic-device-v1.$_device.${'x' * 40}',
        venueId: 'synthetic-venue',
        venueName: 'Synthetic fixture',
      ),
      true,
    );
    LocalPrinterCatalog.windowsTransportOverride = WindowsSpoolerTransport(
      channel: _channel,
      isWindows: () => true,
    );
  }

  for (final size in [
    const Size(360, 480),
    const Size(640, 600),
    const Size(1280, 720),
  ]) {
    testWidgets('LAN route dialog scrolls and cancels cleanly at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester);
      expect(find.byKey(const ValueKey('printer-route-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('printer-route-role')), findsOneWidget);
      expect(find.byKey(const ValueKey('printer-route-ip')), findsOneWidget);
      expect(find.byKey(const ValueKey('printer-route-port')), findsOneWidget);
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(LocalPrinterCatalog.readRoutesForDispatch(), isEmpty);
      expect(fixture.connections, 0);
      expect(nativeCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'developer assigns a bar LAN route while legacy additions remain unassigned',
    (tester) async {
      await tester.runAsync(
        () => LocalPrinterCatalog.add('Legacy station', '10.30.0.8'),
      );
      await open(tester);
      enter(tester, 'printer-route-name', 'ბარი LAN');
      enter(tester, 'printer-route-ip', '10.30.0.1');
      enter(tester, 'printer-route-port', '9200');
      await tester.tap(find.byKey(const ValueKey('printer-route-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ბარის მარშრუტი').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('printer-route-save')),
      );
      final submit = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('printer-route-save')),
          )
          .onPressed!;
      await tester.runAsync(() async {
        submit();
        submit();
      });
      await advance(tester);
      await tester.pumpAndSettle();
      final route = LocalPrinterCatalog.readRoutesForDispatch().single;
      expect(route.role, PrinterRole.bar);
      expect(route.destination.host, '10.30.0.1');
      expect(route.destination.port, 9200);
      expect(route.revision, 1);
      expect(LocalPrinterCatalog.read().single['routing'], 'unassigned');
      expect(find.text('ბარი LAN'), findsOneWidget);
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows queue option requires local Windows transport and enrollment',
    (tester) async {
      await open(tester);
      final field = dropdown<PrinterTransportKind>(
        tester,
        'printer-route-transport',
      );
      expect(
        field.items!
            .singleWhere(
              (item) => item.value == PrinterTransportKind.windowsSpooler,
            )
            .enabled,
        false,
      );
      expect(nativeCalls, isEmpty);
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Windows selection freezes only the enumerated exact queue and revalidates on save',
    (tester) async {
      await tester.runAsync(prepareWindows);
      await open(tester);
      enter(tester, 'printer-route-name', 'USB ბარი');
      await selectWindows(tester);
      expect(find.byKey(const ValueKey('printer-route-ip')), findsNothing);
      expect(
        find.text('ESC/POS მხარდაჭერა ფიზიკურად ჯერ შესამოწმებელია.'),
        findsOneWidget,
      );
      expect(nativeCalls, ['listQueues']);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('printer-route-save')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('printer-route-queue')),
      );
      await tester.tap(find.byKey(const ValueKey('printer-route-queue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic RAW').last);
      await tester.pumpAndSettle();
      expect(
        find.text('დრაივერი: Synthetic ESC/POS\nპორტი: USB001'),
        findsOneWidget,
      );
      final submit = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('printer-route-save')),
          )
          .onPressed!;
      await tester.runAsync(() async => submit());
      await advance(tester);
      await tester.pumpAndSettle();
      final route = LocalPrinterCatalog.readRoutesForDispatch().single;
      expect(route.destination.ownerDeviceId, _device);
      expect(route.destination.queueName, 'Synthetic RAW');
      expect(route.destination.driverName, 'Synthetic ESC/POS');
      expect(route.destination.portName, 'USB001');
      expect(nativeCalls, ['listQueues', 'listQueues']);
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'queue changed after selection shows a failure without saving or submitting',
    (tester) async {
      await tester.runAsync(prepareWindows);
      await open(tester);
      enter(tester, 'printer-route-name', 'USB ბარი');
      await selectWindows(tester);
      final queueField = dropdown<WindowsPrinterQueue>(
        tester,
        'printer-route-queue',
      );
      queueField.onChanged!(queueField.items!.single.value);
      await tester.pump();
      inventory.single['port'] = 'USB002';
      final submit = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('printer-route-save')),
          )
          .onPressed!;
      await tester.runAsync(() async => submit());
      await advance(tester);
      expect(find.textContaining('no longer installed'), findsOneWidget);
      expect(LocalPrinterCatalog.readRoutesForDispatch(), isEmpty);
      expect(nativeCalls, ['listQueues', 'listQueues']);
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cloud ownership shows a hold and prevents a local primary replacement',
    (tester) async {
      final route = await tester.runAsync(
        () => LocalPrinterCatalog.saveRoute(
          name: 'Kitchen route',
          role: PrinterRole.kitchen,
          destination: PrinterDestination.tcp(host: '10.30.0.1', port: 9100),
          expectedRevision: 0,
        ),
      );
      final cloud = {
        'version': 1,
        'printers': {
          'kitchen': {'enabled': true, 'host': '10.30.0.9', 'port': 9100},
          'receipt': {'enabled': false, 'host': '', 'port': 9100},
        },
      };
      await tester.runAsync(
        () => DatabaseCore.settingsBox!.put('deviceRuntimeConfig', cloud),
      );
      await tester.pumpWidget(surface());
      expect(find.textContaining('შეჩერებულია: Cloud'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(ValueKey('edit-printer-route-${route!.id}')),
      );
      await tester.tap(find.byKey(ValueKey('edit-printer-route-${route.id}')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('printer-route-save')),
            )
            .onPressed,
        isNull,
      );
      final roles = dropdown<PrinterRole>(tester, 'printer-route-role');
      expect(
        roles.items!
            .where(
              (item) =>
                  item.value == PrinterRole.kitchen ||
                  item.value == PrinterRole.receipt,
            )
            .every((item) => !item.enabled),
        true,
      );
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(DatabaseCore.settingsBox!.get('deviceRuntimeConfig'), cloud);
      expect(
        LocalPrinterCatalog.readRoutesForAdministration().single.revision,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale edits show a conflict and closing reloads the accepted revision',
    (tester) async {
      final original = await tester.runAsync(
        () => LocalPrinterCatalog.saveRoute(
          name: 'Bar route',
          role: PrinterRole.bar,
          destination: PrinterDestination.tcp(host: '10.30.0.1', port: 9100),
          expectedRevision: 0,
        ),
      );
      await tester.pumpWidget(surface());
      final edit = find.byKey(ValueKey('edit-printer-route-${original!.id}'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final accepted = await tester.runAsync(
        () => LocalPrinterCatalog.saveRoute(
          id: original.id,
          name: original.name,
          role: original.role,
          destination: PrinterDestination.tcp(host: '10.30.0.2', port: 9200),
          expectedRevision: original.revision,
        ),
      );
      enter(tester, 'printer-route-ip', '10.30.0.3');
      final submit = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('printer-route-save')),
          )
          .onPressed!;
      await tester.runAsync(() async => submit());
      await advance(tester);
      expect(
        find.text('მარშრუტი შეიცვალა. დახურეთ ფანჯარა და ხელახლა გახსენით.'),
        findsOneWidget,
      );
      expect(
        LocalPrinterCatalog.readRoutesForDispatch().single.toMap(),
        accepted!.toMap(),
      );
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(find.textContaining('10.30.0.2:9200 · ვერსია 2'), findsOneWidget);
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PosOnScreenTextField>(
              find.byKey(const ValueKey('printer-route-ip')),
            )
            .controller
            .text,
        '10.30.0.2',
      );
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'locking an open route dialog disables its fields and captured submit handler',
    (tester) async {
      await open(tester);
      enter(tester, 'printer-route-name', 'Blocked');
      enter(tester, 'printer-route-ip', '10.30.0.1');
      final captured = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('printer-route-save')),
          )
          .onPressed!;
      DeveloperAccess.lock();
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('printer-route-save')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<PosOnScreenTextField>(
              find.byKey(const ValueKey('printer-route-name')),
            )
            .enabled,
        false,
      );
      captured();
      await advance(tester);
      expect(LocalPrinterCatalog.readRoutesForDispatch(), isEmpty);
      expect(find.byKey(const ValueKey('add-printer-route')), findsNothing);
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'malformed versioned routes disable administration while retaining stored data',
    (tester) async {
      await tester.runAsync(
        () => DatabaseCore.settingsBox!.put(
          LocalPrinterCatalog.routesSettingKey,
          ['malformed'],
        ),
      );
      await tester.pumpWidget(surface());
      expect(find.textContaining('ჩანაწერი შესამოწმებელია'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('add-printer-route')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('add-printer')))
            .onPressed,
        isNull,
      );
      expect(
        DatabaseCore.settingsBox!.get(LocalPrinterCatalog.routesSettingKey),
        ['malformed'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new capability controls use raster defaults with no cutter or sound',
    (tester) async {
      await open(tester);
      expect(
        tester
            .widget<PosOnScreenTextField>(
              find.byKey(const ValueKey('printer-route-paper-width')),
            )
            .controller
            .text,
        '80',
      );
      expect(
        tester
            .widget<PosOnScreenTextField>(
              find.byKey(const ValueKey('printer-route-raster-width')),
            )
            .controller
            .text,
        '576',
      );
      expect(
        dropdown<PrinterCommandLanguage>(
          tester,
          'printer-route-command-language',
        ).value,
        PrinterCommandLanguage.escposRaster,
      );
      expect(
        dropdown<PrinterCutter>(tester, 'printer-route-cutter').value,
        PrinterCutter.none,
      );
      expect(
        dropdown<PrinterBeepCapability>(
          tester,
          'printer-route-beep-capability',
        ).value,
        PrinterBeepCapability.unknown,
      );
      final beep = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('printer-route-beep-enabled')),
      );
      expect(beep.value, false);
      expect(beep.onChanged, isNull);
      expect(
        find.byKey(const ValueKey('printer-route-beep-compatibility')),
        findsNothing,
      );
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(LocalPrinterCatalog.readRoutesForDispatch(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'paper and cutter save explicitly and Epson sound needs confirmation plus enable',
    (tester) async {
      await open(tester);
      enter(tester, 'printer-route-name', 'Configured raster');
      enter(tester, 'printer-route-ip', '10.30.0.1');
      enter(tester, 'printer-route-paper-width', '58');
      enter(tester, 'printer-route-raster-width', '384');
      await selectOption(tester, 'printer-route-cutter', 'ნაწილობრივი ჭრა');
      await selectOption(
        tester,
        'printer-route-beep-capability',
        'Epson-ის რეგისტრირებული ხმის პატერნი',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('printer-route-save')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('printer-route-beep-enabled')),
            )
            .onChanged,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('printer-route-beep-compatibility')),
      );
      await tester.tap(
        find.byKey(const ValueKey('printer-route-beep-compatibility')),
      );
      await tester.pumpAndSettle();
      final compatible = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('printer-route-beep-enabled')),
      );
      expect(compatible.value, false);
      expect(compatible.onChanged, isNotNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('printer-route-beep-enabled')),
      );
      await tester.tap(
        find.byKey(const ValueKey('printer-route-beep-enabled')),
      );
      await tester.pumpAndSettle();
      await submit(tester);
      final accepted = LocalPrinterCatalog.readRoutesForDispatch().single;
      expect(accepted.capabilityProfile.paperWidthMm, 58);
      expect(accepted.capabilityProfile.rasterWidthDots, 384);
      expect(accepted.capabilityProfile.cutter, PrinterCutter.partial);
      expect(
        accepted.capabilityProfile.beep.capability,
        PrinterBeepCapability.epsonEscA97Pattern,
      );
      expect(accepted.capabilityProfile.beep.enabled, true);
      await tester.ensureVisible(
        find.byKey(ValueKey('edit-printer-route-${accepted.id}')),
      );
      await tester.tap(
        find.byKey(ValueKey('edit-printer-route-${accepted.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PosOnScreenTextField>(
              find.byKey(const ValueKey('printer-route-paper-width')),
            )
            .controller
            .text,
        '58',
      );
      expect(
        dropdown<PrinterCutter>(tester, 'printer-route-cutter').value,
        PrinterCutter.partial,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('printer-route-beep-compatibility')),
            )
            .value,
        true,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('printer-route-beep-enabled')),
            )
            .value,
        true,
      );
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('driver-rendered language saves as visibly held configuration', (
    tester,
  ) async {
    await open(tester);
    enter(tester, 'printer-route-name', 'Held driver route');
    enter(tester, 'printer-route-ip', '10.30.0.1');
    await selectOption(
      tester,
      'printer-route-command-language',
      'Windows დრაივერის რენდერი (შეჩერებული)',
    );
    expect(
      find.text(
        'შეჩერებულია: Windows დრაივერის რენდერი ჯერ არ არის ხელმისაწვდომი.',
      ),
      findsOneWidget,
    );
    await submit(tester);
    final held = LocalPrinterCatalog.readRoutesForAdministration().single;
    expect(
      held.capabilityProfile.language,
      PrinterCommandLanguage.windowsDriverRendered,
    );
    expect(LocalPrinterCatalog.readRoutesForDispatch, throwsStateError);
    expect(
      find.textContaining('შეჩერებულია: Windows დრაივერის რენდერი'),
      findsOneWidget,
    );
    expect(fixture.connections, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an absent beep setting stays off when an existing profile is edited',
    (tester) async {
      final route = await tester.runAsync(
        () => LocalPrinterCatalog.saveRoute(
          name: 'Epson name without sound capability',
          role: PrinterRole.bar,
          destination: PrinterDestination.tcp(host: '10.30.0.1', port: 9100),
          expectedRevision: 0,
        ),
      );
      final withoutBeep = route!.capabilityProfile.toMap()..remove('beep');
      await tester.runAsync(
        () => DatabaseCore.settingsBox!.put(
          LocalPrinterCatalog.routesSettingKey,
          [
            {...route.toMap(), 'capabilityProfile': withoutBeep},
          ],
        ),
      );
      await tester.pumpWidget(surface());
      await tester.ensureVisible(
        find.byKey(ValueKey('edit-printer-route-${route.id}')),
      );
      await tester.tap(find.byKey(ValueKey('edit-printer-route-${route.id}')));
      await tester.pumpAndSettle();
      expect(
        dropdown<PrinterBeepCapability>(
          tester,
          'printer-route-beep-capability',
        ).value,
        PrinterBeepCapability.unknown,
      );
      final beep = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('printer-route-beep-enabled')),
      );
      expect(beep.value, false);
      expect(beep.onChanged, isNull);
      await submit(tester);
      expect(
        LocalPrinterCatalog.readRoutesForDispatch()
            .single
            .capabilityProfile
            .beep
            .enabled,
        false,
      );
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid raster dimensions stay visible and do not register a route',
    (tester) async {
      await open(tester);
      enter(tester, 'printer-route-name', 'Invalid raster');
      enter(tester, 'printer-route-ip', '10.30.0.1');
      enter(tester, 'printer-route-raster-width', '385');
      await submit(tester);
      expect(find.textContaining('8-ის ჯერადი'), findsOneWidget);
      expect(LocalPrinterCatalog.readRoutesForDispatch(), isEmpty);
      await tester.ensureVisible(find.text('გაუქმება'));
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
