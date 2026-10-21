import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/manager_theme.dart';
import 'manager_design_components.dart';

/// Data adapter for the approved experiment's RevenueBars. Null is unavailable,
/// never a zero sale. The preview's geometry is retained; production data is
/// supplied by the dashboard's existing sales_daily read.
class ManagerRevenuePoint {
  const ManagerRevenuePoint({
    required this.label,
    required this.value,
    this.isToday = false,
  });
  final String label;
  final double? value;
  final bool isToday;
}

class ManagerRevenueBars extends StatelessWidget {
  const ManagerRevenueBars({
    super.key,
    required this.points,
    this.compact = false,
  });
  final List<ManagerRevenuePoint> points;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final t = managerThemeOf(context);
    if (points.isEmpty || points.every((p) => p.value == null)) {
      return SizedBox(
        height: compact ? 112 : 180,
        child: Center(
          child: Text(
            'გაყიდვების ისტორია მიუწვდომელია',
            style: managerDesignText(context, 12, muted: true),
          ),
        ),
      );
    }
    final maximum = points.fold<double>(0, (v, p) => math.max(v, p.value ?? 0));
    final magnitude = maximum <= 0
        ? 1.0
        : math.pow(10, (math.log(maximum) / math.ln10).floor()).toDouble();
    final ceiling = maximum <= 0
        ? 1.0
        : [
                1.0,
                2.0,
                5.0,
                10.0,
              ].firstWhere((step) => step >= maximum / magnitude) *
              magnitude;
    // Original preview: 112/180 high, 8/20 bar gutters, 6px upper corners,
    // three horizontal guides, 10px label gap and 9px date labels.
    return SizedBox(
      height: compact ? 112 : 180,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                for (final f in [.0, .5, 1.0])
                  Positioned(
                    left: 0,
                    right: 0,
                    top: f * (compact ? 78 : 146),
                    child: Container(height: 1, color: t.cardBorder),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final point in points)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 8 : 20,
                          ),
                          child: FractionallySizedBox(
                            heightFactor: point.value == null
                                ? 1
                                : (point.value! / ceiling).clamp(0, 1),
                            alignment: Alignment.bottomCenter,
                            child: Tooltip(
                              message: point.value == null
                                  ? '${point.label}: მონაცემი მიუწვდომელია'
                                  : '${point.label}: ${point.value!.toStringAsFixed(2)} ₾',
                              child: point.value == null
                                  ? Center(
                                      child: Text(
                                        '—',
                                        style: managerDesignText(
                                          context,
                                          12,
                                          muted: true,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        color: point.isToday
                                            ? t.primary
                                            : t.isDark
                                            ? t.primarySoft
                                            : const Color(0xFFE8E0F4),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(6),
                                            ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final point in points)
                Expanded(
                  child: Text(
                    point.isToday ? 'დღეს' : point.label,
                    textAlign: TextAlign.center,
                    style: managerDesignText(context, 9, muted: !point.isToday)
                        .copyWith(
                          color: point.isToday ? t.primary : t.textSecondary,
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

/// Direct port of the segmented occupancy visualization in DashboardView.
class ManagerOccupancyBars extends StatelessWidget {
  const ManagerOccupancyBars({
    super.key,
    required this.total,
    required this.occupied,
  });
  final int total, occupied;
  @override
  Widget build(BuildContext context) {
    final t = managerThemeOf(context);
    if (total <= 0)
      return Text(
        'მაგიდების რაოდენობა მიუწვდომელია',
        style: managerDesignText(context, 12, muted: true),
      );
    return Semantics(
      label: '$total მაგიდიდან $occupied დაკავებულია',
      child: Row(
        children: List.generate(
          total,
          (i) => Expanded(
            child: Container(
              height: 24,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: i < occupied
                    ? t.primary
                    : t.isDark
                    ? t.surfaceMuted
                    : const Color(0xFFEDE9F2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
