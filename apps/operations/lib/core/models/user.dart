import 'package:hive/hive.dart';
import 'package:vynic/core/models/staff_role.dart';

part 'user.g.dart';

@HiveType(typeId: 0)
class User extends HiveObject {
  @HiveField(0)
  String username;

  @HiveField(1)
  String pinCode;

  @HiveField(2)
  String role; // manager | supervisor | waiter (legacy: admin → manager)

  User({required this.username, required this.pinCode, required this.role});

  String get normalizedRole => StaffRole.normalizeClient(role);

  bool get isManager => normalizedRole == StaffRole.manager;

  bool get isSupervisor => normalizedRole == StaffRole.supervisor;

  bool get isWaiter => normalizedRole == StaffRole.waiter;

  /// მენეჯერის მობილური აპი — მხოლოდ მენეჯერი.
  bool get canUseManagerMobileApp => StaffRole.canUseManagerMobileApp(role);

  /// Windows POS elevated access (მართვის ცენტრი) — was `admin`; now manager only.
  @Deprecated('Use isManager')
  bool get isAdmin => isManager;

  /// მენიუს დათვლა — სრული მართვა (მართვა, სახელი, წაშლა, რეზერვაცია).
  bool get canManageMenuCountDrafts => StaffRole.canManageMenuCountDrafts(role);

  /// მართვის ცენტრი.
  bool get canAccessManagementCenter =>
      StaffRole.canAccessManagementCenter(role);

  bool get canCreateReservationsInAdmin =>
      StaffRole.canCreateReservationsInAdmin(role);

  bool get canManageReservationsOnHome =>
      StaffRole.canManageReservationsOnHome(role);

  bool get canSendReservationKitchenCheckOnHome =>
      StaffRole.canSendReservationKitchenCheckOnHome(role);

  bool get canCloseTablesNonFiscal => StaffRole.canCloseTablesNonFiscal(role);

  bool get canApplyDiscount => StaffRole.canApplyDiscount(role);

  bool get canAccessXReport => StaffRole.canAccessXReport(role);

  bool get canDeleteReservations => StaffRole.canDeleteReservations(role);

  bool get canCancelReservations => StaffRole.canCancelReservations(role);

  bool get canManageAllStaffInAdmin => StaffRole.canManageAllStaffInAdmin(role);

  bool canViewStaffPinOf(User other) =>
      StaffRole.canViewStaffPinInAdmin(role, other.role);

  bool canManageStaffUser(User other) =>
      StaffRole.canManageStaffUserInAdmin(role, other.role);

  String get roleLabelKa => StaffRole.labelKa(role);
}
