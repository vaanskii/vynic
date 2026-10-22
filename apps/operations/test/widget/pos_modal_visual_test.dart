import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/reservation_creation_sheet.dart';
import 'package:vynic/apps/windows_pos/widgets/time_entry_pad.dart';
import 'package:vynic/apps/windows_pos/widgets/admin_verification_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/menu_item_form.dart';
import 'package:vynic/apps/windows_pos/widgets/estimate_customer_dialog.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard.dart';
import '../support/pos03_fixture.dart';

// Opt-in image output: no production bootstrap, network, or restaurant data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Pos03Fixture fixture;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vynic_modal_visual_');
    fixture = Pos03Fixture();
    await fixture.open(directory.path);
    await DatabaseCore.settingsBox!.putAll({
      'currentDate': '2026-10-15T00:00:00.000',
      'defaultLanguage': 'ka',
    });
    PosInputSettings.active = true;
    PosInputSettings.enabled.value = true;
    final loader = FontLoader('NotoSansGeorgian')
      ..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  tearDown(() async {
    PosInputSettings.active = false;
    PosInputSettings.keyboardHeight.value = 0;
    await fixture.close();
    await directory.delete(recursive: true);
  });

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    const output = String.fromEnvironment('POS_MODAL_SCREENSHOTS');
    if (output.isEmpty) return;
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final kind in ['time', 'pin', 'contact', 'menu', 'confirmation']) {
    testWidgets('$kind isolated modal visual', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1024, 768);
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
            builder: (_, child) =>
                PosLocaleHost(child: PosInputScope(child: child!)),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showPosModal<void>(
                      context: context,
                      builder: (_) => switch (kind) {
                        'time' => const TimeEntryDialog(initialTime: '18:30'),
                        'pin' => const AdminVerificationDialog(),
                        'contact' => const EstimateCustomerDialog(
                          name: 'ნინო საცდელი',
                          phone: '555000000',
                        ),
                        'menu' => MenuItemForm(
                          defaultSendToKitchen: true,
                          onAddVariant: (_, __) {},
                          onSave: (_, __, ___, ____, _____) async => true,
                        ),
                        _ => AlertDialog(
                          title: const Text('დახურვის დადასტურება'),
                          content: const Text(
                            'ცვლილებები არ არის შენახული. ნამდვილად გსურთ დახურვა?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('გაგრძელება'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('დახურვა'),
                            ),
                          ],
                        ),
                      },
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await capture(tester, boundary, kind);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final origin in ['admin', 'estimate']) {
    testWidgets('$origin isolated reservation visual and touch latency', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1024, 768);
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
            builder: (_, child) =>
                PosLocaleHost(child: PosInputScope(child: child!)),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () {
                      final sheet = ReservationCreationSheet(
                        title: origin == 'admin'
                            ? 'ახალი რეზერვაცია'
                            : 'რეზერვაციის დადასტურება',
                        initialName: 'ნინო საცდელი',
                        initialPhone: '555000000',
                        initialDate: DateTime(2026, 10, 17),
                        initialGuests: 4,
                        initialTime: const TimeOfDay(hour: 18, minute: 30),
                      );
                      ReservationCreationSheet.show(context, form: sheet);
                    },
                    child: Text(origin),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(origin));
      final watch = Stopwatch()..start();
      final frames = await tester.pumpAndSettle(
        const Duration(milliseconds: 16),
      );
      debugPrint(
        'MODAL_PROFILE $origin open: ${frames * 16}ms scheduled, ${watch.elapsedMicroseconds}us host',
      );
      await capture(tester, boundary, '$origin-reservation');
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'სახელი და გვარი',
      );
      await tester.tap(field);
      var latency = 0;
      while (find.byType(PosKeyboard).evaluate().isEmpty && latency < 1000) {
        await tester.pump(const Duration(milliseconds: 16));
        latency += 16;
      }
      debugPrint(
        'MODAL_PROFILE $origin touch keyboard first build: ${latency}ms',
      );
      expect(
        latency,
        lessThanOrEqualTo(32),
        reason: 'Visible fields must not wait for a pre-scroll animation.',
      );
      await tester.pumpAndSettle();
      await capture(tester, boundary, '$origin-keyboard');
      expect(find.byType(PosKeyboard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
