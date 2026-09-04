import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/money_audit.dart';
import 'package:vynic/core/services/audit/reservation_audit.dart';

/// What kind of thing a venue-wide audit action is about.
///
/// New rows carry `entityType`/`entityId` on themselves, written by
/// [GlobalAudit]. Rows written before those columns existed do not, and this
/// repository does not rewrite history — so this table exists to classify a
/// row from its action name and its own stored details instead.
///
/// The mapping is derivation, never guessing: an action name that is not in
/// this table resolves to no entity rather than to a plausible one.
class GlobalAuditEntityRef {
  const GlobalAuditEntityRef(this.entityType, this.entityId);

  final String entityType;
  final String? entityId;
}

abstract final class GlobalAuditRegistry {
  /// Actions whose subject is an Order.
  static const Set<String> _orderActions = {
    'ORDER_CREATED',
    'TAKEAWAY_ORDER_CREATED',
    'ORDER_HARD_DELETED',
    'ORDER_DISCOUNT_CHANGED',
    MoneyAuditAction.orderManualAdjustmentChanged,
    MoneyAuditAction.orderServiceFeeChanged,
    MoneyAuditAction.advanceRecorded,
    MoneyAuditAction.saleRestoredToOrder,
  };

  static const Set<String> _staffActions = {
    GlobalAuditAction.staffCreated,
    GlobalAuditAction.staffUpdated,
    GlobalAuditAction.staffRoleChanged,
    GlobalAuditAction.staffPinChanged,
    GlobalAuditAction.staffDeleted,
  };

  static const Set<String> _menuItemActions = {
    GlobalAuditAction.menuItemCreated,
    GlobalAuditAction.menuItemUpdated,
    GlobalAuditAction.menuItemDeleted,
  };

  static const Set<String> _menuCategoryActions = {
    GlobalAuditAction.menuCategoryCreated,
    GlobalAuditAction.menuCategoryUpdated,
    GlobalAuditAction.menuCategoryDeleted,
  };

  static const Set<String> _packageActions = {
    GlobalAuditAction.packageCreated,
    GlobalAuditAction.packageUpdated,
    GlobalAuditAction.packageDeleted,
  };

  static const Set<String> _closeDayActions = {
    GlobalAuditAction.closeDayCompleted,
    GlobalAuditAction.closeDayBlocked,
  };

  /// The entity a stored row is about.
  ///
  /// [storedType]/[storedId] are the row's own columns and always win: a
  /// writer that named its subject knows better than this table does. The
  /// derivation is the fallback for everything written before they existed.
  static GlobalAuditEntityRef? resolve({
    required String action,
    Map<String, dynamic> data = const {},
    String? storedType,
    String? storedId,
  }) {
    final declared = _clean(storedType);
    if (declared != null) return GlobalAuditEntityRef(declared, _clean(storedId));

    final trimmed = action.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('developer.')) {
      return const GlobalAuditEntityRef(GlobalAuditEntity.developer, null);
    }

    final reservationAction = ReservationAuditAction.normalize(trimmed);
    if (reservationAction != null) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.reservation,
        _clean(data['reservationId']?.toString()),
      );
    }

    final upper = trimmed.toUpperCase();
    if (_orderActions.contains(upper)) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.order,
        _clean(data['orderId']?.toString()),
      );
    }
    if (upper == MoneyAuditAction.saleCancelled) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.sale,
        _clean(data['saleId']?.toString()) ??
            _clean(data['closureId']?.toString()) ??
            _clean(data['orderId']?.toString()),
      );
    }
    if (upper == MoneyAuditAction.closureRecovered) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.sale,
        _clean(data['closureId']?.toString()),
      );
    }
    if (upper == MoneyAuditAction.businessDateChanged) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.businessDate,
        _clean(data['newDate']?.toString()),
      );
    }
    if (upper == MoneyAuditAction.receiptServiceFeePolicyChanged) {
      return const GlobalAuditEntityRef(
        GlobalAuditEntity.settings,
        'receiptServiceFeePolicy',
      );
    }
    if (upper == MoneyAuditAction.reportCostAssumptionChanged) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.settings,
        _clean(data['field']?.toString()),
      );
    }
    if (_staffActions.contains(upper)) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.staff,
        _clean(data['staffName']?.toString()),
      );
    }
    if (_menuItemActions.contains(upper)) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.menuItem,
        _clean(data['itemId']?.toString()) ??
            _clean(data['itemName']?.toString()),
      );
    }
    if (_menuCategoryActions.contains(upper)) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.menuCategory,
        _clean(data['categoryName']?.toString()),
      );
    }
    if (_packageActions.contains(upper)) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.package,
        _clean(data['packageId']?.toString()),
      );
    }
    if (upper == GlobalAuditAction.expenseCreated) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.expense,
        _clean(data['expenseId']?.toString()),
      );
    }
    if (_closeDayActions.contains(upper)) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.closeDay,
        _clean(data['businessDateClosed']?.toString()) ??
            _clean(data['businessDate']?.toString()),
      );
    }
    if (upper == GlobalAuditAction.backupRestored) {
      return GlobalAuditEntityRef(
        GlobalAuditEntity.backup,
        _clean(data['backupCreatedAt']?.toString()),
      );
    }
    return null;
  }

  static String? _clean(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
