enum TableLayoutRenderMode { svgMap, buttonGrid, floorPlan }

enum RestaurantLayoutObjectType {
  table,
  wall,
  entrance,
  stairs,
  stage,
  bar,
  counter,
  label,
  restroom,

  /// Half-height partition: drawn as a segment like [wall], but visually
  /// lighter and non-structural.
  divider,

  /// Named background region (Main hall, Terrace, VIP...). Drawn behind
  /// tables and never intercepts taps.
  zone,
}

enum RestaurantTableShape {
  rectangle,
  rounded,
  square,
  circle,
  long,
  booth,
  barSeat,
}

class RestaurantTableLayout {
  final String id;
  final String name;
  final List<RestaurantZone> zones;
  final List<RestaurantTableDefinition> tables;
  final List<RestaurantLayoutObject> objects;

  const RestaurantTableLayout({
    required this.id,
    this.name = 'Default layout',
    required this.zones,
    required this.tables,
    this.objects = const [],
  });

  factory RestaurantTableLayout.fromJson(Map<String, dynamic> json) {
    return RestaurantTableLayout(
      id: _stringValue(json['id'], fallback: 'custom-layout'),
      name: _stringValue(json['name'], fallback: 'Custom layout'),
      zones: _listValue(
        json['zones'],
      ).map((entry) => RestaurantZone.fromJson(_mapValue(entry))).toList(),
      tables: _listValue(json['tables'])
          .map((entry) => RestaurantTableDefinition.fromJson(_mapValue(entry)))
          .toList(),
      objects: _listValue(json['objects'])
          .map((entry) => RestaurantLayoutObject.fromJson(_mapValue(entry)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'zones': zones.map((zone) => zone.toJson()).toList(),
      'tables': tables.map((table) => table.toJson()).toList(),
      'objects': objects.map((object) => object.toJson()).toList(),
    };
  }

  RestaurantZone? zoneForLegacyFloor(String floor) {
    for (final zone in zones) {
      if (zone.legacyFloor == floor) {
        return zone;
      }
    }
    return null;
  }

  RestaurantZone? zoneForDisplayOrder(int displayOrder) {
    for (final zone in zones) {
      if (zone.displayOrder == displayOrder) {
        return zone;
      }
    }
    return null;
  }

  RestaurantTableDefinition? tableForId(String id) {
    for (final table in tables) {
      if (table.id == id) {
        return table;
      }
    }
    return null;
  }

  RestaurantTableDefinition? tableForLegacy({
    required String floor,
    required String tableNumber,
  }) {
    for (final table in tables) {
      if (table.legacyFloor == floor &&
          table.legacyTableNumber == tableNumber) {
        return table;
      }
    }
    return null;
  }

  List<RestaurantTableDefinition> tablesForZone(String zoneId) {
    final zoneTables = tables.where((table) => table.zoneId == zoneId).toList();
    zoneTables.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return zoneTables;
  }

  List<RestaurantLayoutObject> objectsForZone(String zoneId) {
    final zoneObjects = objects
        .where((object) => object.zoneId == zoneId)
        .toList();
    zoneObjects.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return zoneObjects;
  }

  RestaurantLayoutObject? objectForTable(String tableId) {
    for (final object in objects) {
      if (object.type == RestaurantLayoutObjectType.table &&
          object.tableId == tableId) {
        return object;
      }
    }
    return null;
  }

  List<RestaurantTableDefinition> tablesForLegacyFloor(String floor) {
    final zone = zoneForLegacyFloor(floor);
    if (zone == null) {
      return const [];
    }
    return tablesForZone(zone.id);
  }

  Map<String, List<String>> legacyTableLayout() {
    return {
      for (final zone in zones)
        zone.legacyFloor: tablesForZone(
          zone.id,
        ).map((table) => table.legacyTableNumber).toList(),
    };
  }
}

class RestaurantLayoutObject {
  final String id;
  final String zoneId;
  final RestaurantLayoutObjectType type;
  final String label;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final int sortOrder;
  final String? tableId;
  final RestaurantTableShape tableShape;
  final String? colorHex;

  const RestaurantLayoutObject({
    required this.id,
    required this.zoneId,
    required this.type,
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.sortOrder = 0,
    this.tableId,
    this.tableShape = RestaurantTableShape.rectangle,
    this.colorHex,
  });

  factory RestaurantLayoutObject.fromJson(Map<String, dynamic> json) {
    return RestaurantLayoutObject(
      id: _stringValue(json['id'], fallback: 'layout-object'),
      zoneId: _stringValue(json['zoneId'], fallback: 'zone'),
      type: _objectTypeFromJson(json['type']),
      label: _stringValue(json['label'], fallback: 'Object'),
      x: _doubleValue(json['x']) ?? 0,
      y: _doubleValue(json['y']) ?? 0,
      width: _doubleValue(json['width']) ?? 100,
      height: _doubleValue(json['height']) ?? 80,
      rotation: _doubleValue(json['rotation']) ?? 0,
      sortOrder: _intValue(json['sortOrder'], fallback: 0),
      tableId: _nullableStringValue(json['tableId']),
      tableShape: _tableShapeFromJson(json['tableShape']),
      colorHex: _nullableStringValue(json['colorHex']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'zoneId': zoneId,
      'type': type.name,
      'label': label,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'sortOrder': sortOrder,
      if (tableId != null) 'tableId': tableId,
      'tableShape': tableShape.name,
      if (colorHex != null) 'colorHex': colorHex,
    };
  }
}

class RestaurantZone {
  final String id;
  final String name;
  final String legacyFloor;
  final int displayOrder;
  final TableLayoutRenderMode renderMode;
  final String? svgAsset;
  final double? canvasWidth;
  final double? canvasHeight;

  const RestaurantZone({
    required this.id,
    required this.name,
    required this.legacyFloor,
    required this.displayOrder,
    required this.renderMode,
    this.svgAsset,
    this.canvasWidth,
    this.canvasHeight,
  });

  factory RestaurantZone.fromJson(Map<String, dynamic> json) {
    return RestaurantZone(
      id: _stringValue(json['id'], fallback: 'zone'),
      name: _stringValue(json['name'], fallback: 'Zone'),
      legacyFloor: _stringValue(json['legacyFloor'], fallback: 'first'),
      displayOrder: _intValue(json['displayOrder'], fallback: 1),
      renderMode: _renderModeFromJson(json['renderMode']),
      svgAsset: _nullableStringValue(json['svgAsset']),
      canvasWidth: _doubleValue(json['canvasWidth']),
      canvasHeight: _doubleValue(json['canvasHeight']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'legacyFloor': legacyFloor,
      'displayOrder': displayOrder,
      'renderMode': renderMode.name,
      if (svgAsset != null) 'svgAsset': svgAsset,
      if (canvasWidth != null) 'canvasWidth': canvasWidth,
      if (canvasHeight != null) 'canvasHeight': canvasHeight,
    };
  }
}

class RestaurantTableDefinition {
  final String id;
  final String zoneId;
  final String legacyFloor;
  final String legacyTableNumber;
  final String label;
  final int capacity;
  final int sortOrder;
  final String? svgElementId;
  final TableHitBox? hitBox;

  const RestaurantTableDefinition({
    required this.id,
    required this.zoneId,
    required this.legacyFloor,
    required this.legacyTableNumber,
    required this.label,
    required this.capacity,
    required this.sortOrder,
    this.svgElementId,
    this.hitBox,
  });

  factory RestaurantTableDefinition.fromJson(Map<String, dynamic> json) {
    final hitBoxJson = json['hitBox'];
    return RestaurantTableDefinition(
      id: _stringValue(json['id'], fallback: 'table'),
      zoneId: _stringValue(json['zoneId'], fallback: 'zone'),
      legacyFloor: _stringValue(json['legacyFloor'], fallback: 'first'),
      legacyTableNumber: _stringValue(json['legacyTableNumber'], fallback: '1'),
      label: _stringValue(json['label'], fallback: 'Table'),
      capacity: _intValue(json['capacity'], fallback: 0),
      sortOrder: _intValue(json['sortOrder'], fallback: 0),
      svgElementId: _nullableStringValue(json['svgElementId']),
      hitBox: hitBoxJson is Map
          ? TableHitBox.fromJson(_mapValue(hitBoxJson))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'zoneId': zoneId,
      'legacyFloor': legacyFloor,
      'legacyTableNumber': legacyTableNumber,
      'label': label,
      'capacity': capacity,
      'sortOrder': sortOrder,
      if (svgElementId != null) 'svgElementId': svgElementId,
      if (hitBox != null) 'hitBox': hitBox!.toJson(),
    };
  }
}

class TableHitBox {
  final double left;
  final double top;
  final double width;
  final double height;

  const TableHitBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory TableHitBox.fromJson(Map<String, dynamic> json) {
    return TableHitBox(
      left: _doubleValue(json['left']) ?? 0,
      top: _doubleValue(json['top']) ?? 0,
      width: _doubleValue(json['width']) ?? 0,
      height: _doubleValue(json['height']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'left': left, 'top': top, 'width': width, 'height': height};
  }
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<Object?> _listValue(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

String _stringValue(Object? value, {required String fallback}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String? _nullableStringValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _intValue(Object? value, {required int fallback}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double? _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

TableLayoutRenderMode _renderModeFromJson(Object? value) {
  final name = value?.toString();
  for (final mode in TableLayoutRenderMode.values) {
    if (mode.name == name) {
      return mode;
    }
  }
  return TableLayoutRenderMode.buttonGrid;
}

RestaurantLayoutObjectType _objectTypeFromJson(Object? value) {
  final name = value?.toString();
  for (final type in RestaurantLayoutObjectType.values) {
    if (type.name == name) {
      return type;
    }
  }
  return RestaurantLayoutObjectType.label;
}

RestaurantTableShape _tableShapeFromJson(Object? value) {
  final name = value?.toString();
  for (final shape in RestaurantTableShape.values) {
    if (shape.name == name) {
      return shape;
    }
  }
  return RestaurantTableShape.rectangle;
}

class RestaurantTableLayouts {
  RestaurantTableLayouts._();

  static final current = floorPlanPreview;

  static final available = <RestaurantTableLayout>[
    floorPlanPreview,
    svgMap,
    buttonGridPreview,
  ];

  static const svgMap = RestaurantTableLayout(
    id: 'default-vynic-restaurant',
    name: 'SVG floor map',
    zones: [
      RestaurantZone(
        id: 'main-floor',
        name: 'First floor',
        legacyFloor: 'first',
        displayOrder: 1,
        renderMode: TableLayoutRenderMode.svgMap,
        svgAsset: 'assets/new-floor1.svg',
        canvasWidth: 1005,
        canvasHeight: 1101,
      ),
      RestaurantZone(
        id: 'vip-floor',
        name: 'Second floor',
        legacyFloor: 'second',
        displayOrder: 2,
        renderMode: TableLayoutRenderMode.svgMap,
        svgAsset: 'assets/new-floor2.svg',
        canvasWidth: 953,
        canvasHeight: 958,
      ),
    ],
    tables: [
      RestaurantTableDefinition(
        id: 'floor1-table1',
        zoneId: 'main-floor',
        legacyFloor: 'first',
        legacyTableNumber: '1',
        label: 'Table 1',
        capacity: 0,
        sortOrder: 1,
        svgElementId: 'table1',
        hitBox: TableHitBox(
          left: 64.5,
          top: 260.65,
          width: 101.29,
          height: 161.76,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor1-table2',
        zoneId: 'main-floor',
        legacyFloor: 'first',
        legacyTableNumber: '2',
        label: 'Table 2',
        capacity: 0,
        sortOrder: 2,
        svgElementId: 'table2',
        hitBox: TableHitBox(
          left: 266.5,
          top: 178.65,
          width: 101.29,
          height: 161.76,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor1-table3',
        zoneId: 'main-floor',
        legacyFloor: 'first',
        legacyTableNumber: '3',
        label: 'Table 3',
        capacity: 0,
        sortOrder: 3,
        svgElementId: 'table3',
        hitBox: TableHitBox(
          left: 484.5,
          top: 178.65,
          width: 101.29,
          height: 161.76,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor1-table4',
        zoneId: 'main-floor',
        legacyFloor: 'first',
        legacyTableNumber: '4',
        label: 'Table 4',
        capacity: 0,
        sortOrder: 4,
        svgElementId: 'table4',
        hitBox: TableHitBox(
          left: 699.5,
          top: 178.65,
          width: 101.29,
          height: 161.76,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor1-table5',
        zoneId: 'main-floor',
        legacyFloor: 'first',
        legacyTableNumber: '5',
        label: 'Table 5',
        capacity: 0,
        sortOrder: 5,
        svgElementId: 'table5',
        hitBox: TableHitBox(
          left: 57.5,
          top: 737.65,
          width: 161.77,
          height: 101.29,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor1-table6',
        zoneId: 'main-floor',
        legacyFloor: 'first',
        legacyTableNumber: '6',
        label: 'Table 6',
        capacity: 0,
        sortOrder: 6,
        svgElementId: 'table6',
        hitBox: TableHitBox(
          left: 60.5,
          top: 917.89,
          width: 161.77,
          height: 101.29,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor1-table7',
        zoneId: 'main-floor',
        legacyFloor: 'first',
        legacyTableNumber: '7',
        label: 'Table 7',
        capacity: 0,
        sortOrder: 7,
        svgElementId: 'table7',
        hitBox: TableHitBox(
          left: 351.5,
          top: 887.65,
          width: 101.29,
          height: 161.77,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor1-table8',
        zoneId: 'main-floor',
        legacyFloor: 'first',
        legacyTableNumber: '8',
        label: 'Table 8',
        capacity: 0,
        sortOrder: 8,
        svgElementId: 'table8',
        hitBox: TableHitBox(
          left: 583.5,
          top: 887.87,
          width: 101.29,
          height: 161.76,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor1-table9',
        zoneId: 'main-floor',
        legacyFloor: 'first',
        legacyTableNumber: '9',
        label: 'Table 9',
        capacity: 0,
        sortOrder: 9,
        svgElementId: 'table9',
        hitBox: TableHitBox(
          left: 793.5,
          top: 887.87,
          width: 101.29,
          height: 161.76,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor2-table1',
        zoneId: 'vip-floor',
        legacyFloor: 'second',
        legacyTableNumber: '1',
        label: 'VIP Zone 1',
        capacity: 0,
        sortOrder: 1,
        svgElementId: 'table1',
        hitBox: TableHitBox(
          left: 45.23,
          top: 719.11,
          width: 101.29,
          height: 161.11,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor2-table2',
        zoneId: 'vip-floor',
        legacyFloor: 'second',
        legacyTableNumber: '2',
        label: 'VIP Zone 2',
        capacity: 0,
        sortOrder: 2,
        svgElementId: 'table2',
        hitBox: TableHitBox(
          left: 245.23,
          top: 719.11,
          width: 101.29,
          height: 161.11,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor2-table3',
        zoneId: 'vip-floor',
        legacyFloor: 'second',
        legacyTableNumber: '3',
        label: 'VIP Zone 3',
        capacity: 0,
        sortOrder: 3,
        svgElementId: 'table3',
        hitBox: TableHitBox(
          left: 445.23,
          top: 719.11,
          width: 101.29,
          height: 161.11,
        ),
      ),
      RestaurantTableDefinition(
        id: 'floor2-table4',
        zoneId: 'vip-floor',
        legacyFloor: 'second',
        legacyTableNumber: '4',
        label: 'VIP Zone 4',
        capacity: 0,
        sortOrder: 4,
        svgElementId: 'table4',
        hitBox: TableHitBox(
          left: 644.23,
          top: 721.11,
          width: 101.29,
          height: 161.11,
        ),
      ),
    ],
  );

  static final buttonGridPreview = RestaurantTableLayout(
    id: 'button-grid-preview',
    name: 'Button grid preview',
    zones: const [
      RestaurantZone(
        id: 'main-floor',
        name: 'First floor',
        legacyFloor: 'first',
        displayOrder: 1,
        renderMode: TableLayoutRenderMode.buttonGrid,
      ),
      RestaurantZone(
        id: 'vip-floor',
        name: 'Second floor',
        legacyFloor: 'second',
        displayOrder: 2,
        renderMode: TableLayoutRenderMode.buttonGrid,
      ),
    ],
    tables: svgMap.tables,
  );

  static final floorPlanPreview = RestaurantTableLayout(
    id: 'floor-plan-preview',
    name: 'Visual floor plan preview',
    zones: const [
      RestaurantZone(
        id: 'main-floor',
        name: 'First floor',
        legacyFloor: 'first',
        displayOrder: 1,
        renderMode: TableLayoutRenderMode.floorPlan,
        canvasWidth: 1005,
        canvasHeight: 1101,
      ),
      RestaurantZone(
        id: 'vip-floor',
        name: 'Second floor',
        legacyFloor: 'second',
        displayOrder: 2,
        renderMode: TableLayoutRenderMode.floorPlan,
        canvasWidth: 953,
        canvasHeight: 958,
      ),
    ],
    tables: svgMap.tables,
    objects: [
      ..._objectsFromTables(svgMap.tablesForZone('main-floor'), 'main-floor'),
      ..._objectsFromTables(svgMap.tablesForZone('vip-floor'), 'vip-floor'),
      const RestaurantLayoutObject(
        id: 'main-floor-entrance',
        zoneId: 'main-floor',
        type: RestaurantLayoutObjectType.entrance,
        label: 'Entrance',
        x: 392,
        y: 20,
        width: 220,
        height: 42,
        sortOrder: 200,
      ),
      const RestaurantLayoutObject(
        id: 'main-floor-bar',
        zoneId: 'main-floor',
        type: RestaurantLayoutObjectType.bar,
        label: 'Bar',
        x: 20,
        y: 560,
        width: 180,
        height: 52,
        sortOrder: 201,
      ),
      const RestaurantLayoutObject(
        id: 'vip-floor-stage',
        zoneId: 'vip-floor',
        type: RestaurantLayoutObjectType.stage,
        label: 'Stage',
        x: 330,
        y: 80,
        width: 280,
        height: 72,
        sortOrder: 200,
      ),
      const RestaurantLayoutObject(
        id: 'vip-floor-stairs',
        zoneId: 'vip-floor',
        type: RestaurantLayoutObjectType.stairs,
        label: 'Stairs',
        x: 50,
        y: 80,
        width: 150,
        height: 56,
        sortOrder: 201,
      ),
    ],
  );

  static List<RestaurantLayoutObject> _objectsFromTables(
    List<RestaurantTableDefinition> tables,
    String zoneId,
  ) {
    return [
      for (final table in tables)
        RestaurantLayoutObject(
          id: '${table.id}-visual',
          zoneId: zoneId,
          type: RestaurantLayoutObjectType.table,
          label: table.label,
          x: table.hitBox?.left ?? (80 + table.sortOrder * 24),
          y: table.hitBox?.top ?? (80 + table.sortOrder * 24),
          width: table.hitBox?.width ?? 120,
          height: table.hitBox?.height ?? 90,
          sortOrder: table.sortOrder,
          tableId: table.id,
          tableShape: table.sortOrder.isEven
              ? RestaurantTableShape.rectangle
              : RestaurantTableShape.circle,
        ),
    ];
  }
}
