import 'package:vynic/core/models/audit_source.dart';
import 'package:vynic/core/models/package.dart';
import 'package:vynic/core/services/audit/global_audit.dart';

import '../database_core.dart';

/// Banquet/event packages (fixed menus priced per person).
class PackageRepository {
  PackageRepository._();

  /// Attribution for a package change whose caller did not say who made it.
  static const String _unknownActor = 'unknown';

  static PackageItem clonePackageItem(PackageItem item) {
    return PackageItem(
      itemKey: item.itemKey,
      itemName: item.itemName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      menuItemId: item.menuItemId,
      variantId: item.variantId,
    );
  }

  static Package _clonePackage(Package package) {
    return Package(
      packageId: package.packageId,
      name: package.name,
      description: package.description,
      items: package.items.map(clonePackageItem).toList(),
      pricePerPerson: package.pricePerPerson,
      isActive: package.isActive,
      createdAt: package.createdAt,
      createdBy: package.createdBy,
      servingSize: package.servingSize,
      allowedTables: List<String>.from(package.allowedTables),
    );
  }

  static List<Package> getAllPackages({bool includeInactive = true}) {
    if (DatabaseCore.packageBox == null) {
      return [];
    }
    final packages = DatabaseCore.packageBox!.values.where(
      (pkg) => includeInactive || pkg.isActive,
    );
    final cloned = packages.map(_clonePackage).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return cloned;
  }

  static Package? getPackageById(String packageId) {
    if (DatabaseCore.packageBox == null) {
      return null;
    }
    final package = DatabaseCore.packageBox!.get(packageId);
    if (package == null) {
      return null;
    }
    return _clonePackage(package);
  }

