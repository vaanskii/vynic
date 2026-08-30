import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_operational_status.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_grouping.dart';
import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_names.dart';
import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_painters.dart';
import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_seats.dart';
import 'package:vynic/apps/windows_pos/widgets/home/table_status_presentation.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_status_tokens.dart';

class TableSelectionWidget extends StatefulWidget {
  final VoidCallback? onSelectionChanged;
  final Function(TableModel)? onTableTap;
  final int currentFloor;
  final PosTableTileSize tableTileSize;
  final PosLayoutClass layoutClass;

  /// Draws the alignment grid behind the floor plan. When off, the plan's
  /// own background fill is dropped too, so it sits transparently on the
  /// panel behind it rather than on a second surface.
  final bool showFloorPlanGrid;

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
    this.tableTileSize = PosTableTileSize.automatic,
    this.layoutClass = PosLayoutClass.md,
    this.showFloorPlanGrid = true,
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
  int _currentFloor = 1; // Track current floor (1 or 2)
  List<TableModel> _tables = [];
  Map<String, Color> _reservationColors =
      {}; // Cached colors per group (reservation/order)

  RestaurantZone get _currentZone =>
      _layout.zoneForDisplayOrder(_currentFloor) ?? _layout.zones.first;

  List<RestaurantTableDefinition> get _currentTableDefinitions =>
      _layout.tablesForZone(_currentZone.id);

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

  String? _tableNumberFromId(String tableId) {
    return _layout.tableForId(tableId)?.legacyTableNumber;
  }

  String _floorForTableId(String tableId) {
    return _layout.tableForId(tableId)?.legacyFloor ?? _currentZone.legacyFloor;
  }

  /// What a table is *called* — whatever was typed into the floor editor.
  ///
  /// This used to synthesise 'Second Floor Table N' for the upstairs zone,
  /// which threw away the name the admin had set. The layout owns the name for
  /// every floor now; identity still travels as (floor, tableNumber).
  String _displayNameForTableId(String tableId) {
    final tableDefinition = _layout.tableForId(tableId);
    if (tableDefinition == null) {
      return tableId;
    }
    return floorPlanTableNameOrNumber(
      _layout,
      floor: tableDefinition.legacyFloor,
      tableNumber: tableDefinition.legacyTableNumber,
    );
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

    if (!mounted) {
      return;
    }

    setState(() {
      _tables = tables;
      _reservationColors = reservationColors;
    });
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

  Order? _activeOrderForTable(TableModel? table) {
    final orderId = table?.activeOrderId;
    if (orderId == null) return null;
    return DatabaseService.getOrder(orderId);
  }

  ({String label, IconData icon, VynicStatusTone tone}) _serviceMetaFor(
    TableModel? table,
    Order? order,
    TableStatusPresentation presentation,
  ) {
    if (order != null && order.statusEnum == OrderStatus.served) {
      return (
        label: 'გადასახდელი',
        icon: Icons.payments_outlined,
        tone: VynicStatusTone.danger,
      );
    }
    if (presentation.status == TableOperationalStatus.reserved) {
      return (
        label: presentation.label,
        icon: presentation.icon,
        tone: VynicStatusTone.warning,
      );
    }
    if (presentation.status == TableOperationalStatus.occupied) {
      return (
        label: presentation.label,
        icon: presentation.icon,
        tone: VynicStatusTone.info,
      );
    }
    return (
      label: 'თავისუფალი',
      icon: Icons.table_restaurant_outlined,
      tone: VynicStatusTone.neutral,
    );
  }

  String? _tableMetaLine(TableModel? table, Order? order) {
    if (order != null) {
      final bill = order.totalAmount > 0
          ? _formatMoney(order.totalAmount)
          : null;
      final elapsed = _elapsedSince(order.createdAt);
      final waiter = order.openedByUserId?.trim().isNotEmpty == true
          ? order.openedByUserId!.trim()
          : order.createdBy.trim();
      final parts = [
        if (bill != null) bill,
        elapsed,
        if (waiter.isNotEmpty) waiter,
      ];
      return parts.join(' · ');
    }
    if (table?.reservedBy?.trim().isNotEmpty == true) {
      final elapsed = table?.reservedAt == null
          ? null
          : _elapsedSince(table!.reservedAt!);
      return [
        table!.reservedBy!.trim(),
        if (elapsed != null) elapsed,
      ].join(' · ');
    }
    return null;
  }

  String _formatMoney(double amount) {
    return '${amount.toStringAsFixed(2)} ₾';
  }

  String _elapsedSince(DateTime startedAt) {
    // Business clock, not the wall clock: orders carry the business date with
    // the current time of day, so DateTime.now() measures the gap between the
    // two calendars whenever the venue's business day is not today.
    final elapsed = DatabaseService.getCurrentDateTime().difference(startedAt);
    if (elapsed.inMinutes < 1) return 'ახლახან';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} წთ';
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${elapsed.inHours}:$minutes';
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
      if (!_selectionWouldStayContiguous({..._selectedTables, tableId})) {
        _warnSelectionNotAdjacent();
        return;
      }
      setState(() {
        _focusedReservedTables.clear();
        _selectedTables.add(tableId);
        selectedTable = tableId;
      });
      widget.onSelectionChanged?.call();
      return;
    }

