import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_painters.dart';
import 'package:vynic/apps/windows_pos/widgets/home/table_status_presentation.dart';
import 'package:vynic/core/ui/vynic_colors.dart';

class TableSelectionWidget extends StatefulWidget {
  final VoidCallback? onSelectionChanged;
  final Function(TableModel)? onTableTap;
  final int currentFloor;

  /// Fired right after a fresh short tap selects exactly one free table (no
  /// other table already selected) — the fast path: home_screen jumps
  /// straight to the menu instead of requiring a separate "continue" tap.
  /// Building a multi-table selection (long-press, or tapping a further
  /// table once one is already selected) does not fire this.
  final VoidCallback? onQuickEnterTable;

  const TableSelectionWidget({
    super.key,
    this.onSelectionChanged,
    this.onTableTap,
    this.onQuickEnterTable,
    this.currentFloor = 1,
  });

  @override
  State<TableSelectionWidget> createState() => TableSelectionWidgetState();
}

class TableSelectionWidgetState extends State<TableSelectionWidget> {
  static const double _fallbackCanvasWidth = 1000;
  static const double _fallbackCanvasHeight = 620;

  RestaurantTableLayout get _layout =>
      DatabaseService.getRestaurantTableLayout();
  String? selectedTable;
  final Set<String> _selectedTables = {};
  final Set<String> _focusedReservedTables = {};
  String _svgString = '';
  Map<String, Rect> _tablePositions = {};
  int _currentFloor = 1; // Track current floor (1 or 2)
  double _svgWidth = 1005.0;
  double _svgHeight = 1101.0;
  List<TableModel> _tables = [];
  Map<String, Color> _reservationColors =
      {}; // Cached colors per group (reservation/order)

  RestaurantZone get _currentZone =>
      _layout.zoneForDisplayOrder(_currentFloor) ?? _layout.zones.first;

  List<RestaurantTableDefinition> get _currentTableDefinitions =>
      _layout.tablesForZone(_currentZone.id);

  bool get _usesSvgMap =>
      _currentZone.renderMode == TableLayoutRenderMode.svgMap;

  bool get _usesFloorPlan =>
      _currentZone.renderMode == TableLayoutRenderMode.floorPlan;

  // Get current floor's table IDs
  List<String> get tableIds =>
      _currentTableDefinitions.map((table) => table.id).toList();

  @override
  void initState() {
    super.initState();
    _currentFloor = widget.currentFloor;
    _loadTables();
    _loadSvg();
  }

