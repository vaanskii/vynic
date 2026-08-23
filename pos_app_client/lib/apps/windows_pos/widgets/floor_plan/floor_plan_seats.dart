import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:vynic/core/models/table_layout.dart';

/// Seat (chair) marks around a table.
///
/// Shared by the admin floor editor and the operational POS plan so a table
/// seated for six looks the same in both. Positions are returned in *layout*
/// coordinates — the caller scales them.

/// One seat mark's footprint, in layout units.
const Size floorPlanSeatSize = Size(15, 11);

/// Distance from the table edge to the centre of a seat mark.
const double _seatGap = 9;

/// Where the chairs go for a table of [capacity] seats.
///
/// Long sides get the bulk of the seats, and the two short ends get one each
/// once the table is elongated enough for someone to actually sit there — the
/// way a real six- or eight-top is laid out. Returns an empty list when the
/// capacity is unset, so tables without a seat count simply show none.
List<Offset> floorPlanSeatPositions({
  required Rect rect,
  required RestaurantTableShape shape,
  required int capacity,
}) {
  if (capacity <= 0) {
    return const [];
  }

  switch (shape) {
    case RestaurantTableShape.barSeat:
      // A bar stool *is* the seat; drawing a chair beside it is noise.
      return const [];
    case RestaurantTableShape.circle:
      return _circleSeats(
        rect.center,
        math.min(rect.width, rect.height) / 2,
        capacity,
      );
    case RestaurantTableShape.booth:
      return _boothSeats(rect, capacity);
    case RestaurantTableShape.rectangle:
    case RestaurantTableShape.rounded:
    case RestaurantTableShape.square:
    case RestaurantTableShape.long:
      return _rectSeats(rect, capacity);
  }
}

List<Offset> _rectSeats(Rect rect, int capacity) {
  final horizontal = rect.width >= rect.height;
  final longSide = horizontal ? rect.width : rect.height;
  final shortSide = horizontal ? rect.height : rect.width;

  var ends = (capacity >= 6 && longSide / math.max(shortSide, 1) >= 1.4)
      ? 2
      : 0;
  if (capacity - ends < 2) {
    ends = 0;
  }
  final perSide = (capacity - ends) ~/ 2;
  final leftover = (capacity - ends) % 2;

  final seats = <Offset>[];

  void alongSide(int count, bool primary) {
    for (var i = 0; i < count; i++) {
      final t = (i + 1) / (count + 1);
      if (horizontal) {
        seats.add(
          Offset(
            rect.left + rect.width * t,
            primary ? rect.top - _seatGap : rect.bottom + _seatGap,
          ),
        );
      } else {
        seats.add(
          Offset(
            primary ? rect.left - _seatGap : rect.right + _seatGap,
            rect.top + rect.height * t,
          ),
        );
      }
    }
  }

  alongSide(perSide + leftover, true);
  alongSide(perSide, false);

  if (ends == 2) {
    if (horizontal) {
      seats
        ..add(Offset(rect.left - _seatGap, rect.center.dy))
        ..add(Offset(rect.right + _seatGap, rect.center.dy));
    } else {
      seats
        ..add(Offset(rect.center.dx, rect.top - _seatGap))
        ..add(Offset(rect.center.dx, rect.bottom + _seatGap));
    }
  }

  return seats;
}

List<Offset> _circleSeats(Offset center, double radius, int capacity) {
  final distance = radius + _seatGap;
  return [
    for (var i = 0; i < capacity; i++)
      () {
        final angle = -math.pi / 2 + (2 * math.pi * i) / capacity;
        return center + Offset(math.cos(angle), math.sin(angle)) * distance;
      }(),
  ];
}

/// A booth's bench is drawn as part of the table, so only the loose chairs on
/// the open side get marks.
List<Offset> _boothSeats(Rect rect, int capacity) {
  final horizontal = rect.width >= rect.height;
  final loose = capacity ~/ 2;
  return [
    for (var i = 0; i < loose; i++)
      () {
        final t = (i + 1) / (loose + 1);
        return horizontal
            ? Offset(rect.left + rect.width * t, rect.bottom + 7)
            : Offset(rect.right + 7, rect.top + rect.height * t);
      }(),
  ];
}

/// Draws a single seat mark centred on [center], in the canvas's current
/// transform.
void paintFloorPlanSeat(Canvas canvas, Offset center, Paint paint) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: floorPlanSeatSize.width,
        height: floorPlanSeatSize.height,
      ),
      const Radius.circular(4),
    ),
    paint,
  );
}

/// A table's geometry as far as seat drawing is concerned.
typedef FloorPlanSeatedTable = ({
  Rect rect,
  double rotation,
  RestaurantTableShape shape,
  int capacity,
});

/// Paints the chairs for every table on a floor.
///
/// The POS draws its tables as positioned widgets, which clip to the table's
/// own box — seats sit *outside* that box, so they need their own layer
/// underneath. One painter for the whole floor keeps that to a single repaint.
class FloorPlanSeatsPainter extends CustomPainter {
  const FloorPlanSeatsPainter({
    required this.tables,
    required this.scale,
    required this.color,
  });

  final List<FloorPlanSeatedTable> tables;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas
      ..save()
      ..scale(scale);

    for (final table in tables) {
      final seats = floorPlanSeatPositions(
        rect: table.rect,
        shape: table.shape,
        capacity: table.capacity,
      );
      if (seats.isEmpty) continue;

      canvas.save();
      if (table.rotation % 360 != 0) {
        final center = table.rect.center;
        canvas
          ..translate(center.dx, center.dy)
          ..rotate(table.rotation * math.pi / 180)
          ..translate(-center.dx, -center.dy);
      }
      for (final seat in seats) {
        paintFloorPlanSeat(canvas, seat, paint);
      }
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FloorPlanSeatsPainter oldDelegate) {
    return oldDelegate.scale != scale ||
        oldDelegate.color != color ||
        oldDelegate.tables != tables;
  }
}
