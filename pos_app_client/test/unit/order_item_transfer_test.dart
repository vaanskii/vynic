import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/services/pos/order_item_transfer.dart';

/// Moving items between two open orders changes what two different people owe,
/// at the same time. These check the arithmetic in memory — no database, no
/// dialog — because that is the part where being nearly right is a refund.

OrderItem _line(
  String name,
  double unitPrice,
  int quantity, {
  String? comment,
  double? total,
}) {
  return OrderItem(
    // The key is the dish, never the comment: `_addToCartEntry` keys the cart
    // by item name (plus variant) and carries the comment alongside. Folding
    // the comment in here would have made the merge tests below pass for the
    // wrong reason — on a key mismatch rather than on the comment itself.
    itemKey: name,
    itemName: name,
    unitPrice: unitPrice,
    quantity: quantity,
    total: total ?? unitPrice * quantity,
    comment: comment,
  );
}

Order _order({
  required int id,
  required List<OrderItem> items,
  String floor = 'first',
  List<String>? tables,
  String status = 'confirmed',
  bool serviceFee = false,
}) {
  final order = Order(
    orderId: id,
    tableNumbers: tables ?? ['$id'],
    floor: floor,
    items: items,
    totalAmount: 0,
    createdAt: DateTime(2026, 8, 23, 19),
    createdBy: 'გიორგი',
    includeServiceFee: serviceFee,
  )..status = status;
  order.recalculateTotal();
  return order;
}

