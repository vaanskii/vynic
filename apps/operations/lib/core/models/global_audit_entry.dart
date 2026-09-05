import 'package:vynic/core/models/audit_event_log.dart';
import 'package:vynic/core/services/audit/global_audit.dart';
import 'package:vynic/core/services/audit/global_audit_registry.dart';

/// One field that moved, in the shape every audit writer records it.
class GlobalAuditChange {
  const GlobalAuditChange({
    required this.field,
    this.previousValue,
    this.newValue,
  });

  final String field;
  final Object? previousValue;
  final Object? newValue;

  static List<GlobalAuditChange> fromData(Map<String, dynamic> data) {
    final listed = data['changes'];
    if (listed is List) {
      return [
        for (final entry in listed)
          if (entry is Map)
            GlobalAuditChange(
              field: (entry['field'] ?? '').toString(),
              previousValue: entry['previousValue'],
              newValue: entry['newValue'],
            ),
      ].where((change) => change.field.isNotEmpty).toList(growable: false);
    }
    final field = data['field'];
    if (field is String &&
        field.trim().isNotEmpty &&
        (data.containsKey('previousValue') || data.containsKey('newValue'))) {
      return [
        GlobalAuditChange(
          field: field.trim(),
          previousValue: data['previousValue'],
          newValue: data['newValue'],
        ),
      ];
    }
    // The reservation timeline records a transition rather than a named field.
    if (data['previousStatus'] != null || data['newStatus'] != null) {
      return [
        GlobalAuditChange(
          field: 'status',
          previousValue: data['previousStatus'],
          newValue: data['newStatus'],
        ),
      ];
    }
    return const <GlobalAuditChange>[];
  }
}

/// One row of the venue-wide audit feed, from either side of the sync.
///
/// The POS reads its own Hive rows; the Manager reads the Cloud mirror of the
/// same rows. Both render through this, so the two apps cannot drift into
/// describing the same event differently.
class GlobalAuditEntry {
  const GlobalAuditEntry({
    required this.id,
    required this.action,
    required this.actorId,
    required this.actorName,
    required this.createdAt,
    this.entityType,
    this.entityId,
    this.entityLabel,
    this.source,
    this.businessDate,
    this.deviceType,
    this.changes = const <GlobalAuditChange>[],
    this.data = const <String, dynamic>{},
  });

  final String id;
  final String action;
  final String? entityType;
  final String? entityId;

  /// A human name for the subject, when the row carries one.
  final String? entityLabel;

  final String actorId;
  final String actorName;
  final String? source;
  final String? businessDate;
  final String? deviceType;
  final DateTime createdAt;
  final List<GlobalAuditChange> changes;
  final Map<String, dynamic> data;

  /// A row read from this terminal's own audit box.
  ///
  /// Rows written before entity identity existed carry none, so the entity is
  /// derived from the action and the row's own details — the same derivation
  /// the backend applies, and never a rewrite of the stored row.
  factory GlobalAuditEntry.fromLocal(AuditEventLog log) {
    final data = Map<String, dynamic>.from(log.data);
    final entity = GlobalAuditRegistry.resolve(
      action: log.action,
      data: data,
      storedType: log.entityType,
      storedId: log.entityId,
    );
    return GlobalAuditEntry(
      id: log.id,
      action: log.action,
      entityType: entity?.entityType,
      entityId: entity?.entityId,
      entityLabel: _labelOf(data),
      actorId: log.userId,
      actorName: (data['actorName'] as String?)?.trim().isNotEmpty == true
          ? (data['actorName'] as String).trim()
          : log.userId,
      source: _text(data['source']),
      businessDate: _text(data['businessDate']),
      deviceType: log.deviceType,
      createdAt: log.createdAt,
      changes: GlobalAuditChange.fromData(data),
      data: data,
    );
  }

