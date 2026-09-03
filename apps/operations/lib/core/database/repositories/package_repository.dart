import 'package:vynic/core/models/package.dart';

import '../database_core.dart';

/// Banquet/event packages (fixed menus priced per person).
class PackageRepository {
  PackageRepository._();

  static PackageItem clonePackageItem(PackageItem item) {
    return PackageItem(
      itemKey: item.itemKey,
      itemName: item.itemName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
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
    return _clonePackage(existing);
  }

  static Future<void> deletePackage(String packageId) async {
    if (DatabaseCore.packageBox == null) {
      return;
    }
    await DatabaseCore.packageBox!.delete(packageId);
  }

  static Future<void> setPackageActive({
    required String packageId,
    required bool isActive,
  }) async {
    if (DatabaseCore.packageBox == null) {
      return;
    }
    final existing = DatabaseCore.packageBox!.get(packageId);
    if (existing == null) {
      return;
    }
    existing.isActive = isActive;
    await existing.save();
  }
}