  @override
  void didUpdateWidget(covariant TableSelectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentFloor != oldWidget.currentFloor &&
        widget.currentFloor != _currentFloor) {
      switchFloor(widget.currentFloor);
    }
  }

  void _loadTables() {
    final floor = _currentZone.legacyFloor;
    final tables = DatabaseService.getTablesByFloor(floor);
    final reservationColors = _buildReservationColorMap();

    setState(() {
      _tables = tables;
      _reservationColors = reservationColors;
    });
  }

  TableModel? _getTableModel(String tableId) {
    final tableDefinition = _layout.tableForId(tableId);
    if (tableDefinition == null) {
      return null;
    }

    // Find in cached tables first
    try {
      return _tables.firstWhere(
        (t) =>
            t.tableNumber == tableDefinition.legacyTableNumber &&
            t.floor == tableDefinition.legacyFloor,
      );
    } catch (e) {
      // If not found in cache, query database directly
      return DatabaseService.getTable(
        tableDefinition.legacyTableNumber,
        tableDefinition.legacyFloor,
      );
    }
  }

  String _svgTableIdFor(String tableId) {
    return _layout.tableForId(tableId)?.svgElementId ?? tableId;
  }

  String? _tableNumberFromId(String tableId) {
    return _layout.tableForId(tableId)?.legacyTableNumber;
  }

  String _floorForTableId(String tableId) {
    return _layout.tableForId(tableId)?.legacyFloor ?? _currentZone.legacyFloor;
  }

  String _displayNameForTableId(String tableId) {
    final tableDefinition = _layout.tableForId(tableId);
    if (tableDefinition == null) {
      return tableId;
    }
    return tableDefinition.legacyFloor == 'second'
        ? 'Second Floor Table ${tableDefinition.legacyTableNumber}'
        : tableDefinition.label;
  }

  Future<void> _loadSvg() async {
    final zone = _currentZone;
    if (!_usesSvgMap) {
      setState(() {
        _svgString = '';
        _tablePositions = {};
      });
      return;
    }

    final asset = zone.svgAsset;
    if (asset == null) {
      setState(() {
        _svgString = '';
        _tablePositions = {};
      });
      return;
    }

    final svgString = await rootBundle.loadString(asset);
    final positions = _extractTablePositions();

    _svgWidth = zone.canvasWidth ?? _svgWidth;
    _svgHeight = zone.canvasHeight ?? _svgHeight;

    setState(() {
      _svgString = svgString;
      _tablePositions = positions;
    });
  }

  void switchFloor(int floor) {
    if (floor != _currentFloor && _layout.zoneForDisplayOrder(floor) != null) {
      setState(() {
        _currentFloor = floor;
        _selectedTables.clear();
        _focusedReservedTables.clear();
        selectedTable = null;
      });
      widget.onSelectionChanged?.call();
      _loadTables();
      _loadSvg();
    }
  }

  // Force refresh tables from database (for same floor)
  Future<void> refreshTables() async {
    if (!mounted) {
      return;
    }

    final zone = _currentZone;
    final floor = zone.legacyFloor;
    final tables = DatabaseService.getTablesByFloor(floor);
    final reservationColors = _buildReservationColorMap();

    var svgString = '';
    var positions = <String, Rect>{};
    if (zone.renderMode == TableLayoutRenderMode.svgMap) {
      final asset = zone.svgAsset;
      if (asset != null) {
        svgString = await rootBundle.loadString(asset);
        positions = _extractTablePositions();
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _tables = tables;
      _reservationColors = reservationColors;
      _svgString = svgString;
      _tablePositions = positions;
    });
  }

  Map<String, Rect> _extractTablePositions() {
    final positions = <String, Rect>{};
    for (final table in _currentTableDefinitions) {
      final hitBox = table.hitBox;
      if (hitBox == null) {
        continue;
      }
      positions[table.id] = Rect.fromLTWH(
        hitBox.left,
        hitBox.top,
        hitBox.width,
        hitBox.height,
      );
    }

    // Inflate hitboxes for better touch target size (minimum 48px recommended for touch)
    const double minTouchSize = 48.0;
    const double padding = 8.0; // Extra padding to make touch targets easier

    final Map<String, Rect> inflatedPositions = {};
    positions.forEach((id, rect) {
      final center = rect.center;
      final width = rect.width < minTouchSize ? minTouchSize : rect.width;
      final height = rect.height < minTouchSize ? minTouchSize : rect.height;

      // Add padding to make touch targets more forgiving
      inflatedPositions[id] = Rect.fromCenter(
        center: center,
        width: width + padding,
        height: height + padding,
      );
    });

    return inflatedPositions;
  }

  /// Converts a local tap position (in scaled SVG canvas coordinates) into
  /// the table id at that position, or null if it misses every table.
  String? _svgTableIdAtLocalPosition(
    Offset localPosition,
    double scaleX,
    double scaleY,
  ) {
    final x = localPosition.dx / scaleX;
    final y = localPosition.dy / scaleY;
    for (final entry in _tablePositions.entries) {
      if (entry.value.contains(Offset(x, y))) {
        return entry.key;
      }
    }
    return null;
  }

  Map<String, Color> _buildReservationColorMap() {
    final map = <String, Color>{};
    for (final table in DatabaseService.getAllTables()) {
      final groupKey = _getReservationGroupKey(table);
      if (table.isReserved && groupKey != null) {
        map.putIfAbsent(groupKey, () => _generateColorFromId(groupKey));
      }
    }
    return map;
  }

  String? _getReservationGroupKey(TableModel table) {
    if (table.reservationId != null && table.reservationId!.isNotEmpty) {
      return 'reservation-${table.reservationId}';
    }
    if (table.activeOrderId != null) {
      return 'order-${table.activeOrderId}';
    }
    if (table.isReserved) {
      // Fallback ensures each reserved-but-unlinked table still gets a unique color
      return 'table-${table.floor}-${table.tableNumber}-${table.reservedAt?.millisecondsSinceEpoch ?? 0}';
    }
    return null;
  }

  Color _generateColorFromId(String groupKey) {
    final normalizedHash = groupKey.hashCode & 0x7fffffff;
    final hue = (normalizedHash % 360).toDouble();
    final saturation = 0.55 + ((normalizedHash >> 3) % 35) / 100; // 0.55 - 0.9
    final lightness = 0.45 + ((normalizedHash >> 5) % 20) / 100; // 0.45 - 0.65
    return HSLColor.fromAHSL(
      0.85,
      hue,
      saturation.clamp(0.0, 1.0),
      lightness.clamp(0.0, 1.0),
    ).toColor();
  }

  Color _getReservationColor(TableModel table) {
    final groupKey = _getReservationGroupKey(table);
    if (groupKey != null) {
      return _reservationColors[groupKey] ?? _generateColorFromId(groupKey);
    }
    return Colors.red;
  }

  String _colorToHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  String _modifySvgForSelection(String svgString) {
    if (svgString.isEmpty) return svgString;

    final document = XmlDocument.parse(svgString);

    // Find and modify each table group
    for (final tableId in tableIds) {
      final svgTableId = _svgTableIdFor(tableId);
      final elements = document
          .findAllElements('g')
          .where((element) => element.getAttribute('id') == svgTableId);

      final tableModel = _getTableModel(tableId);
      final isReserved = tableModel?.isReserved ?? false;

      for (final element in elements) {
        // Find all path elements within this table group
        final paths = element.findAllElements('path');
        for (final path in paths) {
          if (isReserved) {
            // Reserved state - unique color per reservation/order group (highest priority)
            final color = tableModel != null
                ? _getReservationColor(tableModel)
                : Colors.red;
            path.setAttribute('fill', _colorToHex(color));
            path.setAttribute('fill-opacity', '0.8');
          } else if (_selectedTables.contains(tableId)) {
            // Selected state - green color
            path.setAttribute('fill', '#047857');
            path.setAttribute('fill-opacity', '0.7');
          } else {
            // Default state - white to be more visible
            path.setAttribute('fill', '#FFFFFF');
            path.setAttribute('fill-opacity', '1');
          }
        }
      }
    }

    return document.toXmlString();
  }

  void _handleTableTap(String tableId) {
    final tableModel = _getTableModel(tableId);

    // Reserved/occupied tables open immediately — no separate "continue"
    // step. Tables sharing the same reservation/order (e.g. two tables
    // pushed together for one party) are grouped by reservation/order key
    // and all get the focus highlight, but `onTableTap` only needs the
    // tapped table: `_handleReservedTableTap` reads its shared
    // activeOrderId/reservationId, which is identical across the whole
    // group, so opening any one of them opens the shared order for all.
    if (tableModel != null && tableModel.isReserved) {
      final groupKey = _getReservationGroupKey(tableModel);
      final groupedTableIds = tableIds.where((candidateId) {
        final candidateTable = _getTableModel(candidateId);
        if (candidateTable == null || !candidateTable.isReserved) {
          return false;
        }
        if (groupKey == null) {
          return candidateId == tableId;
        }
        return _getReservationGroupKey(candidateTable) == groupKey;
      }).toSet();
      final nextFocusedTableIds = groupedTableIds.isEmpty
          ? {tableId}
          : groupedTableIds;

      setState(() {
        _selectedTables.clear();
        _focusedReservedTables
          ..clear()
          ..addAll(nextFocusedTableIds);
        selectedTable = tableId;
      });
      widget.onSelectionChanged?.call();
      widget.onTableTap?.call(tableModel);
      return;
    }

    // Free table. If the waiter is already mid-way through building a
    // multi-table selection (started via long-press, or a previous tap that
    // already picked one table), a further tap just adds/removes from that
    // set — it must not discard progress or auto-navigate. Only a tap from a
    // completely clean slate takes the fast, single-tap-opens-the-table path.
    final buildingMultiSelect =
        _selectedTables.isNotEmpty && !_selectedTables.contains(tableId);
    // Tapping any already-selected table (whether it's the only one or one of
    // several) removes just that table from the set instead of navigating —
    // e.g. selecting 1, 2, 3 then tapping 3 again drops 3 and keeps 1, 2.
    final togglingOffASelectedTable =
        _selectedTables.isNotEmpty && _selectedTables.contains(tableId);

    if (buildingMultiSelect) {
      setState(() {
        _focusedReservedTables.clear();
        _selectedTables.add(tableId);
        selectedTable = tableId;
      });
      widget.onSelectionChanged?.call();
      return;
    }

    if (togglingOffASelectedTable) {
      setState(() {
        _selectedTables.remove(tableId);
        if (selectedTable == tableId) {
          selectedTable = _selectedTables.isNotEmpty
              ? _selectedTables.last
              : null;
        }
      });
      widget.onSelectionChanged?.call();
      return;
    }

    setState(() {
      _focusedReservedTables.clear();
      _selectedTables
        ..clear()
        ..add(tableId);
      selectedTable = tableId;
    });
    widget.onSelectionChanged?.call();
    widget.onQuickEnterTable?.call();
  }

  /// Long-press on a free table toggles it into/out of a multi-table
  /// selection without auto-navigating — the deliberate path for merging
  /// several free tables into one order. Reserved/occupied tables ignore
  /// long-press; short tap already handles their quick-overview flow.
  void _handleTableLongPress(String tableId) {
    final tableModel = _getTableModel(tableId);
    if (tableModel != null && tableModel.isReserved) {
      return;
    }

    setState(() {
      _focusedReservedTables.clear();
      if (_selectedTables.contains(tableId)) {
        _selectedTables.remove(tableId);
        if (selectedTable == tableId) {
          selectedTable = null;
        }
      } else {
        _selectedTables.add(tableId);
        selectedTable = tableId;
      }
    });
    widget.onSelectionChanged?.call();
  }

  // Public method to clear all selections
  void clearSelection() {
    setState(() {
      _selectedTables.clear();
      _focusedReservedTables.clear();
      selectedTable = null;
    });
    widget.onSelectionChanged?.call();
  }

  Widget _buildTableOverlay() {
    if (_tablePositions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: _tablePositions.entries.map((entry) {
        final tableModel = _getTableModel(entry.key);
        final presentation = TableStatusPresentation.of(tableModel);
        final isReserved = presentation.isBusy;
        final isSelected = _selectedTables.contains(entry.key);
        final isFocused = _focusedReservedTables.contains(entry.key);
        final Color? reservationColor = isReserved && tableModel != null
            ? _getReservationColor(tableModel)
            : null;

        Reservation? reservation;
        if (tableModel?.reservationId != null) {
          reservation = DatabaseService.findReservationById(
            tableModel!.reservationId!,
          );
        }

        if (reservation == null && tableModel?.activeOrderId != null) {
          final order = DatabaseService.getOrder(tableModel!.activeOrderId!);
          if (order != null) {
            reservation = DatabaseService.findReservationForOrder(order);
          }
        }

        final note = reservation?.notes?.trim();

        return Positioned(
          left: entry.value.left,
          top: entry.value.top,
          width: entry.value.width,
          height: entry.value.height,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isReserved
                    ? (reservationColor ?? Colors.red).withValues(
                        alpha: isFocused ? 0.86 : 0.68,
                      ) // Unique per reservation/order group
                    : isSelected
                    ? const Color(0xFF047857).withValues(alpha: 0.68)
                    : Colors.transparent,
                border: Border.all(
                  color: isReserved
                      ? (isFocused
                            ? const Color(0xFF0F172A)
                            : (reservationColor ?? Colors.red))
                      : isSelected
                      ? const Color(0xFF047857)
                      : Colors.grey.withValues(
                          alpha: 0.15,
                        ), // Very subtle border
                  width: isFocused
                      ? 4
                      : isReserved
                      ? 3
                      : isSelected
                      ? 2
                      : 0.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isReserved)
                      Icon(
                        isFocused ? Icons.visibility : presentation.icon,
                        color: Colors.white,
                        size: isFocused ? 30 : 28,
                      )
                    else if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 32,
                      ),
                    if (isReserved || isSelected) const SizedBox(height: 4),
                    // Show table number or VIP zone label - larger for touch
                    Text(
                      'T${_tableNumberFromId(entry.key) ?? entry.key}',
                      style: TextStyle(
                        color: (isReserved || isSelected)
                            ? Colors.white
                            : Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isReserved) ...[
                      const SizedBox(height: 2),
                      Text(
                        presentation.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (note != null && note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'ნოუთი: $note',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // Expose current floor getter for home screen to show floor buttons
  int get currentFloor => _currentFloor;

  // Expose selected tables list for navigation to menu
  List<String> get selectedTables =>
      _selectedTables.map(_displayNameForTableId).toList();

  List<TableModel> get selectedTableModels => _selectedTables
      .map(_getTableModel)
      .whereType<TableModel>()
      .toList(growable: false);

  List<TableModel> get focusedReservedTables => _focusedReservedTables
      .map(_getTableModel)
      .whereType<TableModel>()
      .toList(growable: false);

  TableModel? get focusedReservedTable =>
      focusedReservedTables.isEmpty ? null : focusedReservedTables.first;

  bool get hasMixedFloorSelection {
    final selectedFloors = _selectedTables.map(_floorForTableId).toSet();
    return selectedFloors.length > 1;
  }

  // Expose selected tables for display in home screen
  String get selectedTablesText {
    if (_selectedTables.isEmpty) return 'None';
    return _selectedTables.map(_displayNameForTableId).join(', ');
  }

  Widget _buildSvgFloorPlan() {
    if (_svgString.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFC0AD7B)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use dynamic SVG dimensions based on current floor
        final svgWidth = _svgWidth;
        final svgHeight = _svgHeight;
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        // Aspect-ratio preserved (uniform scale), not stretched — stretching
        // was tried and reverted: it made the POS floor plan look visibly
        // different from the same layout shown true-to-scale in the admin
        // layout editor, which was more confusing than the empty side
        // margins it was meant to fix.
        final rawScaleX = availableWidth / svgWidth;
        final rawScaleY = availableHeight / svgHeight;
        final scale = rawScaleX < rawScaleY ? rawScaleX : rawScaleY;

        final scaledWidth = svgWidth * scale;
        final scaledHeight = svgHeight * scale;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: scaledWidth,
            height: scaledHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // Better touch detection
              onTapUp: (details) {
                final tableId = _svgTableIdAtLocalPosition(
                  details.localPosition,
                  scale,
                  scale,
                );
                if (tableId != null) {
                  _handleTableTap(tableId);
                }
              },
              onLongPressStart: (details) {
                final tableId = _svgTableIdAtLocalPosition(
                  details.localPosition,
                  scale,
                  scale,
                );
                if (tableId != null) {
                  _handleTableLongPress(tableId);
                }
              },
              child: Stack(
                children: [
                  // SVG Background
                  SizedBox(
                    width: scaledWidth,
                    height: scaledHeight,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.topLeft,
                      child: Builder(
                        builder: (context) {
                          final modifiedSvg = _modifySvgForSelection(
                            _svgString,
                          );
                          return SizedBox(
                            width: svgWidth,
                            height: svgHeight,
                            // Key on the rendered content so the raster is
                            // rebuilt the moment table colors change.
                            child: SvgPicture.string(
                              modifiedSvg,
                              key: ValueKey<int>(modifiedSvg.hashCode),
                              fit: BoxFit.fill,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // Interactive overlay
                  SizedBox(
                    width: scaledWidth,
                    height: scaledHeight,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: svgWidth,
                        height: svgHeight,
                        child: _buildTableOverlay(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloorPlan() {
    final canvasWidth = _currentZone.canvasWidth ?? _fallbackCanvasWidth;
    final canvasHeight = _currentZone.canvasHeight ?? _fallbackCanvasHeight;
    final objects = _floorPlanObjectsForCurrentZone();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Aspect-ratio preserved (uniform scale), not stretched — stretching
        // was tried and reverted: it made the POS floor plan look visibly
        // different from the same layout shown true-to-scale in the admin
        // layout editor, which was more confusing than the empty side
        // margins it was meant to fix.
        final rawScaleX = constraints.maxWidth / canvasWidth;
        final rawScaleY = constraints.maxHeight / canvasHeight;
        final scale = rawScaleX < rawScaleY ? rawScaleX : rawScaleY;
        final scaledWidth = canvasWidth * scale;
        final scaledHeight = canvasHeight * scale;

        return Align(
          alignment: Alignment.topCenter,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: scaledWidth,
              height: scaledHeight,
              child: ColoredBox(
                color: const Color(0xFFF8FAFC),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: FloorPlanGridPainter()),
                    ),
                    ..._buildConnectedReservationBands(objects, scale, scale),
                    for (final object in objects)
                      if (object.type != RestaurantLayoutObjectType.table)
                        _buildFloorPlanObject(object, scale, scale),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: FloorPlanWallJointsPainter(
                            joints: floorPlanWallJoints(
                              _wallSegmentsOf(objects),
                              scale,
                              scale,
                            ),
                            color: _floorPlanObjectColors(
                              const RestaurantLayoutObject(
                                id: 'wall-color',
                                zoneId: 'wall-color',
                                type: RestaurantLayoutObjectType.wall,
                                label: 'Wall',
                                x: 0,
                                y: 0,
                                width: 1,
                                height: 1,
                              ),
                            ).$1,
                            borderColor: _floorPlanObjectColors(
                              const RestaurantLayoutObject(
                                id: 'wall-border',
                                zoneId: 'wall-border',
                                type: RestaurantLayoutObjectType.wall,
                                label: 'Wall',
                                x: 0,
                                y: 0,
                                width: 1,
                                height: 1,
                              ),
                            ).$2,
                          ),
                        ),
                      ),
                    ),
                    for (final object in objects)
                      if (object.type == RestaurantLayoutObjectType.table &&
                          object.tableId != null)
                        _buildFloorPlanTable(object, scale, scale),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<RestaurantLayoutObject> _floorPlanObjectsForCurrentZone() {
    final objects = _layout.objectsForZone(_currentZone.id);
    final objectTableIds = objects
        .where((object) => object.type == RestaurantLayoutObjectType.table)
        .map((object) => object.tableId)
        .whereType<String>()
        .toSet();

    return [
      ...objects,
      for (var i = 0; i < _currentTableDefinitions.length; i++)
        if (!objectTableIds.contains(_currentTableDefinitions[i].id))
          _fallbackTableObject(_currentTableDefinitions[i], i),
    ];
  }

  RestaurantLayoutObject _fallbackTableObject(
    RestaurantTableDefinition table,
    int index,
  ) {
    const columns = 4;
    const cellWidth = 210.0;
    const cellHeight = 130.0;
    return RestaurantLayoutObject(
      id: '${table.id}-fallback-visual',
      zoneId: table.zoneId,
      type: RestaurantLayoutObjectType.table,
      label: table.label,
      x: 70 + (index % columns) * cellWidth,
      y: 70 + (index ~/ columns) * cellHeight,
      width: 130,
      height: 86,
      sortOrder: table.sortOrder,
      tableId: table.id,
      tableShape: RestaurantTableShape.rectangle,
    );
  }

  List<Widget> _buildConnectedReservationBands(
    List<RestaurantLayoutObject> objects,
    double scaleX,
    double scaleY,
  ) {
    final grouped = <String, List<RestaurantLayoutObject>>{};
    for (final object in objects) {
      final tableId = object.tableId;
      if (object.type != RestaurantLayoutObjectType.table || tableId == null) {
        continue;
      }
      final table = _getTableModel(tableId);
      final groupKey = table == null ? null : _getReservationGroupKey(table);
      if (table == null || !table.isReserved || groupKey == null) {
        continue;
      }
      grouped.putIfAbsent(groupKey, () => []).add(object);
    }

    final bands = <Widget>[];
    for (final entry in grouped.entries) {
      for (final component in _nearbyTableComponents(entry.value)) {
        if (component.length < 2) {
          continue;
        }
        final color =
            _reservationColors[entry.key] ?? _generateColorFromId(entry.key);
        final union = _unionForObjects(component).inflate(18);
        bands.add(
          Positioned(
            left: union.left * scaleX,
            top: union.top * scaleY,
            width: union.width * scaleX,
            height: union.height * scaleY,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: color.withValues(alpha: 0.58),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return bands;
  }

  List<List<RestaurantLayoutObject>> _nearbyTableComponents(
    List<RestaurantLayoutObject> objects,
  ) {
    final remaining = {...objects};
    final components = <List<RestaurantLayoutObject>>[];
    while (remaining.isNotEmpty) {
      final start = remaining.first;
      final queue = <RestaurantLayoutObject>[start];
      final component = <RestaurantLayoutObject>[];
      remaining.remove(start);

      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        component.add(current);
        final neighbors = remaining
            .where((candidate) => _tableGap(current, candidate) <= 90)
            .toList();
        for (final neighbor in neighbors) {
          remaining.remove(neighbor);
          queue.add(neighbor);
        }
      }
      components.add(component);
    }
    return components;
  }

  double _tableGap(RestaurantLayoutObject a, RestaurantLayoutObject b) {
    final dx = math.max(
      0,
      (a.x + a.width / 2 - b.x - b.width / 2).abs() - (a.width + b.width) / 2,
    );
    final dy = math.max(
      0,
      (a.y + a.height / 2 - b.y - b.height / 2).abs() -
          (a.height + b.height) / 2,
    );
    return math.sqrt(dx * dx + dy * dy);
  }

  Rect _unionForObjects(List<RestaurantLayoutObject> objects) {
    var left = objects.first.x;
    var top = objects.first.y;
    var right = objects.first.x + objects.first.width;
    var bottom = objects.first.y + objects.first.height;
    for (final object in objects.skip(1)) {
      left = math.min(left, object.x);
      top = math.min(top, object.y);
      right = math.max(right, object.x + object.width);
      bottom = math.max(bottom, object.y + object.height);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Widget _buildFloorPlanTable(
    RestaurantLayoutObject object,
    double scaleX,
    double scaleY,
  ) {
    final tableId = object.tableId!;
    final tableModel = _getTableModel(tableId);
    final presentation = TableStatusPresentation.of(tableModel);
    final isBusy = presentation.isBusy;
    final isSelected = _selectedTables.contains(tableId);
    final isFocused = _focusedReservedTables.contains(tableId);
    final reservationColor = isBusy && tableModel != null
        ? _getReservationColor(tableModel)
        : null;

    Color backgroundColor;
    Color borderColor;
    Color textColor;
    IconData icon;

    if (isBusy) {
      backgroundColor = (reservationColor ?? Colors.red).withValues(
        alpha: isFocused ? 0.94 : 0.82,
      );
      borderColor = isFocused
          ? const Color(0xFF0F172A)
          : (reservationColor ?? Colors.red);
      textColor = Colors.white;
      icon = isFocused ? Icons.visibility : presentation.icon;
    } else if (isSelected) {
      backgroundColor = const Color(0xFF047857);
      borderColor = const Color(0xFF065F46);
      textColor = Colors.white;
      icon = Icons.check_circle;
    } else {
      backgroundColor = VynicColors.cardSoft;
      borderColor = VynicColors.borderStrong;
      textColor = VynicColors.textPrimary;
      icon = Icons.table_restaurant;
    }

    final label = _displayNameForTableId(tableId);

    return Positioned(
      left: object.x * scaleX,
      top: object.y * scaleY,
      width: object.width * scaleX,
      height: object.height * scaleY,
      child: GestureDetector(
        onTap: () => _handleTableTap(tableId),
        onLongPress: () => _handleTableLongPress(tableId),
        child: Transform.rotate(
          angle: object.rotation * math.pi / 180,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: _floorPlanTableDecoration(
              shape: object.tableShape,
              color: backgroundColor,
              borderColor: borderColor,
              focused: isFocused,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              // FittedBox+scaleDown so a table box that's too short for its
              // icon+label+status text (e.g. at 1024×768, where the whole
              // canvas scales down) shrinks the content instead of
              // overflowing — it only ever shrinks, never enlarges past the
              // content's natural size.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: textColor, size: isFocused ? 24 : 20),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (isBusy) ...[
                      const SizedBox(height: 2),
                      Text(
                        presentation.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloorPlanObject(
    RestaurantLayoutObject object,
    double scaleX,
    double scaleY,
  ) {
    final colors = _floorPlanObjectColors(object);
    return Positioned(
      left: object.x * scaleX,
      top: object.y * scaleY,
      width: object.width * scaleX,
      height: object.height * scaleY,
      child: Transform.rotate(
        angle: object.rotation * math.pi / 180,
        child: object.type == RestaurantLayoutObjectType.wall
            ? CustomPaint(
                painter: FloorPlanWallSegmentPainter(
                  color: colors.$1,
                  borderColor: colors.$2,
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.$1,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.$2, width: 1.5),
                ),
                child: Stack(
                  children: [
                    if (object.type == RestaurantLayoutObjectType.stairs)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FloorPlanStairsPainter(colors.$2),
                        ),
                      ),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _floorPlanObjectIcon(object.type),
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
                  ],
                ),
              ),
      ),
    );
  }

  BoxDecoration _floorPlanTableDecoration({
    required RestaurantTableShape shape,
    required Color color,
    required Color borderColor,
    required bool focused,
  }) {
    return BoxDecoration(
      color: color,
      border: Border.all(color: borderColor, width: focused ? 3 : 2),
      borderRadius: BorderRadius.circular(_floorPlanTableRadius(shape)),
      boxShadow: [
        BoxShadow(
          color: borderColor.withValues(alpha: focused ? 0.28 : 0.16),
          blurRadius: focused ? 16 : 10,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  (Color, Color, Color) _floorPlanObjectColors(RestaurantLayoutObject object) {
    switch (object.type) {
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

  IconData _floorPlanObjectIcon(RestaurantLayoutObjectType type) {
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

  Widget _buildButtonGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 4
            : width >= 620
            ? 3
            : 2;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
          ),
          itemCount: tableIds.length,
          itemBuilder: (context, index) {
            return _buildTableButton(tableIds[index]);
          },
        );
      },
    );
  }

  Widget _buildTableButton(String tableId) {
    final tableModel = _getTableModel(tableId);
    final presentation = TableStatusPresentation.of(tableModel);
    final isReserved = presentation.isBusy;
    final isSelected = _selectedTables.contains(tableId);
    final isFocused = _focusedReservedTables.contains(tableId);
    final reservationColor = isReserved && tableModel != null
        ? _getReservationColor(tableModel)
        : null;

    Color backgroundColor;
    Color borderColor;
    Color textColor;
    IconData icon;

    if (isReserved) {
      backgroundColor = (reservationColor ?? Colors.red).withValues(
        alpha: isFocused ? 0.92 : 0.78,
      );
      borderColor = isFocused
          ? const Color(0xFF0F172A)
          : (reservationColor ?? Colors.red);
      textColor = Colors.white;
      icon = isFocused ? Icons.visibility : presentation.icon;
    } else if (isSelected) {
      backgroundColor = const Color(0xFF047857);
      borderColor = const Color(0xFF065F46);
      textColor = Colors.white;
      icon = Icons.check_circle;
    } else {
      backgroundColor = VynicColors.cardSoft;
      borderColor = VynicColors.border;
      textColor = VynicColors.textPrimary;
      icon = Icons.table_restaurant;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _handleTableTap(tableId),
        onLongPress: () => _handleTableLongPress(tableId),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: borderColor, width: isFocused ? 3 : 1.5),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              if (isFocused || isSelected)
                BoxShadow(
                  color: borderColor.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: textColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _displayNameForTableId(tableId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isReserved
                          ? presentation.label
                          : isSelected
                          ? 'არჩეულია'
                          : _currentZone.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _usesSvgMap
              ? _buildSvgFloorPlan()
              : _usesFloorPlan
              ? _buildFloorPlan()
              : _buildButtonGrid(),
        ),
      ],
    );
  }
}

double _floorPlanTableRadius(RestaurantTableShape shape) {
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

List<FloorPlanWallSegment> _wallSegmentsOf(
  List<RestaurantLayoutObject> objects,
) {
  return [
    for (final object in objects)
      if (object.type == RestaurantLayoutObjectType.wall)
        (
          x: object.x,
          y: object.y,
          width: object.width,
          height: object.height,
          rotation: object.rotation,
        ),
  ];
}
