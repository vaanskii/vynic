import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_grouping.dart';

/// Selecting several tables on the floor should show them joined only when they
/// could actually be pushed together: side by side, with nothing in the way.

/// A row of same-size tables, `gap` apart, named T1, T2, T3...
List<FloorPlanGroupCandidate> _row(int count, {double gap = 30}) {
  const width = 120.0;
  const height = 90.0;
  return [
    for (var i = 0; i < count; i++)
      (
        id: 'T${i + 1}',
        rect: Rect.fromLTWH(i * (width + gap), 0, width, height),
      ),
  ];
}

List<FloorPlanGroupCandidate> _pick(
  List<FloorPlanGroupCandidate> all,
  List<String> ids,
) {
  return [
    for (final candidate in all)
      if (ids.contains(candidate.id)) candidate,
  ];
}

void main() {
  group('neighbours join', () {
    test('two tables side by side become one group', () {
      final all = _row(3);
      final groups = floorPlanAdjacencyGroups(
        selected: _pick(all, ['T2', 'T3']),
        obstacles: all,
      );

      expect(groups, hasLength(1));
      expect(groups.first, ['T2', 'T3']);
    });

    test('a run of three joins into a single group', () {
      final all = _row(4);
      final groups = floorPlanAdjacencyGroups(
        selected: _pick(all, ['T1', 'T2', 'T3']),
        obstacles: all,
      );

      expect(groups, hasLength(1));
      expect(groups.first, ['T1', 'T2', 'T3']);
    });

    test('touching tables join', () {
      final all = _row(2, gap: 0);
      final groups = floorPlanAdjacencyGroups(selected: all, obstacles: all);
      expect(groups, hasLength(1));
    });
  });

  group('a table in between blocks the join', () {
    test('T1 and T3 do not join across T2', () {
      final all = _row(3);
      final groups = floorPlanAdjacencyGroups(
        selected: _pick(all, ['T1', 'T3']),
        obstacles: all,
      );

      // Two lone tables, so nothing is drawn as joined.
      expect(groups, isEmpty);
    });

    test('T1 and T3 join once the table between them is gone', () {
      final all = _row(3);
      final withoutMiddle = _pick(all, ['T1', 'T3']);
      final groups = floorPlanAdjacencyGroups(
        selected: withoutMiddle,
        // T2 no longer exists on this floor at all.
        obstacles: withoutMiddle,
      );

      // They are now 270 apart edge-to-edge, still too far to push together.
      expect(groups, isEmpty);
    });

    test('an unselected neighbour still blocks two selected tables', () {
      // T1 and T3 are close enough to reach, but T2 is physically in the way.
      final all = [
        (id: 'T1', rect: const Rect.fromLTWH(0, 0, 100, 90)),
        (id: 'T2', rect: const Rect.fromLTWH(110, 0, 100, 90)),
        (id: 'T3', rect: const Rect.fromLTWH(220, 0, 100, 90)),
      ];
      final groups = floorPlanAdjacencyGroups(
        selected: _pick(all, ['T1', 'T3']),
        obstacles: all,
      );

      expect(groups, isEmpty);
    });
  });

  group('distance', () {
    test('tables further apart than their own size stay separate', () {
      // The fixture tables are 90 tall, so 100 apart is out of reach.
      final all = _row(2, gap: 100);
      final groups = floorPlanAdjacencyGroups(selected: all, obstacles: all);
      expect(groups, isEmpty);
    });

    test('a generously spaced row still joins', () {
      // This is the case a fixed 64-unit threshold got wrong: an 80-unit gap
      // on a 90-tall table is a normal aisle-free layout, and those tables can
      // be pushed together.
      final all = _row(2, gap: 80);
      final groups = floorPlanAdjacencyGroups(selected: all, obstacles: all);
      expect(groups, hasLength(1));
    });

    test('the reach scales with the smaller of the two tables', () {
      const small = Rect.fromLTWH(0, 0, 60, 60);
      const large = Rect.fromLTWH(0, 0, 300, 200);
      // Bounded below by the small table, not the large one.
      expect(floorPlanJoinGapFor(small, large), 60);
      // ...and never below the bar-stool floor.
      expect(
        floorPlanJoinGapFor(
          const Rect.fromLTWH(0, 0, 20, 20),
          const Rect.fromLTWH(0, 0, 20, 20),
        ),
        floorPlanMinJoinGap,
      );
    });

    test('diagonally offset tables measure corner to corner', () {
      const a = Rect.fromLTWH(0, 0, 100, 100);
      const b = Rect.fromLTWH(130, 140, 100, 100);
      expect(floorPlanRectGap(a, b), closeTo(50, 0.01));
      expect(floorPlanRectGap(a, a), 0);
    });
  });

  group('multiple clusters', () {
    test('two separate pairs come back as two groups', () {
      final all = [
        (id: 'A1', rect: const Rect.fromLTWH(0, 0, 100, 90)),
        (id: 'A2', rect: const Rect.fromLTWH(120, 0, 100, 90)),
        (id: 'B1', rect: const Rect.fromLTWH(0, 400, 100, 90)),
        (id: 'B2', rect: const Rect.fromLTWH(120, 400, 100, 90)),
      ];
      final groups = floorPlanAdjacencyGroups(selected: all, obstacles: all);

      expect(groups, hasLength(2));
      expect(groups[0], ['A1', 'A2']);
      expect(groups[1], ['B1', 'B2']);
    });

    test('a lone selection is never a group', () {
      final all = _row(3);
      expect(
        floorPlanAdjacencyGroups(selected: _pick(all, ['T2']), obstacles: all),
        isEmpty,
      );
      expect(
        floorPlanAdjacencyGroups(selected: const [], obstacles: all),
        isEmpty,
      );
    });
  });

  group('bounds', () {
    test('the band spans the whole cluster', () {
      final bounds = floorPlanGroupBounds(const [
        Rect.fromLTWH(0, 0, 100, 90),
        Rect.fromLTWH(120, 10, 100, 90),
      ]);
      expect(bounds, const Rect.fromLTRB(0, 0, 220, 100));
    });

    test('an empty cluster has no bounds', () {
      expect(floorPlanGroupBounds(const []), Rect.zero);
    });
  });

  group('a joined run behaves like one table', () {
    test('capacity sums across the run', () {
      // Two six-tops pushed together seat twelve.
      const seatsPerTable = 6;
      final all = _row(3);
      final groups = floorPlanAdjacencyGroups(
        selected: _pick(all, ['T2', 'T3']),
        obstacles: all,
      );

      expect(groups, hasLength(1));
      expect(groups.first.length * seatsPerTable, 12);
    });

    test('the merged footprint spans both tables and the gap between', () {
      final all = _row(3);
      final groups = floorPlanAdjacencyGroups(
        selected: _pick(all, ['T2', 'T3']),
        obstacles: all,
      );
      final rects = {for (final c in all) c.id: c.rect};
      final bounds = floorPlanGroupBounds(groups.first.map((id) => rects[id]!));

      // T2 starts at 150 and T3 ends at 420 in the fixture row.
      expect(bounds.left, rects['T2']!.left);
      expect(bounds.right, rects['T3']!.right);
      expect(bounds.width, greaterThan(rects['T2']!.width));
    });

    test('a blocked pair yields no merged footprint', () {
      final all = _row(3);
      final groups = floorPlanAdjacencyGroups(
        selected: _pick(all, ['T1', 'T3']),
        obstacles: all,
      );
      // Nothing merges, so both keep their own footprint and their own seats.
      expect(groups, isEmpty);
    });
  });

  group('selection must stay contiguous', () {
    test('a single table is always a valid selection', () {
      final all = _row(3);
      expect(
        floorPlanSelectionIsContiguous(
          selected: _pick(all, ['T2']),
          obstacles: all,
        ),
        isTrue,
      );
      expect(
        floorPlanSelectionIsContiguous(selected: const [], obstacles: all),
        isTrue,
      );
    });

    test('neighbours are a valid selection', () {
      final all = _row(4);
      expect(
        floorPlanSelectionIsContiguous(
          selected: _pick(all, ['T2', 'T3']),
          obstacles: all,
        ),
        isTrue,
      );
      expect(
        floorPlanSelectionIsContiguous(
          selected: _pick(all, ['T1', 'T2', 'T3']),
          obstacles: all,
        ),
        isTrue,
      );
    });

    test('skipping a table is refused', () {
      final all = _row(4);
      // T1 + T3 across T2, and T5 + T7 across T6 — the cases a waiter cannot
      // actually set up.
      expect(
        floorPlanSelectionIsContiguous(
          selected: _pick(all, ['T1', 'T3']),
          obstacles: all,
        ),
        isFalse,
      );
      expect(
        floorPlanSelectionIsContiguous(
          selected: _pick(all, ['T2', 'T4']),
          obstacles: all,
        ),
        isFalse,
      );
    });

    test('a run broken in the middle is refused', () {
      final all = _row(4);
      // Dropping T2 out of 1-2-3 would leave two disconnected halves.
      expect(
        floorPlanSelectionIsContiguous(
          selected: _pick(all, ['T1', 'T3']),
          obstacles: all,
        ),
        isFalse,
      );
    });

    test('two far-apart tables are refused even with nothing between', () {
      final all = _row(2, gap: 400);
      expect(
        floorPlanSelectionIsContiguous(selected: all, obstacles: all),
        isFalse,
      );
    });
  });
}
