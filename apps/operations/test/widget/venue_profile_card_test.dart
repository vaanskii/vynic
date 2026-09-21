import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/venue_profile_card.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';

void main() {
  tearDown(ManagerEntitlements.clear);
  for (final width in [390.0, 1280.0]) {
    testWidgets('profile updates and validates at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ManagerEntitlements.profile.value = {
        'name': 'რესტორანი',
        'branchName': 'ვაკე',
        'address': 'თბილისი, ჭავჭავაძის გამზირი 12',
      };
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: VenueProfileCard()),
          ),
        ),
      );
      expect(find.text('ფილიალის სახელი: ვაკე'), findsOneWidget);
      ManagerEntitlements.profile.value = {
        'name': 'რესტორანი',
        'branchName': 'დიდუბე',
      };
      await tester.pump();
      expect(find.text('ფილიალის სახელი: ვაკე'), findsNothing);
      expect(find.text('ფილიალის სახელი: დიდუბე'), findsOneWidget);
      await tester.tap(find.text('პროფილის შეცვლა'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '  ');
      await tester.tap(find.text('შენახვა'));
      await tester.pump();
      expect(find.text('შეიყვანეთ სახელი'), findsOneWidget);
      expect(find.text('მთავარი ფილიალი'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('გაუქმება'));
      await tester.pumpAndSettle();
    });
  }
}
