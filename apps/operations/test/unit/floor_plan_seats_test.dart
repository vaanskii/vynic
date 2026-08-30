import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_seats.dart';
import 'package:vynic/core/models/table_layout.dart';

/// Seat geometry is shared by the admin editor and the operational POS plan, so
/// a six-seat table looks the same in both. These pin the arrangement.

List<Offset> _seats(
  RestaurantTableShape shape,
  int capacity, {
  Rect rect = const Rect.fromLTWH(0, 0, 190, 90),
}) {
  return floorPlanSeatPositions(rect: rect, shape: shape, capacity: capacity);
}

void main() {
  group('rectangular tables', () {
    test('a 4-top seats two per long side, none on the ends', () {
      const rect = Rect.fromLTWH(0, 0, 140, 90);
      final seats = _seats(RestaurantTableShape.rectangle, 4, rect: rect);

      expect(seats, hasLength(4));
      expect(seats.where((s) => s.dy < rect.top), hasLength(2));
      expect(seats.where((s) => s.dy > rect.bottom), hasLength(2));
    });

    test('a 6-top on a long table puts one at each end', () {
      const rect = Rect.fromLTWH(0, 0, 190, 90);
      final seats = _seats(RestaurantTableShape.rectangle, 6, rect: rect);

      expect(seats, hasLength(6));
      expect(seats.where((s) => s.dx < rect.left), hasLength(1));
      expect(seats.where((s) => s.dx > rect.right), hasLength(1));
      expect(seats.where((s) => s.dy < rect.top), hasLength(2));
      expect(seats.where((s) => s.dy > rect.bottom), hasLength(2));
    });

    test('a square 4-top keeps the ends clear', () {
      const rect = Rect.fromLTWH(0, 0, 110, 110);
      final seats = _seats(RestaurantTableShape.square, 4, rect: rect);

      expect(seats, hasLength(4));
      expect(seats.where((s) => s.dx < rect.left), isEmpty);
      expect(seats.where((s) => s.dx > rect.right), isEmpty);
    });

    test('an odd capacity still places every seat', () {
      for (final capacity in [1, 3, 5, 7, 9]) {
        expect(
          _seats(RestaurantTableShape.rectangle, capacity),
          hasLength(capacity),
          reason: 'capacity $capacity',
        );
      }
    });

    test('a tall table seats along its vertical sides', () {
      const rect = Rect.fromLTWH(0, 0, 90, 190);
      final seats = _seats(RestaurantTableShape.rectangle, 4, rect: rect);

      expect(seats.where((s) => s.dx < rect.left), hasLength(2));
      expect(seats.where((s) => s.dx > rect.right), hasLength(2));
    });
  });

  group('round tables', () {
    test('seats are spread evenly around the rim', () {
      const rect = Rect.fromLTWH(0, 0, 110, 110);
      final seats = _seats(RestaurantTableShape.circle, 6, rect: rect);

      expect(seats, hasLength(6));
      final radius = rect.width / 2 + 9;
      for (final seat in seats) {
        expect((seat - rect.center).distance, closeTo(radius, 0.01));
      }
      // First seat sits at the top.
      expect(seats.first.dx, closeTo(rect.center.dx, 0.01));
      expect(seats.first.dy, lessThan(rect.center.dy));
    });
  });

  group('booths and bar stools', () {
    test('a booth only marks the loose chairs opposite its bench', () {
      final seats = _seats(RestaurantTableShape.booth, 6);
      // The bench is drawn as part of the table, so only half are chairs.
      expect(seats, hasLength(3));
    });

    test('a bar stool draws no chair of its own', () {
      expect(_seats(RestaurantTableShape.barSeat, 1), isEmpty);
    });
  });

  group('unset capacity', () {
    test('a table without a seat count shows no chairs', () {
      for (final shape in RestaurantTableShape.values) {
        expect(_seats(shape, 0), isEmpty, reason: shape.name);
        expect(_seats(shape, -3), isEmpty, reason: shape.name);
      }
    });
  });

  group('painter', () {
    test('repaints when the scale, colour or tables change', () {
      const tables = <FloorPlanSeatedTable>[
        (
          rect: Rect.fromLTWH(0, 0, 140, 90),
          rotation: 0,
          shape: RestaurantTableShape.rectangle,
          capacity: 4,
        ),
      ];
      const base = FloorPlanSeatsPainter(
        tables: tables,
        scale: 1,
        color: Color(0xFFE2E0DB),
      );

      expect(
        base.shouldRepaint(
          const FloorPlanSeatsPainter(
            tables: tables,
            scale: 2,
            color: Color(0xFFE2E0DB),
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const FloorPlanSeatsPainter(
            tables: tables,
            scale: 1,
            color: Color(0xFF000000),
          ),
        ),
        isTrue,
      );
      expect(base.shouldRepaint(base), isFalse);
    });
  });
}
