import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_seats.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'floor_editor_controller.dart';
import 'floor_editor_model.dart';

/// Palette for the canvas. Kept local to the painter so the floor plan reads
/// as one drawing rather than a pile of arbitrary object colours.
abstract final class _Ink {
  static const canvas = Color(0xFFFFFFFF);
  static const canvasEdge = VynicColors.borderStrong;
  static const gridFine = Color(0xFFF0EEEA);
  static const gridMajor = Color(0xFFE4E1DB);

  static const tableFill = Color(0xFFFCFBF9);
  static const tableLine = Color(0xFFBFB8AC);
  static const tableText = VynicColors.textPrimary;
  static const seat = Color(0xFFD9D3C7);
  static const bench = Color(0xFFE6E0D4);

  static const structure = Color(0xFF3A342C);
  static const structureSoft = Color(0xFF8A8175);
  static const bar = Color(0xFF4A3F52);
  static const barFill = Color(0xFFEFEAF1);

  static const zoneLine = Color(0xFFB9A9BD);
  static const zoneFill = Color(0x14764B7C);

  static const selection = VynicColors.accent;

  /// Selected objects are re-tinted rather than only outlined — on a busy
  /// floor an outline alone is easy to lose.
  static const selectedFill = Color(0xFFF1E8F3);
  static const selectedLine = VynicColors.accent;
  static const selectedText = Color(0xFF4A2F4E);
  static const selectedSeat = Color(0xFFD8C4DC);

  static const guide = Color(0xFFCE6A3E);
}

/// Cached text layout — a 200-object floor would otherwise re-layout every
/// label on every drag frame.
final Map<String, TextPainter> _textCache = <String, TextPainter>{};

TextPainter _text(
  String value, {
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w700,
}) {
  final key = '$value|$size|${color.toARGB32()}|${weight.value}';
  final cached = _textCache[key];
  if (cached != null) {
    return cached;
  }
  if (_textCache.length > 600) {
    _textCache.clear();
  }
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        height: 1.1,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: 400);
  _textCache[key] = painter;
  return painter;
}

void _paintCenteredText(
  Canvas canvas,
  String value,
  Offset center, {
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w700,
}) {
  final painter = _text(value, size: size, color: color, weight: weight);
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
}

/// Draws the entire floor in one pass.
///
/// Everything on the canvas — grid, zones, objects, selection chrome — is a
/// single [CustomPaint] rather than one widget per object. A 50+ table floor
/// then costs one repaint per drag frame instead of dozens of widget
/// rebuilds, which is what keeps dragging smooth.
class FloorEditorPainter extends CustomPainter {
  FloorEditorPainter({
    required this.floor,
    required this.scale,
    required this.offset,
    required this.selection,
    required this.gridVisible,
    required this.gridSize,
    required this.guides,
    required this.marquee,
    required this.segmentPreview,
    required this.segmentThickness,
    required this.showHandles,
    required this.showSeats,
    super.repaint,
  });

  final EditorFloor floor;
  final double scale;
  final Offset offset;
  final Set<String> selection;
  final bool gridVisible;
  final double gridSize;
  final List<AlignmentGuide> guides;
  final Rect? marquee;
  final (Offset, Offset)? segmentPreview;
  final double segmentThickness;
  final bool showHandles;
  final bool showSeats;

