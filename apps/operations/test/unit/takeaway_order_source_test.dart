import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/backup_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/takeaway_order.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';

/// Where the home takeaway panel gets its takeaways.
///
/// It used to get them from the reservation box: every takeaway order also
/// wrote a booking-shaped row, and the panel listed, counted and totalled
/// those. `Reservation.preOrderItems` exists because of it — a copy of
/// `Order.items` kept so a screen could render. The property that replaces all
/// of that is stated first below, and it is the one that matters: a takeaway
/// order with no reservation row anywhere shows up complete.
late Directory _tempDir;

const _guestFallback = 'გატანის სტუმარი';

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TableModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(OrderItemAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(OrderAdapter());
  if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ReservationAdapter());
}

Future<void> _openBoxes() async {
  DatabaseCore.userBox = await Hive.openBox<User>('to_users');
  DatabaseCore.tableBox = await Hive.openBox<TableModel>('to_tables');
  DatabaseCore.orderBox = await Hive.openBox<Order>('to_orders');
  DatabaseCore.packageBox = await Hive.openBox<Package>('to_packages');
  DatabaseCore.menuBox = await Hive.openBox<MenuCategoryDB>('to_menu');
  DatabaseCore.reservationBox = await Hive.openBox<Reservation>('to_res');
  DatabaseCore.quickOrderBox = await Hive.openBox<QuickOrderDraft>('to_quick');
  DatabaseCore.settingsBox = await Hive.openBox('to_settings');
  DatabaseCore.salesBox = await Hive.openBox('to_sales');
  DatabaseCore.expenseBox = await Hive.openBox('to_expenses');
  DatabaseCore.auditLogBox = await Hive.openBox('to_audit');
  DatabaseCore.errorLogBox = await Hive.openBox('to_errors');
  DatabaseCore.metaBox = await Hive.openBox('to_meta');
}

final DateTime _businessDate = DateTime(2026, 9, 3);

OrderItem item(String name, {int quantity = 2, double unitPrice = 3.5}) =>
    OrderItem(
      itemKey: name,
      itemName: name,
      unitPrice: unitPrice,
      quantity: quantity,
      total: unitPrice * quantity,
    );

/// A takeaway order exactly as `createTakeAwayOrder` writes one.
Order takeawayOrder({
  int orderId = 1766,
  String status = 'pending',
  List<OrderItem>? items,
  DateTime? createdAt,
  double? totalAmount,
}) {
  final order = Order(
    orderId: orderId,
    tableNumbers: ['TA-$orderId'],
    floor: 'takeaway',
    items: items ?? [item('ხინკალი')],
    totalAmount: 0,
    createdAt: createdAt ?? DateTime(2026, 9, 3, 12, 30),
    createdBy: 'Nino',
    status: status,
    includeServiceFee: false,
  );
  if (totalAmount == null) {
    order.recalculateTotal();
  } else {
    order.totalAmount = totalAmount;
  }
  return order;
}

/// A seated order, as `createOrder` writes one.
Order walkInOrder({int orderId = 1765, String floor = 'first'}) {
  final order = Order(
    orderId: orderId,
    tableNumbers: const ['7'],
    floor: floor,
    items: [item('ღვინო', quantity: 1, unitPrice: 25)],
    totalAmount: 0,
    createdAt: DateTime(2026, 9, 3, 13, 0),
    createdBy: 'Nino',
    status: 'confirmed',
    includeServiceFee: true,
  );
  order.recalculateTotal();
  return order;
}

/// A package order — `createOrderForPackage` makes an ordinary seated order
/// and hangs the package on it.
Order packageOrder({int orderId = 1767}) {
  final order = walkInOrder(orderId: orderId);
  order.packageId = 'pkg-1';
  order.packageName = 'ბანკეტი';
  order.packageGuestCount = 10;
  order.packageUnitPrice = 40;
  order.packagePrice = 400;
  order.packageItems = [item('სალათი', quantity: 10, unitPrice: 4)];
  return order;
}