  static Future<Package> createPackage({
    required String name,
    String? description,
    required List<PackageItem> items,
    required double pricePerPerson,
    required int servingSize,
    required String createdBy,
    List<String>? allowedTables,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    if (DatabaseCore.packageBox == null) {
      throw StateError('Package storage is not initialized');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Package name cannot be empty');
    }
    if (items.isEmpty) {
      throw ArgumentError('Package must include at least one item');
    }
    final normalizedPrice = double.parse(pricePerPerson.toStringAsFixed(2));
    if (normalizedPrice <= 0) {
      throw ArgumentError('Package price must be greater than zero');
    }
    final normalizedServingSize = servingSize;
    if (normalizedServingSize <= 0) {
      throw ArgumentError('Serving size must be greater than zero');
    }
    final normalizedDescription = description?.trim();
    final normalizedAllowedTables = allowedTables == null
        ? <String>[]
        : (allowedTables
              .map((table) => table.trim())
              .where((table) => table.isNotEmpty)
              .toSet()
              .toList()
            ..sort());

    final package = Package.create(
      name: trimmedName,
      description: normalizedDescription?.isEmpty == true
          ? null
          : normalizedDescription,
      items: items.map(clonePackageItem).toList(),
      pricePerPerson: normalizedPrice,
      servingSize: normalizedServingSize,
      createdBy: createdBy,
      allowedTables: normalizedAllowedTables,
    );
    await DatabaseCore.packageBox!.put(package.packageId, package);
    await GlobalAudit.packageChanged(
      action: GlobalAuditAction.packageCreated,
      packageId: package.packageId,
      name: package.name,
      pricePerPerson: package.pricePerPerson,
      isActive: package.isActive,
      actorId: createdBy,
      actorName: actorName,
      source: source,
    );
    return _clonePackage(package);
  }

  static Future<Package> updatePackage({
    required String packageId,
    required String name,
    String? description,
    required List<PackageItem> items,
    required double pricePerPerson,
    required int servingSize,
    bool? isActive,
    List<String>? allowedTables,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    if (DatabaseCore.packageBox == null) {
      throw StateError('Package storage is not initialized');
    }
    final existing = DatabaseCore.packageBox!.get(packageId);
    if (existing == null) {
      throw ArgumentError('Package not found');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Package name cannot be empty');
    }
    if (items.isEmpty) {
      throw ArgumentError('Package must include at least one item');
    }
    final normalizedPrice = double.parse(pricePerPerson.toStringAsFixed(2));
    if (normalizedPrice <= 0) {
      throw ArgumentError('Package price must be greater than zero');
    }
    final normalizedServingSize = servingSize;
    if (normalizedServingSize <= 0) {
      throw ArgumentError('Serving size must be greater than zero');
    }
    final normalizedDescription = description?.trim();

    final normalizedAllowedTables = allowedTables == null
        ? List<String>.from(existing.allowedTables)
        : (allowedTables
              .map((table) => table.trim())
              .where((table) => table.isNotEmpty)
              .toSet()
              .toList()
            ..sort());

    final previousName = existing.name;
    final previousPrice = existing.pricePerPerson;
    final previousServingSize = existing.servingSize;
    final previousActive = existing.isActive;
    final previousItemCount = existing.items.length;
    final previousDescription = existing.description;
    final previousAllowedTables = List<String>.from(existing.allowedTables);

    existing
      ..name = trimmedName
      ..description = normalizedDescription?.isEmpty == true
          ? null
          : normalizedDescription
      ..items = items.map(clonePackageItem).toList()
      ..pricePerPerson = normalizedPrice
      ..servingSize = normalizedServingSize
      ..isActive = isActive ?? existing.isActive
      ..allowedTables = normalizedAllowedTables;
    await existing.save();
    final changes = <Map<String, dynamic>>[
      if (previousName != existing.name)
        GlobalAudit.change(
          field: 'name',
          previousValue: previousName,
          newValue: existing.name,
        ),
      if (previousPrice != existing.pricePerPerson)
        GlobalAudit.change(
          field: 'pricePerPerson',
          previousValue: previousPrice,
          newValue: existing.pricePerPerson,
        ),
      if (previousServingSize != existing.servingSize)
        GlobalAudit.change(
          field: 'servingSize',
          previousValue: previousServingSize,
          newValue: existing.servingSize,
        ),
      if (previousActive != existing.isActive)
        GlobalAudit.change(
          field: 'isActive',
          previousValue: previousActive,
          newValue: existing.isActive,
        ),
      if (previousItemCount != existing.items.length)
        GlobalAudit.change(
          field: 'itemCount',
          previousValue: previousItemCount,
          newValue: existing.items.length,
        ),
      if (previousDescription != existing.description)
        GlobalAudit.change(
          field: 'description',
          previousValue: previousDescription,
          newValue: existing.description,
        ),
      if (!_sameTables(previousAllowedTables, existing.allowedTables))
        GlobalAudit.change(
          field: 'allowedTables',
          previousValue: previousAllowedTables,
          newValue: List<String>.from(existing.allowedTables),
        ),
    ];
    // Re-saving a form that changed nothing is not a configuration change.
    if (changes.isNotEmpty) {
      await GlobalAudit.packageChanged(
        action: GlobalAuditAction.packageUpdated,
        packageId: existing.packageId,
        name: existing.name,
        pricePerPerson: existing.pricePerPerson,
        isActive: existing.isActive,
        changes: changes,
        actorId: actorId,
        actorName: actorName,
        source: source,
      );
    }
    return _clonePackage(existing);
  }

  static Future<void> deletePackage(
    String packageId, {
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    if (DatabaseCore.packageBox == null) {
      return;
    }
    final existing = DatabaseCore.packageBox!.get(packageId);
    await DatabaseCore.packageBox!.delete(packageId);
    // A delete of a package that was not there changed nothing.
    if (existing == null) return;
    await GlobalAudit.packageChanged(
      action: GlobalAuditAction.packageDeleted,
      packageId: packageId,
      name: existing.name,
      pricePerPerson: existing.pricePerPerson,
      isActive: existing.isActive,
      actorId: actorId,
      actorName: actorName,
      source: source,
    );
  }

  static Future<void> setPackageActive({
    required String packageId,
    required bool isActive,
    String actorId = _unknownActor,
    String? actorName,
    AuditSource source = AuditSource.pos,
  }) async {
    if (DatabaseCore.packageBox == null) {
      return;
    }
    final existing = DatabaseCore.packageBox!.get(packageId);
    if (existing == null) {
      return;
    }
    final previousActive = existing.isActive;
    existing.isActive = isActive;
    await existing.save();
    if (previousActive == isActive) return;
    // Enabling and disabling are the same kind of configuration change, told
    // apart by the field that moved rather than by a second action name.
    await GlobalAudit.packageChanged(
      action: GlobalAuditAction.packageUpdated,
      packageId: packageId,
      name: existing.name,
      pricePerPerson: existing.pricePerPerson,
      isActive: isActive,
      changes: <Map<String, dynamic>>[
        GlobalAudit.change(
          field: 'isActive',
          previousValue: previousActive,
          newValue: isActive,
        ),
      ],
      actorId: actorId,
      actorName: actorName,
      source: source,
    );
  }

  /// Whether two allowed-table lists name the same tables. Both are stored
  /// sorted and de-duplicated, so order is content, not noise.
  static bool _sameTables(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