  /// Screen-space radius of a resize grip. Also used for hit testing in the
  /// canvas, so both agree on where the grips are.
  static const double handleRadius = 5.5;
  static const double rotationHandleGap = 26;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);

    _paintCanvasSurface(canvas);
    if (gridVisible) {
      _paintGrid(canvas);
    }

    for (final object in floor.objects) {
      _paintObject(canvas, object);
    }

    canvas.restore();

    // Chrome is drawn unscaled so outlines and grips keep a constant weight
    // at any zoom level.
    for (final object in floor.objects) {
      if (selection.contains(object.id)) {
        _paintSelection(canvas, object);
      }
    }
    _paintGuides(canvas, size);
    _paintMarquee(canvas);
    _paintSegmentPreview(canvas);
  }

  // -------------------------------------------------------------- surface

  void _paintCanvasSurface(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, floor.canvasWidth, floor.canvasHeight);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = _Ink.canvas,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = _Ink.canvasEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale,
      );
  }

  void _paintGrid(Canvas canvas) {
    // Below ~0.35× the grid turns into a grey wash; hide it instead.
    if (gridSize * scale < 6) return;

    final fine = Paint()
      ..color = _Ink.gridFine
      ..strokeWidth = 1 / scale;
    final major = Paint()
      ..color = _Ink.gridMajor
      ..strokeWidth = 1 / scale;

    var index = 0;
    for (var x = 0.0; x <= floor.canvasWidth; x += gridSize, index++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, floor.canvasHeight),
        index % 5 == 0 ? major : fine,
      );
    }
    index = 0;
    for (var y = 0.0; y <= floor.canvasHeight; y += gridSize, index++) {
      canvas.drawLine(
        Offset(0, y),
        Offset(floor.canvasWidth, y),
        index % 5 == 0 ? major : fine,
      );
    }
  }

  // -------------------------------------------------------------- objects

  void _paintObject(Canvas canvas, EditorObject object) {
    final selected = selection.contains(object.id);
    canvas.save();
    final center = object.center;
    canvas
      ..translate(center.dx, center.dy)
      ..rotate(object.rotationRadians)
      ..translate(-center.dx, -center.dy);

    switch (object.type) {
      case RestaurantLayoutObjectType.table:
        _paintTable(canvas, object, selected);
      case RestaurantLayoutObjectType.wall:
        _paintSegment(
          canvas,
          object,
          color: selected ? _Ink.selectedLine : _Ink.structure,
        );
      case RestaurantLayoutObjectType.divider:
        _paintSegment(
          canvas,
          object,
          color: selected ? _Ink.selectedLine : _Ink.structureSoft,
          dashed: true,
        );
      case RestaurantLayoutObjectType.entrance:
        _paintDoor(canvas, object, selected);
      case RestaurantLayoutObjectType.bar:
      case RestaurantLayoutObjectType.counter:
        _paintBar(canvas, object, selected);
      case RestaurantLayoutObjectType.zone:
        _paintZone(canvas, object, selected);
      case RestaurantLayoutObjectType.label:
        _paintLabel(canvas, object, selected);
      case RestaurantLayoutObjectType.stairs:
      case RestaurantLayoutObjectType.stage:
      case RestaurantLayoutObjectType.restroom:
        _paintUtility(canvas, object, selected);
    }

    canvas.restore();
  }

  // ---------------------------------------------------------------- tables

  void _paintTable(Canvas canvas, EditorObject object, bool selected) {
    switch (object.tableShape) {
      case RestaurantTableShape.circle:
        _paintRoundTable(canvas, object, selected);
      case RestaurantTableShape.barSeat:
        _paintBarSeat(canvas, object, selected);
      case RestaurantTableShape.booth:
        _paintBooth(canvas, object, selected);
      case RestaurantTableShape.rectangle:
      case RestaurantTableShape.rounded:
      case RestaurantTableShape.square:
      case RestaurantTableShape.long:
        _paintRectTable(canvas, object, selected);
    }
  }

  Paint _tableFill(bool selected) =>
      Paint()..color = selected ? _Ink.selectedFill : _Ink.tableFill;

  Paint _tableStroke(bool selected) => Paint()
    ..color = selected ? _Ink.selectedLine : _Ink.tableLine
    ..style = PaintingStyle.stroke
    ..strokeWidth = selected ? 2.2 : 1.6;

  Paint _seatPaint(bool selected) =>
      Paint()..color = selected ? _Ink.selectedSeat : _Ink.seat;

  void _paintRectTable(Canvas canvas, EditorObject object, bool selected) {
    final rect = object.rect;
    final radius = object.tableShape == RestaurantTableShape.rounded
        ? 18.0
        : 6.0;

    if (showSeats && object.capacity > 0) {
      for (final seat in floorPlanSeatPositions(
        rect: rect,
        shape: object.tableShape,
        capacity: object.capacity,
      )) {
        _paintSeat(canvas, seat, selected);
      }
    }

    final body = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas
      ..drawRRect(body, _tableFill(selected))
      ..drawRRect(body, _tableStroke(selected));

    // Long communal tables get a centre seam so they read as one big top.
    if (object.tableShape == RestaurantTableShape.long) {
      final seam = Paint()
        ..color = (selected ? _Ink.selectedLine : _Ink.tableLine).withValues(
          alpha: 0.45,
        )
        ..strokeWidth = 1;
      if (rect.width >= rect.height) {
        canvas.drawLine(
          Offset(rect.left + 10, rect.center.dy),
          Offset(rect.right - 10, rect.center.dy),
          seam,
        );
      } else {
        canvas.drawLine(
          Offset(rect.center.dx, rect.top + 10),
          Offset(rect.center.dx, rect.bottom - 10),
          seam,
        );
      }
    }

    _paintTableCaption(canvas, object, rect, selected);
  }

  void _paintRoundTable(Canvas canvas, EditorObject object, bool selected) {
    final rect = object.rect;
    final radius = math.min(rect.width, rect.height) / 2;

    if (showSeats && object.capacity > 0) {
      for (final seat in floorPlanSeatPositions(
        rect: rect,
        shape: object.tableShape,
        capacity: object.capacity,
      )) {
        _paintSeat(canvas, seat, selected);
      }
    }

    canvas
      ..drawCircle(rect.center, radius, _tableFill(selected))
      ..drawCircle(rect.center, radius, _tableStroke(selected))
      ..drawCircle(
        rect.center,
        math.max(4, radius - 9),
        Paint()
          ..color = _Ink.tableLine.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

    _paintTableCaption(canvas, object, rect, selected);
  }

  void _paintBarSeat(Canvas canvas, EditorObject object, bool selected) {
    final rect = object.rect;
    final radius = math.min(rect.width, rect.height) / 2;
    canvas
      ..drawCircle(rect.center, radius, Paint()..color = _Ink.bench)
      ..drawCircle(rect.center, radius, _tableStroke(selected))
      ..drawCircle(
        rect.center,
        math.max(3, radius * 0.45),
        Paint()..color = _Ink.tableFill,
      );
    _paintTableCaption(canvas, object, rect, selected);
  }

  /// A booth is a bench along one long side with the table in front of it.
  /// Which side the bench is on is the whole point — that is how an admin
  /// sees which way the booth faces once it is rotated.
  void _paintBooth(Canvas canvas, EditorObject object, bool selected) {
    final rect = object.rect;
    final horizontal = rect.width >= rect.height;
    final benchDepth = math.max(
      10.0,
      (horizontal ? rect.height : rect.width) * 0.3,
    );

    final benchRect = horizontal
        ? Rect.fromLTWH(rect.left, rect.top, rect.width, benchDepth)
        : Rect.fromLTWH(rect.left, rect.top, benchDepth, rect.height);
    final tableRect = horizontal
        ? Rect.fromLTRB(
            rect.left + 12,
            benchRect.bottom + 6,
            rect.right - 12,
            rect.bottom - 4,
          )
        : Rect.fromLTRB(
            benchRect.right + 6,
            rect.top + 12,
            rect.right - 4,
            rect.bottom - 12,
          );

    // Bench (banquette) — solid, with a back-rest line.
    final bench = RRect.fromRectAndCorners(
      benchRect,
      topLeft: const Radius.circular(10),
      topRight: const Radius.circular(10),
      bottomLeft: Radius.circular(horizontal ? 3 : 10),
      bottomRight: Radius.circular(horizontal ? 3 : 10),
    );
    canvas
      ..drawRRect(bench, Paint()..color = _Ink.bench)
      ..drawRRect(bench, _tableStroke(selected));

    final backRest = Paint()
      ..color = _Ink.tableLine.withValues(alpha: 0.6)
      ..strokeWidth = 1.4;
    if (horizontal) {
      canvas.drawLine(
        Offset(benchRect.left + 8, benchRect.top + benchDepth * 0.42),
        Offset(benchRect.right - 8, benchRect.top + benchDepth * 0.42),
        backRest,
      );
    } else {
      canvas.drawLine(
        Offset(benchRect.left + benchDepth * 0.42, benchRect.top + 8),
        Offset(benchRect.left + benchDepth * 0.42, benchRect.bottom - 8),
        backRest,
      );
    }

    if (tableRect.width > 4 && tableRect.height > 4) {
      final body = RRect.fromRectAndRadius(tableRect, const Radius.circular(6));
      canvas
        ..drawRRect(body, _tableFill(selected))
        ..drawRRect(body, _tableStroke(selected));
    }

    // Loose chairs opposite the bench, so the seat count still reads.
    if (showSeats) {
      for (final seat in floorPlanSeatPositions(
        rect: rect,
        shape: object.tableShape,
        capacity: object.capacity,
      )) {
        _paintSeat(canvas, seat, selected);
      }
    }

    _paintTableCaption(
      canvas,
      object,
      tableRect.width > 30 ? tableRect : rect,
      selected,
    );
  }

  void _paintSeat(Canvas canvas, Offset center, bool selected) {
    paintFloorPlanSeat(canvas, center, _seatPaint(selected));
  }

  void _paintTableCaption(
    Canvas canvas,
    EditorObject object,
    Rect rect,
    bool selected,
  ) {
    final textColor = selected ? _Ink.selectedText : _Ink.tableText;
    // Below this the glyphs are unreadable anyway and just add noise.
    if (rect.shortestSide * scale < 22) return;

    final hasSeats = object.capacity > 0;
    final labelSize = math.min(18.0, math.max(11.0, rect.shortestSide * 0.24));
    final labelPainter = _text(
      object.label,
      size: labelSize,
      color: textColor,
      weight: FontWeight.w800,
    );

    if (!hasSeats || rect.height * scale < 44) {
      _paintCenteredText(
        canvas,
        object.label,
        rect.center,
        size: labelSize,
        color: textColor,
        weight: FontWeight.w800,
      );
      return;
    }

    final seatsPainter = _text(
      '${object.capacity}',
      size: math.max(9.0, labelSize * 0.66),
      color: VynicColors.textMuted,
      weight: FontWeight.w700,
    );
    final totalHeight = labelPainter.height + seatsPainter.height + 2;
    final top = rect.center.dy - totalHeight / 2;
    labelPainter.paint(
      canvas,
      Offset(rect.center.dx - labelPainter.width / 2, top),
    );
    seatsPainter.paint(
      canvas,
      Offset(
        rect.center.dx - seatsPainter.width / 2,
        top + labelPainter.height + 2,
      ),
    );
  }

  // ------------------------------------------------------------ structure

  void _paintSegment(
    Canvas canvas,
    EditorObject object, {
    required Color color,
    bool dashed = false,
  }) {
    final rect = object.rect;
    final thickness = math.max(2.0, rect.height);
    final start = Offset(rect.left, rect.center.dy);
    final end = Offset(rect.right, rect.center.dy);

    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    if (!dashed) {
      canvas.drawLine(start, end, paint);
      return;
    }

    const dash = 14.0;
    const space = 8.0;
    var position = 0.0;
    while (position < rect.width) {
      final segmentEnd = math.min(position + dash, rect.width);
      canvas.drawLine(
        Offset(rect.left + position, rect.center.dy),
        Offset(rect.left + segmentEnd, rect.center.dy),
        paint,
      );
      position = segmentEnd + space;
    }
  }

  void _paintDoor(Canvas canvas, EditorObject object, bool selected) {
    final rect = object.rect;
    final ink = selected ? _Ink.selectedLine : _Ink.structure;
    final jamb = Paint()
      ..color = ink
      ..strokeWidth = math.max(3.0, rect.height * 0.22)
      ..strokeCap = StrokeCap.round;
    final leafWidth = rect.width;

    // Opening: two jambs with a swing arc between them.
    canvas
      ..drawLine(
        Offset(rect.left, rect.bottom),
        Offset(rect.left + leafWidth * 0.12, rect.bottom),
        jamb,
      )
      ..drawLine(
        Offset(rect.right - leafWidth * 0.12, rect.bottom),
        Offset(rect.right, rect.bottom),
        jamb,
      )
      ..drawArc(
        Rect.fromCircle(
          center: Offset(rect.left + leafWidth * 0.12, rect.bottom),
          radius: leafWidth * 0.76,
        ),
        -math.pi / 2,
        math.pi / 2,
        false,
        Paint()
          ..color = selected ? _Ink.selectedLine : _Ink.structureSoft
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      )
      ..drawLine(
        Offset(rect.left + leafWidth * 0.12, rect.bottom),
        Offset(rect.left + leafWidth * 0.12, rect.bottom - leafWidth * 0.76),
        Paint()
          ..color = ink
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      );
  }

  void _paintBar(Canvas canvas, EditorObject object, bool selected) {
    final rect = object.rect;
    final ink = selected ? _Ink.selectedLine : _Ink.bar;
    final body = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas
      ..drawRRect(
        body,
        Paint()..color = selected ? _Ink.selectedFill : _Ink.barFill,
      )
      ..drawRRect(
        body,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

    // Service edge: a heavier rule along the long side, so a bar never
    // reads as just another rectangular table.
    final horizontal = rect.width >= rect.height;
    final edge = Paint()
      ..color = ink
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if (horizontal) {
      canvas.drawLine(
        Offset(rect.left + 8, rect.top + 9),
        Offset(rect.right - 8, rect.top + 9),
        edge,
      );
    } else {
      canvas.drawLine(
        Offset(rect.left + 9, rect.top + 8),
        Offset(rect.left + 9, rect.bottom - 8),
        edge,
      );
    }

    if (rect.shortestSide * scale >= 20) {
      _paintCenteredText(
        canvas,
        object.label,
        horizontal
            ? Offset(rect.center.dx, rect.center.dy + 6)
            : Offset(rect.center.dx + 6, rect.center.dy),
        size: math.min(15, math.max(10, rect.shortestSide * 0.26)),
        color: ink,
        weight: FontWeight.w800,
      );
    }
  }

  void _paintZone(Canvas canvas, EditorObject object, bool selected) {
    final rect = object.rect;
    final ink = selected ? _Ink.selectedLine : _Ink.zoneLine;
    final body = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(
      body,
      Paint()
        ..color = selected
            ? _Ink.selectedLine.withValues(alpha: 0.16)
            : _Ink.zoneFill,
    );

    // Dashed boundary: present enough to read as a region, quiet enough to
    // stay behind the tables that sit in it.
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2 : 1.5;
    const dash = 12.0;
    const space = 9.0;
    final path = Path()..addRRect(body);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), stroke);
        distance = next + space;
      }
    }

    final painter = _text(
      object.label,
      size: 13,
      color: ink,
      weight: FontWeight.w800,
    );
    final chip = Rect.fromLTWH(
      rect.left + 12,
      rect.top + 10,
      painter.width + 18,
      painter.height + 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(999)),
      Paint()..color = _Ink.canvas,
    );
    painter.paint(canvas, Offset(chip.left + 9, chip.top + 5));
  }

  void _paintLabel(Canvas canvas, EditorObject object, bool selected) {
    final rect = object.rect;
    _paintCenteredText(
      canvas,
      object.label,
      rect.center,
      size: math.min(17, math.max(11, rect.height * 0.42)),
      color: selected ? _Ink.selectedLine : VynicColors.textMuted,
      weight: FontWeight.w800,
    );
  }

  void _paintUtility(Canvas canvas, EditorObject object, bool selected) {
    final rect = object.rect;
    final ink = selected ? _Ink.selectedLine : _Ink.structureSoft;
    final body = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas
      ..drawRRect(
        body,
        Paint()..color = selected ? _Ink.selectedFill : const Color(0xFFF3F1EC),
      )
      ..drawRRect(
        body,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1.5,
      );

    if (object.type == RestaurantLayoutObjectType.stairs) {
      final treads = Paint()
        ..color = ink.withValues(alpha: 0.5)
        ..strokeWidth = 1.4;
      const steps = 5;
      for (var i = 1; i < steps; i++) {
        final x = rect.left + rect.width * i / steps;
        canvas.drawLine(
          Offset(x, rect.top + 5),
          Offset(x, rect.bottom - 5),
          treads,
        );
      }
    }

    if (rect.shortestSide * scale >= 18) {
      _paintCenteredText(
        canvas,
        object.label,
        rect.center,
        size: math.min(14, math.max(10, rect.shortestSide * 0.24)),
        color: selected ? _Ink.selectedText : VynicColors.textMuted,
      );
    }
  }

  // --------------------------------------------------------------- chrome

  void _paintSelection(Canvas canvas, EditorObject object) {
    final corners = [
      for (final corner in object.rotatedCorners) corner * scale + offset,
    ];

    final path = Path()..addPolygon(corners, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = _Ink.selection
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    if (!showHandles) return;

    final fill = Paint()..color = _Ink.canvas;
    final stroke = Paint()
      ..color = _Ink.selection
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    for (final point in handlePositions(object)) {
      canvas
        ..drawCircle(point.$2, handleRadius, fill)
        ..drawCircle(point.$2, handleRadius, stroke);
    }

    final rotation = rotationHandlePosition(object);
    canvas
      ..drawLine(
        _midpoint(corners[0], corners[1]),
        rotation,
        Paint()
          ..color = _Ink.selection
          ..strokeWidth = 1.4,
      )
      ..drawCircle(rotation, handleRadius + 1, fill)
      ..drawCircle(rotation, handleRadius + 1, stroke);
  }

  static Offset _midpoint(Offset a, Offset b) => (a + b) / 2;

  /// Screen positions of the eight resize grips. Shared with the canvas so
  /// hit testing and drawing can never disagree.
  List<(ResizeHandle, Offset)> handlePositions(EditorObject object) {
    final corners = [
      for (final corner in object.rotatedCorners) corner * scale + offset,
    ];
    final topLeft = corners[0];
    final topRight = corners[1];
    final bottomRight = corners[2];
    final bottomLeft = corners[3];

    // A thin wall has no meaningful top/bottom grips — only its two ends.
    if (object.isSegment) {
      return [
        (ResizeHandle.left, _midpoint(topLeft, bottomLeft)),
        (ResizeHandle.right, _midpoint(topRight, bottomRight)),
      ];
    }

    return [
      (ResizeHandle.topLeft, topLeft),
      (ResizeHandle.top, _midpoint(topLeft, topRight)),
      (ResizeHandle.topRight, topRight),
      (ResizeHandle.right, _midpoint(topRight, bottomRight)),
      (ResizeHandle.bottomRight, bottomRight),
      (ResizeHandle.bottom, _midpoint(bottomRight, bottomLeft)),
      (ResizeHandle.bottomLeft, bottomLeft),
      (ResizeHandle.left, _midpoint(bottomLeft, topLeft)),
    ];
  }

  Offset rotationHandlePosition(EditorObject object) {
    final corners = [
      for (final corner in object.rotatedCorners) corner * scale + offset,
    ];
    final top = _midpoint(corners[0], corners[1]);
    final bottom = _midpoint(corners[3], corners[2]);
    final direction = top - bottom;
    final length = direction.distance;
    if (length < 0.001) {
      return top - const Offset(0, rotationHandleGap);
    }
    return top + (direction / length) * rotationHandleGap;
  }

  void _paintGuides(Canvas canvas, Size size) {
    if (guides.isEmpty) return;
    final paint = Paint()
      ..color = _Ink.guide
      ..strokeWidth = 1;
    for (final guide in guides) {
      if (guide.isVertical) {
        final x = guide.position * scale + offset.dx;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      } else {
        final y = guide.position * scale + offset.dy;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  void _paintMarquee(Canvas canvas) {
    final rect = marquee;
    if (rect == null) return;
    final screen = Rect.fromPoints(
      rect.topLeft * scale + offset,
      rect.bottomRight * scale + offset,
    );
    canvas
      ..drawRect(
        screen,
        Paint()..color = _Ink.selection.withValues(alpha: 0.08),
      )
      ..drawRect(
        screen,
        Paint()
          ..color = _Ink.selection
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  void _paintSegmentPreview(Canvas canvas) {
    final preview = segmentPreview;
    if (preview == null) return;
    final start = preview.$1 * scale + offset;
    final end = preview.$2 * scale + offset;
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = _Ink.structure.withValues(alpha: 0.65)
        ..strokeWidth = math.max(2, segmentThickness * scale)
        ..strokeCap = StrokeCap.round,
    );

    final length = (preview.$2 - preview.$1).distance;
    _paintCenteredText(
      canvas,
      '${length.round()}',
      _midpoint(start, end) - const Offset(0, 18),
      size: 12,
      color: _Ink.guide,
      weight: FontWeight.w800,
    );
  }

  @override
  bool shouldRepaint(covariant FloorEditorPainter oldDelegate) => true;
}
