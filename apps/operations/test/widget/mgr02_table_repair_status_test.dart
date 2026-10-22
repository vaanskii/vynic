import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/apps/mobile_app/presentation/widgets/table_repair_status_panel.dart';
import 'package:vynic/core/services/manager_app/table_repair_request.dart';
import '../unit/mgr02_table_repair_request_test.dart' show repairResponse;

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vynic-mgr02-widget-');
    Hive.init(dir.path);
    await TableRepairRequests.submit(
      scope: 'fixture',
      number: '7',
      floor: 'first',
      send: (_) async => repairResponse('QUEUED'),
    );
  });

  Future<void> closeStore(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final closed = Completer<void>();
    Hive.close().whenComplete(closed.complete);
    for (var attempt = 0; attempt < 100 && !closed.isCompleted; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(closed.isCompleted, isTrue);
    await tester.runAsync(() => dir.delete(recursive: true));
  }

  for (final width in [320.0, 1024.0]) {
    testWidgets(
      'reopened $width screen retains pending request and refreshes same identity',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final id = TableRepairRequests.read(
          'fixture',
          '7',
          'first',
        )!['requestId'];
        final refreshed = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TableRepairStatusPanel(
                  scope: 'fixture',
                  refresh: (number, floor) => TableRepairRequests.submit(
                    scope: 'fixture',
                    number: number,
                    floor: floor,
                    refresh: true,
                    send: (body) async {
                      expect(body['requestId'], id);
                      return repairResponse('SUCCEEDED');
                    },
                  ).whenComplete(refreshed.complete),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('მოთხოვნა რიგშია — მაგიდა ჯერ არ გათავისუფლებულა'),
          findsOneWidget,
        );
        expect(find.textContaining('მოთხოვნის კოდი:'), findsOneWidget);
        await tester.tap(find.text('შედეგის განახლება'));
        for (
          var attempt = 0;
          attempt < 100 && !refreshed.isCompleted;
          attempt++
        ) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(refreshed.isCompleted, isTrue);
        await tester.pumpAndSettle();
        expect(find.text('მოთხოვნა შესრულებულია POS-ის მიერ'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeStore(tester);
      },
    );
  }
  testWidgets(
    'refresh rejection surfaces an error and preserves pending state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableRepairStatusPanel(
              scope: 'fixture',
              refresh: (_, _) async =>
                  throw StateError('synthetic changed session'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('შედეგის განახლება'));
      await tester.pumpAndSettle();
      expect(
        find.text('შედეგი ვერ გადამოწმდა — სცადეთ ხელახლა'),
        findsOneWidget,
      );
      expect(
        find.text('მოთხოვნა რიგშია — მაგიდა ჯერ არ გათავისუფლებულა'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await closeStore(tester);
    },
  );
}
