import 'package:vynic/core/services/pos/table_payment_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/update/pos_update_ui.dart';
import 'package:vynic/core/services/pos/update/pos_updater.dart';
import 'package:vynic/core/services/pos/update/update_readiness.dart';

void main() {
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
