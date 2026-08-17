import 'package:flutter/material.dart';

import 'package:vynic/core/models/table_layout.dart';

/// What a single click on the canvas creates.
///
/// Presets exist so an administrator picks "round, 4 seats" and drops it —
/// instead of building a rectangle and typing width/height, which is the
/// interaction this redesign is replacing.
@immutable
class EditorPlacementSpec {
  const EditorPlacementSpec({
    required this.id,
    required this.type,
    required this.label,
    required this.width,
    required this.height,
    this.tableShape = RestaurantTableShape.rectangle,
    this.capacity = 0,
    this.nameSeed,
  });

  final String id;
  final RestaurantLayoutObjectType type;

  /// Shown in the palette.
  final String label;

  final double width;
  final double height;
  final RestaurantTableShape tableShape;
  final int capacity;

  /// Prefix used when auto-naming the placed object ("T", "B", "Bar"...).
  final String? nameSeed;

  bool get isTable => type == RestaurantLayoutObjectType.table;

  bool get isSegment =>
      type == RestaurantLayoutObjectType.wall ||
      type == RestaurantLayoutObjectType.divider;
}

/// A group of presets in the left palette.
@immutable
class EditorPaletteGroup {
  const EditorPaletteGroup({
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final List<EditorPaletteEntry> entries;
}

@immutable
class EditorPaletteEntry {
  const EditorPaletteEntry({
    required this.icon,
    required this.tooltip,
    required this.spec,
    this.variants = const [],
  });

  final IconData icon;
  final String tooltip;

  /// Chosen when the entry is clicked without picking a variant.
  final EditorPlacementSpec spec;

  /// Seat/size presets revealed on hover-press, e.g. "Round · 4 seats".
  final List<EditorPlacementSpec> variants;

  bool get hasVariants => variants.isNotEmpty;
}

/// Seats are stored in [RestaurantTableDefinition.capacity]; sizes in the
/// layout object. Both already persist, so presets need no new fields.
abstract final class EditorPresets {
  static const double gridStep = 20;

  static const _square2 = EditorPlacementSpec(
    id: 'square-2',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.square,
    label: 'კვადრატი · 2 ადგილი',
    width: 80,
    height: 80,
    capacity: 2,
    nameSeed: 'T',
  );

  static const _square4 = EditorPlacementSpec(
    id: 'square-4',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.square,
    label: 'კვადრატი · 4 ადგილი',
    width: 110,
    height: 110,
    capacity: 4,
    nameSeed: 'T',
  );

  static const _rectangle4 = EditorPlacementSpec(
    id: 'rect-4',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.rectangle,
    label: 'მართკუთხედი · 4 ადგილი',
    width: 140,
    height: 90,
    capacity: 4,
    nameSeed: 'T',
  );

  static const _rectangle6 = EditorPlacementSpec(
    id: 'rect-6',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.rectangle,
    label: 'მართკუთხედი · 6 ადგილი',
    width: 190,
    height: 90,
    capacity: 6,
    nameSeed: 'T',
  );

  static const _rectangle8 = EditorPlacementSpec(
    id: 'rect-8',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.rectangle,
    label: 'მართკუთხედი · 8 ადგილი',
    width: 240,
    height: 100,
    capacity: 8,
    nameSeed: 'T',
  );

  static const _round2 = EditorPlacementSpec(
    id: 'round-2',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.circle,
    label: 'მრგვალი · 2 ადგილი',
    width: 84,
    height: 84,
    capacity: 2,
    nameSeed: 'T',
  );

  static const _round4 = EditorPlacementSpec(
    id: 'round-4',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.circle,
    label: 'მრგვალი · 4 ადგილი',
    width: 110,
    height: 110,
    capacity: 4,
    nameSeed: 'T',
  );

  static const _round6 = EditorPlacementSpec(
    id: 'round-6',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.circle,
    label: 'მრგვალი · 6 ადგილი',
    width: 140,
    height: 140,
    capacity: 6,
    nameSeed: 'T',
  );

  static const _communal8 = EditorPlacementSpec(
    id: 'communal-8',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.long,
    label: 'საერთო · 8 ადგილი',
    width: 300,
    height: 100,
    capacity: 8,
    nameSeed: 'T',
  );

  static const _communal12 = EditorPlacementSpec(
    id: 'communal-12',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.long,
    label: 'საერთო · 12 ადგილი',
    width: 400,
    height: 110,
    capacity: 12,
    nameSeed: 'T',
  );

  static const _booth4 = EditorPlacementSpec(
    id: 'booth-4',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.booth,
    label: 'ბოქსი · 2–4 ადგილი',
    width: 160,
    height: 110,
    capacity: 4,
    nameSeed: 'B',
  );

  static const _booth6 = EditorPlacementSpec(
    id: 'booth-6',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.booth,
    label: 'ბოქსი · 4–6 ადგილი',
    width: 210,
    height: 120,
    capacity: 6,
    nameSeed: 'B',
  );

  static const _barSeat = EditorPlacementSpec(
    id: 'bar-seat',
    type: RestaurantLayoutObjectType.table,
    tableShape: RestaurantTableShape.barSeat,
    label: 'ბარის ადგილი · 1',
    width: 64,
    height: 64,
    capacity: 1,
    nameSeed: 'Bar',
  );

  static const wall = EditorPlacementSpec(
    id: 'wall',
    type: RestaurantLayoutObjectType.wall,
    label: 'კედელი',
    width: 240,
    height: 16,
  );

  static const divider = EditorPlacementSpec(
    id: 'divider',
    type: RestaurantLayoutObjectType.divider,
    label: 'ტიხარი',
    width: 200,
    height: 10,
  );

  static const door = EditorPlacementSpec(
    id: 'door',
    type: RestaurantLayoutObjectType.entrance,
    label: 'კარი / შესასვლელი',
    width: 120,
    height: 40,
    nameSeed: 'შესასვლელი',
  );

  static const bar = EditorPlacementSpec(
    id: 'bar-counter',
    type: RestaurantLayoutObjectType.bar,
    label: 'ბარი',
    width: 300,
    height: 70,
    nameSeed: 'ბარი',
  );

  static const counter = EditorPlacementSpec(
    id: 'counter',
    type: RestaurantLayoutObjectType.counter,
    label: 'დახლი',
    width: 220,
    height: 60,
    nameSeed: 'დახლი',
  );

  static const zone = EditorPlacementSpec(
    id: 'zone',
    type: RestaurantLayoutObjectType.zone,
    label: 'ზონა / არეალი',
    width: 360,
    height: 260,
    nameSeed: 'ზონა',
  );

  static const label = EditorPlacementSpec(
    id: 'label',
    type: RestaurantLayoutObjectType.label,
    label: 'წარწერა',
    width: 150,
    height: 44,
    nameSeed: 'წარწერა',
  );

  static const stairs = EditorPlacementSpec(
    id: 'stairs',
    type: RestaurantLayoutObjectType.stairs,
    label: 'კიბე',
    width: 160,
    height: 90,
    nameSeed: 'კიბე',
  );

  static const restroom = EditorPlacementSpec(
    id: 'restroom',
    type: RestaurantLayoutObjectType.restroom,
    label: 'სველი წერტილი',
    width: 150,
    height: 90,
    nameSeed: 'სველი წერტილი',
  );

  static const stage = EditorPlacementSpec(
    id: 'stage',
    type: RestaurantLayoutObjectType.stage,
    label: 'სცენა',
    width: 260,
    height: 120,
    nameSeed: 'სცენა',
  );

  /// The palette, top to bottom. Adding an object type later means adding an
  /// entry here plus a case in the painter — nothing else.
  static const List<EditorPaletteGroup> groups = [
    EditorPaletteGroup(
      title: 'მაგიდები',
      icon: Icons.table_restaurant_outlined,
      entries: [
        EditorPaletteEntry(
          icon: Icons.crop_square,
          tooltip: 'მაგიდა',
          spec: _rectangle4,
          variants: [_square2, _square4, _rectangle4, _rectangle6, _rectangle8],
        ),
        EditorPaletteEntry(
          icon: Icons.circle_outlined,
          tooltip: 'მრგვალი მაგიდა',
          spec: _round4,
          variants: [_round2, _round4, _round6],
        ),
        EditorPaletteEntry(
          icon: Icons.weekend_outlined,
          tooltip: 'ბოქსი',
          spec: _booth4,
          variants: [_booth4, _booth6],
        ),
        EditorPaletteEntry(
          icon: Icons.table_bar_outlined,
          tooltip: 'საერთო მაგიდა',
          spec: _communal8,
          variants: [_communal8, _communal12, _barSeat],
        ),
      ],
    ),
    EditorPaletteGroup(
      title: 'კონსტრუქცია',
      icon: Icons.architecture_outlined,
      entries: [
        EditorPaletteEntry(
          icon: Icons.horizontal_rule,
          tooltip: 'კედელი — დახაზეთ გადათრევით',
          spec: wall,
        ),
        EditorPaletteEntry(
          icon: Icons.power_input,
          tooltip: 'ტიხარი — დახაზეთ გადათრევით',
          spec: divider,
        ),
        EditorPaletteEntry(
          icon: Icons.sensor_door_outlined,
          tooltip: 'კარი / შესასვლელი',
          spec: door,
        ),
      ],
    ),
    EditorPaletteGroup(
      title: 'ობიექტები',
      icon: Icons.local_bar_outlined,
      entries: [
        EditorPaletteEntry(
          icon: Icons.local_bar_outlined,
          tooltip: 'ბარი',
          spec: bar,
          variants: [bar, counter],
        ),
        EditorPaletteEntry(
          icon: Icons.stairs_outlined,
          tooltip: 'სხვა ობიექტი',
          spec: stairs,
          variants: [stairs, restroom, stage],
        ),
      ],
    ),
    EditorPaletteGroup(
      title: 'აღნიშვნა',
      icon: Icons.label_outline,
      entries: [
        EditorPaletteEntry(
          icon: Icons.crop_free,
          tooltip: 'ზონა / არეალი',
          spec: zone,
        ),
        EditorPaletteEntry(
          icon: Icons.text_fields,
          tooltip: 'წარწერა',
          spec: label,
        ),
      ],
    ),
  ];

  /// Shape options offered in the inspector for an already-placed table.
  static const List<(RestaurantTableShape, String, IconData)> tableShapes = [
    (RestaurantTableShape.rectangle, 'მართკუთხედი', Icons.crop_landscape),
    (RestaurantTableShape.square, 'კვადრატი', Icons.crop_square),
    (RestaurantTableShape.circle, 'მრგვალი', Icons.circle_outlined),
    (RestaurantTableShape.long, 'საერთო', Icons.table_bar_outlined),
    (RestaurantTableShape.booth, 'ბოქსი', Icons.weekend_outlined),
    (RestaurantTableShape.barSeat, 'ბარის ადგილი', Icons.chair_outlined),
  ];

  /// Smallest allowed size per object type, in canvas units.
  static Size minimumSize(RestaurantLayoutObjectType type) {
    switch (type) {
      case RestaurantLayoutObjectType.wall:
        return const Size(24, 6);
      case RestaurantLayoutObjectType.divider:
        return const Size(24, 4);
      case RestaurantLayoutObjectType.zone:
        return const Size(80, 80);
      case RestaurantLayoutObjectType.label:
        return const Size(60, 28);
      case RestaurantLayoutObjectType.table:
      case RestaurantLayoutObjectType.entrance:
      case RestaurantLayoutObjectType.stairs:
      case RestaurantLayoutObjectType.stage:
      case RestaurantLayoutObjectType.bar:
      case RestaurantLayoutObjectType.counter:
      case RestaurantLayoutObjectType.restroom:
        return const Size(40, 32);
    }
  }

  static String typeLabel(RestaurantLayoutObjectType type) {
    switch (type) {
      case RestaurantLayoutObjectType.table:
        return 'მაგიდა';
      case RestaurantLayoutObjectType.wall:
        return 'კედელი';
      case RestaurantLayoutObjectType.divider:
        return 'ტიხარი';
      case RestaurantLayoutObjectType.entrance:
        return 'შესასვლელი';
      case RestaurantLayoutObjectType.stairs:
        return 'კიბე';
      case RestaurantLayoutObjectType.stage:
        return 'სცენა';
      case RestaurantLayoutObjectType.bar:
        return 'ბარი';
      case RestaurantLayoutObjectType.counter:
        return 'დახლი';
      case RestaurantLayoutObjectType.restroom:
        return 'სველი წერტილი';
      case RestaurantLayoutObjectType.label:
        return 'წარწერა';
      case RestaurantLayoutObjectType.zone:
        return 'ზონა';
    }
  }

  static String shapeLabel(RestaurantTableShape shape) {
    switch (shape) {
      case RestaurantTableShape.rectangle:
        return 'მართკუთხედი';
      case RestaurantTableShape.rounded:
        return 'მომრგვალებული';
      case RestaurantTableShape.square:
        return 'კვადრატი';
      case RestaurantTableShape.circle:
        return 'მრგვალი';
      case RestaurantTableShape.long:
        return 'საერთო';
      case RestaurantTableShape.booth:
        return 'ბოქსი';
      case RestaurantTableShape.barSeat:
        return 'ბარის ადგილი';
    }
  }

  static IconData typeIcon(RestaurantLayoutObjectType type) {
    switch (type) {
      case RestaurantLayoutObjectType.table:
        return Icons.table_restaurant_outlined;
      case RestaurantLayoutObjectType.wall:
        return Icons.horizontal_rule;
      case RestaurantLayoutObjectType.divider:
        return Icons.power_input;
      case RestaurantLayoutObjectType.entrance:
        return Icons.sensor_door_outlined;
      case RestaurantLayoutObjectType.stairs:
        return Icons.stairs_outlined;
      case RestaurantLayoutObjectType.stage:
        return Icons.theaters_outlined;
      case RestaurantLayoutObjectType.bar:
        return Icons.local_bar_outlined;
      case RestaurantLayoutObjectType.counter:
        return Icons.storefront_outlined;
      case RestaurantLayoutObjectType.restroom:
        return Icons.wc_outlined;
      case RestaurantLayoutObjectType.label:
        return Icons.text_fields;
      case RestaurantLayoutObjectType.zone:
        return Icons.crop_free;
    }
  }
}
