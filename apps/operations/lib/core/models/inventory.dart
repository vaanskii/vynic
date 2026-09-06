enum StockItemClassification {
  food('FOOD', 'საკვები / ნედლეული'),
  beverage('BEVERAGE', 'სასმელები');

  const StockItemClassification(this.wireValue, this.label);
  final String wireValue;
  final String label;
  static StockItemClassification parse(Object? value) =>
      value == 'BEVERAGE' ? beverage : food;
}

enum InventoryUnitDimension { mass, volume, count }

enum InventoryUnit {
  kg('kg', InventoryUnitDimension.mass),
  g('g', InventoryUnitDimension.mass),
  liter('L', InventoryUnitDimension.volume),
  ml('ml', InventoryUnitDimension.volume),
  piece('piece', InventoryUnitDimension.count),
  bottle('bottle', InventoryUnitDimension.count),
  pack('pack', InventoryUnitDimension.count),
  keg('keg', InventoryUnitDimension.count),
  box('box', InventoryUnitDimension.count);

  const InventoryUnit(this.wireValue, this.dimension);

  final String wireValue;
  final InventoryUnitDimension dimension;

  static InventoryUnit parse(String raw) {
    return InventoryUnit.values.firstWhere(
      (unit) => unit.wireValue == raw.trim(),
      orElse: () => throw FormatException('Unknown inventory unit: $raw'),
    );
  }
}

double convertInventoryQuantity(
  double value, {
  required InventoryUnit from,
  required InventoryUnit to,
}) {
  if (!value.isFinite) throw ArgumentError.value(value, 'value');
  if (from == to) return value;
  if (from.dimension != to.dimension) {
    throw ArgumentError('Cannot convert ${from.wireValue} to ${to.wireValue}');
  }
  const factors = <InventoryUnit, double>{
    InventoryUnit.kg: 1000,
    InventoryUnit.g: 1,
    InventoryUnit.liter: 1000,
    InventoryUnit.ml: 1,
  };
  final fromFactor = factors[from];
  final toFactor = factors[to];
  if (fromFactor == null || toFactor == null) {
    throw ArgumentError(
      'No global conversion exists between '
      '${from.wireValue} and ${to.wireValue}',
    );
  }
  return value * fromFactor / toFactor;
}

/// One item-specific purchasing package, e.g. "1 box = 24 bottle".
///
/// Cloud-owned like the rest of the catalog; the POS reads it so a later step
/// can speak the same packaging language the Manager entered a waybill in.
class StockItemPurchaseUnit {
  const StockItemPurchaseUnit({
    required this.id,
    required this.unit,
    required this.baseUnitMultiplier,
  });

  final String id;
  final InventoryUnit unit;

  /// Exact ratio text as Cloud stored it. Kept verbatim so a round trip
  /// through this projection never re-rounds a Cloud decimal.
  final String baseUnitMultiplier;

  double get multiplier => double.tryParse(baseUnitMultiplier) ?? 0;

  factory StockItemPurchaseUnit.fromJson(Map<String, dynamic> json) {
    return StockItemPurchaseUnit(
      id: _requiredString(json, 'id'),
      unit: InventoryUnit.parse(_requiredString(json, 'unit')),
      baseUnitMultiplier: _optionalString(json['baseUnitMultiplier']) ?? '0',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'unit': unit.wireValue,
    'baseUnitMultiplier': baseUnitMultiplier,
  };
}

class StockItem {
  const StockItem({
    required this.id,
    required this.name,
    required this.baseUnit,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.sku,
    this.minimumStock,
    this.notes,
    this.currentStock = '0.000',
    this.stockStatus = 'NO_MINIMUM',
    this.purchaseUnits = const <StockItemPurchaseUnit>[],
    this.recipeUnits = const <InventoryUnit>[],
    this.classification = StockItemClassification.food,
    this.supplierIds = const [],
  });

