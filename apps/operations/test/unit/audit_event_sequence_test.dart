import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/transactions/close_day_transaction.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/sync/audit_sync_state.dart';

/// Audit storage foundation: the order of a report's events is a number the
/// POS assigns, not something re-derived by sorting a timestamp that ties.
void main() {
  late Directory tempDir;

  const businessDate = '2026-09-05';

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
    'seq_settings',
    'seq_sales',
    'seq_expenses',
    'seq_audit',
    'seq_tables',
    'seq_orders',
    'seq_users',
    'seq_reservations',
  ];

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_audit_sequence');
    Hive.init(tempDir.path);
    registerAdapters();
    Order.serviceFeeRateResolver = () => 0.0;
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('seq_settings');
    DatabaseCore.salesBox = await Hive.openBox('seq_sales');
    DatabaseCore.expenseBox = await Hive.openBox('seq_expenses');
    DatabaseCore.auditLogBox = await Hive.openBox('seq_audit');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('seq_tables');
    DatabaseCore.orderBox = await Hive.openBox<Order>('seq_orders');
    DatabaseCore.userBox = await Hive.openBox<User>('seq_users');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>(
      'seq_reservations',
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

  OrderItem line(String name, int qty) => OrderItem(
    itemKey: name,
    itemName: name,
    unitPrice: 1,
    quantity: qty,
    total: qty.toDouble(),
  );

  AuditReport reportOf(int orderId) {
    final report = AuditRepository.getAuditReport(orderId);
    expect(report, isNotNull, reason: 'order $orderId has no audit report');
    return report!;
  }

  List<int?> sequencesOf(AuditReport report) =>
      report.events.map((event) => event.sequence).toList();

  List<AuditEventType> typesOf(AuditReport report) =>
      report.events.map((event) => event.type).toList();

  /// The exact round trip a report makes on its way to Cloud: Hive map ->
  /// JSON on the wire -> the map the backend reads.
  Map<String, dynamic> wirePayload(AuditReport report) {
    final stored = DatabaseCore.auditLogBox!.get(report.reportId) as Map;
    final decoded = AuditReport.fromMap(Map<dynamic, dynamic>.from(stored));
    return jsonDecode(jsonEncode(decoded.toMap())) as Map<String, dynamic>;
  }

  /// What the backend's `posOwnsOrder` check does with a payload.
  List<int> wireSequences(Map<String, dynamic> payload) => [
    for (final event in payload['events'] as List)
      (event as Map<String, dynamic>)['sequence'] as int,
  ];

  group('creation order', () {
    test(
      'CREATE_WALKIN stays first through 100 same-instant initial lines',
      () async {
        await seedTable('7');

        // 33 was where the old timestamp sort stopped being stable, so 100 is
        // well past the point the previous implementation reordered.
        final order = await OrderRepository.createOrder(
          tableNumbers: const ['7'],
          floor: 'first',
          createdBy: 'Nino',
          items: [for (var i = 0; i < 100; i++) line('Item $i', 1)],
        );

        final report = reportOf(order.orderId);
        expect(report.events, hasLength(101));
        expect(report.events.first.type, AuditEventType.createWalkIn);
        expect(sequencesOf(report), List<int>.generate(101, (i) => i));

        // Every event was written at one instant on purpose. If time were the
        // ordering key there would be nothing here to order by.
        final instants = report.events
            .map((event) => event.timestamp)
            .toSet();
        expect(instants, hasLength(1));

        // Re-read from Hive: deserialization must not reorder.
        final reloaded = reportOf(order.orderId);
        expect(reloaded.events.first.type, AuditEventType.createWalkIn);
        expect(sequencesOf(reloaded), sequencesOf(report));
        expect(typesOf(reloaded), typesOf(report));

        // The wire payload the backend ingests carries the same numbering, so
        // Cloud `seq` is the POS's sequence rather than an arrival position.
        final payload = wirePayload(report);
        expect(wireSequences(payload), List<int>.generate(101, (i) => i));
        expect(
          (payload['events'] as List).first['type'],
          'CREATE_WALKIN',
        );

        // Newest-first display is the same timeline reversed, not a re-sort.
        expect(reloaded.sortedEvents.last.type, AuditEventType.createWalkIn);
      },
    );

    test('the audit screens number the creation event as step 1', () async {
      await seedTable('15');
      final order = await OrderRepository.createOrder(
        tableNumbers: const ['15'],
        floor: 'first',
        createdBy: 'Nino',
        items: [line('Khinkali', 3)],
      );

      // Both audit screens list a report newest-first and label each row with
      // the event's own ordinal, shown one-based. Numbering the rows instead
      // counts the timeline backwards and prints the creation event last.
      final shown = reportOf(order.orderId).sortedEvents;
      String labelOf(int index) {
        final ordinal = shown[index].sequence ?? (shown.length - 1 - index);
        return '${ordinal + 1}. ${auditEventTypeToString(shown[index].type)}';
      }

      expect(labelOf(0), '2. ADD_ITEM');
      expect(labelOf(shown.length - 1), '1. CREATE_WALKIN');
    });

    test('a settled report keeps one revision across reads', () async {
      await seedTable('8');
      final order = await OrderRepository.createOrder(
        tableNumbers: const ['8'],
        floor: 'first',
        createdBy: 'Nino',
        items: [for (var i = 0; i < 60; i++) line('Item $i', 1)],
      );

      final first = AuditSyncState.revisionOf(reportOf(order.orderId));
      final second = AuditSyncState.revisionOf(reportOf(order.orderId));
      expect(second, first);
    });
  });

  group('appending', () {
    test('new events continue the sequence', () async {
      await seedTable('9');
      final order = await OrderRepository.createOrder(
        tableNumbers: const ['9'],
        floor: 'first',
        createdBy: 'Nino',
        items: [line('Khinkali', 3)],
      );

      // seq 0 CREATE_WALKIN, seq 1 ADD_ITEM
      expect(sequencesOf(reportOf(order.orderId)), [0, 1]);

      await AuditRepository.appendOrderAuditEvents(
        orderId: order.orderId,
        events: [
          AuditEvent(
            type: AuditEventType.recordAdvance,
            itemName: 'ORDER',
            previousQty: 0,
            newQty: 0,
            waiterId: 'Nino',
            waiterName: 'Nino',
            timestamp: order.createdAt,
          ),
          AuditEvent(
            type: AuditEventType.close,
            itemName: 'ORDER',
            previousQty: 0,
            newQty: 0,
            waiterId: 'Nino',
            waiterName: 'Nino',
            timestamp: order.createdAt,
          ),
        ],
      );

      final report = reportOf(order.orderId);
      expect(sequencesOf(report), [0, 1, 2, 3]);
      expect(typesOf(report), [
        AuditEventType.createWalkIn,
        AuditEventType.addItem,
        AuditEventType.recordAdvance,
        AuditEventType.close,
      ]);
    });

    test(
      'an event stamped earlier than the report still lands last',
      () async {
        await seedTable('10');
        final order = await OrderRepository.createOrder(
          tableNumbers: const ['10'],
          floor: 'first',
          createdBy: 'Nino',
          items: [line('Khinkali', 1)],
        );

        // A backdated clock must not rewrite what already happened.
        await AuditRepository.appendOrderAuditEvents(
          orderId: order.orderId,
          events: [
            AuditEvent(
              type: AuditEventType.adjustOrder,
              itemName: 'ORDER',
              previousQty: 0,
              newQty: 0,
              waiterId: 'Nino',
              waiterName: 'Nino',
              timestamp: order.createdAt.subtract(const Duration(hours: 3)),
            ),
          ],
        );

        final report = reportOf(order.orderId);
        expect(report.events.last.type, AuditEventType.adjustOrder);
        expect(report.events.last.sequence, 2);
        expect(report.events.first.type, AuditEventType.createWalkIn);
      },
    );

    test('close, restore and re-close keep climbing', () async {
      await seedTable('11');
      final order = await OrderRepository.createOrder(
        tableNumbers: const ['11'],
        floor: 'first',
        createdBy: 'Nino',
        items: [line('Khinkali', 1)],
      );

      AuditEvent closeEvent(String closureId) => AuditEvent(
        type: AuditEventType.close,
        itemName: 'ORDER',
        previousQty: 0,
        newQty: 0,
        waiterId: 'Nino',
        waiterName: 'Nino',
        timestamp: order.createdAt,
        details: <String, dynamic>{'closureId': closureId},
      );

      await AuditRepository.finalizeOrderClosureAudit(
        orderId: order.orderId,
        closingEvent: closeEvent('closure-a'),
        closedById: 'Nino',
        closedByName: 'Nino',
      );
      expect(sequencesOf(reportOf(order.orderId)), [0, 1, 2]);
      expect(reportOf(order.orderId).locked, isTrue);

      await AuditRepository.reopenOrderAuditReport(
        orderId: order.orderId,
        restoreEvent: AuditEvent(
          type: AuditEventType.restore,
          itemName: 'ORDER',
          previousQty: 0,
          newQty: 0,
          waiterId: 'Nino',
          waiterName: 'Nino',
          timestamp: order.createdAt,
          details: const <String, dynamic>{'originalClosureId': 'closure-a'},
        ),
      );

      await AuditRepository.finalizeOrderClosureAudit(
        orderId: order.orderId,
        closingEvent: closeEvent('closure-b'),
        closedById: 'Nino',
        closedByName: 'Nino',
      );

      final report = reportOf(order.orderId);
      expect(sequencesOf(report), [0, 1, 2, 3, 4]);
      expect(typesOf(report), [
        AuditEventType.createWalkIn,
        AuditEventType.addItem,
        AuditEventType.close,
        AuditEventType.restore,
        AuditEventType.close,
      ]);
    });

    test('a redelivered restore adds neither event nor sequence', () async {
      await seedTable('12');
      final order = await OrderRepository.createOrder(
        tableNumbers: const ['12'],
        floor: 'first',
        createdBy: 'Nino',
        items: [line('Khinkali', 1)],
      );

      AuditEvent restore() => AuditEvent(
        type: AuditEventType.restore,
        itemName: 'ORDER',
        previousQty: 0,
        newQty: 0,
        waiterId: 'Nino',
        waiterName: 'Nino',
        timestamp: order.createdAt,
        details: const <String, dynamic>{'originalClosureId': 'closure-a'},
      );

      await AuditRepository.reopenOrderAuditReport(
        orderId: order.orderId,
        restoreEvent: restore(),
      );
      final afterFirst = sequencesOf(reportOf(order.orderId));

      // Crash recovery or a retried command replays the same restore.
      await AuditRepository.reopenOrderAuditReport(
        orderId: order.orderId,
        restoreEvent: restore(),
      );

      expect(sequencesOf(reportOf(order.orderId)), afterFirst);
      expect(afterFirst, [0, 1, 2]);
      expect(
        typesOf(reportOf(order.orderId)).where(
          (type) => type == AuditEventType.restore,
        ),
        hasLength(1),
      );
    });
  });

  group('legacy rows', () {
    /// A report exactly as a build predating sequences wrote it: no
    /// `sequence` key anywhere, all events at one instant.
    Map<String, dynamic> legacyStoredReport() {
      final at = DateTime(2026, 9, 1, 12).toIso8601String();
      return <String, dynamic>{
        'reportId': 'audit_report_order_4242',
        'orderId': 4242,
        'tableNumbers': <String>['5'],
        'floor': 'first',
        'openedById': 'Nino',
        'openedByName': 'Nino',
        'openedAt': at,
        'status': 'OPEN',
        'locked': false,
        'updatedAt': at,
        'events': <Map<String, dynamic>>[
          {
            'type': 'CREATE_WALKIN',
            'itemName': 'ORDER',
            'previousQty': 0,
            'newQty': 0,
            'waiterId': 'Nino',
            'waiterName': 'Nino',
            'timestamp': at,
          },
          for (var i = 0; i < 40; i++)
            {
              'type': 'ADD_ITEM',
              'itemName': 'Item $i',
              'previousQty': 0,
              'newQty': 1,
              'waiterId': 'Nino',
              'waiterName': 'Nino',
              'timestamp': at,
            },
        ],
      };
    }

    test('load safely and get a deterministic compatibility order', () async {
      await DatabaseCore.auditLogBox!.put(
        'audit_report_order_4242',
        legacyStoredReport(),
      );

      final report = reportOf(4242);
      expect(report.events, hasLength(41));
      // Stored array order is the only evidence of the order, so it is kept.
      expect(report.events.first.type, AuditEventType.createWalkIn);
      expect(sequencesOf(report), List<int>.generate(41, (i) => i));
      expect(report.events[1].itemName, 'Item 0');
      expect(report.events.last.itemName, 'Item 39');

      // Deterministic: two reads agree, so the revision settles instead of
      // making the report look dirty forever.
      final again = reportOf(4242);
      expect(sequencesOf(again), sequencesOf(report));
      expect(
        AuditSyncState.revisionOf(again),
        AuditSyncState.revisionOf(report),
      );
    });

    test('the stored row is not rewritten until it is written', () async {
      await DatabaseCore.auditLogBox!.put(
        'audit_report_order_4242',
        legacyStoredReport(),
      );
      reportOf(4242);

      final stored = DatabaseCore.auditLogBox!.get('audit_report_order_4242')
          as Map;
      final storedEvents = (stored['events'] as List).cast<Map>();
      expect(
        storedEvents.every((event) => !event.containsKey('sequence')),
        isTrue,
        reason: 'reading a legacy report must not rewrite history eagerly',
      );

      // The next legitimate append persists the numbering.
      await AuditRepository.appendOrderAuditEvents(
        orderId: 4242,
        events: [
          AuditEvent(
            type: AuditEventType.adjustOrder,
            itemName: 'ORDER',
            previousQty: 0,
            newQty: 0,
            waiterId: 'Nino',
            waiterName: 'Nino',
            timestamp: DateTime(2026, 9, 1, 13),
          ),
        ],
      );

      final rewritten =
          (DatabaseCore.auditLogBox!.get('audit_report_order_4242')
              as Map)['events'] as List;
      expect(
        rewritten.cast<Map>().every((event) => event.containsKey('sequence')),
        isTrue,
      );
      expect(sequencesOf(reportOf(4242)), List<int>.generate(42, (i) => i));
    });

    test('a legacy report still reaches the wire with sequences', () async {
      await DatabaseCore.auditLogBox!.put(
        'audit_report_order_4242',
        legacyStoredReport(),
      );

      final payload = wirePayload(reportOf(4242));
      expect(wireSequences(payload), List<int>.generate(41, (i) => i));
      expect((payload['events'] as List).first['type'], 'CREATE_WALKIN');
    });
  });

  group('durability', () {
    test('sequences survive a backup-shaped JSON round trip', () async {
      await seedTable('13');
      final order = await OrderRepository.createOrder(
        tableNumbers: const ['13'],
        floor: 'first',
        createdBy: 'Nino',
        items: [for (var i = 0; i < 40; i++) line('Item $i', 1)],
      );
      final before = reportOf(order.orderId);

      // Backup writes the raw box value as JSON and restore puts it back
      // under the same key; this is that trip.
      final raw = DatabaseCore.auditLogBox!.get(before.reportId) as Map;
      final restored = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
      await DatabaseCore.auditLogBox!.clear();
      await DatabaseCore.auditLogBox!.put(before.reportId, restored);

      final after = reportOf(order.orderId);
      expect(sequencesOf(after), sequencesOf(before));
      expect(typesOf(after), typesOf(before));
      expect(after.events.first.type, AuditEventType.createWalkIn);
      expect(
        AuditSyncState.revisionOf(after),
        AuditSyncState.revisionOf(before),
      );
    });

    test(
      'Close Day removes the operational Order and keeps the timeline',
      () async {
        await seedTable('14');
        final order = await OrderRepository.createOrder(
          tableNumbers: const ['14'],
          floor: 'first',
          createdBy: 'Nino',
          items: [line('Khinkali', 2)],
          source: AuditSource.pos,
        );

        await AuditRepository.finalizeOrderClosureAudit(
          orderId: order.orderId,
          closingEvent: AuditEvent(
            type: AuditEventType.close,
            itemName: 'ORDER',
            previousQty: 0,
            newQty: 0,
            waiterId: 'Nino',
            waiterName: 'Nino',
            timestamp: order.createdAt,
            details: const <String, dynamic>{'closureId': 'closure-a'},
          ),
          closedById: 'Nino',
          closedByName: 'Nino',
        );
        await OrderRepository.updateOrderStatus(
          orderId: order.orderId,
          status: 'closed',
        );

        final before = reportOf(order.orderId);
        expect(before.status, AuditReportStatus.closed);
        final sequencesBefore = sequencesOf(before);

        expect(await CloseDayTransaction.run(), isTrue);

        // The operational row is gone; its history is not.
        expect(OrderRepository.getOrder(order.orderId), isNull);
        final after = reportOf(order.orderId);
        expect(after.status, AuditReportStatus.closed);
        expect(after.events, hasLength(before.events.length));
        expect(sequencesOf(after), sequencesBefore);
        expect(typesOf(after), typesOf(before));
      },
    );
  });
}
