import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/services/pos/table_payment_service.dart';
import 'package:vynic/core/ui/pos_scaled_surface.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import 'package:vynic/core/widgets/pin_button.dart';
import '../support/pos03_fixture.dart';

void main() {
  late Directory directory;
  late Pos03Fixture fixture;
  TablePaymentSelection? result;
  var returns = 0;
  final captureKey = GlobalKey();
  setUpAll(() async {
    await (FontLoader(
      PosTheme.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vynic_payment_ui_');
    fixture = Pos03Fixture();
    await fixture.open(directory.path);
    await DatabaseCore.settingsBox!.put('defaultLanguage', 'ka');
    PosInputSettings.active = true;
    PosInputSettings.enabled.value = true;
    result = null;
    returns = 0;
  });
  tearDown(() async {
    PosInputSettings.active = false;
    PosInputSettings.keyboardHeight.value = 0;
    await fixture.close();
    await directory.delete(recursive: true);
  });

  Future<void> host(
    WidgetTester tester, {
    double total = 100,
    double scale = 1,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: PosTheme.light,
        builder: (context, child) => RepaintBoundary(
          key: captureKey,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: PosScaledSurface(
              scale: 1,
              child: PosLocaleHost(child: PosInputScope(child: child!)),
            ),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await TablePaymentService(
                  context: context,
                  total: total,
                  grossTotal: total + 20,
                  advanceApplied: 20,
                ).collect();
                returns++;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    const output = String.fromEnvironment('POS_PAYMENT_SCREENSHOTS');
    if (output.isEmpty) return;
    await tester.runAsync(() async {
      final image =
          await (captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final method in ['cash', 'tbc', 'bog', 'split']) {
    testWidgets(
      '$method selection preserves amount/provider and requires confirmation',
      (tester) async {
        await host(tester, total: 51.37);
        if (method == 'cash') {
          await screenshot(tester, 'payment-method');
          await tap(tester, 'ნაღდი ფული');
        } else if (method == 'split') {
          await tap(tester, 'გაყოფილი');
          await screenshot(tester, 'payment-split');
          final box = tester.renderObject<RenderBox>(
            find
                .ancestor(
                  of: find.text('1'),
                  matching: find.byType(OutlinedButton),
                )
                .first,
          );
          expect(
            box.localToGlobal(Offset(0, box.size.height)).dy -
                box.localToGlobal(Offset.zero).dy,
            greaterThanOrEqualTo(47.5),
          );
          await tap(tester, 'დადასტურება');
        } else {
          await tap(tester, 'ბარათით');
          await screenshot(tester, 'payment-bank');
          await tap(tester, method == 'tbc' ? 'TBC Bank' : 'Bank of Georgia');
        }
        expect(returns, 0);
        expect(result, isNull);
        await screenshot(tester, 'payment-confirmation');
        await tap(tester, 'დახურვა');
        expect(returns, 1);
        expect(result!.total, 51.37);
        expect(
          result!.cashAmount,
          method == 'cash'
              ? 51.37
              : method == 'split'
              ? 25.69
              : 0,
        );
        expect(
          result!.bankAmount,
          method == 'cash'
              ? 0
              : method == 'split'
              ? 25.68
              : 51.37,
        );
        expect(
          result!.bankProvider,
          method == 'cash'
              ? null
              : method == 'split'
              ? 'tbc'
              : method,
        );
      },
    );
  }

  testWidgets(
    'split edits preserve cents and selected bank at 150 percent Georgian text',
    (tester) async {
      await host(tester, scale: 1.5);
      await tap(tester, 'გაყოფილი');
      await tester.tap(find.byTooltip('გასუფთავება'));
      await tester.pump();
      for (final value in ['2', '5', '.', '5']) {
        await tap(tester, value);
      }
      await tap(tester, 'BOG POS');
      await screenshot(tester, 'payment-split-large-text');
      await tap(tester, 'დადასტურება');
      await tap(tester, 'დახურვა');
      expect(result!.bankAmount, 25.5);
      expect(result!.cashAmount, 74.5);
      expect(result!.bankProvider, 'bog');
    },
  );

  testWidgets(
    'repeated back and cancellation produce no selection or persisted order changes',
    (tester) async {
      await host(tester);
      final initialOrders = DatabaseCore.orderBox!.length;
      for (var repeat = 0; repeat < 3; repeat++) {
        if (repeat > 0) await tap(tester, 'open');
        await tap(tester, 'ბარათით');
        await tap(tester, 'უკან');
        expect(find.text('აირჩიეთ გადახდის მეთოდი'), findsOneWidget);
        await tap(tester, 'გაყოფილი');
        await tap(tester, 'უკან');
        await tap(tester, 'ნაღდი ფული');
        await tap(tester, 'გაუქმება');
        expect(result, isNull);
        expect(returns, repeat + 1);
        expect(DatabaseCore.orderBox!.length, initialOrders);
      }
      expect(find.byType(PinPad), findsNothing);
    },
  );
}
