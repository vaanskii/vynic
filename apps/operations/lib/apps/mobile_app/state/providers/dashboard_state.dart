import 'package:vynic/core/models/monitoring.dart';

class DashboardState {
  final ManagerDashboardMetrics? metrics;
  final Map<String, dynamic>? salesReport;
  final List<StaffMetric> staff;
  final List<Map<String, dynamic>> salesDaily;
  final List<Map<String, dynamic>> todayReservations;
  final List<dynamic> countedMenus;
  final bool loading;
  final bool firstLoadDone;
  final bool apiError;

  const DashboardState({
    this.metrics,
    this.salesReport,
    this.staff = const [],
    this.salesDaily = const [],
    this.todayReservations = const [],
    this.countedMenus = const [],
    this.loading = true,
    this.firstLoadDone = false,
    this.apiError = false,
  });

  DashboardState copyWith({
    ManagerDashboardMetrics? metrics,
    Map<String, dynamic>? salesReport,
    List<StaffMetric>? staff,
    List<Map<String, dynamic>>? salesDaily,
    List<Map<String, dynamic>>? todayReservations,
    List<dynamic>? countedMenus,
    bool? loading,
    bool? firstLoadDone,
    bool? apiError,
  }) {
    return DashboardState(
      metrics: metrics ?? this.metrics,
      salesReport: salesReport ?? this.salesReport,
      staff: staff ?? this.staff,
      salesDaily: salesDaily ?? this.salesDaily,
      todayReservations: todayReservations ?? this.todayReservations,
      countedMenus: countedMenus ?? this.countedMenus,
      loading: loading ?? this.loading,
      firstLoadDone: firstLoadDone ?? this.firstLoadDone,
      apiError: apiError ?? this.apiError,
    );
  }
}
