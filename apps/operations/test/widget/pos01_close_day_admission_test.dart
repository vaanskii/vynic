import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_close_day_section.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/close_day_journal_repository.dart';
import 'package:vynic/core/models/user.dart';
import '../support/pos01_fixture.dart';

void main() {
  late Directory directory;
  late Pos01Fixture fixture;
  late HttpOverrides? previous;
  WidgetTester? activeTester;
  setUp(() async {
    previous = HttpOverrides.current;
    directory = await Directory.systemTemp.createTemp('vynic-pos01-widget-');
    fixture = Pos01Fixture();
    await fixture.open(directory.path);
    await fixture.seed();
    await DatabaseCore.reservationBox!.clear();
  });
  tearDown(() async {
    // Native Hive close/delete need real I/O outside the widget fake clock.
    await activeTester!.runAsync(() async {
      await fixture.close();
      HttpOverrides.global = previous;
      await directory.delete(recursive: true);
    });
    activeTester = null;
  });
  Future<void> show(WidgetTester tester) async {
    activeTester = tester;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansGeorgian'),
        home: Scaffold(
          body: AdminCloseDaySection(
            user: User(username: 'operator', pinCode: '1234', role: 'manager'),
            onShowBusinessDateSelector: () async {},
            formatDateTimeDisplay: (date) => date.toIso8601String(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'დღის დახურვა'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  }

  Future<void> advanceUntil(WidgetTester tester, String text) async {
    for (
      var tick = 0;
      tick < 40 && find.text(text).evaluate().isEmpty;
      tick++
    ) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
  }

  Future<void> dismissToast(WidgetTester tester, String text) async {
    // Overlay animation frames use the widget clock; the admitted native
    // operation's continuation can schedule its toast timer in the real zone.
    // Yield both clocks until the normal toast dismissal finishes.
    for (
      var tick = 0;
      tick < 50 && find.text(text).evaluate().isNotEmpty;
      tick++
    ) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text(text), findsNothing);
  }

  testWidgets(
    'storage interruption displays restart/recovery reason and exits loading',
    (tester) async {
      fixture.fault = (point, _) async {
        if (point == 'settings.put:currentDate:after')
          throw const FileSystemException('synthetic UI interruption');
      };
      await show(tester);
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(ElevatedButton, 'დახურვა')),
      );
      const message = 'დღის დახურვა შეწყდა; გადატვირთეთ პროგრამა აღდგენისათვის';
      await advanceUntil(tester, message);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.text('დახურვა მიმდინარეობს...'), findsNothing);
      expect(LocalDataAdmission.failure, contains('Close Day'));
      expect(CloseDayJournalRepository.read()!.pending, true);
      expect(tester.takeException(), isNull);
      await dismissToast(tester, message);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a confirmation for yesterday cannot close a newly selected date',
    (tester) async {
      await show(tester);
      // Another admitted date action finishes while this confirmation is open.
      await tester.runAsync(
        () => DatabaseCore.settingsBox!.put(
          'currentDate',
          '2026-10-02T00:00:00.000',
        ),
      );
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(ElevatedButton, 'დახურვა')),
      );
      const message = 'სამუშაო დღე უკვე შეიცვალა; განაახლეთ მონაცემები';
      await advanceUntil(tester, message);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(CloseDayJournalRepository.read(), isNull);
      expect(
        DatabaseCore.settingsBox!.get('currentDate'),
        '2026-10-02T00:00:00.000',
      );
      expect(DatabaseCore.settingsBox!.get('dailySalesTotal'), 70.0);
      expect(tester.takeException(), isNull);
      await dismissToast(tester, message);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