    if (togglingOffASelectedTable) {
      final remaining = {..._selectedTables}..remove(tableId);
      if (!_selectionWouldStayContiguous(remaining)) {
        // Dropping a table from the middle would split the party in two.
        _warnSelectionNotAdjacent();
        return;
      }
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

    final next = {..._selectedTables};
    if (!next.remove(tableId)) {
      next.add(tableId);
    }
    if (!_selectionWouldStayContiguous(next)) {
      _warnSelectionNotAdjacent();
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

  /// A party can only be seated across tables that are physically pushed
  /// together, so a multi-table selection has to stay one contiguous run:
  /// tables 1 and 3 with table 2 between them is not a seating a waiter could
  /// actually set up.
  ///
  /// Only enforced on real floor plans. Button-grid and SVG zones get their
  /// geometry from an arbitrary fallback grid, where adjacency would be
  /// meaningless.
  bool _selectionWouldStayContiguous(Set<String> nextSelection) {
    if (!_usesFloorPlan || nextSelection.length < 2) {
      return true;
    }

    final multiplier = _tableSizeMultiplier();
    final all = <FloorPlanGroupCandidate>[];
    final chosen = <FloorPlanGroupCandidate>[];
    for (final object in _floorPlanObjectsForCurrentZone()) {
      final id = object.tableId;
      if (object.type != RestaurantLayoutObjectType.table || id == null) {
        continue;
      }
      final candidate = (
        id: id,
        rect: Rect.fromCenter(
          center: Offset(
            object.x + object.width / 2,
            object.y + object.height / 2,
          ),
          width: object.width * multiplier,
          height: object.height * multiplier,
        ),
      );
      all.add(candidate);
      if (nextSelection.contains(id)) {
        chosen.add(candidate);
      }
    }

    return floorPlanSelectionIsContiguous(selected: chosen, obstacles: all);
  }

  void _warnSelectionNotAdjacent() {
    unawaited(
      showPosToast(
        context: context,
        message: 'აირჩიეთ მხოლოდ გვერდიგვერდ მდგომი მაგიდები',
        style: PosToastStyle.info,
      ),
    );
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

  // Expose current floor getter for home screen to show floor buttons
  int get currentFloor => _currentFloor;

  // Expose selected tables list for navigation to menu
  List<String> get selectedTables =>
      _selectedTables.map(_displayNameForTableId).toList();

  /// The identity behind [selectedTables], in the same order.
  ///
  /// Names are free text now, so the menu screen can no longer recover a table
  /// number by stripping 'Table ' off a display name — it has to be handed the
  /// real one.
  List<String> get selectedTableNumbers => _selectedTables
      .map((id) => _tableNumberFromId(id))
      .whereType<String>()
      .toList(growable: false);

  /// Legacy floor of the current selection, or null when nothing is selected.
  ///
  /// [hasMixedFloorSelection] is what guards against a selection that spans
  /// floors, so this reports the first one.
  String? get selectedFloor {
    for (final id in _selectedTables) {
      return _floorForTableId(id);
    }
    return null;
  }

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
        // Fit what is actually on the plan, not the editor's working area.
        // The built-in canvas is 1005x1101 with everything in the upper part
        // of it; fitting that whole box into a landscape panel binds on the
        // height and throws away about a third of the scale, on top of the
        // app's own. Cropping to the content keeps the scale that legibility
        // depends on, and it is still a uniform fit — nothing is stretched.
        final content = floorPlanContentBounds(
          objects,
          Size(canvasWidth, canvasHeight),
        );
        final rawScaleX = constraints.maxWidth / content.width;
        final rawScaleY = constraints.maxHeight / content.height;
        final fitted = rawScaleX < rawScaleY ? rawScaleX : rawScaleY;
        // A nearly empty floor would otherwise blow two tables up to fill the
        // panel; a plan should never read as more zoomed-in than its own
        // design size by much.
        final scale = math.min(fitted, maxFloorPlanZoom);
        final scaledWidth = content.width * scale;
        final scaledHeight = content.height * scale;
        final clusters = _buildTableClusters(objects);

        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: scaledWidth,
            height: scaledHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              // Off-white against the white panel, with its own hairline —
              // the plan reads as a surface rather than a hole in the card.
              color: widget.showFloorPlanGrid
                  ? VynicFloorTokens.canvas
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(
                VynicFloorTokens.canvasRadius,
              ),
              border: widget.showFloorPlanGrid
                  ? Border.all(color: VynicFloorTokens.canvasBorder)
                  : null,
            ),
            // The inner stack keeps the plan's own coordinate space — every
            // child is still positioned at `x * scale` — and is slid so the
            // content box lands on the container's origin. Cropping here
            // rather than in each child's arithmetic leaves the positioning
            // maths and the full-canvas painters (grid, seats, walls)
            // untouched.
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -content.left * scale,
                  top: -content.top * scale,
                  width: canvasWidth * scale,
                  height: canvasHeight * scale,
                  child: Stack(
                    children: [
                      if (widget.showFloorPlanGrid)
                        Positioned.fill(
                          child: CustomPaint(painter: FloorPlanGridPainter()),
                        ),
                      // Chairs get their own layer: table tiles are positioned
                      // widgets that clip to their own box, and seat marks sit
                      // just outside it.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: FloorPlanSeatsPainter(
                              tables: _seatedTables(clusters),
                              scale: scale,
                              color: VynicFloorTokens.freeDot,
                            ),
                          ),
                        ),
                      ),
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
                      for (final cluster in clusters)
                        _buildTableCluster(cluster, scale),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableCluster(_TableCluster cluster, double scale) {
    if (!cluster.isMerged) {
      return _buildFloorPlanTable(cluster.objects.first, scale, scale);
    }
    return _buildMergedTable(cluster, scale);
  }

