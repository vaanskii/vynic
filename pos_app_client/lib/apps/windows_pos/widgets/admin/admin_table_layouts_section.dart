import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

const double _planCanvasWidth = 1000;
const double _planCanvasHeight = 620;

class AdminTableLayoutsSection extends StatefulWidget {
  const AdminTableLayoutsSection({super.key});

  @override
  State<AdminTableLayoutsSection> createState() =>
      _AdminTableLayoutsSectionState();
}

class _AdminTableLayoutsSectionState extends State<AdminTableLayoutsSection> {
  late final TextEditingController _layoutNameController;
  late final TextEditingController _firstZoneController;
  late final TextEditingController _secondZoneController;
  final List<_EditableTableDefinition> _firstFloorTables = [];
  final List<_EditableTableDefinition> _secondFloorTables = [];
  final List<_EditablePlanObject> _firstFloorObjects = [];
  final List<_EditablePlanObject> _secondFloorObjects = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _layoutNameController = TextEditingController();
    _firstZoneController = TextEditingController();
    _secondZoneController = TextEditingController();
    _loadDraft(DatabaseService.getRestaurantTableLayout());
  }

  @override
  void dispose() {
    _layoutNameController.dispose();
    _firstZoneController.dispose();
    _secondZoneController.dispose();
    for (final table in [..._firstFloorTables, ..._secondFloorTables]) {
      table.dispose();
    }
    super.dispose();
  }

  void _loadDraft(RestaurantTableLayout layout) {
    for (final table in [..._firstFloorTables, ..._secondFloorTables]) {
      table.dispose();
    }
    _firstFloorTables.clear();
    _secondFloorTables.clear();
    _firstFloorObjects.clear();
    _secondFloorObjects.clear();

    final firstZone = layout.zoneForLegacyFloor('first');
    final secondZone = layout.zoneForLegacyFloor('second');
    final firstZoneId = firstZone?.id ?? 'main-floor';
    final secondZoneId = secondZone?.id ?? 'vip-floor';

    _layoutNameController.text = layout.name;
    _firstZoneController.text = firstZone?.name ?? 'First floor';
    _secondZoneController.text = secondZone?.name ?? 'Second floor';

    _firstFloorTables.addAll(_editableTablesFor(layout, firstZoneId, 'first'));
    _secondFloorTables.addAll(
      _editableTablesFor(layout, secondZoneId, 'second'),
    );
    _firstFloorObjects.addAll(_editableObjectsFor(layout, firstZoneId));
    _secondFloorObjects.addAll(_editableObjectsFor(layout, secondZoneId));

    if (_firstFloorTables.isEmpty) {
      _firstFloorTables.add(_EditableTableDefinition.create('first', 1));
    }
    if (_secondFloorTables.isEmpty) {
      _secondFloorTables.add(_EditableTableDefinition.create('second', 1));
    }
  }

  List<_EditableTableDefinition> _editableTablesFor(
    RestaurantTableLayout layout,
    String zoneId,
    String floor,
  ) {
    final tables = layout.tablesForLegacyFloor(floor);
    return [
      for (var i = 0; i < tables.length; i++)
        _EditableTableDefinition.fromLayout(
          tables[i],
          layout.objectForTable(tables[i].id),
          i,
        ),
    ];
  }

  List<_EditablePlanObject> _editableObjectsFor(
    RestaurantTableLayout layout,
    String zoneId,
  ) {
    return [
      for (final object in layout.objectsForZone(zoneId))
        if (object.type != RestaurantLayoutObjectType.table)
          _EditablePlanObject.fromLayout(object),
    ];
  }

  Future<void> _saveLayout() async {
    if (_isSaving) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final layout = _buildLayout();
      await DatabaseService.saveActiveRestaurantTableLayout(layout);
      if (!mounted) {
        return;
      }
      unawaited(
        showPosToast(
          context: context,
          message: 'მაგიდების გეგმა შენახულია',
          style: PosToastStyle.success,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _resetToDefault() async {
    await DatabaseService.clearActiveRestaurantTableLayout();
    if (!mounted) {
      return;
    }
    setState(() {
      _loadDraft(RestaurantTableLayouts.floorPlanPreview);
    });
    unawaited(
      showPosToast(
        context: context,
        message: 'დაბრუნდა საწყისი ვიზუალური გეგმა',
        style: PosToastStyle.info,
      ),
    );
  }

  RestaurantTableLayout _buildLayout() {
    final layoutName = _layoutNameController.text.trim();
    const mainZoneId = 'main-floor';
    const vipZoneId = 'vip-floor';
    return RestaurantTableLayout(
      id: 'custom-floor-plan-layout',
      name: layoutName.isEmpty ? 'Custom floor plan' : layoutName,
      zones: [
        RestaurantZone(
          id: mainZoneId,
          name: _zoneName(_firstZoneController.text, 'First floor'),
          legacyFloor: 'first',
          displayOrder: 1,
          renderMode: TableLayoutRenderMode.floorPlan,
          canvasWidth: _planCanvasWidth,
          canvasHeight: _planCanvasHeight,
        ),
        RestaurantZone(
          id: vipZoneId,
          name: _zoneName(_secondZoneController.text, 'Second floor'),
          legacyFloor: 'second',
          displayOrder: 2,
          renderMode: TableLayoutRenderMode.floorPlan,
          canvasWidth: _planCanvasWidth,
          canvasHeight: _planCanvasHeight,
        ),
      ],
      tables: [
        ..._buildTables(_firstFloorTables, mainZoneId, 'first'),
        ..._buildTables(_secondFloorTables, vipZoneId, 'second'),
      ],
      objects: [
        ..._buildObjects(
          _firstFloorTables,
          _firstFloorObjects,
          mainZoneId,
          'first',
        ),
        ..._buildObjects(
          _secondFloorTables,
          _secondFloorObjects,
          vipZoneId,
          'second',
        ),
      ],
    );
  }

  String _zoneName(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  List<RestaurantTableDefinition> _buildTables(
    List<_EditableTableDefinition> draft,
    String zoneId,
    String legacyFloor,
  ) {
    return [
      for (var i = 0; i < draft.length; i++)
        RestaurantTableDefinition(
          id: _tableIdFor(legacyFloor, i),
          zoneId: zoneId,
          legacyFloor: legacyFloor,
          legacyTableNumber: '${i + 1}',
          label: draft[i].label,
          capacity: draft[i].capacity,
          sortOrder: i + 1,
        ),
    ];
  }

  List<RestaurantLayoutObject> _buildObjects(
    List<_EditableTableDefinition> tables,
    List<_EditablePlanObject> objects,
    String zoneId,
    String legacyFloor,
  ) {
    return [
      for (var i = 0; i < tables.length; i++)
        RestaurantLayoutObject(
          id: '${_tableIdFor(legacyFloor, i)}-visual',
          zoneId: zoneId,
          type: RestaurantLayoutObjectType.table,
          label: tables[i].label,
          x: tables[i].x,
          y: tables[i].y,
          width: tables[i].width,
          height: tables[i].height,
          rotation: tables[i].rotation,
          sortOrder: i + 1,
          tableId: _tableIdFor(legacyFloor, i),
          tableShape: tables[i].shape,
        ),
      for (var i = 0; i < objects.length; i++)
        RestaurantLayoutObject(
          id: objects[i].id,
          zoneId: zoneId,
          type: objects[i].type,
          label: objects[i].label,
          x: objects[i].x,
          y: objects[i].y,
          width: objects[i].width,
          height: objects[i].height,
          rotation: objects[i].rotation,
          sortOrder: 1000 + i,
          colorHex: objects[i].colorHex,
        ),
    ];
  }

  String _tableIdFor(String floor, int index) {
    return floor == 'second'
        ? 'floor2-table${index + 1}'
        : 'floor1-table${index + 1}';
  }

  void _addTable(List<_EditableTableDefinition> tables, String floor) {
    setState(() {
      tables.add(_EditableTableDefinition.create(floor, tables.length + 1));
    });
  }

  void _removeLastTable(List<_EditableTableDefinition> tables, String floor) {
    if (tables.length <= 1) {
      return;
    }
    final lastTableNumber = tables.length.toString();
    final liveTable = DatabaseService.getTable(lastTableNumber, floor);
    if (liveTable?.isReserved == true) {
      unawaited(
        showPosToast(
          context: context,
          message: 'დაკავებული მაგიდის წაშლა ჯერ არ შეიძლება',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    setState(() {
      tables.removeLast().dispose();
    });
  }

  void _addPlanObject(
    List<_EditablePlanObject> objects,
    RestaurantLayoutObjectType type,
  ) {
    setState(() {
      objects.add(_EditablePlanObject.create(type, objects.length + 1));
    });
  }

  void _removePlanObject(List<_EditablePlanObject> objects, String id) {
    setState(() {
      objects.removeWhere((object) => object.id == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(
            icon: Icons.map_outlined,
            title: 'მაგიდების განლაგება',
            subtitle: 'შექმენით რეალური დარბაზის გეგმა POS-ისთვის.',
            badge: AdminStatusBadge(
              icon: Icons.drag_indicator,
              label: 'Floor plan',
            ),
            action: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _resetToDefault,
                  style: AdminDesign.outlineButtonStyle(),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('საწყისი'),
                ),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveLayout,
                  style: AdminDesign.primaryButtonStyle(),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_isSaving ? 'ინახება...' : 'შენახვა'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AdminPanel(
            child: TextField(
              controller: _layoutNameController,
              decoration: const InputDecoration(
                labelText: 'განლაგების სახელი',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildZoneEditor(
            title: 'პირველი ზონა',
            zoneController: _firstZoneController,
            tables: _firstFloorTables,
            objects: _firstFloorObjects,
            floor: 'first',
          ),
          const SizedBox(height: 16),
          _buildZoneEditor(
            title: 'მეორე ზონა',
            zoneController: _secondZoneController,
            tables: _secondFloorTables,
            objects: _secondFloorObjects,
            floor: 'second',
          ),
        ],
      ),
    );
  }

  Widget _buildZoneEditor({
    required String title,
    required TextEditingController zoneController,
    required List<_EditableTableDefinition> tables,
    required List<_EditablePlanObject> objects,
    required String floor,
  }) {
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final controls = Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _removeLastTable(tables, floor),
                    style: AdminDesign.outlineButtonStyle(
                      foreground: AdminDesign.danger,
                    ),
                    icon: const Icon(Icons.remove, size: 18),
                    label: const Text('ბოლო მაგიდის წაშლა'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _addTable(tables, floor),
                    style: AdminDesign.primaryButtonStyle(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('მაგიდის დამატება'),
                  ),
                  _buildAddObjectButton(objects),
                ],
              );

              final header = Text(
                title,
                style: const TextStyle(
                  color: AdminDesign.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, const SizedBox(height: 12), controls],
                );
              }

              return Row(
                children: [
                  Expanded(child: header),
                  controls,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: zoneController,
            decoration: const InputDecoration(
              labelText: 'ზონის სახელი',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _buildPlanCanvas(tables: tables, objects: objects),
          const SizedBox(height: 16),
          ...tables.map((table) => _buildTableRow(table)),
          if (objects.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'ობიექტები',
              style: TextStyle(
                color: AdminDesign.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...objects.map(
              (object) => _buildObjectRow(
                object,
                onRemove: () => _removePlanObject(objects, object.id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddObjectButton(List<_EditablePlanObject> objects) {
    return PopupMenuButton<RestaurantLayoutObjectType>(
      tooltip: 'ობიექტის დამატება',
      onSelected: (type) => _addPlanObject(objects, type),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: RestaurantLayoutObjectType.wall,
          child: Text('კედელი'),
        ),
        PopupMenuItem(
          value: RestaurantLayoutObjectType.entrance,
          child: Text('შესასვლელი'),
        ),
        PopupMenuItem(
          value: RestaurantLayoutObjectType.stairs,
          child: Text('კიბე'),
        ),
        PopupMenuItem(
          value: RestaurantLayoutObjectType.stage,
          child: Text('სცენა'),
        ),
        PopupMenuItem(
          value: RestaurantLayoutObjectType.bar,
          child: Text('ბარი'),
        ),
        PopupMenuItem(
          value: RestaurantLayoutObjectType.label,
          child: Text('წარწერა'),
        ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        style: AdminDesign.outlineButtonStyle(),
        icon: const Icon(Icons.add_box_outlined, size: 18),
        label: const Text('ობიექტი'),
      ),
    );
  }

  Widget _buildPlanCanvas({
    required List<_EditableTableDefinition> tables,
    required List<_EditablePlanObject> objects,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / _planCanvasWidth;
        final canvasHeight = _planCanvasHeight * scale;
        return ClipRRect(
          borderRadius: BorderRadius.circular(AdminDesign.radius),
          child: Container(
            height: canvasHeight,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: AdminDesign.border),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _PlanGridPainter()),
                ),
                for (final object in objects)
                  _buildEditableObjectOnCanvas(object, scale),
                for (final table in tables)
                  _buildEditableTableOnCanvas(table, scale),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableTableOnCanvas(
    _EditableTableDefinition table,
    double scale,
  ) {
    return Positioned(
      left: table.x * scale,
      top: table.y * scale,
      width: table.width * scale,
      height: table.height * scale,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            table.moveBy(details.delta.dx / scale, details.delta.dy / scale);
          });
        },
        child: Transform.rotate(
          angle: table.rotation * math.pi / 180,
          child: DecoratedBox(
            decoration: _tableDecoration(
              shape: table.shape,
              color: const Color(0xFFE0F2FE),
              borderColor: const Color(0xFF0369A1),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  table.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditableObjectOnCanvas(
    _EditablePlanObject object,
    double scale,
  ) {
    final colors = _objectColors(object.type);
    return Positioned(
      left: object.x * scale,
      top: object.y * scale,
      width: object.width * scale,
      height: object.height * scale,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            object.moveBy(details.delta.dx / scale, details.delta.dy / scale);
          });
        },
        child: Transform.rotate(
          angle: object.rotation * math.pi / 180,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.$1,
              borderRadius: BorderRadius.circular(
                object.type == RestaurantLayoutObjectType.wall ? 2 : 8,
              ),
              border: Border.all(color: colors.$2, width: 1.5),
            ),
            child: Stack(
              children: [
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _objectIcon(object.type),
                        color: colors.$3,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          object.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.$3,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: InkWell(
                    onTap: () => _removePlanObject(
                      _firstFloorObjects.contains(object)
                          ? _firstFloorObjects
                          : _secondFloorObjects,
                      object.id,
                    ),
                    child: const Icon(Icons.close, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _tableDecoration({
    required RestaurantTableShape shape,
    required Color color,
    required Color borderColor,
  }) {
    return BoxDecoration(
      color: color,
      border: Border.all(color: borderColor, width: 2),
      borderRadius: BorderRadius.circular(
        shape == RestaurantTableShape.circle ? 999 : 8,
      ),
      boxShadow: [
        BoxShadow(
          color: borderColor.withValues(alpha: 0.14),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildTableRow(_EditableTableDefinition table) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final fields = [
            SizedBox(
              width: compact ? double.infinity : 42,
              child: Text(
                '#${table.sortOrder}',
                style: const TextStyle(
                  color: AdminDesign.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: TextField(
                controller: table.labelController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'მაგიდის სახელი',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: table.capacityController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'ადგილი',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: compact ? double.infinity : 170,
              child: DropdownButtonFormField<RestaurantTableShape>(
                initialValue: table.shape,
                decoration: const InputDecoration(
                  labelText: 'ფორმა',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: RestaurantTableShape.rectangle,
                    child: Text('მართკუთხა'),
                  ),
                  DropdownMenuItem(
                    value: RestaurantTableShape.circle,
                    child: Text('მრგვალი'),
                  ),
                  DropdownMenuItem(
                    value: RestaurantTableShape.booth,
                    child: Text('ბოქსი'),
                  ),
                  DropdownMenuItem(
                    value: RestaurantTableShape.barSeat,
                    child: Text('ბარის ადგილი'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => table.shape = value);
                },
              ),
            ),
          ];

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fields[0],
                const SizedBox(height: 8),
                Row(
                  children: [fields[1], const SizedBox(width: 10), fields[2]],
                ),
                const SizedBox(height: 8),
                fields[3],
              ],
            );
          }

          return Row(
            children: [
              fields[0],
              fields[1],
              const SizedBox(width: 10),
              fields[2],
              const SizedBox(width: 10),
              fields[3],
            ],
          );
        },
      ),
    );
  }

  Widget _buildObjectRow(
    _EditablePlanObject object, {
    required VoidCallback onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(_objectIcon(object.type), color: AdminDesign.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              object.label,
              style: const TextStyle(
                color: AdminDesign.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'წაშლა',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  IconData _objectIcon(RestaurantLayoutObjectType type) {
    switch (type) {
      case RestaurantLayoutObjectType.table:
        return Icons.table_restaurant;
      case RestaurantLayoutObjectType.wall:
        return Icons.horizontal_rule;
      case RestaurantLayoutObjectType.entrance:
        return Icons.login;
      case RestaurantLayoutObjectType.stairs:
        return Icons.layers;
      case RestaurantLayoutObjectType.stage:
        return Icons.theaters;
      case RestaurantLayoutObjectType.bar:
        return Icons.local_bar;
      case RestaurantLayoutObjectType.counter:
        return Icons.storefront;
      case RestaurantLayoutObjectType.label:
        return Icons.label_outline;
      case RestaurantLayoutObjectType.restroom:
        return Icons.wc;
    }
  }

  (Color, Color, Color) _objectColors(RestaurantLayoutObjectType type) {
    switch (type) {
      case RestaurantLayoutObjectType.wall:
        return (const Color(0xFF334155), const Color(0xFF0F172A), Colors.white);
      case RestaurantLayoutObjectType.entrance:
        return (
          const Color(0xFFDCFCE7),
          const Color(0xFF16A34A),
          const Color(0xFF14532D),
        );
      case RestaurantLayoutObjectType.stairs:
        return (
          const Color(0xFFFFF7ED),
          const Color(0xFFF97316),
          const Color(0xFF7C2D12),
        );
      case RestaurantLayoutObjectType.stage:
        return (
          const Color(0xFFFCE7F3),
          const Color(0xFFDB2777),
          const Color(0xFF831843),
        );
      case RestaurantLayoutObjectType.bar:
      case RestaurantLayoutObjectType.counter:
        return (
          const Color(0xFFE0F2FE),
          const Color(0xFF0284C7),
          const Color(0xFF0C4A6E),
        );
      case RestaurantLayoutObjectType.restroom:
        return (
          const Color(0xFFEDE9FE),
          const Color(0xFF7C3AED),
          const Color(0xFF3B0764),
        );
      case RestaurantLayoutObjectType.table:
      case RestaurantLayoutObjectType.label:
        return (
          const Color(0xFFF8FAFC),
          const Color(0xFFCBD5E1),
          const Color(0xFF334155),
        );
    }
  }
}

class _EditableTableDefinition {
  _EditableTableDefinition({
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

  factory _EditableTableDefinition.create(String floor, int sortOrder) {
    final label = floor == 'second'
        ? 'VIP Zone $sortOrder'
        : 'Table $sortOrder';
    final point = _defaultTablePoint(sortOrder - 1);
    return _EditableTableDefinition(
      sortOrder: sortOrder,
      label: label,
      capacity: 0,
      x: point.dx,
      y: point.dy,
      width: 130,
      height: 86,
      shape: RestaurantTableShape.rectangle,
    );
  }

  factory _EditableTableDefinition.fromLayout(
    RestaurantTableDefinition table,
    RestaurantLayoutObject? object,
    int index,
  ) {
    final point = _defaultTablePoint(index);
    return _EditableTableDefinition(
      sortOrder: table.sortOrder,
      label: table.label,
      capacity: table.capacity,
      x: object?.x ?? point.dx,
      y: object?.y ?? point.dy,
      width: object?.width ?? 130,
      height: object?.height ?? 86,
      rotation: object?.rotation ?? 0,
      shape: object?.tableShape ?? RestaurantTableShape.rectangle,
    );
  }

  final int sortOrder;
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

  void moveBy(double dx, double dy) {
    x = (x + dx).clamp(0, _planCanvasWidth - width).toDouble();
    y = (y + dy).clamp(0, _planCanvasHeight - height).toDouble();
  }

  void dispose() {
    labelController.dispose();
    capacityController.dispose();
  }
}

class _EditablePlanObject {
  _EditablePlanObject({
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

  factory _EditablePlanObject.create(
    RestaurantLayoutObjectType type,
    int index,
  ) {
    final size = _defaultObjectSize(type);
    return _EditablePlanObject(
      id: '${type.name}-${DateTime.now().microsecondsSinceEpoch}-$index',
      type: type,
      label: _labelForType(type),
      x: 90 + (index * 28),
      y: 80 + (index * 24),
      width: size.width,
      height: size.height,
    );
  }

  factory _EditablePlanObject.fromLayout(RestaurantLayoutObject object) {
    return _EditablePlanObject(
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

  final String id;
  final RestaurantLayoutObjectType type;
  final String label;
  double x;
  double y;
  final double width;
  final double height;
  final double rotation;
  final String? colorHex;

  void moveBy(double dx, double dy) {
    x = (x + dx).clamp(0, _planCanvasWidth - width).toDouble();
    y = (y + dy).clamp(0, _planCanvasHeight - height).toDouble();
  }
}

class _PlanGridPainter extends CustomPainter {
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

Offset _defaultTablePoint(int index) {
  const columns = 4;
  const cellWidth = 210.0;
  const cellHeight = 130.0;
  return Offset(
    70 + (index % columns) * cellWidth,
    70 + (index ~/ columns) * cellHeight,
  );
}

Size _defaultObjectSize(RestaurantLayoutObjectType type) {
  switch (type) {
    case RestaurantLayoutObjectType.wall:
      return const Size(220, 24);
    case RestaurantLayoutObjectType.entrance:
      return const Size(170, 44);
    case RestaurantLayoutObjectType.stairs:
      return const Size(150, 58);
    case RestaurantLayoutObjectType.stage:
      return const Size(220, 72);
    case RestaurantLayoutObjectType.bar:
    case RestaurantLayoutObjectType.counter:
      return const Size(210, 56);
    case RestaurantLayoutObjectType.restroom:
    case RestaurantLayoutObjectType.label:
    case RestaurantLayoutObjectType.table:
      return const Size(150, 48);
  }
}

String _labelForType(RestaurantLayoutObjectType type) {
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