  final String id;
  final String name;
  final String? sku;
  final StockItemClassification classification;
  final List<String> supplierIds;
  final InventoryUnit baseUnit;
  final double? minimumStock;
  final bool isActive;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Cloud's derived balance as exact decimal text.
  ///
  /// Current stock is `SUM(StockMovement.quantityDeltaBase)`, computed in
  /// PostgreSQL where the arithmetic is exact. The POS holds a projection of
  /// that answer and never recomputes or accumulates it locally.
  final String currentStock;

  /// `LOW`, `OK`, or `NO_MINIMUM` when no threshold is configured.
  final String stockStatus;

  bool get isNegativeStock => stockStatus == 'NEGATIVE';

  final List<StockItemPurchaseUnit> purchaseUnits;

  /// The units a recipe may consume this item in, as Cloud decides them.
  ///
  /// Narrower than [purchaseUnits] on purpose: a venue buys lemonade by the
  /// box and serves it by the bottle, so packaging is deliberately not offered
  /// here. Empty on an older catalog; [consumptionUnits] then falls back to the
  /// base unit rather than guessing.
  final List<InventoryUnit> recipeUnits;

  /// What a recipe editor should offer. Never empty.
  List<InventoryUnit> get consumptionUnits =>
      recipeUnits.isEmpty ? <InventoryUnit>[baseUnit] : recipeUnits;

  /// For display and layout only. The durable value stays [currentStock].
  double get currentStockValue => double.tryParse(currentStock) ?? 0;

  /// Cloud's verdict, not a local re-derivation, so the POS and the Manager
  /// never disagree at the threshold boundary.
  bool get isLowStock => stockStatus == 'LOW';

