import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_login_screen.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(1024, 900)]) {
    testWidgets('restaurant entry and keypad remain usable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: MobileLoginScreen()));
      final field = find.byKey(const Key('manager-venue-code'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'venue-b');
      await tester.pump();
      expect(find.text('venue-b'), findsOneWidget);
      expect(find.text('რესტორანი'), findsOneWidget);
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('1'));
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.ensureVisible(find.text('შესვლა'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
