import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/sale_record.dart';

/// Task 1 (docs/VYNIC_ROADMAP.md): the typed [SaleRecord] must represent the
/// legacy sales-box maps losslessly so later tasks can dual-write and
/// union-read without changing behavior.
void main() {
  /// A record exactly as `SalesRepository.saveSaleRecord` writes it today
  /// (post-v4 migration shape: the read-time defaults are materialized).
  Map<String, dynamic> legacyFixture() => {
    'orderId': 118,
    'tableNumbers': ['Table 4', 'Table 5'],
    'floor': 'first',
    'items': [
      {'itemName': 'ხინკალი', 'quantity': 10, 'unitPrice': 1.5, 'total': 15.0},
      {'itemName': 'ლუდი', 'quantity': 2, 'unitPrice': 6.0, 'total': 12.0},
    ],
    'totalAmount': 29.7,
    'total': 29.7,
    'paymentMethod': 'cash',
    'paymentBreakdown': {'cash': 29.7},
    'customPaymentLabel': null,
    'createdBy': 'waiter1',
    'createdAt': '2026-07-20T13:05:00.000',
    'closedAt': '2026-07-20T14:40:00.000',
    'includeServiceFee': true,
    'discountAmount': 0.0,
    'advanceAmount': 0.0,
    'subtotalAmount': 27.0,
    'manualAdjustmentAmount': 0.0,
    'finalTransaction': {
      'tableId': 'Table 4',
      'orderId': 118,
      'isFiscal': true,
    },
    'date': '2026-07-20',
    'isCancelled': false,
    'isFiscal': true,
    'restoredToOrder': false,
  };

  group('SaleRecord legacy round trip', () {
    test('fromMap(toMap(fromMap(x))) preserves the legacy shape exactly', () {
      final record = SaleRecord.fromMap(legacyFixture());
      final emitted = record.toMap();
      expect(emitted, equals(legacyFixture()));
    });

    test('legacy fields are parsed faithfully', () {
      final record = SaleRecord.fromMap(legacyFixture());
      expect(record.closureId, isNull);
      expect(record.orderId, 118);
      expect(record.tableNumbers, ['Table 4', 'Table 5']);
      expect(record.items, hasLength(2));
      expect(record.items.first.itemName, 'ხინკალი');
      expect(record.totalAmount, 29.7);
      expect(record.subtotalAmount, 27.0);
      expect(record.paymentBreakdown, {'cash': 29.7});
      expect(record.businessDate, '2026-07-20');
      expect(record.isFiscal, isTrue);
      expect(record.isCancelled, isFalse);
      expect(record.restoredToOrder, isFalse);
      expect(record.tipAmount, 0.0);
      expect(record.closedById, isNull);
    });

    test('cancelled + restored records round-trip their extra keys', () {
      final map = legacyFixture()
        ..['isCancelled'] = true
        ..['cancelledAt'] = '2026-07-20T15:00:00.000'
        ..['restoredToOrder'] = true
        ..['restoredAt'] = '2026-07-20T15:05:00.000'
        ..['restoredBy'] = 'manager1';
      final emitted = SaleRecord.fromMap(map).toMap();
      expect(emitted, equals(map));
    });

    test('defaults match the read path when keys are missing', () {
      // Pre-v4 records lack isCancelled/restoredToOrder/isFiscal; the read
      // path (SalesRepository._mapSalesRecords) defaults them like this.
      final map = legacyFixture()
        ..remove('isCancelled')
        ..remove('restoredToOrder')
        ..remove('isFiscal');
      final record = SaleRecord.fromMap(map);
      expect(record.isCancelled, isFalse);
      expect(record.restoredToOrder, isFalse);
      expect(record.isFiscal, isTrue);
    });

    test('tolerates the sync/report item shape (name/price)', () {
      final record = SaleRecord.fromMap({
        ...legacyFixture(),
        'items': [
          {'name': 'ხაჭაპური', 'quantity': 2, 'price': 9.0},
        ],
      });
      expect(record.items.single.itemName, 'ხაჭაპური');
      expect(record.items.single.unitPrice, 9.0);
      expect(record.items.single.total, 18.0);
    });

    test('falls back from totalAmount to total like existing readers', () {
      final map = legacyFixture()..remove('totalAmount');
      expect(SaleRecord.fromMap(map).totalAmount, 29.7);
    });
  });

  group('Order.closureId (schema only)', () {
    Order buildOrder() => Order(
      orderId: 7,
      tableNumbers: ['Table 1'],
      floor: 'first',
      items: [],
      totalAmount: 0,
      createdAt: DateTime(2026, 7, 20, 12),
      createdBy: 'waiter1',
    );

    test('defaults to null and is untouched by recalculateTotal', () {
      final order = buildOrder();
      expect(order.closureId, isNull);
      order.recalculateTotal();
      expect(order.closureId, isNull);
    });

    test('clone carries closureId', () {
      final order = buildOrder()..closureId = 'closure-abc';
      expect(order.clone().closureId, 'closure-abc');
    });

    test('toJson/fromJson round-trips closureId', () {
      final order = buildOrder()..closureId = 'closure-abc';
      final revived = Order.fromJson(order.toJson());
      expect(revived.closureId, 'closure-abc');
    });

    test('fromJson without the key (old backups, server payloads) is null', () {
      final json = buildOrder().toJson()..remove('closureId');
      expect(Order.fromJson(json).closureId, isNull);
    });
  });
}
