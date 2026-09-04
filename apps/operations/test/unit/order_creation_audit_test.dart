import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/transactions/activate_reservation_transaction.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/pos/order_item_transfer.dart';
import 'package:vynic/core/services/pos/pos_command_applier.dart';

/// Creation-taxonomy phase: every Order report opens with the event that
/// created it, says what kind of Order it is and which channel opened it, and
/// a transfer is written as a move rather than an add and a removal.
void main() {
  late Directory tempDir;

  const businessDate = '2026-09-04';
  final user = User(username: 'Nino', pinCode: '0000', role: 'waiter');

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
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(SaleRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SaleRecordItemAdapter());
    }
  }

  const boxes = [
    'oc_settings',
    'oc_sales',
    'oc_expenses',
    'oc_audit',
    'oc_tables',
    'oc_orders',
    'oc_users',
    'oc_reservations',
  ];

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_order_creation');
    Hive.init(tempDir.path);
    registerAdapters();
    Order.serviceFeeRateResolver = () => 0.0;
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('oc_settings');
    DatabaseCore.salesBox = await Hive.openBox('oc_sales');
    DatabaseCore.expenseBox = await Hive.openBox('oc_expenses');
    DatabaseCore.auditLogBox = await Hive.openBox('oc_audit');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('oc_tables');
    DatabaseCore.orderBox = await Hive.openBox<Order>('oc_orders');
    DatabaseCore.userBox = await Hive.openBox<User>('oc_users');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>(
      'oc_reservations',
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
    DatabaseCore.salesBox = null;
    DatabaseCore.expenseBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.userBox = null;
    DatabaseCore.reservationBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> seedTable(String number, {String floor = 'first'}) =>
      DatabaseCore.tableBox!.put(
        '$floor-$number',
        TableModel(tableNumber: number, floor: floor),
      );

  OrderItem line(String name, double price, int qty) => OrderItem(
    itemKey: name,
    itemName: name,
    unitPrice: price,
    quantity: qty,
    total: price * qty,
  );

  AuditReport reportOf(int orderId) {
    final report = AuditRepository.getAuditReport(orderId);
    expect(report, isNotNull, reason: 'order $orderId has no audit report');
    return report!;
  }

  void expectOrderEvent(
    AuditEvent event, {
    required AuditEventType type,
    required String orderKind,
    required String source,
    required String actor,
    required int orderId,
  }) {
    expect(event.type, type);
    expect(event.itemName, 'ORDER');
    expect(event.waiterId, actor);
    expect(event.waiterName, actor);
    final details = event.details!;
    expect(details, containsPair('orderId', orderId));
    expect(details, containsPair('orderKind', orderKind));
    expect(details, containsPair('source', source));
    expect(details, containsPair('actorId', actor));
    expect(details, containsPair('actorName', actor));
    expect(details, containsPair('businessDate', businessDate));
    expect(details.keys.map((k) => k.toLowerCase()), isNot(contains('pin')));
  }

  group('Walk-In', () {
    test(
      'the report opens with CREATE_WALKIN before its first lines',
      () async {
        await seedTable('7');

        final order = await OrderRepository.createOrder(
          tableNumbers: const ['7'],
          floor: 'first',
          createdBy: 'Nino',
          items: [line('ხინკალი', 1.5, 4), line('ლუდი', 6.0, 2)],
        );

        final report = reportOf(order.orderId);
        expect(report.events, hasLength(3));
        final created = report.events.first;
        expectOrderEvent(
          created,
          type: AuditEventType.createWalkIn,
          orderKind: 'WALK_IN',
          source: 'POS',
          actor: 'Nino',
          orderId: order.orderId,
        );
        expect(created.timestamp, order.createdAt);
        expect(created.details, containsPair('tableRefs', ['first/7']));
        expect(created.details, containsPair('floor', 'first'));
        expect(
          report.events.skip(1).map((e) => e.type),
          everyElement(AuditEventType.addItem),
        );
        expect(report.status, AuditReportStatus.open);
      },
    );

    test(
      'an Order opened with nothing on it still has its creation row',
      () async {
        await seedTable('7');

        final order = await OrderRepository.createOrder(
          tableNumbers: const ['7'],
          floor: 'first',
          createdBy: 'Nino',
          items: const [],
        );

        expect(
          reportOf(order.orderId).events.single.type,
          AuditEventType.createWalkIn,
        );
      },
    );

    test(
      'a Manager Walk-In is source MANAGER and not re-created on redelivery',
      () async {
        await seedTable('7');
        final payload = <String, dynamic>{
          'posOrderId': 4301,
          'tableNumbers': <String>['7'],
          'floor': 'first',
          'waiterName': 'Nino',
          'guestCount': 3,
          'items': <Map<String, dynamic>>[],
        };

        expect((await PosCommandApplier.upsertDineInOrder(payload)).ok, isTrue);
        expect((await PosCommandApplier.upsertDineInOrder(payload)).ok, isTrue);

        final report = reportOf(4301);
        expect(report.events, hasLength(1));
        expectOrderEvent(
          report.events.single,
          type: AuditEventType.createWalkIn,
          orderKind: 'WALK_IN',
          source: 'MANAGER',
          actor: 'Nino',
          orderId: 4301,
        );
        expect(report.events.single.details, containsPair('guestCount', 3));
      },
    );
  });

  group('Takeaway', () {
    test('the report exists from creation with the guest details', () async {
      final order = await OrderRepository.createTakeAwayOrder(
        customerName: 'Guest',
        customerPhone: '555123456',
        pickupTime: '18:30',
        items: [line('ხაჭაპური', 12.0, 1)],
        createdBy: 'Nino',
      );

      final report = reportOf(order.orderId);
      expect(report.events, hasLength(2));
      final created = report.events.first;
      expectOrderEvent(
        created,
        type: AuditEventType.createTakeaway,
        orderKind: 'TAKEAWAY',
        source: 'POS',
        actor: 'Nino',
        orderId: order.orderId,
      );
      expect(created.details, containsPair('customerName', 'Guest'));
      expect(created.details, containsPair('customerPhone', '555123456'));
      expect(created.details, containsPair('pickupTime', '18:30'));
      expect(
        created.details,
        containsPair('tableRefs', ['takeaway/TA-${order.orderId}']),
      );
      expect(report.events.last.type, AuditEventType.addItem);
      // No physical table was touched.
      expect(DatabaseCore.tableBox!.isEmpty, isTrue);
    });

    test('a Manager Takeaway is source MANAGER', () async {
      final result =
          await PosCommandApplier.upsertTakeawayOrder(<String, dynamic>{
            'posOrderId': 90001,
            'customerName': 'Guest',
            'pickupTime': '19:00',
            'waiterName': 'Nino',
            'items': <Map<String, dynamic>>[],
          });
      expect(result.ok, isTrue);

      final created = reportOf(90001).events.single;
      expectOrderEvent(
        created,
        type: AuditEventType.createTakeaway,
        orderKind: 'TAKEAWAY',
        source: 'MANAGER',
        actor: 'Nino',
        orderId: 90001,
      );
      expect(created.details, containsPair('customerName', 'Guest'));
      expect(created.details, containsPair('pickupTime', '19:00'));
    });
  });

  group('Package', () {
    test(
      'opens as a PACKAGE carrier and records APPLY_PACKAGE after it',
      () async {
        await seedTable('9');
        final package = Package(
          packageId: 'pkg-1',
          name: 'სუფრა',
          items: [
            PackageItem(
              itemKey: 'khinkali',
              itemName: 'ხინკალი',
              quantity: 10,
              unitPrice: 1.5,
            ),
          ],
          pricePerPerson: 50,
          createdAt: DateTime.parse('${businessDate}T10:00:00'),
          createdBy: 'admin',
          servingSize: 4,
        );

        final order = await OrderRepository.createOrderForPackage(
          package: package,
          tableNumbers: const ['9'],
          floor: 'first',
          guestCount: 4,
          createdBy: 'Nino',
        );

        final report = reportOf(order.orderId);
        expect(report.events, hasLength(2));
        expectOrderEvent(
          report.events.first,
          type: AuditEventType.createWalkIn,
          orderKind: 'PACKAGE',
          source: 'POS',
          actor: 'Nino',
          orderId: order.orderId,
        );
        final applied = report.events.last;
        expect(applied.type, AuditEventType.applyPackage);
        expect(applied.itemName, 'სუფრა');
        expect(
          applied.timestamp.isAfter(report.events.first.timestamp),
          isTrue,
        );
        expect(applied.details, containsPair('packageId', 'pkg-1'));
        expect(applied.details, containsPair('packageName', 'სუფრა'));
        expect(applied.details, containsPair('packageGuestCount', 4));
        expect(applied.details, containsPair('packageUnitPrice', 50.0));
        expect(applied.details, containsPair('packagePrice', 200.0));
        expect(applied.details, containsPair('orderKind', 'PACKAGE'));
        final items = applied.details!['packageItems'] as List;
        expect(items, hasLength(1));
        expect((items.single as Map)['itemName'], 'ხინკალი');
        expect((items.single as Map)['quantity'], 10);
        expect(order.statusEnum, OrderStatus.confirmed);
      },
    );
  });

  group('Reservation', () {
    Reservation booking({List<OrderItem>? preOrder}) => Reservation(
      id: 'res-1',
      customerName: 'ნინო გ.',
      customerPhone: '+995555000000',
      tableNumbers: const [5],
      tableRefs: const ['first/5'],
      reservationDate: DateTime.parse('${businessDate}T00:00:00'),
      reservationTime: '19:00',
      numberOfGuests: 4,
      createdAt: DateTime.parse('2026-09-01T12:00:00'),
      createdBy: 'Nino',
      status: 'confirmed',
      preOrderItems: preOrder,
    );

    test(
      'seating a booking opens the report with ACTIVATE_RESERVATION',
      () async {
        await seedTable('5');
        await DatabaseCore.reservationBox!.add(
          booking(preOrder: [line('საფერავი', 42.0, 1)]),
        );

        final result = await ActivateReservationTransaction.activate(
          reservationId: 'res-1',
          activatedBy: 'Nino',
        );
        expect(result.isSuccess, isTrue);

        final report = reportOf(result.orderId!);
        expect(report.events, hasLength(2));
        final activated = report.events.first;
        expectOrderEvent(
          activated,
          type: AuditEventType.activateReservation,
          orderKind: 'RESERVATION',
          source: 'POS',
          actor: 'Nino',
          orderId: result.orderId!,
        );
        expect(activated.details, containsPair('reservationId', 'res-1'));
        expect(activated.details, containsPair('customerName', 'ნინო გ.'));
        expect(activated.details, containsPair('tableRefs', ['first/5']));
        expect(report.events.last.type, AuditEventType.addItem);
        expect(
          report.events.where((e) => e.type == AuditEventType.createWalkIn),
          isEmpty,
        );
      },
    );

    test('day-open activation is attributed to the system source', () async {
      await seedTable('5');
      await DatabaseCore.reservationBox!.add(booking());

      await ActivateReservationTransaction.activateTodaysReservations();

      final order = DatabaseCore.orderBox!.values.single;
      final activated = reportOf(order.orderId).events.single;
      expectOrderEvent(
        activated,
        type: AuditEventType.activateReservation,
        orderKind: 'RESERVATION',
        source: 'SYSTEM',
        actor: 'System (Reservation)',
        orderId: order.orderId,
      );
      expect(activated.details, containsPair('reservationId', 'res-1'));
    });

    test(
      're-seating an already linked booking adds no second creation',
      () async {
        await seedTable('5');
        await DatabaseCore.reservationBox!.add(booking());

        final first = await ActivateReservationTransaction.activate(
          reservationId: 'res-1',
          activatedBy: 'Nino',
        );
        final second = await ActivateReservationTransaction.activate(
          reservationId: 'res-1',
          activatedBy: 'Nino',
        );

        expect(second.orderId, first.orderId);
        expect(reportOf(first.orderId!).events, hasLength(1));
      },
    );
  });

  group('Transfer', () {
    test('a whole bill moving closes the source with TRANSFER_CLOSE', () async {
      await seedTable('7');
      await seedTable('12');
      final source = await OrderRepository.createOrder(
        tableNumbers: const ['7'],
        floor: 'first',
        createdBy: 'Nino',
        items: [line('ხინკალი', 1.5, 6)],
      );
      final destination = await OrderRepository.createOrder(
        tableNumbers: const ['12'],
        floor: 'first',
        createdBy: 'Nino',
        items: const [],
      );

      final result = await OrderItemTransfer.apply(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 6)],
        user: user,
        sourceLabel: 'მაგიდა 7',
        destinationLabel: 'მაგიდა 12',
      );
      expect(result.sourceLeftEmpty, isTrue);
      await OrderItemTransfer.releaseEmptiedOrder(
        source,
        user: user,
        destination: destination,
      );

      final sourceReport = reportOf(source.orderId);
      expect(sourceReport.events.map((e) => e.type), [
        AuditEventType.createWalkIn,
        AuditEventType.addItem,
        AuditEventType.moveItems,
        AuditEventType.transferClose,
      ]);
      expect(sourceReport.status, AuditReportStatus.closed);
      expect(sourceReport.locked, isTrue);
      final moved = sourceReport.events[2];
      expect(moved.details, containsPair('direction', 'OUT'));
      expect(moved.details, containsPair('toOrderId', destination.orderId));
      expect(moved.details, containsPair('toTableRefs', ['first/12']));
      expect(moved.details, containsPair('quantity', 6));
      expect(moved.details, containsPair('amount', 9.0));

      final destinationReport = reportOf(destination.orderId);
      expect(destinationReport.events.map((e) => e.type), [
        AuditEventType.createWalkIn,
        AuditEventType.moveItems,
      ]);
      expect(
        destinationReport.events.last.details,
        containsPair('direction', 'IN'),
      );
      expect(destinationReport.status, AuditReportStatus.open);

      // The floor and the money: source table free, no Sale, no revenue.
      expect(DatabaseCore.tableBox!.get('first-7')!.isReserved, isFalse);
      expect(
        DatabaseCore.tableBox!.get('first-12')!.activeOrderId,
        destination.orderId,
      );
      expect(DatabaseCore.salesBox!.isEmpty, isTrue);
      expect(
        OrderRepository.getOrder(source.orderId)!.statusEnum,
        OrderStatus.closed,
      );
    });
  });

  group('wire format', () {
    const newTypes = {
      AuditEventType.createWalkIn: 'CREATE_WALKIN',
      AuditEventType.createTakeaway: 'CREATE_TAKEAWAY',
      AuditEventType.applyPackage: 'APPLY_PACKAGE',
      AuditEventType.activateReservation: 'ACTIVATE_RESERVATION',
      AuditEventType.moveItems: 'MOVE_ITEMS',
      AuditEventType.transferClose: 'TRANSFER_CLOSE',
    };

    test('every new type round-trips through its stored string', () {
      for (final entry in newTypes.entries) {
        expect(auditEventTypeToString(entry.key), entry.value);
        expect(auditEventTypeFromString(entry.value), entry.key);
        expect(auditEventTypeFromString(entry.value.toLowerCase()), entry.key);
      }
    });

    test('a typed move is not re-inferred from its quantities', () {
      final event = AuditEvent.fromMap({
        'type': 'MOVE_ITEMS',
        'itemName': 'x',
        'previousQty': 0,
        'newQty': 3,
        'waiterId': 'n',
        'waiterName': 'n',
        'timestamp': '2026-09-04T12:00:00.000',
      });
      expect(event.type, AuditEventType.moveItems);
    });

    test('a type this build does not know still degrades by quantity', () {
      final event = AuditEvent.fromMap({
        'type': 'SOME_FUTURE_TYPE',
        'itemName': 'x',
        'previousQty': 0,
        'newQty': 3,
        'waiterId': 'n',
        'waiterName': 'n',
        'timestamp': '2026-09-04T12:00:00.000',
      });
      expect(event.type, AuditEventType.addItem);
    });
  });
}
