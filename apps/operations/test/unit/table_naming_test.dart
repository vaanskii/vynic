import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/apps/windows_pos/widgets/order/helpers/order_detail_common_helpers.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/utils/table_naming.dart';

/// What a table is called, and who decides.
///
/// The POS used to answer that with `floor == 'second' ? 'კუპე' : 'მაგიდა'`, in
/// four separate files — while the floor editor called those same tables „VIP
/// Zone 1..4". A waiter renaming a table saw the new name on the plan and the
/// old guess everywhere else, and the kitchen check printed a third thing
/// again („5, კუპე 5").

RestaurantTableLayout _layout() => const RestaurantTableLayout(
  id: 'test',
  name: 'Test plan',
  zones: [
    RestaurantZone(
      id: 'main',
      name: 'პირველი სართული',
      legacyFloor: 'first',
      displayOrder: 1,
      renderMode: TableLayoutRenderMode.floorPlan,
    ),
    RestaurantZone(
      id: 'vip',
      name: 'ტერასა',
      legacyFloor: 'second',
      displayOrder: 2,
      renderMode: TableLayoutRenderMode.floorPlan,
    ),
  ],
  tables: [
    RestaurantTableDefinition(
      id: 'first-1',
      zoneId: 'main',
      legacyFloor: 'first',
      legacyTableNumber: '1',
      label: 'ფანჯარასთან',
      capacity: 4,
      sortOrder: 1,
    ),
    RestaurantTableDefinition(
      id: 'first-2',
      zoneId: 'main',
      legacyFloor: 'first',
      legacyTableNumber: '2',
      label: 'მაგიდა 2',
      capacity: 2,
      sortOrder: 2,
    ),
    RestaurantTableDefinition(
      id: 'second-1',
      zoneId: 'vip',
      legacyFloor: 'second',
      legacyTableNumber: '1',
      label: 'VIP Zone 1',
      capacity: 8,
      sortOrder: 1,
    ),
  ],
);

Order _order({required List<String> tables, String floor = 'first'}) => Order(
  orderId: 1,
  tableNumbers: tables,
  floor: floor,
  items: const [],
  totalAmount: 0,
  createdAt: DateTime(2026, 8, 23),
  createdBy: 'გიორგი',
);

void main() {
  group('a table is called what the layout calls it', () {
    test('a renamed table keeps its name', () {
      expect(
        TableNaming.table(tableNumber: '1', floor: 'first', from: _layout()),
        'ფანჯარასთან',
      );
    });

    test('the second floor is not automatically „კუპე" any more', () {
      // The whole bug: the second floor was assumed to be booths, everywhere
      // except the one screen where the names are actually edited.
      final name = TableNaming.table(
        tableNumber: '1',
        floor: 'second',
        from: _layout(),
      );
      expect(name, 'VIP Zone 1');
      expect(name, isNot(contains('კუპე')));
    });

    test('a table the plan no longer has still reads as its number', () {
      // Deleted from the plan while an order was open on it. The number is
      // still the truth about which table it is.
      expect(
        TableNaming.table(tableNumber: '99', floor: 'first', from: _layout()),
        'მაგიდა 99',
      );
    });
  });

  group('several tables on one bill', () {
    test('are joined with a plus, not a comma', () {
      // A comma reads as a list of separate bills. These are one.
      expect(
        TableNaming.orderTables(_order(tables: ['1', '2']), from: _layout()),
        'ფანჯარასთან + მაგიდა 2',
      );
    });

    test('a single table has no joiner at all', () {
      expect(
        TableNaming.orderTables(_order(tables: ['2']), from: _layout()),
        'მაგიდა 2',
      );
    });

    test('an order with no tables says so rather than reading empty', () {
      expect(TableNaming.orderTables(_order(tables: []), from: _layout()), '—');
    });
  });

  group('the floor', () {
    test('is named by the layout, not by the legacy key', () {
      expect(TableNaming.zone('second', from: _layout()), 'ტერასა');
      expect(TableNaming.zone('first', from: _layout()), 'პირველი სართული');
    });

    test('take-away has no floor to name', () {
      expect(TableNaming.zone('takeaway', from: _layout()), isNull);
    });

    test('an unknown floor is null rather than a guess', () {
      expect(TableNaming.zone('third', from: _layout()), isNull);
    });
  });

  group('the kitchen check', () {
    test('reads the same name as the floor screen', () {
      // It used to print the number twice — „5, კუპე 5" — behind a word the
      // floor editor does not use, so a runner was looking for a table that
      // did not exist under that name.
      final label = OrderDetailCommonHelpers.kitchenTableLabel(
        _order(tables: ['1', '2']),
      );
      expect(label, isNot(contains('კუპე')));
    });
  });
}
