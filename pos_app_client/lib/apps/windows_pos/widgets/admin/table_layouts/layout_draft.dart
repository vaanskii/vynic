import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vynic/core/models/table_layout.dart';

/// Mutable draft state for the admin floor-plan editor: floors, tables,
/// and venue objects being edited before they are built into a
/// [RestaurantTableLayout] and saved.

const double _defaultPlanCanvasWidth = 1000;
const double _defaultPlanCanvasHeight = 1000;

class EditableZonePlan {
  EditableZonePlan({
    required this.zoneId,
    required this.floorKey,
    required this.displayOrder,
    required this.canvasWidth,
    required this.canvasHeight,
    required String name,
    required this.tables,
    required this.objects,
  }) : nameController = TextEditingController(text: name);

  factory EditableZonePlan.create(int displayOrder) {
    final floorKey = displayOrder == 1
        ? 'first'
        : displayOrder == 2
        ? 'second'
        : 'floor-$displayOrder';
    return EditableZonePlan(
      zoneId: displayOrder == 1
          ? 'main-floor'
          : displayOrder == 2
          ? 'vip-floor'
          : 'floor-$displayOrder',
      floorKey: floorKey,
      displayOrder: displayOrder,
      canvasWidth: _defaultPlanCanvasWidth,
      canvasHeight: _defaultPlanCanvasHeight,
      name: displayOrder == 1
          ? 'First floor'
          : displayOrder == 2
          ? 'Second floor'
          : 'Floor $displayOrder',
      tables: [EditableTableDefinition.create(floorKey, 1, '1')],
      objects: [],
    );
  }

  factory EditableZonePlan.fromLayout(
    RestaurantTableLayout layout,
    RestaurantZone zone,
  ) {
    final tables = layout.tablesForZone(zone.id);
    return EditableZonePlan(
      zoneId: zone.id,
      floorKey: zone.legacyFloor,
      displayOrder: zone.displayOrder,
      canvasWidth: zone.canvasWidth ?? _defaultPlanCanvasWidth,
      canvasHeight: zone.canvasHeight ?? _defaultPlanCanvasHeight,
      name: zone.name,
      tables: [
        for (var i = 0; i < tables.length; i++)
          EditableTableDefinition.fromLayout(
            tables[i],
            layout.objectForTable(tables[i].id),
            i,
          ),
      ],
      objects: [
        for (final object in layout.objectsForZone(zone.id))
          if (object.type != RestaurantLayoutObjectType.table)
            EditablePlanObject.fromLayout(object),
      ],
    );
  }

  EditableZonePlan copy() {
    return EditableZonePlan(
      zoneId: zoneId,
      floorKey: floorKey,
      displayOrder: displayOrder,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      name: name,
      tables: [for (final table in tables) table.copy()],
      objects: [for (final object in objects) object.copy()],
    );
  }

  final String zoneId;
  final String floorKey;
  final int displayOrder;
  final double canvasWidth;
  final double canvasHeight;
  final TextEditingController nameController;
  final List<EditableTableDefinition> tables;
  final List<EditablePlanObject> objects;

  String get name {
    final value = nameController.text.trim();
    return value.isEmpty ? 'Floor $displayOrder' : value;
  }

  void renumberTables() {
    for (var i = 0; i < tables.length; i++) {
      tables[i].sortOrder = i + 1;
    }
  }

  String nextLegacyTableNumber() {
    var highest = 0;
    for (final table in tables) {
      final parsed = int.tryParse(table.legacyTableNumber);
      if (parsed != null && parsed > highest) {
        highest = parsed;
      }
    }
    return '${highest + 1}';
  }

  void replaceFrom(EditableZonePlan other) {
    for (final table in tables) {
      table.dispose();
    }
    nameController.text = other.name;
    tables
      ..clear()
      ..addAll([for (final table in other.tables) table.copy()]);
    objects
      ..clear()
      ..addAll([for (final object in other.objects) object.copy()]);
    renumberTables();
  }

  void dispose() {
    nameController.dispose();
    for (final table in tables) {
      table.dispose();
    }
  }
}

class EditableTableDefinition {
  EditableTableDefinition({
    required this.legacyTableNumber,
    required this.sortOrder,
    required String label,
    required int capacity,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.shape,
    this.rotation = 0,
  }) : labelController = TextEditingController(text: label),
       capacityController = TextEditingController(
         text: capacity > 0 ? capacity.toString() : '',
       );