void main() {
  setUpAll(() {
    // The model reads the live service-fee setting through this hook; without
    // a database behind it the tests would be measuring whatever the last one
    // left in a static.
    Order.serviceFeeRateResolver = () => 0.10;
  });

  tearDownAll(() => Order.serviceFeeRateResolver = null);

  group('moving part of a line', () {
    test('splits the quantity and the money between the two orders', () {
      final source = _order(id: 1, items: [_line('ხინკალი', 2.50, 10)]);
      final destination = _order(id: 2, items: []);

      final result = OrderItemTransfer.move(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 4)],
      );

      expect(result.ok, isTrue);
      expect(source.items.single.quantity, 6);
      expect(source.items.single.total, 15.00);
      expect(destination.items.single.quantity, 4);
      expect(destination.items.single.total, 10.00);
      // Nothing was created or destroyed on the way across.
      expect(source.totalAmount + destination.totalAmount, 25.00);
    });

    test(
      'the two halves still add up when the line total is not q x price',
      () {
        // A line whose total does not equal unitPrice x quantity — a hand-keyed
        // price, or a rounding from an older build. Recomputing from the unit
        // price would quietly reprice the bill, so the existing total is split
        // instead and the halves have to close.
        final source = _order(
          id: 1,
          items: [_line('ღვინო', 12.00, 3, total: 33.33)],
        );
        final destination = _order(id: 2, items: []);

        OrderItemTransfer.move(
          source: source,
          destination: destination,
          moves: const [(index: 0, quantity: 1)],
        );

        expect(destination.items.single.total, 11.11);
        expect(source.items.single.total, 22.22);
        expect(
          source.items.single.total + destination.items.single.total,
          33.33,
        );
      },
    );

    test('moving every unit removes the line rather than leaving a zero', () {
      final source = _order(
        id: 1,
        items: [_line('ხინკალი', 2.50, 10), _line('მწვადი', 18.00, 2)],
      );
      final destination = _order(id: 2, items: []);

      OrderItemTransfer.move(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 10)],
      );

      expect(source.items.map((i) => i.itemName), ['მწვადი']);
      expect(destination.items.single.quantity, 10);
    });
  });

  group('landing on the destination', () {
    test('stacks onto a line that is already the same thing', () {
      final source = _order(id: 1, items: [_line('ხინკალი', 2.50, 6)]);
      final destination = _order(id: 2, items: [_line('ხინკალი', 2.50, 4)]);

      OrderItemTransfer.move(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 5)],
      );

      expect(destination.items.length, 1);
      expect(destination.items.single.quantity, 9);
      expect(destination.items.single.total, 22.50);
    });

    test('keeps a line with a different comment separate', () {
      // „ხახვის გარეშე" is the whole reason the kitchen made it differently.
      // Merging on the item key alone would drop it.
      final source = _order(
        id: 1,
        items: [_line('სალათი', 14.00, 2, comment: 'ხახვის გარეშე')],
      );
      final destination = _order(id: 2, items: [_line('სალათი', 14.00, 1)]);

      OrderItemTransfer.move(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 2)],
      );

      expect(destination.items.length, 2);
      expect(
        destination.items.map((i) => i.comment),
        containsAll(<String?>[null, 'ხახვის გარეშე']),
      );
    });

    test('an empty comment and no comment are the same thing', () {
      final source = _order(
        id: 1,
        items: [_line('პური', 1.50, 2, comment: '  ')],
      );
      final destination = _order(id: 2, items: [_line('პური', 1.50, 1)]);

      OrderItemTransfer.move(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 2)],
      );

      expect(destination.items.length, 1);
      expect(destination.items.single.quantity, 3);
    });
  });

  group('several lines at once', () {
    test('moves each of them and reports what went', () {
      final source = _order(
        id: 1,
        items: [
          _line('ხინკალი', 2.50, 10),
          _line('მწვადი', 18.00, 4),
          _line('საფერავი', 42.00, 2),
        ],
      );
      final destination = _order(id: 2, items: []);

      final result = OrderItemTransfer.move(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 10), (index: 2, quantity: 1)],
      );

      expect(result.ok, isTrue);
      expect(result.totalQuantity, 11);
      expect(result.totalAmount, 67.00);
      // Reported in the order they were picked, not the order the loop
      // happened to need to walk them in.
      expect(result.moved.map((l) => l.itemName), ['ხინკალი', 'საფერავი']);
      expect(source.items.map((i) => i.itemName), ['მწვადი', 'საფერავი']);
      expect(source.items.last.quantity, 1);
    });

    test('emptying the source is allowed, and is reported', () {
      // A whole party moving tables is the ordinary case, not an error — but
      // the caller has to be able to warn that a table is now open with
      // nothing on it.
      final source = _order(id: 1, items: [_line('ხინკალი', 2.50, 4)]);
      final destination = _order(id: 2, items: []);

      final result = OrderItemTransfer.move(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 4)],
      );

      expect(result.ok, isTrue);
      expect(result.sourceLeftEmpty, isTrue);
      expect(source.totalAmount, 0);
    });
  });

  group('service fee', () {
    test('each order charges its own fee on what it now holds', () {
      // Moving off a table that charges service onto one that does not is a
      // real change in what is owed. It is the operator's decision, but the
      // totals have to follow it honestly.
      final source = _order(
        id: 1,
        items: [_line('მწვადი', 18.00, 4)],
        serviceFee: true,
      );
      final destination = _order(id: 2, items: [], serviceFee: false);
      expect(source.totalAmount, 79.20); // 72 + 10%

      OrderItemTransfer.move(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 2)],
      );

      expect(source.totalAmount, 39.60); // 36 + 10%
      expect(destination.totalAmount, 36.00); // no fee on this one
    });
  });

  group('refusals', () {
    test('an order cannot be moved onto itself', () {
      final order = _order(id: 1, items: [_line('ხინკალი', 2.50, 4)]);
      final twin = _order(id: 1, items: [_line('ხინკალი', 2.50, 4)]);

      expect(
        OrderItemTransfer.move(
          source: order,
          destination: twin,
          moves: const [(index: 0, quantity: 1)],
        ).error,
        OrderTransferError.sameOrder,
      );
    });

    test('a closed order is history on both sides', () {
      final open = _order(id: 1, items: [_line('ხინკალი', 2.50, 4)]);
      final paid = _order(id: 2, items: [], status: 'paid');

      expect(
        OrderItemTransfer.move(
          source: open,
          destination: paid,
          moves: const [(index: 0, quantity: 1)],
        ).error,
        OrderTransferError.destinationFinalized,
      );
      expect(
        OrderItemTransfer.move(
          source: _order(id: 3, items: [_line('ხ', 2.5, 4)], status: 'closed'),
          destination: open,
          moves: const [(index: 0, quantity: 1)],
        ).error,
        OrderTransferError.sourceFinalized,
      );
    });

    test('asking for more than is there changes nothing at all', () {
      final source = _order(id: 1, items: [_line('ხინკალი', 2.50, 4)]);
      final destination = _order(id: 2, items: []);

      final result = OrderItemTransfer.move(
        source: source,
        destination: destination,
        moves: const [(index: 0, quantity: 5)],
      );

      expect(result.error, OrderTransferError.quantityOutOfRange);
      // The refusal has to be total: a partly applied move would leave the two
      // orders disagreeing about how many exist.
      expect(source.items.single.quantity, 4);
      expect(destination.items, isEmpty);
    });

    test('two moves that together overdraw one line are refused', () {
      final source = _order(id: 1, items: [_line('ხინკალი', 2.50, 4)]);
      final destination = _order(id: 2, items: []);

      expect(
        OrderItemTransfer.move(
          source: source,
          destination: destination,
          moves: const [(index: 0, quantity: 3), (index: 0, quantity: 2)],
        ).error,
        OrderTransferError.quantityOutOfRange,
      );
      expect(source.items.single.quantity, 4);
    });

    test('a line that is not there is refused', () {
      expect(
        OrderItemTransfer.move(
          source: _order(id: 1, items: [_line('ხინკალი', 2.50, 4)]),
          destination: _order(id: 2, items: []),
          moves: const [(index: 7, quantity: 1)],
        ).error,
        OrderTransferError.quantityOutOfRange,
      );
    });

    test('moving nothing is refused rather than silently succeeding', () {
      expect(
        OrderItemTransfer.move(
          source: _order(id: 1, items: [_line('ხინკალი', 2.50, 4)]),
          destination: _order(id: 2, items: []),
          moves: const [(index: 0, quantity: 0)],
        ).error,
        OrderTransferError.nothingSelected,
      );
    });
  });

  group('take away and tables are the same operation', () {
    test('a take-away order can hand its items to a table', () {
      final takeAway = _order(
        id: 1,
        floor: 'takeaway',
        tables: ['TA-4'],
        items: [_line('ხინკალი', 2.50, 10)],
      );
      final table = _order(id: 2, floor: 'first', tables: ['7'], items: []);

      final result = OrderItemTransfer.move(
        source: takeAway,
        destination: table,
        moves: const [(index: 0, quantity: 10)],
      );

      expect(result.ok, isTrue);
      expect(table.items.single.quantity, 10);
      // The orders keep their own identity — only the items moved.
      expect(table.floor, 'first');
      expect(takeAway.floor, 'takeaway');
    });

    test('and a table can hand its items to a take-away', () {
      final table = _order(
        id: 1,
        floor: 'first',
        tables: ['7'],
        items: [_line('მწვადი', 18.00, 3)],
      );
      final takeAway = _order(
        id: 2,
        floor: 'takeaway',
        tables: ['TA-4'],
        items: [],
      );

      final result = OrderItemTransfer.move(
        source: table,
        destination: takeAway,
        moves: const [(index: 0, quantity: 3)],
      );

      expect(result.ok, isTrue);
      expect(takeAway.items.single.quantity, 3);
      expect(takeAway.totalAmount, 54.00);
    });
  });
}
