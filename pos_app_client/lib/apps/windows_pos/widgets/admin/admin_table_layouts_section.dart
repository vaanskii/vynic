import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

const double _defaultPlanCanvasWidth = 1000;
const double _defaultPlanCanvasHeight = 1000;

class AdminTableLayoutsSection extends StatefulWidget {
  const AdminTableLayoutsSection({super.key});

  @override
  State<AdminTableLayoutsSection> createState() =>
      _AdminTableLayoutsSectionState();
}

class _AdminTableLayoutsSectionState extends State<AdminTableLayoutsSection> {
  late final TextEditingController _layoutNameController;
  final List<_EditableZonePlan> _zones = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _layoutNameController = TextEditingController();
    _loadDraft(DatabaseService.getRestaurantTableLayout());
  }

  @override
  void dispose() {
    _layoutNameController.dispose();
    for (final zone in _zones) {
      zone.dispose();
    }
    super.dispose();
  }

  void _loadDraft(RestaurantTableLayout layout) {
    for (final zone in _zones) {
      zone.dispose();
    }
    _zones.clear();

    _layoutNameController.text = layout.name;
    final sortedZones = [...layout.zones]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    for (final zone in sortedZones) {
      _zones.add(_EditableZonePlan.fromLayout(layout, zone));
    }

    if (_zones.isEmpty) {
      _zones
        ..add(_EditableZonePlan.create(1))
        ..add(_EditableZonePlan.create(2));
    }
  }

  Future<void> _saveLayout({VoidCallback? refresh}) async {
    if (_isSaving) {
      return;
    }

    setState(() => _isSaving = true);
    refresh?.call();
    try {
      await DatabaseService.saveActiveRestaurantTableLayout(_buildLayout());
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
    } on StateError catch (error) {
      // The repository refuses layouts that would drop occupied tables.
      if (!mounted) {
        return;
      }
      unawaited(
        showPosToast(
          context: context,
          message: 'გეგმა ვერ შეინახა: ${error.message}',
          style: PosToastStyle.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        refresh?.call();
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
    return RestaurantTableLayout(
      id: 'custom-floor-plan-layout',
      name: layoutName.isEmpty ? 'Custom floor plan' : layoutName,
      zones: [
        for (final zone in _zones)
          RestaurantZone(
            id: zone.zoneId,
            name: zone.name,
            legacyFloor: zone.floorKey,
            displayOrder: zone.displayOrder,
            renderMode: TableLayoutRenderMode.floorPlan,
            canvasWidth: zone.canvasWidth,
            canvasHeight: zone.canvasHeight,
          ),
      ],
      tables: [for (final zone in _zones) ..._buildTables(zone)],
      objects: [for (final zone in _zones) ..._buildObjects(zone)],
    );
  }

  List<RestaurantTableDefinition> _buildTables(_EditableZonePlan zone) {
    return [
      for (var i = 0; i < zone.tables.length; i++)
        RestaurantTableDefinition(
          id: _tableIdFor(zone.floorKey, zone.tables[i].legacyTableNumber),
          zoneId: zone.zoneId,
          legacyFloor: zone.floorKey,
          legacyTableNumber: zone.tables[i].legacyTableNumber,
          label: zone.tables[i].label,
          capacity: zone.tables[i].capacity,
          sortOrder: i + 1,
        ),
    ];
  }

  List<RestaurantLayoutObject> _buildObjects(_EditableZonePlan zone) {
    return [
      for (var i = 0; i < zone.tables.length; i++)
        RestaurantLayoutObject(
          id: '${_tableIdFor(zone.floorKey, zone.tables[i].legacyTableNumber)}-visual',
          zoneId: zone.zoneId,
          type: RestaurantLayoutObjectType.table,
          label: zone.tables[i].label,
          x: zone.tables[i].x,
          y: zone.tables[i].y,
          width: zone.tables[i].width,
          height: zone.tables[i].height,
          rotation: zone.tables[i].rotation,
          sortOrder: i + 1,
          tableId: _tableIdFor(zone.floorKey, zone.tables[i].legacyTableNumber),
          tableShape: zone.tables[i].shape,
        ),
      for (var i = 0; i < zone.objects.length; i++)
        RestaurantLayoutObject(
          id: zone.objects[i].id,
          zoneId: zone.zoneId,
          type: zone.objects[i].type,
          label: zone.objects[i].label,
          x: zone.objects[i].x,
          y: zone.objects[i].y,
          width: zone.objects[i].width,
          height: zone.objects[i].height,
          rotation: zone.objects[i].rotation,
          sortOrder: 1000 + i,
          colorHex: zone.objects[i].colorHex,
        ),
    ];
  }

  void _addFloor() {
    setState(() {
      _zones.add(_EditableZonePlan.create(_zones.length + 1));
    });
  }

  _EditableTableDefinition _addTable(
    _EditableZonePlan zone, {
    VoidCallback? refresh,
  }) {
    late final _EditableTableDefinition table;
    table = _EditableTableDefinition.create(
      zone.floorKey,
      zone.tables.length + 1,
      zone.nextLegacyTableNumber(),
    );
    zone.tables.add(table);
    table.moveBy(
      0,
      0,
      canvasWidth: zone.canvasWidth,
      canvasHeight: zone.canvasHeight,
    );
    _refreshDraft(refresh);
    return table;
  }

  bool _removeTable(
    _EditableZonePlan zone,
    _EditableTableDefinition table, {
    VoidCallback? refresh,
  }) {
    if (zone.tables.length <= 1) {
      unawaited(
        showPosToast(
          context: context,
          message: 'ბოლო მაგიდა ვერ წაიშლება',
          style: PosToastStyle.error,
        ),
      );
      return false;
    }
    final tableIndex = zone.tables.indexOf(table);
    if (tableIndex < 0) {
      return false;
    }
    final liveTable = DatabaseService.getTable(
      table.legacyTableNumber,
      zone.floorKey,
    );
    if (liveTable?.isReserved == true || liveTable?.activeOrderId != null) {
      unawaited(
        showPosToast(
          context: context,
          message: 'დაკავებული მაგიდის წაშლა ჯერ არ შეიძლება',
          style: PosToastStyle.error,
        ),
      );
      return false;
    }

    zone.tables.removeAt(tableIndex).dispose();
    zone.renumberTables();
    _refreshDraft(refresh);
    return true;
  }

  _EditablePlanObject _addPlanObject(
    _EditableZonePlan zone,
    RestaurantLayoutObjectType type, {
    VoidCallback? refresh,
  }) {
    late final _EditablePlanObject object;
    object = _EditablePlanObject.create(type, zone.objects.length + 1);
    zone.objects.add(object);
    object.moveBy(
      0,
      0,
      canvasWidth: zone.canvasWidth,
      canvasHeight: zone.canvasHeight,
    );
    _refreshDraft(refresh);
    return object;
  }

  _EditablePlanObject _createPlanObject(
    _EditableZonePlan zone,
    RestaurantLayoutObjectType type, {
    required double x,
    required double y,
    required double width,
    required double height,
    double rotation = 0,
    String? label,
    VoidCallback? refresh,
  }) {
    final object = _EditablePlanObject(
      id: '${type.name}-${DateTime.now().microsecondsSinceEpoch}-${zone.objects.length + 1}',
      type: type,
      label: label ?? _labelForType(type),
      x: x,
      y: y,
      width: width,
      height: height,
      rotation: rotation,
    );
    zone.objects.add(object);
    object.moveBy(
      0,
      0,
      canvasWidth: zone.canvasWidth,
      canvasHeight: zone.canvasHeight,
    );
    _refreshDraft(refresh);
    return object;
  }

  void _removePlanObject(
    _EditableZonePlan zone,
    String id, {
    VoidCallback? refresh,
  }) {
    zone.objects.removeWhere((object) => object.id == id);
    _refreshDraft(refresh);
  }

  _EditablePlanObject _addEntranceInWall(
    _EditableZonePlan zone,
    _EditablePlanObject wall, {
    VoidCallback? refresh,
  }) {
    final entranceWidth = math
        .min(math.max(wall.width * 0.28, 86), 140)
        .toDouble();
    final entranceHeight = math.max(wall.height + 18, 42).toDouble();
    final entrance = _createPlanObject(
      zone,
      RestaurantLayoutObjectType.entrance,
      x: wall.x + (wall.width - entranceWidth) / 2,
      y: wall.y + (wall.height - entranceHeight) / 2,
      width: entranceWidth,
      height: entranceHeight,
      rotation: wall.rotation,
      refresh: refresh,
    );
    _splitWallForOpening(
      zone,
      wall,
      openingWidth: entranceWidth,
      openingHeight: entranceHeight,
      refresh: refresh,
    );
    return entrance;
  }

  void _splitWall(
    _EditableZonePlan zone,
    _EditablePlanObject wall, {
    VoidCallback? refresh,
  }) {
    final index = zone.objects.indexOf(wall);
    if (index < 0 || wall.type != RestaurantLayoutObjectType.wall) {
      return;
    }
    final endpoints = _editableWallEndpoints(wall);
    final midpoint = Offset(
      (endpoints.$1.dx + endpoints.$2.dx) / 2,
      (endpoints.$1.dy + endpoints.$2.dy) / 2,
    );
    final first = _editableWallFromPoints(
      id: wall.id,
      start: endpoints.$1,
      end: midpoint,
      thickness: wall.height,
      label: wall.label,
    );
    final second = _editableWallFromPoints(
      id: '${wall.id}-split-${DateTime.now().microsecondsSinceEpoch}',
      start: midpoint,
      end: endpoints.$2,
      thickness: wall.height,
      label: wall.label,
    );
    if (first == null || second == null) {
      return;
    }
    zone.objects
      ..removeAt(index)
      ..insert(index, second)
      ..insert(index, first);
    _refreshDraft(refresh);
  }

  void _splitWallForOpening(
    _EditableZonePlan zone,
    _EditablePlanObject wall, {
    required double openingWidth,
    required double openingHeight,
    VoidCallback? refresh,
  }) {
    final index = zone.objects.indexOf(wall);
    if (index < 0 || wall.type != RestaurantLayoutObjectType.wall) {
      return;
    }

    final endpoints = _editableWallEndpoints(wall);
    final start = endpoints.$1;
    final end = endpoints.$2;
    final vector = end - start;
    final length = vector.distance;
    final gap = openingWidth.clamp(18.0, math.max(18.0, length - 48));
    final segmentLength = (length - gap) / 2;
    if (segmentLength < 24) {
      return;
    }
    final unit = Offset(vector.dx / length, vector.dy / length);
    final firstEnd = start + unit * segmentLength;
    final secondStart = end - unit * segmentLength;
    final first = _editableWallFromPoints(
      id: wall.id,
      start: start,
      end: firstEnd,
      thickness: wall.height,
      label: wall.label,
    );
    final second = _editableWallFromPoints(
      id: '${wall.id}-split-${DateTime.now().microsecondsSinceEpoch}',
      start: secondStart,
      end: end,
      thickness: wall.height,
      label: wall.label,
    );
    if (first == null || second == null) {
      return;
    }

    zone.objects
      ..removeAt(index)
      ..insert(index, second)
      ..insert(index, first);
    _refreshDraft(refresh);
  }

  _EditablePlanObject? _addWallSegmentFromPoints(
    _EditableZonePlan zone,
    Offset start,
    Offset end, {
    VoidCallback? refresh,
  }) {
    final wall = _editableWallFromPoints(
      id: 'wall-${DateTime.now().microsecondsSinceEpoch}-${zone.objects.length + 1}',
      start: start,
      end: end,
      thickness: 24,
    );
    if (wall == null) {
      return null;
    }
    zone.objects.add(wall);
    _refreshDraft(refresh);
    return wall;
  }

  void _refreshDraft(VoidCallback? refresh) {
    if (refresh != null) {
      refresh();
      return;
    }
    setState(() {});
  }

  void _removeFloor(_EditableZonePlan zone) {
    if (_zones.length <= 1) {
      unawaited(
        showPosToast(
          context: context,
          message: 'ერთი სართული მაინც უნდა დარჩეს',
          style: PosToastStyle.error,
        ),
      );
      return;
    }
    final hasBusyTables = zone.tables.any((table) {
      final liveTable = DatabaseService.getTable(
        table.legacyTableNumber,
        zone.floorKey,
      );
      return liveTable?.isReserved == true || liveTable?.activeOrderId != null;
    });
    if (hasBusyTables) {
      unawaited(
        showPosToast(
          context: context,
          message: 'დაკავებული სართული ჯერ ვერ წაიშლება',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    setState(() {
      _zones.remove(zone);
      zone.dispose();
    });
  }

  void _showExpandedPlan(_EditableZonePlan zone) {
    final workingZone = zone.copy();
    _EditableTableDefinition? selectedTable;
    _EditablePlanObject? selectedObject;
    final selectedTables = <_EditableTableDefinition>{};
    bool multiSelectMode = false;
    bool wallDrawMode = false;
    Offset? wallStart;
    Offset? wallHover;

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(20),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            zone.name,
                            style: const TextStyle(
                              color: AdminDesign.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'დახურვა',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            final table = _addTable(
                              workingZone,
                              refresh: () => dialogSetState(() {}),
                            );
                            dialogSetState(() {
                              selectedTables
                                ..clear()
                                ..add(table);
                              selectedTable = table;
                              selectedObject = null;
                            });
                          },
                          style: AdminDesign.primaryButtonStyle(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('მაგიდის დამატება'),
                        ),
                        _buildAddObjectButton(
                          workingZone,
                          refresh: () => dialogSetState(() {}),
                          onAdded: (object) {
                            dialogSetState(() {
                              wallDrawMode = false;
                              wallStart = null;
                              wallHover = null;
                              selectedTables.clear();
                              selectedObject = object;
                              selectedTable = null;
                            });
                          },
                        ),
                        FilterChip(
                          selected: wallDrawMode,
                          onSelected: (value) {
                            dialogSetState(() {
                              wallDrawMode = value;
                              wallStart = null;
                              wallHover = null;
                              selectedTables.clear();
                              selectedTable = null;
                              selectedObject = null;
                            });
                          },
                          avatar: const Icon(Icons.edit_road, size: 18),
                          label: const Text('კედლის დახაზვა'),
                        ),
                        FilterChip(
                          selected: multiSelectMode,
                          onSelected: (value) {
                            dialogSetState(() {
                              multiSelectMode = value;
                              wallDrawMode = false;
                              wallStart = null;
                              wallHover = null;
                              selectedObject = null;
                              if (!multiSelectMode &&
                                  selectedTables.length > 1) {
                                selectedTable = selectedTables.first;
                                selectedTables
                                  ..clear()
                                  ..add(selectedTable!);
                              }
                            });
                          },
                          avatar: const Icon(Icons.checklist, size: 18),
                          label: const Text('რამდენიმეს არჩევა'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() {
                                    zone.replaceFrom(workingZone);
                                  });
                                  await _saveLayout(
                                    refresh: () => dialogSetState(() {}),
                                  );
                                },
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
                    const SizedBox(height: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final sideBySide = constraints.maxWidth >= 1080;
                          final canvas = _buildPlanCanvas(
                            zone: workingZone,
                            expanded: true,
                            editable: true,
                            selectedTable: selectedTable,
                            selectedTables: selectedTables,
                            selectedObject: selectedObject,
                            wallDraftStart: wallStart,
                            wallDraftEnd: wallHover,
                            onTableTap: (table) {
                              dialogSetState(() {
                                wallDrawMode = false;
                                wallStart = null;
                                wallHover = null;
                                if (multiSelectMode) {
                                  if (!selectedTables.remove(table)) {
                                    selectedTables.add(table);
                                  }
                                  selectedTable = selectedTables.length == 1
                                      ? selectedTables.first
                                      : null;
                                } else {
                                  selectedTables
                                    ..clear()
                                    ..add(table);
                                  selectedTable = table;
                                }
                                selectedObject = null;
                              });
                            },
                            onObjectTap: (object) {
                              dialogSetState(() {
                                wallDrawMode = false;
                                wallStart = null;
                                wallHover = null;
                                selectedTables.clear();
                                selectedObject = object;
                                selectedTable = null;
                              });
                            },
                            onObjectRemove: (object) {
                              _removePlanObject(
                                workingZone,
                                object.id,
                                refresh: () => dialogSetState(() {}),
                              );
                              dialogSetState(() {
                                if (selectedObject == object) {
                                  selectedObject = null;
                                }
                                selectedTables.clear();
                                selectedTable = null;
                              });
                            },
                            onTableDrag: (table, delta) {
                              dialogSetState(() {
                                _moveTableSelection(
                                  workingZone,
                                  table,
                                  selectedTables,
                                  dx: delta.dx,
                                  dy: delta.dy,
                                );
                              });
                            },
                            onCanvasTap: (point) {
                              if (!wallDrawMode) {
                                return;
                              }
                              dialogSetState(() {
                                if (wallStart == null) {
                                  wallStart = point;
                                  wallHover = point;
                                  selectedTables.clear();
                                  selectedTable = null;
                                  selectedObject = null;
                                  return;
                                }
                                final wall = _addWallSegmentFromPoints(
                                  workingZone,
                                  wallStart!,
                                  point,
                                  refresh: () => dialogSetState(() {}),
                                );
                                wallStart = point;
                                wallHover = point;
                                if (wall != null) {
                                  selectedObject = wall;
                                  selectedTable = null;
                                  selectedTables.clear();
                                }
                              });
                            },
                            onCanvasDoubleTap: () {
                              if (!wallDrawMode) {
                                return;
                              }
                              dialogSetState(() {
                                wallDrawMode = false;
                                wallStart = null;
                                wallHover = null;
                              });
                            },
                            onCanvasHover: (point) {
                              if (!wallDrawMode || wallStart == null) {
                                return;
                              }
                              dialogSetState(() => wallHover = point);
                            },
                            onCanvasChanged: () => dialogSetState(() {}),
                          );
                          final editor = _buildSelectionEditor(
                            zone: workingZone,
                            table: selectedTable,
                            selectedTables: selectedTables,
                            object: selectedObject,
                            onRemoveTable: selectedTable == null
                                ? null
                                : () {
                                    final removed = _removeTable(
                                      workingZone,
                                      selectedTable!,
                                      refresh: () => dialogSetState(() {}),
                                    );
                                    if (removed) {
                                      selectedTables.remove(selectedTable);
                                      selectedTable = null;
                                      selectedObject = null;
                                    }
                                  },
                            onRemoveObject: selectedObject == null
                                ? null
                                : () {
                                    _removePlanObject(
                                      workingZone,
                                      selectedObject!.id,
                                      refresh: () => dialogSetState(() {}),
                                    );
                                    selectedObject = null;
                                    selectedTable = null;
                                  },
                            onAddEntranceInWall:
                                selectedObject?.type !=
                                    RestaurantLayoutObjectType.wall
                                ? null
                                : () {
                                    final entrance = _addEntranceInWall(
                                      workingZone,
                                      selectedObject!,
                                      refresh: () => dialogSetState(() {}),
                                    );
                                    selectedObject = entrance;
                                    selectedTable = null;
                                    selectedTables.clear();
                                  },
                            onSplitWall:
                                selectedObject?.type !=
                                    RestaurantLayoutObjectType.wall
                                ? null
                                : () {
                                    _splitWall(
                                      workingZone,
                                      selectedObject!,
                                      refresh: () => dialogSetState(() {}),
                                    );
                                    selectedObject = null;
                                  },
                            onBulkShapeChanged: (shape) {
                              _applyShapeToTables(
                                selectedTables,
                                shape,
                                workingZone,
                              );
                            },
                            onAlignRow: () {
                              _alignSelectedTables(
                                selectedTables,
                                workingZone,
                                axis: Axis.horizontal,
                              );
                            },
                            onAlignColumn: () {
                              _alignSelectedTables(
                                selectedTables,
                                workingZone,
                                axis: Axis.vertical,
                              );
                            },
                            onClearTableSelection: () {
                              selectedTables.clear();
                              selectedTable = null;
                            },
                            refresh: () {
                              dialogSetState(() {});
                            },
                          );

                          if (sideBySide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: canvas),
                                const SizedBox(width: 16),
                                SizedBox(width: 330, child: editor),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              Expanded(child: canvas),
                              const SizedBox(height: 12),
                              SizedBox(height: 230, child: editor),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(workingZone.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(
            icon: Icons.map_outlined,
            title: 'მაგიდების განლაგება',
            subtitle: 'შექმენით რეალური დარბაზის გეგმა POS-ისთვის.',
            action: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _addFloor,
                  style: AdminDesign.outlineButtonStyle(),
                  icon: const Icon(Icons.add_business_outlined, size: 18),
                  label: const Text('სართულის დამატება'),
                ),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _resetToDefault,
                  style: AdminDesign.outlineButtonStyle(),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('საწყისი'),
                ),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : () => _saveLayout(),
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
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 16.0;
              final twoColumns = constraints.maxWidth >= 1120;
              final cardWidth = twoColumns
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final zone in _zones)
                    SizedBox(width: cardWidth, child: _buildZoneEditor(zone)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildZoneEditor(_EditableZonePlan zone) {
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final controls = Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showExpandedPlan(zone),
                    style: AdminDesign.outlineButtonStyle(),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('რედაქტირება'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _removeFloor(zone),
                    style: AdminDesign.outlineButtonStyle(
                      foreground: AdminDesign.danger,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('სართულის წაშლა'),
                  ),
                ],
              );

              final header = Text(
                'სართული ${zone.displayOrder}',
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
            controller: zone.nameController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'ზონის სახელი',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _buildPlanCanvas(zone: zone, showLabels: false),
        ],
      ),
    );
  }

  Widget _buildAddObjectButton(
    _EditableZonePlan zone, {
    VoidCallback? refresh,
    ValueChanged<_EditablePlanObject>? onAdded,
  }) {
    return PopupMenuButton<RestaurantLayoutObjectType>(
      tooltip: 'ობიექტის დამატება',
      onSelected: (type) {
        final object = _addPlanObject(zone, type, refresh: refresh);
        onAdded?.call(object);
      },
      itemBuilder: (context) => const [
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
    required _EditableZonePlan zone,
    bool expanded = false,
    bool editable = false,
    _EditableTableDefinition? selectedTable,
    Set<_EditableTableDefinition> selectedTables = const {},
    _EditablePlanObject? selectedObject,
    Offset? wallDraftStart,
    Offset? wallDraftEnd,
    bool showLabels = true,
    ValueChanged<_EditableTableDefinition>? onTableTap,
    ValueChanged<_EditablePlanObject>? onObjectTap,
    ValueChanged<_EditablePlanObject>? onObjectRemove,
    void Function(_EditableTableDefinition table, Offset delta)? onTableDrag,
    ValueChanged<Offset>? onCanvasTap,
    VoidCallback? onCanvasDoubleTap,
    ValueChanged<Offset>? onCanvasHover,
    VoidCallback? onCanvasChanged,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final planCanvasWidth = zone.canvasWidth;
        final planCanvasHeight = zone.canvasHeight;
        final maxPreviewHeight = expanded
            ? constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : constraints.maxWidth * (planCanvasHeight / planCanvasWidth)
            : math.min(320.0, constraints.maxWidth * 0.46);
        final scaleByWidth = constraints.maxWidth / planCanvasWidth;
        final scaleByHeight = maxPreviewHeight / planCanvasHeight;
        final scale = math.min(scaleByWidth, scaleByHeight);
        final canvasWidth = planCanvasWidth * scale;
        final canvasHeight = planCanvasHeight * scale;

        return Align(
          alignment: Alignment.topCenter,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AdminDesign.radius),
            child: SizedBox(
              width: canvasWidth,
              height: canvasHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: AdminDesign.border),
                ),
                child: MouseRegion(
                  onHover: onCanvasHover == null
                      ? null
                      : (event) {
                          onCanvasHover(
                            Offset(
                              event.localPosition.dx / scale,
                              event.localPosition.dy / scale,
                            ),
                          );
                        },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _PlanGridPainter()),
                      ),
                      if (editable && onCanvasTap != null)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) {
                              onCanvasTap(
                                Offset(
                                  details.localPosition.dx / scale,
                                  details.localPosition.dy / scale,
                                ),
                              );
                            },
                            onDoubleTap: onCanvasDoubleTap,
                          ),
                        ),
                      if (wallDraftStart != null && wallDraftEnd != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _WallDraftPainter(
                                start: wallDraftStart * scale,
                                end: wallDraftEnd * scale,
                              ),
                            ),
                          ),
                        ),
                      for (final object in zone.objects)
                        _buildEditableObjectOnCanvas(
                          object: object,
                          scale: scale,
                          canvasWidth: planCanvasWidth,
                          canvasHeight: planCanvasHeight,
                          editable: editable,
                          selected: selectedObject == object,
                          onTap: () => onObjectTap?.call(object),
                          onRemove: onObjectRemove == null
                              ? null
                              : () => onObjectRemove(object),
                          showLabel: showLabels,
                          onCanvasChanged: onCanvasChanged,
                        ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _WallJointsPainter(
                              joints: _editableWallJoints(zone.objects, scale),
                              color: _objectColors(
                                RestaurantLayoutObjectType.wall,
                              ).$1,
                              borderColor: _objectColors(
                                RestaurantLayoutObjectType.wall,
                              ).$2,
                            ),
                          ),
                        ),
                      ),
                      for (final table in zone.tables)
                        _buildEditableTableOnCanvas(
                          table,
                          scale,
                          canvasWidth: planCanvasWidth,
                          canvasHeight: planCanvasHeight,
                          editable: editable,
                          selected:
                              selectedTable == table ||
                              selectedTables.contains(table),
                          onTap: () => onTableTap?.call(table),
                          onDrag: onTableDrag == null
                              ? null
                              : (delta) => onTableDrag(table, delta),
                          showLabel: showLabels,
                          onCanvasChanged: onCanvasChanged,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableTableOnCanvas(
    _EditableTableDefinition table,
    double scale, {
    required double canvasWidth,
    required double canvasHeight,
    required bool editable,
    required bool selected,
    required VoidCallback? onTap,
    ValueChanged<Offset>? onDrag,
    required bool showLabel,
    VoidCallback? onCanvasChanged,
  }) {
    return Positioned(
      left: table.x * scale,
      top: table.y * scale,
      width: table.width * scale,
      height: table.height * scale,
      child: GestureDetector(
        onTap: onTap,
        onPanUpdate: (details) {
          if (!editable) {
            return;
          }
          final delta = Offset(
            details.delta.dx / scale,
            details.delta.dy / scale,
          );
          if (onDrag != null) {
            onDrag(delta);
          } else {
            setState(() {
              table.moveBy(
                delta.dx,
                delta.dy,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
              );
            });
          }
          onCanvasChanged?.call();
        },
        child: Transform.rotate(
          angle: table.rotation * math.pi / 180,
          child: DecoratedBox(
            decoration: _tableDecoration(
              shape: table.shape,
              color: const Color(0xFFE0F2FE),
              borderColor: selected
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF0369A1),
              selected: selected,
            ),
            child: showLabel
                ? Center(
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
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildEditableObjectOnCanvas({
    required _EditablePlanObject object,
    required double scale,
    required double canvasWidth,
    required double canvasHeight,
    required bool editable,
    required bool selected,
    required VoidCallback? onTap,
    VoidCallback? onRemove,
    required bool showLabel,
    VoidCallback? onCanvasChanged,
  }) {
    final colors = _objectColors(object.type);
    return Positioned(
      left: object.x * scale,
      top: object.y * scale,
      width: object.width * scale,
      height: object.height * scale,
      child: GestureDetector(
        onTap: onTap,
        onPanUpdate: (details) {
          if (!editable) {
            return;
          }
          setState(() {
            object.moveBy(
              details.delta.dx / scale,
              details.delta.dy / scale,
              canvasWidth: canvasWidth,
              canvasHeight: canvasHeight,
            );
          });
          onCanvasChanged?.call();
        },
        child: object.type == RestaurantLayoutObjectType.wall
            ? Transform.rotate(
                angle: object.rotation * math.pi / 180,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _WallSegmentPainter(
                          color: colors.$1,
                          borderColor: selected
                              ? const Color(0xFF0F172A)
                              : colors.$2,
                          selected: selected,
                        ),
                      ),
                    ),
                    if (editable)
                      Positioned(
                        right: -6,
                        top: -12,
                        child: InkWell(
                          onTap: onRemove,
                          child: const Icon(Icons.close, size: 14),
                        ),
                      ),
                  ],
                ),
              )
            : Transform.rotate(
                angle: object.rotation * math.pi / 180,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.$1,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? const Color(0xFF0F172A) : colors.$2,
                      width: selected ? 3 : 1.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (object.type == RestaurantLayoutObjectType.stairs)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _StairsPainter(colors.$2),
                          ),
                        ),
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _objectIcon(object.type),
                              color: colors.$3,
                              size: 18,
                            ),
                            if (showLabel) ...[
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
                          ],
                        ),
                      ),
                      if (editable)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: InkWell(
                            onTap: onRemove,
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
    bool selected = false,
  }) {
    return BoxDecoration(
      color: color,
      border: Border.all(color: borderColor, width: selected ? 3 : 2),
      borderRadius: BorderRadius.circular(_tableRadius(shape)),
      boxShadow: [
        BoxShadow(
          color: borderColor.withValues(alpha: 0.14),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildSelectionEditor({
    required _EditableZonePlan zone,
    required _EditableTableDefinition? table,
    required Set<_EditableTableDefinition> selectedTables,
    required _EditablePlanObject? object,
    required VoidCallback? onRemoveTable,
    required VoidCallback? onRemoveObject,
    required VoidCallback? onAddEntranceInWall,
    required VoidCallback? onSplitWall,
    required ValueChanged<RestaurantTableShape> onBulkShapeChanged,
    required VoidCallback onAlignRow,
    required VoidCallback onAlignColumn,
    required VoidCallback onClearTableSelection,
    required VoidCallback refresh,
  }) {
    return AdminPanel(
      shadow: false,
      color: const Color(0xFFF8FAFC),
      child: selectedTables.length > 1
          ? _buildSelectedTablesEditor(
              zone,
              selectedTables,
              onBulkShapeChanged,
              onAlignRow,
              onAlignColumn,
              onClearTableSelection,
              refresh,
            )
          : table != null
          ? _buildSelectedTableEditor(zone, table, refresh, onRemoveTable)
          : object != null
          ? _buildSelectedObjectEditor(
              zone,
              object,
              refresh,
              onRemoveObject,
              onAddEntranceInWall,
              onSplitWall,
            )
          : const Center(
              child: Text(
                'აირჩიეთ მაგიდა ან ობიექტი გეგმაზე',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AdminDesign.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
    );
  }

  Widget _buildSelectedTablesEditor(
    _EditableZonePlan zone,
    Set<_EditableTableDefinition> tables,
    ValueChanged<RestaurantTableShape> onShapeChanged,
    VoidCallback onAlignRow,
    VoidCallback onAlignColumn,
    VoidCallback onClearSelection,
    VoidCallback refresh,
  ) {
    final selectedTables = tables.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final commonShape = _commonTableShape(selectedTables);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${selectedTables.length} მაგიდა',
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'მონიშვნის მოხსნა',
                onPressed: () {
                  onClearSelection();
                  refresh();
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<RestaurantTableShape>(
            initialValue: commonShape,
            decoration: const InputDecoration(
              labelText: 'ფორმა ყველასთვის',
              border: OutlineInputBorder(),
            ),
            items: _tableShapeMenuItems(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              onShapeChanged(value);
              refresh();
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  onAlignRow();
                  refresh();
                },
                style: AdminDesign.outlineButtonStyle(),
                icon: const Icon(Icons.align_horizontal_left, size: 18),
                label: const Text('რიგში გასწორება'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  onAlignColumn();
                  refresh();
                },
                style: AdminDesign.outlineButtonStyle(),
                icon: const Icon(Icons.align_vertical_top, size: 18),
                label: const Text('სვეტში გასწორება'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            selectedTables.map((table) => table.label).join(', '),
            style: const TextStyle(
              color: AdminDesign.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedTableEditor(
    _EditableZonePlan zone,
    _EditableTableDefinition table,
    VoidCallback refresh,
    VoidCallback? onRemove,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'მაგიდა #${table.sortOrder}',
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'წაშლა',
                onPressed: onRemove == null
                    ? null
                    : () {
                        onRemove();
                        refresh();
                      },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _tableLabelField(table, refresh),
          const SizedBox(height: 10),
          _capacityField(table, refresh),
          const SizedBox(height: 10),
          _shapePicker(zone, table, refresh),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StepperControl(
                label: 'W ${table.width.round()}',
                onDecrease: () {
                  table.resizeBy(
                    widthDelta: -12,
                    canvasWidth: zone.canvasWidth,
                    canvasHeight: zone.canvasHeight,
                  );
                  refresh();
                },
                onIncrease: () {
                  table.resizeBy(
                    widthDelta: 12,
                    canvasWidth: zone.canvasWidth,
                    canvasHeight: zone.canvasHeight,
                  );
                  refresh();
                },
              ),
              _StepperControl(
                label: 'H ${table.height.round()}',
                onDecrease: () {
                  table.resizeBy(
                    heightDelta: -12,
                    canvasWidth: zone.canvasWidth,
                    canvasHeight: zone.canvasHeight,
                  );
                  refresh();
                },
                onIncrease: () {
                  table.resizeBy(
                    heightDelta: 12,
                    canvasWidth: zone.canvasWidth,
                    canvasHeight: zone.canvasHeight,
                  );
                  refresh();
                },
              ),
              _StepperControl(
                label: '${table.rotation.round()}°',
                onDecrease: () {
                  table.rotateBy(-15);
                  refresh();
                },
                onIncrease: () {
                  table.rotateBy(15);
                  refresh();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedObjectEditor(
    _EditableZonePlan zone,
    _EditablePlanObject object,
    VoidCallback refresh,
    VoidCallback? onRemove,
    VoidCallback? onAddEntranceInWall,
    VoidCallback? onSplitWall,
  ) {
    final isWall = object.type == RestaurantLayoutObjectType.wall;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_objectIcon(object.type), color: AdminDesign.accentDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _labelForType(object.type),
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'წაშლა',
                onPressed: onRemove == null
                    ? null
                    : () {
                        onRemove();
                        refresh();
                      },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: object.label,
            onChanged: (value) {
              object.label = value.trim().isEmpty
                  ? _labelForType(object.type)
                  : value.trim();
              refresh();
            },
            decoration: const InputDecoration(
              labelText: 'სახელი',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StepperControl(
                label: 'W ${object.width.round()}',
                onDecrease: () {
                  object.resizeBy(
                    widthDelta: -20,
                    canvasWidth: zone.canvasWidth,
                    canvasHeight: zone.canvasHeight,
                  );
                  refresh();
                },
                onIncrease: () {
                  object.resizeBy(
                    widthDelta: 20,
                    canvasWidth: zone.canvasWidth,
                    canvasHeight: zone.canvasHeight,
                  );
                  refresh();
                },
              ),
              _StepperControl(
                label: 'H ${object.height.round()}',
                onDecrease: () {
                  object.resizeBy(
                    heightDelta: isWall ? -8 : -12,
                    canvasWidth: zone.canvasWidth,
                    canvasHeight: zone.canvasHeight,
                  );
                  refresh();
                },
                onIncrease: () {
                  object.resizeBy(
                    heightDelta: isWall ? 8 : 12,
                    canvasWidth: zone.canvasWidth,
                    canvasHeight: zone.canvasHeight,
                  );
                  refresh();
                },
              ),
              _StepperControl(
                label: '${object.rotation.round()}°',
                onDecrease: () {
                  object.rotateBy(-15);
                  refresh();
                },
                onIncrease: () {
                  object.rotateBy(15);
                  refresh();
                },
              ),
            ],
          ),
          if (isWall) ...[
            const SizedBox(height: 14),
            const Text(
              'კედლის მოქმედებები',
              style: TextStyle(
                color: AdminDesign.text,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onAddEntranceInWall == null
                      ? null
                      : () {
                          onAddEntranceInWall();
                          refresh();
                        },
                  style: AdminDesign.outlineButtonStyle(),
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('შესასვლელი კედელში'),
                ),
                OutlinedButton.icon(
                  onPressed: onSplitWall == null
                      ? null
                      : () {
                          onSplitWall();
                          refresh();
                        },
                  style: AdminDesign.outlineButtonStyle(),
                  icon: const Icon(Icons.call_split, size: 18),
                  label: const Text('გაყოფა'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _shapePicker(
    _EditableZonePlan zone,
    _EditableTableDefinition table,
    VoidCallback refresh,
  ) {
    return DropdownButtonFormField<RestaurantTableShape>(
      initialValue: table.shape,
      decoration: const InputDecoration(
        labelText: 'ფორმა',
        border: OutlineInputBorder(),
      ),
      items: _tableShapeMenuItems(),
      onChanged: (value) {
        if (value == null) {
          return;
        }
        table.applyShape(
          value,
          canvasWidth: zone.canvasWidth,
          canvasHeight: zone.canvasHeight,
        );
        refresh();
      },
    );
  }

  Widget _tableLabelField(
    _EditableTableDefinition table,
    VoidCallback refresh,
  ) {
    return TextField(
      controller: table.labelController,
      onChanged: (_) => refresh(),
      decoration: const InputDecoration(
        labelText: 'მაგიდის სახელი',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _capacityField(_EditableTableDefinition table, VoidCallback refresh) {
    return TextField(
      controller: table.capacityController,
      keyboardType: TextInputType.number,
      onChanged: (_) => refresh(),
      decoration: const InputDecoration(
        labelText: 'ადგილი',
        border: OutlineInputBorder(),
      ),
    );
  }

  void _applyShapeToTables(
    Set<_EditableTableDefinition> tables,
    RestaurantTableShape shape,
    _EditableZonePlan zone,
  ) {
    for (final table in tables) {
      table.applyShape(
        shape,
        canvasWidth: zone.canvasWidth,
        canvasHeight: zone.canvasHeight,
      );
    }
  }

  void _moveTableSelection(
    _EditableZonePlan zone,
    _EditableTableDefinition draggedTable,
    Set<_EditableTableDefinition> selectedTables, {
    required double dx,
    required double dy,
  }) {
    if (!selectedTables.contains(draggedTable) || selectedTables.length < 2) {
      draggedTable.moveBy(
        dx,
        dy,
        canvasWidth: zone.canvasWidth,
        canvasHeight: zone.canvasHeight,
      );
      return;
    }

    final movableTables = selectedTables.toList();
    final minDx = movableTables
        .map((table) => -table.x)
        .reduce((value, limit) => math.max(value, limit));
    final maxDx = movableTables
        .map((table) => zone.canvasWidth - table.width - table.x)
        .reduce((value, limit) => math.min(value, limit));
    final minDy = movableTables
        .map((table) => -table.y)
        .reduce((value, limit) => math.max(value, limit));
    final maxDy = movableTables
        .map((table) => zone.canvasHeight - table.height - table.y)
        .reduce((value, limit) => math.min(value, limit));
    final clampedDx = dx.clamp(minDx, maxDx).toDouble();
    final clampedDy = dy.clamp(minDy, maxDy).toDouble();

    for (final table in movableTables) {
      table.moveBy(
        clampedDx,
        clampedDy,
        canvasWidth: zone.canvasWidth,
        canvasHeight: zone.canvasHeight,
      );
    }
  }

  void _alignSelectedTables(
    Set<_EditableTableDefinition> tables,
    _EditableZonePlan zone, {
    required Axis axis,
  }) {
    if (tables.length < 2) {
      return;
    }
    final selected = tables.toList()
      ..sort(
        (a, b) =>
            axis == Axis.horizontal ? a.x.compareTo(b.x) : a.y.compareTo(b.y),
      );
    const gap = 18.0;
    if (axis == Axis.horizontal) {
      var cursor = selected.map((table) => table.x).reduce(math.min);
      final y =
          selected.map((table) => table.y).reduce((a, b) => a + b) /
          selected.length;
      for (final table in selected) {
        table.placeAt(
          cursor,
          y,
          canvasWidth: zone.canvasWidth,
          canvasHeight: zone.canvasHeight,
        );
        cursor += table.width + gap;
      }
      return;
    }

    var cursor = selected.map((table) => table.y).reduce(math.min);
    final x =
        selected.map((table) => table.x).reduce((a, b) => a + b) /
        selected.length;
    for (final table in selected) {
      table.placeAt(
        x,
        cursor,
        canvasWidth: zone.canvasWidth,
        canvasHeight: zone.canvasHeight,
      );
      cursor += table.height + gap;
    }
  }

  RestaurantTableShape? _commonTableShape(
    List<_EditableTableDefinition> tables,
  ) {
    if (tables.isEmpty) {
      return null;
    }
    final firstShape = tables.first.shape;
    return tables.every((table) => table.shape == firstShape)
        ? firstShape
        : null;
  }

  List<DropdownMenuItem<RestaurantTableShape>> _tableShapeMenuItems() {
    return const [
      DropdownMenuItem(
        value: RestaurantTableShape.rectangle,
        child: Text('ჩვეულებრივი'),
      ),
      DropdownMenuItem(
        value: RestaurantTableShape.rounded,
        child: Text('მომრგვალებული'),
      ),
      DropdownMenuItem(
        value: RestaurantTableShape.square,
        child: Text('კვადრატი'),
      ),
      DropdownMenuItem(
        value: RestaurantTableShape.circle,
        child: Text('მრგვალი'),
      ),
      DropdownMenuItem(value: RestaurantTableShape.long, child: Text('გრძელი')),
      DropdownMenuItem(value: RestaurantTableShape.booth, child: Text('ბოქსი')),
      DropdownMenuItem(
        value: RestaurantTableShape.barSeat,
        child: Text('ბარის ადგილი'),
      ),
    ];
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
        return Icons.stairs_outlined;
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

class _EditableZonePlan {
  _EditableZonePlan({
    required this.zoneId,
    required this.floorKey,
    required this.displayOrder,
    required this.canvasWidth,
    required this.canvasHeight,
    required String name,
    required this.tables,
    required this.objects,
  }) : nameController = TextEditingController(text: name);

  factory _EditableZonePlan.create(int displayOrder) {
    final floorKey = displayOrder == 1
        ? 'first'
        : displayOrder == 2
        ? 'second'
        : 'floor-$displayOrder';
    return _EditableZonePlan(
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
      tables: [_EditableTableDefinition.create(floorKey, 1, '1')],
      objects: [],
    );
  }

  factory _EditableZonePlan.fromLayout(
    RestaurantTableLayout layout,
    RestaurantZone zone,
  ) {
    final tables = layout.tablesForZone(zone.id);
    return _EditableZonePlan(
      zoneId: zone.id,
      floorKey: zone.legacyFloor,
      displayOrder: zone.displayOrder,
      canvasWidth: zone.canvasWidth ?? _defaultPlanCanvasWidth,
      canvasHeight: zone.canvasHeight ?? _defaultPlanCanvasHeight,
      name: zone.name,
      tables: [
        for (var i = 0; i < tables.length; i++)
          _EditableTableDefinition.fromLayout(
            tables[i],
            layout.objectForTable(tables[i].id),
            i,
          ),
      ],
      objects: [
        for (final object in layout.objectsForZone(zone.id))
          if (object.type != RestaurantLayoutObjectType.table)
            _EditablePlanObject.fromLayout(object),
      ],
    );
  }

  _EditableZonePlan copy() {
    return _EditableZonePlan(
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
  final List<_EditableTableDefinition> tables;
  final List<_EditablePlanObject> objects;

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

  void replaceFrom(_EditableZonePlan other) {
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

class _EditableTableDefinition {
  _EditableTableDefinition({
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

  factory _EditableTableDefinition.create(
    String floor,
    int sortOrder,
    String legacyTableNumber,
  ) {
    final label = floor == 'second'
        ? 'VIP Zone $legacyTableNumber'
        : 'Table $legacyTableNumber';
    final point = _defaultTablePoint(sortOrder - 1);
    final size = _tableSize(RestaurantTableShape.rectangle);
    return _EditableTableDefinition(
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

  factory _EditableTableDefinition.fromLayout(
    RestaurantTableDefinition table,
    RestaurantLayoutObject? object,
    int index,
  ) {
    final shape = object?.tableShape ?? RestaurantTableShape.rectangle;
    final point = _defaultTablePoint(index);
    final size = _tableSize(shape);
    return _EditableTableDefinition(
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

  _EditableTableDefinition copy() {
    return _EditableTableDefinition(
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

  _EditablePlanObject copy() {
    return _EditablePlanObject(
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

  _EditablePlanObject copyWith({
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
    return _EditablePlanObject(
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

class _StepperControl extends StatelessWidget {
  const _StepperControl({
    required this.label,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AdminDesign.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDecrease,
            icon: const Icon(Icons.remove, size: 16),
          ),
          SizedBox(
            width: 58,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminDesign.text,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onIncrease,
            icon: const Icon(Icons.add, size: 16),
          ),
        ],
      ),
    );
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

class _WallDraftPainter extends CustomPainter {
  const _WallDraftPainter({required this.start, required this.end});

  final Offset start;
  final Offset end;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, paint);

    final anchorPaint = Paint()..color = const Color(0xFF22C55E);
    canvas
      ..drawCircle(start, 6, anchorPaint)
      ..drawCircle(end, 5, anchorPaint);
  }

  @override
  bool shouldRepaint(covariant _WallDraftPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}

class _WallSegmentPainter extends CustomPainter {
  const _WallSegmentPainter({
    required this.color,
    required this.borderColor,
    required this.selected,
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
      ..drawLine(
        Offset.zero.translate(0, centerY),
        Offset(size.width, centerY),
        borderPaint,
      )
      ..drawLine(
        Offset.zero.translate(0, centerY),
        Offset(size.width, centerY),
        fillPaint,
      );
  }

  @override
  bool shouldRepaint(covariant _WallSegmentPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.selected != selected;
  }
}

class _WallJoint {
  const _WallJoint({required this.center, required this.radius});

  final Offset center;
  final double radius;
}

class _WallEndpoint {
  const _WallEndpoint({required this.point, required this.radius});

  final Offset point;
  final double radius;
}

class _WallJointsPainter extends CustomPainter {
  const _WallJointsPainter({
    required this.joints,
    required this.color,
    required this.borderColor,
  });

  final List<_WallJoint> joints;
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
  bool shouldRepaint(covariant _WallJointsPainter oldDelegate) {
    return oldDelegate.joints != joints ||
        oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor;
  }
}

class _StairsPainter extends CustomPainter {
  const _StairsPainter(this.color);

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
  bool shouldRepaint(covariant _StairsPainter oldDelegate) {
    return oldDelegate.color != color;
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

_EditablePlanObject? _editableWallFromPoints({
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
  return _EditablePlanObject(
    id: id,
    type: RestaurantLayoutObjectType.wall,
    label: label ?? _labelForType(RestaurantLayoutObjectType.wall),
    x: center.dx - length / 2,
    y: center.dy - thickness / 2,
    width: length,
    height: thickness,
    rotation: math.atan2(vector.dy, vector.dx) * 180 / math.pi,
  );
}

(Offset, Offset) _editableWallEndpoints(_EditablePlanObject wall) {
  final center = Offset(wall.x + wall.width / 2, wall.y + wall.height / 2);
  final angle = wall.rotation * math.pi / 180;
  final half = Offset(math.cos(angle), math.sin(angle)) * (wall.width / 2);
  return (center - half, center + half);
}

List<_WallJoint> _editableWallJoints(
  List<_EditablePlanObject> objects,
  double scale,
) {
  final endpoints = <_WallEndpoint>[];
  for (final object in objects) {
    if (object.type != RestaurantLayoutObjectType.wall) {
      continue;
    }
    final points = _editableWallEndpoints(object);
    final radius = object.height * scale / 2;
    endpoints
      ..add(_WallEndpoint(point: points.$1 * scale, radius: radius))
      ..add(_WallEndpoint(point: points.$2 * scale, radius: radius));
  }

  final used = <int>{};
  final joints = <_WallJoint>[];
  for (var i = 0; i < endpoints.length; i++) {
    if (used.contains(i)) {
      continue;
    }
    final group = <_WallEndpoint>[endpoints[i]];
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
    joints.add(_WallJoint(center: center, radius: radius));
  }
  return joints;
}

String _tableIdFor(String floor, String tableNumber) {
  if (floor == 'second') {
    return 'floor2-table$tableNumber';
  }
  if (floor == 'first') {
    return 'floor1-table$tableNumber';
  }
  return '${_safeId(floor)}-table$tableNumber';
}

String _safeId(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('(^-|-\$)'), '');
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

double _tableRadius(RestaurantTableShape shape) {
  switch (shape) {
    case RestaurantTableShape.circle:
      return 999;
    case RestaurantTableShape.rounded:
    case RestaurantTableShape.booth:
      return 22;
    case RestaurantTableShape.barSeat:
      return 14;
    case RestaurantTableShape.rectangle:
    case RestaurantTableShape.square:
    case RestaurantTableShape.long:
      return 8;
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