  factory EditableTableDefinition.create(
    String floor,
    int sortOrder,
    String legacyTableNumber,
  ) {
    final label = floor == 'second'
        ? 'VIP Zone $legacyTableNumber'
        : 'Table $legacyTableNumber';
    final point = _defaultTablePoint(sortOrder - 1);
    final size = _tableSize(RestaurantTableShape.rectangle);
    return EditableTableDefinition(
      legacyTableNumber: legacyTableNumber,
      sortOrder: sortOrder,
      label: label,
      capacity: 0,
      x: point.dx,
      y: point.dy,
      width: size.width,
      height: size.height,
      shape: RestaurantTableShape.rectangle,
    );
  }

  factory EditableTableDefinition.fromLayout(
    RestaurantTableDefinition table,
    RestaurantLayoutObject? object,
    int index,
  ) {
    final shape = object?.tableShape ?? RestaurantTableShape.rectangle;
    final point = _defaultTablePoint(index);
    final size = _tableSize(shape);
    return EditableTableDefinition(
      legacyTableNumber: table.legacyTableNumber,
      sortOrder: table.sortOrder,
      label: table.label,
      capacity: table.capacity,
      x: object?.x ?? point.dx,
      y: object?.y ?? point.dy,
      width: object?.width ?? size.width,
      height: object?.height ?? size.height,
      rotation: object?.rotation ?? 0,
      shape: shape,
    );
  }

  EditableTableDefinition copy() {
    return EditableTableDefinition(
      legacyTableNumber: legacyTableNumber,
      sortOrder: sortOrder,
      label: label,
      capacity: capacity,
      x: x,
      y: y,
      width: width,
      height: height,
      shape: shape,
      rotation: rotation,
    );
  }

  /// Stable identity: orders, reservations, and Hive table rows key on
  /// (floor, tableNumber), so this must survive reorders and deletions.
  final String legacyTableNumber;
  int sortOrder;
  final TextEditingController labelController;
  final TextEditingController capacityController;
  double x;
  double y;
  double width;
  double height;
  double rotation;
  RestaurantTableShape shape;

  String get label {
    final value = labelController.text.trim();
    return value.isEmpty ? 'Table $sortOrder' : value;
  }

  int get capacity {
    final parsed = int.tryParse(capacityController.text.trim());
    if (parsed == null || parsed < 0) {
      return 0;
    }
    return parsed;
  }

  void applyShape(
    RestaurantTableShape value, {
    required double canvasWidth,
    required double canvasHeight,
  }) {
    shape = value;
    final size = _tableSize(value);
    width = size.width;
    height = size.height;
    moveBy(0, 0, canvasWidth: canvasWidth, canvasHeight: canvasHeight);
  }

  void resizeBy({
    double widthDelta = 0,
    double heightDelta = 0,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    width = (width + widthDelta).clamp(54, 280).toDouble();
    height = (height + heightDelta).clamp(44, 180).toDouble();
    moveBy(0, 0, canvasWidth: canvasWidth, canvasHeight: canvasHeight);
  }

  void rotateBy(double delta) {
    rotation = (rotation + delta) % 360;
  }

  void moveBy(
    double dx,
    double dy, {
    required double canvasWidth,
    required double canvasHeight,
  }) {
    x = _clampCanvasCoordinate(x + dx, width, canvasWidth);
    y = _clampCanvasCoordinate(y + dy, height, canvasHeight);
  }

  void placeAt(
    double newX,
    double newY, {
    required double canvasWidth,
    required double canvasHeight,
  }) {
    x = _clampCanvasCoordinate(newX, width, canvasWidth);
    y = _clampCanvasCoordinate(newY, height, canvasHeight);
  }

  void dispose() {
    labelController.dispose();
    capacityController.dispose();
  }
}

class EditablePlanObject {
  EditablePlanObject({
    required this.id,
    required this.type,
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.colorHex,
  });

  factory EditablePlanObject.create(
    RestaurantLayoutObjectType type,
    int index,
  ) {
    final size = _defaultObjectSize(type);
    return EditablePlanObject(
      id: '${type.name}-${DateTime.now().microsecondsSinceEpoch}-$index',
      type: type,
      label: labelForObjectType(type),
      x: 90 + (index * 28),
      y: 80 + (index * 24),
      width: size.width,
      height: size.height,
    );
  }

  factory EditablePlanObject.fromLayout(RestaurantLayoutObject object) {
    return EditablePlanObject(
      id: object.id,
      type: object.type,
      label: object.label,
      x: object.x,
      y: object.y,
      width: object.width,
      height: object.height,
      rotation: object.rotation,
      colorHex: object.colorHex,
    );
  }

  EditablePlanObject copy() {
    return EditablePlanObject(
      id: id,
      type: type,
      label: label,
      x: x,
      y: y,
      width: width,
      height: height,
      rotation: rotation,
      colorHex: colorHex,
    );
  }

