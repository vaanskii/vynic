import 'package:vynic/core/widgets/pos_text.dart';

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/table_selection_widget.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_operational_status.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

class HomeTablesDashboardSection extends StatelessWidget {
  const HomeTablesDashboardSection({
    super.key,
    required this.textPrimary,
    required this.mutedText,
    required this.tableSelectionKey,
    required this.onSelectionChanged,
    required this.onTableTap,
    required this.onContinueToMenu,
    required this.currentFloor,
    required this.onSwitchFloor,
    required this.onOpenReservations,
    required this.displaySettings,
    this.onQuickCheckout,
  });

  final Color textPrimary;
  final Color mutedText;
  final GlobalKey<TableSelectionWidgetState> tableSelectionKey;
  final VoidCallback onSelectionChanged;
  final ValueChanged<TableModel> onTableTap;
  final VoidCallback onContinueToMenu;
  final VoidCallback? onQuickCheckout;
  final int currentFloor;
  final ValueChanged<int> onSwitchFloor;
  final VoidCallback onOpenReservations;
  final PosDisplaySettings displaySettings;

  /// A single-tap on a free table with nothing else selected fires this
  /// directly — the fast path so opening a table takes one tap instead of
  /// tap-then-continue. Wired to the same handler as the "continue" button.
  VoidCallback get onQuickEnterTable => onContinueToMenu;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutClass = displaySettings.layoutClassForWidth(
          MediaQuery.sizeOf(context).width,
        );
        final narrow = layoutClass.isXs;
        final state = tableSelectionKey.currentState;
        final selected = state?.selectedTableModels.length ?? 0;
        final selecting = state?.multiSelectionMode ?? false;
        final zone = DatabaseService.getRestaurantTableLayout()
            .zoneForDisplayOrder(currentFloor);
        final tables = DatabaseService.getTablesByFloor(
          zone?.legacyFloor ?? 'first',
        );
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 12 : 20,
                12,
                narrow ? 12 : 20,
                12,
              ),
              child: SizedBox(
                width: double.infinity,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _FloorSwitch(
                            key: floorSwitchKey,
                            currentFloor: currentFloor,
                            onSwitchFloor: onSwitchFloor,
                            floors: _floorEntries(),
                          ),
                          _StatusLegend(
                            compact: constraints.maxWidth < 1000,
                            free: tables
                                .where(
                                  (t) =>
                                      t.operationalStatus ==
                                      TableOperationalStatus.free,
                                )
                                .length,
                            occupied: tables
                                .where(
                                  (t) =>
                                      t.operationalStatus ==
                                      TableOperationalStatus.occupied,
                                )
                                .length,
                            reserved: tables
                                .where(
                                  (t) =>
                                      t.operationalStatus ==
                                      TableOperationalStatus.reserved,
                                )
                                .length,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 12 : 20,
                  0,
                  narrow ? 12 : 20,
                  narrow ? 12 : 20,
                ),
                child: _TableActionWorkspace(
                  plan: _buildPlanPanel(
                    narrow: narrow,
                    layoutClass: layoutClass,
                  ),
                  selected: selected,
                  selecting: selecting,
                  onQuickCheckout: onQuickCheckout,
                  onToggleSelection: () => tableSelectionKey.currentState
                      ?.toggleMultiSelectionMode(),
                  onContinue: onContinueToMenu,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlanPanel({
    required bool narrow,
    required PosLayoutClass layoutClass,
  }) {
    return Container(
      key: planPanelKey,
      decoration: BoxDecoration(
        color: VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TableSelectionWidget(
                key: tableSelectionKey,
                currentFloor: currentFloor,
                onSelectionChanged: onSelectionChanged,
                onTableTap: onTableTap,
                onQuickEnterTable: onQuickEnterTable,
                tableTileSize: displaySettings.tableTileSize,
                layoutClass: layoutClass,
                showFloorPlanGrid: displaySettings.floorPlanGrid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<({int floor, String label, String free})> _floorEntries() {
    final zones = [...DatabaseService.getRestaurantTableLayout().zones]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return [
      for (final zone in zones)
        (
          floor: zone.displayOrder,
          label: zone.name,
          free:
              '${DatabaseService.getTablesByFloor(zone.legacyFloor).where((table) => table.operationalStatus == TableOperationalStatus.free).length}',
        ),
    ];
  }
}

class _FloorSwitch extends StatelessWidget {
  const _FloorSwitch({
    super.key,
    required this.currentFloor,
    required this.onSwitchFloor,
    required this.floors,
  });

  final int currentFloor;
  final ValueChanged<int> onSwitchFloor;
  final List<({int floor, String label, String free})> floors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(VynicFloorTokens.switchRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < floors.length; i++) ...[
            if (i != 0) const SizedBox(width: 4),
            _FloorTab(
              label: floors[i].label,
              count: floors[i].free,
              selected: floors[i].floor == currentFloor,
              onTap: floors[i].floor == currentFloor
                  ? null
                  : () => onSwitchFloor(floors[i].floor),
            ),
          ],
        ],
      ),
    );
  }
}

class _FloorTab extends StatelessWidget {
  const _FloorTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VynicFloorTokens.switchButtonRadius),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? VynicFloorTokens.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(
            VynicFloorTokens.switchButtonRadius,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PosText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? VynicFloorTokens.accentText
                    : VynicFloorTokens.textMuted,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Free / occupied / reserved key for the plan's tile colours.
class _StatusLegend extends StatelessWidget {
  const _StatusLegend({
    required this.free,
    required this.occupied,
    required this.reserved,
    required this.compact,
  });
  final int free, occupied, reserved;
  final bool compact;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: compact ? 12 : 16,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final entry in <(Color, String, int, Key)>[
        (VynicFloorTokens.freeDot, 'თავისუფალი', free, homeFreeCountKey),
        (
          VynicFloorTokens.occupiedDot,
          'დაკავებული',
          occupied,
          homeOccupiedCountKey,
        ),
        (
          VynicFloorTokens.reservedDot,
          'რეზერვი',
          reserved,
          const Key('home-tables-reserved-count'),
        ),
      ])
        Tooltip(
          message: '${entry.$2}: ${entry.$3}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: entry.$1,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              if (!compact) ...[
                Text(
                  entry.$2,
                  style: const TextStyle(
                    fontSize: 12,
                    color: VynicFloorTokens.textMuted,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                '${entry.$3}',
                key: entry.$4,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: VynicFloorTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Drawer occupies its own layout column. It never intercepts table hits.
class _TableActionWorkspace extends StatefulWidget {
  const _TableActionWorkspace({
    required this.plan,
    required this.selected,
    required this.selecting,
    required this.onQuickCheckout,
    required this.onToggleSelection,
    required this.onContinue,
  });
  final Widget plan;
  final int selected;
  final bool selecting;
  final VoidCallback? onQuickCheckout;
  final VoidCallback onToggleSelection, onContinue;
  @override
  State<_TableActionWorkspace> createState() => _TableActionWorkspaceState();
}

class _TableActionWorkspaceState extends State<_TableActionWorkspace> {
  bool expanded = false;
  @override
  void didUpdateWidget(covariant _TableActionWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected > 0 && oldWidget.selected == 0) expanded = true;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth * 0.26).clamp(180.0, 232.0);
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.plan),
          const SizedBox(width: 8),
          AnimatedContainer(
            key: const Key('home-table-actions-column'),
            width: expanded ? width : 44,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: ExcludeSemantics(
                        excluding: !expanded,
                        child: FocusScope(
                          canRequestFocus: expanded,
                          child: AnimatedOpacity(
                            duration: duration,
                            opacity: expanded ? 1 : 0,
                            child: OverflowBox(
                              alignment: Alignment.topRight,
                              minWidth: width,
                              maxWidth: width,
                              child: Container(
                                width: width,
                                decoration: BoxDecoration(
                                  color: VynicFloorTokens.panel,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: VynicFloorTokens.panelBorder,
                                  ),
                                ),
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    14,
                                    14,
                                    18,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(right: 32),
                                        child: Text(
                                          'მოქმედებები',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: VynicFloorTokens.text,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      if (widget.onQuickCheckout != null) ...[
                                        _ToolbarAction(
                                          label: 'სწრაფი გაყიდვა',
                                          icon: Icons.payments_outlined,
                                          onPressed: widget.onQuickCheckout,
                                        ),
                                        const SizedBox(height: 20),
                                        const Divider(
                                          height: 1,
                                          color: VynicFloorTokens.panelBorder,
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                      const Text(
                                        'მაგიდები',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: VynicFloorTokens.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _ToolbarAction(
                                        key: const Key(
                                          'home-table-multi-select',
                                        ),
                                        label: widget.selecting
                                            ? 'არჩევის დასრულება'
                                            : 'გაერთიანება',
                                        icon: widget.selecting
                                            ? Icons.check_box_outlined
                                            : Icons.join_inner,
                                        selected: widget.selecting,
                                        onPressed: widget.onToggleSelection,
                                      ),
                                      if (widget.selecting)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 12),
                                          child: Text(
                                            'აირჩიეთ გვერდიგვერდ თავისუფალი მაგიდები.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.5,
                                              color: VynicFloorTokens.textMuted,
                                            ),
                                          ),
                                        ),
                                      if (widget.selected > 0) ...[
                                        const SizedBox(height: 12),
                                        _ToolbarAction(
                                          label: 'მენიუ (${widget.selected})',
                                          icon: Icons.restaurant_menu,
                                          onPressed: widget.onContinue,
                                          selected: true,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 2,
                    width: 44,
                    height: 44,
                    child: IconButton(
                      key: const Key('home-table-actions-toggle'),
                      tooltip: expanded
                          ? 'მოქმედებების დახურვა'
                          : 'მოქმედებების გახსნა',
                      style: IconButton.styleFrom(
                        foregroundColor: VynicFloorTokens.accentText,
                        backgroundColor: expanded
                            ? Colors.transparent
                            : VynicFloorTokens.accentSoft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: Icon(
                        expanded ? Icons.chevron_right : Icons.chevron_left,
                        size: 22,
                      ),
                      onPressed: () => setState(() => expanded = !expanded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      foregroundColor: selected
          ? VynicFloorTokens.accentText
          : VynicFloorTokens.text,
      backgroundColor: selected
          ? VynicFloorTokens.accentSoft
          : VynicFloorTokens.panel,
      side: BorderSide(
        color: selected
            ? VynicFloorTokens.accentBadgeText
            : VynicFloorTokens.panelBorder,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    icon: Icon(icon, size: 18),
    label: PosText(label),
  );
}

const Key floorSwitchKey = Key('home-tables-floor-switch');
const Key planPanelKey = Key('home-tables-plan-panel');
const Key homeFreeCountKey = Key('home-tables-free-count');
const Key homeOccupiedCountKey = Key('home-tables-occupied-count');
