import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central configuration for the backend API URL.
///
/// Priority order:
///   1. BACKEND_URL_<PLATFORM> from .env (e.g. BACKEND_URL_ANDROID)
///   2. BACKEND_URL from .env (single URL for all platforms, production-friendly)
///   3. --dart-define variants (BACKEND_URL_<PLATFORM>, BACKEND_URL)
///   4. BACKEND_URL_FALLBACK from .env or localhost fallback
class ApiConfig {
  static bool _loggedResolvedUrl = false;

  static String get baseUrl {
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

  static String get _defaultBaseUrl {
    final fallback = dotenv.env['BACKEND_URL_FALLBACK']?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return 'http://localhost:3000';
  }

  static String? get _explicitBackendUrl {
    final envPlatformUrl = dotenv.env[_platformBackendKey]?.trim();
    if (envPlatformUrl != null && envPlatformUrl.isNotEmpty) {
      return envPlatformUrl;
    }
    final envUrl = dotenv.env['BACKEND_URL']?.trim();
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }
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
