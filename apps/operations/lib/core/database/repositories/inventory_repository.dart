import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vynic/core/models/non_fiscal_close_grant.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/models/feature_keys.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/models/inventory.dart';

/// The complete Cloud-owned Inventory projection kept in one Hive box.
///
/// Replacing one `catalog` value avoids a half-new Stock Item list beside an
/// old Supplier list if the process stops during refresh. Local reads never
/// need Cloud and no local code mints or edits business identities.
abstract final class InventoryRepository {
  static const String catalogKey = 'catalog';
  static final featureRevision = ValueNotifier<int>(0);
  static NonFiscalCloseGrant? _nonFiscalGrant;
  static Object? _grantSettings;
  static Timer? _grantExpiry;
  static Future<void> applyRuntimeFeatures(List<String> features) async {
    final wasGranted = hasFeature(FeatureKeys.nonFiscalClose);
    final old = DatabaseCore.settingsBox?.get('runtimeFeatures');
    final device = EdgeDeviceCredentialStore.deviceId;
    final venue = EdgeDeviceCredentialStore.venueId;
    _grantExpiry?.cancel();
    _nonFiscalGrant = null;
    _grantSettings = null;
    try {
      await DatabaseCore.settingsBox!.put('runtimeFeatures', features);
      if (features.contains(FeatureKeys.nonFiscalClose) &&
          device != null &&
          venue != null &&
          EdgeDeviceCredentialStore.credential != null) {
        _nonFiscalGrant = NonFiscalCloseGrant(deviceId: device, venueId: venue);
        _grantSettings = DatabaseCore.settingsBox;
        _grantExpiry = Timer(NonFiscalCloseGrant.lifetime, () {
          _nonFiscalGrant = null;
          featureRevision.value++;
        });
      }
    } finally {
      if (wasGranted != hasFeature(FeatureKeys.nonFiscalClose) ||
          old is! List ||
          !setEquals(old.toSet(), features.toSet())) {
        featureRevision.value++;
      }
    }
  }

  static bool hasFeature(String feature) {
    if (feature == FeatureKeys.nonFiscalClose) {
      return identical(_grantSettings, DatabaseCore.settingsBox) &&
          DatabaseCore.settingsBox?.isOpen == true &&
          EdgeDeviceCredentialStore.hasCredential &&
          DatabaseCore.settingsBox?.get('restoreLegacyIncomplete') != true &&
          (DatabaseCore.settingsBox?.get('runtimeFeatures') is List &&
              (DatabaseCore.settingsBox!.get('runtimeFeatures') as List)
                  .contains(feature)) &&
          _nonFiscalGrant?.allows(
                EdgeDeviceCredentialStore.deviceId,
                EdgeDeviceCredentialStore.venueId,
              ) ==
              true;
    }
    final features =
        DatabaseCore.settingsBox?.get('runtimeFeatures') ??
        _catalog()['features'];
    return features is! List || features.contains(feature);
  }

  static List<StockItem> getStockItems() {
    final raw = _catalog()['stockItems'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => StockItem.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  static List<Supplier> getSuppliers() {
    final raw = _catalog()['suppliers'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Supplier.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  /// The active consumption definitions, as Cloud last projected them.
  ///
  /// Read-only: the POS never authors a recipe, and Step 4 will consume from
  /// these numbers rather than recompute them.
  static List<InventoryRecipe> getRecipes() {
    if (!hasFeature(FeatureKeys.inventory)) return const [];
    final raw = _catalog()['recipes'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => InventoryRecipe.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  static DateTime? get lastRefreshedAt =>
      DateTime.tryParse(_catalog()['generatedAt']?.toString() ?? '')?.toUtc();

  static Future<void> replaceCatalog(Map<String, dynamic> catalog) async {
    final stockItems = (catalog['stockItems'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => StockItem.fromJson(Map<String, dynamic>.from(row)).toJson(),
        )
        .toList(growable: false);
    final suppliers = (catalog['suppliers'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => Supplier.fromJson(Map<String, dynamic>.from(row)).toJson(),
        )
        .toList(growable: false);
    // Absent on a v1/v2 catalog and on a backup written before Step 3. An
    // empty list is the honest answer there; the next Device pull fills it.
    final recipes = (catalog['recipes'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) =>
              InventoryRecipe.fromJson(Map<String, dynamic>.from(row)).toJson(),
        )
        .toList(growable: false);
    final normalized = <String, dynamic>{
      if (catalog['features'] is List)
        'features': List<String>.from(catalog['features'] as List),
      'version': (catalog['version'] as num?)?.toInt() ?? 1,
      'generatedAt':
          DateTime.tryParse(
            catalog['generatedAt']?.toString() ?? '',
          )?.toUtc().toIso8601String() ??
          DateTime.now().toUtc().toIso8601String(),
      'stockItems': stockItems,
      'suppliers': suppliers,
      'recipes': recipes,
      if (catalog['inspection'] is Map)
        'inspection': Map<String, dynamic>.from(catalog['inspection'] as Map),
    };
    await DatabaseCore.inventoryBox!.put(catalogKey, normalized);
    featureRevision.value++;
  }

  static Map<String, dynamic> exportCatalog() =>
      Map<String, dynamic>.from(_catalog());

  static Future<void> restoreCatalog(Object? raw) async {
    if (raw is! Map || raw.isEmpty) return;
    await replaceCatalog(Map<String, dynamic>.from(raw));
  }

  static Map _catalog() {
    final raw = DatabaseCore.inventoryBox?.get(catalogKey);
    return raw is Map ? raw : const {};
  }
}
