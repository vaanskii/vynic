import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_canvas.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_inspector.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_palette.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_painter.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_screen.dart';
import 'package:vynic/core/models/table_layout.dart';

/// The editor is desktop-first but has to survive the small POS terminals
/// too. These pump it at every supported resolution and assert the canvas
/// keeps the lion's share of the window — the side panels must never take
/// over at 1024x768.

const _resolutions = <(String, Size)>[
  ('1024x768', Size(1024, 768)),
  ('1280x720', Size(1280, 720)),
  ('1366x768', Size(1366, 768)),
  ('1440x900', Size(1440, 900)),
  ('1920x1080', Size(1920, 1080)),
];

Future<void> _pumpEditor(WidgetTester tester, Size size) async {
  tester.view
    ..devicePixelRatio = 1.0
    ..physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: FloorEditorScreen(
        layout: RestaurantTableLayouts.floorPlanPreview,
        floorId: RestaurantTableLayouts.floorPlanPreview.zones.first.id,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in _resolutions) {
    testWidgets('renders without overflow at $name', (tester) async {
      await _pumpEditor(tester, size);

      expect(tester.takeException(), isNull);
      expect(find.byType(FloorEditorCanvas), findsOneWidget);
      expect(find.byType(FloorEditorPalette), findsOneWidget);
    });

    testWidgets('canvas stays the largest region at $name', (tester) async {
      await _pumpEditor(tester, size);

      final canvasWidth = tester.getSize(find.byType(FloorEditorCanvas)).width;
      final paletteWidth = tester
          .getSize(find.byType(FloorEditorPalette))
          .width;
      final inspectorWidth =
          find.byType(FloorEditorInspector).evaluate().isEmpty
          ? 0.0
          : tester.getSize(find.byType(FloorEditorInspector)).width;

      expect(canvasWidth, greaterThan(paletteWidth + inspectorWidth));
      expect(canvasWidth, greaterThan(size.width / 2));
    });
  }

  testWidgets('the tool palette collapses to icons on a narrow window', (
    tester,
  ) async {
    await _pumpEditor(tester, const Size(1024, 768));
    final compactWidth = tester.getSize(find.byType(FloorEditorPalette)).width;

    await _pumpEditor(tester, const Size(1920, 1080));
    final fullWidth = tester.getSize(find.byType(FloorEditorPalette)).width;

    expect(compactWidth, lessThan(fullWidth));
  });

  testWidgets('the zoom controls are present and discoverable', (tester) async {
    await _pumpEditor(tester, const Size(1440, 900));
    expect(find.byType(FloorEditorZoomControls), findsOneWidget);
    expect(find.byType(FloorEditorStatusStrip), findsOneWidget);
  });

  _canvasTests();
}

/// The painter that is actually on screen. Reading its fields — rather than
/// the zoom readout — is the point: the readout comes from a separate
/// listenable and stayed correct even when the canvas was frozen.
FloorEditorPainter _livePainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(FloorEditorCanvas),
      matching: find.byType(CustomPaint),
    ),
  );
  return paints
      .map((paint) => paint.painter)
      .whereType<FloorEditorPainter>()
      .first;
}

void _canvasTests() {
  testWidgets('opens fitted to the window rather than at 100%', (tester) async {
    await _pumpEditor(tester, const Size(1440, 900));

    final painter = _livePainter(tester);
    // The default floor is 1005x1101 canvas units; at this window size it
    // has to be scaled down to fit, and the *painter* must know that.
    expect(painter.scale, lessThan(1.0));
    expect(painter.scale, greaterThan(0.2));

    // And it must be centred, not pinned to the corner.
    expect(painter.offset.dx, greaterThan(0));
    expect(painter.offset.dy, greaterThanOrEqualTo(0));
  });

  testWidgets('the zoom buttons change what is painted', (tester) async {
    await _pumpEditor(tester, const Size(1440, 900));
    final fitted = _livePainter(tester).scale;

    await tester.tap(find.byTooltip('გადიდება'));
    await tester.pumpAndSettle();
    expect(_livePainter(tester).scale, greaterThan(fitted));

    await tester.tap(find.byTooltip('დაპატარავება'));
    await tester.pumpAndSettle();
    expect(_livePainter(tester).scale, closeTo(fitted, 0.001));

    await tester.tap(find.byTooltip('მთლიანი ხედი'));
    await tester.pumpAndSettle();
    expect(_livePainter(tester).scale, closeTo(fitted, 0.001));
  });

  testWidgets('zooming keeps the plan centred in the viewport', (tester) async {
    await _pumpEditor(tester, const Size(1440, 900));
    final canvasSize = tester.getSize(find.byType(FloorEditorCanvas));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('გადიდება'));
      await tester.pumpAndSettle();
    }

    final painter = _livePainter(tester);
    final planCentre =
        Offset(painter.floor.canvasWidth, painter.floor.canvasHeight) /
            2 *
            painter.scale +
        painter.offset;

    expect(planCentre.dx, closeTo(canvasSize.width / 2, 1));
    expect(planCentre.dy, closeTo(canvasSize.height / 2, 1));
  });

  testWidgets('clicking a table selects it, and the painter is told', (
    tester,
  ) async {
    await _pumpEditor(tester, const Size(1440, 900));
    expect(_livePainter(tester).selection, isEmpty);

    final painter = _livePainter(tester);
    final table = painter.floor.tables.first;
    final canvasTopLeft = tester.getTopLeft(find.byType(FloorEditorCanvas));
    await tester.tapAt(
      canvasTopLeft + table.center * painter.scale + painter.offset,
    );
    await tester.pumpAndSettle();

    expect(_livePainter(tester).selection, contains(table.id));
    expect(_livePainter(tester).showHandles, isTrue);
  });
}
