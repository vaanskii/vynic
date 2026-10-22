import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/apps/windows_pos/screens/home_screen.dart';
import 'package:vynic/apps/windows_pos/screens/order_detail_screen.dart';
import 'package:vynic/apps/windows_pos/widgets/order/order_detail_content_section.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/auth/session_lock.dart';
import 'package:vynic/core/services/pos/update/tracked_box.dart';
import 'package:vynic/core/utils/table_naming.dart';
import '../support/pos03_fixture.dart' show pos03User;
import '../support/pos05_fixture.dart';

void main() {
  Future<void> advance(WidgetTester tester, [int count = 10]) async {
    for (var n = 0; n < count; n++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
  }

  late Directory root;
  late Pos05Fixture fixture;
  WidgetTester? active;
  late HttpOverrides? prior;
  setUpAll(() async {
    final bytes = File('assets/fonts/NotoSansGeorgian.ttf').readAsBytesSync();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
  });
  setUp(() async {
    prior = HttpOverrides.current;
    root = await Directory.systemTemp.createTemp('vynic-pos05-widget-');
    fixture = Pos05Fixture();
    await fixture.open(root.path);
    await fixture.prepare('move');
    for (final number in ['8', '9'])
      await DatabaseCore.tableBox!.put(
        'free-$number',
        TableModel(tableNumber: number, floor: 'first'),
      );
    await DatabaseCore.packageBox!.put(
      'package-id',
      Package(
        packageId: 'package-id',
        name: 'Package snapshot',
        pricePerPerson: 7.11,
        servingSize: 1,
        createdAt: DateTime(2026, 9, 30),
        createdBy: 'synthetic',
        items: [
          PackageItem(
            itemKey: 'package',
            itemName: 'Fixed package',
            quantity: 1,
            unitPrice: 8,
            menuItemId: 'package-menu',
            variantId: 'package-variant',
          ),
        ],
      ),
    );
  });
  tearDown(() async {
    SessionLock.disarm();
    await active!.runAsync(() async {
      await fixture.close();
      HttpOverrides.global = prior;
      await root.delete(recursive: true);
    });
    active = null;
  });
  Future<void> show(WidgetTester tester, Widget screen) async {
    active = tester;
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => tester.pumpWidget(MaterialApp(home: screen)));
    await advance(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).first);
    await tester.runAsync(() => tester.tap(find.text(label).first));
    await advance(tester, 3);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> message(WidgetTester tester, String value) async {
    for (var n = 0; n < 80 && find.text(value).evaluate().isEmpty; n++)
      await advance(tester, 1);
    expect(
      find.text(value),
      findsOneWidget,
      reason:
          'Rendered: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
    );
    expect(tester.takeException(), isNull);
  }

  Future<void> finish(WidgetTester tester) async {
    // Animation frames and real timers must both advance before unmounting.
    await advance(tester, 120);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    SessionLock.disarm();
  }

  OrderDetailScreen detail() => OrderDetailScreen(user: pos03User, orderId: 1);
  const stale = 'შეკვეთა შეიცვალა — განაახლეთ და გაიმეორეთ მოქმედება';
  void proofWidget(String name, Future<void> Function(WidgetTester) action) {
    testWidgets(name, (tester) async {
      active = tester;
      try {
        await action(tester);
      } finally {
        await finish(tester);
      }
    });
  }

  proofWidget(
    'two mounted Order views remain readable and both refresh after a fresh external edit',
    (tester) async {
      var selected = 0;
      await show(
        tester,
        StatefulBuilder(
          builder: (context, setView) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => setView(() => selected = 1 - selected),
                  child: const Text('Switch synthetic view'),
                ),
                Expanded(
                  child: IndexedStack(
                    index: selected,
                    children: [
                      OrderDetailScreen(
                        key: const ValueKey('view-one'),
                        user: pos03User,
                        orderId: 1,
                      ),
                      OrderDetailScreen(
                        key: const ValueKey('view-two'),
                        user: pos03User,
                        orderId: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.byType(OrderDetailScreen, skipOffstage: false),
        findsNWidgets(2),
      );
      await tester.runAsync(() async {
        final fresh = OrderRepository.getOrder(1)!;
        fresh.items.single.quantity = 6;
        fresh.items.single.total = 15.01;
        await OrderRepository.updateOrder(fresh);
        await OrderRepository.createOrder(
          tableNumbers: ['8'],
          floor: 'first',
          createdBy: 'other',
          items: [],
        );
      });
      await advance(tester);
      await tester.pumpAndSettle();
      final sections = tester
          .widgetList<OrderDetailContentSection>(
            find.byType(OrderDetailContentSection, skipOffstage: false),
          )
          .toList();
      expect(sections, hasLength(2));
      expect(sections.every((s) => s.order.items.single.quantity == 6), true);
      expect(find.text('6'), findsWidgets);
      await tap(tester, 'Switch synthetic view');
      expect(find.text('6'), findsWidgets);
      expect(LocalDataAdmission.failure, isNull);
      expect(OrderTableMutationRepository.integrityReport(), isEmpty);
      await finish(tester);
    },
  );

  proofWidget(
    'table picker allows another writer and clearly refuses occupied target, then permits fresh retry',
    (tester) async {
      await show(tester, detail());
      await tap(tester, 'მაგიდის შეცვლა');
      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          TableNaming.table(tableNumber: '8', floor: 'first'),
        ),
      );
      await tester.pump();
      final other = (await tester.runAsync(
        () => OrderRepository.createOrder(
          tableNumbers: ['8'],
          floor: 'first',
          createdBy: 'other',
          items: [],
        ),
      ))!;
      final source = OrderTableMutationRepository.image(
        OrderRepository.getOrder(1)!,
      );
      final audit = AuditRepository.getAuditReport(1)!.toMap();
      await tap(tester, 'შეცვლა');
      await message(tester, 'მაგიდა უკვე დაკავებულია — განაახლეთ შეკვეთა');
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(
        OrderTableMutationRepository.image(OrderRepository.getOrder(1)!),
        source,
      );
      expect(AuditRepository.getAuditReport(1)!.toMap(), audit);
      expect(
        DatabaseCore.tableBox!.get('free-8')!.activeOrderId,
        other.orderId,
      );
      await tap(tester, 'მაგიდის შეცვლა');
      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          TableNaming.table(tableNumber: '9', floor: 'first'),
        ),
      );
      await tester.pump();
      await tap(tester, 'შეცვლა');
      await message(tester, 'მაგიდა შეიცვალა: 9');
      expect(OrderRepository.getOrder(1)!.tableNumbers, ['9']);
      expect(OrderTableMutationRepository.integrityReport(), isEmpty);
      await finish(tester);
    },
  );
  proofWidget(
    'payment confirmation admits concurrent edit and refuses stale money before Sale or closure intent',
    (tester) async {
      await show(tester, detail());
      await tap(tester, 'მაგიდის დახურვა');
      await tap(tester, 'ნაღდი ფული');
      expect(find.textContaining('ნამდვილად გსურთ დახურვა'), findsOneWidget);
      await tester.runAsync(() async {
        final edited = OrderRepository.getOrder(1)!;
        edited.items.single.quantity = 6;
        edited.items.single.total = 15.01;
        await OrderRepository.updateOrder(edited);
      });
      final committed = OrderTableMutationRepository.image(
        OrderRepository.getOrder(1)!,
      );
      await tap(tester, 'დახურვა');
      await message(tester, stale);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(
        OrderTableMutationRepository.image(OrderRepository.getOrder(1)!),
        committed,
      );
      expect(
        DatabaseCore.salesBox!.values.whereType<Map>().where(
          (s) => s['orderId'] == 1,
        ),
        isEmpty,
      );
      expect(DatabaseCore.closureJournalBox!.isEmpty, true);
      expect(OrderRepository.getOrder(1)!.closureId, isNull);
      expect(DatabaseCore.tableBox!.get('source-table')!.activeOrderId, 1);
      await finish(tester);
    },
  );
  proofWidget(
    'package dialog freezes its inputs, refuses stale Order and calls visible refresh',
    (tester) async {
      var refreshed = 0;
      await show(
        tester,
        Scaffold(
          body: OrderDetailContentSection(
            order: OrderRepository.getOrder(1)!,
            canModify: true,
            isAdmin: true,
            onOrderUpdated: () async {
              refreshed++;
            },
          ),
        ),
      );
      await tap(tester, 'პაკეტის კორექტირება');
      await tester.enterText(find.byType(TextField).first, '3');
      await tester.pump();
      await tester.runAsync(() async {
        final edited = OrderRepository.getOrder(1)!;
        edited.items.single.quantity = 6;
        edited.items.single.total = 15.01;
        await OrderRepository.updateOrder(edited);
        final definition = DatabaseCore.packageBox!.get('package-id')!;
        definition.pricePerPerson = 999;
        await definition.save();
      });
      final committed = OrderTableMutationRepository.image(
        OrderRepository.getOrder(1)!,
      );
      await tap(tester, 'შენახვა');
      await message(tester, stale);
      expect(find.byType(Dialog), findsNothing);
      expect(refreshed, 1);
      expect(
        OrderTableMutationRepository.image(OrderRepository.getOrder(1)!),
        committed,
      );
      expect(OrderRepository.getOrder(1)!.packageGuestCount, 1);
      await finish(tester);
    },
  );
  proofWidget(
    'reserved-table fault surfaces recovery even when tracked error logging is denied',
    (tester) async {
      await tester.runAsync(() async {
        await fixture.prepare('activation');
        final booking = DatabaseCore.reservationBox!.get('booking')!;
        booking.reservationDate = DateTime(2026, 10, 2);
        await DatabaseCore.reservationBox!.put('booking', booking);
        DatabaseCore.errorLogBox = UpdateTrackedBox(DatabaseCore.errorLogBox!);
      });
      await show(tester, HomeScreen(user: pos03User));
      fixture.fault = (point, _) async {
        if (point.startsWith('orders.put:') &&
            point.endsWith(':after') &&
            OrderTableMutationRepository.records().any((r) => r.pending)) {
          throw const FileSystemException('synthetic activation interruption');
        }
      };
      await tap(tester, TableNaming.table(tableNumber: '7', floor: 'first'));
      await message(tester, 'ოპერაცია აღსადგენია — გადატვირთეთ POS');
      expect(find.byType(OrderDetailScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(OrderTableMutationRepository.records().single.pending, true);
      expect(LocalDataAdmission.failure, contains('Order/table recovery'));
      expect(DatabaseCore.errorLogBox!.isEmpty, true);
      await finish(tester);
    },
  );
  proofWidget(
    'legacy ownership report preserves readable Home and refuses mutation without repair',
    (tester) async {
      final duplicate = OrderRepository.getOrder(1)!.clone()
        ..orderId = 3
        ..orderUuid = 'synthetic-duplicate';
      await tester.runAsync(
        () => DatabaseCore.orderBox!.put('duplicate', duplicate),
      );
      final before = fixture.persisted();
      await show(tester, HomeScreen(user: pos03User));
      expect(
        find.byKey(const ValueKey('order-table-repair-report')),
        findsOneWidget,
      );
      expect(
        find.textContaining('ჩანაწერების ნახვა ხელმისაწვდომია'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        await expectLater(
          OrderRepository.createOrder(
            tableNumbers: ['7'],
            floor: 'first',
            createdBy: 'synthetic',
            items: [],
          ),
          throwsA(isA<OrderMutationConflict>()),
        );
      });
      expect(fixture.persisted(), before);
      expect(LocalDataAdmission.failure, isNull);
      await finish(tester);
    },
  );
  proofWidget(
    'fee normalization holds only a short mutation and concurrent stale edit cannot overwrite its view',
    (tester) async {
      final stored = DatabaseCore.orderBox!.get('source')!
        ..includeServiceFee = true;
      await tester.runAsync(() => DatabaseCore.orderBox!.put('source', stored));
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.fault = (point, _) async {
        if (point == 'orders.put:source:before') {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
      };
      active = tester;
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(
        () => tester.pumpWidget(MaterialApp(home: detail())),
      );
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 3)),
      );
      final staleOrder = OrderRepository.getOrder(1)!;
      staleOrder.items.single.quantity = 9;
      staleOrder.items.single.total = 22.51;
      final queued = tester.runAsync(() async {
        try {
          await OrderRepository.updateOrder(staleOrder);
          return null;
        } catch (e) {
          return e;
        }
      });
      release.complete();
      fixture.fault = null;
      expect(await queued, isA<OrderMutationConflict>());
      await advance(tester);
      await tester.pumpAndSettle();
      expect(OrderRepository.getOrder(1)!.includeServiceFee, false);
      expect(OrderRepository.getOrder(1)!.items.single.quantity, 4);
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.text('Order not found'), findsNothing);
      await tester.runAsync(() async {
        final fresh = OrderRepository.getOrder(1)!;
        fresh.items.single.quantity = 6;
        fresh.items.single.total = 15.01;
        await OrderRepository.updateOrder(fresh);
      });
      await advance(tester);
      expect(OrderRepository.getOrder(1)!.items.single.quantity, 6);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
}
