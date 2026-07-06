import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_staff_admin_rail.dart';
import 'package:vynic/apps/windows_pos/widgets/home/table_status_presentation.dart';
import 'package:vynic/apps/windows_pos/widgets/table_selection_widget.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_operational_status.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_shadows.dart';
import 'package:vynic/core/ui/widgets/vynic_status_chip.dart';

class HomeTablesDashboardSection extends StatelessWidget {
  const HomeTablesDashboardSection({
    super.key,
    required this.username,
    required this.roleLabel,
    required this.textPrimary,
    required this.mutedText,
    required this.tableSelectionKey,
    required this.onSelectionChanged,
    required this.onTableTap,
    required this.onContinueToMenu,
    required this.currentFloor,
    required this.onSwitchFloor,
    this.onStaffSwitchTap,
    this.onOpenAdminPanel,
  });

  /// The staff member currently operating the POS and their role — shown at
  /// the bottom of the side rail, below the table metrics.
  final String username;
  final String roleLabel;
  final Color textPrimary;
  final Color mutedText;
  final GlobalKey<TableSelectionWidgetState> tableSelectionKey;
  final VoidCallback onSelectionChanged;
  final ValueChanged<TableModel> onTableTap;
  final VoidCallback onContinueToMenu;
  final int currentFloor;
  final ValueChanged<int> onSwitchFloor;

  /// Tapping the staff card locks the terminal (PIN required to continue /
  /// switch). Null hides the lock affordance (card stays static).
  final VoidCallback? onStaffSwitchTap;

  /// Opens the Management Center. Null hides the button entirely — the
  /// caller only passes this for manager/supervisor (`canAccessManagementCenter`),
  /// matching every other admin-panel entry point in the app.
  final VoidCallback? onOpenAdminPanel;

  /// A single-tap on a free table with nothing else selected fires this
  /// directly — the fast path so opening a table takes one tap instead of
  /// tap-then-continue. Wired to the same handler as the "continue" button.
  VoidCallback get onQuickEnterTable => onContinueToMenu;

