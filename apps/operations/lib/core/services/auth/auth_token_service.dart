import 'package:hive_flutter/hive_flutter.dart';

/// Stores and retrieves the JWT issued by the backend's /auth/mobile-login.
/// Uses a dedicated Hive box so the token survives app restarts.
class AuthTokenService {
  static const _boxName = 'auth_tokens';
  static const _tokenKey = 'access_token';
  static const _roleKey = 'role';
  static const _usernameKey = 'username';
  static const _expiresAtKey = 'expires_at'; // ISO string

  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  static Future<void> saveToken({
    required String token,
    required String role,
    required String username,
    required int expiresInSeconds,
  }) async {
    assert(_box != null, 'AuthTokenService.init() must be called first');
    final expiresAt = DateTime.now()
        .add(Duration(seconds: expiresInSeconds))
        .toIso8601String();
    await Future.wait([
      _box!.put(_tokenKey, token),
      _box!.put(_roleKey, role),
      _box!.put(_usernameKey, username),
      _box!.put(_expiresAtKey, expiresAt),
    ]);
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  static String? get token => _box?.get(_tokenKey) as String?;
  static String? get role => _box?.get(_roleKey) as String?;
  static String? get username => _box?.get(_usernameKey) as String?;

  static bool get hasValidToken {
    final t = token;
    final expiresAtStr = _box?.get(_expiresAtKey) as String?;
    if (t == null || expiresAtStr == null) return false;
    final expiresAt = DateTime.tryParse(expiresAtStr);
    if (expiresAt == null) return false;
    // Allow 60 s clock skew
    return DateTime.now().isBefore(
      expiresAt.subtract(const Duration(seconds: 60)),
    );
  }

  /// Returns true if a token exists but is expired (grace period for offline use).
  /// We allow up to 7 days of stale-token offline access.
  static bool get hasStaleToken {
    final t = token;
    final expiresAtStr = _box?.get(_expiresAtKey) as String?;
    if (t == null || expiresAtStr == null) return false;
    final expiresAt = DateTime.tryParse(expiresAtStr);
    if (expiresAt == null) return false;
    final graceCutoff = expiresAt.add(const Duration(days: 7));
    return DateTime.now().isBefore(graceCutoff);
  }

  static Map<String, String> get authHeader {
    final t = token;
    if (t == null) return {};
    return {'Authorization': 'Bearer $t'};
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  static Future<void> clearToken() async {
    await _box?.deleteAll([_tokenKey, _roleKey, _usernameKey, _expiresAtKey]);
  }
}
