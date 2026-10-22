import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/count_design_candidate.dart';

void main() {
  for (final variant in ['populated', 'long', 'empty']) {
    testWidgets('Count $variant review candidate renders at actual 1024x768', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1024, 768);
      addTearDown(tester.view.reset);
      await (FontLoader(
        'NotoSansGeorgian',
      )..addFont(rootBundle.load('assets/fonts/NotoSansGeorgian.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: countDesignCandidatePreview(
            empty: variant == 'empty',
            longContent: variant == 'long',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      const output = String.fromEnvironment('COUNT_DESIGN_SCREENSHOT');
      if (output.isNotEmpty)
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            variant == 'populated'
                ? output
                : output.replaceAll('.png', '-$variant.png'),
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      if (variant != 'empty') {
        expect(find.text('რეზერვაცია').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('რაოდენობის გაზრდა').first);
        await tester.pump();
        expect(find.text('76.00 ₾'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } else {
        expect(find.text('შექმენით პირველი შეფასება'), findsOneWidget);
      }
    });
  }
}
