import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/repositories/closure_journal_repository.dart';
import 'package:vynic/core/database/repositories/order_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/audit_report.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/reservation_status.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/pos/closure_recovery_service.dart';

/// Regression specifications produced by the Closure + Payment + Audit audit.
///
/// These tests intentionally state the correct domain contract. They are not
/// changed to bless known-bad current behaviour. In particular, a successful
/// close must never be represented by the cancellation-only `CANCEL_TABLE`
/// event, and recovery/restore must leave a complete lifecycle trail.
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
    if (!Hive.isAdapterRegistered(9))
      Hive.registerAdapter(ReservationAdapter());
    if (!Hive.isAdapterRegistered(15))
      Hive.registerAdapter(SaleRecordAdapter());
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SaleRecordItemAdapter());
    }
  }

  Future<Order> seedOrder({
    required int orderId,
    double gross = 100,
    double advance = 0,
    String floor = 'first',
    String? tableNumber,
    bool package = false,
  }) async {
    final table =
        tableNumber ?? (floor == 'takeaway' ? 'TA-$orderId' : '$orderId');
    final order = Order(
      orderId: orderId,
      tableNumbers: [table],
      floor: floor,
      items: package
          ? const []
          : [
              OrderItem(
                itemKey: 'item-$orderId',
                itemName: 'Item $orderId',
                unitPrice: gross,
                quantity: 1,
                total: gross,
              ),
            ],
      totalAmount: gross,
      createdAt: DateTime.parse('${businessDate}T12:00:00'),
      createdBy: 'waiter',
      status: 'served',
    );
    if (package) {
      order.packageId = 'package-$orderId';
      order.packageName = 'Package $orderId';
      order.packageGuestCount = 10;
      order.packageUnitPrice = gross / 10;
      order.packagePrice = gross;
      order.packageItems = [
        OrderItem(
          itemKey: 'package-item-$orderId',
          itemName: 'Package item $orderId',
          unitPrice: 5,
          quantity: 2,
          total: 10,
        ),
      ];
    }
    if (advance > 0) {
      order.advanceAmount = advance;
      order.advanceCollectedOn = businessDate;
    }
    order.recalculateTotal(serviceFeeRate: 0);
    await DatabaseCore.orderBox!.put(orderId, order);
    return order;
  }

  Future<void> seedOccupiedTable(Order order, {String? reservationId}) async {
    final table = TableModel(
      tableNumber: order.tableNumbers.single,
      floor: order.floor,
    )..reserve('waiter', order.orderId, reservationId: reservationId);
    await DatabaseCore.tableBox!.put(
      '${order.floor}-${order.tableNumbers.single}',
      table,
    );
  }

  Map<String, dynamic> saleFor(int orderId) =>
      SalesRepository.getSalesForDate(businessDate).firstWhere(
        (sale) => sale['recordType'] == 'sale' && sale['orderId'] == orderId,
      );

  double breakdownTotal(Map<String, dynamic> breakdown) => breakdown.values
      .fold<double>(0, (sum, value) => sum + (value as num).toDouble());

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_closure_audit');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('cai_settings');
    DatabaseCore.salesBox = await Hive.openBox('cai_sales');
    DatabaseCore.auditLogBox = await Hive.openBox('cai_audit');
    DatabaseCore.orderBox = await Hive.openBox<Order>('cai_orders');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('cai_tables');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>('cai_res');
    DatabaseCore.closureJournalBox = await Hive.openBox('cai_journal');
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      '${businessDate}T00:00:00.000',
    );
    await DatabaseCore.settingsBox!.put('serviceFeePercent', 0.0);
    Order.serviceFeeRateResolver = () => 0.0;
  });

  tearDown(() async {
    Order.serviceFeeRateResolver = null;
    for (final name in const [
      'cai_settings',
      'cai_sales',
      'cai_audit',
      'cai_orders',
      'cai_tables',
      'cai_res',
      'cai_journal',
    ]) {
      await Hive.deleteBoxFromDisk(name);
    }
    DatabaseCore.settingsBox = null;
    DatabaseCore.salesBox = null;
    DatabaseCore.auditLogBox = null;
    DatabaseCore.orderBox = null;
    DatabaseCore.tableBox = null;
    DatabaseCore.reservationBox = null;
    DatabaseCore.closureJournalBox = null;
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test(
    'fiscal close matrix preserves money and never emits cancellation',
    () async {
      final scenarios =
          <
            ({
              String name,
              String method,
              Map<String, double> tender,
              double advance,
              String floor,
              bool package,
              bool reservation,
            })
          >[
            (
              name: 'walk-in cash',
              method: 'cash',
              tender: const {'cash': 100},
              advance: 0,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'walk-in card',
              method: 'card-tbc',
              tender: const {'card-tbc': 100},
              advance: 0,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'walk-in split',
              method: 'split',
              tender: const {'cash': 40, 'card-bog': 60},
              advance: 0,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'advance plus cash',
              method: 'cash',
              tender: const {'cash': 80},
              advance: 20,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'advance plus card',
              method: 'card-tbc',
              tender: const {'card-tbc': 80},
              advance: 20,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'advance plus split',
              method: 'split',
              tender: const {'cash': 30, 'card-bog': 50},
              advance: 20,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'takeaway cash',
              method: 'cash',
              tender: const {'cash': 100},
              advance: 0,
              floor: 'takeaway',
              package: false,
              reservation: false,
            ),
            (
              name: 'takeaway card',
              method: 'card-bog',
              tender: const {'card-bog': 100},
              advance: 0,
              floor: 'takeaway',
              package: false,
              reservation: false,
            ),
            (
              name: 'takeaway split',
              method: 'split',
              tender: const {'cash': 25, 'card-tbc': 75},
              advance: 0,
              floor: 'takeaway',
              package: false,
              reservation: false,
            ),
            (
              name: 'package split',
              method: 'split',
              tender: const {'cash': 40, 'card-bog': 60},
              advance: 0,
              floor: 'first',
              package: true,
              reservation: false,
            ),
            (
              name: 'reservation-linked cash',
              method: 'cash',
              tender: const {'cash': 100},
              advance: 0,
              floor: 'first',
              package: false,
              reservation: true,
            ),
          ];

      final cancellationLabels = <String>[];

      for (var index = 0; index < scenarios.length; index++) {
        final scenario = scenarios[index];
        final orderId = 100 + index;
        final order = await seedOrder(
          orderId: orderId,
          advance: scenario.advance,
          floor: scenario.floor,
          package: scenario.package,
        );

        if (scenario.advance > 0) {
          final receiptId = await SalesRepository.recordAdvanceReceipt(
            orderId: orderId,
            amount: scenario.advance,
            collectedBy: 'manager',
          );
          order.advanceReceiptId = receiptId;
          await order.save();
        }

        Reservation? reservation;
        if (scenario.reservation) {
          reservation = Reservation(
            id: 'reservation-$orderId',
            customerName: 'Guest',
            customerPhone: '+995555000000',
            tableNumbers: [orderId],
            tableRefs: ['first/$orderId'],
            reservationDate: DateTime.parse('${businessDate}T00:00:00'),
            reservationTime: '12:00',
            numberOfGuests: 2,
            createdAt: DateTime.parse('${businessDate}T10:00:00'),
            createdBy: 'manager',
            status: ReservationStatus.inProgress.storageValue,
            linkedOrderId: orderId,
          );
          await DatabaseCore.reservationBox!.add(reservation);
        }
        if (scenario.floor != 'takeaway') {
          await seedOccupiedTable(order, reservationId: reservation?.id);
        }

        final collectedNow = scenario.tender.values.fold<double>(
          0,
          (sum, amount) => sum + amount,
        );
        final result = await CloseTableTransaction.run(
          orderId: orderId,
          money: ClosureMoney.fromOrder(order, collectedNow: collectedNow),
          paymentMethod: scenario.method,
          tenderBreakdown: scenario.tender,
          closedById: 'manager',
          isFiscal: true,
        );

        expect(result.outcome, ClosureOutcome.closed, reason: scenario.name);
        expect(
          DatabaseCore.orderBox!.get(orderId)!.status,
          'closed',
          reason: scenario.name,
        );

        final sale = saleFor(orderId);
        expect(sale['grossSaleAmount'], 100, reason: scenario.name);
        expect(sale['advanceApplied'], scenario.advance, reason: scenario.name);
        expect(sale['collectedNow'], collectedNow, reason: scenario.name);
        expect(sale['closureId'], result.closureId, reason: scenario.name);
        expect(SalesRepository.countsAsRevenue(sale), isTrue);
        final breakdown = Map<String, dynamic>.from(
          sale['paymentBreakdown'] as Map,
        );
        for (final tender in scenario.tender.entries) {
          expect(breakdown[tender.key], tender.value, reason: scenario.name);
        }
        if (scenario.advance > 0) {
          expect(breakdown['advance'], scenario.advance, reason: scenario.name);
        }
        expect(breakdownTotal(breakdown), 100, reason: scenario.name);

        final journal = ClosureJournalRepository.find(result.closureId!)!;
        expect(journal.phase, ClosurePhase.completed, reason: scenario.name);
        expect(journal.grossSaleAmount, 100, reason: scenario.name);
        expect(journal.advanceApplied, scenario.advance, reason: scenario.name);
        expect(journal.collectedNow, collectedNow, reason: scenario.name);
        expect(journal.businessDate, businessDate, reason: scenario.name);

        if (scenario.floor != 'takeaway') {
          final table = DatabaseCore.tableBox!.values.firstWhere(
            (candidate) => candidate.tableNumber == order.tableNumbers.single,
          );
          expect(table.isReserved, isFalse, reason: scenario.name);
          expect(table.activeOrderId, isNull, reason: scenario.name);
        }
        if (reservation != null) {
          expect(
            DatabaseCore.reservationBox!.values
                .firstWhere((candidate) => candidate.id == reservation!.id)
                .statusEnum,
            ReservationStatus.completed,
            reason: scenario.name,
          );
        }

        final report = AuditRepository.getAuditReport(orderId);
        expect(report, isNotNull, reason: scenario.name);
        expect(report!.status, AuditReportStatus.closed, reason: scenario.name);
        expect(report.locked, isTrue, reason: scenario.name);
        if (report.events.any(
          (event) => event.type == AuditEventType.cancelTable,
        )) {
          cancellationLabels.add(scenario.name);
        }
      }

      expect(
        cancellationLabels,
        isEmpty,
        reason:
            'Successful close requires a dedicated close/payment audit event; '
            'CANCEL_TABLE is reserved for genuine cancellation.',
      );
    },
  );

  test(
    'a genuine cancellation uses cancellation audit and writes no sale',
    () async {
      final order = await seedOrder(orderId: 300);
      await seedOccupiedTable(order);

      await AuditRepository.logAdminAction(
        actionType: 'cancel_table',
        performedBy: 'manager',
        details: {
          'orderId': order.orderId,
          'tableNumbers': order.tableNumbers,
          'floor': order.floor,
        },
        comment: 'Guest left before service',
      );
      await OrderRepository.updateOrderStatus(
        orderId: order.orderId,
        status: 'cancelled',
      );

      final report = AuditRepository.getAuditReport(order.orderId)!;
      expect(DatabaseCore.orderBox!.get(order.orderId)!.status, 'cancelled');
      expect(report.status, AuditReportStatus.cancelled);
      expect(report.events.single.type, AuditEventType.cancelTable);
      expect(report.events.single.note, 'Guest left before service');
      expect(
        DatabaseCore.salesBox!.values.where(
          (raw) => raw is Map && raw['recordType'] == 'sale',
        ),
        isEmpty,
      );
      expect(DatabaseCore.tableBox!.values.single.isReserved, isFalse);
    },
  );

  test(
    'internal close records no collection and is not a cancellation',
    () async {
      final order = await seedOrder(orderId: 400);
      await seedOccupiedTable(order);

      // This is the current production caller contract. The assertions below
      // deliberately reject its invented cash collection.
      final result = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 100),
        paymentMethod: 'non-fiscal',
        tenderBreakdown: const {'cash': 100},
        closedById: 'manager',
        isFiscal: false,
      );
      final sale = saleFor(order.orderId);
      final report = AuditRepository.getAuditReport(order.orderId)!;
      final violations = <String>[];

      if ((sale['collectedNow'] as num).toDouble() != 0) {
        violations.add('internal Sale says money was collected');
      }
      if ((sale['paymentBreakdown'] as Map).containsKey('cash')) {
        violations.add('internal Sale masquerades as cash');
      }
      if (report.events.any(
        (event) => event.type == AuditEventType.cancelTable,
      )) {
        violations.add('internal close masquerades as cancellation');
      }

      expect(result.outcome, ClosureOutcome.closed);
      expect(sale['isFiscal'], isFalse);
      expect(SalesRepository.countsAsRevenue(sale), isFalse);
      expect(BusinessDayRepository.grossSalesTotalForDate(businessDate), 0);
      expect(BusinessDayRepository.collectedTotalForDate(businessDate), 0);
      expect(violations, isEmpty);
    },
  );

  test(
    'restore reopens the audit lifecycle and re-close appends a new close',
    () async {
      final order = await seedOrder(
        orderId: 500,
        advance: 20,
        tableNumber: '1',
      );
      await seedOccupiedTable(order);
      final receiptId = await SalesRepository.recordAdvanceReceipt(
        orderId: order.orderId,
        amount: 20,
        collectedBy: 'manager',
      );
      order.advanceReceiptId = receiptId;
      await order.save();

      final first = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 80),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 80},
        closedById: 'manager',
        isFiscal: true,
      );
      final firstSale = saleFor(order.orderId);
      final restored = await SalesRepository.restoreClosedOrderFromSale(
        recordKey: firstSale['recordKey'],
        restoredBy: 'manager',
      );

      expect(restored, isTrue);
      expect(
        ClosureJournalRepository.find(first.closureId!)!.isReversed,
        isTrue,
      );
      expect(firstSale['closureId'], first.closureId);
      expect(BusinessDayRepository.grossSalesTotalForDate(businessDate), 0);
      final reopened = DatabaseCore.orderBox!.get(order.orderId)!;
      expect(reopened.status, 'confirmed');
      expect(reopened.advanceAmount, 20);
      expect(reopened.closureId, isNull);
      expect(DatabaseCore.tableBox!.values.single.activeOrderId, order.orderId);

      final reportAfterRestore = AuditRepository.getAuditReport(order.orderId)!;
      final eventsAfterRestore = reportAfterRestore.events.length;
      final violations = <String>[];
      if (reportAfterRestore.status != AuditReportStatus.open ||
          reportAfterRestore.locked) {
        violations.add('restore retained a CLOSED, locked audit report');
      }
      if (eventsAfterRestore <= 1) {
        violations.add('restore did not append a restore/reopen event');
      }

      final second = await CloseTableTransaction.run(
        orderId: reopened.orderId,
        money: ClosureMoney.fromOrder(reopened, collectedNow: 80),
        paymentMethod: 'card-bog',
        tenderBreakdown: const {'card-bog': 80},
        closedById: 'manager',
        isFiscal: true,
      );

      expect(second.outcome, ClosureOutcome.closed);
      expect(second.closureId, isNot(first.closureId));
      expect(
        DatabaseCore.salesBox!.values
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .where(SalesRepository.countsAsRevenue),
        hasLength(1),
      );
      expect(BusinessDayRepository.grossSalesTotalForDate(businessDate), 100);
      final finalReport = AuditRepository.getAuditReport(order.orderId)!;
      if (finalReport.status != AuditReportStatus.closed) {
        violations.add('re-close did not close the audit report');
      }
      if (finalReport.events.length <= eventsAfterRestore) {
        violations.add('re-close did not append a new closure event');
      }
      if (finalReport.events.any(
        (event) => event.type == AuditEventType.cancelTable,
      )) {
        violations.add('close/re-close lifecycle contains cancellation');
      }
      expect(violations, isEmpty);
    },
  );

  test(
    'crash recovery completes reservation and the same closure audit',
    () async {
      final order = await seedOrder(orderId: 600);
      final reservation = Reservation(
        id: 'reservation-600',
        customerName: 'Guest',
        customerPhone: '+995555000000',
        tableNumbers: const [600],
        tableRefs: const ['first/600'],
        reservationDate: DateTime.parse('${businessDate}T00:00:00'),
        reservationTime: '12:00',
        numberOfGuests: 2,
        createdAt: DateTime.parse('${businessDate}T10:00:00'),
        createdBy: 'manager',
        status: ReservationStatus.inProgress.storageValue,
        linkedOrderId: order.orderId,
      );
      await DatabaseCore.reservationBox!.add(reservation);
      await seedOccupiedTable(order, reservationId: reservation.id);
      await AuditRepository.ensureAuditReport(
        orderId: order.orderId,
        orderSnapshot: order,
      );

      final closureId = ClosureJournalRepository.newClosureId();
      final saleKey = await SalesRepository.saveSaleRecord(
        orderId: order.orderId,
        tableNumbers: order.tableNumbers,
        floor: order.floor,
        items: order.items,
        totalAmount: 100,
        paymentMethod: 'cash',
        paymentBreakdown: const {'cash': 100},
        createdBy: order.createdBy,
        createdAt: order.createdAt,
        closedAt: DateTime.parse('${businessDate}T13:00:00'),
        includeServiceFee: false,
        closureId: closureId,
        grossSaleAmount: 100,
        collectedNow: 100,
        businessDate: businessDate,
      );
      expect(saleKey, isNotNull);
      await ClosureJournalRepository.write(
        ClosureJournalEntry(
          closureId: closureId,
          orderId: order.orderId,
          phase: ClosurePhase.started,
          businessDate: businessDate,
          isFiscal: true,
          grossSaleAmount: 100,
          advanceApplied: 0,
          collectedNow: 100,
          paymentMethod: 'cash',
          paymentBreakdown: const {'cash': 100},
          actorId: 'manager',
          startedAt: DateTime.parse('${businessDate}T13:00:00'),
        ),
      );

      final outcomes = await ClosureRecoveryService.recoverPending();

      expect(outcomes.single.action, ClosureRecoveryAction.finished);
      expect(DatabaseCore.orderBox!.get(order.orderId)!.status, 'closed');
      expect(saleFor(order.orderId)['closureId'], closureId);
      expect(
        ClosureJournalRepository.find(closureId)!.phase,
        ClosurePhase.completed,
      );
      expect(DatabaseCore.tableBox!.values.single.isReserved, isFalse);
      final violations = <String>[];
      if (DatabaseCore.reservationBox!.values.single.statusEnum !=
          ReservationStatus.completed) {
        violations.add('recovery left linked reservation IN_PROGRESS');
      }
      final report = AuditRepository.getAuditReport(order.orderId)!;
      if (report.status != AuditReportStatus.closed || !report.locked) {
        violations.add('recovery left the closure audit report OPEN');
      }
      if (report.events.any(
        (event) => event.type == AuditEventType.cancelTable,
      )) {
        violations.add('recovery represented successful close as cancellation');
      }
      if (report.events.isEmpty) {
        violations.add('recovery did not append a closure audit event');
      }
      expect(violations, isEmpty);
    },
  );
}
