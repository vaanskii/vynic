import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';

/// Central configuration for the backend API URL.
///
/// Priority order:
///   1. Admin-saved override from local Hive settings
///   2. `BACKEND_URL_<PLATFORM>` from .env (e.g. BACKEND_URL_ANDROID)
///   3. BACKEND_URL from .env (single URL for all platforms, production-friendly)
///   4. --dart-define variants (`BACKEND_URL_<PLATFORM>`, BACKEND_URL)
///   5. BACKEND_URL_FALLBACK from .env or localhost fallback
class ApiConfig {
  static bool _loggedResolvedUrl = false;

  static String get baseUrl {
    // Desktop POS stores its override in DatabaseService; the mobile manager app
    // (which never inits DatabaseService) stores it in ManagerAppPreferences.
    final adminOverride =
        DatabaseService.getBackendUrlOverride() ??
        ManagerAppPreferences.backendUrlOverride.value;
    if (adminOverride != null) {
      final normalized = _normalizeAndroidLoopback(adminOverride);
      _logResolvedUrlOnce(normalized, source: 'admin override');
      return normalized;
    }

    final override = _explicitBackendUrl;
    if (override != null) {
      final normalized = _normalizeAndroidLoopback(override);
      _logResolvedUrlOnce(normalized, source: '.env or dart-define');
      return normalized;
    }

    final resolved = _normalizeAndroidLoopback(_defaultBaseUrl);
    _logResolvedUrlOnce(resolved, source: 'platform default');
    return resolved;
  }

  /// Turns what someone typed into a backend origin, or `null` if it cannot be
  /// one.
  ///
  /// `10.10.10.3` becomes `http://10.10.10.3:3000`, which is the shape a LAN
  /// server is reached at and the reason the helper exists. An explicit
  /// `https://` host keeps its own default port — appending `:3000` to a public
  /// API origin would produce an address nothing is listening on.
  static String? normalizeEditableBackendUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    // A host cannot contain whitespace, and Uri.parse would silently
    // percent-encode it into something that looks like a valid address.
    if (RegExp(r'\s').hasMatch(value)) return null;
    if (!value.contains('://')) {
      value = 'http://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.trim().isEmpty) return null;
    if (uri.hasQuery || uri.hasFragment) return null;
    if (uri.path.isNotEmpty && uri.path != '/') return null;

    final port = uri.hasPort
        ? uri.port
        : scheme == 'https'
        ? 443
        : 3000;
    if (port <= 0 || port > 65535) return null;

    return uri
        .replace(
          scheme: scheme,
          path: '',
          query: null,
          fragment: null,
          port: port,
        )
        .toString();
  }

  static void resetResolvedUrlLog() {
    _loggedResolvedUrl = false;
  }