/// The bookkeeping row `createTakeAwayOrder` still writes beside the order.
Reservation legacyTakeawayRow({
  int orderId = 1766,
  String id = 'legacy-takeaway',
  String customerName = 'Giorgi',
  String pickupTime = '13:30',
}) => Reservation(
  id: id,
  customerName: customerName,
  customerPhone: '+995555111222',
  tableNumbers: const [],
  reservationDate: _businessDate,
  reservationTime: pickupTime,
  numberOfGuests: 2,
  notes: 'Take-away Order #$orderId',
  createdAt: DateTime(2026, 9, 3, 12, 30),
  createdBy: 'Nino',
  status: 'confirmed',
  isTakeAway: true,
  linkedOrderId: orderId,
  // The duplicate of Order.items that this whole phase exists to stop using.
  preOrderItems: [item('სულ სხვა კერძი', quantity: 99, unitPrice: 999)],
);

Future<void> _seedOrders(List<Order> orders) async {
  await DatabaseCore.orderBox!.clear();
  for (final order in orders) {
    await DatabaseCore.orderBox!.add(order);
  }
}

Future<void> _seedReservations(List<Reservation> reservations) async {
  await DatabaseCore.reservationBox!.clear();
  for (final reservation in reservations) {
    await DatabaseCore.reservationBox!.add(reservation);
  }
}

