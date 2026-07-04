import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/models/reservation.dart';

class TableSelectionWidget extends StatefulWidget {
  final VoidCallback? onSelectionChanged;
  final Function(TableModel)? onTableTap;
  final int currentFloor;

  const TableSelectionWidget({
    super.key,
    this.onSelectionChanged,
    this.onTableTap,
    this.currentFloor = 1,
  });

  @override
  State<TableSelectionWidget> createState() => TableSelectionWidgetState();
}

class TableSelectionWidgetState extends State<TableSelectionWidget> {
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

    // Reserved tables show a quick overview first; the rail CTA opens them.
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
      final isAlreadyFocused =
          _focusedReservedTables.length == nextFocusedTableIds.length &&
          _focusedReservedTables.containsAll(nextFocusedTableIds);

      setState(() {
        _selectedTables.clear();
        if (isAlreadyFocused) {
          _focusedReservedTables.clear();
          selectedTable = null;
        } else {
          _focusedReservedTables
            ..clear()
            ..addAll(nextFocusedTableIds);
          selectedTable = tableId;
        }
      });
      widget.onSelectionChanged?.call();
      return;
    }

    // Otherwise, handle normal selection
    setState(() {
      _focusedReservedTables.clear();
      if (_selectedTables.contains(tableId)) {
        _selectedTables.remove(tableId);
        selectedTable = null;
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
        final isReserved = tableModel?.isReserved ?? false;
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
                        isFocused ? Icons.visibility : Icons.lock,
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
                      const Text(
                        'დაკავებულია',
                        style: TextStyle(
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
    final hasFirstFloor = _selectedTables.any(
      (id) => _floorForTableId(id) == 'first',
    );
    final hasSecondFloor = _selectedTables.any(
      (id) => _floorForTableId(id) == 'second',
    );
    return hasFirstFloor && hasSecondFloor;
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

        // Calculate scale to fit entire SVG while maintaining aspect ratio
        final scaleX = availableWidth / svgWidth;
        final scaleY = availableHeight / svgHeight;
        final scale = scaleX < scaleY ? scaleX : scaleY;

        final scaledWidth = svgWidth * scale;
        final scaledHeight = svgHeight * scale;

        return Center(
          child: SizedBox(
            width: scaledWidth,
            height: scaledHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // Better touch detection
              onTapUp: (details) {
                // Convert tap position to SVG coordinates
                final tapX = details.localPosition.dx / scale;
                final tapY = details.localPosition.dy / scale;

                // Check which table was tapped
                for (final entry in _tablePositions.entries) {
                  if (entry.value.contains(Offset(tapX, tapY))) {
                    _handleTableTap(entry.key);
                    break;
                  }
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
    final isReserved = tableModel?.isReserved ?? false;
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
      icon = isFocused ? Icons.visibility : Icons.lock;
    } else if (isSelected) {
      backgroundColor = const Color(0xFF047857);
      borderColor = const Color(0xFF065F46);
      textColor = Colors.white;
      icon = Icons.check_circle;
    } else {
      backgroundColor = const Color(0xFFF8FAFC);
      borderColor = const Color(0xFFE2E8F0);
      textColor = const Color(0xFF0F172A);
      icon = Icons.table_restaurant;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _handleTableTap(tableId),
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
                          ? 'დაკავებულია'
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
          child: _usesSvgMap ? _buildSvgFloorPlan() : _buildButtonGrid(),
        ),
      ],
    );
  }
}