  @override
  Widget build(BuildContext context) {
    final layout = DatabaseService.getRestaurantTableLayout();
    final currentZone =
        layout.zoneForDisplayOrder(currentFloor) ?? layout.zones.first;
    final floorName = currentZone.legacyFloor;
    final tables = DatabaseService.getTablesByFloor(floorName);
    // Counted via TableOperationalStatus (not the raw `isReserved` boolean,
    // which is also true for occupied tables) so "თავისუფალი"/"დაკავებული"
    // actually mean free/occupied, and reserved-but-not-yet-seated gets its
    // own accurate count instead of being folded into "occupied".
    final freeCount = tables
        .where((t) => t.operationalStatus == TableOperationalStatus.free)
        .length;
    final occupiedCount = tables
        .where((t) => t.operationalStatus == TableOperationalStatus.occupied)
        .length;
    final reservedCount = tables
        .where((t) => t.operationalStatus == TableOperationalStatus.reserved)
        .length;
    final metrics = [
      _FloorMetricData(
        icon: Icons.table_restaurant_outlined,
        iconColor: const Color(0xFF075E6B),
        label: 'სულ მაგიდები',
        value: '${tables.length}',
      ),
      _FloorMetricData(
        icon: Icons.event_available_outlined,
        iconColor: const Color(0xFF047857),
        label: 'თავისუფალი',
        value: '$freeCount',
      ),
      _FloorMetricData(
        icon: Icons.receipt_long_outlined,
        iconColor: VynicColors.info,
        label: 'დაკავებული',
        value: '$occupiedCount',
      ),
      _FloorMetricData(
        icon: Icons.event_outlined,
        iconColor: const Color(0xFFB45309),
        label: 'დაჯავშნილი',
        value: '$reservedCount',
      ),
    ];

    // Deliberately checked against the window's actual logical width
    // (MediaQuery), not the LayoutBuilder's `constraints.maxWidth` — this
    // widget sits inside `home_screen.dart`'s 16px-each-side content padding,
    // so `constraints.maxWidth` here is already ~32px short of the real
    // window width. At a nominal 1024px-wide window that reads as 992,
    // which is why an earlier version of this threshold (compared against
    // `constraints.maxWidth >= 1000`) still silently fell back to the
    // stacked layout at 1024×768 despite the fix's intent. Comparing
    // against the true window width avoids depending on exactly how much
    // padding sits between the window edge and this widget.
    final windowWidth = MediaQuery.sizeOf(context).width;
    // Not the shared `VynicBreakpoints.compactMax` (1100px) either: that's
    // tuned for screens in general, but this screen's side rail is a fixed
    // 220px, so it comfortably fits next to the floor plan down to
    // ~1000px — and the side rail is strictly better for the floor plan
    // than the stacked fallback at any width where it fits, since it skips
    // stacking heading/floor-card/selection-overview ABOVE the canvas
    // (stacked mode leaves the floor plan roughly 250px shorter at the same
    // window height). The shared 1100px threshold was pushing 1024×768 — a
    // real supported POS resolution — into the strictly worse stacked
    // layout for no width reason.
    final useSideRailLayout = windowWidth >= 1000;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
      child: useSideRailLayout
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 220px (down from 260px) — the floor switch inside the
                // rail now stacks its buttons vertically instead of side by
                // side, so the rail needs less width, leaving more of it to
                // the floor plan.
                SizedBox(width: 220, child: _buildControlRail(metrics)),
                const SizedBox(width: 14),
                Expanded(child: _buildPlanPanel(showHeader: false)),
              ],
            )
          // Stacked/compact mode: every row here eats into the floor plan's
          // vertical budget, so the heading is shrunk and the selection card
          // collapses to a one-line hint when idle. The chrome (heading +
          // floor card + selection overview) is wrapped in a scroll view as
          // a safety net — if a window is ever so short that even this
          // shrunk chrome doesn't fit, it scrolls instead of overflowing.
          // The floor plan itself stays outside the scroll view (it needs
          // bounded height to do its own scale-to-fit math), so it still
          // gets whatever height remains, however little.
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPageHeading(compact: true),
                      const SizedBox(height: 10),
                      _buildFloorControlCard(),
                      const SizedBox(height: 10),
                      _buildSelectionOverview(),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(child: _buildPlanPanel(showHeader: true)),
              ],
            ),
    );
  }

  Widget _buildControlRail(List<_FloorMetricData> metrics) {
    // The staff card + admin button are pinned outside the Expanded so they
    // always render, at the bottom of the rail. Everything above them
    // (heading, floor card, selection overview, metrics) lives inside an
    // Expanded+SingleChildScrollView instead of a bare Column: at tight
    // heights (e.g. 1024×768, where these fixed-height pieces plus the
    // staff/admin footer add up to more than the rail actually has room
    // for) it scrolls instead of overflowing the rail.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPageHeading(compact: true),
                const SizedBox(height: 12),
                _buildFloorControlCard(),
                const SizedBox(height: 12),
                _buildSelectionOverview(),
                const SizedBox(height: 12),
                for (final metric in metrics) ...[
                  _FloorMetricCard(
                    icon: metric.icon,
                    iconColor: metric.iconColor,
                    label: metric.label,
                    value: metric.value,
                    compact: true,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        HomeStaffAdminRail(
          username: username,
          roleLabel: roleLabel,
          onStaffSwitchTap: onStaffSwitchTap,
          onOpenAdminPanel: onOpenAdminPanel,
        ),
      ],
    );
  }

  Widget _buildSelectionOverview() {
    final state = tableSelectionKey.currentState;
    final focusedBusyTables =
        state?.focusedReservedTables ?? const <TableModel>[];
    final focusedBusyTable = focusedBusyTables.isNotEmpty
        ? focusedBusyTables.first
        : null;
    final selectedTables = state?.selectedTableModels ?? const <TableModel>[];
    final hasFreeSelection = selectedTables.isNotEmpty;
    final hasBusySelection = focusedBusyTable != null;

    // Reserved/occupied tables open immediately on tap (see
    // TableSelectionWidgetState._handleTableTap) — there's no "continue"
    // decision to make here anymore, so this is just a brief, non-
    // interactive acknowledgement while the async order lookup/activation
    // completes, not a card the user is meant to act on.
    if (hasBusySelection) {
      final presentation = TableStatusPresentation.of(focusedBusyTable);
      final tableNumbers = focusedBusyTables
          .map((table) => table.tableNumber)
          .join(', ');
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: VynicColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFB45309).withValues(alpha: 0.24),
          ),
          boxShadow: VynicShadows.panel,
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFB45309),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$tableNumbers • იხსნება...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            VynicStatusChip.forState(
              label: presentation.label,
              state: presentation.vynicState,
              icon: presentation.icon,
            ),
          ],
        ),
      );
    }

    // Nothing selected — no card at all. It used to show an "აირჩიეთ
    // მაგიდა" hint here (a full card, or a slim one-liner in compact mode),
    // but that idle state doesn't need to occupy space in the rail; the
    // floor plan itself is the affordance for picking a table.
    if (!hasFreeSelection) {
      return const SizedBox.shrink();
    }

    const statusColor = Color(0xFF047857);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VynicColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.24)),
        boxShadow: VynicShadows.panel,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'არჩეული მაგიდები',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'გააგრძელეთ მენიუში შეკვეთის შესაქმნელად',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: mutedText, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _OverviewLine(
            icon: Icons.table_bar_outlined,
            label: 'არჩეული',
            value: selectedTables.map((table) => table.tableNumber).join(', '),
          ),
          const SizedBox(height: 7),
          _OverviewLine(
            icon: Icons.layers_outlined,
            label: 'სართული',
            value: currentFloor == 1 ? 'პირველი' : 'მეორე',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onContinueToMenu,
            style: FilledButton.styleFrom(
              backgroundColor: statusColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              disabledForegroundColor: const Color(0xFF64748B),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
            label: const Text(
              'მენიუში გადასვლა',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanPanel({required bool showHeader}) {
    return Container(
      decoration: BoxDecoration(
        color: VynicColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VynicColors.border),
        boxShadow: VynicShadows.panel,
      ),
      child: Column(
        children: [
          if (showHeader) ...[
            _buildFloorPanelHeader(),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
          ],
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(showHeader ? 10 : 8),
              child: TableSelectionWidget(
                key: tableSelectionKey,
                currentFloor: currentFloor,
                onSelectionChanged: onSelectionChanged,
                onTableTap: onTableTap,
                onQuickEnterTable: onQuickEnterTable,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloorPanelHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.layers_outlined,
                  color: Color(0xFF075E6B),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'სართული',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _FloorSwitch(
            currentFloor: currentFloor,
            activeColor: const Color(0xFF075E6B),
            mutedText: mutedText,
            onSwitchFloor: onSwitchFloor,
            floors: _floorEntries(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloorControlCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VynicColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VynicColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.layers_outlined,
                color: Color(0xFF075E6B),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'სართული',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _FloorSwitch(
            currentFloor: currentFloor,
            activeColor: const Color(0xFF075E6B),
            mutedText: mutedText,
            onSwitchFloor: onSwitchFloor,
            floors: _floorEntries(),
            vertical: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeading({bool compact = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 42 : 48,
          height: compact ? 42 : 48,
          decoration: BoxDecoration(
            color: const Color(0xFF075E6B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(compact ? 13 : 16),
          ),
          child: Icon(
            Icons.restaurant_outlined,
            color: const Color(0xFF075E6B),
            size: compact ? 22 : 24,
          ),
        ),
        SizedBox(width: compact ? 12 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'მაგიდები',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: compact ? 22 : 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                Text(
                  'აირჩიეთ სართული და მონიშნეთ მაგიდები შეკვეთის დასაწყებად.',
                  style: TextStyle(color: mutedText, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<({int floor, String label})> _floorEntries() {
    final zones = [...DatabaseService.getRestaurantTableLayout().zones]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return [
      for (final zone in zones) (floor: zone.displayOrder, label: zone.name),
    ];
  }
}

class _FloorSwitch extends StatelessWidget {
  const _FloorSwitch({
    required this.currentFloor,
    required this.activeColor,
    required this.mutedText,
    required this.onSwitchFloor,
    required this.floors,
    this.vertical = false,
  });

  final int currentFloor;
  final Color activeColor;
  final Color mutedText;
  final ValueChanged<int> onSwitchFloor;
  final List<({int floor, String label})> floors;

  /// Stacks the floor buttons top-to-bottom instead of side-by-side — used
  /// in the rail's floor control card so the switch takes less width,
  /// leaving more of the rail's fixed width for the floor plan next to it.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: vertical
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < floors.length; i++) ...[
                  _buildFloorButton(floors[i], fullWidth: true),
                  if (i != floors.length - 1) const SizedBox(height: 4),
                ],
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (final floor in floors) _buildFloorButton(floor)],
            ),
    );
  }

  Widget _buildFloorButton(
    ({int floor, String label}) floor, {
    bool fullWidth = false,
  }) {
    return InkWell(
      onTap: floor.floor == currentFloor
          ? null
          : () => onSwitchFloor(floor.floor),
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: fullWidth ? null : 104,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: floor.floor == currentFloor ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(7),
          boxShadow: floor.floor == currentFloor
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          floor.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: floor.floor == currentFloor ? Colors.white : mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _FloorMetricCard extends StatelessWidget {
  const _FloorMetricCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.compact = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 72 : 84,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      decoration: BoxDecoration(
        color: VynicColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VynicColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 48,
            height: compact ? 40 : 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(compact ? 11 : 13),
            ),
            child: Icon(icon, color: iconColor, size: compact ? 21 : 25),
          ),
          SizedBox(width: compact ? 10 : 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5B677A),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF102033),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewLine extends StatelessWidget {
  const _OverviewLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 7),
        SizedBox(
          width: 70,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF102033),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _FloorMetricData {
  const _FloorMetricData({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
}
