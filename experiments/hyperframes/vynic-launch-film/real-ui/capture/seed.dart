import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/models/user.dart';
export 'package:vynic/core/models/user.dart';

/// Demo restaurant "ფიქალი" — synthetic data only.
void registerAll() {
  void r<T>(int id, TypeAdapter<T> a) { if (!Hive.isAdapterRegistered(id)) Hive.registerAdapter(a); }
  r(0, UserAdapter()); r(2, TableModelAdapter()); r(3, OrderItemAdapter()); r(4, OrderAdapter());
  r(5, MenuCategoryDBAdapter()); r(6, MenuSubcategoryDBAdapter()); r(7, MenuItemDBAdapter()); r(8, MenuVariantDBAdapter());
  r(9, ReservationAdapter()); r(14, QuickOrderDraftAdapter());
}

OrderItem oi(String name, double price, int qty) => OrderItem(itemKey: name, itemName: name, unitPrice: price, quantity: qty, total: price * qty);
MenuItemDB mi(String ka, double price) => MenuItemDB.create(translationsEn: {'name': ka}, translationsKa: {'name': ka}, price: price);
MenuCategoryDB cat(String slug, String ka, List<MenuItemDB> items) =>
    MenuCategoryDB.create(slug: slug, translationsEn: {'name': ka}, translationsKa: {'name': ka}, items: items);

Map<String, dynamic> georgianLayout() {
  final j = jsonDecode(jsonEncode(RestaurantTableLayouts.floorPlanPreview)) as Map<String, dynamic>;
  String ka(String s) => s
      .replaceAll('Table ', 'მაგიდა ')
      .replaceAll('VIP Zone ', 'VIP ')
      .replaceAll('Bar', 'ბარი')
      .replaceAll('Entrance', 'შესასვლელი')
      .replaceAll('Stage', 'სცენა')
      .replaceAll('Stairs', 'კიბე')
      .replaceAll('First floor', 'დარბაზი')
      .replaceAll('Second floor', 'ტერასა');
  dynamic walk(dynamic v) {
    if (v is Map) return <String, dynamic>{for (final e in v.entries) e.key.toString(): (e.key == 'label' || e.key == 'name') && e.value is String ? ka(e.value as String) : walk(e.value)};
    if (v is List) return v.map(walk).toList();
    return v;
  }
  return walk(j) as Map<String, dynamic>;
}

