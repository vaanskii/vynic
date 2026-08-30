import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vynic/apps/mobile_app/data/repositories/dashboard_repository.dart';
import 'package:vynic/apps/mobile_app/state/providers/dashboard_state.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/sync/monitoring_socket_service.dart';

class DashboardController extends ChangeNotifier {
  final DashboardRepository _repository;
  DashboardState _state = const DashboardState();
  Timer? _refreshTimer;
  Timer? _socketDebounce;

  DashboardController(this._repository);

  DashboardState get state => _state;

  Future<void> initialize() async {
    await loadAll();
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => loadAll(),
    );
  }

  /// Lightweight refresh for realtime socket events (revenue + tables).
  void scheduleMetricsRefresh() {
    _socketDebounce?.cancel();
    _socketDebounce = Timer(const Duration(milliseconds: 350), refreshMetrics);
  }

  Future<void> refreshMetrics() async {
    try {
      final metrics = await MobileApiService.getDashboard();
      MonitoringSocketService.apiError.value = false;
      _state = _state.copyWith(metrics: metrics, apiError: false);
      notifyListeners();
    } catch (_) {
      // Keep showing last known metrics on transient failures.
    }
  }

  Future<void> loadAll() async {
    try {
      final bundle = await _repository.getDashboardBundle();
      MonitoringSocketService.apiError.value = false;
      _state = _state.copyWith(
        metrics: bundle.metrics,
        salesReport: bundle.salesReport,
        staff: bundle.staff,
        salesDaily: bundle.salesDaily,
        todayReservations: bundle.todayReservations,
        countedMenus: bundle.countedMenus,
        loading: false,
        firstLoadDone: true,
        apiError: false,
      );
      notifyListeners();
    } catch (_) {
      MonitoringSocketService.apiError.value = true;
      _state = _state.copyWith(loading: false, apiError: true);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _socketDebounce?.cancel();
    super.dispose();
  }
}
