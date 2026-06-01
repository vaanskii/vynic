import 'package:vynic/apps/mobile_app/data/models/dashboard_bundle.dart';
import 'package:vynic/apps/mobile_app/data/services/dashboard_remote_service.dart';

class DashboardRepository {
  final DashboardRemoteService _remoteService;

  const DashboardRepository(this._remoteService);

  Future<DashboardBundle> getDashboardBundle() {
    return _remoteService.fetchDashboardBundle();
  }
}