void main() {
  setUpAll(() async {
    dotenv.loadFromString(envString: 'POS_ENV=test');
    _tempDir = await Directory.systemTemp.createTemp('vynic_takeaway_source');
    DatabaseCore.dataDirectoryPath = _tempDir.path;
    Hive.init(_tempDir.path);
    _registerAdapters();
    await _openBoxes();
  });

  tearDownAll(() async {
    await Hive.close();
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await DatabaseCore.settingsBox!.clear();
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      _businessDate.toIso8601String(),
    );
    await DatabaseCore.settingsBox!.put('serviceFeePercent', 10.0);
    await DatabaseCore.orderBox!.clear();
    await DatabaseCore.reservationBox!.clear();
  });

  group('a takeaway order with no reservation at all', () {
    test('still lists, with its items, total and status', () {
      final order = takeawayOrder(items: [item('ხინკალი', quantity: 5)]);

      final tickets = TakeawayTickets.forBusinessDate(
        orders: [order],
        businessDate: _businessDate,
      );

      expect(tickets, hasLength(1));
      final ticket = tickets.single;
      expect(ticket.orderId, 1766);
      expect(ticket.orderNumber, '#TA-1766');
      expect(ticket.items.map((i) => i.itemName), ['ხინკალი']);
      expect(ticket.itemCount, 5);
      expect(ticket.total, order.totalAmount);
      expect(ticket.status, 'pending');
      expect(ticket.isActive, isTrue);
      expect(ticket.isFinalized, isFalse);
    });

    test('falls back for the guest details the order cannot carry', () {
      final tickets = TakeawayTickets.forBusinessDate(
        orders: [takeawayOrder()],
        businessDate: _businessDate,
      );
      final ticket = tickets.single;

      expect(ticket.customerName(_guestFallback), _guestFallback);
      expect(ticket.customerPhone, isNull);
      expect(ticket.notes, isNull);
      expect(ticket.pickupTime, isNull);
      // No invented deadline: an unknown pickup time is never overdue.
      expect(ticket.isDelayedAt(DateTime(2026, 9, 3, 23, 59)), isFalse);
    });

    test('closes and cancels like any order', () {
      final closed = TakeawayTickets.forBusinessDate(
        orders: [takeawayOrder(status: 'closed')],
        businessDate: _businessDate,
      ).single;
      final cancelled = TakeawayTickets.forBusinessDate(
        orders: [takeawayOrder(status: 'cancelled')],
        businessDate: _businessDate,
      ).single;

      expect(closed.isCompleted, isTrue);
      expect(closed.isFinalized, isTrue);
      expect(closed.isActive, isFalse);
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.isActive, isFalse);
      // The legacy 'paid' spelling settles the same way OrderStatus reads it.
      final paid = TakeawayTickets.forBusinessDate(
        orders: [takeawayOrder(status: 'paid')],
        businessDate: _businessDate,
      ).single;
      expect(paid.isCompleted, isTrue);
    });
  });

  group('the order is the money', () {
    test('the shown total is the order total, not a re-sum of lines', () {
      // A discount, an adjustment or an advance all land in totalAmount; a
      // panel that re-added the lines would disagree with the receipt.
      final order = takeawayOrder(totalAmount: 12.34);

      final ticket = TakeawayTickets.forBusinessDate(
        orders: [order],
        businessDate: _businessDate,
      ).single;

      expect(ticket.total, 12.34);
      expect(ticket.total, order.totalAmount);
    });

    test('the legacy row cannot move the money or the item list', () async {
      // The bookkeeping row here claims a wildly different basket on purpose.
      final order = takeawayOrder(items: [item('ხინკალი', quantity: 5)]);
      await _seedOrders([order]);
      await _seedReservations([legacyTakeawayRow()]);

      final ticket = DatabaseService.getTakeawayTicketsForDate(
        _businessDate,
      ).single;

      expect(ticket.total, order.totalAmount);
      expect(ticket.items.map((i) => i.itemName), ['ხინკალი']);
      expect(ticket.itemCount, 5);
    });

    test('a package order contributes its package lines when it is takeaway', () {
      final order = packageOrder();
      order.floor = 'takeaway';

      final ticket = TakeawayTickets.forBusinessDate(
        orders: [order],
        businessDate: _businessDate,
      ).single;

      expect(ticket.items.first.itemName, 'სალათი');
      expect(ticket.total, order.totalAmount);
    });
  });

  group('which orders are takeaway', () {
    test('the tolerated spellings and the TA- table all count', () {
      final orders = [
        takeawayOrder(orderId: 1),
        takeawayOrder(orderId: 2)..floor = 'take-away',
        takeawayOrder(orderId: 3)..floor = 'Take Away',
        Order(
          orderId: 4,
          tableNumbers: const ['TA-4'],
          floor: 'first',
          items: [item('ა')],
          totalAmount: 7,
          createdAt: DateTime(2026, 9, 3, 12),
          createdBy: 'Nino',
          status: 'pending',
          includeServiceFee: false,
        ),
      ];

      for (final order in orders) {
        expect(isTakeawayOrder(order), isTrue, reason: 'order ${order.orderId}');
      }
    });

    test('walk-in and package orders never appear', () {
      final tickets = TakeawayTickets.forBusinessDate(
        orders: [walkInOrder(), packageOrder(), takeawayOrder()],
        businessDate: _businessDate,
      );

      expect(tickets.map((t) => t.orderId), [1766]);
      expect(isTakeawayOrder(walkInOrder()), isFalse);
      expect(isTakeawayOrder(packageOrder()), isFalse);
    });

    test('another day of takeaway is not today of takeaway', () {
      final tickets = TakeawayTickets.forBusinessDate(
        orders: [
          takeawayOrder(orderId: 10),
          takeawayOrder(
            orderId: 11,
            createdAt: DateTime(2026, 9, 2, 19, 0),
          ),
        ],
        businessDate: _businessDate,
      );

      expect(tickets.map((t) => t.orderId), [10]);
    });

    test('the queue is newest first', () {
      final tickets = TakeawayTickets.forBusinessDate(
        orders: [
          takeawayOrder(orderId: 12),
          takeawayOrder(orderId: 30),
          takeawayOrder(orderId: 21),
        ],
        businessDate: _businessDate,
      );

      expect(tickets.map((t) => t.orderId), [30, 21, 12]);
    });

    test('active counts exclude both settled and cancelled', () {
      final count = TakeawayTickets.activeCount(
        orders: [
          takeawayOrder(orderId: 1),
          takeawayOrder(orderId: 2, status: 'closed'),
          takeawayOrder(orderId: 3, status: 'cancelled'),
        ],
        businessDate: _businessDate,
      );

      expect(count, 1);
    });
  });

  group('guest details, where they still come from', () {
    test('a legacy row supplies the name, phone and pickup time', () async {
      await _seedOrders([takeawayOrder()]);
      await _seedReservations([legacyTakeawayRow()]);

      final ticket = DatabaseService.getTakeawayTicketsForDate(
        _businessDate,
      ).single;

      expect(ticket.customerName(_guestFallback), 'Giorgi');
      expect(ticket.customerPhone, '+995555111222');
      expect(ticket.pickupTime, '13:30');
    });

    test('a pickup time in the past makes an open ticket late', () {
      final ticket = TakeawayTicket(
        order: takeawayOrder(),
        contact: const TakeawayContact(pickupTime: '13:30'),
      );

      expect(ticket.isDelayedAt(DateTime(2026, 9, 3, 14, 0)), isTrue);
      expect(ticket.isDelayedAt(DateTime(2026, 9, 3, 13, 0)), isFalse);
    });

    test('a settled ticket is never late, however long ago it was due', () {
      final ticket = TakeawayTicket(
        order: takeawayOrder(status: 'closed'),
        contact: const TakeawayContact(pickupTime: '13:30'),
      );

      expect(ticket.isDelayedAt(DateTime(2026, 9, 3, 23, 59)), isFalse);
    });

    test('a placeholder phone reads as no phone', () {
      final ticket = TakeawayTicket(
        order: takeawayOrder(),
        contact: const TakeawayContact(customerPhone: '-'),
      );

      expect(ticket.customerPhone, isNull);
    });
  });

  group('an order and its legacy row are one takeaway', () {
    test('the historical duplicate appears exactly once', () async {
      await _seedOrders([takeawayOrder()]);
      await _seedReservations([
        legacyTakeawayRow(),
        // A second stale row pointing at the same order, as a repeated
        // remote delivery could once have left behind.
        legacyTakeawayRow(id: 'legacy-duplicate', customerName: 'Duplicate'),
      ]);

      final tickets = DatabaseService.getTakeawayTicketsForDate(_businessDate);

      expect(tickets, hasLength(1));
      expect(tickets.single.orderId, 1766);
    });

    test('a legacy row whose order is gone lists nothing', () async {
      // Orders are cleared at day close while the bookkeeping row survives.
      // The old panel would have shown a phantom takeaway; this one cannot.
      await _seedOrders([]);
      await _seedReservations([legacyTakeawayRow()]);

      expect(DatabaseService.getTakeawayTicketsForDate(_businessDate), isEmpty);
      expect(DatabaseCore.reservationBox!.length, 1);
    });
  });

  group('the remote and mobile paths', () {
    test('a takeaway order created remotely lists like a local one', () async {
      // What createTakeawayOrderFromRemote / upsertMobileTakeawayOrder leave:
      // the same floor and TA- table, status confirmed.
      final remote = takeawayOrder(orderId: 4321, status: 'confirmed');
      await _seedOrders([remote]);
      await _seedReservations([
        legacyTakeawayRow(orderId: 4321, id: 'remote-row'),
      ]);

      final ticket = DatabaseService.getTakeawayTicketsForDate(
        _businessDate,
      ).single;

      expect(ticket.orderId, 4321);
      expect(ticket.orderNumber, '#TA-4321');
      expect(ticket.status, OrderStatus.confirmed.storageValue);
      expect(ticket.isActive, isTrue);
    });
  });

  group('backup and restore', () {
    test('an old backup restores both records and the panel reads the order',
        () async {
      await _seedOrders([takeawayOrder(), walkInOrder()]);
      await _seedReservations([legacyTakeawayRow()]);

      final file = File('${_tempDir.path}/takeaway_backup.json');
      await BackupRepository.createDataBackup(targetFilePath: file.path);
      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      await DatabaseCore.orderBox!.clear();
      await DatabaseCore.reservationBox!.clear();
      await BackupRepository.replaceOrdersFromJson(payload['orders'] as List);
      await BackupRepository.replaceReservationsFromJson(
        payload['reservations'] as List,
      );

      // Both historical records came back.
      expect(DatabaseCore.orderBox!.length, 2);
      expect(DatabaseCore.reservationBox!.length, 1);

      // And the panel reads the order, once.
      final tickets = DatabaseService.getTakeawayTicketsForDate(_businessDate);
      expect(tickets, hasLength(1));
      expect(tickets.single.orderId, 1766);
      expect(tickets.single.items.map((i) => i.itemName), ['ხინკალი']);
    });

    test('a backup with no takeaway reservation at all still restores a working panel',
        () async {
      // A future backup, taken once the bookkeeping row is gone.
      await _seedOrders([takeawayOrder()]);
      await _seedReservations([]);

      final file = File('${_tempDir.path}/no_row_backup.json');
      await BackupRepository.createDataBackup(targetFilePath: file.path);
      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      await DatabaseCore.orderBox!.clear();
      await BackupRepository.replaceOrdersFromJson(payload['orders'] as List);

      final tickets = DatabaseService.getTakeawayTicketsForDate(_businessDate);

      expect(tickets, hasLength(1));
      expect(tickets.single.total, greaterThan(0));
      expect(tickets.single.customerName(_guestFallback), _guestFallback);
    });
  });
}
