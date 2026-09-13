import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/database_service.dart';

/// Environment-level endpoint; a URL never grants Venue authority.
class ApiConfig {
  static const environment = String.fromEnvironment(
    'VYNIC_ENV',
    defaultValue: 'development',
  );
  static const configuredUrl = String.fromEnvironment('VYNIC_API_URL');
  static bool get allowDeveloperOverride =>
      kDebugMode && environment == 'development';
  static void validateBuild() {
    if (!['development', 'staging', 'production'].contains(environment))
      throw StateError('Unknown VYNIC_ENV');
    if (!allowDeveloperOverride) {
      final uri = Uri.tryParse(configuredUrl);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/'))
        throw StateError(
          'Release builds require an HTTPS VYNIC_API_URL origin',
        );
    }
  }

  static String get baseUrl {
    if (configuredUrl.isNotEmpty)
      return configuredUrl.replaceFirst(RegExp(r'/$'), '');
    if (allowDeveloperOverride) {
      final override =
          DatabaseService.getBackendUrlOverride() ??
          ManagerAppPreferences.backendUrlOverride.value;
      if (override != null) return override;
    }
    validateBuild();
    return !kIsWeb && Platform.isAndroid
        ? 'http://10.0.2.2:3000'
        : 'http://127.0.0.1:3000';
  }

  static void resetResolvedUrlLog() {}
  static bool get isIosPhysicalDevice =>
      !kIsWeb &&
      Platform.isIOS &&
      !Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');

  /// Legacy shared credentials are never shipped or read by new builds.
  static String? get posSyncApiKey => null;
  static Map<String, String> get posSyncHeaders => {
    'Content-Type': 'application/json',
    if (EdgeDeviceCredentialStore.credential case final String credential)
      'X-POS-Sync-Key': credential,
  };
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
    if (uri.host.trim().isEmpty || uri.userInfo.isNotEmpty) return null;
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
}
