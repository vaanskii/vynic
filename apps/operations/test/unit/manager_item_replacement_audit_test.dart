import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';

/// A Manager edit to an Order that already exists.
///
/// The Manager upsert replaces the Order's whole item collection, so what the
/// operator actually did is only visible as the difference against what is
/// stored. Without that diff, a Manager changed the check and left nothing on
/// the report, while the same edit made at the POS wrote `ADD_ITEM`,
/// `REDUCE_QTY` or `DELETE_ITEM`.
void main() {
  late Directory tempDir;

  const businessDate = '2026-09-05';

  const boxes = [
    'mir_settings',
    'mir_audit',
    'mir_orders',
    'mir_tables',
    'mir_users',
    'mir_reservations',
  ];

  void registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(UserAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MenuCategoryDBAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(MenuSubcategoryDBAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MenuItemDBAdapter());
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(MenuVariantDBAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(ReservationAdapter());
    }
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_manager_items');
    Hive.init(tempDir.path);
    registerAdapters();
    Order.serviceFeeRateResolver = () => 0.0;
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('mir_settings');
    DatabaseCore.auditLogBox = await Hive.openBox('mir_audit');
    DatabaseCore.orderBox = await Hive.openBox<Order>('mir_orders');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('mir_tables');
    DatabaseCore.userBox = await Hive.openBox<User>('mir_users');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>(
      'mir_reservations',
    );
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '${businessDate}T00:00:00.000',
    );
  });

  tearDown(() async {
    for (final name in boxes) {
      await Hive.deleteBoxFromDisk(name);
    }
    DatabaseCore.settingsBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.userBox = null;
    DatabaseCore.reservationBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  OrderItem item(String name, int quantity, {double price = 5}) => OrderItem(
    itemKey: name,
    itemName: name,
    unitPrice: price,
    quantity: quantity,
    total: price * quantity,
  );

  Future<void> upsertTakeaway(List<OrderItem> items) =>
      OrderRepository.upsertMobileTakeawayOrder(
        posOrderId: 1,
        customerName: 'Tamar',
        pickupTime: '19:00',
        waiterName: 'mobile_manager',
        items: items,
      );

  Future<void> upsertDineIn(List<OrderItem> items) =>
      OrderRepository.upsertMobileDineInOrder(
        posOrderId: 2,
        tableNumbers: const ['5'],
        floor: 'first',
        waiterName: 'mobile_manager',
        items: items,
      );

  /// The Order's timeline after the creation event and its opening lines.
  List<AuditEvent> changesAfterCreation(int orderId) {
    final report = AuditRepository.getAuditReport(orderId)!;
    final events = report.orderedEvents;
    // Everything the creation wrote shares the Order's opening instant; the
    // edits are what came after.
    final openedAt = events.first.timestamp;
    return events
        .skip(1)
        .where((event) => event.timestamp.isAfter(openedAt))
        .toList(growable: false);
  }

  test('a new line on an existing takeaway order is an ADD_ITEM', () async {
    await upsertTakeaway([item('Khinkali', 2)]);
    await upsertTakeaway([item('Khinkali', 2), item('Lobio', 1)]);

    final changes = changesAfterCreation(1);
    expect(changes, hasLength(1));
    expect(changes.single.type, AuditEventType.addItem);
    expect(changes.single.itemName, 'Lobio');
    expect(changes.single.previousQty, 0);
    expect(changes.single.newQty, 1);
    // And it says the edit came from the Manager, not from this terminal.
    expect(changes.single.details?[AuditSource.detailsKey], 'MANAGER');
  });

  test('a smaller quantity is a REDUCE_QTY, a removed line a DELETE_ITEM', () async {
    await upsertDineIn([item('Khinkali', 4), item('Lobio', 2)]);
    await upsertDineIn([item('Khinkali', 1)]);

    final changes = changesAfterCreation(2);
    final byName = {for (final change in changes) change.itemName: change};
    expect(byName.keys, unorderedEquals(<String>['Khinkali', 'Lobio']));

    expect(byName['Khinkali']!.type, AuditEventType.reduceQty);
    expect(byName['Khinkali']!.previousQty, 4);
    expect(byName['Khinkali']!.newQty, 1);

    expect(byName['Lobio']!.type, AuditEventType.deleteItem);
    expect(byName['Lobio']!.previousQty, 2);
    expect(byName['Lobio']!.newQty, 0);
  });

  test('a redelivered identical payload writes nothing', () async {
    await upsertDineIn([item('Khinkali', 4)]);
    final beforeRetry = AuditRepository.getAuditReport(2)!.events.length;

    // At-least-once delivery: the same command arriving three times is one
    // edit, and the diff against storage is what makes that true.
    await upsertDineIn([item('Khinkali', 4)]);
    await upsertDineIn([item('Khinkali', 4)]);

    expect(AuditRepository.getAuditReport(2)!.events, hasLength(beforeRetry));
    expect(changesAfterCreation(2), isEmpty);
  });

  test('the edits extend the timeline rather than rewriting it', () async {
    await upsertDineIn([item('Khinkali', 2)]);
    await upsertDineIn([item('Khinkali', 2), item('Lobio', 1)]);
    await upsertDineIn([item('Khinkali', 2)]);

    final events = AuditRepository.getAuditReport(2)!.orderedEvents;
    // Gapless, ascending, creation first — the Phase 3.5 contract holds for
    // events appended from this path like any other.
    expect(
      events.map((event) => event.sequence).toList(),
      List<int>.generate(events.length, (index) => index),
    );
    expect(events.first.type, AuditEventType.createWalkIn);
    expect(events.last.type, AuditEventType.deleteItem);
    expect(events.last.itemName, 'Lobio');
  });
}
