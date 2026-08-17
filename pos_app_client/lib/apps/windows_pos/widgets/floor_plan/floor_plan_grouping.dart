import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// One table considered for grouping, in layout coordinates.
typedef FloorPlanGroupCandidate = ({String id, Rect rect});

/// Smallest reach, in layout units, for tables that are tiny (bar stools).
const double floorPlanMinJoinGap = 48;

/// How far apart two tables can be and still count as "pushed together".
///
/// Scaled to the tables themselves rather than a fixed distance: a gap smaller
/// than the narrower table means nothing else could fit between them, so they
/// are neighbours. A fixed threshold made this depend on how widely a
/// particular floor happened to be spaced — tables laid out on a generous grid
/// never joined, while tightly packed ones did.
///
/// Being generous here is safe because [floorPlanAdjacencyGroups] also refuses
/// any pair with another table physically in the way.
double floorPlanJoinGapFor(Rect a, Rect b) {
  return math.max(
    floorPlanMinJoinGap,
    math.min(a.shortestSide, b.shortestSide),
  );
}

/// Clusters [selected] into the sets of tables that can physically be pushed
/// together.
///
/// Two selected tables join when they are close enough — [maxGap], or
/// [floorPlanJoinGapFor] when that is left null — *and* nothing else stands
/// between them — a third table sitting in the gap means
/// they cannot actually be joined, so selecting table 1 and table 3 across
/// table 2 yields two separate clusters rather than one.
///
/// [obstacles] should be every table on the floor, including the selected ones;
/// a candidate never blocks itself or its partner.
///
/// Returns only clusters of two or more, in the order their first member
/// appears in [selected]. Single tables are not a join.
List<List<String>> floorPlanAdjacencyGroups({
  required List<FloorPlanGroupCandidate> selected,
  required List<FloorPlanGroupCandidate> obstacles,
  double? maxGap,
}) {
  if (selected.length < 2) {
    return const [];
  }

  // Adjacency list over the selected tables.
  final links = <int, Set<int>>{
    for (var i = 0; i < selected.length; i++) i: <int>{},
  };
  for (var i = 0; i < selected.length; i++) {
    for (var j = i + 1; j < selected.length; j++) {
      if (_canJoin(selected[i], selected[j], obstacles, maxGap)) {
        links[i]!.add(j);
        links[j]!.add(i);
      }
    }
  }

  final visited = <int>{};
  final groups = <List<String>>[];
  for (var i = 0; i < selected.length; i++) {
    if (visited.contains(i)) continue;
    final queue = <int>[i];
    final cluster = <int>[];
    visited.add(i);
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      cluster.add(current);
      for (final next in links[current]!) {
        if (visited.add(next)) {
          queue.add(next);
        }
      }
    }
    if (cluster.length < 2) continue;
    cluster.sort();
    groups.add([for (final index in cluster) selected[index].id]);
  }
  return groups;
}

bool _canJoin(
  FloorPlanGroupCandidate a,
  FloorPlanGroupCandidate b,
  List<FloorPlanGroupCandidate> obstacles,
  double? maxGap,
) {
  final limit = maxGap ?? floorPlanJoinGapFor(a.rect, b.rect);
  if (floorPlanRectGap(a.rect, b.rect) > limit) {
    return false;
  }
  final from = a.rect.center;
  final to = b.rect.center;
  for (final obstacle in obstacles) {
    if (obstacle.id == a.id || obstacle.id == b.id) {
      continue;
    }
    if (_segmentIntersectsRect(from, to, obstacle.rect)) {
      return false;
    }
  }
  return true;
}

/// Edge-to-edge distance between two axis-aligned rects; 0 when they touch or
/// overlap.
double floorPlanRectGap(Rect a, Rect b) {
  final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right));
  final dy = math.max(0.0, math.max(a.top - b.bottom, b.top - a.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

/// Liang–Barsky segment/rect clip — true when the segment touches the rect.
bool _segmentIntersectsRect(Offset from, Offset to, Rect rect) {
  if (rect.contains(from) || rect.contains(to)) {
    return true;
  }
  var t0 = 0.0;
  var t1 = 1.0;
  final dx = to.dx - from.dx;
  final dy = to.dy - from.dy;

  for (var edge = 0; edge < 4; edge++) {
    final double p;
    final double q;
    switch (edge) {
      case 0:
        p = -dx;
        q = from.dx - rect.left;
      case 1:
        p = dx;
        q = rect.right - from.dx;
      case 2:
        p = -dy;
        q = from.dy - rect.top;
      default:
        p = dy;
        q = rect.bottom - from.dy;
    }

    if (p == 0) {
      // Parallel to this edge and starting outside it: no intersection.
      if (q < 0) return false;
      continue;
    }
    final r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
  }
  return true;
}

/// Bounding box of a cluster, for drawing the band that ties it together.
Rect floorPlanGroupBounds(Iterable<Rect> rects) {
  final iterator = rects.iterator;
  if (!iterator.moveNext()) {
    return Rect.zero;
  }
  var bounds = iterator.current;
  while (iterator.moveNext()) {
    bounds = bounds.expandToInclude(iterator.current);
  }
  return bounds;
}

/// Whether [selected] forms a single physically joinable run.
///
/// Used to police multi-table selection: a party can only be seated across
/// tables that are actually pushed together, so picking table 1 and table 3
/// with table 2 between them is not a valid selection at all — not merely one
/// that fails to merge.
bool floorPlanSelectionIsContiguous({
  required List<FloorPlanGroupCandidate> selected,
  required List<FloorPlanGroupCandidate> obstacles,
}) {
  if (selected.length < 2) {
    return true;
  }
  final groups = floorPlanAdjacencyGroups(
    selected: selected,
    obstacles: obstacles,
  );
  return groups.length == 1 && groups.first.length == selected.length;
}
