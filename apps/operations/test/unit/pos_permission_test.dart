// Tests for [PosPermissions] — the UI Phase 1 permission foundation
// (docs/UI_PLAN.md §4.4). Locks in the role → permission mapping so future
// UI phases can rely on `PosPermissions.has(user, ...)` without re-deriving
// which roles get which controls.

import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/models/pos_permission.dart';
import 'package:vynic/core/models/staff_role.dart';
import 'package:vynic/core/models/user.dart';

void main() {
  final waiter = User(
    username: 'w1',
    pinCode: '111111',
    role: StaffRole.waiter,
  );
  final supervisor = User(
    username: 's1',
    pinCode: '222222',
    role: StaffRole.supervisor,
  );
  final manager = User(
    username: 'm1',
    pinCode: '333333',
    role: StaffRole.manager,
  );

  group('PosPermissions.has — applyDiscount', () {
    test('waiter is denied', () {
      expect(PosPermissions.has(waiter, PosPermission.applyDiscount), isFalse);
    });

    test('supervisor and manager are allowed', () {
      expect(
        PosPermissions.has(supervisor, PosPermission.applyDiscount),
        isTrue,
      );
      expect(PosPermissions.has(manager, PosPermission.applyDiscount), isTrue);
    });
  });

  group('PosPermissions.has — viewReports (X-report)', () {
    test('waiter is denied', () {
      expect(PosPermissions.has(waiter, PosPermission.viewReports), isFalse);
    });

    test('supervisor and manager are allowed', () {
      expect(PosPermissions.has(supervisor, PosPermission.viewReports), isTrue);
      expect(PosPermissions.has(manager, PosPermission.viewReports), isTrue);
    });
  });

  group('PosPermissions.has — manager-only actions', () {
    const managerOnly = [
      PosPermission.voidOrder,
      PosPermission.refundPayment,
      PosPermission.viewSales,
      PosPermission.manageMenu,
      PosPermission.managePrinters,
      PosPermission.overrideManagerApproval,
      PosPermission.deleteOrder,
      PosPermission.editClosedOrder,
    ];

    test('waiter and supervisor are denied', () {
      for (final permission in managerOnly) {
        expect(
          PosPermissions.has(waiter, permission),
          isFalse,
          reason: 'waiter should not have $permission',
        );
        expect(
          PosPermissions.has(supervisor, permission),
          isFalse,
          reason: 'supervisor should not have $permission',
        );
      }
    });

    test('manager is allowed', () {
      for (final permission in managerOnly) {
        expect(
          PosPermissions.has(manager, permission),
          isTrue,
          reason: 'manager should have $permission',
        );
      }
    });
  });

  group('PosPermissions.has — supervisor+manager actions', () {
    const supervisorAndManager = [
      PosPermission.closeDay,
      PosPermission.manageStaff,
      PosPermission.openAdmin,
    ];

    test('waiter is denied', () {
      for (final permission in supervisorAndManager) {
        expect(
          PosPermissions.has(waiter, permission),
          isFalse,
          reason: 'waiter should not have $permission',
        );
      }
    });

    test('supervisor and manager are allowed', () {
      for (final permission in supervisorAndManager) {
        expect(
          PosPermissions.has(supervisor, permission),
          isTrue,
          reason: 'supervisor should have $permission',
        );
        expect(
          PosPermissions.has(manager, permission),
          isTrue,
          reason: 'manager should have $permission',
        );
      }
    });
  });

  group('PosPermissions.has — universal actions (everyday waiter ops)', () {
    const universal = [
      PosPermission.closeTable,
      PosPermission.reprintReceipt,
      PosPermission.changeTable,
    ];

    test('every role is allowed, including waiter', () {
      for (final permission in universal) {
        expect(
          PosPermissions.has(waiter, permission),
          isTrue,
          reason: 'waiter must keep $permission — everyday operation',
        );
        expect(PosPermissions.has(supervisor, permission), isTrue);
        expect(PosPermissions.has(manager, permission), isTrue);
      }
    });
  });

  group('StaffRole.canApplyDiscount / canAccessXReport', () {
    test('normalize legacy admin value to manager-level access', () {
      expect(StaffRole.canApplyDiscount(StaffRole.legacyAdmin), isTrue);
      expect(StaffRole.canAccessXReport(StaffRole.legacyAdmin), isTrue);
    });

    test('unknown role strings fall back to waiter (denied)', () {
      expect(StaffRole.canApplyDiscount('made-up-role'), isFalse);
      expect(StaffRole.canAccessXReport('made-up-role'), isFalse);
    });
  });

  group('User.canApplyDiscount / User.canAccessXReport', () {
    test('wired through to StaffRole', () {
      expect(waiter.canApplyDiscount, isFalse);
      expect(supervisor.canApplyDiscount, isTrue);
      expect(manager.canApplyDiscount, isTrue);

      expect(waiter.canAccessXReport, isFalse);
      expect(supervisor.canAccessXReport, isTrue);
      expect(manager.canAccessXReport, isTrue);
    });
  });
}
