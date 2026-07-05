// Tests for [OrderStatus] parsing/mapping — the Phase 4 status-enum
// foundation. Locks in exact-match canonicalization and the legacy 'paid'
// alias so future changes to this file are deliberate.

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';

void main() {
  group('OrderStatus.fromStorage', () {
    test('parses every canonical value', () {
      expect(OrderStatus.fromStorage('pending'), OrderStatus.pending);
      expect(OrderStatus.fromStorage('confirmed'), OrderStatus.confirmed);
      expect(OrderStatus.fromStorage('preparing'), OrderStatus.preparing);
      expect(OrderStatus.fromStorage('served'), OrderStatus.served);
      expect(OrderStatus.fromStorage('closed'), OrderStatus.closed);
      expect(OrderStatus.fromStorage('cancelled'), OrderStatus.cancelled);
    });

    test('treats legacy "paid" as an alias for closed', () {
      expect(OrderStatus.fromStorage('paid'), OrderStatus.closed);
    });

    test('treats legacy "canceled" (single L) as cancelled', () {
      expect(OrderStatus.fromStorage('canceled'), OrderStatus.cancelled);
    });

    test('normalizes case and surrounding whitespace', () {
      expect(OrderStatus.fromStorage('  CONFIRMED  '), OrderStatus.confirmed);
    });

    test('maps null and unrecognized values to unknown, not pending', () {
      expect(OrderStatus.fromStorage(null), OrderStatus.unknown);
      expect(OrderStatus.fromStorage(''), OrderStatus.unknown);
      expect(OrderStatus.fromStorage('garbage'), OrderStatus.unknown);
    });
  });

  group('OrderStatus.storageValue', () {
    test('round-trips every canonical value', () {
      for (final status in OrderStatus.values) {
        if (status == OrderStatus.unknown) continue;
        expect(OrderStatus.fromStorage(status.storageValue), status);
      }
    });

    test('unknown has no storage representation', () {
      expect(() => OrderStatus.unknown.storageValue, throwsStateError);
    });
  });

  group('OrderStatus.isTerminal', () {
    test('closed and cancelled are terminal', () {
      expect(OrderStatus.closed.isTerminal, isTrue);
      expect(OrderStatus.cancelled.isTerminal, isTrue);
    });

    test('legacy paid alias is terminal (via closed)', () {
      expect(OrderStatus.fromStorage('paid').isTerminal, isTrue);
    });

    test('pending, confirmed, preparing, served are not terminal', () {
      expect(OrderStatus.pending.isTerminal, isFalse);
      expect(OrderStatus.confirmed.isTerminal, isFalse);
      expect(OrderStatus.preparing.isTerminal, isFalse);
      expect(OrderStatus.served.isTerminal, isFalse);
    });

    test('unknown is not terminal', () {
      expect(OrderStatus.unknown.isTerminal, isFalse);
    });
  });

  group('Order.statusEnum', () {
    Order buildOrder({String status = 'pending'}) => Order(
      orderId: 1,
      tableNumbers: const ['1'],
      floor: 'first',
      items: const [],
      totalAmount: 0,
      createdAt: DateTime(2026, 1, 1),
      createdBy: 'tester',
      status: status,
    );

    test('reads the raw string field through the enum', () {
      expect(buildOrder(status: 'confirmed').statusEnum, OrderStatus.confirmed);
    });

    test('legacy raw "paid" reads as closed via the enum', () {
      expect(buildOrder(status: 'paid').statusEnum, OrderStatus.closed);
    });

    test('writing the enum updates the raw string field', () {
      final order = buildOrder();
      order.statusEnum = OrderStatus.closed;
      expect(order.status, 'closed');
    });
  });
}
