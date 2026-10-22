import 'package:vynic/core/services/manager_app/manager_data_read.dart';
import 'package:vynic/core/models/monitoring.dart';

class DashboardState {
  final ManagerDashboardMetrics? metrics;
  final Map<String, dynamic>? productAnalytics;
  final Map<String, dynamic>? financials;
  final List<StaffMetric> staff;
  final List<Map<String, dynamic>> salesDaily;
  final List<Map<String, dynamic>> todayReservations;
  final List<dynamic> countedMenus;
  final bool loading;
  final bool firstLoadDone;
  final bool apiError;
  final Map<String, ManagerReadStatus> reads;

  const DashboardState({
    this.metrics,
    this.productAnalytics,
    this.financials,
    this.staff = const [],
    this.salesDaily = const [],
    this.todayReservations = const [],
    this.countedMenus = const [],
    this.loading = true,
    this.firstLoadDone = false,
    this.apiError = false,
    this.reads = const {},
  });

  DashboardState copyWith({
    ManagerDashboardMetrics? metrics,
    Map<String, dynamic>? productAnalytics,
    Map<String, dynamic>? financials,
    List<StaffMetric>? staff,
    List<Map<String, dynamic>>? salesDaily,
    List<Map<String, dynamic>>? todayReservations,
    List<dynamic>? countedMenus,
    bool? loading,
    bool? firstLoadDone,
    bool? apiError,
    Map<String, ManagerReadStatus>? reads,
  }) {
    return DashboardState(
      metrics: metrics ?? this.metrics,
      productAnalytics: productAnalytics ?? this.productAnalytics,
      financials: financials ?? this.financials,
      staff: staff ?? this.staff,
      salesDaily: salesDaily ?? this.salesDaily,
      todayReservations: todayReservations ?? this.todayReservations,
      countedMenus: countedMenus ?? this.countedMenus,
      loading: loading ?? this.loading,
      firstLoadDone: firstLoadDone ?? this.firstLoadDone,
      apiError: apiError ?? this.apiError,
      reads: reads ?? this.reads,
    );
  }
}
