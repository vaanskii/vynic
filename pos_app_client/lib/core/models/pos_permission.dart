import 'package:vynic/core/models/user.dart';

/// Central catalogue of gate-able POS actions, per docs/UI_PLAN.md §4.4.
///
/// This is a lookup facade over the boolean checks already defined on
/// [User]/`StaffRole` — it does not replace them. UI code that wants a
/// single, memorable name to check before showing/hiding/disabling a
/// control should prefer `PosPermissions.has(user, ...)`. Per-target checks
/// that compare two users (e.g. `User.canManageStaffUser`) stay as they are
/// — a flat enum can't express a two-user relationship.
enum PosPermission {
  applyDiscount,
  voidOrder,
  refundPayment,
  closeTable,
  closeDay,
  viewReports,
  viewSales,
  manageMenu,
  manageStaff,
  managePrinters,
  openAdmin,
  overrideManagerApproval,
  reprintReceipt,
  changeTable,
  deleteOrder,
  editClosedOrder,
}

class PosPermissions {
  PosPermissions._();

  static bool has(User user, PosPermission permission) {
    switch (permission) {
      case PosPermission.applyDiscount:
        return user.canApplyDiscount;

      case PosPermission.voidOrder:
        // Order-level cancellation is already UI-gated to managers only
        // (order_detail_action_helpers.dart) and separately protected by a
        // shared destructive-action password. There is no line-item void
        // yet (docs/UI_PLAN.md §5) — this is the permission hook for that
        // future workflow.
        return user.isManager;

      case PosPermission.refundPayment:
        // No refund action exists anywhere in the app yet
        // (docs/UI_PLAN.md §5 — reporting field only). Scaffolded ahead of
        // its consumer, the same way PrintOperationalStatus was scaffolded
        // in Phase 4.
        return user.isManager;

      case PosPermission.closeTable:
        // Everyday fiscal close (take payment, close the table) is a
        // routine waiter operation today and must stay open to every role —
        // see docs/UI_PLAN.md §4.4 and the standing "do not block normal
        // waiter operations" constraint. The separate, already-gated
        // *non-fiscal* close ("no sale") stays manager-only via the
        // existing `User.canCloseTablesNonFiscal` — unaffected by this.
        return true;

      case PosPermission.closeDay:
        return user.canAccessManagementCenter;

      case PosPermission.viewReports:
        return user.canAccessXReport;

      case PosPermission.viewSales:
        // Admin "sales" / "salesReport" / "audit" sections are already
        // unreachable for supervisors — they're absent from the limited
        // admin sidebar in admin_screen.dart. Manager-only.
        return user.isManager;

      case PosPermission.manageMenu:
        return user.isManager;

      case PosPermission.manageStaff:
        // Coarse "can enter the staff section" check. Per-target
        // mutations keep using the existing fine-grained
        // `User.canManageStaffUser` / `User.canManageAllStaffInAdmin` —
        // do not replace those with this.
        return user.canAccessManagementCenter;

      case PosPermission.managePrinters:
        return user.isManager;

      case PosPermission.openAdmin:
        return user.canAccessManagementCenter;

      case PosPermission.overrideManagerApproval:
        return user.isManager;

      case PosPermission.reprintReceipt:
        return true;

      case PosPermission.changeTable:
        return true;

      case PosPermission.deleteOrder:
        // Alias of voidOrder until a distinct delete-vs-cancel workflow
        // exists — docs/UI_PLAN.md §5 lists no such split today.
        return user.isManager;

      case PosPermission.editClosedOrder:
        // No such workflow exists yet — scaffold only.
        return user.isManager;
    }
  }
}
