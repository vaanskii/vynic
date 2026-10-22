// Isolated render: approved preview versus production, synthetic test data only.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_preview_charts.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/manager_design_components.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/apps/mobile_app/theme/manager_dashboard_theme.dart';
import '../fixtures/manager_reference_preview/main.dart' as preview;
import '../fixtures/manager_reference_preview/screens.dart' as approved;
import '../fixtures/manager_reference_preview/design.dart' as design;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansGeorgian',
    )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    ManagerAppPreferences.dashboardAppearance.value =
        ManagerDashboardAppearance.light;
  });
  for (final width in [390.0, 780.0, 834.0, 1440.0, 1728.0, 1920.0]) {
    testWidgets('approved and production charts $width', (t) async {
      t.view.physicalSize = Size(width, width < 850 ? 400 : 500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      final compact = width < 850;
      const values = [4800.0, 6900.0, 5800.0, 8200.0, 6600.0, 7491.0, 8450.0];
      for (final reference in [true, false]) {
        final chart = reference
            ? approved.RevenueBars(compact: compact)
            : ManagerRevenueBars(
                compact: compact,
                points: [
                  for (var i = 0; i < values.length; i++)
                    ManagerRevenuePoint(
                      label: '${10 + i} ოქტ',
                      value: values[i],
                      isToday: i == 6,
                    ),
                ],
              );
        final occupancy = reference
            ? Row(
                children: List.generate(
                  18,
                  (i) => Expanded(
                    child: Container(
                      height: 24,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: i < 8
                            ? design.D.purple
                            : const Color(0xFFEDE9F2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              )
            : const ManagerOccupancyBars(total: 18, occupied: 8);
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: design.previewTheme(),
              home: Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(compact ? 20 : 32),
                  child: ManagerPanel(
                    padding: compact ? 20 : 26,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'გაყიდვების დინამიკა',
                          style: design.ts(12, weight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        chart,
                        const SizedBox(height: 26),
                        Text('რესტორანი ახლა · 8 / 18', style: design.ts(12)),
                        const SizedBox(height: 15),
                        occupancy,
                        const SizedBox(height: 20),
                        Text(
                          'სინთეტიკური მონაცემები · დიზაინის შედარება',
                          style: design.ts(10, color: design.D.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final output = Platform.environment['MANAGER_RENDER_DIR'];
        if (output != null)
          await t.runAsync(() async {
            await Directory(output).create(recursive: true);
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              '$output/chart-${reference ? 'approved' : 'production'}-${width.toInt()}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
      }
    });
  }
  for (final size in [const Size(390, 844), const Size(1728, 1117)]) {
    testWidgets('approved full dashboard ${size.width}', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(key: key, child: const preview.ManagerPreview()),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final output = Platform.environment['MANAGER_RENDER_DIR'];
      if (output != null)
        await t.runAsync(() async {
          await Directory(output).create(recursive: true);
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$output/dashboard-approved-${size.width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }
  testWidgets('unavailable history stays unavailable; zero stays zero', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ManagerRevenueBars(points: [])),
      ),
    );
    expect(find.text('გაყიდვების ისტორია მიუწვდომელია'), findsOneWidget);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ManagerRevenueBars(
            points: [ManagerRevenuePoint(label: 'დღეს', value: 0)],
          ),
        ),
      ),
    );
    expect(find.text('გაყიდვების ისტორია მიუწვდომელია'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
