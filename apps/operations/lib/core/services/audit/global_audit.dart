import 'package:vynic/core/database/repositories/business_day_repository.dart';
import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/services/audit/audit_event_service.dart';

/// The kinds of thing a venue-wide audit row can be about.
///
/// An Order has its own report and its own ordered timeline; everything else a
/// restaurant does to itself — hiring, pricing, packages, expenses, closing the
/// day, restoring a backup — has no such container, so the generic log is where
/// it lives and this is what identifies its subject.
///
/// Deliberately small: a value earns a place here only when an action actually
/// written by this codebase is about that kind of thing.
abstract final class GlobalAuditEntity {
  static const String staff = 'STAFF';
  static const String menuItem = 'MENU_ITEM';
  static const String menuCategory = 'MENU_CATEGORY';
  static const String menuVariant = 'MENU_VARIANT';
  static const String package = 'PACKAGE';
  static const String expense = 'EXPENSE';
  static const String closeDay = 'CLOSE_DAY';
  static const String backup = 'BACKUP';
  static const String reservation = 'RESERVATION';
  static const String order = 'ORDER';
  static const String sale = 'SALE';
  static const String businessDate = 'BUSINESS_DATE';
  static const String settings = 'SETTINGS';
  static const String developer = 'DEVELOPER';

  static const List<String> all = [
    staff,
    menuItem,
    menuCategory,
    menuVariant,
    package,
    expense,
    closeDay,
    backup,
    reservation,
    order,
    sale,
    businessDate,
    settings,
    developer,
  ];
}

/// The venue-wide action names this phase adds.
///
/// Constants rather than literals for the same reason `MoneyAuditAction` is:
/// the reader groups by `action`, and a typo silently creates a second,
/// invisible category nobody will ever filter for.
abstract final class GlobalAuditAction {
  // Staff. A PIN is a credential, so the log records that one changed and
  // never what it changed to — see [staffPinChanged].
  static const String staffCreated = 'STAFF_CREATED';
  static const String staffUpdated = 'STAFF_UPDATED';
  static const String staffRoleChanged = 'STAFF_ROLE_CHANGED';
  static const String staffPinChanged = 'STAFF_PIN_CHANGED';
  static const String staffDeleted = 'STAFF_DELETED';

  // Menu. A subcategory is a category node, distinguished by `nodeKind` in the
  // details rather than by three more action names.
  static const String menuItemCreated = 'MENU_ITEM_CREATED';
  static const String menuItemUpdated = 'MENU_ITEM_UPDATED';
  static const String menuItemDeleted = 'MENU_ITEM_DELETED';
  static const String menuCategoryCreated = 'MENU_CATEGORY_CREATED';
  static const String menuCategoryUpdated = 'MENU_CATEGORY_UPDATED';
  static const String menuCategoryDeleted = 'MENU_CATEGORY_DELETED';
  static const String menuVariantCreated = 'MENU_VARIANT_CREATED';
  static const String menuVariantUpdated = 'MENU_VARIANT_UPDATED';
  static const String menuVariantDeleted = 'MENU_VARIANT_DELETED';

  // Package definitions. Applying a package to an Order is `APPLY_PACKAGE` on
  // that Order's report and is deliberately not duplicated here.
  static const String packageCreated = 'PACKAGE_CREATED';
  static const String packageUpdated = 'PACKAGE_UPDATED';
  static const String packageDeleted = 'PACKAGE_DELETED';

  static const String expenseCreated = 'EXPENSE_CREATED';

  static const String closeDayCompleted = 'CLOSE_DAY_COMPLETED';
  static const String closeDayBlocked = 'CLOSE_DAY_BLOCKED';

  /// A data backup restored over this terminal's stores. Not `RESTORE` (which
  /// reopens a closed Order) and not `SYSTEM_RECOVERY` (which finishes an
  /// interrupted closure). Three different things; three different names.
  static const String backupRestored = 'BACKUP_RESTORED';
}

/// Writes the venue-wide audit log.
///
/// One entry point, so every domain describes what happened with the same
/// fields: who (`actorId`/`actorName`), through what (`source`), on which
/// business date, and — through the row's own `entityType`/`entityId` — about
/// what.
abstract final class GlobalAudit {
  /// Never throws. An audit row that cannot be written must not undo the
  /// business change it describes; `AuditEventService.logEvent` already
  /// swallows and reports its own storage failures.
  static Future<void> log({
    required String action,
    required String entityType,
    String? entityId,
    required String actorId,
    String? actorName,
    required AuditSource source,
    Map<String, dynamic> data = const {},
  }) async {
    final actor = actorId.trim().isEmpty ? 'unknown' : actorId.trim();
    final name = (actorName == null || actorName.trim().isEmpty)
        ? actor
        : actorName.trim();
    await AuditEventService.logEvent(
      action: action,
      userId: actor,
      entityType: entityType,
      entityId: entityId?.trim().isEmpty == true ? null : entityId?.trim(),
      data: <String, dynamic>{
        'actorId': actor,
        'actorName': name,
        AuditSource.detailsKey: source.wireValue,
        'businessDate': _businessDate(),
        ...data,
      },
    );
  }

