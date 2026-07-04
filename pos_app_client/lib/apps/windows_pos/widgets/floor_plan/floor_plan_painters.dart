import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared rendering for saved visual floor plans, used by both the POS
/// table selector and the admin layout editor.

/// Wall geometry in layout coordinates, independent of the caller's
/// object model (saved layout objects vs editor draft objects).
typedef FloorPlanWallSegment = ({
  double x,
  double y,
  double width,
  double height,
  double rotation,
});

class FloorPlanWallJoint {
  const FloorPlanWallJoint({required this.center, required this.radius});

  final Offset center;
  final double radius;
}

class _FloorPlanWallEndpoint {
  const _FloorPlanWallEndpoint({required this.point, required this.radius});

  final Offset point;
  final double radius;
}

(Offset, Offset) floorPlanWallEndpoints(FloorPlanWallSegment wall) {
  final center = Offset(wall.x + wall.width / 2, wall.y + wall.height / 2);
  final angle = wall.rotation * math.pi / 180;
  final half = Offset(math.cos(angle), math.sin(angle)) * (wall.width / 2);
  return (center - half, center + half);
}

/// Groups wall endpoints that (nearly) touch into solid joint dots so
/// split/connected segments render as one continuous wall.
List<FloorPlanWallJoint> floorPlanWallJoints(
  List<FloorPlanWallSegment> walls,
  double scale,
) {
  final endpoints = <_FloorPlanWallEndpoint>[];
  for (final wall in walls) {
    final points = floorPlanWallEndpoints(wall);
    final radius = wall.height * scale / 2;
    endpoints
      ..add(_FloorPlanWallEndpoint(point: points.$1 * scale, radius: radius))
      ..add(_FloorPlanWallEndpoint(point: points.$2 * scale, radius: radius));
  }

  final used = <int>{};
  final joints = <FloorPlanWallJoint>[];
  for (var i = 0; i < endpoints.length; i++) {
    if (used.contains(i)) {
      continue;
    }
    final group = <_FloorPlanWallEndpoint>[endpoints[i]];
    for (var j = i + 1; j < endpoints.length; j++) {
      if (used.contains(j)) {
        continue;
      }
      final tolerance = math.max(8.0, endpoints[i].radius * 0.65);
      if ((endpoints[i].point - endpoints[j].point).distance <= tolerance) {
        group.add(endpoints[j]);
        used.add(j);
      }
    }
    if (group.length < 2) {
      continue;
    }
    used.add(i);
    final center =
        group.map((entry) => entry.point).reduce((a, b) => a + b) /
        group.length.toDouble();
    final radius = group.map((entry) => entry.radius).reduce(math.max);
    joints.add(FloorPlanWallJoint(center: center, radius: radius));
  }
  return joints;
}

class FloorPlanGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    const spacing = 24.0;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FloorPlanStairsPainter extends CustomPainter {
  const FloorPlanStairsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 2;
    const steps = 5;
    for (var i = 1; i < steps; i++) {
      final x = size.width * i / steps;
      canvas.drawLine(Offset(x, 6), Offset(x, size.height - 6), paint);
    }
    for (var i = 1; i < steps; i++) {
      final y = size.height * i / steps;
      canvas.drawLine(Offset(6, y), Offset(size.width - 6, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanStairsPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class FloorPlanWallSegmentPainter extends CustomPainter {
  const FloorPlanWallSegmentPainter({
    required this.color,
    required this.borderColor,
    this.selected = false,
  });

  final Color color;
  final Color borderColor;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = size.height + (selected ? 8 : 4)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final fillPaint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas
      ..drawLine(Offset(0, centerY), Offset(size.width, centerY), borderPaint)
      ..drawLine(Offset(0, centerY), Offset(size.width, centerY), fillPaint);
  }

  @override
  bool shouldRepaint(covariant FloorPlanWallSegmentPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.selected != selected;
  }
}

class FloorPlanWallJointsPainter extends CustomPainter {
  const FloorPlanWallJointsPainter({
    required this.joints,
    required this.color,
    required this.borderColor,
  });

  final List<FloorPlanWallJoint> joints;
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = borderColor
      ..isAntiAlias = true;
    final fillPaint = Paint()
      ..color = color
      ..isAntiAlias = true;
    for (final joint in joints) {
      canvas
        ..drawCircle(joint.center, joint.radius + 2, borderPaint)
        ..drawCircle(joint.center, joint.radius, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanWallJointsPainter oldDelegate) {
    return oldDelegate.joints != joints ||
        oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor;
  }
}
