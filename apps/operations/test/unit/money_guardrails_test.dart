import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/audit/money_audit.dart';
import 'package:vynic/core/services/sync/pos_ingest_server.dart';

/// Money Integrity 1A: the guardrails around the mutations that move a number
/// the restaurant reports.
///
/// These run against a real (temp-dir) Hive instance, because every property
/// here is about what is actually written — a void that leaves the original
/// record intact, a date change that leaves an audit event behind, a refusal
/// that writes nothing at all.
void main() {
  late Directory tempDir;

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

  const today = '2026-09-01';
  const yesterday = '2026-08-31';

  Map<String, dynamic> sale({
    required int orderId,
    required String date,
    double total = 120.0,
  }) {
    return <String, dynamic>{
      'orderId': orderId,
      'tableNumbers': <String>['1'],
      'floor': 'first',
      'items': <Map<String, dynamic>>[],
      'totalAmount': total,
      'total': total,
      'paymentMethod': 'cash',
      'paymentBreakdown': <String, double>{'cash': total},
      'createdBy': 'waiter',
      'createdAt': '${date}T12:00:00.000',
      'closedAt': '${date}T13:00:00.000',
      'includeServiceFee': false,
      'discountAmount': 0.0,
      'advanceAmount': 0.0,
      'subtotalAmount': total,
      'manualAdjustmentAmount': 0.0,
      'date': date,
      'isCancelled': false,
      'isFiscal': true,
      'restoredToOrder': false,
    };
  }

  List<Map<String, dynamic>> auditEvents() {
    return DatabaseCore.auditLogBox!.values
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
  }

  Map<String, dynamic>? auditEvent(String action) {
    for (final event in auditEvents()) {
      if (event['action'] == action) return event;
    }
    return null;
  }

  Map<String, dynamic> auditData(Map<String, dynamic> event) {
    final raw = event['data'];
    return raw is String
        ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
        : Map<String, dynamic>.from(raw as Map);
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_money_guardrails');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('mg_settings');
    DatabaseCore.salesBox = await Hive.openBox('mg_sales');
    DatabaseCore.expenseBox = await Hive.openBox('mg_expenses');
    DatabaseCore.auditLogBox = await Hive.openBox('mg_audit');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('mg_tables');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>(
      'mg_reservations',
    );
    await DatabaseCore.settingsBox!.put('currentDate', '${today}T00:00:00.000');
  });

  tearDown(() async {
    for (final name in const [
      'mg_settings',
      'mg_sales',
      'mg_expenses',
      'mg_audit',
      'mg_tables',
      'mg_reservations',
    ]) {
      await Hive.deleteBoxFromDisk(name);
    }
    DatabaseCore.settingsBox = null;
    DatabaseCore.salesBox = null;
    DatabaseCore.expenseBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.reservationBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('sale cancellation', () {
    test('refuses without a reason and writes nothing', () async {
      final key = await DatabaseCore.salesBox!.add(
        sale(orderId: 1, date: today),
      );

      final outcome = await SalesRepository.cancelSaleRecord(
        recordKey: key,
        cancelledBy: 'manager',
        reason: '   ',
      );

      expect(outcome, SaleCancellationOutcome.reasonRequired);
      final stored = Map<String, dynamic>.from(
        DatabaseCore.salesBox!.get(key) as Map,
      );
      expect(stored['isCancelled'], isFalse);
      expect(auditEvents(), isEmpty);
    });

    test('refuses without a named actor', () async {
      final key = await DatabaseCore.salesBox!.add(
        sale(orderId: 1, date: today),
      );

      final outcome = await SalesRepository.cancelSaleRecord(
        recordKey: key,
        cancelledBy: '',
        reason: 'wrong table',
      );

      expect(outcome, SaleCancellationOutcome.reasonRequired);
      expect(
        Map<String, dynamic>.from(
          DatabaseCore.salesBox!.get(key) as Map,
        )['isCancelled'],
        isFalse,
      );
    });

    test(
      'voids today\'s sale, keeps the record, and records actor and reason',
      () async {
        final key = await DatabaseCore.salesBox!.add(
          sale(orderId: 7, date: today, total: 88.5),
        );

        final outcome = await SalesRepository.cancelSaleRecord(
          recordKey: key,
          cancelledBy: 'manager',
          reason: 'duplicate check',
        );

        expect(outcome, SaleCancellationOutcome.cancelled);
        final stored = Map<String, dynamic>.from(
          DatabaseCore.salesBox!.get(key) as Map,
        );
        expect(stored['isCancelled'], isTrue);
        expect(stored['cancelledBy'], 'manager');
        expect(stored['cancellationReason'], 'duplicate check');
        // The original figures survive the void — nothing is erased.
        expect(stored['totalAmount'], 88.5);
        expect(stored['orderId'], 7);
        expect(stored['paymentBreakdown'], isNotNull);

        final event = auditEvent(MoneyAuditAction.saleCancelled);
        expect(event, isNotNull);
        expect(event!['userId'], 'manager');
        final data = auditData(event);
        expect(data['orderId'], 7);
        expect(data['businessDate'], today);
        expect(data['totalAmount'], 88.5);
        expect(data['reason'], 'duplicate check');
        expect(data['historical'], isFalse);
      },
    );

    test('refuses a closed business day without support authorization, '
        'leaving the sale and the daily total untouched', () async {
      final key = await DatabaseCore.salesBox!.add(
        sale(orderId: 9, date: yesterday),
      );

      final outcome = await SalesRepository.cancelSaleRecord(
        recordKey: key,
        cancelledBy: 'manager',
        reason: 'owner asked',
      );

      expect(outcome, SaleCancellationOutcome.historicalNotPermitted);
      final stored = Map<String, dynamic>.from(
        DatabaseCore.salesBox!.get(key) as Map,
      );
      expect(stored['isCancelled'], isFalse);
      expect(stored.containsKey('cancelledBy'), isFalse);
      expect(auditEvents(), isEmpty);
    });

    test('allows a closed business day only with support authorization, '
        'and marks the event historical', () async {
      final key = await DatabaseCore.salesBox!.add(
        sale(orderId: 9, date: yesterday),
      );

      final outcome = await SalesRepository.cancelSaleRecord(
        recordKey: key,
        cancelledBy: 'support',
        reason: 'double-charged, refunded in cash',
        allowHistorical: true,
      );

      expect(outcome, SaleCancellationOutcome.cancelled);
      final data = auditData(auditEvent(MoneyAuditAction.saleCancelled)!);
      expect(data['historical'], isTrue);
      expect(data['businessDate'], yesterday);
    });

    test('a second void is refused rather than re-recorded', () async {
      final key = await DatabaseCore.salesBox!.add(
        sale(orderId: 3, date: today),
      );
      await SalesRepository.cancelSaleRecord(
        recordKey: key,
        cancelledBy: 'manager',
        reason: 'first',
      );

      final outcome = await SalesRepository.cancelSaleRecord(
        recordKey: key,
        cancelledBy: 'someone else',
        reason: 'second',
      );

      expect(outcome, SaleCancellationOutcome.alreadyCancelled);
      final stored = Map<String, dynamic>.from(
        DatabaseCore.salesBox!.get(key) as Map,
      );
      expect(stored['cancelledBy'], 'manager');
      expect(stored['cancellationReason'], 'first');
      expect(
        auditEvents()
            .where((e) => e['action'] == MoneyAuditAction.saleCancelled)
            .length,
        1,
      );
    });
  });

  group('business date', () {
    test('refuses to move without a reason', () async {
      final outcome = await BusinessDayRepository.setCurrentDate(
        DateTime.parse('2026-09-02'),
        actorId: 'manager',
      );

      expect(outcome, BusinessDateChangeOutcome.reasonRequired);
      expect(
        BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate()),
        today,
      );
      expect(auditEvents(), isEmpty);
    });

    test('moves forward with a reason and audits actor, from, to', () async {
      final outcome = await BusinessDayRepository.setCurrentDate(
        DateTime.parse('2026-09-02'),
        actorId: 'manager',
        reason: 'day was closed twice by mistake',
      );

      expect(outcome, BusinessDateChangeOutcome.changed);
      expect(
        BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate()),
        '2026-09-02',
      );

      final event = auditEvent(MoneyAuditAction.businessDateChanged);
      expect(event, isNotNull);
      expect(event!['userId'], 'manager');
      final data = auditData(event);
      expect(data['previousDate'], today);
      expect(data['newDate'], '2026-09-02');
      expect(data['reason'], 'day was closed twice by mistake');
      expect(data['backdated'], isFalse);
    });

    test('refuses to backdate into a closed period without support '
        'authorization', () async {
      final outcome = await BusinessDayRepository.setCurrentDate(
        DateTime.parse(yesterday),
        actorId: 'manager',
        reason: 'need to add yesterday\'s sale',
      );

      expect(outcome, BusinessDateChangeOutcome.backdateNotPermitted);
      expect(
        BusinessDayRepository.dateKey(BusinessDayRepository.getCurrentDate()),
        today,
      );
      expect(auditEvents(), isEmpty);
    });

    test('backdates with support authorization and flags the event', () async {
      final outcome = await BusinessDayRepository.setCurrentDate(
        DateTime.parse(yesterday),
        actorId: 'support',
        reason: 'terminal ran a day ahead after a clock reset',
        allowBackdate: true,
      );

      expect(outcome, BusinessDateChangeOutcome.changed);
      final data = auditData(auditEvent(MoneyAuditAction.businessDateChanged)!);
      expect(data['backdated'], isTrue);
      expect(data['newDate'], yesterday);
    });

    test('re-selecting the current date records nothing', () async {
      final outcome = await BusinessDayRepository.setCurrentDate(
        DateTime.parse(today),
        actorId: 'manager',
        reason: 'no-op',
      );

      expect(outcome, BusinessDateChangeOutcome.unchanged);
      expect(auditEvents(), isEmpty);
    });
  });

  group('order money mutations', () {
    test('a discount change records actor and both totals', () async {
      await MoneyAudit.orderDiscountChanged(
        actorId: 'supervisor',
        orderId: 12,
        previousDiscount: 0.0,
        newDiscount: 15.0,
        previousTotal: 100.0,
        newTotal: 85.0,
      );

      final event = auditEvent(MoneyAuditAction.orderDiscountChanged);
      expect(event, isNotNull);
      expect(event!['userId'], 'supervisor');
      final data = auditData(event);
      expect(data['orderId'], 12);
      expect(data['previousDiscount'], 0.0);
      expect(data['newDiscount'], 15.0);
      expect(data['previousTotal'], 100.0);
      expect(data['newTotal'], 85.0);
    });

    test('a manual adjustment records actor and both totals', () async {
      await MoneyAudit.orderManualAdjustmentChanged(
        actorId: 'manager',
        orderId: 12,
        previousAdjustment: 0.0,
        newAdjustment: -20.0,
        previousTotal: 100.0,
        newTotal: 80.0,
      );

      final data = auditData(
        auditEvent(MoneyAuditAction.orderManualAdjustmentChanged)!,
      );
      expect(data['previousAdjustment'], 0.0);
      expect(data['newAdjustment'], -20.0);
      expect(data['newTotal'], 80.0);
    });

    test('a service-fee percentage override is recorded even when the fee '
        'stays on', () async {
      await MoneyAudit.orderServiceFeeChanged(
        actorId: 'manager',
        orderId: 12,
        previousIncluded: true,
        newIncluded: true,
        previousPercent: 10.0,
        newPercent: 5.0,
        previousTotal: 110.0,
        newTotal: 105.0,
      );

      final data = auditData(
        auditEvent(MoneyAuditAction.orderServiceFeeChanged)!,
      );
      expect(data['previousPercent'], 10.0);
      expect(data['newPercent'], 5.0);
    });

    test('re-saving an unchanged value writes no event', () async {
      await MoneyAudit.orderDiscountChanged(
        actorId: 'manager',
        orderId: 12,
        previousDiscount: 15.0,
        newDiscount: 15.0,
        previousTotal: 85.0,
        newTotal: 85.0,
      );
      await MoneyAudit.orderServiceFeeChanged(
        actorId: 'manager',
        orderId: 12,
        previousIncluded: true,
        newIncluded: true,
        previousPercent: 10.0,
        newPercent: 10.0,
        previousTotal: 110.0,
        newTotal: 110.0,
      );
      await MoneyAudit.reportCostAssumptionChanged(
        actorId: 'manager',
        field: 'leaseCost',
        scope: 'default',
        previousValue: 13000.0,
        newValue: 13000.0,
      );

      expect(auditEvents(), isEmpty);
    });
  });

  group('expense identity', () {
    test('backfills an id onto a record restored without one', () async {
      await DatabaseCore.expenseBox!.add(<String, dynamic>{
        'description': 'gas',
        'amount': 40.0,
        'category': 'utilities',
        'date': today,
      });
      await DatabaseCore.expenseBox!.add(<String, dynamic>{
        'id': 'already-has-one',
        'description': 'napkins',
        'amount': 12.0,
        'category': 'supplies',
        'date': today,
      });

      final backfilled = await SalesRepository.ensureExpenseIdentities();

      expect(backfilled, 1);
      final ids = SalesRepository.getAllExpenseRecords()
          .map((e) => e['id'] as String?)
          .toList();
      expect(ids.every((id) => id != null && id.isNotEmpty), isTrue);
      expect(ids, contains('already-has-one'));

      // Second run changes nothing — the ids are the identity, so re-running
      // must not hand the same expense a new one.
      expect(await SalesRepository.ensureExpenseIdentities(), 0);
      expect(
        SalesRepository.getAllExpenseRecords()
            .map((e) => e['id'] as String?)
            .toSet(),
        ids.toSet(),
      );
    });
  });

  group('legacy POS ingest authentication', () {
    test('an unprovisioned terminal refuses every caller', () {
      expect(
        PosIngestServer.isRequestAuthorized(
          expectedKey: null,
          providedKey: null,
        ),
        isFalse,
      );
      expect(
        PosIngestServer.isRequestAuthorized(
          expectedKey: '',
          providedKey: 'anything',
        ),
        isFalse,
      );
      expect(
        PosIngestServer.isRequestAuthorized(
          expectedKey: '   ',
          providedKey: 'anything',
        ),
        isFalse,
      );
    });

    test('a missing or wrong key is refused', () {
      expect(
        PosIngestServer.isRequestAuthorized(
          expectedKey: 'secret',
          providedKey: null,
        ),
        isFalse,
      );
      expect(
        PosIngestServer.isRequestAuthorized(
          expectedKey: 'secret',
          providedKey: '',
        ),
        isFalse,
      );
      expect(
        PosIngestServer.isRequestAuthorized(
          expectedKey: 'secret',
          providedKey: 'other',
        ),
        isFalse,
      );
    });

    test('the provisioned key still authenticates the existing flow', () {
      expect(
        PosIngestServer.isRequestAuthorized(
          expectedKey: 'secret',
          providedKey: 'secret',
        ),
        isTrue,
      );
      expect(
        PosIngestServer.isRequestAuthorized(
          expectedKey: 'secret',
          providedKey: '  secret  ',
        ),
        isTrue,
      );
    });
  });
}