  /// One field that moved, in the shape every reader renders as
  /// `previous -> new`.
  static Map<String, dynamic> change({
    required String field,
    Object? previousValue,
    Object? newValue,
  }) => <String, dynamic>{
    'field': field,
    'previousValue': previousValue,
    'newValue': newValue,
  };

  // ── Staff ────────────────────────────────────────────────────────────────

  static Future<void> staffCreated({
    required String username,
    required String role,
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => log(
    action: GlobalAuditAction.staffCreated,
    entityType: GlobalAuditEntity.staff,
    entityId: username,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{'staffName': username, 'role': role},
  );

  static Future<void> staffRenamed({
    required String previousUsername,
    required String newUsername,
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => log(
    action: GlobalAuditAction.staffUpdated,
    entityType: GlobalAuditEntity.staff,
    // The row is about the member as they are now; the old name is the change.
    entityId: newUsername,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'staffName': newUsername,
      ...change(
        field: 'username',
        previousValue: previousUsername,
        newValue: newUsername,
      ),
    },
  );

  static Future<void> staffRoleChanged({
    required String username,
    required String previousRole,
    required String newRole,
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => log(
    action: GlobalAuditAction.staffRoleChanged,
    entityType: GlobalAuditEntity.staff,
    entityId: username,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'staffName': username,
      ...change(
        field: 'role',
        previousValue: previousRole,
        newValue: newRole,
      ),
    },
  );

  /// A PIN change records **that** it happened and nothing else.
  ///
  /// There is no `previousValue`/`newValue` here on purpose: the audit log
  /// syncs to Cloud and is read by managers, and a credential written into it
  /// would be a credential leak wearing an accountability costume.
  static Future<void> staffPinChanged({
    required String username,
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => log(
    action: GlobalAuditAction.staffPinChanged,
    entityType: GlobalAuditEntity.staff,
    entityId: username,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'staffName': username,
      'field': 'pin',
      'changed': true,
    },
  );

  static Future<void> staffDeleted({
    required String username,
    required String role,
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => log(
    action: GlobalAuditAction.staffDeleted,
    entityType: GlobalAuditEntity.staff,
    entityId: username,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{'staffName': username, 'role': role},
  );

  // ── Menu ─────────────────────────────────────────────────────────────────

  /// A menu item created, edited or removed.
  ///
  /// [changes] carries the fields that actually moved — price, availability,
  /// kitchen routing — so "who changed this price" is answerable without
  /// storing a snapshot of the whole menu on every small edit.
  static Future<void> menuItem({
    required String action,
    required String itemId,
    required String itemName,
    String? categoryName,
    List<Map<String, dynamic>> changes = const [],
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
    Map<String, dynamic> extra = const {},
  }) => log(
    action: action,
    entityType: GlobalAuditEntity.menuItem,
    entityId: itemId,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'itemName': itemName,
      if (categoryName != null && categoryName.trim().isNotEmpty)
        'categoryName': categoryName.trim(),
      if (changes.isNotEmpty) 'changes': changes,
      ...extra,
    },
  );

  /// A category or subcategory created, renamed or removed. [nodeKind] is
  /// `CATEGORY` or `SUBCATEGORY`.
  static Future<void> menuCategory({
    required String action,
    required String categoryId,
    required String categoryName,
    String nodeKind = 'CATEGORY',
    String? parentCategoryName,
    List<Map<String, dynamic>> changes = const [],
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
    Map<String, dynamic> extra = const {},
  }) => log(
    action: action,
    entityType: GlobalAuditEntity.menuCategory,
    entityId: categoryId,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'categoryName': categoryName,
      'nodeKind': nodeKind,
      if (parentCategoryName != null && parentCategoryName.trim().isNotEmpty)
        'parentCategoryName': parentCategoryName.trim(),
      if (changes.isNotEmpty) 'changes': changes,
      ...extra,
    },
  );

  static Future<void> menuVariant({
    required String action,
    required String variantId,
    required String itemId,
    required String itemName,
    required double size,
    required double price,
    List<Map<String, dynamic>> changes = const [],
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => log(
    action: action,
    entityType: GlobalAuditEntity.menuVariant,
    entityId: variantId,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'variantId': variantId,
      'itemId': itemId,
      'itemName': itemName,
      'size': size,
      'price': price,
      if (changes.isNotEmpty) 'changes': changes,
    },
  );

  // ── Packages ─────────────────────────────────────────────────────────────

  static Future<void> packageChanged({
    required String action,
    required String packageId,
    required String name,
    double? pricePerPerson,
    bool? isActive,
    List<Map<String, dynamic>> changes = const [],
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => log(
    action: action,
    entityType: GlobalAuditEntity.package,
    entityId: packageId,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'name': name,
      if (pricePerPerson != null) 'pricePerPerson': pricePerPerson,
      if (isActive != null) 'isActive': isActive,
      if (changes.isNotEmpty) 'changes': changes,
    },
  );

  // ── Expenses ─────────────────────────────────────────────────────────────

  static Future<void> expenseCreated({
    required String expenseId,
    required double amount,
    required String category,
    required String description,
    required String paymentType,
    required String businessDate,
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) => log(
    action: GlobalAuditAction.expenseCreated,
    entityType: GlobalAuditEntity.expense,
    entityId: expenseId,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'expenseId': expenseId,
      'amount': amount,
      'category': category,
      'description': description,
      'paymentType': paymentType,
      // The day the expense belongs to, which is not necessarily the day it
      // was entered on.
      'expenseBusinessDate': businessDate,
    },
  );

  // ── Close Day ────────────────────────────────────────────────────────────

  static Future<void> closeDayCompleted({
    required String businessDateClosed,
    required String nextBusinessDate,
    required int reservationsCompleted,
    required int reservationsNoShow,
    required int ordersArchived,
    required int tablesFreed,
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.system,
  }) => log(
    action: GlobalAuditAction.closeDayCompleted,
    entityType: GlobalAuditEntity.closeDay,
    entityId: businessDateClosed,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'businessDateClosed': businessDateClosed,
      'nextBusinessDate': nextBusinessDate,
      'reservationsCompleted': reservationsCompleted,
      'reservationsNoShow': reservationsNoShow,
      'ordersArchived': ordersArchived,
      'tablesFreed': tablesFreed,
    },
  );

  /// A Close Day the POS refused, and what stopped it.
  ///
  /// Written once per genuine attempt that reached the transaction, not per UI
  /// validation keystroke: the operator pressed the button and the day did not
  /// close, which is exactly the thing somebody later asks about.
  static Future<void> closeDayBlocked({
    required String businessDate,
    required String blockedBy,
    required List<Map<String, dynamic>> blockers,
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.system,
  }) => log(
    action: GlobalAuditAction.closeDayBlocked,
    entityType: GlobalAuditEntity.closeDay,
    entityId: businessDate,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      'businessDate': businessDate,
      'blockedBy': blockedBy,
      'blockerCount': blockers.length,
      'blockers': blockers,
    },
  );

  // ── Backup ───────────────────────────────────────────────────────────────

  /// A data backup restored over this terminal.
  ///
  /// Records what was restored and when — never the backup's contents, which
  /// are the whole restaurant and belong in the file, not in a log row.
  static Future<void> backupRestored({
    required String actorId,
    String? actorName,
    AuditSource source = AuditSource.pos,
    String? backupCreatedAt,
    String? backupVersion,
    String? safetyBackupPath,
    bool clearedExisting = true,
    Map<String, dynamic> restoredCounts = const {},
  }) => log(
    action: GlobalAuditAction.backupRestored,
    entityType: GlobalAuditEntity.backup,
    entityId: backupCreatedAt,
    actorId: actorId,
    actorName: actorName,
    source: source,
    data: <String, dynamic>{
      if (backupCreatedAt != null) 'backupCreatedAt': backupCreatedAt,
      if (backupVersion != null) 'backupVersion': backupVersion,
      if (safetyBackupPath != null) 'safetyBackupTaken': true,
      'restoredAt': DateTime.now().toIso8601String(),
      'clearedExisting': clearedExisting,
      if (restoredCounts.isNotEmpty) 'restoredCounts': restoredCounts,
    },
  );

  static String _businessDate() {
    try {
      return BusinessDayRepository.getCurrentDate().toIso8601String().split(
        'T',
      )[0];
    } catch (_) {
      // The business date lives in a Hive box. A restore or a wipe can call an
      // audited path while it is unavailable; that is not a reason to lose the
      // row.
      return DateTime.now().toIso8601String().split('T')[0];
    }
  }
}