  /// `.env` is optional, so every read of it has to be.
  ///
  /// `main()` already treats a missing `.env` as survivable and carries on, but
  /// `dotenv.env` throws when it was never initialized — so a terminal shipped
  /// without one would have failed on the first resolution of its backend URL.
  /// That is exactly the install self-enrollment exists for.
  static String? _env(String key) {
    if (!dotenv.isInitialized) return null;
    final value = dotenv.env[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String get _defaultBaseUrl {
    final fallback = _env('BACKEND_URL_FALLBACK');
    if (fallback != null) return fallback;
    return 'http://localhost:3000';
  }

  static String? get _explicitBackendUrl {
    final envPlatformUrl = _env(_platformBackendKey);
    if (envPlatformUrl != null) return envPlatformUrl;
    final envUrl = _env('BACKEND_URL');
    if (envUrl != null) return envUrl;
    const defineAndroid = String.fromEnvironment('BACKEND_URL_ANDROID');
    const defineIos = String.fromEnvironment('BACKEND_URL_IOS');
    const defineMacos = String.fromEnvironment('BACKEND_URL_MACOS');
    const defineWindows = String.fromEnvironment('BACKEND_URL_WINDOWS');
    const defineWeb = String.fromEnvironment('BACKEND_URL_WEB');
    final definePlatform = _selectByPlatform(
      android: defineAndroid,
      ios: defineIos,
      macos: defineMacos,
      windows: defineWindows,
      web: defineWeb,
    );
    if (definePlatform.isNotEmpty) return definePlatform;
    const dartDefine = String.fromEnvironment('BACKEND_URL');
    if (dartDefine.isNotEmpty) {
      return dartDefine;
    }
    return null;
  }

  static String get _platformBackendKey => _selectByPlatform(
    android: 'BACKEND_URL_ANDROID',
    ios: 'BACKEND_URL_IOS',
    macos: 'BACKEND_URL_MACOS',
    windows: 'BACKEND_URL_WINDOWS',
    web: 'BACKEND_URL_WEB',
  );

  static T _selectByPlatform<T>({
    required T android,
    required T ios,
    required T macos,
    required T windows,
    required T web,
  }) {
    if (kIsWeb) return web;
    if (Platform.isAndroid) return android;
    if (Platform.isIOS) return ios;
    if (Platform.isMacOS) return macos;
    if (Platform.isWindows) return windows;
    return web;
  }

  static String _normalizeAndroidLoopback(String url) {
    if (kIsWeb || !Platform.isAndroid) return url;
    final normalized = url.trim();
    if (normalized.startsWith('http://127.0.0.1:')) {
      return normalized.replaceFirst('http://127.0.0.1:', 'http://10.0.2.2:');
    }
    if (normalized.startsWith('http://localhost:')) {
      return normalized.replaceFirst('http://localhost:', 'http://10.0.2.2:');
    }
    return normalized;
  }

  /// Physical iPhone/iPad (not Simulator).
  static bool get isIosPhysicalDevice {
    if (kIsWeb || !Platform.isIOS) return false;
    return !_isIosSimulator;
  }

  static bool get _isIosSimulator {
    if (kIsWeb || !Platform.isIOS) return false;
    final triple = Platform.environment['LLVM_TARGET_TRIPLE'] ?? '';
    if (triple.contains('simulator')) return true;
    return Platform.environment.containsKey('SIMULATOR_DEVICE_NAME') ||
        (Platform.environment['SIMULATOR_ROOT']?.isNotEmpty ?? false);
  }

  static void _logResolvedUrlOnce(String url, {required String source}) {
    if (!kDebugMode || _loggedResolvedUrl) return;
    _loggedResolvedUrl = true;
    debugPrint('[ApiConfig] API base URL: $url ($source)');
    // Only warn when using loopback default on a physical device (not when .env sets it).
    final loopback = url.contains('127.0.0.1') || url.contains('localhost');
    if (isIosPhysicalDevice && loopback && _explicitBackendUrl == null) {
      debugPrint(
        '[ApiConfig] Physical iPhone cannot use 127.0.0.1 for the Mac server. '
        'Set BACKEND_URL=http://YOUR_MAC_LAN_IP:3000 in .env, then fully restart the app.',
      );
    }
  }

  /// Shared secret for POS → cloud push (`POST /sync/*`). Must match server POS_SYNC_API_KEY.
  static String? get posSyncApiKey {
    final envKey = _env('POS_SYNC_API_KEY');
    if (envKey != null) return envKey;
    const dartDefine = String.fromEnvironment('POS_SYNC_API_KEY');
    if (dartDefine.isNotEmpty) return dartDefine;
    return null;
  }

  /// Headers for authenticated POS push endpoints.
  ///
  /// A provisioned Device credential wins over the shared key. Both travel in
  /// the same header and the server tells them apart by prefix, so a
  /// provisioned installation gets a snapshot push attributed to its own Device
  /// and Venue while an unprovisioned one keeps working exactly as before.
  static Map<String, String> get posSyncHeaders {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final key = EdgeDeviceCredentialStore.credential ?? posSyncApiKey;
    if (key != null && key.isNotEmpty) {
      headers['X-POS-Sync-Key'] = key;
    }
    return headers;
  }
}