  /// A run of joined tables, drawn as one big table.
  Widget _buildMergedTable(_TableCluster cluster, double scale) {
    final models = [
      for (final id in cluster.tableIds)
        if (_getTableModel(id) case final TableModel model) model,
    ];
    final busyModel = models.firstWhere(
      (model) => model.isReserved,
      orElse: () => models.isEmpty
          ? TableModel(tableNumber: '', floor: _currentZone.legacyFloor)
          : models.first,
    );
    final isBusy = models.any((model) => model.isReserved);
    final isSelected = cluster.tableIds.every(_selectedTables.contains);
    final isFocused = cluster.tableIds.any(_focusedReservedTables.contains);
    final order = _activeOrderForTable(
      models.firstWhere(
        (model) => model.activeOrderId != null,
        orElse: () => busyModel,
      ),
    );

    // Each party gets its own hue, so two joined runs on the same floor are
    // told apart at a glance rather than all reading as one warm colour.
    final groupColor = isBusy ? _getReservationColor(busyModel) : null;

    final Color fill;
    final Color border;
    final Color dot;
    if (isSelected && !isBusy) {
      fill = VynicFloorTokens.accentSoft;
      border = VynicFloorTokens.accentBadgeText;
      dot = VynicFloorTokens.accentText;
    } else if (isBusy) {
      fill = VynicFloorTokens.occupiedFill;
      border = groupColor ?? VynicFloorTokens.occupiedBorder;
      dot = groupColor ?? VynicFloorTokens.occupiedDot;
    } else {
      fill = VynicFloorTokens.tileFill;
      border = VynicFloorTokens.tileBorder;
      dot = VynicFloorTokens.freeDot;
    }

    // Names, not numbers: a run of renamed tables should read
    // „ფანჯარასთან + კუთხე", not „3 + 4".
    final numbers = [
      for (final id in cluster.tableIds) _displayNameForTableId(id),
    ].join(' + ');

    return Positioned(
      left: cluster.rect.left * scale,
      top: cluster.rect.top * scale,
      width: cluster.rect.width * scale,
      height: cluster.rect.height * scale,
      child: GestureDetector(
        onTap: () => _handleTableTap(cluster.primaryTableId),
        onLongPress: () => _handleTableLongPress(cluster.primaryTableId),
        child: Transform.rotate(
          angle: cluster.rotation * math.pi / 180,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(VynicFloorTokens.tileRadius),
              border: Border.all(
                color: border,
                width: isFocused || isSelected ? 2 : 1.5,
              ),
              boxShadow: isBusy
                  ? VynicFloorTokens.occupiedTileShadow
                  : VynicFloorTokens.tileShadow,
            ),
            child: _FloorPlanTileLabel(
              numbers: numbers,
              dot: dot,
              capacity: cluster.capacity,
              money: order == null ? null : _formatMoney(order.totalAmount),
              meta: order == null
                  ? null
                  : [
                      _elapsedSince(order.createdAt),
                      ?_waiterFor(order, busyModel),
                    ].join(' · '),
            ),
          ),
        ),
      ),
    );
  }

  /// Groups the floor's tables into what should be drawn as one table.
  ///
  /// A reservation or a selection that spans neighbouring tables is a party
  /// sitting at tables pushed together, so it renders as a single big table
  /// with the seats summed — not as separate tiles. Members of the same group
  /// that are *not* neighbours stay separate, because they cannot physically be
  /// joined: picking tables 1 and 3 across table 2 gives two tables, not one.
  List<_TableCluster> _buildTableClusters(
    List<RestaurantLayoutObject> objects,
  ) {
    final multiplier = _tableSizeMultiplier();
    final byId = <String, RestaurantLayoutObject>{};
    final rects = <String, Rect>{};
    final all = <FloorPlanGroupCandidate>[];

    for (final object in objects) {
      final tableId = object.tableId;
      if (object.type != RestaurantLayoutObjectType.table || tableId == null) {
        continue;
      }
      final rect = Rect.fromCenter(
        center: Offset(
          object.x + object.width / 2,
          object.y + object.height / 2,
        ),
        width: object.width * multiplier,
        height: object.height * multiplier,
      );
      byId[tableId] = object;
      rects[tableId] = rect;
      all.add((id: tableId, rect: rect));
    }

    // What ties tables together: an in-progress selection, or a shared
    // reservation/order.
    final groups = <String, List<String>>{};
    for (final tableId in byId.keys) {
      final String? key;
      if (_selectedTables.contains(tableId)) {
        key = 'selection';
      } else {
        final model = _getTableModel(tableId);
        key = model != null && model.isReserved
            ? _getReservationGroupKey(model)
            : null;
      }
      if (key == null) continue;
      groups.putIfAbsent(key, () => []).add(tableId);
    }

    final merged = <String>{};
    final clusters = <_TableCluster>[];
    for (final entry in groups.entries) {
      if (entry.value.length < 2) continue;
      final candidates = [
        for (final id in entry.value) (id: id, rect: rects[id]!),
      ];
      for (final group in floorPlanAdjacencyGroups(
        selected: candidates,
        obstacles: all,
      )) {
        clusters.add(_clusterFor(group, byId, rects));
        merged.addAll(group);
      }
    }

    // Everything else draws as itself, in the layout's own order.
    for (final object in objects) {
      final tableId = object.tableId;
      if (object.type != RestaurantLayoutObjectType.table ||
          tableId == null ||
          merged.contains(tableId)) {
        continue;
      }
      clusters.add(_clusterFor([tableId], byId, rects));
    }
    return clusters;
  }

  _TableCluster _clusterFor(
    List<String> tableIds,
    Map<String, RestaurantLayoutObject> byId,
    Map<String, Rect> rects,
  ) {
    final members = [for (final id in tableIds) byId[id]!];
    final rect = floorPlanGroupBounds(tableIds.map((id) => rects[id]!));
    // Seats come from the table definitions, so a joined party's capacity is
    // simply the sum — two six-tops pushed together seat twelve.
    var capacity = 0;
    for (final id in tableIds) {
      capacity += _layout.tableForId(id)?.capacity ?? 0;
    }
    final rotations = members.map((object) => object.rotation).toSet();
    return _TableCluster(
      objects: members,
      tableIds: tableIds,
      rect: rect,
      capacity: capacity,
      // A merged rect is axis-aligned, so it can only carry a rotation the
      // whole run agrees on.
      rotation: rotations.length == 1 ? rotations.first : 0,
    );
  }

  /// Seat marks follow the cluster, so a joined run gets one ring of chairs
  /// for its combined capacity instead of two overlapping ones.
  List<FloorPlanSeatedTable> _seatedTables(List<_TableCluster> clusters) {
    return [
      for (final cluster in clusters)
        if (cluster.capacity > 0)
          (
            rect: cluster.rect,
            rotation: cluster.rotation,
            // A joined run behaves like a communal table: chairs along the
            // long sides and one at each end.
            shape: cluster.isMerged
                ? RestaurantTableShape.long
                : cluster.objects.first.tableShape,
            capacity: cluster.capacity,
          ),
    ];
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
    final order = _activeOrderForTable(tableModel);
    final isReserved = presentation.status == TableOperationalStatus.reserved;

    final label = _displayNameForTableId(tableId);
    final sizeMultiplier = _tableSizeMultiplier();
    final scaledWidth = object.width * scaleX * sizeMultiplier;
    final scaledHeight = object.height * scaleY * sizeMultiplier;
    final centerX = (object.x + object.width / 2) * scaleX;
    final centerY = (object.y + object.height / 2) * scaleY;

    // Free tiles are white with a hairline; busy ones warm up. Status is
    // carried by a single dot plus the figures, not by a filled tile — that
    // keeps a full floor readable instead of a wall of colour.
    final Color fill;
    final Color border;
    final Color dot;
    if (isSelected) {
      fill = VynicFloorTokens.accentSoft;
      border = VynicFloorTokens.accentBadgeText;
      dot = VynicFloorTokens.accentText;
    } else if (isBusy) {
      // Each party gets its own hue, so two occupied tables on the same floor
      // are told apart at a glance instead of all reading as one warm colour.
      final groupColor = tableModel == null
          ? null
          : _getReservationColor(tableModel);
      fill = VynicFloorTokens.occupiedFill;
      border = groupColor ?? VynicFloorTokens.occupiedBorder;
      dot =
          groupColor ??
          (isReserved
              ? VynicFloorTokens.reservedDot
              : VynicFloorTokens.occupiedDot);
    } else {
      fill = VynicFloorTokens.tileFill;
      border = VynicFloorTokens.tileBorder;
      dot = VynicFloorTokens.freeDot;
    }

    return Positioned(
      left: centerX - scaledWidth / 2,
      top: centerY - scaledHeight / 2,
      width: scaledWidth,
      height: scaledHeight,
      child: GestureDetector(
        onTap: () => _handleTableTap(tableId),
        onLongPress: () => _handleTableLongPress(tableId),
        child: Transform.rotate(
          angle: object.rotation * math.pi / 180,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(
                _floorPlanTableRadius(object.tableShape),
              ),
              border: Border.all(
                color: border,
                width: isSelected || isFocused ? 1.5 : 1,
              ),
              boxShadow: isBusy
                  ? VynicFloorTokens.occupiedTileShadow
                  : VynicFloorTokens.tileShadow,
            ),
            // Same label as a merged tile. This path had its own copy —
            // another `FittedBox(scaleDown)` around a fixed 128pt column — so
            // the single tables, which is most of them, kept shrinking their
            // type while the merged ones had already stopped.
            child: _FloorPlanTileLabel(
              numbers: label,
              dot: dot,
              capacity: _layout.tableForId(tableId)?.capacity ?? 0,
              money: !isBusy || order == null
                  ? null
                  : _formatMoney(order.totalAmount),
              meta: !isBusy
                  ? null
                  : () {
                      final startedAt =
                          order?.createdAt ?? tableModel?.reservedAt;
                      final parts = [
                        if (startedAt != null) _elapsedSince(startedAt),
                        ?_waiterFor(order, tableModel),
                      ];
                      return parts.isEmpty ? null : parts.join(' · ');
                    }(),
            ),
          ),
        ),
      ),
    );
  }

  String? _waiterFor(Order? order, TableModel? tableModel) {
    final fromOrder = order?.openedByUserId?.trim().isNotEmpty == true
        ? order!.openedByUserId!.trim()
        : order?.createdBy.trim();
    if (fromOrder != null && fromOrder.isNotEmpty) {
      return fromOrder;
    }
    final reservedBy = tableModel?.reservedBy?.trim();
    return reservedBy == null || reservedBy.isEmpty ? null : reservedBy;
  }

  double _tableSizeMultiplier() {
    switch (widget.tableTileSize) {
      case PosTableTileSize.small:
        return 0.9;
      case PosTableTileSize.medium:
        return 1.05;
      case PosTableTileSize.large:
        return 1.2;
      case PosTableTileSize.automatic:
        switch (widget.layoutClass) {
          case PosLayoutClass.xs:
            return 0.86;
          case PosLayoutClass.sm:
            return 0.94;
          case PosLayoutClass.md:
            return 1;
          case PosLayoutClass.lg:
            return 1.12;
        }
    }
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
        child:
            object.type == RestaurantLayoutObjectType.wall ||
                object.type == RestaurantLayoutObjectType.divider
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

  (Color, Color, Color) _floorPlanObjectColors(RestaurantLayoutObject object) {
    switch (object.type) {
      case RestaurantLayoutObjectType.wall:
        return (const Color(0xFF334155), const Color(0xFF0F172A), Colors.white);
      case RestaurantLayoutObjectType.divider:
        return (const Color(0xFF94A3B8), const Color(0xFF64748B), Colors.white);
      case RestaurantLayoutObjectType.zone:
        return (
          const Color(0xFFF6F2F7),
          const Color(0xFFD9C9DD),
          const Color(0xFF6B5570),
        );
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
      case RestaurantLayoutObjectType.divider:
        return Icons.power_input;
      case RestaurantLayoutObjectType.zone:
        return Icons.crop_free;
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
        final targetWidth = _targetGridTileWidth(width);
        final columns = math.max(2, (width / targetWidth).floor());
        final tileHeight = _targetGridTileHeight(width);

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: (width / columns) / tileHeight,
          ),
          itemCount: tableIds.length,
          itemBuilder: (context, index) {
            return _buildTableButton(tableIds[index]);
          },
        );
      },
    );
  }

  double _targetGridTileWidth(double availableWidth) {
    switch (widget.tableTileSize) {
      case PosTableTileSize.small:
        return 190;
      case PosTableTileSize.medium:
        return 230;
      case PosTableTileSize.large:
        return 270;
      case PosTableTileSize.automatic:
        switch (widget.layoutClass) {
          case PosLayoutClass.xs:
            return 190;
          case PosLayoutClass.sm:
            return 210;
          case PosLayoutClass.md:
            return 235;
          case PosLayoutClass.lg:
            return 255;
        }
    }
  }

  double _targetGridTileHeight(double availableWidth) {
    switch (widget.tableTileSize) {
      case PosTableTileSize.small:
        return 104;
      case PosTableTileSize.medium:
        return 124;
      case PosTableTileSize.large:
        return 144;
      case PosTableTileSize.automatic:
        switch (widget.layoutClass) {
          case PosLayoutClass.xs:
            return 104;
          case PosLayoutClass.sm:
            return 112;
          case PosLayoutClass.md:
            return 126;
          case PosLayoutClass.lg:
            return 138;
        }
    }
  }

  Widget _buildTableButton(String tableId) {
    final tableModel = _getTableModel(tableId);
    final presentation = TableStatusPresentation.of(tableModel);
    final isReserved = presentation.isBusy;
    final isSelected = _selectedTables.contains(tableId);
    final isFocused = _focusedReservedTables.contains(tableId);
    final order = _activeOrderForTable(tableModel);
    final serviceMeta = _serviceMetaFor(tableModel, order, presentation);
    final statusToken = VynicStatusTokens.ofTone(serviceMeta.tone);
    final metaLine = _tableMetaLine(tableModel, order);

    Color backgroundColor;
    Color borderColor;
    Color textColor;
    IconData icon;

    if (isReserved) {
      backgroundColor = isFocused ? statusToken.background : Colors.white;
      borderColor = isFocused ? statusToken.foreground : statusToken.border;
      textColor = VynicColors.textPrimary;
      icon = isFocused ? Icons.visibility : presentation.icon;
    } else if (isSelected) {
      backgroundColor = VynicColors.accent;
      borderColor = VynicColors.accentHover;
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
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.14)
                      : isReserved
                      ? statusToken.background
                      : VynicColors.cardSoft,
                  borderRadius: VynicRadius.smAll,
                  border: Border.all(
                    color: isReserved ? statusToken.border : VynicColors.border,
                  ),
                ),
                child: Icon(
                  icon,
                  color: isReserved ? statusToken.foreground : textColor,
                  size: 22,
                ),
              ),
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
                          ? serviceMeta.label
                          : isSelected
                          ? 'არჩეულია'
                          : _currentZone.name,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (metaLine != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        metaLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.72),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
          child: _usesFloorPlan ? _buildFloorPlan() : _buildButtonGrid(),
        ),
      ],
    );
  }
}

