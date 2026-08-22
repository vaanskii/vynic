import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/home/table_status_presentation.dart';
import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_names.dart';
import 'package:vynic/apps/windows_pos/widgets/table_selection_widget.dart';
import 'package:vynic/core/models/pos_display_settings.dart';
import 'package:vynic/core/models/order_status.dart';
import 'package:vynic/core/models/reservation.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/models/table_operational_status.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/ui/vynic_radius.dart';
import 'package:vynic/core/ui/vynic_shadows.dart';
import 'package:vynic/core/ui/widgets/vynic_status_chip.dart';
import 'package:vynic/core/utils/home_reservations_helper.dart';
import 'package:vynic/core/utils/reservation_table_availability.dart';

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
  });

  final Color textPrimary;
  final Color mutedText;
  final GlobalKey<TableSelectionWidgetState> tableSelectionKey;
  final VoidCallback onSelectionChanged;
  final ValueChanged<TableModel> onTableTap;
  final VoidCallback onContinueToMenu;
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
        icon: Icons.event_available_outlined,
        iconColor: VynicColors.neutral,
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
        iconColor: VynicColors.warning,
        label: 'დაჯავშნილი',
        value: '$reservedCount',
      ),
      _FloorMetricData(
        icon: Icons.payments_outlined,
        iconColor: VynicColors.danger,
        label: 'გადასახდელი',
        value: '${_paymentAttentionItems(tables).length}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final windowWidth = MediaQuery.sizeOf(context).width;
        final layoutClass = displaySettings.layoutClassForWidth(windowWidth);
        final density = displaySettings.effectiveDensityForWidth(windowWidth);
        final compact = density == PosUiDensity.compact;
        final narrow = layoutClass.isXs;
        final railWidth = layoutClass.sideRailWidth;
        // Gate on the width this section actually got — not on the window —
        // so a collapsed sidebar earns the rail back at 1024x768 instead of
        // dropping it into a sheet.
        final useSideRailLayout =
            constraints.maxWidth >= layoutClass.minWidthForInlineRail;
        final sideRail = _buildSideRail(metrics, density: density);

        return Column(
          children: [
            _buildOperationsBar(compact: compact, narrow: narrow),
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    // No top padding: the operations row above already ends
                    // with a 12px gap, and adding another 20 here is what put
                    // visibly more space under the floor tabs than above them.
                    padding: EdgeInsets.fromLTRB(
                      narrow ? 12 : 20,
                      0,
                      narrow ? 12 : 20,
                      narrow ? 12 : 20,
                    ),
                    child: useSideRailLayout
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _buildPlanPanel(
                                  narrow: narrow,
                                  layoutClass: layoutClass,
                                ),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(width: railWidth, child: sideRail),
                            ],
                          )
                        : _buildPlanPanel(
                            narrow: narrow,
                            layoutClass: layoutClass,
                          ),
                  ),
                  if (!useSideRailLayout)
                    Positioned(
                      left: narrow ? 20 : 28,
                      right: narrow ? 20 : 28,
                      bottom: narrow ? 16 : 24,
                      child: _BottomServiceButton(
                        metrics: metrics,
                        compact: compact,
                        onTap: () => _showCompactSideRail(context, sideRail),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSideRail(
    List<_FloorMetricData> metrics, {
    required PosUiDensity density,
  }) {
    final compact = density == PosUiDensity.compact;
    final alerts = _paymentAttentionItems(
      DatabaseService.getTablesByFloor(
        (DatabaseService.getRestaurantTableLayout().zoneForDisplayOrder(
                  currentFloor,
                ) ??
                DatabaseService.getRestaurantTableLayout().zones.first)
            .legacyFloor,
      ),
    );
    final reservations = _nextReservations().take(4).toList();

    return Container(
      decoration: BoxDecoration(
        color: VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(VynicFloorTokens.panelRadius),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SelectionRailSlot(child: _buildSelectionOverview()),
            _RailSection(
              title: 'SERVICE RIGHT NOW',
              // The rail is narrower on small terminals, so the tiles are
              // sized from the width they actually get. Without this the
              // fixed aspect ratio squeezes them below the height their
              // label+value needs and the grid overflows.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final tileWidth = (constraints.maxWidth - spacing) / 2;
                  final baseRatio = compact ? 1.5 : 1.36;
                  return GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: math.min(
                      baseRatio,
                      tileWidth / _railMetricMinHeight,
                    ),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final metric in metrics) _RailMetric(metric: metric),
                    ],
                  );
                },
              ),
            ),
            _RailSection(
              title: 'NEEDS ATTENTION',
              trailing: Text(
                '${alerts.length}',
                style: TextStyle(
                  color: alerts.isEmpty
                      ? VynicFloorTokens.sectionLabel
                      : VynicColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: alerts.isEmpty
                  ? const _RailEmptyText('ყურადღება არ სჭირდება')
                  : Column(
                      children: [
                        for (var i = 0; i < alerts.length && i < 3; i++) ...[
                          _AttentionCard(item: alerts[i]),
                          if (i != alerts.length - 1 && i < 2)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
            _RailSection(
              title: 'NEXT RESERVATIONS',
              trailing: InkWell(
                onTap: onOpenReservations,
                borderRadius: VynicRadius.smAll,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'ყველა',
                    style: TextStyle(
                      color: VynicFloorTokens.accentBadgeText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              child: reservations.isEmpty
                  ? const _RailEmptyText('შემდეგი რეზერვაცია არ არის')
                  : Column(
                      children: [
                        for (var i = 0; i < reservations.length; i++) ...[
                          _ReservationRailCard(
                            reservation: reservations[i],
                            onViewAll: onOpenReservations,
                          ),
                          if (i != reservations.length - 1)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Floor tabs plus the status legend, sitting directly on the page.
  ///
  /// No surface of its own: in the mock the white floor-switch pill is the
  /// only raised thing in this row, and giving the row a white bar of its own
  /// made that pill disappear into it.
  Widget _buildOperationsBar({required bool compact, required bool narrow}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(narrow ? 12 : 20, 14, narrow ? 12 : 20, 12),
      // Row, not Wrap: Wrap sizes each run to its tallest child and aligns the
      // rest to the run's top, which left the tabs and the legend sitting high
      // against the taller of the two. A Row centres both on one baseline.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _FloorSwitch(
            key: floorSwitchKey,
            currentFloor: currentFloor,
            onSwitchFloor: onSwitchFloor,
            floors: _floorEntries(),
          ),
          const SizedBox(width: 16),
          const Flexible(child: _StatusLegend()),
        ],
      ),
    );
  }

  Future<void> _showCompactSideRail(BuildContext context, Widget sideRail) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: size.height * 0.82,
            ),
            decoration: BoxDecoration(
              color: VynicColors.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border.all(color: VynicColors.border),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: sideRail,
            ),
          ),
        );
      },
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
      final tableNumbers = focusedBusyTables.map(_tableName).join(', ');
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

    // The selection accent, not the old green: selecting tables is the same
    // action the floor plan tints in lavender, so the card has to agree with it.
    const statusColor = VynicFloorTokens.accentText;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VynicFloorTokens.accentSoft,
        borderRadius: BorderRadius.circular(VynicFloorTokens.metricRadius),
        border: Border.all(
          color: VynicFloorTokens.accentBadgeText.withValues(alpha: 0.35),
        ),
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
                  color: VynicFloorTokens.panel,
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
                    const Text(
                      'არჩეული მაგიდები',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: VynicFloorTokens.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'გააგრძელეთ მენიუში შეკვეთის შესაქმნელად',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: VynicFloorTokens.textMuted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _OverviewLine(
            icon: Icons.table_bar_outlined,
            label: 'არჩეული',
            value: selectedTables.map(_tableName).join(', '),
          ),
          const SizedBox(height: 8),
          _OverviewLine(
            icon: Icons.layers_outlined,
            label: 'სართული',
            value: _currentFloorLabel(),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onContinueToMenu,
            style: FilledButton.styleFrom(
              backgroundColor: statusColor,
              foregroundColor: VynicFloorTokens.panel,
              disabledBackgroundColor: VynicFloorTokens.badgeFill,
              disabledForegroundColor: VynicFloorTokens.textFaint,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
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
              padding: EdgeInsets.all(narrow ? 12 : 16),
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

  /// What a live table row is called on screen: the name set in the floor
  /// editor, falling back to „მაგიდა N" for a row whose layout entry is gone.
  String _tableName(TableModel table) {
    return floorPlanTableName(
          DatabaseService.getRestaurantTableLayout(),
          floor: table.floor,
          tableNumber: table.tableNumber,
        ) ??
        'მაგიდა ${table.tableNumber}';
  }

  String _currentFloorLabel() {
    for (final floor in _floorEntries()) {
      if (floor.floor == currentFloor) return floor.label;
    }
    return 'სართული $currentFloor';
  }

  List<_AttentionItem> _paymentAttentionItems(List<TableModel> tables) {
    final items = <_AttentionItem>[];
    for (final table in tables) {
      final orderId = table.activeOrderId;
      if (orderId == null) continue;
      final order = DatabaseService.getOrder(orderId);
      if (order == null || order.statusEnum != OrderStatus.served) continue;
      items.add(
        _AttentionItem(
          title: _tableName(table),
          detail:
              '${order.totalAmount.toStringAsFixed(2)} ₾ · ${order.createdBy}',
          time: _elapsedSince(order.createdAt),
        ),
      );
    }
    return items;
  }

  List<Reservation> _nextReservations() {
    final currentDate = DatabaseService.getCurrentDate();
    final reservations = HomeReservationsHelper.getAdminPanelReservations()
        .where((reservation) {
          if (reservation.isTakeAway) return false;
          if (!HomeReservationsHelper.isSameDate(
            reservation.reservationDate,
            currentDate,
          )) {
            return false;
          }
          final status = HomeReservationsHelper.normalizeStatus(
            reservation.status,
          );
          return status.startsWith('confirmed') || status.startsWith('pending');
        })
        .toList();
    reservations.sort((a, b) => a.reservationTime.compareTo(b.reservationTime));
    return reservations;
  }

  static String _elapsedSince(DateTime startedAt) {
    // Business clock, not the wall clock: orders carry the business date with
    // the current time of day, so DateTime.now() measures the gap between the
    // two calendars whenever the venue's business day is not today.
    final elapsed = DatabaseService.getCurrentDateTime().difference(startedAt);
    if (elapsed.inMinutes < 1) return 'ახლახან';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} წთ';
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${elapsed.inHours}:$minutes';
  }
}

class _BottomServiceButton extends StatelessWidget {
  const _BottomServiceButton({
    required this.metrics,
    required this.compact,
    required this.onTap,
  });

  final List<_FloorMetricData> metrics;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = metrics.take(3).toList();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: compact ? 54 : 60,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
          decoration: BoxDecoration(
            color: VynicColors.accentHover,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: VynicColors.textPrimary.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.dashboard_customize_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Text(
                'SERVICE RIGHT NOW',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              for (var i = 0; i < preview.length; i++) ...[
                _BottomServiceMetric(metric: preview[i]),
                if (i != preview.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomServiceMetric extends StatelessWidget {
  const _BottomServiceMetric({required this.metric});

  final _FloorMetricData metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: VynicRadius.smAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        metric.value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Floor tabs. A white pill on the page, with the active tab as a pale
/// lavender chip — not a saturated fill.
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
            Text(
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
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: selected
                    ? VynicFloorTokens.panel
                    : VynicFloorTokens.badgeFill,
                borderRadius: BorderRadius.circular(
                  VynicFloorTokens.badgeRadius,
                ),
              ),
              child: Text(
                count,
                style: TextStyle(
                  color: selected
                      ? VynicFloorTokens.accentBadgeText
                      : VynicFloorTokens.textFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
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
  const _StatusLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.start,
      children: [
        for (final entry in const <(Color, String)>[
          (VynicFloorTokens.freeDot, 'თავისუფალი'),
          (VynicFloorTokens.occupiedDot, 'დაკავებული'),
          (VynicFloorTokens.reservedDot, 'რეზერვი'),
        ])
          Row(
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
              const SizedBox(width: 7),
              Text(
                entry.$2,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: VynicFloorTokens.textMuted,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _RailSection extends StatelessWidget {
  const _RailSection({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // The mock separates sections with an 18px gap and a hairline rule rather
    // than giving each one a boxed-in border, so the rail reads as one column.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VynicFloorTokens.sectionLabel,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.99,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 12),
        child,
        const SizedBox(height: 18),
        Container(height: 1, color: VynicFloorTokens.divider),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _SelectionRailSlot extends StatelessWidget {
  const _SelectionRailSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (child is SizedBox) return child;
    // The rail already pads its own sides, so this only needs to keep the card
    // off the section beneath it — the old 16px inset doubled up and the
    // missing bottom gap left the card touching the next heading.
    return Padding(padding: const EdgeInsets.only(bottom: 18), child: child);
  }
}

/// Test hooks for the vertical rhythm of the operations row: the gap above the
/// floor tabs and the gap below them (to the plan panel) have to stay equal, or
/// the tabs read as sitting too high.
const Key floorSwitchKey = Key('home-tables-floor-switch');
const Key planPanelKey = Key('home-tables-plan-panel');

/// Vertical space a [_RailMetric] needs: a 1px border and 8px padding top and
/// bottom, an 11px label, a 3px gap and an 18px value. Georgian glyphs sit
/// taller than Latin ones at the same point size, so this is measured from
/// the rendered result rather than from the nominal font sizes.
const double _railMetricMinHeight = 74;

class _RailMetric extends StatelessWidget {
  const _RailMetric({required this.metric});

  final _FloorMetricData metric;

  /// Occupied is the one metric the mock tints; the rest sit on a neutral
  /// fill so the amber actually means something.
  bool get _isOccupied => metric.iconColor == VynicColors.warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isOccupied
            ? VynicFloorTokens.occupiedTileFill
            : VynicFloorTokens.metricFill,
        borderRadius: BorderRadius.circular(VynicFloorTokens.metricRadius),
      ),
      // scaleDown is the backstop: the grid reserves
      // [_railMetricMinHeight], but a longer translation or a taller fallback
      // font must shrink the text rather than overflow it.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isOccupied
                    ? VynicFloorTokens.occupiedMeta
                    : VynicFloorTokens.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              metric.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isOccupied
                    ? VynicFloorTokens.occupiedValue
                    : VynicFloorTokens.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.item});

  final _AttentionItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VynicColors.dangerSoft,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: VynicColors.dangerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: VynicColors.danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VynicColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                item.time,
                style: const TextStyle(
                  color: VynicColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            item.detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: VynicColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReservationRailCard extends StatelessWidget {
  const _ReservationRailCard({
    required this.reservation,
    required this.onViewAll,
  });

  final Reservation reservation;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final layout = DatabaseService.getRestaurantTableLayout();
    final tables = ReservationTableAvailability.tableRefsOf(reservation)
        .map(
          (ref) => floorPlanTableNameOrNumber(
            layout,
            floor: ref.floor,
            tableNumber: ref.tableNumber,
          ),
        )
        .join(', ');
    final detail = [
      if (reservation.numberOfGuests > 0)
        '${reservation.numberOfGuests} სტუმარი',
      if (tables.isNotEmpty) tables,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: VynicColors.card,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: VynicColors.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  reservation.customerName.trim().isEmpty
                      ? 'რეზერვაცია'
                      : reservation.customerName.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VynicColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                reservation.reservationTime,
                style: const TextStyle(
                  color: VynicColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  detail.isEmpty ? 'მაგიდა არ არის არჩეული' : detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VynicColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                onTap: onViewAll,
                child: const Text(
                  'სუფრაზე',
                  style: TextStyle(
                    color: VynicColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RailEmptyText extends StatelessWidget {
  const _RailEmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: VynicColors.neutral,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AttentionItem {
  const _AttentionItem({
    required this.title,
    required this.detail,
    required this.time,
  });

  final String title;
  final String detail;
  final String time;
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
