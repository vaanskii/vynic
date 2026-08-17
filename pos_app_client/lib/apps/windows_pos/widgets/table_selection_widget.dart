import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/models/order.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_operational_status.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_grouping.dart';
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
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed.inMinutes < 1) return 'ახლახან';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} წთ';
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${elapsed.inHours}:$minutes';
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
        final overlayRect = _scaledAroundCenter(
          entry.value,
          _tableSizeMultiplier(),
        );

        return Positioned(
          left: overlayRect.left,
          top: overlayRect.top,
          width: overlayRect.width,
          height: overlayRect.height,
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
            child: SizedBox(
              width: scaledWidth,
              height: scaledHeight,
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

    final numbers = [
      for (final id in cluster.tableIds) _tableNumberFromId(id) ?? id,
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          numbers,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VynicFloorTokens.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (cluster.capacity > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${cluster.capacity} სტუმარი',
                        maxLines: 1,
                        style: const TextStyle(
                          color: VynicFloorTokens.textFaint,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (order != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _formatMoney(order.totalAmount),
                        maxLines: 1,
                        style: const TextStyle(
                          color: VynicFloorTokens.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          _elapsedSince(order.createdAt),
                          ?_waiterFor(order, busyModel),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VynicFloorTokens.occupiedMeta,
                          fontSize: 11.5,
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
            child: isBusy
                ? _buildBusyTileBody(
                    label: label,
                    dot: dot,
                    order: order,
                    tableModel: tableModel,
                  )
                : _buildFreeTileBody(label: label, dot: dot),
          ),
        ),
      ),
    );
  }

  /// Free tile: just the name, centred.
  Widget _buildFreeTileBody({required String label, required Color dot}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      // scaleDown so a tile too short for its label shrinks the text rather
      // than overflowing — it never enlarges past the natural size.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: VynicFloorTokens.text,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// Busy tile: name + status dot, the running total, then elapsed and waiter
  /// pinned to the bottom.
  Widget _buildBusyTileBody({
    required String label,
    required Color dot,
    required Order? order,
    required TableModel? tableModel,
  }) {
    final amount = order == null ? null : _formatMoney(order.totalAmount);
    final startedAt = order?.createdAt ?? tableModel?.reservedAt;
    final elapsed = startedAt == null ? null : _elapsedSince(startedAt);
    final waiter = _waiterFor(order, tableModel);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 128,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VynicFloorTokens.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              if (amount != null) ...[
                const SizedBox(height: 6),
                Text(
                  amount,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VynicFloorTokens.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (elapsed != null || waiter != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (elapsed != null)
                      Text(
                        elapsed,
                        style: const TextStyle(
                          color: VynicFloorTokens.occupiedMeta,
                          fontSize: 11.5,
                        ),
                      ),
                    if (elapsed != null && waiter != null) const Spacer(),
                    if (waiter != null)
                      Flexible(
                        child: Text(
                          waiter,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: VynicFloorTokens.occupiedMeta,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
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

  Rect _scaledAroundCenter(Rect rect, double multiplier) {
    if ((multiplier - 1).abs() < 0.001) return rect;
    final width = rect.width * multiplier;
    final height = rect.height * multiplier;
    return Rect.fromCenter(center: rect.center, width: width, height: height);
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
