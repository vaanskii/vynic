import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/apps/windows_pos/screens/menu_screen.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_context.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/pos/menu_service.dart';

late Directory _tempDir;

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(UserAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(TableModelAdapter());
  }
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(OrderItemAdapter());
  }
  if (!Hive.isAdapterRegistered(4)) {
    Hive.registerAdapter(OrderAdapter());
  }
  if (!Hive.isAdapterRegistered(5)) {
    Hive.registerAdapter(MenuCategoryDBAdapter());
  }
  if (!Hive.isAdapterRegistered(6)) {
    Hive.registerAdapter(MenuSubcategoryDBAdapter());
  }
  if (!Hive.isAdapterRegistered(7)) {
    Hive.registerAdapter(MenuItemDBAdapter());
  }
  if (!Hive.isAdapterRegistered(8)) {
    Hive.registerAdapter(MenuVariantDBAdapter());
  }
  if (!Hive.isAdapterRegistered(9)) {
    Hive.registerAdapter(ReservationAdapter());
  }
}

MenuItemDB _item(String ka, double? price) => MenuItemDB(
  translationsEn: {'name': ka},
  translationsKa: {'name': ka},
  price: price,
);

final _user = User(username: 'giorgi', pinCode: '0000', role: 'manager');

Future<void> _seed() async {
  DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('ms_menu');
  DatabaseCore.orderBox = await Hive.openBox<Order>('ms_orders');
  DatabaseCore.settingsBox = await Hive.openBox('ms_settings');
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('ms_tables');

  await DatabaseCore.settingsBox!.put('serviceFeeEnabled', true);
  await DatabaseCore.settingsBox!.put('serviceFeePercentage', 10.0);
  await DatabaseCore.settingsBox!.put('defaultIncludeServiceFee', true);

  await DatabaseCore.menuBox!.add(
    MenuCategoryDB(
      slug: 'hot',
      translationsEn: {'name': 'Hot dishes'},
      translationsKa: {'name': 'ცხელი კერძები'},
      items: [
        _item('ხინკალი კალმახის ხორცით', 2.5),
        _item('მწვადი ღორის ქონდარით', 18),
        _item('შემწვარი კარტოფილი სოკოთი', 12.5),
        _item('ჩაქაფული ტარხუნით და თეთრი ღვინით', 26),
        _item('ოჯახური ღორის ხორცით და კარტოფილით', 24),
        _item('ბადრიჯანი ნიგვზით', 14),
      ],
      subcategories: [
        MenuSubcategoryDB(
          slug: 'grill',
          translationsEn: {'name': 'Grill'},
          translationsKa: {'name': 'მწვადეული'},
          items: [_item('მწვადი ცხვრის', 22)],
        ),
        MenuSubcategoryDB(
          slug: 'stew',
          translationsEn: {'name': 'Stews'},
          translationsKa: {'name': 'შემწვარი და მოხარშული'},
          items: [_item('ჩაშუშული', 21)],
        ),
      ],
    ),
  );
  await DatabaseCore.menuBox!.add(
    MenuCategoryDB(
      slug: 'drinks',
      translationsEn: {'name': 'Drinks'},
      translationsKa: {'name': 'სასმელები'},
      items: [
        _item('საფერავი 0.75', 42),
        _item('ბორჯომი 0.5', 3),
        MenuItemDB(
          translationsEn: const {'name': 'Draft beer'},
          translationsKa: const {'name': 'მოსაწური ლუდი'},
          variants: [
            MenuVariantDB(size: 0.25, price: 4),
            MenuVariantDB(size: 0.33, price: 5),
            MenuVariantDB(size: 0.5, price: 7),
            MenuVariantDB(size: 1, price: 12),
            MenuVariantDB(size: 1.5, price: 17),
            MenuVariantDB(size: 2, price: 22),
          ],
        ),
      ],
    ),
  );

  final order = Order(
    orderId: 1,
    tableNumbers: ['7'],
    floor: 'first',
    items: [
      OrderItem(
        itemKey: 'ხინკალი კალმახის ხორცით',
        itemName: 'ხინკალი კალმახის ხორცით',
        unitPrice: 2.5,
        quantity: 10,
        total: 25,
        comment: 'ცომი თხელი, წიწაკის გარეშე',
      ),
      OrderItem(
        itemKey: 'ჩაქაფული ტარხუნით და თეთრი ღვინით',
        itemName: 'ჩაქაფული ტარხუნით და თეთრი ღვინით',
        unitPrice: 26,
        quantity: 4,
        total: 104,
      ),
      OrderItem(
        itemKey: 'საფერავი 0.75',
        itemName: 'საფერავი 0.75',
        unitPrice: 42,
        quantity: 3,
        total: 126,
      ),
    ],
    totalAmount: 255,
    createdBy: 'გიორგი',
    createdAt: DateTime(2026, 8, 22, 19, 30),
  )..status = 'confirmed';
  order.discountAmount = 20;
  order.includeServiceFee = true;
  await DatabaseCore.orderBox!.put(1, order);
}

