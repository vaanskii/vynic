import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

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

    _layoutNameController.text = layout.name;
    _firstZoneController.text =
        layout.zoneForLegacyFloor('first')?.name ?? 'First floor';
    _secondZoneController.text =
        layout.zoneForLegacyFloor('second')?.name ?? 'Second floor';

    final firstTables = layout.tablesForLegacyFloor('first');
    final secondTables = layout.tablesForLegacyFloor('second');
    _firstFloorTables.addAll(
      firstTables.map((table) => _EditableTableDefinition.fromLayout(table)),
    );
    _secondFloorTables.addAll(
      secondTables.map((table) => _EditableTableDefinition.fromLayout(table)),
    );

    if (_firstFloorTables.isEmpty) {
      _firstFloorTables.add(_EditableTableDefinition.create('first', 1));
    }
    if (_secondFloorTables.isEmpty) {
      _secondFloorTables.add(_EditableTableDefinition.create('second', 1));
    }
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
          message: 'მაგიდების განლაგება შენახულია',
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
      _loadDraft(RestaurantTableLayouts.buttonGridPreview);
    });
    unawaited(
      showPosToast(
        context: context,
        message: 'დაბრუნდა საწყისი მაგიდების განლაგება',
        style: PosToastStyle.info,
      ),
    );
  }

  RestaurantTableLayout _buildLayout() {
    final layoutName = _layoutNameController.text.trim();
    return RestaurantTableLayout(
      id: 'custom-button-grid-layout',
      name: layoutName.isEmpty ? 'Custom table layout' : layoutName,
      zones: [
        RestaurantZone(
          id: 'main-floor',
          name: _zoneName(_firstZoneController.text, 'First floor'),
          legacyFloor: 'first',
          displayOrder: 1,
          renderMode: TableLayoutRenderMode.buttonGrid,
        ),
        RestaurantZone(
          id: 'vip-floor',
          name: _zoneName(_secondZoneController.text, 'Second floor'),
          legacyFloor: 'second',
          displayOrder: 2,
          renderMode: TableLayoutRenderMode.buttonGrid,
        ),
      ],
      tables: [
        ..._buildTables(_firstFloorTables, 'main-floor', 'first'),
        ..._buildTables(_secondFloorTables, 'vip-floor', 'second'),
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
          id: legacyFloor == 'second'
              ? 'floor2-table${i + 1}'
              : 'floor1-table${i + 1}',
          zoneId: zoneId,
          legacyFloor: legacyFloor,
          legacyTableNumber: '${i + 1}',
          label: draft[i].label,
          capacity: draft[i].capacity,
          sortOrder: i + 1,
        ),
    ];
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(
            icon: Icons.table_restaurant_outlined,
            title: 'მაგიდების განლაგება',
            subtitle: 'შექმენით POS-ისთვის მარტივი მაგიდების ღილაკები.',
            badge: AdminStatusBadge(
              icon: Icons.view_module_outlined,
              label: 'Button grid',
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
            floor: 'first',
          ),
          const SizedBox(height: 16),
          _buildZoneEditor(
            title: 'მეორე ზონა',
            zoneController: _secondZoneController,
            tables: _secondFloorTables,
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
    required String floor,
  }) {
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 680;
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
          _buildTablePreview(tables),
          const SizedBox(height: 16),
          ...tables.map((table) => _buildTableRow(table)),
        ],
      ),
    );
  }

  Widget _buildTablePreview(List<_EditableTableDefinition> tables) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 620
            ? 3
            : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tables.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.1,
          ),
          itemBuilder: (context, index) {
            final table = tables[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminDesign.panelSoft,
                borderRadius: BorderRadius.circular(AdminDesign.radius),
                border: Border.all(color: AdminDesign.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.table_restaurant,
                    color: AdminDesign.accentDark,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      table.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminDesign.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (table.capacity > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${table.capacity}',
                      style: const TextStyle(
                        color: AdminDesign.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTableRow(_EditableTableDefinition table) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 42,
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
          const SizedBox(width: 10),
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
        ],
      ),
    );
  }
}

class _EditableTableDefinition {
  _EditableTableDefinition({
    required this.sortOrder,
    required String label,
    required int capacity,
  }) : labelController = TextEditingController(text: label),
       capacityController = TextEditingController(
         text: capacity > 0 ? capacity.toString() : '',
       );

  factory _EditableTableDefinition.create(String floor, int sortOrder) {
    final label = floor == 'second'
        ? 'VIP Zone $sortOrder'
        : 'Table $sortOrder';
    return _EditableTableDefinition(
      sortOrder: sortOrder,
      label: label,
      capacity: 0,
    );
  }

  factory _EditableTableDefinition.fromLayout(RestaurantTableDefinition table) {
    return _EditableTableDefinition(
      sortOrder: table.sortOrder,
      label: table.label,
      capacity: table.capacity,
    );
  }

  final int sortOrder;
  final TextEditingController labelController;
  final TextEditingController capacityController;

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

  void dispose() {
    labelController.dispose();
    capacityController.dispose();
  }
}
