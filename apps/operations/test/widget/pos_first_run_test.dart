import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/screens/pos_first_run.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';

void main() {
  testWidgets(
    'enrolled POS waits for its Manager instead of an empty PIN login',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('pos-first-run'),
      ))!;
      EdgeDeviceCredentialStore.resetForTest();
      EdgeDeviceCredentialStore.directoryOverride = directory.path;
      await tester.runAsync(() async {
        expect(
          await EdgeDeviceCredentialStore.saveEnrollment(
            rawCredential:
                'vynic-device-v1.00000000-0000-4000-8000-000000000001.test-only-secret-00000000000000000000',
            venueId: 'test-venue',
            venueName: 'Test venue',
          ),
          isTrue,
        );
      });
      await tester.pumpWidget(const MaterialApp(home: PosFirstRun()));
      expect(
        find.textContaining('მენეჯერის წვდომის მიღების მოლოდინში'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      EdgeDeviceCredentialStore.resetForTest();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
  for (final size in [const Size(1024, 768), const Size(1440, 900)]) {
    testWidgets('POS code entry stays usable at $size', (tester) async {
      EdgeDeviceCredentialStore.resetForTest();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: PosFirstRun()));
      expect(find.text('Vynic POS'), findsOneWidget);
      final code = find.widgetWithText(TextField, 'მოწყობილობის კოდი');
      await tester.enterText(code, 'ABCD-EFGH-IJKL');
      await tester.ensureVisible(find.text('მოწყობილობის დაკავშირება'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
