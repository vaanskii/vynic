import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/widgets/connection_feedback.dart';

void main() {
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
