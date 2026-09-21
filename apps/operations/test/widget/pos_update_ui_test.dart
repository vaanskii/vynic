import 'dart:async';
import 'package:vynic/core/services/pos/table_payment_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/update/pos_update_ui.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';

void main() {
  testWidgets(
    'Go probation stays in the background while update controls remain usable',
    (tester) async {
      var opened = false;
      final u = PosUpdater()..probation = true;
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          builder: (_, child) =>
              PosUpdateHost(updater: u, navigatorKey: key, child: child!),
          home: Scaffold(
            body: TextButton(
              onPressed: () => opened = true,
              child: const Text('პროგრამის განახლება'),
            ),
          ),
        ),
      );
      expect(find.text('მოწმდება POS-ის სტაბილურობა'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('პროგრამის განახლება'));
      expect(opened, isTrue);
      expect(u.inputHeld, isTrue); // Login admission remains closed.
      await tester.pumpWidget(const SizedBox());
      u.dispose();
    },
  );

  testWidgets(
    'Settings shows download percent and bytes, and checks show a loader',
    (tester) async {
      final response = Completer<Map<String, dynamic>>();
      var checks = 0;
      final u =
          PosUpdater(
              requestOverride: (route, _) async {
                if (route == 'check') {
                  checks++;
                  return response.future;
                }
                return {'status': 'UP_TO_DATE'};
              },
            )
            ..configured = true
            ..state = {
              'status': 'DOWNLOADING',
              'downloaded': 5242880,
              'total': 10485760,
            };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PosUpdateSettings(updater: u)),
        ),
      );
      expect(find.text('50% · 5.0 / 10.0 MB'), findsOneWidget);
      u.state = {'status': 'UP_TO_DATE'};
      u.notifyListeners();
      await tester.pump();
      await tester.tap(find.text('შემოწმება'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('მოწმდება…'), findsOneWidget);
      await u.check();
      expect(checks, 1);
      response.complete({});
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      u.dispose();
    },
  );

  testWidgets(
    'startup failure replaces spinner and keeps business input blocked',
    (tester) async {
      var edits = 0;
      final u = PosUpdater()
        ..probation = true
        ..startupFailure = 'POS startup health timeout';
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          builder: (context, child) =>
              PosUpdateHost(updater: u, navigatorKey: key, child: child!),
          home: Scaffold(
            body: TextButton(
              onPressed: () => edits++,
              child: const Text('Edit order'),
            ),
          ),
        ),
      );
      expect(find.text('POS startup health timeout'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('ხელახლა შემოწმება'), findsOneWidget);
      await tester.tap(find.text('Edit order'), warnIfMissed: false);
      expect(edits, 0);
      await tester.pumpWidget(const SizedBox());
      u.dispose();
    },
  );

  testWidgets('real payment collection blocks Update Now until cancellation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    UpdateReadiness.enabled = true;
    UpdateReadiness.startupReady = true;
    UpdateReadiness.frozen = false;
    UpdateReadiness.failure = null;
    UpdateReadiness.recoveryChecks.clear();
    late BuildContext posContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            posContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final payment = TablePaymentService(
      context: posContext,
      total: 10,
    ).collect();
    // The real collect() Future is now waiting for user input. This test
    // exercises operation admission, not the existing payment tile layout.
    expect(UpdateReadiness.evaluate().status, 'BLOCKED');
    var requests = 0;
    final updater = PosUpdater(
      dataDirectory: "/isolated/ui-proof",
      requestOverride: (route, body) async {
        requests++;
        return {};
      },
      flushOverride: () async {},
    );
    await updater.installNow();
    expect(requests, 0);
    Navigator.of(posContext).pop();
    await payment;
    await tester.pumpAndSettle();
    expect(UpdateReadiness.evaluate().status, 'READY');
    updater.dispose();
    UpdateReadiness.enabled = false;
  });

  testWidgets('Later dismisses prompt; Settings keeps explicit Update Now', (
    tester,
  ) async {
    UpdateReadiness.startupReady = true;
    UpdateReadiness.frozen = false;
    UpdateReadiness.failure = null;
    UpdateReadiness.recoveryChecks.clear();
    var installs = 0;
    final u = PosUpdater(
      dataDirectory: "/isolated/ui-proof",
      requestOverride: (route, body) async {
        if (route == 'install') installs++;
        return {'status': 'INSTALLING'};
      },
      flushOverride: () async {},
    )..configured = true;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        builder: (context, child) =>
            PosUpdateHost(updater: u, navigatorKey: key, child: child!),
        home: Scaffold(body: PosUpdateSettings(updater: u)),
      ),
    );
    u.state = {'status': 'READY_TO_INSTALL', 'version': '1.9.0'};
    u.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('მოგვიანებით'), findsOneWidget);
    expect(find.text('1.9.0'), findsNWidgets(2));
    await tester.tap(find.text('მოგვიანებით'));
    await tester.pumpAndSettle();
    expect(installs, 0);
    expect(u.status, 'READY_TO_INSTALL');
    expect(find.text('პროგრამის განახლება'), findsOneWidget);
    expect(find.text('განახლება ახლა'), findsOneWidget);
    await tester.tap(find.text('განახლება ახლა'));
    await tester.pump();
    expect(installs, 1);
    await tester.pumpWidget(const SizedBox());
    u.dispose();
    UpdateReadiness.frozen = false;
  });
}
