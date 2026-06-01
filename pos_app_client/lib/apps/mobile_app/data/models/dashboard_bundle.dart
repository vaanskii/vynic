import 'package:vynic/core/models/monitoring.dart';

class DashboardBundle {
  final ManagerDashboardMetrics metrics;
  final Map<String, dynamic> salesReport;
  final List<StaffMetric> staff;
  final List<Map<String, dynamic>> salesDaily;
  final List<Map<String, dynamic>> todayReservations;
  final List<dynamic> countedMenus;

  const DashboardBundle({
    required this.metrics,
    required this.salesReport,
    required this.staff,
    this.salesDaily = const [],
    this.todayReservations = const [],
    this.countedMenus = const [],
  });
}
