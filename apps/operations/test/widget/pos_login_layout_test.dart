import '../support/pos_visual_capture.dart';
import 'package:vynic/core/ui/pos_theme.dart';
import 'package:vynic/core/ui/pos_scaled_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/login/login_desktop_view.dart';

void main() {
  setUpAll(loadPosVisualFonts);
  testWidgets('production login visual at 1024', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pin = ValueNotifier('');
    addTearDown(pin.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: PosTheme.light,
        debugShowCheckedModeBanner: false,
        builder: (_, child) => RepaintBoundary(
          key: posVisualKey,
          child: PosScaledSurface(scale: 1, child: child!),
        ),
        home: Scaffold(
          body: LoginDesktopView(
            pin: pin,
            isLoading: false,
            workDate: DateTime(2026, 10, 15),
            now: DateTime(2026, 10, 15, 18),
            version: '1.0.8',
            onDigitPressed: (_) {},
            onClearPressed: () {},
            onDeletePressed: () {},
            onLoginPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capturePosVisual(tester, 'login-1024x768');
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 800.0, 1024.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('Login version and right-aligned date at $width / $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pin = ValueNotifier('');
        addTearDown(pin.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: LoginDesktopView(
                pin: pin,
                isLoading: false,
                workDate: DateTime(2026, 9, 21),
                now: DateTime(2026, 9, 21, 12),
                version: '1.0.8',
                onDigitPressed: (_) {},
                onClearPressed: () {},
                onDeletePressed: () {},
                onLoginPressed: () {},
              ),
            ),
          ),
        );
        expect(find.text('პროგრამის განახლება'), findsNothing);
        expect(find.text('ვერსია 1.0.8'), findsOneWidget);
        final date = find.byKey(const ValueKey('pos-work-date'));
        expect(date, findsOneWidget);
        expect(tester.widget<Text>(date).textAlign, TextAlign.right);
        expect(tester.getRect(date).right, closeTo(width - 20, 1));
        expect(
          tester.getRect(find.byKey(const ValueKey('pos-current-time'))).right,
          closeTo(width - 20, 1),
        );
        // Flutter reports uncaught layout exceptions at test completion.
      });
    }
  }
}
