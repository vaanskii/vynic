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

  const TableSelectionWidget({
    super.key,
    this.onSelectionChanged,
    this.onTableTap,
  });

  @override
  State<TableSelectionWidget> createState() => TableSelectionWidgetState();
}

class TableSelectionWidgetState extends State<TableSelectionWidget> {
  String? selectedTable;
  final Set<String> _selectedTables = {};
  String _svgString = '';
  Map<String, Rect> _tablePositions = {};
  int _currentFloor = 1; // Track current floor (1 or 2)
  double _svgWidth = 1576.0;
  double _svgHeight = 1112.0;
  List<TableModel> _tables = [];
  Map<String, Color> _reservationColors =
      {}; // Cached colors per group (reservation/order)

  // Floor 1 tables
  final List<String> _floor1TableIds = [
    'table1',
    'table2',
    'table3',
    'table4',
    'table5',
    'table6',
    'table7',
    'table8',
    'table9',
    'table10',
  ];

  // Floor 2 VIP zones
  final List<String> _floor2TableIds = [
    'vip-zone-1',
    'vip-zone-2',
    'vip-zone-3',
  ];

  // Get current floor's table IDs
  List<String> get tableIds =>
      _currentFloor == 1 ? _floor1TableIds : _floor2TableIds;

  @override
  void initState() {
    super.initState();
    _loadTables();
    _loadSvg();
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
    // Extract table number from ID (e.g., 'table1' -> '1', 'vip-zone-1' -> '1')
    String tableNumber;
    if (tableId.startsWith('table')) {
      tableNumber = tableId.replaceAll('table', '');
    } else if (tableId.startsWith('vip-zone-')) {
      tableNumber = tableId.replaceAll('vip-zone-', '');
    } else {
      return null;
    }

    final floor = _currentFloor == 1 ? 'first' : 'second';

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

  Future<void> _loadSvg() async {
    final floorFile = _currentFloor == 1 ? 'floor1.svg' : 'floor2.svg';
    final svgString = await rootBundle.loadString('assets/$floorFile');
    final positions = _extractTablePositions(svgString);

    // Set SVG dimensions based on floor
    if (_currentFloor == 1) {
      _svgWidth = 1576.0;
      _svgHeight = 1112.0;
    } else {
      _svgWidth = 1191.0;
      _svgHeight = 842.0;
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
        // Don't clear selection - keep tables from both floors selected
      });
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

    final floorFile = _currentFloor == 1 ? 'floor1.svg' : 'floor2.svg';
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
      // Use hardcoded positions from Figma for accuracy
      const double tableWidth = 105.0;
      const double tableHeight = 165.0;

      // For rotated tables, swap width and height
      const double rotatedWidth = 165.0;
      const double rotatedHeight = 105.0;

      positions = {
        'table1': Rect.fromLTWH(320.4, 46.87, tableWidth, tableHeight),
        'table2': Rect.fromLTWH(325.29, 307.18, tableWidth, tableHeight),
        'table3': Rect.fromLTWH(504, 210, tableWidth, tableHeight),
        'table4': Rect.fromLTWH(711.46, 211.29, tableWidth, tableHeight),
        'table5': Rect.fromLTWH(
          332,
          728,
          rotatedWidth,
          rotatedHeight,
        ), // Rotated 90°
        'table6': Rect.fromLTWH(
          335,
          908.24,
          rotatedWidth,
          rotatedHeight,
        ), // Rotated 90°
        'table7': Rect.fromLTWH(606, 878.21, tableWidth, tableHeight),
        'table8': Rect.fromLTWH(798.09, 878.21, tableWidth, tableHeight),
        'table9': Rect.fromLTWH(983, 878.21, tableWidth, tableHeight),
        'table10': Rect.fromLTWH(1158, 878.21, tableWidth, tableHeight),
      };
    } else {
      // Floor 2 - VIP zones
      positions = {
        'vip-zone-1': Rect.fromLTWH(617.52, 54.36, 233.4, 209.4),
        'vip-zone-2': Rect.fromLTWH(581.4, 458.88, 218.64, 269.04),
        'vip-zone-3': Rect.fromLTWH(295.56, 54.36, 170.52, 134.52),
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
    final rgb = color.value & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  String _modifySvgForSelection(String svgString) {
    if (svgString.isEmpty) return svgString;

    final document = XmlDocument.parse(svgString);

    // Find and modify each table group
    for (final tableId in tableIds) {
      final elements = document
          .findAllElements('g')
          .where((element) => element.getAttribute('id') == tableId);

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
            // Selected state - gold color
            path.setAttribute('fill', '#C0AD7B');
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

    // If table is reserved, trigger callback to show order
    if (tableModel != null &&
        tableModel.isReserved &&
        widget.onTableTap != null) {
      widget.onTableTap!(tableModel);
      return;
    }

    // Otherwise, handle normal selection
    setState(() {
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
                        alpha: 0.7,
                      ) // Unique per reservation/order group
                    : isSelected
                    ? const Color(0xFFC0AD7B).withValues(
                        alpha: 0.6,
                      ) // Gold for selected
                    : Colors.transparent,
                border: Border.all(
                  color: isReserved
                      ? (reservationColor ?? Colors.red)
                      : isSelected
                      ? const Color(0xFFC0AD7B)
                      : Colors.grey.withValues(
                          alpha: 0.15,
                        ), // Very subtle border
                  width: isReserved
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
                      const Icon(Icons.lock, color: Colors.white, size: 28)
                    else if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 32,
                      ),
                    if (isReserved || isSelected) const SizedBox(height: 4),
                    // Show table number or VIP zone label - larger for touch
                    Text(
                      entry.key
                          .replaceAll('table', 'T')
                          .replaceAll('vip-zone-', 'VIP'),
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
  List<String> get selectedTables => _selectedTables
      .map(
        (t) => t
            .replaceAll('table', 'Table ')
            .replaceAll('vip-zone-', 'VIP Zone '),
      )
      .toList();

  bool get hasMixedFloorSelection {
    final hasFirstFloor = _selectedTables.any((id) => id.startsWith('table'));
    final hasSecondFloor = _selectedTables.any(
      (id) => id.startsWith('vip-zone-'),
    );
    return hasFirstFloor && hasSecondFloor;
  }

  // Expose selected tables for display in home screen
  String get selectedTablesText {
    if (_selectedTables.isEmpty) return 'None';
    return _selectedTables
        .map(
          (t) => t
              .replaceAll('table', 'Table ')
              .replaceAll('vip-zone-', 'VIP Zone '),
        )
        .join(', ');
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
                ),
        ),
      ],
    );
  }
}
