import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/core/models/monitoring.dart';

class DashboardBundle {
  final ManagerDashboardMetrics? metrics;
  final Map<String, dynamic>? productAnalytics;
  final Map<String, dynamic>? financials;
  final List<StaffMetric>? staff;
  final List<Map<String, dynamic>>? salesDaily;
  final List<Map<String, dynamic>>? todayReservations;
  final List<dynamic>? countedMenus;

  final Map<String, ManagerReadStatus> reads;

  const DashboardBundle({
    this.reads = const {},
    required this.metrics,
    required this.productAnalytics,
    this.financials,
    required this.staff,
    this.salesDaily,
    this.todayReservations,
    this.countedMenus,
  });
}
