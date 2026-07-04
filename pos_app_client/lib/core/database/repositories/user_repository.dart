import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';

import '../database_core.dart';

/// Staff accounts: PIN authentication, roles, and user CRUD.
class UserRepository {
  UserRepository._();

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

  // Create default manager user
  static Future<void> createDefaultAdmin() async {
    final manager = User(
      username: 'vaanskii',
      pinCode: '000000',
      role: 'manager',
    );
    await DatabaseCore.userBox!.add(manager);
  }

  // Add a new user
  static Future<bool> addUser({
    required String username,
    required String pinCode,
    required String role,
  }) async {
    // Check if PIN code already exists
    if (isPinCodeExists(pinCode)) {
      return false; // PIN code must be unique
    }

    final user = User(username: username, pinCode: pinCode, role: role);

    await DatabaseCore.userBox!.add(user);
    _notifyUsersChanged();
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
        (user) => user.pinCode == pinCode,
      );
    } catch (e) {
      return null; // User not found
    }
  }

  // Get all users
  static List<User> getAllUsers() {
    return DatabaseCore.userBox!.values.toList();
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
    return true;
  }

  static Future<bool> updateUserPinByUsername({
    required String username,
    required String pinCode,
  }) async {
    final user = getUserByUsername(username);
    if (user == null) return false;
    final pinUsedByAnother = DatabaseCore.userBox!.values.any(
      (u) => u.username != username && u.pinCode == pinCode,
    );
    if (pinUsedByAnother) return false;
    user.pinCode = pinCode;
    await user.save();
    _notifyUsersChanged();
    return true;
  }

  static Future<bool> updateUserRoleByUsername({
    required String username,
    required String role,
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

    user.role = normalizedRole;
    await user.save();
    _notifyUsersChanged();
    return true;
  }

  // Delete user
  static Future<void> deleteUser(User user) async {
    await user.delete();
    _notifyUsersChanged();
  }

  static Future<bool> deleteUserByUsername(String username) async {
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
    await user.delete();
    _notifyUsersChanged();
    return true;
  }
}
