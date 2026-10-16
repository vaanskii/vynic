import 'dart:io';
import 'package:vynic/apps/windows_pos/screens/developer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/printers/admin_printers_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/printers/additional_printers_section.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/local_printer_catalog.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import '../support/pos02_fixture.dart';
import '../support/pos02_developer_fixture.dart';
import 'package:vynic/core/services/security/developer_access.dart';

void main() {
  late Directory root;
  late Pos02Fixture fixture;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vynic_pos02_admin_widget_');
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
  Widget surface(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  Future<void> advance(WidgetTester tester) async {
    for (var n = 0; n < 10; n++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  for (final width in [640.0, 1280.0]) {
    testWidgets('add/cancel form fits at width $width without printing', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(surface(const AdditionalPrintersSection()));
      await tester.tap(find.byKey(const ValueKey('add-printer')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('additional-printer-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('additional-printer-ip')),
        findsOneWidget,
      );
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(LocalPrinterCatalog.read(), isEmpty);
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admin adds a named IP once on repeated submit', (tester) async {
    await tester.pumpWidget(surface(const AdditionalPrintersSection()));
    await tester.tap(find.byKey(const ValueKey('add-printer')));
    await tester.pumpAndSettle();
    tester
            .widget<PosOnScreenTextField>(
              find.byKey(const ValueKey('additional-printer-name')),
            )
            .controller
            .text =
        'ბარი';
    tester
            .widget<PosOnScreenTextField>(
              find.byKey(const ValueKey('additional-printer-ip')),
            )
            .controller
            .text =
        '10.0.0.7';
    final submit = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('additional-printer-save')),
        )
        .onPressed!;
    await tester.runAsync(() async {
      submit();
      submit();
    });
    await advance(tester);
    await tester.pumpAndSettle();
    expect(LocalPrinterCatalog.read(), hasLength(1));
    expect(find.text('ბარი'), findsOneWidget);
    expect(find.text('10.0.0.7:9100 · მარშრუტი დასადგენია'), findsOneWidget);
    expect(fixture.connections, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bad IP remains visible and cancel leaves the database empty', (
    tester,
  ) async {
    await tester.pumpWidget(surface(const AdditionalPrintersSection()));
    await tester.tap(find.byKey(const ValueKey('add-printer')));
    await tester.pumpAndSettle();
    tester
            .widget<PosOnScreenTextField>(
              find.byKey(const ValueKey('additional-printer-name')),
            )
            .controller
            .text =
        'ბარი';
    tester
            .widget<PosOnScreenTextField>(
              find.byKey(const ValueKey('additional-printer-ip')),
            )
            .controller
            .text =
        '999.1.2.3';
    await tester.tap(find.byKey(const ValueKey('additional-printer-save')));
    await advance(tester);
    expect(find.textContaining('valid IPv4'), findsOneWidget);
    expect(LocalPrinterCatalog.read(), isEmpty);
    await tester.tap(find.text('გაუქმება'));
    await tester.pumpAndSettle();
    expect(fixture.connections, 0);
  });

  testWidgets(
    'fixed Kitchen/Receipt controls coexist with extra printer list',
    (tester) async {
      await tester.runAsync(() => LocalPrinterCatalog.add('ბარი', '10.0.0.7'));
      final kitchen = TextEditingController();
      final receipt = TextEditingController();
      final port = TextEditingController(text: '9100');
      addTearDown(kitchen.dispose);
      addTearDown(receipt.dispose);
      addTearDown(port.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminPrintersSection(
              kitchenPrinterController: kitchen,
              receiptPrinterController: receipt,
              printerPortController: port,
              isSavingPrinterSettings: false,
              isTestingPrinters: false,
              onSavePrinterSettings: () async {},
              onTestPrinterConnections: () async {},
            ),
          ),
        ),
      );
      expect(find.text('სამზარეულო'), findsOneWidget);
      expect(find.text('ჩეკი'), findsOneWidget);
      expect(find.byType(AdditionalPrintersSection), findsOneWidget);
      expect(find.text('ბარი'), findsOneWidget);
      expect(DatabaseService.getKitchenPrinterIp(), 'synthetic.invalid');
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'malformed prior registration disables add without discarding data',
    (tester) async {
      await tester.runAsync(
        () => DatabaseCore.settingsBox!.put('printersList', ['legacy-record']),
      );
      await tester.pumpWidget(surface(const AdditionalPrintersSection()));
      expect(find.textContaining('ჩანაწერი შესამოწმებელია'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('add-printer')))
            .onPressed,
        isNull,
      );
      expect(DatabaseCore.settingsBox!.get('printersList'), ['legacy-record']);
    },
  );
  testWidgets(
    'manager cannot see or add extra printers without developer access',
    (tester) async {
      await tester.runAsync(
        () => LocalPrinterCatalog.add('Synthetic bar', '10.0.0.7'),
      );
      DeveloperAccess.lock();
      await tester.pumpWidget(surface(const AdditionalPrintersSection()));
      expect(find.text('Synthetic bar'), findsNothing);
      expect(find.byKey(const ValueKey('add-printer')), findsNothing);
      expect(fixture.connections, 0);
    },
  );

  testWidgets(
    'login support route hides printers from diagnostics-only token',
    (tester) async {
      await tester.runAsync(
        () => unlockSyntheticPrinterDeveloper(
          scopes: [DeveloperScope.diagnostics],
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: DeveloperScreen()));
      expect(find.text('პრინტერები'), findsNothing);
      expect(find.byType(AdminPrintersSection), findsNothing);
      expect(fixture.connections, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('login support route gives printer scope its existing controls', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DeveloperScreen()));
    await tester.tap(find.text('პრინტერები'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminPrintersSection), findsOneWidget);
    expect(find.byType(AdditionalPrintersSection), findsOneWidget);
    expect(fixture.connections, 0);
    expect(tester.takeException(), isNull);
  });
}
