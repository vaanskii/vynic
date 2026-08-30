import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_names.dart';
import 'package:vynic/core/models/table_layout.dart';

/// A table is shown under the name the admin typed in the floor editor, on
/// every floor — and that name never doubles as the table's identity.

RestaurantTableLayout _layout({
  String firstLabel = 'ფანჯარასთან',
  String secondLabel = 'VIP კუთხე',
}) {
  return RestaurantTableLayout(
    id: 'test',
    zones: const [
      RestaurantZone(
        id: 'z1',
        name: 'სართული 1',
        legacyFloor: 'first',
        displayOrder: 1,
        renderMode: TableLayoutRenderMode.floorPlan,
      ),
      RestaurantZone(
        id: 'z2',
        name: 'სართული 2',
        legacyFloor: 'second',
        displayOrder: 2,
        renderMode: TableLayoutRenderMode.floorPlan,
      ),
    ],
    tables: [
      RestaurantTableDefinition(
        id: 'first-table-3',
        zoneId: 'z1',
        legacyFloor: 'first',
        legacyTableNumber: '3',
        label: firstLabel,
        capacity: 4,
        sortOrder: 1,
      ),
      RestaurantTableDefinition(
        id: 'second-table-1',
        zoneId: 'z2',
        legacyFloor: 'second',
        legacyTableNumber: '1',
        label: secondLabel,
        capacity: 6,
        sortOrder: 1,
      ),
    ],
  );
}

void main() {
  test('a renamed table is found by its own name', () {
    expect(
      floorPlanTableName(_layout(), floor: 'first', tableNumber: '3'),
      'ფანჯარასთან',
    );
  });

  test('the second floor keeps its name too', () {
    // This is the regression: upstairs tables used to be relabelled
    // 'Second Floor Table N', discarding whatever the admin had set.
    expect(
      floorPlanTableName(_layout(), floor: 'second', tableNumber: '1'),
      'VIP კუთხე',
    );
  });

  test('the floor is part of the lookup, not just the number', () {
    // Table 1 exists upstairs only; asking for it downstairs must not match.
    expect(
      floorPlanTableName(_layout(), floor: 'first', tableNumber: '1'),
      isNull,
    );
  });

  test('a table with no layout entry has no name', () {
    // A live row left behind after its table was deleted from the plan.
    expect(
      floorPlanTableName(_layout(), floor: 'first', tableNumber: '99'),
      isNull,
    );
  });

  test('a blank name counts as no name rather than an empty tile', () {
    expect(
      floorPlanTableName(
        _layout(firstLabel: '   '),
        floor: 'first',
        tableNumber: '3',
      ),
      isNull,
    );
  });

  test('the number stands in when there is no name', () {
    expect(
      floorPlanTableNameOrNumber(_layout(), floor: 'first', tableNumber: '99'),
      '99',
    );
    expect(
      floorPlanTableNameOrNumber(_layout(), floor: 'first', tableNumber: '3'),
      'ფანჯარასთან',
    );
  });

  test('renaming a table does not move its identity', () {
    // The point of keeping name and (floor, number) apart: the same table
    // answers to a new name while orders and reservations still find it.
    final before = _layout();
    final after = _layout(firstLabel: 'ტერასა 1');

    expect(
      before.tableForLegacy(floor: 'first', tableNumber: '3')?.id,
      'first-table-3',
    );
    expect(
      after.tableForLegacy(floor: 'first', tableNumber: '3')?.id,
      'first-table-3',
    );
    expect(
      floorPlanTableName(after, floor: 'first', tableNumber: '3'),
      'ტერასა 1',
    );
  });
}
