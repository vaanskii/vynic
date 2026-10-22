import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/screens/order_detail_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_move_items_dialog.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/order_transfer_journal_repository.dart';
import '../support/pos03_fixture.dart';

void main() {
  late Directory directory;
  late Pos03Fixture fixture;
  late HttpOverrides? previous;
  WidgetTester? activeTester;
  setUpAll(() async {
    final data = File('assets/fonts/NotoSansGeorgian.ttf').readAsBytesSync();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.view(data.buffer)));
    await loader.load();
  });
  setUp(() async {
    previous = HttpOverrides.current;
    directory = await Directory.systemTemp.createTemp('vynic-pos03-widget-');
    fixture = Pos03Fixture();
    await fixture.open(directory.path);
    await fixture.seed();
  });
  tearDown(() async {
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
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      OrderDetailScreen(user: pos03User, orderId: 1),
                ),
              ),
              child: const Text('Open synthetic Order'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open synthetic Order'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderDetailScreen), findsOneWidget);
    await tester.ensureVisible(find.text('პროდუქტების გადატანა'));
    // Start the screen's complete await chain in a real-I/O zone, then pump
    // route/overlay frames separately. No storage future runs on a fake clock.
    await tester.runAsync(() => tester.tap(find.text('პროდუქტების გადატანა')));
    await tester.pumpAndSettle();
    expect(find.byType(OrderMoveItemsDialog), findsOneWidget);
    await tester.tap(find.text('ყველა'));
    await tester.tap(find.text('მაგიდა 12'));
    await tester.pump();
  }

  Future<void> waitFor(WidgetTester tester, String message) async {
    for (
      var tick = 0;
      tick < 50 && find.text(message).evaluate().isEmpty;
      tick++
    ) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
    expect(
      find.text(message),
      findsOneWidget,
      reason:
          'Rendered text: ${tester.widgetList<Text>(find.byType(Text)).map((v) => v.data).toList()}; journal=${OrderTransferJournalRepository.records().map((v) => v.data['phase']).toList()}',
    );
    expect(find.byType(OrderMoveItemsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  }

  Future<void> drain(WidgetTester tester, String message) async {
    for (
      var tick = 0;
      tick < 50 && find.text(message).evaluate().isNotEmpty;
      tick++
    ) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets(
    'whole-bill UI transfer completes journal and cleanup before showing success',
    (tester) async {
      await show(tester);
      await tester.runAsync(() => tester.tap(find.text('გადატანა')));
      const message = '4 ცალი გადავიდა: მაგიდა 12 — Table 7 გათავისუფლდა';
      await waitFor(tester, message);
      fixture.verify(id: OrderTransferJournalRepository.records().single.id);
      expect(find.byType(OrderDetailScreen), findsNothing);
      await drain(tester, message);
    },
  );
  testWidgets(
    'source changed while picker is open refuses immutable selection',
    (tester) async {
      await show(tester);
      await tester.runAsync(() async {
        final source = DatabaseCore.orderBox!.get('source')!.clone();
        source.items.single.quantity = 6;
        source.items.single.total = 15.01;
        await DatabaseCore.orderBox!.put('source', source);
      });
      await tester.runAsync(() => tester.tap(find.text('გადატანა')));
      const message = 'შეკვეთა შეიცვალა — განაახლეთ გვერდი და აირჩიეთ თავიდან';
      await waitFor(tester, message);
      expect(OrderTransferJournalRepository.records(), isEmpty);
      expect(
        DatabaseCore.orderBox!.get('destination')!.items.single.quantity,
        1,
      );
      expect(DatabaseCore.orderBox!.get('source')!.items.single.quantity, 6);
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      await drain(tester, message);
    },
  );
  testWidgets(
    'storage interruption reports recovery without claiming released source',
    (tester) async {
      await show(tester);
      fixture.fault = (point, _) async {
        if (point == 'orders.put:destination:after' &&
            OrderTransferJournalRepository.records().isNotEmpty) {
          throw const FileSystemException(
            'synthetic UI destination interruption',
          );
        }
      };
      await tester.runAsync(() => tester.tap(find.text('გადატანა')));
      const message = 'გადატანა შეწყდა — გადატვირთეთ პროგრამა აღდგენისათვის';
      await waitFor(tester, message);
      expect(OrderTransferJournalRepository.records().single.pending, true);
      expect(
        LocalDataAdmission.failure,
        contains('Order transfer recovery required'),
      );
      expect(DatabaseCore.tableBox!.get('source-table')!.activeOrderId, 1);
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      await drain(tester, message);
    },
  );
}
