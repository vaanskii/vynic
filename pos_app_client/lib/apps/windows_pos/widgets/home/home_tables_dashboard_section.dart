import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/table_selection_widget.dart';
import 'package:vynic/core/models/table.dart';

class HomeTablesDashboardSection extends StatelessWidget {
  const HomeTablesDashboardSection({
    super.key,
    required this.primaryColor,
    required this.tableSelectionKey,
    required this.onSelectionChanged,
    required this.onTableTap,
    required this.currentFloor,
    required this.onSwitchFloor,
  });

  final Color primaryColor;
  final GlobalKey<TableSelectionWidgetState> tableSelectionKey;
  final VoidCallback onSelectionChanged;
  final ValueChanged<TableModel> onTableTap;
  final int currentFloor;
  final ValueChanged<int> onSwitchFloor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.layers_outlined,
                color: Color(0xFF23445A),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'სართული',
                style: TextStyle(
                  color: Color(0xFF23445A),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final floor in [1, 2])
                      InkWell(
                        onTap: floor == currentFloor
                            ? null
                            : () => onSwitchFloor(floor),
                        borderRadius: BorderRadius.circular(9),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: floor == currentFloor
                                ? const Color(0xFF06384F)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: floor == currentFloor
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF06384F,
                                      ).withValues(alpha: 0.2),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            '$floor სართული',
                            style: TextStyle(
                              color: floor == currentFloor
                                  ? Colors.white
                                  : const Color(0xFF52677A),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 233, 233, 233),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.05),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: TableSelectionWidget(
                key: tableSelectionKey,
                onSelectionChanged: onSelectionChanged,
                onTableTap: onTableTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
