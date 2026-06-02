import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vynic/core/services/api_config.dart';
import 'package:vynic/core/services/auth_token_service.dart';
import 'package:vynic/core/services/firebase_messaging_service.dart';
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

enum MobileAuthError { invalidPin, networkError, serverError, accessDenied }

/// Authenticates the manager against the backend (/auth/mobile-login).
/// Falls back to cached token for offline access.
class MobileAuthService {
  /// Attempt to authenticate with the backend.
  /// Returns a [MobileLoginResult] on success.
  /// Throws a [MobileAuthError] on failure.
  static Future<MobileLoginResult> login(String pin) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/auth/mobile-login');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pin': pin}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
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

        // Persist token
        await AuthTokenService.saveToken(
          token: result.accessToken,
          role: result.role,
          username: result.username,
          expiresInSeconds: result.expiresIn,
        );
        await FirebaseMessagingService.instance().syncCurrentTokenWithBackend();

        return result;
      } else if (response.statusCode == 401) {
        throw MobileAuthError.invalidPin;
      } else {
        throw MobileAuthError.serverError;
      }
    } on MobileAuthError {
      rethrow;
    } catch (e) {
      debugPrint(
        '[MobileAuth] Network error (${ApiConfig.baseUrl}): $e',
      );
      throw MobileAuthError.networkError;
    }
  }

  /// Try to use a cached token for offline access.
  /// Returns the username from the token if valid (or stale within grace period).
  static OfflineAuthResult? tryOfflineAccess() {
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
    await FirebaseMessagingService.instance().unregisterCurrentTokenFromBackend();
    await AuthTokenService.clearToken();
  }

  static String errorMessage(MobileAuthError error) {
    switch (error) {
      case MobileAuthError.invalidPin:
        return 'არასწორი PIN კოდი';
      case MobileAuthError.networkError:
        return 'სერვერთან კავშირი ვერ დამყარდა';
      case MobileAuthError.serverError:
        return 'სერვერის შეცდომა. სცადეთ ახლავე.';
      case MobileAuthError.accessDenied:
        return 'წვდომა აკრძალულია.';
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
