enum InventoryUnitDimension { mass, volume, count }

enum InventoryUnit {
  kg('kg', InventoryUnitDimension.mass),
  g('g', InventoryUnitDimension.mass),
  liter('L', InventoryUnitDimension.volume),
  ml('ml', InventoryUnitDimension.volume),
  piece('piece', InventoryUnitDimension.count),
  bottle('bottle', InventoryUnitDimension.count),
  pack('pack', InventoryUnitDimension.count),
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
      baseUnitMultiplier:
          _optionalString(json['baseUnitMultiplier']) ?? '0',
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
  });

  final String id;
  final String name;
  final String? sku;
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

  final List<StockItemPurchaseUnit> purchaseUnits;

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
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'sku': sku,
    'baseUnit': baseUnit.wireValue,
    'minimumStock': minimumStock,
    'isActive': isActive,
    'notes': notes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'currentStock': currentStock,
    'stockStatus': stockStatus,
    'purchaseUnits': [
      for (final unit in purchaseUnits) unit.toJson(),
    ],
  };
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.taxId,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  final String id;
  final String name;
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

double? _optionalDouble(Object? raw) {
  if (raw == null || raw == '') return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}

DateTime _date(Object? raw) {
  return DateTime.tryParse(raw?.toString() ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
