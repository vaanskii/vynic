import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/table_selection_widget.dart';
import 'package:vynic/core/models/table.dart';
import 'package:vynic/core/services/database_service.dart';

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
  });

  final Color textPrimary;
  final Color mutedText;
  final GlobalKey<TableSelectionWidgetState> tableSelectionKey;
  final VoidCallback onSelectionChanged;
  final ValueChanged<TableModel> onTableTap;
  final VoidCallback onContinueToMenu;
  final int currentFloor;
  final ValueChanged<int> onSwitchFloor;

  @override
  Widget build(BuildContext context) {
    final layout = DatabaseService.getRestaurantTableLayout();
    final currentZone =
        layout.zoneForDisplayOrder(currentFloor) ?? layout.zones.first;
    final floorName = currentZone.legacyFloor;
    final tables = DatabaseService.getTablesByFloor(floorName);
    final reservedCount = tables.where((table) => table.isReserved).length;
    final availableCount = tables.length - reservedCount;
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
        value: '$availableCount',
      ),
      _FloorMetricData(
        icon: Icons.lock_clock_outlined,
        iconColor: const Color(0xFFB45309),
        label: 'დაკავებული',
        value: '$reservedCount',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideRailLayout = constraints.maxWidth >= 920;

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          child: useSideRailLayout
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 292, child: _buildControlRail(metrics)),
                    const SizedBox(width: 14),
                    Expanded(child: _buildPlanPanel(showHeader: false)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPageHeading(),
                    const SizedBox(height: 16),
                    _buildFloorControlCard(),
                    const SizedBox(height: 12),
                    _buildSelectionOverview(),
                    const SizedBox(height: 12),
                    Expanded(child: _buildPlanPanel(showHeader: true)),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildControlRail(List<_FloorMetricData> metrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPageHeading(compact: true),
        const SizedBox(height: 12),
        _buildFloorControlCard(),
        const SizedBox(height: 12),
        _buildSelectionOverview(),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: metrics.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final metric = metrics[index];
              return _FloorMetricCard(
                icon: metric.icon,
                iconColor: metric.iconColor,
                label: metric.label,
                value: metric.value,
                compact: true,
              );
            },
          ),
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
    final activeOrder = focusedBusyTable?.activeOrderId != null
        ? DatabaseService.getOrder(focusedBusyTable!.activeOrderId!)
        : null;
    final reservation = focusedBusyTable?.reservationId != null
        ? DatabaseService.findReservationById(focusedBusyTable!.reservationId!)
        : null;

    final Color statusColor = hasBusySelection
        ? const Color(0xFFB45309)
        : hasFreeSelection
        ? const Color(0xFF047857)
        : const Color(0xFF075E6B);
    final String title = hasBusySelection
        ? 'დაკავებული მაგიდა'
        : hasFreeSelection
        ? 'არჩეული მაგიდები'
        : 'აირჩიეთ მაგიდა';
    final String subtitle = hasBusySelection
        ? 'სწრაფი მიმოხილვა და შეკვეთაზე გადასვლა'
        : hasFreeSelection
        ? 'გააგრძელეთ მენიუში შეკვეთის შესაქმნელად'
        : 'შეკვეთის გასაგრძელებლად მონიშნეთ თავისუფალი მაგიდა';
    final String buttonLabel = hasBusySelection
        ? 'გაგრძელება'
        : hasFreeSelection
        ? 'მენიუში გადასვლა'
        : 'აირჩიეთ მაგიდა';
    final IconData buttonIcon = hasBusySelection
        ? Icons.open_in_new_rounded
        : hasFreeSelection
        ? Icons.restaurant_menu_rounded
        : Icons.touch_app_outlined;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
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
                child: Icon(
                  hasBusySelection
                      ? Icons.lock_clock_outlined
                      : hasFreeSelection
                      ? Icons.check_circle_outline_rounded
                      : Icons.event_available_outlined,
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
                      title,
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
                      subtitle,
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
          if (hasBusySelection) ...[
            _OverviewLine(
              icon: Icons.table_restaurant_outlined,
              label: focusedBusyTables.length > 1 ? 'მაგიდები' : 'მაგიდა',
              value:
                  '${focusedBusyTable.floor == 'second' ? 'II' : 'I'} • ${focusedBusyTables.map((table) => table.tableNumber).join(', ')}',
            ),
            if (activeOrder != null) ...[
              const SizedBox(height: 7),
              _OverviewLine(
                icon: Icons.receipt_long_outlined,
                label: 'შეკვეთა',
                value:
                    '#${activeOrder.orderId} • ${activeOrder.items.length} პროდუქტი',
              ),
              const SizedBox(height: 7),
              _OverviewLine(
                icon: Icons.payments_outlined,
                label: 'ჯამი',
                value: '${activeOrder.totalAmount.toStringAsFixed(2)} ₾',
              ),
            ] else if (reservation != null) ...[
              const SizedBox(height: 7),
              _OverviewLine(
                icon: Icons.person_outline,
                label: 'რეზერვაცია',
                value: reservation.customerName.trim().isEmpty
                    ? reservation.reservationTime
                    : reservation.customerName.trim(),
              ),
            ],
          ] else if (hasFreeSelection) ...[
            _OverviewLine(
              icon: Icons.table_bar_outlined,
              label: 'არჩეული',
              value: selectedTables
                  .map((table) => table.tableNumber)
                  .join(', '),
            ),
            const SizedBox(height: 7),
            _OverviewLine(
              icon: Icons.layers_outlined,
              label: 'სართული',
              value: currentFloor == 1 ? 'პირველი' : 'მეორე',
            ),
          ] else ...[
            _OverviewLine(
              icon: Icons.info_outline,
              label: 'სტატუსი',
              value: 'მაგიდა არ არის არჩეული',
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: hasBusySelection
                ? () => onTableTap(focusedBusyTable)
                : hasFreeSelection
                ? onContinueToMenu
                : null,
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
            icon: Icon(buttonIcon, size: 18),
            label: Text(
              buttonLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanPanel({required bool showHeader}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE4ED)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B0F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE4ED)),
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
            expanded: true,
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
    this.expanded = false,
  });

  final int currentFloor;
  final Color activeColor;
  final Color mutedText;
  final ValueChanged<int> onSwitchFloor;
  final List<({int floor, String label})> floors;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final floor in floors)
            expanded
                ? Expanded(child: _buildFloorButton(floor))
                : _buildFloorButton(floor),
        ],
      ),
    );
  }

  Widget _buildFloorButton(({int floor, String label}) floor) {
    return InkWell(
      onTap: floor.floor == currentFloor
          ? null
          : () => onSwitchFloor(floor.floor),
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: expanded ? null : 104,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE4ED)),
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
