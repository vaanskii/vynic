import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vynic/apps/mobile_app/data/repositories/dashboard_repository.dart';
import 'package:vynic/apps/mobile_app/state/providers/dashboard_state.dart';
import 'package:vynic/core/services/manager_app/mobile_api_service.dart';
import 'package:vynic/core/services/manager_app/manager_data_read.dart';

class DashboardController extends ChangeNotifier {
  final DashboardRepository _repository;
  DashboardState _state = const DashboardState();
  Timer? _refreshTimer;
  Timer? _socketDebounce;
  bool _disposed = false, _loading = false;

  DashboardController(this._repository);

  DashboardState get state => _state;

  Future<void> initialize() async {
    await loadAll();
    if (_disposed) return;
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
    await loadAll();
  }

  Future<void> loadAll() async {
    if (_disposed || _loading) return;
    _loading = true;
    String? scope;
    try {
      scope = MobileApiService.tableRepairScope;
      final bundle = await _repository.getDashboardBundle();
      if (_disposed || !MobileApiService.isCurrentTableRepairScope(scope))
        return;
      final reads = <String, ManagerReadStatus>{};
      for (final entry in bundle.reads.entries) {
        final previous = _state.reads[entry.key];
        reads[entry.key] =
            entry.value.location == 'unavailable' &&
                !entry.value.accessDenied &&
                previous?.fetchedAt != null &&
                previous!.query == entry.value.query
            ? previous.failed(
                entry.value.error ?? 'მონაცემები ვერ განახლდა.',
                location: 'memory',
              )
            : entry.value;
      }
      // An access denial must clear retained memory just as it excludes cache.
      // Transient failures may retain the same-query value with its old status.
      MobileApiService.releaseReadStatuses(_state.reads.values);
      _state = DashboardState(
        metrics: reads['dashboard']?.accessDenied == true
            ? null
            : bundle.metrics ?? _state.metrics,
        productAnalytics: reads['product_analytics']?.accessDenied == true
            ? null
            : bundle.productAnalytics ?? _state.productAnalytics,
        financials: reads['financials']?.accessDenied == true
            ? null
            : bundle.financials ?? _state.financials,
        staff: reads['staff_performance']?.accessDenied == true
            ? const []
            : bundle.staff ?? _state.staff,
        salesDaily: reads['sales_daily']?.accessDenied == true
            ? const []
            : bundle.salesDaily ?? _state.salesDaily,
        todayReservations: reads['reservations']?.location == 'unavailable'
            ? const []
            : bundle.todayReservations ?? _state.todayReservations,
        countedMenus: reads['counted_menus']?.accessDenied == true
            ? const []
            : bundle.countedMenus ?? _state.countedMenus,
        loading: false,
        firstLoadDone: true,
        apiError: reads.values.any(
          (r) => !r.apiAvailable && r.completeness != 'DISABLED',
        ),
        reads: reads,
      );
      notifyListeners();
    } catch (_) {
      if (scope == null) {
        if (!_disposed) {
          _state = const DashboardState(
            loading: false,
            apiError: true,
            reads: {
              'dashboard': ManagerReadStatus(
                key: 'dashboard',
                error: 'სესია მიუწვდომელია. შედით ხელახლა.',
              ),
            },
          );
          notifyListeners();
        }
        return;
      }
      if (_disposed || !MobileApiService.isCurrentTableRepairScope(scope))
        return;
      _state = _state.copyWith(
        loading: false,
        apiError: true,
        reads: {
          ..._state.reads,
          'dashboard':
              (_state.reads['dashboard'] ??
                      const ManagerReadStatus(key: 'dashboard'))
                  .failed('დაფა ვერ განახლდა.'),
        },
      );
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _socketDebounce?.cancel();
    super.dispose();
  }
}