/// One drawn table: either a single table, or a run of neighbouring tables
/// pushed together for one party.
@immutable
class _TableCluster {
  const _TableCluster({
    required this.objects,
    required this.tableIds,
    required this.rect,
    required this.capacity,
    required this.rotation,
  });

  final List<RestaurantLayoutObject> objects;
  final List<String> tableIds;

  /// Union of the members, in layout units, already size-multiplied.
  final Rect rect;

  /// Summed seats across the run.
  final int capacity;

  final double rotation;

  bool get isMerged => tableIds.length > 1;

  /// Members share the reservation/order, so opening any one of them opens the
  /// party's order.
  String get primaryTableId => tableIds.first;
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

/// What a table tile says, and how much of it survives a small tile.
///
/// This used to be a `FittedBox(fit: BoxFit.scaleDown)` wrapped around every
/// row the tile could show. That shrinks the *type* until the content fits,
/// which on a 1024x768 terminal produced the exact inversion of what you want:
/// a free table has one line and stayed readable, while an occupied table —
/// number, guests, total, elapsed·waiter — had four rows crushed into the same
/// box and came out around six physical pixels. The tables carrying money were
/// the ones nobody could read.
///
/// Detail is dropped instead. Type size is fixed at every level, and the tile
/// shows as many rows as it can actually fit: everything, then number and
/// total, then just the number. Only the last of those may still scale down,
/// and one short string shrinks far less than a four-row column.
class _FloorPlanTileLabel extends StatelessWidget {
  const _FloorPlanTileLabel({
    required this.numbers,
    required this.dot,
    required this.capacity,
    required this.money,
    required this.meta,
  });

