import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_model.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_screen.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/pos_display_settings_controller.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

/// Floors & areas overview.
///
/// This page *manages* floors — add, rename, duplicate, delete — and hands
/// the actual plan drawing over to [FloorEditorScreen]. It deliberately
/// contains no canvas: designing a floor plan inside a settings card was the
/// core problem with the previous editor.
class AdminTableLayoutsSection extends StatefulWidget {
  const AdminTableLayoutsSection({super.key});

  @override
  State<AdminTableLayoutsSection> createState() =>
      _AdminTableLayoutsSectionState();
}

class _AdminTableLayoutsSectionState extends State<AdminTableLayoutsSection> {
  late EditorDocument _document;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _document = EditorDocument.fromLayout(
      DatabaseService.getRestaurantTableLayout(),
    );
  }

  // -------------------------------------------------------------- helpers

  /// Every structural change is persisted immediately — these are cheap,
  /// discrete operations, unlike plan editing which batches behind Save.
  Future<void> _persist(EditorDocument next, {required String message}) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await DatabaseService.saveActiveRestaurantTableLayout(next.toLayout());
      if (!mounted) return;
      setState(_reload);
      unawaited(
        showPosToast(
          context: context,
          message: message,
          style: PosToastStyle.success,
        ),
      );
    } on StateError catch (error) {
      // The repository guards live tables; surface its reason verbatim.
      if (!mounted) return;
      unawaited(
        showPosToast(
          context: context,
          message: 'ვერ შესრულდა: ${error.message}',
          style: PosToastStyle.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// Live tables that would be orphaned by removing [floor]. Mirrors the
  /// repository's own rule so the user is told *before* the attempt.
  List<String> _occupiedTablesOn(EditorFloor floor) {
    return [
      for (final table in DatabaseService.getAllTables())
        if (table.floor == floor.legacyFloor &&
            (table.isReserved || table.activeOrderId != null))
          table.tableNumber,
    ];
  }

  // ------------------------------------------------------------- commands

  Future<void> _openEditor(EditorFloor floor) async {
    final saved = await FloorEditorScreen.open(
      context,
      layout: DatabaseService.getRestaurantTableLayout(),
      floorId: floor.zoneId,
    );
    if (saved && mounted) {
      setState(_reload);
    }
  }

  Future<void> _addFloor() async {
    final order = _document.floors.isEmpty
        ? 1
        : _document.floors
                  .map((floor) => floor.displayOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final name = await _promptForName(
      title: 'ახალი სართული',
      initial: 'სართული $order',
    );
    if (name == null) return;

    final floor = EditorFloor(
      zoneId: _uniqueZoneId(order),
      legacyFloor: _uniqueLegacyFloor(order),
      displayOrder: order,
      name: name,
      // 16:10 — POS terminals are landscape, so a landscape canvas fills the
      // plan panel instead of being letterboxed with dead side margins.
      canvasWidth: 1440,
      canvasHeight: 900,
      objects: const [],
    );
    await _persist(
      _document.copyWith(floors: [..._document.floors, floor]),
      message: 'სართული დაემატა',
    );
  }

  Future<void> _renameFloor(EditorFloor floor) async {
    final name = await _promptForName(
      title: 'სართულის გადარქმევა',
      initial: floor.name,
    );
    if (name == null || name == floor.name) return;
    await _persist(
      _document.replaceFloor(floor.copyWith(name: name)),
      message: 'სახელი შეიცვალა',
    );
  }

  Future<void> _duplicateFloor(EditorFloor floor) async {
    final order =
        _document.floors
            .map((entry) => entry.displayOrder)
            .reduce((a, b) => a > b ? a : b) +
        1;
    final legacyFloor = _uniqueLegacyFloor(order);

    // Table numbers are scoped to a floor, so the copy can keep the same
    // numbers — only the definition ids have to be re-keyed to the new floor.
    final copy = EditorFloor(
      zoneId: _uniqueZoneId(order),
      legacyFloor: legacyFloor,
      displayOrder: order,
      name: '${floor.name} (ასლი)',
      canvasWidth: floor.canvasWidth,
      canvasHeight: floor.canvasHeight,
      renderMode: floor.renderMode,
      objects: [
        for (var i = 0; i < floor.objects.length; i++)
          floor.objects[i].duplicated(
            newId: '$legacyFloor-${floor.objects[i].id}',
            newLegacyTableNumber: floor.objects[i].legacyTableNumber,
            newTableDefinitionId: floor.objects[i].isTable
                ? '$legacyFloor-table-${floor.objects[i].legacyTableNumber}'
                : null,
            newLabel: floor.objects[i].label,
          ),
      ],
    );

    await _persist(
      _document.copyWith(floors: [..._document.floors, copy]),
      message: 'სართული დუბლირდა',
    );
  }

  Future<void> _deleteFloor(EditorFloor floor) async {
    if (_document.floors.length <= 1) {
      unawaited(
        showPosToast(
          context: context,
          message: 'ბოლო სართული ვერ წაიშლება',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    final occupied = _occupiedTablesOn(floor);
    if (occupied.isNotEmpty) {
      unawaited(
        showPosToast(
          context: context,
          message:
              'დაკავებული მაგიდები: ${occupied.join(', ')}. '
              'ჯერ დახურეთ მათი შეკვეთები.',
          style: PosToastStyle.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminDesign.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          '„${floor.name}“ წაიშალოს?',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AdminDesign.text,
          ),
        ),
        content: Text(
          'სართული და მისი ${floor.tableCount} მაგიდა სამუდამოდ წაიშლება.',
          style: const TextStyle(fontSize: 13, color: AdminDesign.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AdminDesign.danger),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _persist(
      _document.copyWith(
        floors: [
          for (final entry in _document.floors)
            if (entry.zoneId != floor.zoneId) entry,
        ],
      ),
      message: 'სართული წაიშალა',
    );
  }

  Future<void> _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminDesign.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'საწყის განლაგებაზე დაბრუნება?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AdminDesign.text,
          ),
        ),
        content: const Text(
          'ყველა შენახული ცვლილება დაიკარგება.',
          style: TextStyle(fontSize: 13, color: AdminDesign.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AdminDesign.danger),
            child: const Text('დაბრუნება'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DatabaseService.clearActiveRestaurantTableLayout();
    if (!mounted) return;
    setState(_reload);
    unawaited(
      showPosToast(
        context: context,
        message: 'დაბრუნდა საწყისი განლაგება',
        style: PosToastStyle.info,
      ),
    );
  }

  Future<String?> _promptForName({
    required String title,
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminDesign.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AdminDesign.text,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AdminDesign.panelSoft,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AdminDesign.border),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('გაუქმება'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: AdminDesign.accentDark,
            ),
            child: const Text('დადასტურება'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = result?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _uniqueZoneId(int order) {
    var candidate = 'floor-$order';
    var suffix = order;
    while (_document.floorById(candidate) != null) {
      suffix++;
      candidate = 'floor-$suffix';
    }
    return candidate;
  }

  /// New floors never reuse `'first'`/`'second'` — those keys already own
  /// historical orders and table rows.
  String _uniqueLegacyFloor(int order) {
    final used = {for (final floor in _document.floors) floor.legacyFloor};
    var suffix = order;
    var candidate = 'floor-$suffix';
    while (used.contains(candidate)) {
      suffix++;
      candidate = 'floor-$suffix';
    }
    return candidate;
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final floors = [..._document.floors]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(
            icon: Icons.map_outlined,
            title: 'სართულები და არეალები',
            subtitle:
                'მართეთ სართულები, შემდეგ დახაზეთ თითოეულის გეგმა რედაქტორში.',
            badge: AdminStatusBadge(
              icon: Icons.table_restaurant_outlined,
              label:
                  '${floors.fold(0, (sum, floor) => sum + floor.tableCount)} მაგიდა',
            ),
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _resetToDefault,
                  icon: const Icon(Icons.restart_alt, size: 17),
                  label: const Text('საწყისი'),
                  style: AdminDesign.outlineButtonStyle(),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _isBusy ? null : _addFloor,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('სართულის დამატება'),
                  style: AdminDesign.primaryButtonStyle(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _FloorPlanGridCard(),
          const SizedBox(height: 10),
          if (floors.isEmpty)
            const AdminEmptyState(
              icon: Icons.layers_outlined,
              title: 'სართული არ არის',
              message: 'დაამატეთ პირველი სართული, რომ დაიწყოთ გეგმის შექმნა.',
            )
          else
            for (final floor in floors)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FloorCard(
                  floor: floor,
                  busy: _isBusy,
                  onEdit: () => _openEditor(floor),
                  onRename: () => _renameFloor(floor),
                  onDuplicate: () => _duplicateFloor(floor),
                  onDelete: () => _deleteFloor(floor),
                ),
              ),
        ],
      ),
    );
  }
}

class _FloorCard extends StatelessWidget {
  const _FloorCard({
    required this.floor,
    required this.busy,
    required this.onEdit,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final EditorFloor floor;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;

          final identity = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AdminDesign.accentSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminDesign.border),
                ),
                child: const Icon(
                  Icons.layers_outlined,
                  size: 20,
                  color: AdminDesign.accentDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      floor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AdminDesign.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 14,
                      children: [
                        _Metric(
                          icon: Icons.table_restaurant_outlined,
                          value: '${floor.tableCount} მაგიდა',
                        ),
                        _Metric(
                          icon: Icons.event_seat_outlined,
                          value: '${floor.seatCount} ადგილი',
                        ),
                        _Metric(
                          icon: Icons.category_outlined,
                          value:
                              '${floor.objects.length - floor.tableCount} ობიექტი',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('გეგმის რედაქტირება'),
                style: AdminDesign.primaryButtonStyle(),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                enabled: !busy,
                tooltip: 'დამატებითი',
                icon: const Icon(Icons.more_horiz, size: 20),
                color: AdminDesign.panel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AdminDesign.border),
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      onRename();
                    case 'duplicate':
                      onDuplicate();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('გადარქმევა')),
                  PopupMenuItem(value: 'duplicate', child: Text('დუბლირება')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'წაშლა',
                      style: TextStyle(color: AdminDesign.danger),
                    ),
                  ),
                ],
              ),
            ],
          );

          if (!compact) {
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 12),
                actions,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: VynicFloorTokens.textFaint),
        const SizedBox(width: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AdminDesign.muted,
          ),
        ),
      ],
    );
  }
}

/// POS appearance of the plan the floors below describe.
///
/// It lives on this page — not in Settings → Display — because this is where
/// an administrator is already looking at the floor plan, and it is the only
/// place the preference can be changed.
class _FloorPlanGridCard extends StatelessWidget {
  const _FloorPlanGridCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PosDisplaySettings>(
      valueListenable: PosDisplaySettingsController.settings,
      builder: (context, settings, _) {
        return AdminPanel(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AdminDesign.panelSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminDesign.border),
                ),
                child: Icon(
                  settings.floorPlanGrid
                      ? Icons.grid_on_outlined
                      : Icons.grid_off_outlined,
                  size: 20,
                  color: AdminDesign.muted,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ბადე POS-ის მაგიდების ეკრანზე',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AdminDesign.text,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'გამორთვისას ბადეც და ფონიც იხსნება — გეგმა '
                      'გამჭვირვალედ ჩანს.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AdminDesign.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PosToggle(
                value: settings.floorPlanGrid,
                semanticLabel: 'ბადე',
                // Persisted straight away: this is a one-switch preference,
                // not part of the layout the editor saves.
                onChanged: (value) => unawaited(
                  PosDisplaySettingsController.save(
                    settings.copyWith(floorPlanGrid: value),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
