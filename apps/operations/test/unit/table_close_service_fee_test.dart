import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/pos/table_payment_service.dart';

/// Regression tests for the service-fee rate mismatch between the amount the
/// guest is charged and the amount recorded on the sale.
///
/// Before the fix, `_startTableClosureFlow` recalculated the order total with
/// the *global* rate (an explicitly passed rate used to win over the order's
/// own custom percentage) while `_finalizeTableClosure` recorded a total
/// re-derived from `getServiceFee()`, which resolved the *custom* percentage.
/// A ₾100 order with a 5% custom fee under a 10% global rate collected ₾110
/// and booked ₾105.
void main() {
  const globalRate = 0.10; // 10% configured for the venue

  setUp(() {
    Order.serviceFeeRateResolver = () => globalRate;
  });

  tearDown(() {
    Order.serviceFeeRateResolver = null;
  });

  double round2(double value) => double.parse(value.toStringAsFixed(2));

  Order buildOrder({double? customPercent, double discount = 0.0}) {
    return Order(
      orderId: 1,
      tableNumbers: ['Table 1'],
      floor: 'first',
      items: [
        OrderItem(
          itemKey: 'item',
          itemName: 'item',
          unitPrice: 100.0,
          quantity: 1,
          total: 100.0,
        ),
      ],
      totalAmount: 0,
      createdAt: DateTime(2026, 7, 21, 12),
      createdBy: 'waiter1',
      includeServiceFee: true,
      discountAmount: discount,
      customServiceFeePercentage: customPercent,
    );
  }

  TablePaymentSelection splitTender(double total) {
    final bank = round2(total / 2);
    return TablePaymentSelection(
      method: TablePaymentMethod.split,
      cashAmount: round2(total - bank),
      bankAmount: bank,
      bankProvider: 'tbc',
    );
  }

  TablePaymentSelection cashTender(double total) => TablePaymentSelection(
    method: TablePaymentMethod.cash,
    cashAmount: round2(total),
    bankAmount: 0,
  );

  TablePaymentSelection cardTender(double total) => TablePaymentSelection(
    method: TablePaymentMethod.bank,
    cashAmount: 0,
    bankAmount: round2(total),
    bankProvider: 'tbc',
  );

  /// Mirrors the production close sequence:
  /// `_startTableClosureFlow` (recalculate with the global rate, hand
  /// `order.totalAmount` to the payment dialog) then `_finalizeTableClosure`
  /// (recalculate again, record `order.totalAmount`, print the same value).
  ({
    double charged,
    double recorded,
    double receiptTotal,
    Map<String, double>? breakdown,
    String? mismatch,
  })
  simulateClose(
    Order order,
    TablePaymentSelection Function(double total) tender,
  ) {
    // _startTableClosureFlow (order_detail_screen.dart:2089-2113)
    order.recalculateTotal(serviceFeeRate: globalRate);
    final charged = order.totalAmount;
    final selection = tender(charged);

    // _finalizeTableClosure (order_detail_screen.dart:2356+)
    order.recalculateTotal(serviceFeeRate: globalRate);
    final recorded = order.totalAmount; // saveSaleRecord(totalAmount: ...)
    final receiptTotal = recorded; // printReceiptInBackground(total: ...)
    final breakdown = TableClosureHelper.buildSaleBreakdown(selection);

    return (
      charged: charged,
      recorded: recorded,
      receiptTotal: receiptTotal,
      breakdown: breakdown,
      mismatch: TableClosureHelper.describeBreakdownMismatch(
        breakdown: breakdown,
        total: recorded,
      ),
    );
  }

  void expectReconciled(
    ({
      double charged,
      double recorded,
      double receiptTotal,
      Map<String, double>? breakdown,
      String? mismatch,
    })
    result,
    double expectedTotal,
  ) {
    expect(result.charged, expectedTotal, reason: 'amount charged to guest');
    expect(result.recorded, expectedTotal, reason: 'sale record total');
    expect(result.receiptTotal, expectedTotal, reason: 'printed receipt total');
    final breakdownSum = result.breakdown!.values.fold<double>(
      0,
      (a, b) => a + b,
    );
    expect(round2(breakdownSum), expectedTotal, reason: 'tendered total');
    expect(result.mismatch, isNull, reason: 'close must not be blocked');
  }

  group('traced scenario: ₾100 item, 5% custom fee, 10% global rate', () {
    // The custom rate is the one the operator set on this order, so ₾105 is
    // the correct number to both charge and book.
    const expectedTotal = 105.0;

    test('split into two parts', () {
      expectReconciled(
        simulateClose(buildOrder(customPercent: 5), splitTender),
        expectedTotal,
      );
    });

    test('cash', () {
      expectReconciled(
        simulateClose(buildOrder(customPercent: 5), cashTender),
        expectedTotal,
      );
    });

    test('card', () {
      expectReconciled(
        simulateClose(buildOrder(customPercent: 5), cardTender),
        expectedTotal,
      );
    });

    test('a custom rate above the global rate also reconciles', () {
      expectReconciled(
        simulateClose(buildOrder(customPercent: 15), splitTender),
        115.0,
      );
    });

    test('custom rate with a discount reconciles', () {
      // 100 + 5% fee - 20 discount = 85
      expectReconciled(
        simulateClose(buildOrder(customPercent: 5, discount: 20), splitTender),
        85.0,
      );
    });
  });

  group('no custom rate — behavior unchanged', () {
    const expectedTotal = 110.0; // 100 + global 10%

    test('split', () {
      expectReconciled(simulateClose(buildOrder(), splitTender), expectedTotal);
    });

    test('cash', () {
      expectReconciled(simulateClose(buildOrder(), cashTender), expectedTotal);
    });

    test('card', () {
      expectReconciled(simulateClose(buildOrder(), cardTender), expectedTotal);
    });

    test('service fee disabled charges and books the bare subtotal', () {
      final order = buildOrder()..includeServiceFee = false;
      expectReconciled(simulateClose(order, splitTender), 100.0);
    });
  });

  group('rate resolution is a single source of truth', () {
    test(
      'getServiceFee matches the fee embedded in the recalculated total',
      () {
        final order = buildOrder(customPercent: 5);
        order.recalculateTotal(serviceFeeRate: globalRate);
        final feeInTotal = round2(
          order.totalAmount - order.getAdditionalItemsSubtotal(),
        );
        expect(order.getServiceFee(), feeInTotal);
        expect(order.getServiceFee(), 5.0);
      },
    );

    test('a custom percentage wins over an explicitly passed global rate', () {
      final order = buildOrder(customPercent: 5);
      order.recalculateTotal(serviceFeeRate: globalRate);
      expect(order.totalAmount, 105.0);
    });

    test('an explicit rate still applies when no custom percentage is set', () {
      final order = buildOrder();
      order.recalculateTotal(serviceFeeRate: 0.20);
      expect(order.totalAmount, 120.0);
    });

    test('the total no longer flips between recalculation call styles', () {
      final order = buildOrder(customPercent: 5);
      order.recalculateTotal(serviceFeeRate: globalRate); // close flow
      final viaExplicitRate = order.totalAmount;
      order.recalculateTotal(); // addItem / removeItem / quantity change
      expect(order.totalAmount, viaExplicitRate);
    });
  });

  group('breakdown reconciliation gate', () {
    test('accepts a breakdown that matches the total', () {
      expect(
        TableClosureHelper.describeBreakdownMismatch(
          breakdown: {'cash': 55.0, 'card-tbc': 50.0},
          total: 105.0,
        ),
        isNull,
      );
    });

    test('tolerates rounding within one tetri', () {
      expect(
        TableClosureHelper.describeBreakdownMismatch(
          breakdown: {'cash': 105.01},
          total: 105.0,
        ),
        isNull,
      );
    });

    test('rejects the pre-fix mismatch (charged 110, booked 105)', () {
      final mismatch = TableClosureHelper.describeBreakdownMismatch(
        breakdown: {'cash': 55.0, 'card-tbc': 55.0},
        total: 105.0,
      );
      expect(mismatch, isNotNull);
      expect(mismatch, contains('110.00'));
      expect(mismatch, contains('105.00'));
      expect(mismatch, contains('5.00'));
    });

    test('rejects an empty breakdown', () {
      expect(
        TableClosureHelper.describeBreakdownMismatch(
          breakdown: null,
          total: 105.0,
        ),
        isNotNull,
      );
      expect(
        TableClosureHelper.describeBreakdownMismatch(
          breakdown: const {},
          total: 105.0,
        ),
        isNotNull,
      );
    });
  });
}