  EditablePlanObject copyWith({
    String? id,
    RestaurantLayoutObjectType? type,
    String? label,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    String? colorHex,
  }) {
    return EditablePlanObject(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  final String id;
  final RestaurantLayoutObjectType type;
  String label;
  double x;
  double y;
  double width;
  double height;
  double rotation;
  final String? colorHex;

  void moveBy(
    double dx,
    double dy, {
    required double canvasWidth,
    required double canvasHeight,
  }) {
    x = _clampCanvasCoordinate(x + dx, width, canvasWidth);
    y = _clampCanvasCoordinate(y + dy, height, canvasHeight);
  }

  void resizeBy({
    double widthDelta = 0,
    double heightDelta = 0,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    final maxWidth = type == RestaurantLayoutObjectType.wall ? 900.0 : 460.0;
    final minHeight = type == RestaurantLayoutObjectType.wall ? 8.0 : 24.0;
    final maxHeight = type == RestaurantLayoutObjectType.wall ? 110.0 : 240.0;
    width = (width + widthDelta).clamp(40, maxWidth).toDouble();
    height = (height + heightDelta).clamp(minHeight, maxHeight).toDouble();
    moveBy(0, 0, canvasWidth: canvasWidth, canvasHeight: canvasHeight);
  }

  void rotateBy(double delta) {
    rotation = (rotation + delta) % 360;
  }
}

Offset _defaultTablePoint(int index) {
  const columns = 4;
  const cellWidth = 210.0;
  const cellHeight = 130.0;
  return Offset(
    70 + (index % columns) * cellWidth,
    70 + (index ~/ columns) * cellHeight,
  );
}

double _clampCanvasCoordinate(
  double value,
  double objectSize,
  double canvasSize,
) {
  final maxValue = math.max(0.0, canvasSize - objectSize);
  return value.clamp(0.0, maxValue).toDouble();
}

EditablePlanObject? editableWallFromPoints({
  required String id,
  required Offset start,
  required Offset end,
  required double thickness,
  String? label,
}) {
  final vector = end - start;
  final length = vector.distance;
  if (length < 18) {
    return null;
  }
  final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
  return EditablePlanObject(
    id: id,
    type: RestaurantLayoutObjectType.wall,
    label: label ?? labelForObjectType(RestaurantLayoutObjectType.wall),
    x: center.dx - length / 2,
    y: center.dy - thickness / 2,
    width: length,
    height: thickness,
    rotation: math.atan2(vector.dy, vector.dx) * 180 / math.pi,
  );
}

Size _tableSize(RestaurantTableShape shape) {
  switch (shape) {
    case RestaurantTableShape.rectangle:
      return const Size(130, 86);
    case RestaurantTableShape.rounded:
      return const Size(136, 88);
    case RestaurantTableShape.square:
      return const Size(112, 112);
    case RestaurantTableShape.circle:
      return const Size(112, 112);
    case RestaurantTableShape.long:
      return const Size(190, 86);
    case RestaurantTableShape.booth:
      return const Size(160, 88);
    case RestaurantTableShape.barSeat:
      return const Size(86, 86);
  }
}

Size _defaultObjectSize(RestaurantLayoutObjectType type) {
  switch (type) {
    case RestaurantLayoutObjectType.wall:
      return const Size(240, 24);
    case RestaurantLayoutObjectType.entrance:
      return const Size(180, 56);
    case RestaurantLayoutObjectType.stairs:
      return const Size(160, 90);
    case RestaurantLayoutObjectType.stage:
      return const Size(240, 90);
    case RestaurantLayoutObjectType.bar:
    case RestaurantLayoutObjectType.counter:
      return const Size(220, 64);
    case RestaurantLayoutObjectType.restroom:
    case RestaurantLayoutObjectType.label:
    case RestaurantLayoutObjectType.table:
      return const Size(150, 48);
  }
}

String labelForObjectType(RestaurantLayoutObjectType type) {
  switch (type) {
    case RestaurantLayoutObjectType.wall:
      return 'Wall';
    case RestaurantLayoutObjectType.entrance:
      return 'Entrance';
    case RestaurantLayoutObjectType.stairs:
      return 'Stairs';
    case RestaurantLayoutObjectType.stage:
      return 'Stage';
    case RestaurantLayoutObjectType.bar:
      return 'Bar';
    case RestaurantLayoutObjectType.counter:
      return 'Counter';
    case RestaurantLayoutObjectType.restroom:
      return 'Restroom';
    case RestaurantLayoutObjectType.table:
      return 'Table';
    case RestaurantLayoutObjectType.label:
      return 'Label';
  }
}
