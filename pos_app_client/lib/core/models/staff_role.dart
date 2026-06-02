/// Staff roles shared by Windows POS (Hive) and manager mobile app.
class StaffRole {
  StaffRole._();

  static const manager = 'manager';
  static const supervisor = 'supervisor';
  static const waiter = 'waiter';

  /// Legacy Hive value — treated as [manager].
  static const legacyAdmin = 'admin';

  static const assignableClientRoles = [manager, supervisor, waiter];

  /// Georgian UI labels.
  static String labelKa(String role) {
    switch (normalizeClient(role)) {
      case manager:
        return 'მენეჯერი';
      case supervisor:
        return 'სუპერვაიზერი';
      case waiter:
      default:
        return 'ოფიციანტი';
    }
  }

  /// API / Prisma enum (uppercase).
  static String labelKaFromApi(String apiRole) =>
      labelKa(fromApi(apiRole));

  static String normalizeClient(String raw) {
    final r = raw.trim().toLowerCase();
    if (r == legacyAdmin || r == manager) return manager;
    if (r == supervisor) return supervisor;
    return waiter;
  }

  static String fromApi(String apiRole) {
    final upper = apiRole.trim().toUpperCase();
    if (upper == 'ADMIN' || upper == 'MANAGER') return manager;
    if (upper == 'SUPERVISOR') return supervisor;
    return waiter;
  }

  static String toApi(String clientRole) {
    switch (normalizeClient(clientRole)) {
      case manager:
        return 'MANAGER';
      case supervisor:
        return 'SUPERVISOR';
      case waiter:
      default:
        return 'WAITER';
    }
  }

  /// მენეჯერის მობილური აპი — მხოლოდ მენეჯერი (არა ზედამხედველი).
  static bool canUseManagerMobileApp(String clientRole) {
    return normalizeClient(clientRole) == manager;
  }

  /// მენიუს დათვლა — სრული მართვა (მართვა, სახელი, წაშლა, რეზერვაცია).
  static bool canManageMenuCountDrafts(String clientRole) {
    final r = normalizeClient(clientRole);
    return r == manager || r == supervisor;
  }

  /// Windows POS მართვის ცენტრი.
  static bool canAccessManagementCenter(String clientRole) {
    final r = normalizeClient(clientRole);
    return r == manager || r == supervisor;
  }

  /// ადმინ პანელი — რეზერვაციის შექმნა (წაშლა/გაუქმება — მენეჯერი).
  static bool canCreateReservationsInAdmin(String clientRole) {
    final r = normalizeClient(clientRole);
    return r == manager || r == supervisor;
  }

  static bool canDeleteReservations(String clientRole) {
    return normalizeClient(clientRole) == manager;
  }

  static bool canCancelReservations(String clientRole) {
    return normalizeClient(clientRole) == manager;
  }

  /// მთავარი ეკრანი — რეზერვაციის სრული მართვა (ოფიციანტი — მენიუს ნახვა + სამზარეულო).
  static bool canManageReservationsOnHome(String clientRole) {
    final r = normalizeClient(clientRole);
    return r == manager || r == supervisor;
  }

  /// მთავარი ეკრანი — რეზერვაციიდან სამზარეულოს ჩეკი (ყველა თანამშრომელი).
  static bool canSendReservationKitchenCheckOnHome(String clientRole) {
    final r = normalizeClient(clientRole);
    return r == manager || r == supervisor || r == waiter;
  }

  /// მაგიდის არაფისკალური დახურვა (შეკვეთის ეკრანი).
  static bool canCloseTablesNonFiscal(String clientRole) {
    final r = normalizeClient(clientRole);
    return r == manager || r == supervisor;
  }

  /// სრული პერსონალის მართვა (ყველა როლი, PIN-ები).
  static bool canManageAllStaffInAdmin(String clientRole) {
    return normalizeClient(clientRole) == manager;
  }

  /// PIN-ის ნახვა ადმინ პანელში (ზედამხედველი — მხოლოდ ოფიციანტი).
  static bool canViewStaffPinInAdmin(String viewerRole, String targetRole) {
    if (canManageAllStaffInAdmin(viewerRole)) return true;
    if (normalizeClient(viewerRole) == supervisor) {
      return normalizeClient(targetRole) == waiter;
    }
    return false;
  }

  /// პერსონალის რედაქტირება/წაშლა ადმინ პანელში.
  static bool canManageStaffUserInAdmin(String viewerRole, String targetRole) {
    if (canManageAllStaffInAdmin(viewerRole)) return true;
    if (normalizeClient(viewerRole) == supervisor) {
      return normalizeClient(targetRole) == waiter;
    }
    return false;
  }

  static bool isMobileApiRole(String apiRole) {
    final upper = apiRole.trim().toUpperCase();
    return upper == 'ADMIN' || upper == 'MANAGER';
  }
}