  final String numbers;
  final Color dot;
  final int capacity;

  /// Null on a free table.
  final String? money;
  final String? meta;

  /// How far type may be shrunk before a line is dropped instead.
  ///
  /// The original bug was unbounded shrinking: four rows squeezed into a small
  /// tile came out around six physical pixels. Measured against real tiles, a
  /// name-plus-total lands at 0.92 on a short label and 0.80 on „440.00 ₾" —
  /// so the floor sits just under that. Above it type is still comfortably
  /// legible; below it, losing a line beats shrinking the tile into mush.
  static const double _minTypeScale = 0.78;

  /// Gap between rows, and the dot plus its gutter on the number row.
  static const double _rowGap = 4;
  static const double _dotSpan = 15;

  /// Secondary lines are read at a glance from standing distance on a panel
  /// that is often neither bright nor high-resolution. The old
  /// `textFaint`/`occupiedMeta` greys measured 3.6:1 and 4.1:1 against a busy
  /// tile — the two lightest things on the tile were also the two smallest.
  static const Color _secondary = VynicFloorTokens.text;
  static const Color _tertiary = VynicFloorTokens.textMuted;

  /// One line of a tile, carrying what it needs to both measure and draw.
  ///
  /// [base] is the style the line will actually be rendered in — taken from
  /// the enclosing [DefaultTextStyle], so it carries the app's font family.
  /// Measuring with a bare `TextStyle` instead measured a *different* font
  /// from the one on screen (the POS renders in NotoSansGeorgian), which made
  /// every width here wrong by however much the two faces differ.
  static _TileLine _line(
    TextStyle base,
    String text,
    double size,
    FontWeight weight,
    Color color, {
    bool withDot = false,
  }) {
    final style = base.copyWith(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.15,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return _TileLine(
      text: text,
      style: style,
      withDot: withDot,
      width: painter.width + (withDot ? _dotSpan : 0),
      height: painter.height,
    );
  }

  /// Richest first. The first one that fits is the one drawn — so raising a
  /// font size can never silently push a tile into the wrong level, which is
  /// what hand-tuned pixel thresholds would have done.
  List<List<_TileLine>> _levels(TextStyle base) {
    final busy = money != null;
    return [
      if (busy)
        [
          _line(
            base,
            numbers,
            16,
            FontWeight.w700,
            VynicFloorTokens.text,
            withDot: true,
          ),
          if (capacity > 0)
            _line(base, '$capacity სტუმარი', 12.5, FontWeight.w600, _tertiary),
          _line(base, money!, 18, FontWeight.w700, VynicFloorTokens.text),
          if (meta != null)
            _line(base, meta!, 12.5, FontWeight.w500, _secondary),
        ],
      if (busy)
        [
          _line(
            base,
            numbers,
            15,
            FontWeight.w700,
            VynicFloorTokens.text,
            withDot: true,
          ),
          _line(base, money!, 17, FontWeight.w700, VynicFloorTokens.text),
          if (meta != null) _line(base, meta!, 12, FontWeight.w500, _secondary),
        ],
      if (busy)
        // The total is the reason anybody looks at an occupied table, so it is
        // the last thing to go.
        [
          _line(base, numbers, 13, FontWeight.w700, VynicFloorTokens.text),
          _line(base, money!, 15, FontWeight.w700, VynicFloorTokens.text),
        ],
      if (!busy && capacity > 0)
        [
          _line(
            base,
            numbers,
            15,
            FontWeight.w700,
            VynicFloorTokens.text,
            withDot: true,
          ),
          _line(base, '$capacity სტუმარი', 12.5, FontWeight.w600, _tertiary),
        ],
      [_line(base, numbers, 15, FontWeight.w700, VynicFloorTokens.text)],
    ];
  }

  Widget _draw(_TileLine line) {
    final text = Text(
      line.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: line.style,
    );
    if (!line.withDot) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Flexible(child: text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A small tile that spends 12 units a side on padding has nothing left
        // for the label.
        final pad = constraints.maxWidth < 90 ? 5.0 : 12.0;
        final inner = Size(
          math.max(0, constraints.maxWidth - pad * 2),
          math.max(0, constraints.maxHeight - pad * 2),
        );

        final levels = _levels(DefaultTextStyle.of(context).style);

        // Pick the richest level that can be drawn at no less than
        // [_minTypeScale] of its intended size, and let a `FittedBox` take up
        // the remaining sliver.
        //
        // A hard "must fit exactly" rule was tried first and was wrong twice
        // over. It dropped a tile straight from four lines to one for the sake
        // of a couple of points, and it depends on text measurement — which
        // differs between the real font and the fallback the test harness
        // substitutes, so any fixed threshold would have been tuned against
        // the wrong numbers. A floor on how small type may go is the property
        // that actually matters, and it holds whatever the font measures.
        var chosen = levels.last;
        for (final level in levels) {
          final needWidth = level.fold<double>(
            0,
            (widest, line) => math.max(widest, line.width),
          );
          final needHeight =
              level.fold<double>(0, (sum, line) => sum + line.height) +
              _rowGap * (level.length - 1);
          if (needWidth <= 0 || needHeight <= 0) continue;
          final fit = math.min(
            inner.width / needWidth,
            inner.height / needHeight,
          );
          if (fit >= _minTypeScale) {
            chosen = level;
            break;
          }
        }

        return Padding(
          padding: EdgeInsets.all(pad),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < chosen.length; i++) ...[
                    if (i > 0) const SizedBox(height: _rowGap),
                    _draw(chosen[i]),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A measured line of tile text: what to draw, and what it costs.
class _TileLine {
  const _TileLine({
    required this.text,
    required this.style,
    required this.withDot,
    required this.width,
    required this.height,
  });

  final String text;
  final TextStyle style;
  final bool withDot;
  final double width;
  final double height;
}

/// Never zoom a plan in past this, however little is on it.
///
/// Without a cap, a floor holding two tables would scale them up until they
/// filled the panel, which reads as a different room rather than a quiet one.
const double maxFloorPlanZoom = 1.6;

/// Breathing room left around the content, in layout units.
///
/// Seat marks are painted just outside a table's own box, so a fit that hugged
/// the tables exactly would clip the chairs off the outermost ones.
const double _floorPlanContentMargin = 44;

/// The region of the plan worth showing: what is actually placed on it, plus a
/// margin — never larger than the canvas itself.
///
/// The declared canvas is the editor's working area and is routinely far bigger
/// than its contents. The built-in plan is 1005x1101 with everything in the
/// upper portion, so fitting the whole canvas into a landscape panel binds on
/// height and gives up roughly a third of the scale for empty space. On a
/// 1024x768 terminal that was one of three compounding shrinks that left table
/// labels at about six physical pixels.
///
/// Returns the full canvas when there is nothing placed, so an empty floor
/// still looks like a floor rather than a zoomed-in speck.
Rect floorPlanContentBounds(List<RestaurantLayoutObject> objects, Size canvas) {
  final full = Rect.fromLTWH(0, 0, canvas.width, canvas.height);
  if (objects.isEmpty || canvas.width <= 0 || canvas.height <= 0) {
    return full;
  }

  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final object in objects) {
    // Width/height can be negative if a layout was authored by dragging
    // up-left; normalise rather than trusting the sign.
    final l = math.min(object.x, object.x + object.width);
    final t = math.min(object.y, object.y + object.height);
    final r = math.max(object.x, object.x + object.width);
    final b = math.max(object.y, object.y + object.height);
    if (l < left) left = l;
    if (t < top) top = t;
    if (r > right) right = r;
    if (b > bottom) bottom = b;
  }

  if (!left.isFinite || !top.isFinite || !right.isFinite || !bottom.isFinite) {
    return full;
  }

  final bounds = Rect.fromLTRB(
    left - _floorPlanContentMargin,
    top - _floorPlanContentMargin,
    right + _floorPlanContentMargin,
    bottom + _floorPlanContentMargin,
  ).intersect(full);

  // A degenerate result — everything stacked on one point, or placed outside
  // the canvas entirely — is not something to zoom into.
  if (bounds.width < 1 || bounds.height < 1) {
    return full;
  }
  return bounds;
}
