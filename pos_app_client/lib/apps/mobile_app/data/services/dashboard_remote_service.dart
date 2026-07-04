import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/data/models/dashboard_bundle.dart';
import 'package:vynic/core/models/monitoring.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

class DashboardRemoteService {
  const DashboardRemoteService();

  String _businessDateKey() {
    final raw = MonitoringSocketService.currentBusinessDate.value;
    if (raw != null && raw.trim().length >= 10) {
      return raw.substring(0, 10);
    }
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  Future<DashboardBundle> fetchDashboardBundle() async {
    final businessDate = _businessDateKey();
    final results = await Future.wait([
      MobileApiService.getDashboard(),
      MobileApiService.getSalesReport(period: 'today'),
      MobileApiService.getStaffPerformance(),
      // Daily history for the dashboard sparkline / weekday comparison.
      MobileApiService.getSalesDaily().catchError(
        (_) => <Map<String, dynamic>>[],
      ),
      // Reservations for the active business day (manager pulse card).
      MobileApiService.getReservations(
        date: businessDate,
      ).catchError((_) => <Map<String, dynamic>>[]),
      MobileApiService.getCountedMenus().catchError((_) => <dynamic>[]),
    ]);

    return DashboardBundle(
      metrics: results[0] as ManagerDashboardMetrics,
      salesReport: results[1] as Map<String, dynamic>,
      staff: results[2] as List<StaffMetric>,
      salesDaily: results[3] as List<Map<String, dynamic>>,
      todayReservations: results[4] as List<Map<String, dynamic>>,
      countedMenus: results[5] as List<dynamic>,
    );
  }
}
