import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central configuration for the backend API URL.
///
/// Priority order:
///   1. BACKEND_URL from .env (explicit production override)
///   2. Compile-time --dart-define=BACKEND_URL=... (CI/CD)
///   3. Platform-based sensible defaults for development
class ApiConfig {
  static String get baseUrl {
    // 1. Explicit env override (production / staging)
    final envUrl = dotenv.env['BACKEND_URL']?.trim();
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;

    // 2. Compile-time define
    const dartDefine = String.fromEnvironment('BACKEND_URL');
    if (dartDefine.isNotEmpty) return dartDefine;

    // 3. Development defaults
    if (kIsWeb) return 'http://localhost:3000';
    if (!kIsWeb && Platform.isAndroid) {
      // Emulator → host PC. Physical device: set BACKEND_URL=http://<PC-LAN-IP>:3000 in .env
      return 'http://10.0.2.2:3000';
    }
    if (!kIsWeb && Platform.isWindows) {
      return 'http://127.0.0.1:3000';
    }
    return 'http://localhost:3000';
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
