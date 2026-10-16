import '../../models/manager_venue_selection.dart';
import 'package:vynic/core/services/manager_app/manager_entitlements.dart';
import 'package:vynic/core/services/notifications/manager_notification_inbox.dart';
import 'package:vynic/core/contracts/manager_login.dart';
import 'package:vynic/core/services/manager_app/manager_app_preferences.dart';
import 'package:vynic/core/services/manager_app/mobile_cache_service.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/services/auth/auth_token_service.dart';
import 'package:vynic/core/services/notifications/firebase_messaging_service.dart';
import 'package:vynic/core/models/staff_role.dart';

/// Result of a successful mobile login against the backend.
class MobileLoginResult {
  final String accessToken;
  final String role;
  final String username;
  final int expiresIn;

  const MobileLoginResult({
    required this.accessToken,
    required this.role,
    required this.username,
    required this.expiresIn,
  });
}

enum MobileAuthError {
  invalidPin,
  networkError,
  serverError,
  accessDenied,
  rateLimited,
  sessionStorageError,
}

/// Authenticates the manager against the backend (/auth/mobile-login).
/// Falls back to cached token for offline access.
class MobileAuthService {
  /// Redeems one Admin-issued code to select a Venue. Does not authenticate Staff.
  static Future<ManagerVenueSelection> linkVenue(
    String value, {
    http.Client? client,
  }) async {
    final origin = ApiConfig.baseUrl;
    final String installationId;
    try {
      installationId = await ManagerAppPreferences.linkInstallationId(origin);
    } catch (_) {
      throw MobileAuthError.sessionStorageError;
    }
    late http.Response response;
    try {
      response = await (client?.post ?? http.post)(
        Uri.parse('$origin/auth/manager-link'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': value.trim(),
          'installationId': installationId,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw MobileAuthError.networkError;
    }
    if (response.statusCode == 429) throw MobileAuthError.rateLimited;
    if (response.statusCode >= 500) throw MobileAuthError.serverError;
    if (response.statusCode != 200) throw MobileAuthError.accessDenied;
    try {
      return ManagerVenueSelection.fromMap(
        jsonDecode(response.body) as Map,
        origin: origin,
      );
    } catch (_) {
      throw MobileAuthError.serverError;
    }
  }

  /// Compatibility for old callers; new first-time UI uses Admin's one-use linking code.
  static Future<ManagerVenueSelection> resolveVenue(
    String value, {
    http.Client? client,
  }) async {
    final code = value.trim().toLowerCase();
    final origin = ApiConfig.baseUrl;
    try {
      final response = await (client?.post ?? http.post)(
        Uri.parse('$origin/auth/manager-venue'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'venueCode': code}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 429) throw MobileAuthError.rateLimited;
      if (response.statusCode >= 500) throw MobileAuthError.serverError;
      if (response.statusCode != 200) throw MobileAuthError.accessDenied;
      final venue = ManagerVenueSelection.fromMap(
        jsonDecode(response.body) as Map,
        origin: origin,
      );
      if (venue.code != code) throw MobileAuthError.accessDenied;
      return venue;
    } on MobileAuthError {
      rethrow;
    } catch (_) {
      throw MobileAuthError.networkError;
    }
  }

  /// Attempt to authenticate with the backend.
  /// Returns a [MobileLoginResult] on success.
  /// Throws a [MobileAuthError] on failure.
  static Future<MobileLoginResult> login(
    String pin, {
    required String venueCode,
    http.Client? client,
  }) async {
    final code = venueCode.trim().toLowerCase();
    late http.Response response;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}${ManagerLoginContract.path}');
      response = await (client?.post ?? http.post)(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          ManagerLoginContract.pinField: pin,
          ManagerLoginContract.venueCodeField: code,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw MobileAuthError.networkError;
    }
    try {
      if (response.statusCode == 200) {
        final Map<String, dynamic> body;
        try {
          body = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {
          throw MobileAuthError.serverError;
        }
        if (body[ManagerLoginContract.venueCodeField] != code) {
          throw MobileAuthError.accessDenied;
        }
        final result = MobileLoginResult(
          accessToken: body['access_token'] as String,
          role: body['role'] as String,
          username: body['username'] as String,
          expiresIn: body['expiresIn'] as int? ?? 86400,
        );

        // Verify role is allowed
        if (!StaffRole.isMobileApiRole(result.role)) {
          throw MobileAuthError.accessDenied;
        }

        // Retire the old device registration before associating this handset with a new session.
        await FirebaseMessagingService.instance()
            .unregisterCurrentTokenFromBackend();
        // A new login never inherits cached restaurant data from an older session.
        await MobileCacheService.clear();
        ManagerNotificationInbox.resetSession();
        await ManagerAppPreferences.setLoginVenueCode(code);
        // Persist token
        await AuthTokenService.saveToken(
          venueCode: code,
          token: result.accessToken,
          role: result.role,
          username: result.username,
          expiresInSeconds: result.expiresIn,
        );
        await FirebaseMessagingService.instance().syncCurrentTokenWithBackend();

        return result;
      } else if (response.statusCode == 401) {
        throw MobileAuthError.invalidPin;
      } else if (response.statusCode == 403) {
        throw MobileAuthError.accessDenied;
      } else if (response.statusCode == 429) {
        throw MobileAuthError.rateLimited;
      } else {
        throw MobileAuthError.serverError;
      }
    } on MobileAuthError {
      rethrow;
    } catch (e) {
      debugPrint('[MobileAuth] Could not establish local session');
      throw MobileAuthError.sessionStorageError;
    }
  }

  /// Try to use a cached token for offline access.
  /// Returns the username from the token if valid (or stale within grace period).
  static OfflineAuthResult? tryOfflineAccess({String? venueCode}) {
    if (venueCode != null &&
        AuthTokenService.venueCode != venueCode.trim().toLowerCase())
      return null;
    final role = AuthTokenService.role ?? '';
    if (!StaffRole.isMobileApiRole(role)) {
      return null;
    }

    if (AuthTokenService.hasValidToken) {
      return OfflineAuthResult(
        username: AuthTokenService.username ?? 'Manager',
        role: role,
        isStale: false,
      );
    }
    if (AuthTokenService.hasStaleToken) {
      return OfflineAuthResult(
        username: AuthTokenService.username ?? 'Manager',
        role: role,
        isStale: true,
      );
    }
    return null;
  }

  static Future<void> logout() async {
    ManagerEntitlements.clear();
    try {
      await FirebaseMessagingService.instance()
          .unregisterCurrentTokenFromBackend();
    } finally {
      await AuthTokenService.clearToken();
      await MobileCacheService.clear();
      ManagerNotificationInbox.resetSession();
    }
  }

  static String errorMessage(MobileAuthError error) {
    switch (error) {
      case MobileAuthError.invalidPin:
        return 'არასწორი რესტორნის კოდი ან PIN';
      case MobileAuthError.networkError:
        return 'სერვერთან კავშირი ვერ დამყარდა';
      case MobileAuthError.serverError:
        return 'სერვერის შეცდომა. სცადეთ ახლავე.';
      case MobileAuthError.accessDenied:
        return 'წვდომა აკრძალულია.';
      case MobileAuthError.rateLimited:
        return 'შესვლის მცდელობები დროებით შეზღუდულია. სცადეთ მოგვიანებით.';
      case MobileAuthError.sessionStorageError:
        return 'შესვლის მონაცემების შენახვა ვერ მოხერხდა. სცადეთ ხელახლა.';
    }
  }
}

class OfflineAuthResult {
  final String username;
  final String role;
  final bool isStale;

  const OfflineAuthResult({
    required this.username,
    required this.role,
    required this.isStale,
  });
}
