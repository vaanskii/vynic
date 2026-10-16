import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_form_controls.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_workflow_actions.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/ui/pos_scaled_surface.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      PosTheme.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
  });

  for (final textScale in [1.0, 1.5]) {
    testWidgets('POS Georgian text survives component themes at $textScale', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1024, 768);
      addTearDown(tester.view.reset);
      var activations = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: PosTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton(
                    focusNode: focus,
                    onPressed: () => activations++,
                    child: const Text('შენახვა'),
                  ),
                  Builder(
                    builder: (context) => Theme(
                      data: AdminTheme.of(context),
                      child: Column(
                        children: [
                          ElevatedButton(
                            onPressed: () {},
                            child: const Text('დამატება'),
                          ),
                          OutlinedButton(
                            onPressed: () {},
                            style: AdminDesign.outlineButtonStyle(),
                            child: const Text('რედაქტირება'),
                          ),
                          const TextButton(
                            onPressed: null,
                            child: Text('მიუწვდომელია'),
                          ),
                          const Chip(label: Text('თანამშრომელი')),
                          ElevatedButton(
                            onPressed: () {},
                            style: AdminFormButtons.primary(),
                            child: const Text('პარამეტრების შენახვა'),
                          ),
                          const TextField(
                            decoration: InputDecoration(labelText: 'ძიება'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PosDialogTheme(
                    child: ElevatedButton(
                      onPressed: () {},
                      child: const Text('დადასტურება'),
                    ),
                  ),
                  PosWorkflowButton(
                    label: 'რეზერვაცია',
                    icon: Icons.event_outlined,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final label in [
        'შენახვა',
        'დამატება',
        'რედაქტირება',
        'მიუწვდომელია',
        'თანამშრომელი',
        'პარამეტრების შენახვა',
        'ძიება',
        'დადასტურება',
        'რეზერვაცია',
      ]) {
        final rendered = tester.widget<RichText>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText && widget.text.toPlainText() == label,
          ),
        );
        expect(
          rendered.text.style?.fontFamily,
          PosTheme.fontFamily,
          reason: '$label lost the bundled Georgian font',
        );
      }
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activations, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shared POS controls keep 48px painted targets at 1024', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    var selectedPane = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: PosTheme.light,
        builder: (_, child) => PosScaledSurface(scale: 1, child: child!),
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(
                key: const ValueKey('root'),
                onPressed: () {},
                child: const Text('შენახვა'),
              ),
              Builder(
                builder: (context) => Theme(
                  data: AdminTheme.of(context),
                  child: OutlinedButton(
                    key: const ValueKey('admin'),
                    onPressed: () {},
                    child: const Text('რედაქტირება'),
                  ),
                ),
              ),
              PosDialogTheme(
                child: TextButton(
                  key: const ValueKey('modal'),
                  onPressed: () {},
                  child: const Text('დახურვა'),
                ),
              ),
              PosActionButton(
                key: const ValueKey('action'),
                label: 'ბეჭდვა',
                onTap: () {},
              ),
              PosPrimaryButton(
                key: const ValueKey('primary'),
                label: 'გადახდა',
                onTap: () {},
              ),
              PosPaneSwitch(
                labels: const ['სია', 'შეფასება'],
                selectedIndex: 0,
                onSelected: (value) => selectedPane = value,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    for (final key in ['root', 'admin', 'modal', 'action', 'primary']) {
      final box = tester.renderObject<RenderBox>(find.byKey(ValueKey(key)));
      final height =
          box.localToGlobal(Offset(0, box.size.height)).dy -
          box.localToGlobal(Offset.zero).dy;
      expect(
        height,
        greaterThanOrEqualTo(47.5),
        reason: '$key shrinks below the POS touch target',
      );
    }
    final pane = find
        .ancestor(of: find.text('შეფასება'), matching: find.byType(InkWell))
        .first;
    final box = tester.renderObject<RenderBox>(pane);
    final height =
        box.localToGlobal(Offset(0, box.size.height)).dy -
        box.localToGlobal(Offset.zero).dy;
    expect(height, greaterThanOrEqualTo(47.5));
    await tester.tap(pane);
    expect(selectedPane, 1);
    expect(tester.takeException(), isNull);
  });

  test('custom text and focus colors keep readable contrast', () {
    double contrast(Color foreground, Color background) {
      final a = foreground.computeLuminance();
      final b = background.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    for (final foreground in [
      VynicFloorTokens.text,
      VynicFloorTokens.textMuted,
      VynicFloorTokens.textFaint,
      VynicFloorTokens.accentStrong,
      VynicFloorTokens.dangerText,
    ]) {
      expect(
        contrast(foreground, VynicFloorTokens.panel),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrast(VynicFloorTokens.accentStrong, VynicFloorTokens.canvas),
      greaterThanOrEqualTo(3),
    );
  });
}
