import 'package:flutter/material.dart';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/widgets/connection_feedback.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

void main() {
  testWidgets('retained Manager token on PIN screen is not a server outage', (
    tester,
  ) async {
    final dir = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp(
        'manager-login-feedback-',
      );
      Hive.init(dir.path);
      await AuthTokenService.init();
      await AuthTokenService.saveToken(
        token: 'synthetic-retained-token',
        role: 'MANAGER',
        username: 'fixture',
        expiresInSeconds: 3600,
      );
      return dir;
    });
    MonitoringSocketService.dispose();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionFeedback.manager(
            child: const Scaffold(body: Text('PIN')),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('სერვერთან კავშირი დაკარგულია'), findsNothing);
      // Once an authenticated monitoring session exists, a real outage still reports.
      MonitoringSocketService.isSessionActive.value = true;
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('სერვერთან კავშირი დაკარგულია'), findsOneWidget);
      MonitoringSocketService.dispose();
      await tester.pump();
      expect(find.text('სერვერთან კავშირი დაკარგულია'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await AuthTokenService.clearToken();
        await Hive.close();
        await dir!.delete(recursive: true);
      });
    }
  });
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets('connection transitions are transient at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final signal = ValueNotifier<bool?>(null);
      addTearDown(signal.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ConnectionFeedback(
            signals: signal,
            readConnected: () => signal.value,
            child: child!,
          ),
          home: const Scaffold(body: Text('Application')),
        ),
      );
      signal.value = true;
      await tester.pump();
      expect(find.text('კავშირი აღდგა'), findsNothing);
      // Normal sync attempts stay silent.
      signal.value = null;
      signal.value = true;
      await tester.pump();
      expect(find.byType(Material), findsOneWidget);
      signal.value = false;
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('სერვერთან კავშირი დაკარგულია'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('სერვერთან კავშირი დაკარგულია'), findsNothing);
      // Failed retries do not repeat the outage or announce restoration.
      signal.value = null;
      signal.value = false;
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('სერვერთან კავშირი დაკარგულია'), findsNothing);
      signal.value = true;
      await tester.pump();
      expect(find.text('კავშირი აღდგა'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('კავშირი აღდგა'), findsNothing);
      // A genuinely new outage can notify again.
      signal.value = false;
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('სერვერთან კავშირი დაკარგულია'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('initial offline, brief reconnect and background handling', (
    tester,
  ) async {
    final signal = ValueNotifier<bool?>(false);
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionFeedback(
          signals: signal,
          readConnected: () => signal.value,
          child: const Scaffold(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('სერვერთან კავშირი დაკარგულია'), findsOneWidget);
    signal.value = true;
    await tester.pump(const Duration(seconds: 4));
    signal.value = false;
    await tester.pump(const Duration(seconds: 1));
    signal.value = true;
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('სერვერთან კავშირი დაკარგულია'), findsNothing);
    expect(find.text('კავშირი აღდგა'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    signal.value = false;
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('სერვერთან კავშირი დაკარგულია'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    signal.value = true;
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('კავშირი აღდგა'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled session suppresses notifications and clears outage', (
    tester,
  ) async {
    final signal = ValueNotifier<bool?>(false);
    addTearDown(signal.dispose);
    var enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionFeedback(
          signals: signal,
          readConnected: () => signal.value,
          enabled: () => enabled,
          child: const Scaffold(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('სერვერთან კავშირი დაკარგულია'), findsNothing);
    enabled = true;
    signal.value = true;
    signal.value = false;
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('სერვერთან კავშირი დაკარგულია'), findsOneWidget);
    enabled = false;
    signal.value = null;
    await tester.pump();
    expect(find.text('სერვერთან კავშირი დაკარგულია'), findsNothing);
    enabled = true;
    signal.value = true;
    await tester.pump();
    expect(find.text('კავშირი აღდგა'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
