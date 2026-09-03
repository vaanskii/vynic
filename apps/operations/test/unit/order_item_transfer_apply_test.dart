import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/order_item_transfer.dart';

/// The half of a transfer that touches the disk: both orders written, and both
/// sides of the move left in the audit trail.
///
/// The arithmetic is covered in `order_item_transfer_test.dart` without a
/// database. This is about what survives being saved — moving items is money
/// leaving one bill and arriving on another, and „it looked right on screen" is
/// not the same as „it is on disk".

late Directory _tempDir;

final _user = User(username: 'გიორგი', pinCode: '0000', role: 'manager');

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
  if (!Hive.isAdapterRegistered(9)) {
    Hive.registerAdapter(ReservationAdapter());
  }
}

OrderItem _line(String name, double price, int qty) => OrderItem(
  itemKey: name,
  itemName: name,
  unitPrice: price,
  quantity: qty,
  total: price * qty,
);

Future<Order> _seedOrder({
  required int id,
  required List<OrderItem> items,
  String floor = 'first',
  List<String>? tables,
}) async {
  final order = Order(
    orderId: id,
    tableNumbers: tables ?? ['$id'],
    floor: floor,
    items: items,
    totalAmount: 0,
    createdAt: DateTime(2026, 8, 23, 19),
    createdBy: 'გიორგი',
  )..status = 'confirmed';
  order.recalculateTotal();
  await DatabaseCore.orderBox!.put(id, order);
  return order;
}

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('vynic_transfer_apply');
    Hive.init(_tempDir.path);
    _registerAdapters();
    DatabaseCore.orderBox = await Hive.openBox<Order>('tx_orders');
    DatabaseCore.settingsBox = await Hive.openBox('tx_settings');
    DatabaseCore.auditLogBox = await Hive.openBox('tx_audit');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('tx_tables');
    DatabaseCore.salesBox = await Hive.openBox('tx_sales');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>('tx_res');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      DateTime(2026, 8, 23).toIso8601String(),
    );
  });

  setUp(() async {
    await DatabaseCore.orderBox!.clear();
    // Audit reports are keyed by order id, and these tests reuse ids 1 and 2.
    // Without this the second test reads the first one's trail and the
    // „a refusal writes nothing" case passes for the wrong reason.
    await DatabaseCore.auditLogBox!.clear();
    await DatabaseCore.tableBox!.clear();
    await DatabaseCore.salesBox!.clear();
    await DatabaseCore.reservationBox!.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.orderBox = null;
    DatabaseCore.settingsBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.salesBox = null;
    DatabaseCore.reservationBox = null;
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  test(
    'both orders come back off disk with the items where they went',
    () async {
      final source = await _seedOrder(
        id: 1,
        tables: ['7'],
        items: [_line('ხინკალი', 2.50, 10), _line('მწვადი', 18.00, 2)],
      );
      final destination = await _seedOrder(id: 2, tables: ['12'], items: []);

      final result = await OrderItemTransfer.apply(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 6)],
        user: _user,
        sourceLabel: 'მაგიდა 7',
        destinationLabel: 'მაგიდა 12',
      );

      expect(result.ok, isTrue);

      final savedSource = DatabaseService.getOrder(1)!;
      final savedDestination = DatabaseService.getOrder(2)!;
      expect(savedSource.items.first.quantity, 4);
      expect(savedDestination.items.single.quantity, 6);
      expect(savedDestination.items.single.total, 15.00);
      // Both totals were recomputed on the way out, not left stale.
      expect(savedSource.totalAmount, 46.00); // 4x2.50 + 2x18
      expect(savedDestination.totalAmount, 15.00);
    },
  );

  test('the move is on both orders audit trails', () async {
    // A bill that shrank and a bill that grew, at the same moment, with no
    // record of why, is the thing a manager cannot reconstruct later.
    final source = await _seedOrder(
      id: 1,
      tables: ['7'],
      items: [_line('საფერავი', 42.00, 2)],
    );
    final destination = await _seedOrder(id: 2, tables: ['12'], items: []);

    await OrderItemTransfer.apply(
      source: source,
      destination: destination,
      moves: const [(index: 0, quantity: 2)],
      user: _user,
      sourceLabel: 'მაგიდა 7',
      destinationLabel: 'მაგიდა 12',
    );

    final sourceReport = DatabaseService.getAuditReport(1);
    final destinationReport = DatabaseService.getAuditReport(2);

    expect(sourceReport, isNotNull);
    expect(destinationReport, isNotNull);

    final left = sourceReport!.events.single;
    expect(left.type, AuditEventType.reduceQty);
    expect(left.itemName, 'საფერავი');
    expect(left.note, contains('მაგიდა 12'));
    expect(left.waiterName, 'გიორგი');

    final arrived = destinationReport!.events.single;
    expect(arrived.type, AuditEventType.addItem);
    expect(arrived.newQty, 2);
    expect(arrived.note, contains('მაგიდა 7'));
  });

  test('a refusal writes nothing at all', () async {
    final source = await _seedOrder(
      id: 1,
      tables: ['7'],
      items: [_line('ხინკალი', 2.50, 4)],
    );
    final destination = await _seedOrder(id: 2, tables: ['12'], items: []);

    final result = await OrderItemTransfer.apply(
      source: source,
      destination: destination,
      moves: const [(index: 0, quantity: 99)],
      user: _user,
      sourceLabel: 'მაგიდა 7',
      destinationLabel: 'მაგიდა 12',
    );

    expect(result.error, OrderTransferError.quantityOutOfRange);
    // Not even the in-memory objects the caller handed in may be touched: the
    // order detail screen keeps painting from them after a refusal.
    expect(source.items.single.quantity, 4);
    expect(DatabaseService.getOrder(1)!.items.single.quantity, 4);
    expect(DatabaseService.getOrder(2)!.items, isEmpty);
    expect(DatabaseService.getAuditReport(1), isNull);
  });

  test('a take-away hands its bill to a table and both persist', () async {
    final takeAway = await _seedOrder(
      id: 1,
      floor: 'takeaway',
      tables: ['TA-4'],
      items: [_line('ხინკალი', 2.50, 10)],
    );
    final table = await _seedOrder(
      id: 2,
      floor: 'first',
      tables: ['7'],
      items: [],
    );

    final result = await OrderItemTransfer.apply(
      source: takeAway,
      destination: table,
      moves: const [(index: 0, quantity: 10)],
      user: _user,
      sourceLabel: 'გატანა',
      destinationLabel: 'მაგიდა 7',
    );

    expect(result.sourceLeftEmpty, isTrue);
    expect(DatabaseService.getOrder(1)!.items, isEmpty);
    expect(DatabaseService.getOrder(2)!.items.single.quantity, 10);
    // The orders keep their own identity; only the items crossed.
    expect(DatabaseService.getOrder(1)!.floor, 'takeaway');
    expect(DatabaseService.getOrder(2)!.floor, 'first');
  });

  group('an order a transfer emptied', () {
    Future<Order> seedOccupiedTable() async {
      final order = await _seedOrder(
        id: 1,
        tables: ['7'],
        items: [_line('ხინკალი', 2.50, 4)],
      );
      final table = TableModel(tableNumber: '7', floor: 'first');
      table.reserve('გიორგი', 1);
      await DatabaseCore.tableBox!.add(table);

      await DatabaseCore.reservationBox!.add(
        Reservation(
          id: 'res-1',
          customerName: 'ნინო',
          customerPhone: '555',
          tableNumbers: const [7],
          reservationDate: DateTime(2026, 8, 23),
          reservationTime: '19:30',
          numberOfGuests: 4,
          createdAt: DateTime(2026, 8, 23),
          createdBy: 'გიორგი',
          status: 'confirmed',
          linkedOrderId: 1,
        ),
      );
      return order;
    }

    test('frees the table it was sitting on', () async {
      final order = await seedOccupiedTable();
      final destination = await _seedOrder(id: 2, tables: ['12'], items: []);

      await OrderItemTransfer.apply(
        source: order,
        destination: destination,
        moves: const [(index: 0, quantity: 4)],
        user: _user,
        sourceLabel: 'მაგიდა 7',
        destinationLabel: 'მაგიდა 12',
      );
      await OrderItemTransfer.releaseEmptiedOrder(order);

      final table = DatabaseCore.tableBox!.values.single;
      expect(table.isReserved, isFalse);
      expect(table.activeOrderId, isNull);
    });

    test(
      'writes no sale record, so reports do not count a cancellation',
      () async {
        // Cancelling an order writes a sale flagged `isCancelled`, and the sales
        // report counts exactly those. Moving a bill between two tables is not a
        // void, and must not show up as one in the venue's numbers.
        final order = await seedOccupiedTable();
        final destination = await _seedOrder(id: 2, tables: ['12'], items: []);

        await OrderItemTransfer.apply(
          source: order,
          destination: destination,
          moves: const [(index: 0, quantity: 4)],
          user: _user,
          sourceLabel: 'მაგიდა 7',
          destinationLabel: 'მაგიდა 12',
        );
        await OrderItemTransfer.releaseEmptiedOrder(order);

        expect(DatabaseCore.salesBox!.isEmpty, isTrue);
      },
    );

    test('closes rather than cancels — nothing was cancelled', () async {
      final order = await seedOccupiedTable();
      final destination = await _seedOrder(id: 2, tables: ['12'], items: []);

      await OrderItemTransfer.apply(
        source: order,
        destination: destination,
        moves: const [(index: 0, quantity: 4)],
        user: _user,
        sourceLabel: 'მაგიდა 7',
        destinationLabel: 'მაგიდა 12',
      );
      await OrderItemTransfer.releaseEmptiedOrder(order);

      final saved = DatabaseService.getOrder(1)!;
      expect(saved.status, isNot('cancelled'));
      expect(saved.statusEnum, OrderStatus.closed);
      expect(saved.closedAt, isNotNull);
      expect(saved.totalAmount, 0);
    });

    test('finishes the booking instead of cancelling it', () async {
      // The party did not cancel — they moved. A booking left `confirmed`
      // against a closed order is also what blocks the day close.
      final order = await seedOccupiedTable();
      final destination = await _seedOrder(id: 2, tables: ['12'], items: []);

      await OrderItemTransfer.apply(
        source: order,
        destination: destination,
        moves: const [(index: 0, quantity: 4)],
        user: _user,
        sourceLabel: 'მაგიდა 7',
        destinationLabel: 'მაგიდა 12',
      );
      await OrderItemTransfer.releaseEmptiedOrder(order);

      final reservation = DatabaseCore.reservationBox!.values.single;
      expect(reservation.statusEnum, ReservationStatus.completed);
    });

    test('a partly emptied order is left alone', () async {
      // Only a whole bill moving frees the table. Half of one is still a party
      // sitting there.
      final order = await seedOccupiedTable();
      final destination = await _seedOrder(id: 2, tables: ['12'], items: []);

      await OrderItemTransfer.apply(
        source: order,
        destination: destination,
        moves: const [(index: 0, quantity: 1)],
        user: _user,
        sourceLabel: 'მაგიდა 7',
        destinationLabel: 'მაგიდა 12',
      );
      await OrderItemTransfer.releaseEmptiedOrder(order);

      expect(DatabaseCore.tableBox!.values.single.isReserved, isTrue);
      expect(
        DatabaseService.getOrder(1)!.statusEnum,
        isNot(OrderStatus.closed),
      );
    });
  });
}
