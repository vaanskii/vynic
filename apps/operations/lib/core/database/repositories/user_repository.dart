import 'package:flutter/foundation.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/audit/global_audit.dart';

import '../database_core.dart';

/// Staff accounts: PIN authentication, roles, and user CRUD.
class UserRepository {
  UserRepository._();

  /// Attribution for a staff mutation whose caller did not say who made it.
  /// A real name is always preferred; this exists so the audit row is written
  /// even when a path has not been taught to pass one, rather than silently
  /// skipped.
  static const String _unknownActor = 'unknown';

  /// Injected by ManagerSyncService so user/PIN changes sync to the backend.
  static void Function()? _onUsersChanged;
  static void registerUsersChangedCallback(void Function() cb) {
    _onUsersChanged = cb;
  }

  static void _notifyUsersChanged() {
    _onUsersChanged?.call();
  }

  /// Maps legacy Hive `admin` role to `manager`.
  static Future<void> migrateLegacyStaffRoles() async {
    if (DatabaseCore.userBox == null) return;
    for (final user in DatabaseCore.userBox!.values) {
      if (user.role.trim().toLowerCase() == 'admin') {
        user.role = 'manager';
        await user.save();
      }
    }
  }

  /// Development-only bootstrap account for local fixtures and tests.
  /// Release installations receive Manager access through authenticated Edge.
  static const String defaultManagerUsername = 'manager';
  static const String defaultManagerPin = '000000';

  static Future<void> createDefaultAdmin() async {
    // Release installations receive their first Manager through authenticated Edge.
    if (!kDebugMode) return;
    final manager = User(
      username: defaultManagerUsername,
      pinCode: defaultManagerPin,
      role: 'manager',
    );
    await DatabaseCore.userBox!.add(manager);
  }

  // Add a new user
  static Future<bool> addUser({
    required String username,
    required String pinCode,
    required String role,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    // Check if PIN code already exists
    if (getUserByUsername(username) != null || isPinCodeExists(pinCode)) {
      return false; // PIN code must be unique
    }

    final user = User(username: username, pinCode: pinCode, role: role);

    await DatabaseCore.userBox!.add(user);
    _notifyUsersChanged();
    await GlobalAudit.staffCreated(
      username: username,
      role: user.role,
      actorId: actorId,
      actorName: actorName,
      source: source,
    );
    return true;
  }

  // Check if a PIN code already exists
  static bool isPinCodeExists(String pinCode) {
    return DatabaseCore.userBox!.values.any((user) => user.pinCode == pinCode);
  }

  // Authenticate user by PIN code
  static User? authenticateByPin(String pinCode) {
    try {
      return DatabaseCore.userBox!.values.firstWhere(
        (user) => user.pinCode == pinCode && !isPlatformDisabled(user.username),
      );
    } catch (e) {
      return null; // User not found
    }
  }

  static bool isPlatformDisabled(String username) =>
      DatabaseCore.settingsBox?.get('platform_staff_disabled:$username') ==
      true;

  static Future<void> setPlatformAccess(
    String username, {
    required bool disabled,
  }) async {
    final settings = DatabaseCore.settingsBox;
    if (settings == null) throw StateError('Staff access settings unavailable');
    await settings.put('platform_staff_disabled:$username', disabled);
    _notifyUsersChanged();
  }

  // Get all users
  static List<User> getAllUsers() {
    return DatabaseCore.userBox!.values
        .where((user) => !isPlatformDisabled(user.username))
        .toList();
  }

  // Get user by username
  static User? getUserByUsername(String username) {
    try {
      return DatabaseCore.userBox!.values.firstWhere(
        (user) => user.username == username,
      );
    } catch (e) {
      return null;
    }
  }

  static String getDisplayOperatorName(
    String? username, {
    bool isEnglish = false,
  }) {
    final trimmed = (username ?? '').trim();
    if (trimmed.isEmpty) {
      return '-';
    }

    final user = getUserByUsername(trimmed);
    if (user != null && user.isManager) {
      return isEnglish ? 'System' : 'სისტემა';
    }

    final normalized = trimmed.toLowerCase();
    if (normalized == 'admin' ||
        normalized == 'administrator' ||
        normalized == 'superadmin' ||
        normalized == 'manager' ||
        normalized == 'მენეჯერი' ||
        normalized == 'ადმინი' ||
        normalized == 'ადმინისტრატორი') {
      return isEnglish ? 'System' : 'სისტემა';
    }

    return trimmed;
  }

  // Update user
  static Future<void> updateUser(User user) async {
    await user.save();
  }

  static Future<bool> renameUserByUsername({
    required String oldUsername,
    required String newUsername,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    final trimmed = newUsername.trim();
    if (trimmed.isEmpty) return false;

    final user = getUserByUsername(oldUsername);
    if (user == null) return false;

    if (trimmed != oldUsername && getUserByUsername(trimmed) != null) {
      return false;
    }

    user.username = trimmed;
    await user.save();
    _notifyUsersChanged();
    // A rename that renamed nothing is not a change; recording one would
    // assert an edit that never happened.
    if (trimmed != oldUsername) {
      await GlobalAudit.staffRenamed(
        previousUsername: oldUsername,
        newUsername: trimmed,
        actorId: actorId,
        actorName: actorName,
        source: source,
      );
    }
    return true;
  }

  static Future<bool> updateUserPinByUsername({
    required String username,
    required String pinCode,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    final user = getUserByUsername(username);
    if (user == null) return false;
    final pinUsedByAnother = DatabaseCore.userBox!.values.any(
      (u) => u.username != username && u.pinCode == pinCode,
    );
    if (pinUsedByAnother) return false;
    final changed = user.pinCode != pinCode;
    user.pinCode = pinCode;
    await user.save();
    _notifyUsersChanged();
    if (changed) {
      // The audit records that the credential moved. It never records the
      // credential — see GlobalAudit.staffPinChanged.
      await GlobalAudit.staffPinChanged(
        username: user.username,
        actorId: actorId,
        actorName: actorName,
        source: source,
      );
    }
    return true;
  }

  static Future<bool> updateUserRoleByUsername({
    required String username,
    required String role,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    final user = getUserByUsername(username);
    if (user == null) return false;

    final normalizedRole = StaffRole.normalizeClient(role);
    if (user.isManager && normalizedRole != StaffRole.manager) {
      final managerCount = DatabaseCore.userBox!.values
          .where((u) => u.isManager)
          .length;
      if (managerCount <= 1) return false;
    }

    final previousRole = user.role;
    user.role = normalizedRole;
    await user.save();
    _notifyUsersChanged();
    if (previousRole != normalizedRole) {
      await GlobalAudit.staffRoleChanged(
        username: user.username,
        previousRole: previousRole,
        newRole: normalizedRole,
        actorId: actorId,
        actorName: actorName,
        source: source,
      );
    }
    return true;
  }

  // Delete user
  static Future<void> deleteUser(User user) async {
    await user.delete();
    _notifyUsersChanged();
  }

  static Future<bool> deleteUserByUsername(
    String username, {
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    final user = getUserByUsername(username);
    if (user == null) return false;
    if (user.isManager) {
      final activeManagers = DatabaseCore.userBox!.values
          .where((u) => u.isManager)
          .length;
      if (activeManagers <= 1) {
        return false;
      }
    }
    final role = user.role;
    final storedName = user.username;
    await user.delete();
    _notifyUsersChanged();
    await GlobalAudit.staffDeleted(
      username: storedName,
      role: role,
      actorId: actorId,
      actorName: actorName,
      source: source,
    );
    return true;
  }
}
