import 'dart:async';
import 'package:vynic/apps/windows_pos/widgets/login/login_desktop_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/pos_quit_action.dart';
import 'package:vynic/core/services/pos/pos_quit.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';

void main() {
  testWidgets('Windows login exposes the shared confirmed Quit before sign-in', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pin = ValueNotifier('');
    addTearDown(pin.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LoginDesktopView(
      pin: pin, isLoading: false, workDate: DateTime(2026), now: DateTime(2026),
      onDigitPressed: (_) {}, onClearPressed: () {}, onDeletePressed: () {},
      onLoginPressed: () {}, showQuitAction: true,
    ))));
    await tester.tap(find.text('აპლიკაციიდან გასვლა'));
    await tester.pumpAndSettle();
    expect(find.text('ნამდვილად გსურთ Vynic POS-ის დახურვა?'), findsOneWidget);
    await tester.tap(find.text('გაუქმება'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'Settings exposes Windows-only Quit and cancellation keeps POS open',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PosQuitAction())),
      );
      await tester.tap(find.text('აპლიკაციიდან გასვლა'));
      await tester.pumpAndSettle();
      expect(
        find.text('ნამდვილად გსურთ Vynic POS-ის დახურვა?'),
        findsOneWidget,
      );
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PosQuitAction(key: ValueKey('mac'))),
        ),
      );
      expect(find.text('აპლიკაციიდან გასვლა'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Quit requires confirmation; cancellation never stops services; cleanup shows progress',
    (tester) async {
      UpdateReadiness.enabled = true;
      UpdateReadiness.startupReady = true;
      UpdateReadiness.frozen = false;
      UpdateReadiness.failure = null;
      final updater = PosUpdater();
      final finish = Completer<void>();
      var stops = 0;
      bool? result;
      final quit = PosQuit(
        updater: updater,
        stopServices: () async {
          stops++;
          await finish.future;
        },
        flushAndClose: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await confirmPosQuit(context, quit: quit);
                },
                child: const Text('Quit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Quit'));
      await tester.pumpAndSettle();
      expect(
        find.text('ნამდვილად გსურთ Vynic POS-ის დახურვა?'),
        findsOneWidget,
      );
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(stops, 0);
      await tester.tap(find.text('Quit'));
      await tester.pumpAndSettle();
      updater.installing = true;
      await tester.tap(find.text('გასვლა'));
      await tester.pumpAndSettle();
      expect(find.textContaining('განახლება მიმდინარეობს'), findsOneWidget);
      expect(stops, 0);
      updater.installing = false;
      await tester.tap(find.text('გასვლა'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'გასვლა'))
            .onPressed,
        isNull,
      );
      finish.complete();
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(stops, 1);
      updater.dispose();
      UpdateReadiness.enabled = false;
      UpdateReadiness.frozen = false;
    },
  );
}
