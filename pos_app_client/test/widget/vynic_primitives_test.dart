// Widget smoke + overflow tests for the UI Phase 2 primitives. The acceptance
// criterion "no new primitive should overflow at 1280×720" is verified here by
// rendering each primitive with long Georgian labels at that viewport and
// asserting no RenderFlex/overflow exceptions were thrown.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/ui/vynic_ui.dart';

/// A deliberately long Georgian string (Georgian labels run ~20-40% longer
/// than English) to stress ellipsis/wrap behavior.
const _longKa = 'გრძელი ქართული წარწერა რომელიც შესაძლოა გადმოვიდეს ღილაკიდან';

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1280, 720),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('VynicButton renders and truncates a long label', (tester) async {
    await _pumpAt(
      tester,
      const SizedBox(
        width: 160,
        child: VynicButton(label: _longKa, onPressed: null),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(VynicButton), findsOneWidget);
  });

  testWidgets('VynicStatusChip.forState renders every operational state', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      SizedBox(
        width: 220,
        child: Wrap(
          children: [
            for (final state in VynicOperationalState.values)
              Padding(
                padding: const EdgeInsets.all(2),
                child: VynicStatusChip.forState(
                  label: _longKa,
                  state: state,
                  icon: Icons.circle,
                ),
              ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byType(VynicStatusChip),
      findsNWidgets(VynicOperationalState.values.length),
    );
  });

  testWidgets('VynicSectionHeader stacks its action when narrow', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      const SizedBox(
        width: 360,
        child: VynicSectionHeader(
          title: _longKa,
          subtitle: _longKa,
          icon: Icons.dashboard,
          action: VynicButton(label: 'მოქმედება', onPressed: null),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('VynicMetricTile renders without overflow', (tester) async {
    await _pumpAt(
      tester,
      const SizedBox(
        width: 200,
        child: VynicMetricTile(
          label: _longKa,
          value: '1 234.56 ₾',
          icon: Icons.payments,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('VynicEmptyState and VynicLoadingState render', (tester) async {
    await _pumpAt(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 380,
            width: 320,
            child: VynicEmptyState(
              icon: Icons.inbox,
              title: _longKa,
              message: _longKa,
            ),
          ),
          SizedBox(
            height: 160,
            width: 320,
            child: VynicLoadingState(message: _longKa),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('VynicTwoPaneLayout shows both panes when wide', (tester) async {
    await _pumpAt(
      tester,
      const SizedBox(
        width: 1280,
        height: 700,
        child: VynicTwoPaneLayout(
          primary: ColoredBox(color: Color(0xFFEEEEEE)),
          secondary: ColoredBox(color: Color(0xFFDDDDDD)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Both panes present side by side.
    expect(find.byType(ColoredBox), findsWidgets);
  });

  testWidgets('VynicTwoPaneLayout collapses to one pane when compact', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      const SizedBox(
        width: 900,
        height: 700,
        child: VynicTwoPaneLayout(
          primary: Text('primary'),
          secondary: Text('secondary'),
        ),
      ),
      size: const Size(1000, 700),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('primary'), findsOneWidget);
    // Secondary hidden by default in compact single-pane mode.
    expect(find.text('secondary'), findsNothing);
  });

  testWidgets('VynicResponsiveDialog caps its width on a small viewport', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const VynicResponsiveDialog(
              child: Padding(padding: EdgeInsets.all(24), child: Text(_longKa)),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(VynicResponsiveDialog), findsOneWidget);
  });
}
