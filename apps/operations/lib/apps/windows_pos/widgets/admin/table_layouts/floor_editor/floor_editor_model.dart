import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:vynic/core/models/table_layout.dart';

/// Immutable view-model for the floor editor.
///
/// The persisted [RestaurantTableLayout] splits a table across two records —
/// a [RestaurantTableDefinition] (identity, name, capacity) and a
/// [RestaurantLayoutObject] (geometry) linked by `tableId`. That split is
/// awkward to drag around, so the editor works on a single flattened
/// [EditorObject] per thing-on-the-canvas and re-splits on save.
///
/// Nothing here is persisted directly: [EditorDocument.toLayout] rebuilds the
/// exact same model the POS already reads, so old saved layouts keep working.
/// [EditorObject.tableDefinitionId] is the immutable physical-table UUID;
/// [EditorObject.legacyTableNumber] remains separately because orders,
/// reservations and the Hive live-state box still use floor/number aliases.
@immutable
class EditorObject {
  const EditorObject({
    required this.id,
    required this.type,
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.tableShape = RestaurantTableShape.rectangle,
    this.capacity = 0,
    this.legacyTableNumber,
    this.tableDefinitionId,
    this.colorHex,
    this.sortOrder = 0,
  });

  final String id;
  final RestaurantLayoutObjectType type;
  final String label;
  final double x;
  final double y;
  final double width;
  final double height;

  /// Degrees, clockwise, around the object's centre.
  final double rotation;

  /// Only meaningful when [isTable].
  final RestaurantTableShape tableShape;

  /// Seats. Only meaningful when [isTable]; 0 means "unset".
  final int capacity;

  /// Preserved legacy identity — see the class doc.
  final String? legacyTableNumber;
  final String? tableDefinitionId;

  /// Carried through untouched so switching a legacy SVG-mapped layout into
  /// the floor-plan editor and back does not lose its SVG bindings.

  final String? colorHex;
  final int sortOrder;

  bool get isTable => type == RestaurantLayoutObjectType.table;

  bool get isSegment =>
      type == RestaurantLayoutObjectType.wall ||
      type == RestaurantLayoutObjectType.divider;

  bool get isZone => type == RestaurantLayoutObjectType.zone;

  /// Zones sit behind everything and must never swallow a tap meant for a
  /// table sitting inside them.
  bool get isBackdrop => isZone;

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  Offset get center => Offset(x + width / 2, y + height / 2);

  double get rotationRadians => rotation * math.pi / 180;

