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
import 'package:vynic/core/models/order_status.dart';
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
/// event, and restore must leave a complete lifecycle trail.
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

  Map<String, dynamic>? saleForOrNull(int orderId) {
    for (final sale in SalesRepository.getSalesForDate(businessDate)) {
      if (sale['recordType'] == 'sale' && sale['orderId'] == orderId) {
        return sale;
      }
    }
    return null;
  }

  Future<
    ({
      Order order,
      String closureId,
      Object saleKey,
      String? receiptId,
      Reservation? reservation,
    })
  >
  seedPostSaleCrash({
    required int orderId,
    required String paymentMethod,
    required Map<String, double> tender,
    double advance = 0,
    bool isFiscal = true,
    String floor = 'first',
    bool package = false,
    bool reservationLinked = false,
  }) async {
    final order = await seedOrder(
      orderId: orderId,
      advance: advance,
      floor: floor,
      package: package,
    );
    final closureId = ClosureJournalRepository.newClosureId();
    order.closureId = closureId;

    String? receiptId;
    if (advance > 0) {
      receiptId = await SalesRepository.recordAdvanceReceipt(
        orderId: orderId,
        amount: advance,
        collectedBy: 'manager',
      );
      order.advanceReceiptId = receiptId;
    }
    await order.save();

    Reservation? reservation;
    if (reservationLinked) {
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
    if (floor != 'takeaway') {
      await seedOccupiedTable(order, reservationId: reservation?.id);
    }
    await AuditRepository.ensureAuditReport(
      orderId: order.orderId,
      orderSnapshot: order,
    );

    final paymentBreakdown = <String, double>{
      ...tender,
      if (advance > 0) 'advance': advance,
    };
    final collectedNow = tender.values.fold<double>(
      0,
      (sum, amount) => sum + amount,
    );
    final saleKey = await SalesRepository.saveSaleRecord(
      orderId: order.orderId,
      tableNumbers: order.tableNumbers,
      floor: order.floor,
      items: [...order.packageItems, ...order.items],
      totalAmount: 100,
      paymentMethod: paymentMethod,
      paymentBreakdown: paymentBreakdown,
      createdBy: order.createdBy,
      createdAt: order.createdAt,
      closedAt: DateTime.parse('${businessDate}T13:00:00'),
      includeServiceFee: order.includeServiceFee,
      discountAmount: order.discountAmount,
      advanceAmount: advance,
      subtotalAmount: 100,
      manualAdjustmentAmount: order.manualAdjustmentAmount,
      isFiscal: isFiscal,
      closureId: closureId,
      closedById: 'manager',
      grossSaleAmount: 100,
      advanceApplied: advance,
      collectedNow: collectedNow,
      businessDate: businessDate,
      advanceReceiptId: receiptId,
    );
    if (saleKey == null) {
      throw StateError('Failed to seed interrupted Sale for $orderId');
    }
    await ClosureJournalRepository.write(
      ClosureJournalEntry(
        closureId: closureId,
        orderId: order.orderId,
        phase: ClosurePhase.started,
        businessDate: businessDate,
        isFiscal: isFiscal,
        grossSaleAmount: 100,
        advanceApplied: advance,
        collectedNow: collectedNow,
        paymentMethod: paymentMethod,
        paymentBreakdown: paymentBreakdown,
        actorId: 'manager',
        actorName: 'Recovery Manager',
        startedAt: DateTime.parse('${businessDate}T13:00:00'),
        advanceReceiptId: receiptId,
      ),
    );

    return (
      order: order,
      closureId: closureId,
      saleKey: saleKey,
      receiptId: receiptId,
      reservation: reservation,
    );
  }

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
        final closeEvent = report.events.single;
        expect(closeEvent.type, AuditEventType.close, reason: scenario.name);
        final details = closeEvent.details!;
        expect(details['orderId'], orderId, reason: scenario.name);
        expect(
          details['tableNumbers'],
          order.tableNumbers,
          reason: scenario.name,
        );
        expect(
          details['tableRefs'],
          order.tableNumbers
              .map((tableNumber) => '${order.floor}/$tableNumber')
              .toList(),
          reason: scenario.name,
        );
        expect(details['actorId'], 'manager', reason: scenario.name);
        expect(details['actorName'], 'manager', reason: scenario.name);
        expect(details['businessDate'], businessDate, reason: scenario.name);
        expect(details['closureId'], result.closureId, reason: scenario.name);
        // A normal close is completed by the POS itself, never by recovery.
        expect(details['source'], 'POS', reason: scenario.name);
        expect(
          details.containsKey('recoveryAction'),
          isFalse,
          reason: scenario.name,
        );
        expect(details['isFiscal'], isTrue, reason: scenario.name);
        expect(details['grossAmount'], 100, reason: scenario.name);
        expect(
          details['paymentMethod'],
          scenario.method,
          reason: scenario.name,
        );
        expect(
          details['cashAmount'],
          scenario.tender['cash'] ?? 0,
          reason: scenario.name,
        );
        expect(
          details['cardAmount'],
          scenario.tender.entries
              .where((entry) => entry.key.startsWith('card'))
              .fold<double>(0, (sum, entry) => sum + entry.value),
          reason: scenario.name,
        );
        expect(
          details['advanceApplied'],
          scenario.advance,
          reason: scenario.name,
        );
        expect(details['collectedNow'], collectedNow, reason: scenario.name);
        expect(details['serviceFee'], 0, reason: scenario.name);
        expect(details['discountAmount'], 0, reason: scenario.name);
        expect(details['manualAdjustmentAmount'], 0, reason: scenario.name);
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
    'fiscal close audit preserves fee, discount, and adjustment truth',
    () async {
      final order = await seedOrder(orderId: 250);
      order.includeServiceFee = true;
      order.customServiceFeePercentage = 10;
      order.discountAmount = 5;
      order.manualAdjustmentAmount = 2;
      order.recalculateTotal();
      await order.save();

      final result = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 107),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 107},
        closedById: 'manager-id',
        closedByName: 'Manager Name',
        isFiscal: true,
      );

      expect(result.outcome, ClosureOutcome.closed);
      final event = AuditRepository.getAuditReport(
        order.orderId,
      )!.events.single;
      expect(event.type, AuditEventType.close);
      expect(event.waiterId, 'manager-id');
      expect(event.waiterName, 'Manager Name');
      expect(event.details, containsPair('actorId', 'manager-id'));
      expect(event.details, containsPair('actorName', 'Manager Name'));
      expect(event.details, containsPair('grossAmount', 107.0));
      expect(event.details, containsPair('serviceFee', 10.0));
      expect(event.details, containsPair('discountAmount', 5.0));
      expect(event.details, containsPair('manualAdjustmentAmount', 2.0));
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
      final order = await seedOrder(orderId: 400, tableNumber: '1');
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
      final journal = ClosureJournalRepository.find(result.closureId!)!;
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
      expect(sale['paymentMethod'], 'non-fiscal');
      expect(sale['grossSaleAmount'], 100);
      expect(sale['collectedNow'], 0);
      expect(sale['paymentBreakdown'], isEmpty);
      expect(
        sale['finalTransaction'],
        containsPair('paymentMethod', 'non-fiscal'),
      );
      expect(
        sale['finalTransaction'],
        containsPair('paymentBreakdown', const <String, double>{}),
      );
      expect(sale['finalTransaction'], containsPair('cashAmount', 0.0));
      expect(sale['finalTransaction'], containsPair('cardAmount', 0.0));
      expect(sale['finalTransaction'], containsPair('collectedNow', 0.0));
      expect(journal.grossSaleAmount, 100);
      expect(journal.collectedNow, 0);
      expect(journal.paymentMethod, 'non-fiscal');
      expect(journal.paymentBreakdown, isEmpty);
      expect(report.events.single.type, AuditEventType.internalClose);
      expect(
        report.events.single.details,
        containsPair('paymentMethod', 'non-fiscal'),
      );
      expect(report.events.single.details, containsPair('cashAmount', 0.0));
      expect(report.events.single.details, containsPair('cardAmount', 0.0));
      expect(report.events.single.details, containsPair('collectedNow', 0.0));
      expect(report.events.single.details, containsPair('grossAmount', 100.0));
      expect(SalesRepository.countsAsRevenue(sale), isFalse);
      expect(BusinessDayRepository.grossSalesTotalForDate(businessDate), 0);
      expect(BusinessDayRepository.collectedTotalForDate(businessDate), 0);

      expect(
        await SalesRepository.restoreClosedOrderFromSale(
          recordKey: sale['recordKey'],
          restoredBy: 'manager',
        ),
        isTrue,
      );
      final restoredSale = saleFor(order.orderId);
      expect(restoredSale['restoredToOrder'], isTrue);
      expect(restoredSale['isFiscal'], isFalse);
      expect(restoredSale['collectedNow'], 0);
      expect(restoredSale['paymentBreakdown'], isEmpty);
      expect(SalesRepository.countsAsRevenue(restoredSale), isFalse);
      expect(BusinessDayRepository.grossSalesTotalForDate(businessDate), 0);
      expect(BusinessDayRepository.collectedTotalForDate(businessDate), 0);
      expect(
        AuditRepository.getAuditReport(
          order.orderId,
        )!.events.map((event) => event.type),
        [AuditEventType.internalClose, AuditEventType.restore],
      );
      expect(
        AuditRepository.getAuditReport(
          order.orderId,
        )!.events.last.details?['originalIsFiscal'],
        isFalse,
      );
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
      final receiptId = (await SalesRepository.recordAdvanceReceipt(
        orderId: order.orderId,
        amount: 20,
        collectedBy: 'manager',
      ))!;
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
      expect(reportAfterRestore.events.map((event) => event.type), [
        AuditEventType.close,
        AuditEventType.restore,
      ]);
      final restoreEvent = reportAfterRestore.events.last;
      expect(
        restoreEvent.details,
        containsPair('originalClosureId', first.closureId),
      );
      expect(
        restoreEvent.details,
        containsPair('originalSaleId', firstSale['posSaleId']),
      );
      expect(restoreEvent.details, containsPair('actorId', 'manager'));
      expect(restoreEvent.details, containsPair('businessDate', businessDate));
      expect(restoreEvent.details, containsPair('tableNumbers', ['1']));
      expect(restoreEvent.details, containsPair('tableRefs', ['first/1']));
      expect(restoreEvent.details, containsPair('restoredGrossAmount', 100.0));
      expect(restoreEvent.details, containsPair('originalIsFiscal', isTrue));
      expect(restoreEvent.details, containsPair('advanceAmount', 20.0));

      final reversedAt = ClosureJournalRepository.find(
        first.closureId!,
      )!.reversedAt;
      final restoredAt = saleFor(order.orderId)['restoredAt'];
      final repeatedRestore = await SalesRepository.restoreClosedOrderFromSale(
        recordKey: firstSale['recordKey'],
        restoredBy: 'manager',
      );
      expect(repeatedRestore, isFalse);
      expect(
        AuditRepository.getAuditReport(order.orderId)!.events,
        hasLength(eventsAfterRestore),
      );
      expect(
        ClosureJournalRepository.find(first.closureId!)!.reversedAt,
        reversedAt,
      );
      expect(saleFor(order.orderId)['restoredAt'], restoredAt);
      expect(
        SalesRepository.getSalesForDate(
          businessDate,
        ).where((sale) => sale['recordType'] == 'sale'),
        hasLength(1),
      );
      expect(
        SalesRepository.findAdvanceReceipt(receiptId)?['appliedToClosureId'],
        isNull,
      );
      expect(DatabaseCore.tableBox!.values.single.activeOrderId, order.orderId);

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
      expect(finalReport.events.map((event) => event.type), [
        AuditEventType.close,
        AuditEventType.restore,
        AuditEventType.close,
      ]);
      expect(finalReport.events.first.details?['closureId'], first.closureId);
      expect(finalReport.events.last.details?['closureId'], second.closureId);
      expect(
        SalesRepository.findAdvanceReceipt(receiptId)?['appliedToClosureId'],
        second.closureId,
      );
      final sales = SalesRepository.getSalesForDate(
        businessDate,
      ).where((sale) => sale['recordType'] == 'sale').toList();
      expect(sales, hasLength(2));
      final originalSale = sales.firstWhere(
        (sale) => sale['closureId'] == first.closureId,
      );
      final replacementSale = sales.firstWhere(
        (sale) => sale['closureId'] == second.closureId,
      );
      expect(originalSale['restoredToOrder'], isTrue);
      expect(originalSale['paymentBreakdown'], {'cash': 80.0, 'advance': 20.0});
      expect(replacementSale['restoredToOrder'], isFalse);
      expect(sales.where(SalesRepository.countsAsRevenue), hasLength(1));
      expect(DatabaseCore.tableBox!.values.single.isReserved, isFalse);
      expect(violations, isEmpty);
    },
  );

  test('cash card and split each preserve CLOSE RESTORE CLOSE', () async {
    final scenarios = <({String method, Map<String, double> tender})>[
      (method: 'cash', tender: const {'cash': 100}),
      (method: 'card-bog', tender: const {'card-bog': 100}),
      (method: 'split', tender: const {'cash': 35, 'card-tbc': 65}),
    ];

    for (var index = 0; index < scenarios.length; index++) {
      final scenario = scenarios[index];
      final order = await seedOrder(orderId: 510 + index, tableNumber: '1');
      await seedOccupiedTable(order);

      final first = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 100),
        paymentMethod: scenario.method,
        tenderBreakdown: scenario.tender,
        closedById: 'manager',
        isFiscal: true,
      );
      final firstSale = saleFor(order.orderId);
      expect(
        await SalesRepository.restoreClosedOrderFromSale(
          recordKey: firstSale['recordKey'],
          restoredBy: 'manager',
        ),
        isTrue,
      );
      final reopened = OrderRepository.getOrder(order.orderId)!;
      final second = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(reopened, collectedNow: 100),
        paymentMethod: scenario.method,
        tenderBreakdown: scenario.tender,
        closedById: 'manager',
        isFiscal: true,
      );

      expect(second.closureId, isNot(first.closureId));
      expect(
        AuditRepository.getAuditReport(
          order.orderId,
        )!.events.map((event) => event.type),
        [AuditEventType.close, AuditEventType.restore, AuditEventType.close],
        reason: scenario.method,
      );
      final orderSales = SalesRepository.getSalesForDate(businessDate)
          .where(
            (sale) =>
                sale['recordType'] == 'sale' &&
                sale['orderId'] == order.orderId,
          )
          .toList();
      expect(orderSales, hasLength(2), reason: scenario.method);
      expect(
        orderSales.firstWhere(
          (sale) => sale['closureId'] == first.closureId,
        )['paymentBreakdown'],
        scenario.tender,
        reason: scenario.method,
      );
      expect(
        orderSales.where(SalesRepository.countsAsRevenue),
        hasLength(1),
        reason: scenario.method,
      );
    }
  });

  test('takeaway restores and recloses without a table dependency', () async {
    final order = await seedOrder(orderId: 520, floor: 'takeaway');
    final first = await CloseTableTransaction.run(
      orderId: order.orderId,
      money: ClosureMoney.fromOrder(order, collectedNow: 100),
      paymentMethod: 'cash',
      tenderBreakdown: const {'cash': 100},
      closedById: 'manager',
      isFiscal: true,
    );
    final firstSale = saleFor(order.orderId);

    expect(
      await SalesRepository.restoreClosedOrderFromSale(
        recordKey: firstSale['recordKey'],
        restoredBy: 'manager',
      ),
      isTrue,
    );
    expect(DatabaseCore.tableBox!.values, isEmpty);
    final reopened = OrderRepository.getOrder(order.orderId)!;
    expect(reopened.status, 'confirmed');
    final second = await CloseTableTransaction.run(
      orderId: order.orderId,
      money: ClosureMoney.fromOrder(reopened, collectedNow: 100),
      paymentMethod: 'card-tbc',
      tenderBreakdown: const {'card-tbc': 100},
      closedById: 'manager',
      isFiscal: true,
    );

    expect(second.closureId, isNot(first.closureId));
    expect(
      AuditRepository.getAuditReport(
        order.orderId,
      )!.events.map((event) => event.type),
      [AuditEventType.close, AuditEventType.restore, AuditEventType.close],
    );
  });

  test('package data survives restore and the next closure', () async {
    final order = await seedOrder(
      orderId: 530,
      tableNumber: '1',
      package: true,
    );
    await seedOccupiedTable(order);
    await CloseTableTransaction.run(
      orderId: order.orderId,
      money: ClosureMoney.fromOrder(order, collectedNow: 100),
      paymentMethod: 'cash',
      tenderBreakdown: const {'cash': 100},
      closedById: 'manager',
      isFiscal: true,
    );
    final firstSale = saleFor(order.orderId);

    expect(
      await SalesRepository.restoreClosedOrderFromSale(
        recordKey: firstSale['recordKey'],
        restoredBy: 'manager',
      ),
      isTrue,
    );
    final reopened = OrderRepository.getOrder(order.orderId)!;
    expect(reopened.packageId, 'package-530');
    expect(reopened.packageName, 'Package 530');
    expect(reopened.packageGuestCount, 10);
    expect(reopened.packageUnitPrice, 10);
    expect(reopened.packagePrice, 100);
    expect(reopened.packageItems.single.itemName, 'Package item 530');

    await CloseTableTransaction.run(
      orderId: order.orderId,
      money: ClosureMoney.fromOrder(reopened, collectedNow: 100),
      paymentMethod: 'cash',
      tenderBreakdown: const {'cash': 100},
      closedById: 'manager',
      isFiscal: true,
    );
    final sales = SalesRepository.getSalesForDate(
      businessDate,
    ).where((sale) => sale['orderId'] == order.orderId).toList();
    expect(sales, hasLength(2));
    final activeSale = sales.singleWhere(SalesRepository.countsAsRevenue);
    expect(
      (activeSale['items'] as List).single['itemName'],
      'Package item 530',
    );
    expect(sales.where(SalesRepository.countsAsRevenue), hasLength(1));
  });

  test(
    'genuine Reservation returns to IN_PROGRESS and completes again',
    () async {
      final order = await seedOrder(orderId: 540, tableNumber: '1');
      final reservation = Reservation(
        id: 'reservation-540',
        customerName: 'Guest',
        customerPhone: '+995555000000',
        tableNumbers: const [1],
        tableRefs: const ['first/1'],
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
      await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 100),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 100},
        closedById: 'manager',
        isFiscal: true,
      );
      expect(reservation.statusEnum, ReservationStatus.completed);
      final firstSale = saleFor(order.orderId);

      expect(
        await SalesRepository.restoreClosedOrderFromSale(
          recordKey: firstSale['recordKey'],
          restoredBy: 'manager',
        ),
        isTrue,
      );
      expect(DatabaseCore.reservationBox!.values, hasLength(1));
      expect(reservation.statusEnum, ReservationStatus.inProgress);
      expect(reservation.linkedOrderId, order.orderId);
      final table = DatabaseCore.tableBox!.values.single;
      expect(table.activeOrderId, order.orderId);
      expect(table.reservationId, reservation.id);

      final reopened = OrderRepository.getOrder(order.orderId)!;
      await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(reopened, collectedNow: 100),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 100},
        closedById: 'manager',
        isFiscal: true,
      );
      expect(reservation.statusEnum, ReservationStatus.completed);
      expect(reservation.linkedOrderId, order.orderId);
      expect(DatabaseCore.reservationBox!.values, hasLength(1));
      expect(table.isReserved, isFalse);
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

      // Same typed event, but its provenance says the system finished what
      // the operator started: actor is the person, source is the mechanism.
      final closeEvents = report.events
          .where((event) => event.type == AuditEventType.close)
          .toList();
      expect(closeEvents, hasLength(1));
      final details = closeEvents.single.details!;
      expect(details['source'], 'SYSTEM_RECOVERY');
      expect(details['recoveryAction'], 'finished');
      expect(details['actorId'], 'manager');
      expect(closeEvents.single.waiterId, 'manager');
    },
  );

  test(
    'post-Sale recovery preserves every payment and order mode exactly once',
    () async {
      final scenarios =
          <
            ({
              String name,
              String method,
              Map<String, double> tender,
              double advance,
              bool isFiscal,
              String floor,
              bool package,
              bool reservation,
            })
          >[
            (
              name: 'cash Walk-In',
              method: 'cash',
              tender: const {'cash': 100},
              advance: 0,
              isFiscal: true,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'card',
              method: 'card-tbc',
              tender: const {'card-tbc': 100},
              advance: 0,
              isFiscal: true,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'split',
              method: 'split',
              tender: const {'cash': 40, 'card-bog': 60},
              advance: 0,
              isFiscal: true,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'advance plus cash',
              method: 'cash',
              tender: const {'cash': 80},
              advance: 20,
              isFiscal: true,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'advance plus card',
              method: 'card-bog',
              tender: const {'card-bog': 80},
              advance: 20,
              isFiscal: true,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'advance plus split',
              method: 'split',
              tender: const {'cash': 30, 'card-tbc': 50},
              advance: 20,
              isFiscal: true,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'internal',
              method: 'non-fiscal',
              tender: const {},
              advance: 0,
              isFiscal: false,
              floor: 'first',
              package: false,
              reservation: false,
            ),
            (
              name: 'Reservation linked',
              method: 'cash',
              tender: const {'cash': 100},
              advance: 0,
              isFiscal: true,
              floor: 'first',
              package: false,
              reservation: true,
            ),
            (
              name: 'Takeaway',
              method: 'cash',
              tender: const {'cash': 100},
              advance: 0,
              isFiscal: true,
              floor: 'takeaway',
              package: false,
              reservation: false,
            ),
            (
              name: 'Package',
              method: 'split',
              tender: const {'cash': 25, 'card-tbc': 75},
              advance: 0,
              isFiscal: true,
              floor: 'first',
              package: true,
              reservation: false,
            ),
          ];

      for (var index = 0; index < scenarios.length; index++) {
        final scenario = scenarios[index];
        final tableCountBefore = DatabaseCore.tableBox!.length;
        final reservationCountBefore = DatabaseCore.reservationBox!.length;
        final interrupted = await seedPostSaleCrash(
          orderId: 700 + index,
          paymentMethod: scenario.method,
          tender: scenario.tender,
          advance: scenario.advance,
          isFiscal: scenario.isFiscal,
          floor: scenario.floor,
          package: scenario.package,
          reservationLinked: scenario.reservation,
        );
        final saleBefore = Map<dynamic, dynamic>.from(
          DatabaseCore.salesBox!.get(interrupted.saleKey) as Map,
        );

        final outcomes = await ClosureRecoveryService.recoverPending();

        expect(outcomes, hasLength(1), reason: scenario.name);
        expect(
          outcomes.single.action,
          ClosureRecoveryAction.finished,
          reason: scenario.name,
        );
        final saleAfter = Map<dynamic, dynamic>.from(
          DatabaseCore.salesBox!.get(interrupted.saleKey) as Map,
        );
        expect(saleAfter, equals(saleBefore), reason: scenario.name);
        expect(
          DatabaseCore.salesBox!.values.where(
            (raw) => raw is Map && raw['closureId'] == interrupted.closureId,
          ),
          hasLength(1),
          reason: scenario.name,
        );

        final order = OrderRepository.getOrder(interrupted.order.orderId)!;
        expect(order.statusEnum, OrderStatus.closed, reason: scenario.name);
        expect(order.closureId, interrupted.closureId, reason: scenario.name);
        expect(order.paymentMethod, scenario.method, reason: scenario.name);

        final journal = ClosureJournalRepository.find(interrupted.closureId)!;
        expect(journal.phase, ClosurePhase.completed, reason: scenario.name);
        expect(
          journal.saleRecordKey,
          interrupted.saleKey,
          reason: scenario.name,
        );

        final report = AuditRepository.getAuditReport(order.orderId)!;
        expect(report.status, AuditReportStatus.closed, reason: scenario.name);
        expect(report.locked, isTrue, reason: scenario.name);
        final matchingEvents = report.events.where(
          (event) => event.details?['closureId'] == interrupted.closureId,
        );
        expect(matchingEvents, hasLength(1), reason: scenario.name);
        final closeEvent = matchingEvents.single;
        expect(
          closeEvent.type,
          scenario.isFiscal
              ? AuditEventType.close
              : AuditEventType.internalClose,
          reason: scenario.name,
        );
        expect(
          report.events.where(
            (event) => event.type == AuditEventType.cancelTable,
          ),
          isEmpty,
          reason: scenario.name,
        );
        final details = closeEvent.details!;
        expect(details['orderId'], order.orderId, reason: scenario.name);
        expect(
          details['closureId'],
          interrupted.closureId,
          reason: scenario.name,
        );
        expect(details['businessDate'], businessDate, reason: scenario.name);
        expect(details['actorId'], 'manager', reason: scenario.name);
        expect(details['actorName'], 'Recovery Manager', reason: scenario.name);
        expect(details['floor'], scenario.floor, reason: scenario.name);
        expect(
          details['tableNumbers'],
          order.tableNumbers,
          reason: scenario.name,
        );
        expect(
          details['tableRefs'],
          order.tableNumbers.map((table) => '${order.floor}/$table').toList(),
          reason: scenario.name,
        );
        expect(details['grossAmount'], 100, reason: scenario.name);
        expect(details['isFiscal'], scenario.isFiscal, reason: scenario.name);
        expect(
          details['paymentMethod'],
          scenario.method,
          reason: scenario.name,
        );
        expect(
          details['paymentBreakdown'],
          saleBefore['paymentBreakdown'],
          reason: scenario.name,
        );
        expect(
          details['cashAmount'],
          scenario.isFiscal ? scenario.tender['cash'] ?? 0 : 0,
          reason: scenario.name,
        );
        expect(
          details['cardAmount'],
          scenario.isFiscal
              ? scenario.tender.entries
                    .where((entry) => entry.key.startsWith('card'))
                    .fold<double>(0, (sum, entry) => sum + entry.value)
              : 0,
          reason: scenario.name,
        );
        expect(
          details['advanceApplied'],
          scenario.advance,
          reason: scenario.name,
        );
        expect(
          details['collectedNow'],
          scenario.tender.values.fold<double>(0, (sum, amount) => sum + amount),
          reason: scenario.name,
        );
        if (!scenario.isFiscal) {
          expect(saleAfter['isFiscal'], isFalse, reason: scenario.name);
          expect(saleAfter['collectedNow'], 0, reason: scenario.name);
          expect(saleAfter['paymentBreakdown'], isEmpty, reason: scenario.name);
          expect(
            SalesRepository.countsAsRevenue(saleAfter),
            isFalse,
            reason: scenario.name,
          );
          expect(details['cashAmount'], 0, reason: scenario.name);
          expect(details['cardAmount'], 0, reason: scenario.name);
        }

        if (scenario.floor == 'takeaway') {
          expect(
            DatabaseCore.tableBox!.length,
            tableCountBefore,
            reason: scenario.name,
          );
          expect(
            DatabaseCore.reservationBox!.length,
            reservationCountBefore,
            reason: scenario.name,
          );
        } else {
          final table = DatabaseCore.tableBox!.values.firstWhere(
            (candidate) => candidate.tableNumber == order.tableNumbers.single,
          );
          expect(table.isReserved, isFalse, reason: scenario.name);
          expect(table.activeOrderId, isNull, reason: scenario.name);
        }
        if (interrupted.reservation != null) {
          expect(
            interrupted.reservation!.statusEnum,
            ReservationStatus.completed,
            reason: scenario.name,
          );
          expect(
            interrupted.reservation!.linkedOrderId,
            order.orderId,
            reason: scenario.name,
          );
          expect(DatabaseCore.reservationBox!.values, hasLength(1));
        }
        Map<String, dynamic>? receiptAfterFirstRecovery;
        if (interrupted.receiptId != null) {
          receiptAfterFirstRecovery = SalesRepository.findAdvanceReceipt(
            interrupted.receiptId!,
          )!;
          expect(
            receiptAfterFirstRecovery['appliedToClosureId'],
            interrupted.closureId,
            reason: scenario.name,
          );
        }
        if (scenario.package) {
          expect(order.packageId, interrupted.order.packageId);
          expect(order.packageName, interrupted.order.packageName);
          expect(order.packageGuestCount, interrupted.order.packageGuestCount);
          expect(order.packageUnitPrice, interrupted.order.packageUnitPrice);
          expect(order.packagePrice, interrupted.order.packagePrice);
          expect(order.packageItems.single.itemName, 'Package item 709');
        }

        final reportAfterFirstRecovery = report.toMap();
        final journalAfterFirstRecovery = Map<dynamic, dynamic>.from(
          DatabaseCore.closureJournalBox!.get(interrupted.closureId) as Map,
        );
        expect(await ClosureRecoveryService.recoverPending(), isEmpty);
        expect(
          AuditRepository.getAuditReport(order.orderId)!.toMap(),
          equals(reportAfterFirstRecovery),
          reason: '${scenario.name} audit changed on second recovery',
        );
        expect(
          DatabaseCore.closureJournalBox!.get(interrupted.closureId),
          equals(journalAfterFirstRecovery),
          reason: '${scenario.name} journal changed on second recovery',
        );
        expect(
          DatabaseCore.salesBox!.get(interrupted.saleKey),
          equals(saleBefore),
          reason: '${scenario.name} Sale changed on second recovery',
        );
        if (interrupted.receiptId != null) {
          expect(
            SalesRepository.findAdvanceReceipt(interrupted.receiptId!),
            equals(receiptAfterFirstRecovery),
            reason: '${scenario.name} advance changed on second recovery',
          );
        }
      }
    },
  );

  test('retry after audit write keeps one typed closure event', () async {
    final interrupted = await seedPostSaleCrash(
      orderId: 820,
      paymentMethod: 'cash',
      tender: const {'cash': 100},
      reservationLinked: true,
    );
    expect(
      (await ClosureRecoveryService.recoverPending()).single.action,
      ClosureRecoveryAction.finished,
    );

    final completed = ClosureJournalRepository.find(interrupted.closureId)!;
    await ClosureJournalRepository.write(
      completed.copyWith(phase: ClosurePhase.saleWritten),
    );
    final auditBeforeRetry = AuditRepository.getAuditReport(
      interrupted.order.orderId,
    )!.toMap();

    expect(
      (await ClosureRecoveryService.recoverPending()).single.action,
      ClosureRecoveryAction.finished,
    );
    final report = AuditRepository.getAuditReport(interrupted.order.orderId)!;
    expect(
      report.events.where(
        (event) => event.details?['closureId'] == interrupted.closureId,
      ),
      hasLength(1),
    );
    expect(report.toMap(), equals(auditBeforeRetry));
    expect(
      report.events
          .where((event) => event.type == AuditEventType.close)
          .single
          .details!['source'],
      'SYSTEM_RECOVERY',
    );
    expect(interrupted.reservation!.statusEnum, ReservationStatus.completed);
    expect(DatabaseCore.reservationBox!.values, hasLength(1));
    expect(
      DatabaseCore.salesBox!.values.where(
        (raw) => raw is Map && raw['closureId'] == interrupted.closureId,
      ),
      hasLength(1),
    );
    expect(
      ClosureJournalRepository.find(interrupted.closureId)!.phase,
      ClosurePhase.completed,
    );
  });

  test(
    'crash before Sale abandons without close audit or Reservation completion',
    () async {
      final order = await seedOrder(orderId: 830);
      final reservation = Reservation(
        id: 'reservation-830',
        customerName: 'Guest',
        customerPhone: '+995555000000',
        tableNumbers: const [830],
        tableRefs: const ['first/830'],
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
      final closureId = ClosureJournalRepository.newClosureId();
      order.closureId = closureId;
      await order.save();
      await AuditRepository.ensureAuditReport(
        orderId: order.orderId,
        orderSnapshot: order,
      );
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

      final outcome = (await ClosureRecoveryService.recoverPending()).single;

      expect(outcome.action, ClosureRecoveryAction.abandoned);
      expect(saleForOrNull(order.orderId), isNull);
      expect(
        OrderRepository.getOrder(order.orderId)!.statusEnum,
        OrderStatus.served,
      );
      expect(OrderRepository.getOrder(order.orderId)!.closureId, isNull);
      expect(reservation.statusEnum, ReservationStatus.inProgress);
      final table = DatabaseCore.tableBox!.values.single;
      expect(table.isReserved, isTrue);
      expect(table.activeOrderId, order.orderId);
      final report = AuditRepository.getAuditReport(order.orderId)!;
      expect(report.status, AuditReportStatus.open);
      expect(report.locked, isFalse);
      expect(
        report.events.where(
          (event) =>
              event.type == AuditEventType.close ||
              event.type == AuditEventType.internalClose,
        ),
        isEmpty,
      );
      final journal = ClosureJournalRepository.find(closureId)!;
      expect(journal.isAbandoned, isTrue);
      expect(journal.phase, ClosurePhase.completed);
    },
  );

  test(
    'post-Sale recovery ignores historical bookkeeping Reservations',
    () async {
      final interrupted = await seedPostSaleCrash(
        orderId: 835,
        paymentMethod: 'cash',
        tender: const {'cash': 100},
      );
      final bookkeeping = Reservation(
        id: 'bookkeeping-835',
        customerName: 'walk-in',
        customerPhone: '-',
        tableNumbers: const [835],
        tableRefs: const ['first/835'],
        reservationDate: DateTime.parse('${businessDate}T00:00:00'),
        reservationTime: '12:00',
        numberOfGuests: 1,
        notes: 'Order #835',
        createdAt: DateTime.parse('${businessDate}T10:00:00'),
        createdBy: 'waiter',
        status: ReservationStatus.inProgress.storageValue,
        linkedOrderId: interrupted.order.orderId,
      );
      await DatabaseCore.reservationBox!.add(bookkeeping);

      await ClosureRecoveryService.recoverPending();

      expect(bookkeeping.statusEnum, ReservationStatus.inProgress);
      expect(bookkeeping.linkedOrderId, interrupted.order.orderId);
      expect(DatabaseCore.reservationBox!.values, hasLength(1));
    },
  );

  test(
    'a recovered close still restores and re-closes as CLOSE RESTORE CLOSE',
    () async {
      final interrupted = await seedPostSaleCrash(
        orderId: 840,
        paymentMethod: 'cash',
        tender: const {'cash': 100},
        floor: 'takeaway',
      );
      await ClosureRecoveryService.recoverPending();
      final recoveredSale = saleFor(interrupted.order.orderId);

      expect(
        await SalesRepository.restoreClosedOrderFromSale(
          recordKey: recoveredSale['recordKey'],
          restoredBy: 'manager',
        ),
        isTrue,
      );
      final reopened = OrderRepository.getOrder(interrupted.order.orderId)!;
      final reclose = await CloseTableTransaction.run(
        orderId: reopened.orderId,
        money: ClosureMoney.fromOrder(reopened, collectedNow: 100),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 100},
        closedById: 'manager',
        isFiscal: true,
      );

      expect(reclose.outcome, ClosureOutcome.closed);
      expect(reclose.closureId, isNot(interrupted.closureId));
      expect(
        AuditRepository.getAuditReport(
          reopened.orderId,
        )!.events.map((event) => event.type).toList(),
        [AuditEventType.close, AuditEventType.restore, AuditEventType.close],
      );
    },
  );

  test('close audit types and structured details round-trip', () {
    final event = AuditEvent(
      type: AuditEventType.close,
      itemName: 'ORDER',
      previousQty: 0,
      newQty: 0,
      waiterId: 'manager',
      waiterName: 'Manager',
      timestamp: DateTime.parse('${businessDate}T13:00:00Z'),
      note: 'Order closed with cash',
      details: const <String, dynamic>{
        'closureId': 'closure-1',
        'grossAmount': 100.0,
        'cashAmount': 100.0,
      },
    );

    expect(auditEventTypeToString(AuditEventType.close), 'CLOSE');
    expect(
      auditEventTypeToString(AuditEventType.internalClose),
      'INTERNAL_CLOSE',
    );
    expect(auditEventTypeToString(AuditEventType.restore), 'RESTORE');
    expect(auditEventTypeFromString('CLOSED'), AuditEventType.close);
    expect(
      auditEventTypeFromString('NON_FISCAL_CLOSE'),
      AuditEventType.internalClose,
    );
    expect(auditEventTypeFromString('REOPENED'), AuditEventType.restore);
    expect(
      auditEventTypeFromString('SALE_RESTORED_TO_ORDER'),
      AuditEventType.restore,
    );

    final restored = AuditEvent.fromMap(event.toMap());
    expect(restored.type, AuditEventType.close);
    expect(restored.details, event.details);
  });
}
