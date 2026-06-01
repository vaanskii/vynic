import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central configuration for the backend API URL.
///
/// Priority order:
///   1. BACKEND_URL from .env (set this for iOS — see comments in `.env`)
///   2. Compile-time --dart-define=BACKEND_URL=... (CI/CD)
///   3. Platform-based defaults for local development
class ApiConfig {
  static bool _loggedResolvedUrl = false;

  static String get baseUrl {
    final override = _explicitBackendUrl;
    if (override != null) {
      _logResolvedUrlOnce(override, source: '.env or dart-define');
      return override;
    }

    final resolved = _defaultBaseUrl;
    _logResolvedUrlOnce(resolved, source: 'platform default');
    return resolved;
  }

  static String get _defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:3000';

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return 'http://127.0.0.1:3000';
    }

    if (Platform.isWindows) {
      return 'http://127.0.0.1:3000';
    }

    return 'http://localhost:3000';
  }

  static String? get _explicitBackendUrl {
    final envUrl = dotenv.env['BACKEND_URL']?.trim();
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;
    const dartDefine = String.fromEnvironment('BACKEND_URL');
    if (dartDefine.isNotEmpty) return dartDefine;
    return null;
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
    final envKey = dotenv.env['POS_SYNC_API_KEY']?.trim();
    if (envKey != null && envKey.isNotEmpty) return envKey;
    const dartDefine = String.fromEnvironment('POS_SYNC_API_KEY');
    if (dartDefine.isNotEmpty) return dartDefine;
    return null;
  }

  /// Headers for authenticated POS push endpoints.
  static Map<String, String> get posSyncHeaders {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final key = posSyncApiKey;
    if (key != null && key.isNotEmpty) {
      headers['X-POS-Sync-Key'] = key;
    }
    return headers;
  }
}