const _resolutions = <(String, Size)>[
  ('1200x720', Size(1200, 720)),
  ('1280x720', Size(1280, 720)),
  ('1366x768', Size(1366, 768)),
  ('1440x900', Size(1440, 900)),
  ('1920x1080', Size(1920, 1080)),
];

final _booking = ReservationContext(
  customerName: 'ნინო ჯავახიშვილი-წერეთელი',
  customerPhone: '+995 555 12 34 56',
  reservationDate: DateTime(2026, 8, 22),
  reservationTime: '19:30',
  tableLabels: const ['ტერასა 1', 'ტერასა 2', 'დარბაზი 7'],
  numberOfGuests: 8,
  notes: 'დაბადების დღე — ტორტი 21:00-ზე, სანთლებით და ბენგალური ცეცხლით',
);

Widget _harness(
  Size size, {
  ReservationContext? reservation,
  int? existingOrderId = 1,
  bool takeAway = false,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: SizedBox(
        width: size.width,
        height: size.height,
        child: MenuScreen(
          user: _user,
          selectedTables: const ['7'],
          tableNumbers: const ['7'],
          tableFloor: 'first',
          existingOrderId: existingOrderId,
          reservationContext: reservation,
          isTakeAwayMode: takeAway,
          takeAwayCustomerName: takeAway ? 'ლევან ბერიძე' : null,
          takeAwayPickupTime: takeAway ? '21:15' : null,
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  ReservationContext? reservation,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(size, reservation: reservation));
  await tester.pump();
}

Future<void> _pumpEmpty(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(size, existingOrderId: null));
  await tester.pump();
}

Future<void> _pumpTakeAway(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _harness(size, existingOrderId: null, takeAway: true),
  );
  await tester.pump();
}

/// `flutter_test` otherwise substitutes a stand-in face whose every glyph is a
/// full em square, which inflates Georgian text to roughly twice its real
/// width. Overflow measured against that font is fiction — it reports tears
/// that do not exist on the terminal and hides the ones that do. Loading the
/// shipped face under the default family makes the numbers here the numbers on
/// the screen.
Future<void> _loadRealFont() async {
  final data = File('assets/fonts/NotoSansGeorgian.ttf').readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(data.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadRealFont();
    _tempDir = await Directory.systemTemp.createTemp('vynic_menu_screen');
    Hive.init(_tempDir.path);
    _registerAdapters();
    await _seed();
    MenuService.clearCache();
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.menuBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.settingsBox = null;
    DatabaseCore.tableBox = null;
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  for (final (name, size) in _resolutions) {
    testWidgets('lays out without overflow at $name', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out without overflow at $name, booked', (tester) async {
      await _pump(tester, size, reservation: _booking);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out without overflow at $name, empty cart', (
      tester,
    ) async {
      await _pumpEmpty(tester, size);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out without overflow at $name, take away', (
      tester,
    ) async {
      await _pumpTakeAway(tester, size);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the quantity pad fits at $name', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('ბადრიჯანი ნიგვზით'));
      await tester.pumpAndSettle();
      expect(find.text('დამატება'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the variant picker fits at $name', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('სასმელები'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('მოსაწური ლუდი'));
      await tester.pumpAndSettle();
      expect(find.text('250 ml'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a two-line dish name stays inside its card at $name', (
      tester,
    ) async {
      // The bug this file was written for: the grid sized its cells with
      // `childAspectRatio`, which ties a card's height to the column width, so
      // whether a dish name tore depended on the resolution the terminal
      // happened to be opened at. „No exception was thrown" only says today's
      // content happened to fit; this says the content is inside the box.
      await _pump(tester, size);
      expect(tester.takeException(), isNull);

      const dish = 'შემწვარი კარტოფილი სოკოთი';
      final card = tester.getRect(
        find
            .ancestor(of: find.text(dish), matching: find.byType(Material))
            .first,
      );
      final name = tester.getRect(find.text(dish));
      final price = tester.getRect(find.text('12.50 ₾'));

      // Rect containment alone is not the test: when the cell was too short the
      // card still measured its full declared height and the *contents* spilled
      // past the padding. So the claim is that the price row — the bottom of
      // what the card holds — still lands inside the padded box.
      const inset = 13.0; // 12pt padding + the 1pt border drawn inside it
      expect(
        price.bottom,
        lessThanOrEqualTo(card.bottom - inset + 0.01),
        reason: 'card $card cannot hold its own contents',
      );
      expect(name.top, greaterThanOrEqualTo(card.top + inset - 0.01));
      expect(name.bottom, lessThanOrEqualTo(price.top + 0.01));
    });

    testWidgets('the comment dialog fits at $name', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('+ კომენტარი').first);
      await tester.pumpAndSettle();
      expect(find.text('კომენტარი'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('service fee controls stay out of take-away menu selection', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 900));
    expect(find.text('სერვისი'), findsOneWidget);

    await _pumpTakeAway(tester, const Size(1440, 900));
    expect(find.text('სერვისი'), findsNothing);
    expect(find.textContaining('სერვისი'), findsNothing);
  });
}