  factory StockItem.fromJson(Map<String, dynamic> json) {
    return StockItem(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      sku: _optionalString(json['sku']),
      classification: StockItemClassification.parse(json['classification']),
      supplierIds: (json['supplierIds'] as List? ?? []).cast<String>(),
      baseUnit: InventoryUnit.parse(_requiredString(json, 'baseUnit')),
      minimumStock: _optionalDouble(json['minimumStock']),
      isActive: json['isActive'] as bool? ?? true,
      notes: _optionalString(json['notes']),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      // A v1 catalog, or a v1 backup, carries neither. Absent reads as an
      // honest zero with no threshold rather than as a fabricated balance.
      currentStock: _optionalString(json['currentStock']) ?? '0.000',
      stockStatus: _optionalString(json['stockStatus']) ?? 'NO_MINIMUM',
      purchaseUnits: (json['purchaseUnits'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                StockItemPurchaseUnit.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
      recipeUnits: _units(json['recipeUnits']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'sku': sku,
    'classification': classification.wireValue,
    'supplierIds': supplierIds,
    'baseUnit': baseUnit.wireValue,
    'minimumStock': minimumStock,
    'isActive': isActive,
    'notes': notes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'currentStock': currentStock,
    'stockStatus': stockStatus,
    'purchaseUnits': [for (final unit in purchaseUnits) unit.toJson()],
    'recipeUnits': [for (final unit in recipeUnits) unit.wireValue],
  };
}

/// One active consumption definition, as the POS caches it offline.
///
/// Read-only, like the rest of the projection: Cloud administers recipes and
/// the POS holds the answer so a later step can consume stock without asking.
/// Both identities travel — the Cloud key that Manager writes address, and the
/// POS's own Menu identity, which is what an offline terminal can match a sold
/// line against.
class InventoryRecipe {
  const InventoryRecipe({
    required this.recipeId,
    required this.revision,
    required this.menuItemId,
    required this.components,
    this.posMenuItemId,
    this.variantId,
    this.posMenuVariantId,
    this.menuItemName = '',
    this.variantLabel,
    this.yieldQuantity = '1.000',
  });

  final String recipeId;

  /// Bumped by Cloud on every saved change, so a later step can record which
  /// definition it consumed by instead of joining today's recipe onto a past
  /// sale.
  final int revision;

  final String menuItemId;
  final String? posMenuItemId;
  final String? variantId;
  final String? posMenuVariantId;
  final String menuItemName;
  final String? variantLabel;
  final String yieldQuantity;
  final List<InventoryRecipeComponent> components;

  factory InventoryRecipe.fromJson(Map<String, dynamic> json) {
    return InventoryRecipe(
      recipeId: _requiredString(json, 'recipeId'),
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      menuItemId: _requiredString(json, 'menuItemId'),
      posMenuItemId: _optionalString(json['posMenuItemId']),
      variantId: _optionalString(json['variantId']),
      posMenuVariantId: _optionalString(json['posMenuVariantId']),
      menuItemName: _optionalString(json['menuItemName']) ?? '',
      variantLabel: _optionalString(json['variantLabel']),
      yieldQuantity: _optionalString(json['yieldQuantity']) ?? '1.000',
      components: (json['components'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => InventoryRecipeComponent.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'recipeId': recipeId,
    'revision': revision,
    'menuItemId': menuItemId,
    'posMenuItemId': posMenuItemId,
    'variantId': variantId,
    'posMenuVariantId': posMenuVariantId,
    'menuItemName': menuItemName,
    'variantLabel': variantLabel,
    'yieldQuantity': yieldQuantity,
    'components': [for (final component in components) component.toJson()],
  };
}

/// What one sold unit consumes of one Stock Item.
class InventoryRecipeComponent {
  const InventoryRecipeComponent({
    required this.stockItemId,
    required this.baseQuantityPerUnit,
    required this.baseUnit,
    this.stockItemName = '',
  });

  final String stockItemId;

  /// Already divided by the recipe yield by Cloud. Exact decimal text, kept
  /// verbatim: the POS never recomputes a consumption quantity.
  final String baseQuantityPerUnit;

  final InventoryUnit baseUnit;
  final String stockItemName;

  factory InventoryRecipeComponent.fromJson(Map<String, dynamic> json) {
    return InventoryRecipeComponent(
      stockItemId: _requiredString(json, 'stockItemId'),
      baseQuantityPerUnit:
          _optionalString(json['baseQuantityPerUnit']) ?? '0.000000',
      baseUnit: InventoryUnit.parse(_requiredString(json, 'baseUnit')),
      stockItemName: _optionalString(json['stockItemName']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'stockItemId': stockItemId,
    'stockItemName': stockItemName,
    'baseQuantityPerUnit': baseQuantityPerUnit,
    'baseUnit': baseUnit.wireValue,
  };
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.stockItemIds = const [],
    this.taxId,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  final String id;
  final String name;
  final List<String> stockItemIds;
  final String? taxId;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      stockItemIds: (json['stockItemIds'] as List? ?? []).cast<String>(),
      taxId: _optionalString(json['taxId']),
      phone: _optionalString(json['phone']),
      email: _optionalString(json['email']),
      address: _optionalString(json['address']),
      notes: _optionalString(json['notes']),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'stockItemIds': stockItemIds,
    'taxId': taxId,
    'phone': phone,
    'email': email,
    'address': address,
    'notes': notes,
    'isActive': isActive,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) throw FormatException('$key is required');
  return value;
}

String? _optionalString(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

/// Unit codes a newer Cloud may extend. An unknown code is dropped rather
/// than crashing the whole catalog decode.
List<InventoryUnit> _units(Object? raw) {
  if (raw is! List) return const <InventoryUnit>[];
  final units = <InventoryUnit>[];
  for (final entry in raw) {
    final value = _optionalString(entry);
    if (value == null) continue;
    try {
      units.add(InventoryUnit.parse(value));
    } on FormatException {
      continue;
    }
  }
  return List<InventoryUnit>.unmodifiable(units);
}

double? _optionalDouble(Object? raw) {
  if (raw == null || raw == '') return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}

DateTime _date(Object? raw) {
  return DateTime.tryParse(raw?.toString() ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
