import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/sale_visibility.dart';

void main() {
  test(
    'feature hides internal closes but retains advances, cancellations and original history',
    () {
      final rows = <Map<String, dynamic>>[
        {'id': 'fiscal', 'isFiscal': true},
        {'id': 'internal', 'isFiscal': false},
        {'id': 'advance', 'isFiscal': false, 'recordType': 'advance_receipt'},
        {'id': 'cancel', 'isFiscal': false, 'isCancelled': true},
        {
          'id': 'legacy',
          'paymentBreakdown': {'non-fiscal': 10},
        },
      ];
      expect(
        rows
            .where((s) => SaleVisibility.visible(s, nonFiscalEnabled: false))
            .map((s) => s['id']),
        ['fiscal', 'advance', 'cancel'],
      );
      expect(
        rows
            .where((s) => SaleVisibility.visible(s, nonFiscalEnabled: true))
            .length,
        5,
      );
      expect(rows.length, 5);
    },
  );
}