  /// A row from `GET /mobile/audit-log`, which has already resolved the entity
  /// and normalized the changes server-side.
  factory GlobalAuditEntry.fromCloud(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : <String, dynamic>{};
    final listed = json['changes'];
    final changes = listed is List
        ? [
            for (final entry in listed)
              if (entry is Map)
                GlobalAuditChange(
                  field: (entry['field'] ?? '').toString(),
                  previousValue: entry['previousValue'],
                  newValue: entry['newValue'],
                ),
          ].where((change) => change.field.isNotEmpty).toList(growable: false)
        : GlobalAuditChange.fromData(data);
    final actorId = (json['actorId'] ?? '').toString();
    return GlobalAuditEntry(
      id: (json['id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      entityType: _text(json['entityType']),
      entityId: _text(json['entityId']),
      entityLabel: _text(json['entityLabel']) ?? _labelOf(data),
      actorId: actorId,
      actorName: _text(json['actorName']) ?? actorId,
      source: _text(json['source']),
      businessDate: _text(json['businessDate']),
      deviceType: _text(json['deviceType']),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      changes: changes,
      data: data,
    );
  }

  /// What the row is about, in one line: the subject's name when it has one,
  /// otherwise its id, otherwise nothing.
  String? get subject => entityLabel ?? entityId;

  static String? _labelOf(Map<String, dynamic> data) {
    for (final key in [
      'staffName',
      'itemName',
      'categoryName',
      'name',
      'customerName',
      'description',
    ]) {
      final value = _text(data[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _text(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// How a venue-wide audit row reads to a person.
///
/// Kept out of the widgets so the POS and the Manager say the same words about
/// the same event, and so a new action name has exactly one place to be named.
abstract final class GlobalAuditPresentation {
  static const Map<String, String> _actionLabels = {
    GlobalAuditAction.staffCreated: 'Staff added',
    GlobalAuditAction.staffUpdated: 'Staff updated',
    GlobalAuditAction.staffRoleChanged: 'Staff role changed',
    GlobalAuditAction.staffPinChanged: 'Staff PIN changed',
    GlobalAuditAction.staffDeleted: 'Staff removed',
    GlobalAuditAction.menuItemCreated: 'Menu item added',
    GlobalAuditAction.menuItemUpdated: 'Menu item updated',
    GlobalAuditAction.menuItemDeleted: 'Menu item removed',
    GlobalAuditAction.menuCategoryCreated: 'Menu category added',
    GlobalAuditAction.menuCategoryUpdated: 'Menu category updated',
    GlobalAuditAction.menuCategoryDeleted: 'Menu category removed',
    GlobalAuditAction.menuVariantCreated: 'Menu variant added',
    GlobalAuditAction.menuVariantUpdated: 'Menu variant updated',
    GlobalAuditAction.menuVariantDeleted: 'Menu variant removed',
    GlobalAuditAction.stockItemCreated: 'Stock item added',
    GlobalAuditAction.stockItemUpdated: 'Stock item updated',
    GlobalAuditAction.stockItemDisabled: 'Stock item disabled',
    GlobalAuditAction.supplierCreated: 'Supplier added',
    GlobalAuditAction.supplierUpdated: 'Supplier updated',
    GlobalAuditAction.supplierDisabled: 'Supplier disabled',
    GlobalAuditAction.packageCreated: 'Package created',
    GlobalAuditAction.packageUpdated: 'Package updated',
    GlobalAuditAction.packageDeleted: 'Package deleted',
    GlobalAuditAction.expenseCreated: 'Expense recorded',
    GlobalAuditAction.closeDayCompleted: 'Business day closed',
    GlobalAuditAction.closeDayBlocked: 'Close day blocked',
    GlobalAuditAction.backupRestored: 'Backup restored',
    'ORDER_CREATED': 'Order opened',
    'TAKEAWAY_ORDER_CREATED': 'Takeaway order opened',
    'ORDER_HARD_DELETED': 'Order deleted (repair)',
    'ORDER_DISCOUNT_CHANGED': 'Order discount changed',
    'ORDER_MANUAL_ADJUSTMENT_CHANGED': 'Order adjustment changed',
    'ORDER_SERVICE_FEE_CHANGED': 'Order service fee changed',
    'ADVANCE_RECORDED': 'Advance recorded',
    'SALE_CANCELLED': 'Sale voided',
    'SALE_RESTORED_TO_ORDER': 'Sale restored to order',
    'CLOSURE_RECOVERED': 'Closure recovered',
    'BUSINESS_DATE_CHANGED': 'Business date changed',
    'RECEIPT_SERVICE_FEE_POLICY_CHANGED': 'Receipt fee policy changed',
    'REPORT_COST_ASSUMPTION_CHANGED': 'Report cost assumption changed',
    'CREATE_RESERVATION': 'Reservation created',
    'UPDATE_RESERVATION': 'Reservation updated',
    'CONFIRM_RESERVATION': 'Reservation confirmed',
    'CANCEL_RESERVATION': 'Reservation cancelled',
    'NO_SHOW_RESERVATION': 'Reservation no-show',
    'COMPLETE_RESERVATION': 'Reservation completed',
    'DELETE_RESERVATION': 'Reservation deleted',
  };

  static const Map<String, String> _entityLabels = {
    GlobalAuditEntity.staff: 'Staff',
    GlobalAuditEntity.menuItem: 'Menu item',
    GlobalAuditEntity.menuCategory: 'Menu category',
    GlobalAuditEntity.menuVariant: 'Menu variant',
    GlobalAuditEntity.stockItem: 'Stock item',
    GlobalAuditEntity.supplier: 'Supplier',
    GlobalAuditEntity.package: 'Package',
    GlobalAuditEntity.expense: 'Expense',
    GlobalAuditEntity.closeDay: 'Close day',
    GlobalAuditEntity.backup: 'Backup',
    GlobalAuditEntity.reservation: 'Reservation',
    GlobalAuditEntity.order: 'Order',
    GlobalAuditEntity.sale: 'Sale',
    GlobalAuditEntity.businessDate: 'Business date',
    GlobalAuditEntity.settings: 'Settings',
    GlobalAuditEntity.developer: 'Developer',
  };

  /// The action in words. Falls back to the stored name so an action this
  /// build has never heard of is still shown as itself rather than hidden.
  static String actionLabel(String action) {
    final trimmed = action.trim();
    final known = _actionLabels[trimmed.toUpperCase()];
    if (known != null) return known;
    if (trimmed.startsWith('developer.')) {
      return 'Developer · ${trimmed.substring('developer.'.length)}';
    }
    if (trimmed.toLowerCase() == 'reservation_cancelled') {
      return _actionLabels['CANCEL_RESERVATION']!;
    }
    return trimmed;
  }

  static String entityLabel(String? entityType) =>
      _entityLabels[entityType ?? ''] ?? (entityType ?? '—');

  /// `Price 2.00 → 2.50`, or `Waiter → Admin`, or nothing.
  static String? changeLine(GlobalAuditChange change) {
    final previous = _value(change.previousValue);
    final next = _value(change.newValue);
    final field = _fieldLabel(change.field);
    if (previous == null && next == null) return null;
    if (previous == null) return '$field: $next';
    if (next == null) return '$field: $previous → —';
    return '$field: $previous → $next';
  }

  static String _fieldLabel(String field) {
    switch (field) {
      case 'price':
      case 'pricePerPerson':
        return 'Price';
      case 'role':
        return 'Role';
      case 'username':
        return 'Name';
      case 'status':
        return 'Status';
      case 'sendToKitchen':
        return 'Kitchen routing';
      case 'isActive':
        return 'Active';
      case 'nameEn':
        return 'Name (EN)';
      case 'nameKa':
        return 'Name (KA)';
      case 'manualAdjustment':
        return 'Adjustment';
      case 'serviceFee':
        return 'Service fee';
      default:
        return field;
    }
  }

  static String? _value(Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return raw ? 'yes' : 'no';
    if (raw is num) {
      // Money and percentages read as figures, not as `2.0`.
      return raw is int ? raw.toString() : raw.toStringAsFixed(2);
    }
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }
}
