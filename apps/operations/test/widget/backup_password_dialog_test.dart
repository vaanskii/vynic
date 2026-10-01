import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/backup_password_dialog.dart';

void main() {
  testWidgets('export requires long matching passwords and explains key loss', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: BackupPasswordDialog(creating: true)),
    );
    expect(find.textContaining('PIN'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('backup-password')))
          .obscureText,
      true,
    );
    await tester.enterText(find.byKey(const Key('backup-password')), 'short');
    await tester.tap(find.byKey(const Key('backup-password-submit')));
    await tester.pump();
    expect(find.textContaining('12 სიმბოლოს'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'synthetic-strong-password',
    );
    await tester.enterText(
      find.byKey(const Key('backup-password-confirm')),
      'different-password',
    );
    await tester.tap(find.byKey(const Key('backup-password-submit')));
    await tester.pump();
    expect(find.text('პაროლები არ ემთხვევა.'), findsOneWidget);
  });
  testWidgets(
    'restore accepts the existing password without export confirmation',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await BackupPasswordDialog.show(
                  context,
                  creating: false,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backup-password-confirm')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('backup-password')),
        'original-password',
      );
      await tester.tap(find.byKey(const Key('backup-password-submit')));
      await tester.pumpAndSettle();
      expect(result, 'original-password');
    },
  );
}
