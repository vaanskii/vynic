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
import 'package:vynic/core/models/table_ref.dart';
import 'package:vynic/core/models/takeaway_order.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/sync/manager_sync_service.dart';

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
  String customerName = '',
  String customerPhone = '',
  String pickupTime = '',
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
    customerName: customerName,
    customerPhone: customerPhone,
    pickupTime: pickupTime,
  );
  if (totalAmount == null) {
    order.recalculateTotal();
  } else {
    order.totalAmount = totalAmount;
  }
  return order;
}

/// Feeds a generated adapter the 26-field shape written before Takeaway guest
/// metadata became additive Order fields.
class _LegacyOrderReader implements BinaryReader {
  _LegacyOrderReader(this.fields);

  final Map<int, dynamic> fields;
  late final List<MapEntry<int, dynamic>> _entries = fields.entries.toList();
  var _byteIndex = -1;
  var _valueIndex = 0;

  @override
  int readByte() {
    _byteIndex++;
    if (_byteIndex == 0) return _entries.length;
    return _entries[_byteIndex - 1].key;
  }

  @override
  dynamic read([int? typeId]) => _entries[_valueIndex++].value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

/// A historical bookkeeping row written beside a Takeaway Order by old builds.
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
    await DatabaseCore.tableBox!.clear();
  });

  group('a takeaway order with no reservation at all', () {
    test('renders its Order-owned guest details, items, total and status', () {
      final order = takeawayOrder(
        items: [item('ხინკალი', quantity: 5)],
        customerName: 'Giorgi',
        customerPhone: '+995555111222',
        pickupTime: '13:30',
      );

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
      expect(ticket.customerName(_guestFallback), 'Giorgi');
      expect(ticket.customerPhone, '+995555111222');
      expect(ticket.pickupTime, '13:30');
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

    test('repository status changes need no bookkeeping reservation', () async {
      final toClose = takeawayOrder(orderId: 41);
      final toCancel = takeawayOrder(orderId: 42);
      await _seedOrders([toClose, toCancel]);
      await _seedReservations([]);

      await DatabaseService.updateOrderStatus(orderId: 41, status: 'closed');
      await DatabaseService.updateOrderStatus(orderId: 42, status: 'cancelled');
      expect(await DatabaseService.cancelReservationByOrderId(42), isFalse);
      expect(await DatabaseService.completeReservationForOrder(41), isFalse);

      final tickets = DatabaseService.getTakeawayTicketsForDate(_businessDate);
      expect(
        tickets.firstWhere((ticket) => ticket.orderId == 41).isCompleted,
        isTrue,
      );
      expect(
        tickets.firstWhere((ticket) => ticket.orderId == 42).isCancelled,
        isTrue,
      );
    });
  });

  test('the pre-metadata Hive shape reads with safe empty defaults', () {
    final restored = OrderAdapter().read(
      _LegacyOrderReader({
        0: 99,
        1: <String>['TA-99'],
        2: 'takeaway',
        3: <OrderItem>[item('ხინკალი')],
        4: 7.0,
        5: DateTime(2026, 9, 3, 12),
        6: 'Nino',
        7: 'pending',
        8: null,
        9: false,
        10: null,
        11: null,
        12: 0.0,
        13: null,
        14: null,
        15: 0.0,
        16: <OrderItem>[],
        17: 0.0,
        18: 0,
        19: 0.0,
        20: null,
        21: null,
        22: null,
        23: 0.0,
        24: null,
        25: null,
      }),
    );

    expect(restored.customerName, isEmpty);
    expect(restored.customerPhone, isEmpty);
    expect(restored.pickupTime, isEmpty);
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

    test(
      'a Package order is excluded even if legacy labels resemble takeaway',
      () {
        final order = packageOrder();
        order.floor = 'takeaway';
        order.tableNumbers = ['TA-${order.orderId}'];

        final tickets = TakeawayTickets.forBusinessDate(
          orders: [order],
          businessDate: _businessDate,
        );

        expect(tickets, isEmpty);
        expect(isTakeawayOrder(order), isFalse);
      },
    );
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
        expect(
          isTakeawayOrder(order),
          isTrue,
          reason: 'order ${order.orderId}',
        );
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
          takeawayOrder(orderId: 11, createdAt: DateTime(2026, 9, 2, 19, 0)),
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

    test('Close Day source blocks only active Takeaway orders', () {
      final disguisedPackage = packageOrder(orderId: 4)
        ..floor = 'takeaway'
        ..tableNumbers = ['TA-4'];
      final active = TakeawayTickets.activeForBusinessDate(
        orders: [
          takeawayOrder(orderId: 1),
          takeawayOrder(orderId: 2, status: 'closed'),
          takeawayOrder(orderId: 3, status: 'cancelled'),
          walkInOrder(orderId: 5),
          disguisedPackage,
        ],
        businessDate: _businessDate,
      );

      expect(active.map((ticket) => ticket.orderId), [1]);
    });
  });

  group('Order-owned guest details with legacy fallback', () {
    test('Order values win over a stale bookkeeping row', () async {
      await _seedOrders([
        takeawayOrder(
          customerName: 'Order Guest',
          customerPhone: '+995555999888',
          pickupTime: '14:45',
        ),
      ]);
      await _seedReservations([
        legacyTakeawayRow(customerName: 'Legacy Guest', pickupTime: '13:30'),
      ]);

      final ticket = DatabaseService.getTakeawayTicketsForDate(
        _businessDate,
      ).single;

      expect(ticket.customerName(_guestFallback), 'Order Guest');
      expect(ticket.customerPhone, '+995555999888');
      expect(ticket.pickupTime, '14:45');
    });

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
    test('local creation stores a self-sufficient Takeaway Order', () async {
      final created = await DatabaseService.createTakeAwayOrder(
        customerName: 'Local Guest',
        customerPhone: '+995555000111',
        pickupTime: '18:30',
        items: [item('ლობიანი')],
        createdBy: 'Nino',
      );
      expect(DatabaseCore.reservationBox!.values, isEmpty);

      final ticket = DatabaseService.getTakeawayTicketsForDate(
        _businessDate,
      ).single;

      expect(ticket.orderId, created.orderId);
      expect(ticket.customerName(_guestFallback), 'Local Guest');
      expect(ticket.customerPhone, '+995555000111');
      expect(ticket.pickupTime, '18:30');
    });

    test('mobile upsert stores and updates every supplied field', () async {
      await DatabaseService.upsertMobileTakeawayOrder(
        posOrderId: 4321,
        customerName: 'Mobile Guest',
        pickupTime: '19:00',
        waiterName: 'Nino',
        items: [item('ხაჭაპური')],
      );
      await DatabaseService.upsertMobileTakeawayOrder(
        posOrderId: 4321,
        customerName: 'Updated Guest',
        pickupTime: '19:15',
        waiterName: 'Nino',
        items: [item('ხაჭაპური', quantity: 2)],
      );
      expect(DatabaseCore.reservationBox!.values, isEmpty);

      final ticket = DatabaseService.getTakeawayTicketsForDate(
        _businessDate,
      ).single;

      expect(ticket.orderNumber, '#TA-4321');
      expect(ticket.status, OrderStatus.confirmed.storageValue);
      expect(ticket.customerName(_guestFallback), 'Updated Guest');
      expect(ticket.pickupTime, '19:15');
      expect(ticket.customerPhone, isNull);
    });

    test('remote creation stores the metadata its contract carries', () async {
      await DatabaseService.createTakeawayOrderFromRemote(
        orderId: 5432,
        customerName: 'Remote Guest',
        pickupTime: '20:00',
        waiterName: 'Nino',
        items: [
          {'itemName': 'მწვადი', 'unitPrice': 25.0, 'quantity': 1},
        ],
      );
      expect(DatabaseCore.reservationBox!.values, isEmpty);

      final ticket = DatabaseService.getTakeawayTicketsForDate(
        _businessDate,
      ).single;

      expect(ticket.customerName(_guestFallback), 'Remote Guest');
      expect(ticket.pickupTime, '20:00');
      expect(ticket.customerPhone, isNull);
    });

    test('sync serializes metadata without a Reservation lookup', () {
      final order = takeawayOrder(
        customerName: 'Sync Guest',
        customerPhone: '+995555222333',
        pickupTime: '20:30',
      );

      final payload = ManagerSyncService.buildOrdersSyncPayload(
        orders: [order],
        businessDate: _businessDate,
      ).single;

      expect(payload['customerName'], 'Sync Guest');
      expect(payload['customerPhone'], '+995555222333');
      expect(payload['pickupTime'], '20:30');
    });
  });

  group('backup and restore', () {
    test(
      'an old backup restores both records and falls back to its legacy row',
      () async {
        await _seedOrders([takeawayOrder(), walkInOrder()]);
        await _seedReservations([legacyTakeawayRow()]);

        final file = File('${_tempDir.path}/takeaway_backup.json');
        await BackupRepository.createDataBackup(targetFilePath: file.path);
        final payload =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (final raw in payload['orders'] as List) {
          final order = raw as Map<String, dynamic>;
          order.remove('customerName');
          order.remove('customerPhone');
          order.remove('pickupTime');
        }

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
        final tickets = DatabaseService.getTakeawayTicketsForDate(
          _businessDate,
        );
        expect(tickets, hasLength(1));
        expect(tickets.single.orderId, 1766);
        expect(tickets.single.items.map((i) => i.itemName), ['ხინკალი']);
        expect(tickets.single.customerName(_guestFallback), 'Giorgi');
        expect(tickets.single.customerPhone, '+995555111222');
        expect(tickets.single.pickupTime, '13:30');

        final historicalRows = DatabaseCore.reservationBox!.length;
        final newOrder = await DatabaseService.createTakeAwayOrder(
          customerName: 'New Guest',
          customerPhone: '+995555777888',
          pickupTime: '22:00',
          items: [item('ლობიანი')],
          createdBy: 'Nino',
        );

        expect(DatabaseCore.reservationBox!.length, historicalRows);
        final afterCreation = DatabaseService.getTakeawayTicketsForDate(
          _businessDate,
        );
        final newTicket = afterCreation.firstWhere(
          (ticket) => ticket.orderId == newOrder.orderId,
        );
        expect(newTicket.customerName(_guestFallback), 'New Guest');
        expect(newTicket.customerPhone, '+995555777888');
        expect(newTicket.pickupTime, '22:00');
      },
    );

    test(
      'a backup with no takeaway reservation at all still restores a working panel',
      () async {
        // A future backup, taken once the bookkeeping row is gone.
        await _seedOrders([
          takeawayOrder(
            customerName: 'Backed-up Guest',
            customerPhone: '+995555444555',
            pickupTime: '21:00',
          ),
        ]);
        await _seedReservations([]);

        final file = File('${_tempDir.path}/no_row_backup.json');
        await BackupRepository.createDataBackup(targetFilePath: file.path);
        final payload =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        await DatabaseCore.orderBox!.clear();
        await BackupRepository.replaceOrdersFromJson(payload['orders'] as List);

        final tickets = DatabaseService.getTakeawayTicketsForDate(
          _businessDate,
        );

        expect(tickets, hasLength(1));
        expect(tickets.single.total, greaterThan(0));
        expect(tickets.single.customerName(_guestFallback), 'Backed-up Guest');
        expect(tickets.single.customerPhone, '+995555444555');
        expect(tickets.single.pickupTime, '21:00');
      },
    );
  });

  test('real Reservation activation keeps and links the booking', () async {
    const reservationId = 'real-booking';
    await DatabaseCore.tableBox!.add(
      TableModel(tableNumber: '7', floor: 'first'),
    );
    await DatabaseCore.reservationBox!.add(
      Reservation(
        id: reservationId,
        customerName: 'Booked Guest',
        customerPhone: '+995555123123',
        tableNumbers: const [7],
        tableRefs: const [
          TableRef(floor: 'first', tableNumber: '7'),
        ].map((ref) => ref.encode()).toList(),
        reservationDate: _businessDate,
        reservationTime: '19:00',
        numberOfGuests: 2,
        createdAt: DateTime(2026, 9, 2),
        createdBy: 'Nino',
        status: 'confirmed',
      ),
    );

    final result = await DatabaseService.activateReservation(
      reservationId: reservationId,
      activatedBy: 'Nino',
    );

    expect(result.isSuccess, isTrue);
    expect(DatabaseCore.orderBox!.values, hasLength(1));
    expect(DatabaseCore.reservationBox!.values, hasLength(1));
    final booking = DatabaseCore.reservationBox!.values.single;
    expect(booking.id, reservationId);
    expect(booking.linkedOrderId, result.orderId);
    expect(booking.status, 'in-progress');
  });
}
