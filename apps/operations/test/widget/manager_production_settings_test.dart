import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/mobile_app/presentation/screens/mobile_admin_screen.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/services/sync/api_config.dart';

void main() {
  testWidgets('production Manager settings have no endpoint editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MobileAdminScreen(
          user: User(username: 'manager', pinCode: '', role: StaffRole.manager),
          onLogout: () {},
        ),
      ),
    );
    await tester.tap(find.text('პარამეტრები'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(
      find.text('კავშირი'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('კავშირი'), findsOneWidget);
    if (!ApiConfig.allowDeveloperOverride) {
      expect(find.text('Backend'), findsNothing);
      expect(find.textContaining('http'), findsNothing);
      expect(find.textContaining('localhost'), findsNothing);
      expect(find.textContaining('127.0.0.1'), findsNothing);
      expect(find.textContaining('API'), findsNothing);
    } else {
      expect(find.text('Backend'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 15));
  });
}
