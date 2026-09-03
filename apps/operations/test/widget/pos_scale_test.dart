import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/core/ui/pos_scaled_surface.dart';

/// What the UI-scale setting actually does to the pixels.
///
/// Two things have to be true at 90%: everything is painted smaller, and the
/// layout is given more room so more fits. Measuring both here because
/// "it doesn't shrink" is otherwise impossible to settle by looking.

Widget _harness(double scale, {Size window = const Size(800, 600)}) {
  return MediaQuery(
    data: MediaQueryData(size: window),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: window.width,
        height: window.height,
        child: PosScaledSurface(
          scale: scale,
          child: Builder(
            builder: (context) => Stack(
              children: [
                // A fixed 200x60 button: whatever scale does to this is what
                // it does to every button on the POS.
                const Positioned(
                  left: 0,
                  top: 0,
                  child: SizedBox(
                    key: ValueKey('button'),
                    width: 200,
                    height: 60,
                  ),
                ),
                // What the subtree believes its viewport is.
                Positioned(
                  left: 0,
                  top: 100,
                  child: Text(
                    'w=${MediaQuery.sizeOf(context).width.round()} '
                    'h=${MediaQuery.sizeOf(context).height.round()}',
                    key: const ValueKey('viewport'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a comfortable window paints a 200pt button at 200pt', (
    tester,
  ) async {
    const roomy = Size(1440, 900);
    tester.view.physicalSize = roomy;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(1.0, window: roomy));
    final rect = tester.getRect(find.byKey(const ValueKey('button')));
    expect(rect.width, closeTo(200, 0.01));
    expect(rect.height, closeTo(60, 0.01));
  });

  testWidgets('a roomy window paints the button at exactly the scale', (
    tester,
  ) async {
    const roomy = Size(1600, 1100);
    tester.view.physicalSize = roomy;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(0.9, window: roomy));
    final rect = tester.getRect(find.byKey(const ValueKey('button')));
    expect(rect.width, closeTo(180, 0.01));
    expect(rect.height, closeTo(54, 0.01));
  });

  testWidgets('a cramped window shrinks the button to make it fit', (
    tester,
  ) async {
    // The button is 200pt in a layout floored to [designSize] wide, painted
    // into an 800pt window. Derived rather than hardcoded so moving the floor
    // does not silently invalidate the expectation.
    await tester.pumpWidget(_harness(1.0));
    final rect = tester.getRect(find.byKey(const ValueKey('button')));
    final paint = 800 / PosScaledSurface.designSize.width;
    expect(rect.width, closeTo(200 * paint, 0.5));
  });

  testWidgets('90% hands the layout more room, not less', (tester) async {
    // This is the half people miss: shrinking the pixels is only useful if
    // the layout is also told it has more space to spend. 1440 ÷ 0.9 = 1600.
    await tester.pumpWidget(_harness(0.9));
    final reported = tester
        .widget<Text>(find.byKey(const ValueKey('viewport')))
        .data;
    // 800 ÷ 0.9 = 889, below the design floor, so the floor decides the paint
    // factor instead. The layout is then the window divided by that, which
    // paints back to exactly 800x600.
    //
    // This once read `w=1280 h=720` — the letterboxed shape, where 720 painted
    // at 0.625 is 450 and 150pt of the window went unpainted. The assertion was
    // pinning the bug in place.
    final paint = 800 / PosScaledSurface.designSize.width;
    expect(reported, 'w=${(800 / paint).round()} h=${(600 / paint).round()}');
  });

  group('the design-size floor', () {
    test('a comfortable window is laid out at its own size', () {
      final r = PosScaledSurface.resolve(const Size(1440, 900), 1.0);
      expect(r.layout, const Size(1440, 900));
      expect(r.paint, closeTo(1.0, 0.001));
    });

    test('90% spends the extra room and paints at 90%', () {
      final r = PosScaledSurface.resolve(const Size(1440, 900), 0.9);
      expect(r.layout, const Size(1600, 1000));
      expect(r.paint, closeTo(0.9, 0.001));
    });

    test('a window below the design size lays out at the design size', () {
      // This is what „everything should become small on a small resolution"
      // means: the widgets still get the room they were built for, and the
      // shortfall comes out of the pixels.
      final r = PosScaledSurface.resolve(const Size(900, 700), 1.0);
      expect(r.layout.width, PosScaledSurface.designSize.width);
      expect(r.paint, lessThan(1.0));
      // The painted result exactly fills the window on its tight axis.
      expect(r.layout.width * r.paint, closeTo(900, 0.5));
    });

    test('110% on a small window shrinks to fit rather than overflowing', () {
      // 1024 ÷ 1.1 = 931, below the floor — so it lays out at the design
      // size instead of handing the layout less room than it can survive.
      final r = PosScaledSurface.resolve(const Size(1024, 768), 1.1);
      expect(r.layout.width, PosScaledSurface.designSize.width);
      expect(r.paint, lessThan(1.0));
      expect(r.layout.width * r.paint, lessThanOrEqualTo(1024.5));
      expect(r.layout.height * r.paint, lessThanOrEqualTo(768.5));
    });

    test('the painted box fills the window exactly, on both axes', () {
      // The original assertion here was one-sided — it only checked the paint
      // never *exceeded* the window — and that is precisely how the letterbox
      // shipped. At 1024x768 the app painted 1024x614 and left a 154pt black
      // strip along the bottom, and the test was perfectly happy: 614 is
      // indeed less than 768.
      //
      // Filling is the actual requirement. Anything less is a dead band on a
      // screen that has none to spare.
      for (final window in const [
        Size(1024, 768),
        Size(1280, 720),
        Size(1366, 768),
        Size(1440, 900),
        Size(1920, 1080),
        Size(900, 700),
        Size(800, 600),
      ]) {
        for (final scale in const [0.9, 1.0, 1.1]) {
          final r = PosScaledSurface.resolve(window, scale);
          expect(
            r.layout.width * r.paint,
            closeTo(window.width, 0.5),
            reason: 'horizontal band at $window @ $scale',
          );
          expect(
            r.layout.height * r.paint,
            closeTo(window.height, 0.5),
            reason: 'vertical band at $window @ $scale',
          );
          // And never below the size every screen is verified at — on both
          // axes, not just width.
          expect(
            r.layout.width,
            greaterThanOrEqualTo(PosScaledSurface.designSize.width - 0.5),
            reason: '$window @ $scale',
          );
          expect(
            r.layout.height,
            greaterThanOrEqualTo(PosScaledSurface.designSize.height - 0.5),
            reason: '$window @ $scale',
          );
          // Never bigger than the operator asked for.
          expect(
            r.paint,
            lessThanOrEqualTo(scale + 0.001),
            reason: '$window @ $scale',
          );
        }
      }
    });

    test('a 1024x768 terminal uses its whole screen', () {
      // The reported bug, pinned to the resolution it was reported at: the
      // window was painted 1024x614 with a 154pt dead strip below it.
      final r = PosScaledSurface.resolve(const Size(1024, 768), 1.0);
      expect(r.paint, closeTo(1024 / PosScaledSurface.designSize.width, 0.001));
      expect(r.layout.width * r.paint, closeTo(1024, 0.5));
      expect(r.layout.height * r.paint, closeTo(768, 0.5));
    });
  });
}
