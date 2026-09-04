import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/sync/manager_sales_history_builder.dart';

void main() {
  const date = '2026-09-04';

  Map<String, dynamic> sale({
    required int orderId,
    required double gross,
    required Map<String, double> breakdown,
    bool isFiscal = true,
    bool isCancelled = false,
    bool restored = false,
    double advanceApplied = 0,
  }) => {
    'recordType': 'sale',
    'orderId': orderId,
    'date': date,
    'grossSaleAmount': gross,
    'totalAmount': gross,
    'advanceApplied': advanceApplied,
    'collectedNow': gross - advanceApplied,
    'paymentBreakdown': breakdown,
    'isFiscal': isFiscal,
    'isCancelled': isCancelled,
    'restoredToOrder': restored,
    'tableNumbers': ['$orderId'],
    'floor': 'first',
    'closedAt': '${date}T18:00:00.000',
    'items': [
      {'itemName': 'Item $orderId', 'quantity': 1, 'unitPrice': gross},
    ],
  };

  test('daily and monthly source rows use Sale revenue truth', () {
    final history = ManagerSalesHistoryBuilder.build(
      sales: [
        sale(orderId: 1, gross: 100, breakdown: const {'cash': 100}),
        sale(orderId: 2, gross: 100, breakdown: const {'card-tbc': 100}),
        sale(
          orderId: 3,
          gross: 100,
          breakdown: const {'cash': 40, 'card-bog': 60},
        ),
        sale(
          orderId: 4,
          gross: 100,
          advanceApplied: 20,
          breakdown: const {'cash': 80, 'advance': 20},
        ),
        sale(
          orderId: 5,
          gross: 900,
          breakdown: const {'cash': 900},
          isFiscal: false,
        ),
        sale(
          orderId: 6,
          gross: 800,
          breakdown: const {'cash': 800},
          isCancelled: true,
        ),
        sale(
          orderId: 7,
          gross: 700,
          breakdown: const {'card-tbc': 700},
          restored: true,
        ),
        {
          'recordType': 'advance_receipt',
          'orderId': 8,
          'date': date,
          'totalAmount': 20.0,
          'grossSaleAmount': 20.0,
          'collectedNow': 20.0,
          'paymentBreakdown': const {'advance': 20.0},
          'isFiscal': false,
        },
      ],
      expenseTotalForDate: (_) => 25,
    );

    final day = history[date]!;
    expect(day['totalRevenue'], 400);
    expect(day['orderCount'], 4);
    expect(day['totalOrders'], 7);
    expect(day['cancelledOrders'], 1);
    expect(day['advanceReceived'], 20);
    expect(day['cashRevenue'], 220);
    expect(day['cardRevenue'], 160);
    expect(day['profit'], 375);

    final breakdown = Map<String, double>.from(day['paymentBreakdown'] as Map);
    expect(breakdown, {
      'cash': 220,
      'card-tbc': 100,
      'card-bog': 60,
      'advance': 20,
    });
    expect(breakdown.containsKey('non-fiscal'), isFalse);

    final closedTables = (day['closedTables'] as List).whereType<Map>();
    expect(closedTables, hasLength(4));
    expect(
      closedTables.map((entry) => entry['orderId']),
      orderedEquals([1, 2, 3, 4]),
    );
    final topItems = (day['topItems'] as List).whereType<Map>();
    expect(topItems, hasLength(4));
    expect(
      topItems.map((entry) => entry['name']),
      unorderedEquals(['Item 1', 'Item 2', 'Item 3', 'Item 4']),
    );
  });

  test('an internal-only day exists operationally with zero revenue', () {
    final history = ManagerSalesHistoryBuilder.build(
      sales: [
        sale(
          orderId: 10,
          gross: 100,
          breakdown: const {'cash': 100},
          isFiscal: false,
        ),
      ],
      expenseTotalForDate: (_) => 0,
    );

    final day = history[date]!;
    expect(day['totalRevenue'], 0);
    expect(day['orderCount'], 0);
    expect(day['totalOrders'], 1);
    expect(day['paymentBreakdown'], isEmpty);
    expect(day['closedTables'], isEmpty);
    expect(day['topItems'], isEmpty);
  });
}
