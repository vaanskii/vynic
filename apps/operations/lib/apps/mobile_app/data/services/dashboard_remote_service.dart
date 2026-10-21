import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:intl/intl.dart';
import 'package:vynic/apps/mobile_app/data/models/dashboard_bundle.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

class DashboardRemoteService {
  const DashboardRemoteService();
  String _businessDateKey() {
    final raw = MonitoringSocketService.currentBusinessDate.value;
    return raw != null && raw.trim().length >= 10
        ? raw.substring(0, 10)
        : DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  Future<DashboardBundle> fetchDashboardBundle() async {
    final metrics = await MobileApiService.captureRead(
      'dashboard',
      MobileApiService.getDashboard,
    );
    final businessDate = metrics.data?.businessDate ?? _businessDateKey();
    final results = await Future.wait<ManagerDataRead<dynamic>>([
      Future.value(metrics),
      MobileApiService.captureRead(
        'product_analytics',
        () => MobileApiService.getProductAnalytics(
          from: businessDate,
          to: businessDate,
        ),
      ),
      MobileApiService.captureRead(
        'staff_performance',
        () => MobileApiService.getStaffPerformance(
          from: businessDate,
          to: businessDate,
        ),
      ),
      MobileApiService.captureRead(
        'sales_daily',
        MobileApiService.getSalesDaily,
      ),
      ManagerEntitlements.has(FeatureKeys.managerReservations)
          ? MobileApiService.captureRead(
              'reservations',
              () => MobileApiService.getReservations(date: businessDate),
            )
          : Future.value(
              const ManagerDataRead(
                null,
                ManagerReadStatus(
                  key: 'reservations',
                  completeness: 'DISABLED',
                ),
              ),
            ),
      MobileApiService.captureRead(
        'counted_menus',
        MobileApiService.getCountedMenus,
      ),
      MobileApiService.captureRead(
        'financials',
        MobileApiService.getFinancials,
      ),
    ]);
    return DashboardBundle(
      metrics: results[0].data,
      productAnalytics: results[1].data,
      staff: results[2].data,
      salesDaily: results[3].data,
      todayReservations: results[4].data,
      countedMenus: results[5].data,
      financials: results[6].data,
      reads: {for (final result in results) result.status.key: result.status},
    );
  }
}