Future<void> seedRestaurant(String p, DateTime day) async {
  DatabaseCore.settingsBox = await Hive.openBox('${p}_settings');
  DatabaseCore.salesBox = await Hive.openBox('${p}_sales');
  DatabaseCore.auditLogBox = await Hive.openBox('${p}_audit');
  DatabaseCore.orderBox = await Hive.openBox<Order>('${p}_orders');
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('${p}_tables');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('${p}_res');
  DatabaseCore.closureJournalBox = await Hive.openBox('${p}_journal');
  DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('${p}_menu');
  DatabaseCore.quickOrderBox = await Hive.openBox<QuickOrderDraft>('${p}_quick');
  DatabaseCore.expenseBox = await Hive.openBox('${p}_expenses');
  DatabaseCore.errorLogBox = await Hive.openBox('${p}_errors');
  DatabaseCore.metaBox = await Hive.openBox('${p}_meta');
  DatabaseCore.userBox = await Hive.openBox<User>('${p}_users');
  for (final u in [('ნინო', 'manager'), ('გიორგი', 'waiter'), ('ანა', 'waiter'), ('ლევანი', 'supervisor')]) {
    await DatabaseCore.userBox!.add(User(username: u.$1, pinCode: '0000', role: u.$2));
  }

  final s = DatabaseCore.settingsBox!;
  await s.put('currentDate', DateTime(day.year, day.month, day.day).toIso8601String());
  await s.put('serviceFeeEnabled', true);
  await s.put('serviceFeePercentage', 10.0);
  await s.put('defaultIncludeServiceFee', true);
  await s.put('activeTableLayoutJson', jsonEncode(georgianLayout()));

  final menu = DatabaseCore.menuBox!;
  await menu.add(cat('bakery', 'ცომეული', [mi('ხაჭაპური აჭარული', 22), mi('ხაჭაპური იმერული', 18), mi('ლობიანი', 12), mi('პენოვანი', 16)]));
  await menu.add(cat('salads', 'სალათები', [mi('ქართული სალათი', 14), mi('ბადრიჯანი ნიგვზით', 12), mi('ფხალეულის დაფა', 19), mi('ყველის დაფა', 16)]));
  await menu.add(cat('hot', 'ცხელი კერძები', [mi('ხინკალი ქალაქური', 1.2), mi('მწვადი ღორის', 24), mi('ჩაქაფული', 26), mi('ოჯახური', 22)]));
  await menu.add(cat('drinks', 'სასმელები', [mi('ლიმონათი', 6), mi('ტარხუნის ლიმონათი', 6), mi('ბორჯომი 0.5', 4), mi('საფერავი, ჭიქა', 9)]));
  await menu.add(cat('desserts', 'დესერტები', [mi('ჩურჩხელა', 6), mi('ფელამუში', 9)]));

  // Table 1 is already occupied tonight.
  final now = DateTime.now();
  final o1 = Order(
    orderId: 1741, tableNumbers: const ['1'], floor: 'first',
    items: [oi('ხინკალი ქალაქური', 1.2, 20), oi('მწვადი ღორის', 24, 2), oi('ქართული სალათი', 14, 2), oi('საფერავი, ჭიქა', 9, 4)],
    totalAmount: 116.0, createdAt: now.subtract(const Duration(minutes: 2)), createdBy: 'ნინო', status: 'served', includeServiceFee: true,
  );
  await DatabaseCore.orderBox!.put(o1.orderId, o1);
  for (var i = 1; i <= 9; i++) {
    final t = TableModel(tableNumber: '$i', floor: 'first');
    if (i == 1) t.reserve('ნინო', o1.orderId);
    await DatabaseCore.tableBox!.put('first-$i', t);
  }

  // Tonight's reservations (one confirmed, one waiting to be seated).
  final res = DatabaseCore.reservationBox!;
  await res.put('r1', Reservation(id: 'r1', customerName: 'ნინო ბერიძე', customerPhone: '555 12 34 50', tableNumbers: [],
      reservationDate: day, reservationTime: '22:00', numberOfGuests: 4, notes: 'ფანჯარასთან', createdAt: now, createdBy: 'ნინო',
      status: 'confirmed', preOrderItems: [oi('ხინკალი ქალაქური', 1.2, 20), oi('საფერავი, ჭიქა', 9, 4)]));
  await res.put('r2', Reservation(id: 'r2', customerName: 'ლევან კაპანაძე', customerPhone: '599 44 21 07', tableNumbers: [],
      reservationDate: day, reservationTime: '22:30', numberOfGuests: 6, notes: 'დაბადების დღე', createdAt: now, createdBy: 'ნინო',
      status: 'confirmed', preOrderItems: [oi('ხაჭაპური აჭარული', 22, 2), oi('ფხალეულის დაფა', 19, 1)]));

  // Takeaways.
  var id = 1760;
  for (final t in [
    ('გიორგი მაისურაძე', '577 00 11 20', '21:05', [oi('ხინკალი ქალაქური', 1.2, 30), oi('ლობიანი', 12, 1)], 'served'),
    ('ანა ჯაფარიძე', '591 32 18 44', '21:25', [oi('ხაჭაპური იმერული', 18, 2), oi('ლიმონათი', 6, 2)], 'served'),
    ('თამარ გელაშვილი', '555 70 02 13', '20:10', [oi('მწვადი ღორის', 24, 1)], 'closed'),
  ]) {
    final items = t.$4;
    final o = Order(orderId: id, tableNumbers: ['TA-${id - 1759}'], floor: 'takeaway', items: items,
        totalAmount: items.fold(0.0, (a, b) => a + b.total), createdAt: now.subtract(const Duration(minutes: 20)), createdBy: 'ნინო',
        status: t.$5, includeServiceFee: false, customerName: t.$1, customerPhone: t.$2, pickupTime: t.$3);
    await DatabaseCore.orderBox!.put(id, o);
    id++;
  }

  // Menu counting (დათვლა): saved menus for groups.
  final q = DatabaseCore.quickOrderBox!;
  final banquet = [oi('ხინკალი ქალაქური', 1.2, 60), oi('ფხალეულის დაფა', 19, 3), oi('ქართული სალათი', 14, 3), oi('ლიმონათი', 6, 12)];
  final sub1 = banquet.fold(0.0, (a, b) => a + b.total);
  await q.put('d1', QuickOrderDraft(id: 'd1', items: banquet, subtotal: sub1, serviceFeeAmount: sub1 * 0.1, total: sub1 * 1.1,
      includeServiceFee: true, serviceFeeRate: 0.1, createdAt: now, createdBy: 'ნინო', displayName: 'ბანკეტი — 12 სტუმარი'));
  final lunch = [oi('ხაჭაპური აჭარული', 22, 4), oi('ქართული სალათი', 14, 4), oi('ბორჯომი 0.5', 4, 8)];
  final sub2 = lunch.fold(0.0, (a, b) => a + b.total);
  await q.put('d2', QuickOrderDraft(id: 'd2', items: lunch, subtotal: sub2, serviceFeeAmount: sub2 * 0.1, total: sub2 * 1.1,
      includeServiceFee: true, serviceFeeRate: 0.1, createdAt: now, createdBy: 'ნინო', displayName: 'საქმიანი სადილი'));
}
