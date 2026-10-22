import '../../models/manager_venue_selection.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vynic/core/services/manager_app/manager_dashboard_appearance.dart';

/// Local preferences for the mobile manager app (Hive-backed).
class ManagerAppPreferences {
  ManagerAppPreferences._();

  static const _boxName = 'manager_preferences';
  static const _dashboardAppearanceKey = 'dashboard_appearance';
  static const _backendUrlKey = 'backend_url_override';

  static Box? _box;
  static final Map<String, Future<String>> _linkIds = {};
  static ManagerVenueSelection? selectedVenue(String origin) {
    final value = _box?.get('selected_venue');
    if (value is! Map || value['origin'] != origin) return null;
    try {
      return ManagerVenueSelection.fromMap(value, origin: origin);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static Future<void> rememberVenue(ManagerVenueSelection venue) async {
    if (_box == null)
      throw StateError('Manager preferences are not initialized');
    await _box!.put('selected_venue', venue.toMap());
  }

  /// Persist before redemption so a lost reply or preferences retry keeps the same identity.
  /// This public UUID is a retry key, never a credential or Staff authority.
  static Future<String> linkInstallationId(String origin) {
    if (_box == null)
      return Future.error(
        StateError('Manager preferences are not initialized'),
      );
    return _linkIds.putIfAbsent(origin, () => _loadLinkInstallationId(origin));
  }

  static Future<String> _loadLinkInstallationId(String origin) async {
    if (_box == null)
      throw StateError('Manager preferences are not initialized');
    final key = 'link_installation_id:$origin';
    final stored = _box!.get(key);
    if (stored is String && Uuid.isValidUUID(fromString: stored)) return stored;
    final id = const Uuid().v4();
    try {
      await _box!.put(key, id);
      await _box!.flush();
    } catch (_) {
      _linkIds.remove(origin);
      rethrow;
    }
    return id;
  }

  static Future<void> clearVenue() async {
    await _box?.deleteAll(['selected_venue', 'login_venue_code']);
  }

  static String? get loginVenueCode => _box?.get('login_venue_code') as String?;
  static Future<void> setLoginVenueCode(String code) async {
    await _box?.put('login_venue_code', code);
  }

  static final ValueNotifier<ManagerDashboardAppearance> dashboardAppearance =
      ValueNotifier(ManagerDashboardAppearance.light);

  /// User-set backend URL for the mobile manager app (e.g. the Windows POS LAN
  /// address http://10.10.10.4:3000). Null = use the compiled environment default.
  static final ValueNotifier<String?> backendUrlOverride =
      ValueNotifier<String?>(null);

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _linkIds.clear();
    final stored = _box!.get(_dashboardAppearanceKey) as String?;
    dashboardAppearance.value = _parseAppearance(stored);
    final url = (_box!.get(_backendUrlKey) as String?)?.trim();
    backendUrlOverride.value = (url == null || url.isEmpty) ? null : url;
  }

  /// Set (or clear, with null/empty) the backend URL override.
  static Future<void> setBackendUrlOverride(String? url) async {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      backendUrlOverride.value = null;
      await _box?.delete(_backendUrlKey);
    } else {
      backendUrlOverride.value = value;
      await _box?.put(_backendUrlKey, value);
    }
  }

  static ManagerDashboardAppearance _parseAppearance(String? raw) {
    if (raw == ManagerDashboardAppearance.dark.name) {
      return ManagerDashboardAppearance.dark;
    }
    return ManagerDashboardAppearance.light;
  }

  static Future<void> setDashboardAppearance(
    ManagerDashboardAppearance appearance,
  ) async {
    dashboardAppearance.value = appearance;
    await _box?.put(_dashboardAppearanceKey, appearance.name);
  }
}