  /// Axis-aligned bounds that contain the rotated object — used for marquee
  /// selection, alignment and fit-to-content.
  Rect get boundingBox {
    if (rotation % 360 == 0) {
      return rect;
    }
    final corners = rotatedCorners;
    var left = corners.first.dx;
    var top = corners.first.dy;
    var right = left;
    var bottom = top;
    for (final corner in corners.skip(1)) {
      left = math.min(left, corner.dx);
      top = math.min(top, corner.dy);
      right = math.max(right, corner.dx);
      bottom = math.max(bottom, corner.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Corners in world space, clockwise from top-left.
  List<Offset> get rotatedCorners {
    final c = center;
    final angle = rotationRadians;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return [
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ])
        Offset(
          c.dx + (corner.dx - c.dx) * cos - (corner.dy - c.dy) * sin,
          c.dy + (corner.dx - c.dx) * sin + (corner.dy - c.dy) * cos,
        ),
    ];
  }

  /// Maps a world point into the object's unrotated local space, so hit
  /// testing and handle maths can ignore rotation.
  Offset toLocal(Offset world) {
    final c = center;
    final angle = -rotationRadians;
    final dx = world.dx - c.dx;
    final dy = world.dy - c.dy;
    return Offset(
      c.dx + dx * math.cos(angle) - dy * math.sin(angle),
      c.dy + dx * math.sin(angle) + dy * math.cos(angle),
    );
  }

  bool containsWorldPoint(Offset world, {double tolerance = 0}) {
    return rect.inflate(tolerance).contains(toLocal(world));
  }

  EditorObject copyWith({
    RestaurantLayoutObjectType? type,
    String? label,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    RestaurantTableShape? tableShape,
    int? capacity,
    String? colorHex,
    int? sortOrder,
  }) {
    return EditorObject(
      id: id,
      type: type ?? this.type,
      label: label ?? this.label,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      tableShape: tableShape ?? this.tableShape,
      capacity: capacity ?? this.capacity,
      legacyTableNumber: legacyTableNumber,
      tableDefinitionId: tableDefinitionId,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// A copy with a brand-new id — and, for tables, a brand-new legacy
  /// identity, because two tables may never share `(floor, tableNumber)`.
  EditorObject duplicated({
    required String newId,
    required String? newLegacyTableNumber,
    required String? newTableDefinitionId,
    required String newLabel,
    double dx = 0,
    double dy = 0,
  }) {
    return EditorObject(
      id: newId,
      type: type,
      label: newLabel,
      x: x + dx,
      y: y + dy,
      width: width,
      height: height,
      rotation: rotation,
      tableShape: tableShape,
      capacity: capacity,
      legacyTableNumber: newLegacyTableNumber,
      tableDefinitionId: newTableDefinitionId,
      colorHex: colorHex,
      sortOrder: sortOrder,
    );
  }
}

/// One floor / area of the venue. Maps 1:1 onto a persisted [RestaurantZone].
@immutable
class EditorFloor {
  const EditorFloor({
    required this.zoneId,
    required this.legacyFloor,
    required this.displayOrder,
    required this.name,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.objects,
    this.renderMode = TableLayoutRenderMode.floorPlan,
  });

  final String zoneId;

  /// The `'first'`/`'second'`/`'floor-3'` key that live table rows, orders
  /// and reservations are stored against. Never rewritten by the editor.
  final String legacyFloor;

  final int displayOrder;
  final String name;
  final double canvasWidth;
  final double canvasHeight;
  final List<EditorObject> objects;

  /// Preserved verbatim so renaming a floor never silently converts a
  /// legacy SVG-mapped or button-grid zone into a floor plan. Only the
  /// editor itself flips a floor to [TableLayoutRenderMode.floorPlan], and
  /// only for the floor whose geometry it actually edited.
  final TableLayoutRenderMode renderMode;

  Iterable<EditorObject> get tables => objects.where((o) => o.isTable);

  int get tableCount => tables.length;

  int get seatCount =>
      tables.fold(0, (total, table) => total + math.max(0, table.capacity));

  Size get canvasSize => Size(canvasWidth, canvasHeight);

  /// Smallest canvas that still contains every object, or null on an empty
  /// floor. Reshaping the canvas must never go below this, or a table would
  /// end up outside the plan.
  Rect? get contentBounds {
    if (objects.isEmpty) {
      return null;
    }
    var bounds = objects.first.boundingBox;
    for (final object in objects.skip(1)) {
      bounds = bounds.expandToInclude(object.boundingBox);
    }
    return bounds;
  }

  EditorFloor copyWith({
    String? name,
    double? canvasWidth,
    double? canvasHeight,
    List<EditorObject>? objects,
    int? displayOrder,
    TableLayoutRenderMode? renderMode,
  }) {
    return EditorFloor(
      zoneId: zoneId,
      legacyFloor: legacyFloor,
      displayOrder: displayOrder ?? this.displayOrder,
      name: name ?? this.name,
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
      objects: objects ?? this.objects,
      renderMode: renderMode ?? this.renderMode,
    );
  }

  /// Lowest unused positive integer, so deleting T3 then adding a table
  /// reuses `3` rather than drifting numbers upward forever.
  String nextLegacyTableNumber() {
    final used = <int>{
      for (final table in tables)
        if (int.tryParse(table.legacyTableNumber ?? '') case final int n) n,
    };
    var candidate = 1;
    while (used.contains(candidate)) {
      candidate++;
    }
    return '$candidate';
  }

  /// The zone region whose area is smallest among those containing [point] —
  /// the innermost one wins when regions are nested.
  ///
  /// Zone membership is *derived from geometry*, not stored: the legacy
  /// [RestaurantTableDefinition] has no per-table area field, and inventing
  /// one would be a data-model change this pass explicitly defers.
  EditorObject? zoneAt(Offset point) {
    EditorObject? best;
    for (final object in objects) {
      if (!object.isZone || !object.containsWorldPoint(point)) {
        continue;
      }
      if (best == null ||
          object.width * object.height < best.width * best.height) {
        best = object;
      }
    }
    return best;
  }
}

/// The whole editable layout: every floor plus the layout-level name.
@immutable
class EditorDocument {
  const EditorDocument({
    required this.layoutId,
    required this.name,
    required this.floors,
  });

  final String layoutId;
  final String name;
  final List<EditorFloor> floors;

  EditorDocument copyWith({String? name, List<EditorFloor>? floors}) {
    return EditorDocument(
      layoutId: layoutId,
      name: name ?? this.name,
      floors: floors ?? this.floors,
    );
  }

  EditorFloor? floorById(String zoneId) {
    for (final floor in floors) {
      if (floor.zoneId == zoneId) {
        return floor;
      }
    }
    return null;
  }

  EditorDocument replaceFloor(EditorFloor floor) {
    return copyWith(
      floors: [
        for (final existing in floors)
          if (existing.zoneId == floor.zoneId) floor else existing,
      ],
    );
  }

  // ---------------------------------------------------------------- loading

  static const double _fallbackCanvasWidth = 1000;
  static const double _fallbackCanvasHeight = 1000;

  factory EditorDocument.fromLayout(RestaurantTableLayout layout) {
    final zones = [...layout.zones]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return EditorDocument(
      layoutId: layout.id,
      name: layout.name,
      floors: [for (final zone in zones) _floorFromZone(layout, zone)],
    );
  }

  static EditorFloor _floorFromZone(
    RestaurantTableLayout layout,
    RestaurantZone zone,
  ) {
    final canvasWidth = zone.canvasWidth ?? _fallbackCanvasWidth;
    final canvasHeight = zone.canvasHeight ?? _fallbackCanvasHeight;
    final definitions = layout.tablesForZone(zone.id);
    final objects = <EditorObject>[];

    for (var i = 0; i < definitions.length; i++) {
      final definition = definitions[i];
      final visual = layout.objectForTable(definition.id);
      // A button-grid layout has no floor-plan geometry for its tables; fall
      // back to a readable grid so opening one in the editor shows real tables
      // rather than a blank canvas. (This used to fall back to the SVG hit box
      // first, which is gone along with the drawings.)
      final fallback = _fallbackTableRect(i);
      objects.add(
        EditorObject(
          id: visual?.id ?? '${definition.id}-visual',
          type: RestaurantLayoutObjectType.table,
          label: definition.label,
          x: visual?.x ?? fallback.left,
          y: visual?.y ?? fallback.top,
          width: visual?.width ?? fallback.width,
          height: visual?.height ?? fallback.height,
          rotation: visual?.rotation ?? 0,
          tableShape: visual?.tableShape ?? RestaurantTableShape.rectangle,
          capacity: definition.capacity,
          legacyTableNumber: definition.legacyTableNumber,
          tableDefinitionId: definition.id,
          sortOrder: definition.sortOrder,
        ),
      );
    }

    for (final object in layout.objectsForZone(zone.id)) {
      if (object.type == RestaurantLayoutObjectType.table) {
        continue;
      }
      objects.add(
        EditorObject(
          id: object.id,
          type: object.type,
          label: object.label,
          x: object.x,
          y: object.y,
          width: object.width,
          height: object.height,
          rotation: object.rotation,
          colorHex: object.colorHex,
          sortOrder: object.sortOrder,
        ),
      );
    }

    return EditorFloor(
      zoneId: zone.id,
      legacyFloor: zone.legacyFloor,
      displayOrder: zone.displayOrder,
      name: zone.name,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      renderMode: zone.renderMode,
      objects: objects,
    );
  }

  static Rect _fallbackTableRect(int index) {
    const columns = 4;
    const cellWidth = 210.0;
    const cellHeight = 130.0;
    return Rect.fromLTWH(
      70 + (index % columns) * cellWidth,
      70 + (index ~/ columns) * cellHeight,
      130,
      86,
    );
  }

  // ---------------------------------------------------------------- saving

  /// Rebuilds the persisted model exactly as the POS already reads it.
  ///
  /// Each floor keeps its own [EditorFloor.renderMode]; the editor screen is
  /// what flips the floor it edited to [TableLayoutRenderMode.floorPlan],
  /// because that floor now has real geometry to render.
  RestaurantTableLayout toLayout() {
    final zones = <RestaurantZone>[];
    final definitions = <RestaurantTableDefinition>[];
    final objects = <RestaurantLayoutObject>[];

    for (final floor in floors) {
      zones.add(
        RestaurantZone(
          id: floor.zoneId,
          name: floor.name,
          legacyFloor: floor.legacyFloor,
          displayOrder: floor.displayOrder,
          renderMode: floor.renderMode,
          canvasWidth: floor.canvasWidth,
          canvasHeight: floor.canvasHeight,
        ),
      );

      var tableIndex = 0;
      var objectIndex = 0;
      for (final object in floor.objects) {
        if (object.isTable) {
          tableIndex++;
          final legacyNumber = object.legacyTableNumber ?? '$tableIndex';
          final definitionId =
              object.tableDefinitionId ??
              '${floor.legacyFloor}-table-$legacyNumber';
          definitions.add(
            RestaurantTableDefinition(
              id: definitionId,
              zoneId: floor.zoneId,
              legacyFloor: floor.legacyFloor,
              legacyTableNumber: legacyNumber,
              label: object.label,
              capacity: object.capacity,
              sortOrder: tableIndex,
            ),
          );
          objects.add(
            RestaurantLayoutObject(
              id: object.id,
              zoneId: floor.zoneId,
              type: RestaurantLayoutObjectType.table,
              label: object.label,
              x: object.x,
              y: object.y,
              width: object.width,
              height: object.height,
              rotation: object.rotation,
              sortOrder: tableIndex,
              tableId: definitionId,
              tableShape: object.tableShape,
            ),
          );
        } else {
          objectIndex++;
          objects.add(
            RestaurantLayoutObject(
              id: object.id,
              zoneId: floor.zoneId,
              type: object.type,
              label: object.label,
              x: object.x,
              y: object.y,
              width: object.width,
              height: object.height,
              rotation: object.rotation,
              sortOrder: 1000 + objectIndex,
              colorHex: object.colorHex,
            ),
          );
        }
      }
    }

    return RestaurantTableLayout(
      id: layoutId,
      name: name.trim().isEmpty ? 'Custom floor plan' : name.trim(),
      zones: zones,
      tables: definitions,
      objects: objects,
    );
  }
}
