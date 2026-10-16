import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_amount_form.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';

void main() {
  late TextEditingController controller;
  double? result;
  var returns = 0;
  setUp(() {
    controller = TextEditingController(text: '12.50');
    result = null;
    returns = 0;
  });
  tearDown(() => controller.dispose());

  Future<void> host(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PosTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showPosModal<double>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => PosAmountForm(
                    title: 'ფასის კორექცია',
                    description: 'დადებითი ზრდის ჯამს, უარყოფითი ამცირებს.',
                    controller: controller,
                    keypad: const SizedBox(height: 220),
                    clearLabel: 'განულება',
                    parse: (raw) => double.tryParse(raw) ?? 0,
                    validate: (raw) => (double.tryParse(raw) ?? 0) > 100
                        ? 'მაქსიმალური თანხაა 100 GEL'
                        : null,
                  ),
                );
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
  }

  testWidgets(
    'invalid amount stays inline; keyboard submit returns the corrected amount',
    (tester) async {
      await host(tester, scale: 1.5);
      await tester.enterText(find.byType(TextField), '101');
      expect(controller.text, '101');
      await tester.tap(find.text('შენახვა'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.errorText,
        'მაქსიმალური თანხაა 100 GEL',
      );
      expect(returns, 0);
      await tester.enterText(find.byType(TextField), '-18.25');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, -18.25);
      expect(returns, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel close and Escape repeatedly return no amount', (
    tester,
  ) async {
    await host(tester);
    for (final action in ['გაუქმება', 'დახურვა', 'escape']) {
      if (action == 'escape') {
        await tester.tap(find.byType(TextField));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else if (action == 'დახურვა') {
        await tester.tap(find.byTooltip(action));
      } else {
        await tester.tap(find.text(action));
      }
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(PosAmountForm), findsNothing);
      expect(controller.text, '12.50');
      if (action != 'escape') {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }
    }
    expect(returns, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit clear alone returns zero', (tester) async {
    await host(tester);
    await tester.tap(find.text('განულება'));
    await tester.pumpAndSettle();
    expect(result, 0);
    expect(returns, 1);
  });
}
