import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/audit/money_audit.dart';

/// Phase 3: money mutations that used to live only in the write-only log are
/// mirrored into the Order's visible report. The log entry is still written
/// (compatibility), the money itself is untouched, and a report locked by a
/// close takes exactly one accountability row for a Sale void.
void main() {
  late Directory tempDir;

  const businessDate = '2026-09-04';

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
    'mm_settings',
    'mm_sales',
    'mm_expenses',
    'mm_audit',
    'mm_tables',
    'mm_orders',
    'mm_users',
    'mm_reservations',
    'mm_journal',
  ];

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_money_mirror');
    Hive.init(tempDir.path);
    registerAdapters();
    Order.serviceFeeRateResolver = () => 0.0;
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('mm_settings');
    DatabaseCore.salesBox = await Hive.openBox('mm_sales');
    DatabaseCore.expenseBox = await Hive.openBox('mm_expenses');
    DatabaseCore.auditLogBox = await Hive.openBox('mm_audit');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('mm_tables');
    DatabaseCore.orderBox = await Hive.openBox<Order>('mm_orders');
    DatabaseCore.userBox = await Hive.openBox<User>('mm_users');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>(
      'mm_reservations',
    );
    DatabaseCore.closureJournalBox = await Hive.openBox('mm_journal');
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
    DatabaseCore.closureJournalBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<Order> seedOrder({double gross = 100}) async {
    await DatabaseCore.tableBox!.put(
      'first-7',
      TableModel(tableNumber: '7', floor: 'first'),
    );
    return OrderRepository.createOrder(
      tableNumbers: const ['7'],
      floor: 'first',
      createdBy: 'Nino',
      items: [
        OrderItem(
          itemKey: 'item',
          itemName: 'Item',
          unitPrice: gross,
          quantity: 1,
          total: gross,
        ),
      ],
    );
  }

  List<AuditEvent> eventsOfType(int orderId, AuditEventType type) =>
      AuditRepository.getAuditReport(
        orderId,
      )!.events.where((e) => e.type == type).toList();

  /// Append-only log rows with [action], decoded.
  List<Map<String, dynamic>> logRows(String action) => [
    for (final raw in DatabaseCore.auditLogBox!.values)
      if (raw is Map && raw['action'] == action)
        Map<String, dynamic>.from(jsonDecode(raw['data'] as String) as Map),
  ];

  test('an advance shows on the report as RECORD_ADVANCE, once', () async {
    final order = await seedOrder();

    await MoneyAudit.advanceRecorded(
      actorId: 'Giorgi',
      orderId: order.orderId,
      previousAmount: 0,
      newAmount: 50,
      businessDate: businessDate,
      receiptId: 'receipt-1',
    );
    // Re-saving the same amount is not a change.
    await MoneyAudit.advanceRecorded(
      actorId: 'Giorgi',
      orderId: order.orderId,
      previousAmount: 50,
      newAmount: 50,
      businessDate: businessDate,
      receiptId: 'receipt-1',
    );

    final events = eventsOfType(order.orderId, AuditEventType.recordAdvance);
    expect(events, hasLength(1));
    final event = events.single;
    expect(event.waiterId, 'Giorgi');
    expect(event.details, containsPair('previousAmount', 0.0));
    expect(event.details, containsPair('newAmount', 50.0));
    expect(event.details, containsPair('receiptId', 'receipt-1'));
    expect(event.details, containsPair('collectedOn', businessDate));
    expect(event.details, containsPair('source', 'POS'));
    expect(event.details, containsPair('actorId', 'Giorgi'));
    expect(event.details, containsPair('orderKind', 'WALK_IN'));
    // The write-only log still gets its row (compatibility duplicate), and
    // the receipt itself is not created here.
    expect(logRows(MoneyAuditAction.advanceRecorded), hasLength(1));
    expect(DatabaseCore.salesBox!.isEmpty, isTrue);
  });

  test('a manual adjustment is ADJUST_ORDER field=manualAdjustment', () async {
    final order = await seedOrder();

    await MoneyAudit.orderManualAdjustmentChanged(
      actorId: 'Giorgi',
      orderId: order.orderId,
      previousAdjustment: 0,
      newAdjustment: -5,
      previousTotal: 100,
      newTotal: 95,
    );

    final event = eventsOfType(
      order.orderId,
      AuditEventType.adjustOrder,
    ).single;
    expect(event.details, containsPair('field', 'manualAdjustment'));
    expect(event.details, containsPair('previousValue', 0.0));
    expect(event.details, containsPair('newValue', -5.0));
    expect(event.details, containsPair('previousTotal', 100.0));
    expect(event.details, containsPair('newTotal', 95.0));
    expect(event.details, containsPair('source', 'POS'));
    expect(
      logRows(MoneyAuditAction.orderManualAdjustmentChanged),
      hasLength(1),
    );
  });

  test('a service-fee change is ADJUST_ORDER field=serviceFee', () async {
    final order = await seedOrder();

    await MoneyAudit.orderServiceFeeChanged(
      actorId: 'mobile_manager',
      orderId: order.orderId,
      previousIncluded: true,
      newIncluded: false,
      previousPercent: 10,
      newPercent: 10,
      previousTotal: 110,
      newTotal: 100,
      source: AuditSource.manager,
    );
    // Nothing changed: nothing written.
    await MoneyAudit.orderServiceFeeChanged(
      actorId: 'mobile_manager',
      orderId: order.orderId,
      previousIncluded: false,
      newIncluded: false,
      previousTotal: 100,
      newTotal: 100,
      source: AuditSource.manager,
    );

    final events = eventsOfType(order.orderId, AuditEventType.adjustOrder);
    expect(events, hasLength(1));
    final event = events.single;
    expect(event.details, containsPair('field', 'serviceFee'));
    expect(event.details!['previousValue'], {
      'included': true,
      'percent': 10.0,
    });
    expect(event.details!['newValue'], {'included': false, 'percent': 10.0});
    expect(event.details, containsPair('source', 'MANAGER'));
    expect(event.details, containsPair('actorId', 'mobile_manager'));
  });

  test('voiding a Sale appends VOID_SALE to the locked report, once', () async {
    final order = await seedOrder();
    final result = await CloseTableTransaction.run(
      orderId: order.orderId,
      money: ClosureMoney.fromOrder(order, collectedNow: 100),
      paymentMethod: 'cash',
      tenderBreakdown: const {'cash': 100},
      closedById: 'Giorgi',
      isFiscal: true,
    );
    expect(result.outcome, ClosureOutcome.closed);
    final saleKey = SalesRepository.findSaleKeyByClosureId(result.closureId!);
    expect(saleKey, isNotNull);
    final reportBefore = AuditRepository.getAuditReport(order.orderId)!;
    expect(reportBefore.locked, isTrue);

    final voided = await SalesRepository.cancelSaleRecord(
      recordKey: saleKey,
      cancelledBy: 'Admin',
      reason: 'Wrong table',
    );
    final again = await SalesRepository.cancelSaleRecord(
      recordKey: saleKey,
      cancelledBy: 'Admin',
      reason: 'Wrong table',
    );

    expect(voided, SaleCancellationOutcome.cancelled);
    expect(again, SaleCancellationOutcome.alreadyCancelled);

    final report = AuditRepository.getAuditReport(order.orderId)!;
    // The report is still the closed, locked record of a settled Order; the
    // void is a row on it, not a reopening.
    expect(report.status, AuditReportStatus.closed);
    expect(report.locked, isTrue);
    final voids = report.events
        .where((e) => e.type == AuditEventType.voidSale)
        .toList();
    expect(voids, hasLength(1));
    final event = voids.single;
    expect(event.waiterId, 'Admin');
    expect(event.details, containsPair('saleId', saleKey.toString()));
    expect(event.details, containsPair('closureId', result.closureId));
    expect(event.details, containsPair('grossAmount', 100.0));
    expect(event.details, containsPair('reason', 'Wrong table'));
    expect(event.details, containsPair('saleBusinessDate', businessDate));
    expect(event.details, containsPair('source', 'POS'));
    expect(event.note, 'Wrong table');
    // It is not a cancelled Order.
    expect(
      report.events.where((e) => e.type == AuditEventType.cancelTable),
      isEmpty,
    );
    expect(DatabaseCore.orderBox!.values.single.status, 'closed');

    // The financial reversal is unchanged: flagged, kept, out of revenue.
    final sale = DatabaseCore.salesBox!.get(saleKey) as Map;
    expect(sale['isCancelled'], isTrue);
    expect(sale['restoredToOrder'], isNot(true));
    expect(SalesRepository.countsAsRevenue(sale), isFalse);
    expect(logRows(MoneyAuditAction.saleCancelled), hasLength(1));
  });

  test('mirrors never write Sale records or move money', () async {
    final order = await seedOrder();
    await MoneyAudit.advanceRecorded(
      actorId: 'Giorgi',
      orderId: order.orderId,
      previousAmount: 0,
      newAmount: 20,
      businessDate: businessDate,
    );
    await MoneyAudit.orderManualAdjustmentChanged(
      actorId: 'Giorgi',
      orderId: order.orderId,
      previousAdjustment: 0,
      newAdjustment: 3,
      previousTotal: 100,
      newTotal: 103,
    );
    expect(DatabaseCore.salesBox!.isEmpty, isTrue);
    expect(DatabaseCore.orderBox!.values.single.totalAmount, 100.0);
  });

  test(
    'a mirror for an unknown Order is skipped, the log row still lands',
    () async {
      await MoneyAudit.orderManualAdjustmentChanged(
        actorId: 'Giorgi',
        orderId: 999,
        previousAdjustment: 0,
        newAdjustment: 1,
        previousTotal: 10,
        newTotal: 11,
      );
      expect(AuditRepository.getAuditReport(999), isNull);
      expect(
        logRows(MoneyAuditAction.orderManualAdjustmentChanged),
        hasLength(1),
      );
    },
  );
}
