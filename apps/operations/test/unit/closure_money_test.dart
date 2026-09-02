import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/database/repositories/closure_journal_repository.dart';
import 'package:vynic/core/database/repositories/sales_repository.dart';
import 'package:vynic/core/database/transactions/close_table_transaction.dart';
import 'package:vynic/core/models/closure_money.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/sale_record.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/pos/closure_recovery_service.dart';

/// Money Integrity 1B: what a table closure is worth, how many times it can
/// happen, and what survives a crash in the middle of one.
///
/// Everything here runs against a real (temp-dir) Hive instance, because every
/// property is about what is actually persisted — one sale and not two, a
/// deposit dated the day it was taken, a daily total that equals the records
/// it claims to summarize.
void main() {
  late Directory tempDir;

  const today = '2026-09-04';
  const dayOne = '2026-08-31';

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

  /// A 900 order: nine items at 100, no service fee, no adjustment.
  Future<Order> seedOrder({
    int orderId = 1,
    double itemTotal = 900,
    double advance = 0,
  }) async {
    final order = Order(
      orderId: orderId,
      tableNumbers: const ['1'],
      floor: 'first',
      items: [
        OrderItem(
          itemKey: 'ღვინო',
          itemName: 'ღვინო',
          unitPrice: itemTotal,
          quantity: 1,
          total: itemTotal,
        ),
      ],
      totalAmount: itemTotal,
      createdAt: DateTime.parse('${today}T12:00:00'),
      createdBy: 'waiter',
      status: 'served',
    );
    if (advance > 0) {
      order.advanceAmount = advance;
      order.advanceCollectedOn = today;
    }
    order.recalculateTotal(serviceFeeRate: 0);
    await DatabaseCore.orderBox!.put(orderId, order);
    return order;
  }

  List<Map<String, dynamic>> salesFor(String date) =>
      SalesRepository.getSalesForDate(date);

  List<Map<String, dynamic>> closedSales(String date) =>
      salesFor(date).where(SalesRepository.isSaleRecord).toList();

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('vynic_closure_money');
    Hive.init(tempDir.path);
    registerAdapters();
  });

  setUp(() async {
    DatabaseCore.settingsBox = await Hive.openBox('cm_settings');
    DatabaseCore.salesBox = await Hive.openBox('cm_sales');
    DatabaseCore.auditLogBox = await Hive.openBox('cm_audit');
    DatabaseCore.orderBox = await Hive.openBox<Order>('cm_orders');
    DatabaseCore.tableBox = await Hive.openBox<TableModel>('cm_tables');
    DatabaseCore.reservationBox = await Hive.openBox<Reservation>('cm_res');
    DatabaseCore.closureJournalBox = await Hive.openBox('cm_journal');
    await DatabaseCore.settingsBox!.put('currentDate', '${today}T00:00:00.000');
    await DatabaseCore.settingsBox!.put('serviceFeePercent', 0.0);
    Order.serviceFeeRateResolver = () => 0.0;
  });

  tearDown(() async {
    Order.serviceFeeRateResolver = null;
    for (final name in const [
      'cm_settings',
      'cm_sales',
      'cm_audit',
      'cm_orders',
      'cm_tables',
      'cm_res',
      'cm_journal',
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

  group('the accounting identity', () {
    test('gross equals advance plus balance due', () {
      const money = ClosureMoney(
        gross: 900,
        advanceApplied: 50,
        collectedNow: 850,
      );
      expect(money.amountDueNow, 850);
      expect(money.describeMismatch(), isNull);
    });

    test('reads the split off an order whose total is already net', () async {
      final order = await seedOrder(itemTotal: 900, advance: 50);
      // What the payment dialog collects against.
      expect(order.totalAmount, 850);
      expect(order.grossAmount, 900);

      final money = ClosureMoney.fromOrder(order, collectedNow: 850);
      expect(money.gross, 900);
      expect(money.advanceApplied, 50);
      expect(money.amountDueNow, 850);
      expect(money.describeMismatch(), isNull);
    });

    test('a tender that does not settle the balance is a mismatch', () {
      const money = ClosureMoney(
        gross: 900,
        advanceApplied: 50,
        collectedNow: 800,
      );
      expect(money.describeMismatch(), contains('does not settle'));
    });

    test('a legacy sale with no gross field reads as its own total', () {
      final money = ClosureMoney.fromSaleMap({'totalAmount': 850.0});
      expect(money.gross, 850);
      expect(money.advanceApplied, 0);
    });
  });

  group('normal close', () {
    test('a 900 order books exactly one 900 sale', () async {
      final order = await seedOrder(itemTotal: 900);

      final result = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 900),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 900},
        closedById: 'manager',
        isFiscal: true,
      );

      expect(result.outcome, ClosureOutcome.closed);
      final sales = closedSales(today);
      expect(sales, hasLength(1));
      expect(sales.first['grossSaleAmount'], 900);
      expect(sales.first['totalAmount'], 900);
      expect(sales.first['collectedNow'], 900);
      expect(sales.first['advanceApplied'], 0);
      expect(sales.first['closureId'], result.closureId);
      expect(grossSalesFor(today), 900);
    });

    test('refuses and writes nothing when the tender is short', () async {
      final order = await seedOrder(itemTotal: 900);

      final result = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: const ClosureMoney(
          gross: 900,
          advanceApplied: 0,
          collectedNow: 800,
        ),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 800},
        closedById: 'manager',
        isFiscal: true,
      );

      expect(result.outcome, ClosureOutcome.moneyMismatch);
      expect(closedSales(today), isEmpty);
      expect(ClosureJournalRepository.all(), isEmpty);
      expect(grossSalesFor(today), 0);
    });
  });

  group('double close', () {
    test('the same closure called twice still books one sale', () async {
      final order = await seedOrder(itemTotal: 900);
      final money = ClosureMoney.fromOrder(order, collectedNow: 900);

      final first = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: money,
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 900},
        closedById: 'manager',
        isFiscal: true,
      );
      final second = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: money,
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 900},
        closedById: 'manager',
        isFiscal: true,
      );

      expect(first.outcome, ClosureOutcome.closed);
      expect(second.outcome, ClosureOutcome.alreadyClosed);
      expect(second.closureId, first.closureId);
      expect(closedSales(today), hasLength(1));
      expect(grossSalesFor(today), 900);
    });

    test('three rapid attempts still book one sale', () async {
      final order = await seedOrder(itemTotal: 900);
      final money = ClosureMoney.fromOrder(order, collectedNow: 900);
      Future<ClosureResult> attempt() => CloseTableTransaction.run(
        orderId: order.orderId,
        money: money,
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 900},
        closedById: 'manager',
        isFiscal: true,
      );

      await attempt();
      await attempt();
      await attempt();

      expect(closedSales(today), hasLength(1));
      expect(
        ClosureJournalRepository.all().where((e) => !e.isReversed),
        hasLength(1),
      );
    });
  });

  group('crash and recovery', () {
    test(
      'a closure interrupted after the sale is finished, not repeated',
      () async {
        final order = await seedOrder(itemTotal: 900);
        final closureId = ClosureJournalRepository.newClosureId();

        // Exactly the state a kill between the sale write and the journal
        // advance leaves behind: the sale exists, the journal still says
        // `started`, the order is still open and its table still occupied.
        await SalesRepository.saveSaleRecord(
          orderId: order.orderId,
          tableNumbers: order.tableNumbers,
          floor: order.floor,
          items: order.items,
          totalAmount: 900,
          paymentMethod: 'cash',
          paymentBreakdown: const {'cash': 900},
          createdBy: order.createdBy,
          createdAt: order.createdAt,
          closedAt: DateTime.parse('${today}T13:00:00'),
          includeServiceFee: false,
          closureId: closureId,
          grossSaleAmount: 900,
          collectedNow: 900,
          businessDate: today,
        );
        await ClosureJournalRepository.write(
          ClosureJournalEntry(
            closureId: closureId,
            orderId: order.orderId,
            phase: ClosurePhase.started,
            businessDate: today,
            isFiscal: true,
            grossSaleAmount: 900,
            advanceApplied: 0,
            collectedNow: 900,
            paymentMethod: 'cash',
            paymentBreakdown: const {'cash': 900},
            actorId: 'manager',
            startedAt: DateTime.parse('${today}T13:00:00'),
          ),
        );

        final outcomes = await ClosureRecoveryService.recoverPending();

        expect(outcomes, hasLength(1));
        expect(outcomes.first.action, ClosureRecoveryAction.finished);
        expect(closedSales(today), hasLength(1));
        expect(grossSalesFor(today), 900);
        expect(DatabaseCore.orderBox!.get(order.orderId)!.status, 'closed');
        expect(ClosureJournalRepository.pending(), isEmpty);
      },
    );

    test(
      'a closure interrupted before the sale is abandoned, not invented',
      () async {
        final order = await seedOrder(itemTotal: 900);
        final closureId = ClosureJournalRepository.newClosureId();
        order.closureId = closureId;
        await order.save();

        await ClosureJournalRepository.write(
          ClosureJournalEntry(
            closureId: closureId,
            orderId: order.orderId,
            phase: ClosurePhase.started,
            businessDate: today,
            isFiscal: true,
            grossSaleAmount: 900,
            advanceApplied: 0,
            collectedNow: 900,
            paymentMethod: 'cash',
            paymentBreakdown: const {'cash': 900},
            actorId: 'manager',
            startedAt: DateTime.parse('${today}T13:00:00'),
          ),
        );

        final outcomes = await ClosureRecoveryService.recoverPending();

        expect(outcomes.first.action, ClosureRecoveryAction.abandoned);
        // No money was recorded, so none is invented.
        expect(closedSales(today), isEmpty);
        expect(grossSalesFor(today), 0);
        // The table is still the staff's to close.
        final reloaded = DatabaseCore.orderBox!.get(order.orderId)!;
        expect(reloaded.status, 'served');
        expect(reloaded.closureId, isNull);
      },
    );

    test('recovery then a real close still books one sale', () async {
      final order = await seedOrder(itemTotal: 900);
      final closureId = ClosureJournalRepository.newClosureId();
      order.closureId = closureId;
      await order.save();
      await ClosureJournalRepository.write(
        ClosureJournalEntry(
          closureId: closureId,
          orderId: order.orderId,
          phase: ClosurePhase.started,
          businessDate: today,
          isFiscal: true,
          grossSaleAmount: 900,
          advanceApplied: 0,
          collectedNow: 900,
          paymentMethod: 'cash',
          paymentBreakdown: const {'cash': 900},
          actorId: 'manager',
          startedAt: DateTime.parse('${today}T13:00:00'),
        ),
      );
      await ClosureRecoveryService.recoverPending();

      final reopened = DatabaseCore.orderBox!.get(order.orderId)!;
      final result = await CloseTableTransaction.run(
        orderId: reopened.orderId,
        money: ClosureMoney.fromOrder(reopened, collectedNow: 900),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 900},
        closedById: 'manager',
        isFiscal: true,
      );

      expect(result.outcome, ClosureOutcome.closed);
      expect(closedSales(today), hasLength(1));
      expect(grossSalesFor(today), 900);
    });
  });

  group('advance on the same day', () {
    test('900 order, 50 advance, 850 card: one 900 sale', () async {
      // The deposit is taken first, which is what writes its receipt.
      final receiptId = await SalesRepository.recordAdvanceReceipt(
        orderId: 1,
        amount: 50,
        collectedBy: 'manager',
      );
      final order = await seedOrder(itemTotal: 900, advance: 50);
      order.advanceReceiptId = receiptId;
      await order.save();

      final result = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 850),
        paymentMethod: 'card-tbc',
        tenderBreakdown: const {'card-tbc': 850},
        closedById: 'manager',
        isFiscal: true,
      );

      expect(result.outcome, ClosureOutcome.closed);
      final sales = closedSales(today);
      expect(sales, hasLength(1), reason: 'no second "advance" sale record');

      final sale = sales.first;
      expect(sale['grossSaleAmount'], 900);
      expect(sale['advanceApplied'], 50);
      expect(sale['collectedNow'], 850);
      // The breakdown sums to gross, with the advance named as its own line
      // rather than masquerading as a tender.
      final breakdown = Map<String, dynamic>.from(
        sale['paymentBreakdown'] as Map,
      );
      expect(breakdown['card-tbc'], 850);
      expect(breakdown['advance'], 50);
      expect(
        breakdown.values.fold<double>(0, (a, b) => a + (b as num).toDouble()),
        900,
      );

      // Revenue is the sale. Cash movement today is the 850 tendered plus the
      // 50 receipt, because both happened today.
      expect(grossSalesFor(today), 900);
      expect(BusinessDayRepository.collectedTotalForDate(today), 900);

      final receipt = SalesRepository.findAdvanceReceipt(receiptId!)!;
      expect(receipt['appliedToClosureId'], result.closureId);
    });
  });

  group('advance from an earlier business day', () {
    test(
      'the receipt stays on its collection day and is not re-collected',
      () async {
        // Day 1: the deposit is taken.
        final receiptId = await SalesRepository.recordAdvanceReceipt(
          orderId: 1,
          amount: 50,
          collectedBy: 'manager',
          businessDate: dayOne,
        );

        // Day 5: the order closes for 900, 850 collected.
        final order = await seedOrder(itemTotal: 900, advance: 50);
        order.advanceCollectedOn = dayOne;
        order.advanceReceiptId = receiptId;
        await order.save();

        await CloseTableTransaction.run(
          orderId: order.orderId,
          money: ClosureMoney.fromOrder(order, collectedNow: 850),
          paymentMethod: 'card-tbc',
          tenderBreakdown: const {'card-tbc': 850},
          closedById: 'manager',
          isFiscal: true,
        );

        // Day 1 holds the 50 that was collected on day 1, and no revenue.
        expect(BusinessDayRepository.collectedTotalForDate(dayOne), 50);
        expect(grossSalesFor(dayOne), 0);

        // Day 5 holds the whole 900 sale, but only the 850 that was tendered.
        expect(grossSalesFor(today), 900);
        expect(BusinessDayRepository.collectedTotalForDate(today), 850);

        // Across both days the money adds up once, not twice.
        expect(
          BusinessDayRepository.collectedTotalForDate(dayOne) +
              BusinessDayRepository.collectedTotalForDate(today),
          900,
        );
      },
    );
  });

  group('internal (non-fiscal) closure', () {
    test('does not inflate revenue and books one sale', () async {
      final paid = await seedOrder(orderId: 1, itemTotal: 400);
      await CloseTableTransaction.run(
        orderId: paid.orderId,
        money: ClosureMoney.fromOrder(paid, collectedNow: 400),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 400},
        closedById: 'manager',
        isFiscal: true,
      );

      final internal = await seedOrder(orderId: 2, itemTotal: 300);
      final result = await CloseTableTransaction.run(
        orderId: internal.orderId,
        money: ClosureMoney.fromOrder(internal, collectedNow: 300),
        paymentMethod: 'non-fiscal',
        tenderBreakdown: const {'cash': 300},
        closedById: 'manager',
        isFiscal: false,
      );

      expect(result.outcome, ClosureOutcome.closed);
      expect(closedSales(today), hasLength(2));
      // Only the paid one is revenue.
      expect(grossSalesFor(today), 400);

      final internalSale = closedSales(
        today,
      ).firstWhere((s) => s['orderId'] == 2);
      expect(internalSale['isFiscal'], isFalse);
      expect(SalesRepository.countsAsRevenue(internalSale), isFalse);
    });

    test('shares the closure identity, so it cannot double either', () async {
      final internal = await seedOrder(orderId: 2, itemTotal: 300);
      final money = ClosureMoney.fromOrder(internal, collectedNow: 300);
      await CloseTableTransaction.run(
        orderId: 2,
        money: money,
        paymentMethod: 'non-fiscal',
        tenderBreakdown: const {'cash': 300},
        closedById: 'manager',
        isFiscal: false,
      );
      final second = await CloseTableTransaction.run(
        orderId: 2,
        money: money,
        paymentMethod: 'non-fiscal',
        tenderBreakdown: const {'cash': 300},
        closedById: 'manager',
        isFiscal: false,
      );

      expect(second.outcome, ClosureOutcome.alreadyClosed);
      expect(closedSales(today), hasLength(1));
    });
  });

  group('void', () {
    test(
      'removes the sale from revenue and leaves the record intact',
      () async {
        final order = await seedOrder(itemTotal: 900, advance: 50);
        await CloseTableTransaction.run(
          orderId: order.orderId,
          money: ClosureMoney.fromOrder(order, collectedNow: 850),
          paymentMethod: 'cash',
          tenderBreakdown: const {'cash': 850},
          closedById: 'manager',
          isFiscal: true,
        );
        expect(grossSalesFor(today), 900);

        final key = closedSales(today).first['recordKey'];
        final outcome = await SalesRepository.cancelSaleRecord(
          recordKey: key,
          cancelledBy: 'manager',
          reason: 'wrong table',
        );

        expect(outcome, SaleCancellationOutcome.cancelled);
        expect(grossSalesFor(today), 0);
        // The record still states what it was worth.
        final voided = closedSales(today).first;
        expect(voided['grossSaleAmount'], 900);
        expect(voided['advanceApplied'], 50);
      },
    );
  });

  group('restore then re-close', () {
    test('books one sale, not two, and keeps the advance once', () async {
      final receiptId = await SalesRepository.recordAdvanceReceipt(
        orderId: 1,
        amount: 50,
        collectedBy: 'manager',
      );
      final order = await seedOrder(itemTotal: 900, advance: 50);
      order.advanceReceiptId = receiptId;
      await order.save();

      final first = await CloseTableTransaction.run(
        orderId: order.orderId,
        money: ClosureMoney.fromOrder(order, collectedNow: 850),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 850},
        closedById: 'manager',
        isFiscal: true,
      );
      expect(grossSalesFor(today), 900);

      final saleKey = closedSales(today).first['recordKey'];
      final restored = await SalesRepository.restoreClosedOrderFromSale(
        recordKey: saleKey,
        restoredBy: 'manager',
      );
      expect(restored, isTrue);

      // Restored to the floor: the sale no longer counts, and the deposit is
      // held against the reopened order again.
      expect(grossSalesFor(today), 0);
      final reopened = DatabaseCore.orderBox!.get(order.orderId)!;
      expect(reopened.advanceAmount, 50);
      expect(reopened.closureId, isNull);
      expect(
        SalesRepository.findAdvanceReceipt(receiptId!)!['appliedToClosureId'],
        isNull,
      );

      // Closing again is a new closure, not a refused retry of the old one.
      final second = await CloseTableTransaction.run(
        orderId: reopened.orderId,
        money: ClosureMoney.fromOrder(reopened, collectedNow: 850),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 850},
        closedById: 'manager',
        isFiscal: true,
      );

      expect(second.outcome, ClosureOutcome.closed);
      expect(second.closureId, isNot(first.closureId));
      // Two records exist — the reversed one and the live one — but only one
      // counts, so revenue is 900 and not 1800.
      expect(closedSales(today), hasLength(2));
      expect(
        closedSales(today).where(SalesRepository.countsAsRevenue),
        hasLength(1),
      );
      expect(grossSalesFor(today), 900);
      expect(BusinessDayRepository.collectedTotalForDate(today), 900);
    });
  });

  group('X / Z reconciliation', () {
    /// The payment split exactly as the X and Z reports now build it:
    /// revenue records only, with the applied advance kept out of the tender
    /// lines. Before Phase 1B the X report applied no filter at all and the Z
    /// report filtered on `isFiscal` alone, so both counted voided and
    /// restored sales that the headline total excluded — which is why the Z
    /// figure read higher than the day's takings.
    ({double tender, double advance, int orders}) split(String date) {
      var tender = 0.0;
      var advance = 0.0;
      var orders = 0;
      for (final sale in salesFor(date)) {
        if (!SalesRepository.countsAsRevenue(sale)) continue;
        orders++;
        final breakdown =
            (sale['paymentBreakdown'] as Map?)?.cast<String, dynamic>() ??
            const {};
        breakdown.forEach((key, value) {
          final amount = (value as num).toDouble();
          if (key == 'advance') {
            advance += amount;
          } else {
            tender += amount;
          }
        });
      }
      return (tender: tender, advance: advance, orders: orders);
    }

    test('the split reconciles to gross sales across a messy day', () async {
      // Paid 400 cash.
      final a = await seedOrder(orderId: 1, itemTotal: 400);
      await CloseTableTransaction.run(
        orderId: 1,
        money: ClosureMoney.fromOrder(a, collectedNow: 400),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 400},
        closedById: 'manager',
        isFiscal: true,
      );

      // Paid 900 with a 50 deposit, 850 on card.
      final receiptId = await SalesRepository.recordAdvanceReceipt(
        orderId: 2,
        amount: 50,
        collectedBy: 'manager',
      );
      final b = await seedOrder(orderId: 2, itemTotal: 900, advance: 50);
      b.advanceReceiptId = receiptId;
      await b.save();
      await CloseTableTransaction.run(
        orderId: 2,
        money: ClosureMoney.fromOrder(b, collectedNow: 850),
        paymentMethod: 'card-tbc',
        tenderBreakdown: const {'card-tbc': 850},
        closedById: 'manager',
        isFiscal: true,
      );

      // An internal closure — money moved, but not into revenue.
      final c = await seedOrder(orderId: 3, itemTotal: 300);
      await CloseTableTransaction.run(
        orderId: 3,
        money: ClosureMoney.fromOrder(c, collectedNow: 300),
        paymentMethod: 'non-fiscal',
        tenderBreakdown: const {'cash': 300},
        closedById: 'manager',
        isFiscal: false,
      );

      // A sale that gets voided.
      final d = await seedOrder(orderId: 4, itemTotal: 200);
      await CloseTableTransaction.run(
        orderId: 4,
        money: ClosureMoney.fromOrder(d, collectedNow: 200),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 200},
        closedById: 'manager',
        isFiscal: true,
      );
      await SalesRepository.cancelSaleRecord(
        recordKey: closedSales(
          today,
        ).firstWhere((s) => s['orderId'] == 4)['recordKey'],
        cancelledBy: 'manager',
        reason: 'rung twice',
      );

      // A sale that gets restored to the floor.
      final e = await seedOrder(orderId: 5, itemTotal: 150);
      await CloseTableTransaction.run(
        orderId: 5,
        money: ClosureMoney.fromOrder(e, collectedNow: 150),
        paymentMethod: 'cash',
        tenderBreakdown: const {'cash': 150},
        closedById: 'manager',
        isFiscal: true,
      );
      await SalesRepository.restoreClosedOrderFromSale(
        recordKey: closedSales(
          today,
        ).firstWhere((s) => s['orderId'] == 5)['recordKey'],
        restoredBy: 'manager',
      );

      final gross = grossSalesFor(today);
      final s = split(today);

      // Revenue is the 400 and the 900. Not the internal 300, not the voided
      // 200, not the 150 back on the floor.
      expect(gross, 1300);
      expect(s.orders, 2);
      // The identity the reports now print as their control line.
      expect(s.tender + s.advance, gross);
      expect(s.tender, 1250);
      expect(s.advance, 50);

      // Takings: 400 + 850 tendered today, plus the 50 deposit taken today.
      // The voided 200 and the restored 150 are reversed, and the internal
      // closure never entered the day's takings.
      expect(BusinessDayRepository.collectedTotalForDate(today), 1300);
    });

    test(
      'a voided sale no longer inflates the split above the total',
      () async {
        final a = await seedOrder(orderId: 1, itemTotal: 500);
        await CloseTableTransaction.run(
          orderId: 1,
          money: ClosureMoney.fromOrder(a, collectedNow: 500),
          paymentMethod: 'cash',
          tenderBreakdown: const {'cash': 500},
          closedById: 'manager',
          isFiscal: true,
        );
        await SalesRepository.cancelSaleRecord(
          recordKey: closedSales(today).first['recordKey'],
          cancelledBy: 'manager',
          reason: 'guest walked',
        );

        expect(grossSalesFor(today), 0);
        // The record is still there, still stating 500 — it simply no longer
        // counts anywhere.
        expect(closedSales(today), hasLength(1));
        expect(split(today).tender, 0);
      },
    );
  });

  group('the daily total', () {
    test(
      'equals the records it summarizes after every kind of event',
      () async {
        // A paid close, an internal close, a void and a deposit.
        final a = await seedOrder(orderId: 1, itemTotal: 400);
        await CloseTableTransaction.run(
          orderId: 1,
          money: ClosureMoney.fromOrder(a, collectedNow: 400),
          paymentMethod: 'cash',
          tenderBreakdown: const {'cash': 400},
          closedById: 'manager',
          isFiscal: true,
        );
        final b = await seedOrder(orderId: 2, itemTotal: 300);
        await CloseTableTransaction.run(
          orderId: 2,
          money: ClosureMoney.fromOrder(b, collectedNow: 300),
          paymentMethod: 'non-fiscal',
          tenderBreakdown: const {'cash': 300},
          closedById: 'manager',
          isFiscal: false,
        );
        final c = await seedOrder(orderId: 3, itemTotal: 200);
        await CloseTableTransaction.run(
          orderId: 3,
          money: ClosureMoney.fromOrder(c, collectedNow: 200),
          paymentMethod: 'cash',
          tenderBreakdown: const {'cash': 200},
          closedById: 'manager',
          isFiscal: true,
        );
        await SalesRepository.recordAdvanceReceipt(
          orderId: 4,
          amount: 75,
          collectedBy: 'manager',
        );

        final voidKey = closedSales(
          today,
        ).firstWhere((s) => s['orderId'] == 3)['recordKey'];
        await SalesRepository.cancelSaleRecord(
          recordKey: voidKey,
          cancelledBy: 'manager',
          reason: 'entered twice',
        );

        // Revenue: only the 400 paid close. Not the internal 300, not the
        // voided 200, not the 75 deposit.
        final expected = closedSales(today)
            .where(SalesRepository.countsAsRevenue)
            .fold<double>(0, (sum, s) => sum + SalesRepository.grossOf(s));
        expect(expected, 400);
        expect(grossSalesFor(today), 400);
        expect(
          SalesRepository.getDailySalesTotal(),
          400,
          reason: 'the stored counter agrees with the derived figure',
        );

        // Cash movement: 400 collected + 75 deposit. The internal closure moved
        // no money into the day's takings, and the void reversed its 200.
        expect(BusinessDayRepository.collectedTotalForDate(today), 475);
      },
    );
  });
}

/// Local alias so the assertions read as "gross sales for that date".
double grossSalesFor(String date) =>
    BusinessDayRepository.grossSalesTotalForDate(date);
