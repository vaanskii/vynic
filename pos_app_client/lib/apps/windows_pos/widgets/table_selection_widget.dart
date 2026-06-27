import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/models/table.dart';
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

  // Floor 1 tables
  final List<String> _floor1TableIds = [
    'floor1-table1',
    'floor1-table2',
    'floor1-table3',
    'floor1-table4',
    'floor1-table5',
    'floor1-table6',
    'floor1-table7',
    'floor1-table8',
    'floor1-table9',
  ];

  // Floor 2 tables
  final List<String> _floor2TableIds = [
    'floor2-table1',
    'floor2-table2',
    'floor2-table3',
    'floor2-table4',
  ];

  // Get current floor's table IDs
  List<String> get tableIds =>
      _currentFloor == 1 ? _floor1TableIds : _floor2TableIds;

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
    final floor = _currentFloor == 1 ? 'first' : 'second';
    final tables = DatabaseService.getTablesByFloor(floor);
    final reservationColors = _buildReservationColorMap();

    setState(() {
      _tables = tables;
      _reservationColors = reservationColors;
    });
  }

  TableModel? _getTableModel(String tableId) {
    final tableNumber = _tableNumberFromId(tableId);
    if (tableNumber == null) {
      return null;
    }

    final floor = _floorForTableId(tableId);

    // Find in cached tables first
    try {
      return _tables.firstWhere(
        (t) => t.tableNumber == tableNumber && t.floor == floor,
      );
    } catch (e) {
      // If not found in cache, query database directly
      return DatabaseService.getTable(tableNumber, floor);
    }
  }

  String _svgTableIdFor(String tableId) {
    return tableId.replaceFirst(RegExp(r'^floor[12]-'), '');
  }

  String? _tableNumberFromId(String tableId) {
    final svgTableId = _svgTableIdFor(tableId);
    if (!svgTableId.startsWith('table')) {
      return null;
    }
    return svgTableId.replaceAll('table', '');
  }

  String _floorForTableId(String tableId) {
    if (tableId.startsWith('floor2-')) {
      return 'second';
    }
    return 'first';
  }

  String _displayNameForTableId(String tableId) {
    final tableNumber = _tableNumberFromId(tableId) ?? tableId;
    return _floorForTableId(tableId) == 'second'
        ? 'Second Floor Table $tableNumber'
        : 'Table $tableNumber';
  }

  Future<void> _loadSvg() async {
    final floorFile = _currentFloor == 1 ? 'new-floor1.svg' : 'new-floor2.svg';
    final svgString = await rootBundle.loadString('assets/$floorFile');
    final positions = _extractTablePositions(svgString);

    // Set SVG dimensions based on floor
    if (_currentFloor == 1) {
      _svgWidth = 1005.0;
      _svgHeight = 1101.0;
    } else {
      _svgWidth = 953.0;
      _svgHeight = 958.0;
    }

    setState(() {
      _svgString = svgString;
      _tablePositions = positions;
    });
  }

  void switchFloor(int floor) {
    if (floor != _currentFloor && (floor == 1 || floor == 2)) {
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

    final floor = _currentFloor == 1 ? 'first' : 'second';
    final tables = DatabaseService.getTablesByFloor(floor);
    final reservationColors = _buildReservationColorMap();

    final floorFile = _currentFloor == 1 ? 'new-floor1.svg' : 'new-floor2.svg';
    final svgString = await rootBundle.loadString('assets/$floorFile');
    final positions = _extractTablePositions(svgString);

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

  Map<String, Rect> _extractTablePositions(String svgString) {
    Map<String, Rect> positions = {};

    if (_currentFloor == 1) {
      // Floor 1 - Restaurant tables
      positions = {
        'floor1-table1': Rect.fromLTWH(64.5, 260.65, 101.29, 161.76),
        'floor1-table2': Rect.fromLTWH(266.5, 178.65, 101.29, 161.76),
        'floor1-table3': Rect.fromLTWH(484.5, 178.65, 101.29, 161.76),
        'floor1-table4': Rect.fromLTWH(699.5, 178.65, 101.29, 161.76),
        'floor1-table5': Rect.fromLTWH(57.5, 737.65, 161.77, 101.29),
        'floor1-table6': Rect.fromLTWH(60.5, 917.89, 161.77, 101.29),
        'floor1-table7': Rect.fromLTWH(351.5, 887.65, 101.29, 161.77),
        'floor1-table8': Rect.fromLTWH(583.5, 887.87, 101.29, 161.76),
        'floor1-table9': Rect.fromLTWH(793.5, 887.87, 101.29, 161.76),
      };
    } else {
      // Floor 2 - Restaurant tables
      positions = {
        'floor2-table1': Rect.fromLTWH(45.23, 719.11, 101.29, 161.11),
        'floor2-table2': Rect.fromLTWH(245.23, 719.11, 101.29, 161.11),
        'floor2-table3': Rect.fromLTWH(445.23, 719.11, 101.29, 161.11),
        'floor2-table4': Rect.fromLTWH(644.23, 721.11, 101.29, 161.11),
      };
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // SVG Floor Plan
        Expanded(
          child: _svgString.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFC0AD7B)),
                )
              : LayoutBuilder(
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
                          behavior:
                              HitTestBehavior.opaque, // Better touch detection
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
                                      final modifiedSvg =
                                          _modifySvgForSelection(_svgString);
                                      return SizedBox(
                                        width: svgWidth,
                                        height: svgHeight,
                                        // Key on the rendered content so the
                                        // raster is rebuilt the moment table
                                        // colors change (e.g. a mobile walk-in
                                        // or cancel), instead of showing a
                                        // cached picture until the next tap.
                                        child: SvgPicture.string(
                                          modifiedSvg,
                                          key: ValueKey<int>(
                                            modifiedSvg.hashCode,
                                          ),
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
                ),
        ),
      ],
    );
  }
}
